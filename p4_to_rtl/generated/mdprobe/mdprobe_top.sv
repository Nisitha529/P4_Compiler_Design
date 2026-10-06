module mdprobe_top #(
    parameter int AXI_DATA_W  = 256,
    parameter int AXIL_ADDR_W = 16
) (
    input  logic clk,
    input  logic rst_n,

    // AXI4-Stream slave — packet in
    input  logic [AXI_DATA_W-1:0]    s_axis_tdata,
    input  logic [AXI_DATA_W/8-1:0]  s_axis_tkeep,
    input  logic                      s_axis_tvalid,
    output logic                      s_axis_tready,
    input  logic                      s_axis_tlast,

    // AXI4-Stream master — packet out
    output logic [AXI_DATA_W-1:0]    m_axis_tdata,
    output logic [AXI_DATA_W/8-1:0]  m_axis_tkeep,
    output logic                      m_axis_tvalid,
    input  logic                      m_axis_tready,
    output logic                      m_axis_tlast,

    // AXI4-Lite slave — table control plane
    input  logic [AXIL_ADDR_W-1:0]   s_axil_awaddr,
    input  logic                      s_axil_awvalid,
    output logic                      s_axil_awready,
    input  logic [31:0]               s_axil_wdata,
    input  logic [3:0]                s_axil_wstrb,
    input  logic                      s_axil_wvalid,
    output logic                      s_axil_wready,
    output logic [1:0]                s_axil_bresp,
    output logic                      s_axil_bvalid,
    input  logic                      s_axil_bready,
    input  logic [AXIL_ADDR_W-1:0]   s_axil_araddr,
    input  logic                      s_axil_arvalid,
    output logic                      s_axil_arready,
    output logic [31:0]               s_axil_rdata,
    output logic [1:0]                s_axil_rresp,
    output logic                      s_axil_rvalid,
    input  logic                      s_axil_rready,

    // Metadata sideband (valid while m_axis_tvalid for the packet)
    output logic [7:0] out_meta_colour,
    output logic [15:0] out_meta_midx,
    output logic [8:0] out_std_meta_egress_port
);

  localparam int BEAT_BYTES    = AXI_DATA_W / 8;  // 32
  localparam int MAX_PKT_BEATS = 256;
  localparam int MAX_PKT_BYTES = MAX_PKT_BEATS * BEAT_BYTES;  // 8192
  localparam int HDR_MAX_BYTES = 32;
  localparam int HDR_MAX_BEATS = 1;
  localparam int PAYLOAD_MAX_BYTES = MAX_PKT_BYTES - HDR_MAX_BYTES;  // 8160
  localparam int PAYLOAD_MAX_BEATS = PAYLOAD_MAX_BYTES / BEAT_BYTES;  // 255

  // ── Header slot ring ─────────────────────────────────────────────────────
  // NSLOT packets can be in flight at once. Each slot holds one packet's
  // header region (HDR_MAX_BYTES) as received, its per-row keep, its beat
  // count / done / overflow, and -- once the pipeline has finished with it --
  // the pipeline's output PHV, drop decision and metadata. Four pointers
  // walk the ring in order and never overtake each other:
  //   wr_ptr  : RX fills this slot          (advances on tlast)
  //   iss_ptr : next slot to issue to u_proc (advances on issue)
  //   cmp_ptr : next slot expecting a result (advances on out_valid)
  //   tx_ptr  : TX drains this slot         (advances on last beat / discard)
  // Each carries one extra bit so "full" and "empty" are distinguishable.
  // Payload beats do not live in slots: they stream through u_pfifo in
  // arrival order, and since every stage is in-order, the head of the FIFO
  // is always the first payload beat of the slot TX is on.
  localparam int NSLOT   = 4;
  localparam int SLOT_AW = 2;
  logic [7:0] slot_hdr [0:NSLOT*HDR_MAX_BYTES-1];
  logic [AXI_DATA_W/8-1:0] slot_keep [0:NSLOT*HDR_MAX_BEATS-1];
  logic [8:0] slot_beat_cnt [0:NSLOT-1];
  logic slot_done     [0:NSLOT-1];
  logic slot_overflow [0:NSLOT-1];
  logic [8:0] slot_std_meta_egress_port [0:NSLOT-1];
  logic slot_drop     [0:NSLOT-1];
  logic slot_txdone   [0:NSLOT-1];   // TX has sent (or discarded) this slot
  logic tx_finish;    // driven in the TX section; read here to set slot_txdone
  logic slot_release; // likewise: the payload buffers below clear on it
  `ifndef SYNTHESIS
  // synthesis translate_off
  initial begin
    for (int i = 0; i < NSLOT*HDR_MAX_BYTES; i++) slot_hdr[i] = 8'd0;
  end
  // synthesis translate_on
  `endif
  logic [SLOT_AW:0] wr_ptr, iss_ptr, rel_ptr;
  logic [SLOT_AW:0] cmp_ptr;   // no egress stage: completion is issue order
  wire  [SLOT_AW-1:0] wr_slot  = wr_ptr[SLOT_AW-1:0];
  wire  [SLOT_AW-1:0] iss_slot = iss_ptr[SLOT_AW-1:0];
  wire  [SLOT_AW-1:0] rel_slot = rel_ptr[SLOT_AW-1:0];

  // ── Traffic manager: per-queue slot FIFOs ────────────────────────────────
  // (this program has no egress control, so the scheduler degenerates:
  //  ingress completion feeds the transmit queue directly)
  logic [SLOT_AW-1:0] txq_mem [0:NSLOT-1];
  logic [SLOT_AW:0]   txq_wr, txq_rd;
  logic [SLOT_AW-1:0] cmp_slot;   // slot leaving the pipeline this cycle
  logic [SLOT_AW-1:0] tx_slot;    // slot TX is sending
  always_comb begin
    cmp_slot = cmp_ptr[SLOT_AW-1:0];
    tx_slot  = txq_mem[txq_rd[SLOT_AW-1:0]];
  end
  // rel_ptr: RELEASE pointer, trails tx_ptr. TX moving on (tx_ptr) and the
  // slot being reusable are different events: on an OVERSIZE packet the
  // FIFO entry marked last is pushed at MAX_PKT_BEATS while the link's real
  // tlast arrives later, so TX can finish while RX is still receiving into
  // the slot. Releasing then wiped the slot under RX and the remaining
  // beats were re-read as a new packet's header rows (deadlocked T8).
  // A slot is released only once its tlast has been seen.
  wire  [SLOT_AW:0] n_alloc  = wr_ptr - rel_ptr;
  wire  rx_slot_free = (n_alloc < NSLOT);

  // Header bytes of the slot being issued to the pipeline -- every w_* field
  // below is extracted from this. (Procedural mux, not continuous assigns
  // from array elements -- see the note at the extraction block.)
  logic [7:0] x_hdr [0:HDR_MAX_BYTES-1];
  always_comb for (int i = 0; i < HDR_MAX_BYTES; i++) x_hdr[i] = slot_hdr[iss_slot*HDR_MAX_BYTES + i];

  localparam int PFIFO_W  = AXI_DATA_W + AXI_DATA_W/8 + 1;  // {last, keep, data}
  localparam int PFIFO_AW = 8;
  localparam int PFIFO_DEPTH = 1 << PFIFO_AW;  // 256 >= PAYLOAD_MAX_BEATS
  logic [NSLOT-1:0]    pfifo_wr_en_v;
  logic [PFIFO_W-1:0]  pfifo_wr_data;   // shared: only slot wr_slot is written
  logic [NSLOT-1:0]    pfifo_full_v;
  logic [NSLOT-1:0]    pfifo_rd_valid_v;
  logic [PFIFO_W-1:0]  pfifo_rd_data_v [0:NSLOT-1];
  logic [NSLOT-1:0]    pfifo_rd_en_v;
  logic [NSLOT-1:0]    pfifo_rewind_v;
  logic [NSLOT-1:0]    pfifo_clear_v;
  genvar gs;
  generate for (gs = 0; gs < NSLOT; gs++) begin : g_pfifo
    pkt_beat_buf #(.W(PFIFO_W), .DEPTH(PFIFO_DEPTH), .AW(PFIFO_AW)) u_pbuf (
      .clk(clk), .rst_n(rst_n),
      .wr_en(pfifo_wr_en_v[gs]), .wr_data(pfifo_wr_data), .full(pfifo_full_v[gs]),
      .rd_valid(pfifo_rd_valid_v[gs]), .rd_data(pfifo_rd_data_v[gs]),
      .rd_en(pfifo_rd_en_v[gs]),
      .rewind(pfifo_rewind_v[gs]), .clear(pfifo_clear_v[gs]),
      .occupancy()
    );
  end endgenerate
  // Views of the slot each side is working on. Unpacked-array elements are
  // read in always_comb, never a continuous assign (iverilog 11 rejects the
  // latter -- the same rule the header extraction section follows).
  logic                pfifo_full;
  logic                pfifo_rd_valid;
  logic [PFIFO_W-1:0]  pfifo_rd_data;
  logic                pfifo_rd_en;
  logic                pfifo_wr_en;
  always_comb begin
    pfifo_full     = pfifo_full_v[wr_slot];
    pfifo_rd_valid = pfifo_rd_valid_v[tx_slot];
    pfifo_rd_data  = pfifo_rd_data_v[tx_slot];
    for (int sl = 0; sl < NSLOT; sl++) begin
      pfifo_wr_en_v[sl]  = pfifo_wr_en && (wr_slot == sl[SLOT_AW-1:0]);
      pfifo_rd_en_v[sl]  = pfifo_rd_en && (tx_slot == sl[SLOT_AW-1:0]);
    end
  end
  wire                  pfifo_head_last = pfifo_rd_data[PFIFO_W-1];
  wire [AXI_DATA_W/8-1:0] pfifo_head_keep = pfifo_rd_data[AXI_DATA_W +: AXI_DATA_W/8];
  wire [AXI_DATA_W-1:0]   pfifo_head_data = pfifo_rd_data[AXI_DATA_W-1:0];

  // ── State registers ──────────────────────────────────────────────────────
  //   iss_fire     : one-cycle valid_in pulse to u_proc for slot iss_slot
  //   proc_out_valid: u_proc's data-ALIGNED valid (out_valid port) -- the
  //                  cycle out_*/drop belong to slot cmp_slot
  //   tx_hdr_row/tx_in_payload: TX progress through slot tx_slot
  logic [8:0] tx_hdr_row;
  logic tx_in_payload;
  logic tx_out_valid;
  logic [255:0] tx_out_data;
  logic [31:0] tx_out_keep;
  logic tx_out_last;

  // ── Header field extraction from pkt_buf ────────────────────────────────
  //    Fields extracted using big-endian (network byte order) bit mapping.

  // eth — base: 0
  logic [47:0] w_eth_dst;
  logic [47:0] w_eth_src;
  logic [15:0] w_eth_etype;
  always_comb begin
    w_eth_dst = {x_hdr[0], x_hdr[1], x_hdr[2], x_hdr[3], x_hdr[4], x_hdr[5]};
    w_eth_src = {x_hdr[6], x_hdr[7], x_hdr[8], x_hdr[9], x_hdr[10], x_hdr[11]};
    w_eth_etype = {x_hdr[12], x_hdr[13]};
  end

  // ── Header validity (derived from extracted fields) ──────────────────────
  wire w_eth_valid = 1'b1;

  // ── Header-region cutoff ──────────────────────────────────────────────────
  wire [13:0] w_eth_cutoff_term = 0 + 14;
  wire [13:0] cutoff_byte = w_eth_cutoff_term;

  // ── processing_generated ─────────────────────────────────────────────────
  //    Signals prefixed proc_out_* are the match-action outputs.

  wire out_eth_valid;
  wire [47:0] out_eth_dst;
  wire [47:0] out_eth_src;
  wire [15:0] out_eth_etype;
  wire proc_valid_out;
  wire proc_out_valid;
  wire proc_drop;
  logic iss_fire;
  wire [7:0] proc_out_meta_colour;
  wire [15:0] proc_out_meta_midx;
  wire [8:0] ig_out_std_meta_egress_port;

  wire fwd_cp_query_busy;
  wire fwd_cp_query_hit;
  wire [0:0] fwd_cp_query_action_id;
  wire [8:0] fwd_cp_query_p_p;


  // ── AXI4-Lite staging registers ─────────────────────────────────────────
  logic [3:0] r_fwd_cp_wr_idx;
  logic [0:0] r_fwd_cp_wr_action;
  logic [47:0] r_fwd_cp_wr_key_dst;
  logic [8:0] r_fwd_cp_wr_p_p;
  logic [47:0] r_fwd_cp_query_key_dst;
  logic r_fwd_cp_query_del;
  logic [4:0] r_rate_limit_cp_rate_shift;
  logic [15:0] r_rate_limit_cp_burst;
  logic r_fwd_cp_wr_en;
  logic r_fwd_cp_query_en;
  logic r_rate_limit_cp_wr_en;
  logic r_seen_src_cp_wr_en;
  // seen_src: 48-bit entries, depth 16, packed in the pipeline
  wire        seen_src_push;
  wire [47:0] seen_src_data;
  logic [47:0] seen_src_fifo [0:15];
  logic [4:0] seen_src_wr, seen_src_rd;
  logic [15:0] seen_src_overflow;
  wire seen_src_full  = ((seen_src_wr - seen_src_rd) == 5'd16);
  wire seen_src_empty = (seen_src_wr == seen_src_rd);
  wire [47:0] seen_src_cp_rd_data = seen_src_fifo[seen_src_rd[3:0]];
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      seen_src_wr <= 5'd0; seen_src_rd <= 5'd0; seen_src_overflow <= 16'd0;
    end else begin
      if (seen_src_push) begin
        if (seen_src_full) seen_src_overflow <= seen_src_overflow + 16'd1;
        else begin
          seen_src_fifo[seen_src_wr[3:0]] <= seen_src_data;
          seen_src_wr <= seen_src_wr + 5'd1;
        end
      end
      // r_seen_src_cp_wr_en is the decoder's one-cycle commit pulse,
      // used here as "pop one entry" -- see the regmap note.
      if (r_seen_src_cp_wr_en && !seen_src_empty) seen_src_rd <= seen_src_rd + 5'd1;
    end
  end


  // AXI4-Lite write channel state machine
  typedef enum logic [1:0] {
    AXIL_IDLE  = 2'd0,
    AXIL_WDATA = 2'd1,
    AXIL_BRESP = 2'd2
  } axil_st_t;

  axil_st_t               axil_st;
  logic [AXIL_ADDR_W-1:0] axil_awaddr_r;

  assign s_axil_awready = (axil_st == AXIL_IDLE);
  assign s_axil_bvalid  = (axil_st == AXIL_BRESP);
  assign s_axil_bresp   = 2'b00;

  // Commit-type words for a busy table stall wready instead of silently
  // dropping the write (see cp_query_busy on the query/delete pipeline).
  logic pending_commit_busy;
  always @(*) begin
    pending_commit_busy = 1'b0;
    case (axil_awaddr_r[AXIL_ADDR_W-1:2])
      14'd5: pending_commit_busy = fwd_cp_query_busy;
      14'd8: pending_commit_busy = fwd_cp_query_busy;
      14'd9: pending_commit_busy = fwd_cp_query_busy;
      default: pending_commit_busy = 1'b0;
    endcase
  end
  assign s_axil_wready = (axil_st == AXIL_WDATA) && !pending_commit_busy;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      axil_st <= AXIL_IDLE;
      r_fwd_cp_wr_en <= 1'b0;
      r_fwd_cp_query_en <= 1'b0;
      r_rate_limit_cp_wr_en <= 1'b0;
      r_seen_src_cp_wr_en <= 1'b0;
    end else begin
      r_fwd_cp_wr_en <= 1'b0;
      r_fwd_cp_query_en <= 1'b0;
      r_rate_limit_cp_wr_en <= 1'b0;
      r_seen_src_cp_wr_en <= 1'b0;
      case (axil_st)
        AXIL_IDLE: begin
          if (s_axil_awvalid) begin
            axil_awaddr_r <= s_axil_awaddr;
            axil_st       <= AXIL_WDATA;
          end
        end
        AXIL_WDATA: begin
          if (s_axil_wvalid && s_axil_wready) begin
            case (axil_awaddr_r[AXIL_ADDR_W-1:2])  // word address
              14'd0: r_fwd_cp_wr_idx <= s_axil_wdata[3:0]; // wr_idx
              14'd1: r_fwd_cp_wr_action <= s_axil_wdata[0:0]; // wr_action
              14'd2: r_fwd_cp_wr_key_dst <= s_axil_wdata[31:0]; // key_dst_w0
              14'd3: r_fwd_cp_wr_key_dst[47:32] <= s_axil_wdata[15:0]; // key_dst_w1
              14'd4: r_fwd_cp_wr_p_p <= s_axil_wdata[8:0]; // p_p
              14'd5: r_fwd_cp_wr_en <= 1'b1; // fwd commit
              14'd6: r_fwd_cp_query_key_dst <= s_axil_wdata[31:0]; // query_key_dst_w0
              14'd7: r_fwd_cp_query_key_dst[47:32] <= s_axil_wdata[15:0]; // query_key_dst_w1
              14'd8: begin r_fwd_cp_query_en <= 1'b1; r_fwd_cp_query_del <= 1'b0; end // fwd query
              14'd9: begin r_fwd_cp_query_en <= 1'b1; r_fwd_cp_query_del <= 1'b1; end // fwd delete
              14'd64: r_rate_limit_cp_rate_shift <= s_axil_wdata[4:0]; // rate_shift
              14'd65: r_rate_limit_cp_burst <= s_axil_wdata[15:0]; // burst
              14'd128: r_seen_src_cp_wr_en <= 1'b1; // seen_src commit
              default: ; // ignore unknown address
            endcase
            axil_st <= AXIL_BRESP;
          end
        end
        AXIL_BRESP: begin
          if (s_axil_bready) axil_st <= AXIL_IDLE;
        end
        default: axil_st <= AXIL_IDLE;
      endcase
    end
  end

  // AXI4-Lite read channel
  typedef enum logic {
    AXIL_R_IDLE = 1'd0,
    AXIL_R_DATA = 1'd1
  } axil_rst_t;

  axil_rst_t   axil_rst;
  logic [31:0] r_rdata;

  assign s_axil_arready = (axil_rst == AXIL_R_IDLE);
  assign s_axil_rdata   = r_rdata;
  assign s_axil_rresp   = 2'b00;
  assign s_axil_rvalid  = (axil_rst == AXIL_R_DATA);

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      axil_rst <= AXIL_R_IDLE;
    end else begin
      case (axil_rst)
        AXIL_R_IDLE: begin
          if (s_axil_arvalid) begin
            case (s_axil_araddr[AXIL_ADDR_W-1:2])  // word address
              14'd10: r_rdata <= {30'd0, fwd_cp_query_hit, fwd_cp_query_busy}; // fwd query_status
              14'd11: r_rdata <= {31'd0, fwd_cp_query_action_id}; // fwd query_action_id
              14'd12: r_rdata <= {23'd0, fwd_cp_query_p_p}; // fwd query_p_p
              14'd129: r_rdata <= {seen_src_overflow, 11'd0, (seen_src_wr - seen_src_rd)}; // seen_src status
              14'd130: r_rdata <= seen_src_cp_rd_data[31:0]; // seen_src data0
              14'd131: r_rdata <= {16'd0, seen_src_cp_rd_data[47:32]}; // seen_src data1
              default: r_rdata <= 32'd0;
            endcase
            axil_rst <= AXIL_R_DATA;
          end
        end
        AXIL_R_DATA: begin
          if (s_axil_rready) axil_rst <= AXIL_R_IDLE;
        end
        default: axil_rst <= AXIL_R_IDLE;
      endcase
    end
  end

  wire [3:0] fwd_cp_wr_idx = r_fwd_cp_wr_idx;
  wire [0:0] fwd_cp_wr_action = r_fwd_cp_wr_action;
  wire [47:0] fwd_cp_wr_key_dst = r_fwd_cp_wr_key_dst;
  wire [8:0] fwd_cp_wr_p_p = r_fwd_cp_wr_p_p;
  wire fwd_cp_wr_en = r_fwd_cp_wr_en;
  wire [47:0] fwd_cp_query_key_dst = r_fwd_cp_query_key_dst;
  wire fwd_cp_query_en  = r_fwd_cp_query_en;
  wire fwd_cp_query_del = r_fwd_cp_query_del;
  wire fwd_hit_out;
  wire [4:0] rate_limit_cp_rate_shift = r_rate_limit_cp_rate_shift;
  wire [15:0] rate_limit_cp_burst = r_rate_limit_cp_burst;
  wire seen_src_cp_wr_en = r_seen_src_cp_wr_en;

  processing_generated u_proc (
    .clk       (clk),
    .rst_n     (rst_n),
    .valid_in  (iss_fire),
    .eth_valid     (w_eth_valid),
    .eth_dst  (w_eth_dst),
    .eth_src  (w_eth_src),
    .eth_etype  (w_eth_etype),
    .meta_colour  (8'b0),
    .meta_midx  (16'b0),
    .out_eth_valid     (out_eth_valid),
    .out_eth_dst  (out_eth_dst),
    .out_eth_src  (out_eth_src),
    .out_eth_etype  (out_eth_etype),
    .out_meta_colour  (proc_out_meta_colour),
    .out_meta_midx  (proc_out_meta_midx),
    .out_std_meta_egress_port  (ig_out_std_meta_egress_port),
    .fwd_cp_wr_en  (fwd_cp_wr_en),
    .fwd_cp_wr_idx (fwd_cp_wr_idx),
    .fwd_cp_wr_action (fwd_cp_wr_action),
    .fwd_cp_wr_key_dst (fwd_cp_wr_key_dst),
    .fwd_cp_wr_p_p (fwd_cp_wr_p_p),
    .fwd_cp_query_key_dst (fwd_cp_query_key_dst),
    .fwd_cp_query_en  (fwd_cp_query_en),
    .fwd_cp_query_del (fwd_cp_query_del),
    .fwd_cp_query_busy (fwd_cp_query_busy),
    .fwd_cp_query_hit  (fwd_cp_query_hit),
    .fwd_cp_query_action_id (fwd_cp_query_action_id),
    .fwd_cp_query_p_p (fwd_cp_query_p_p),
    .fwd_hit_out  (fwd_hit_out),
    .rate_limit_cp_rate_shift (rate_limit_cp_rate_shift),
    .rate_limit_cp_burst      (rate_limit_cp_burst),
    .seen_src_push (seen_src_push),
    .seen_src_data (seen_src_data),
    .out_valid (proc_out_valid),   // aligned with out_*/drop
    .valid_out (proc_valid_out),   // legacy registered-late valid, unused here
    .drop      (proc_drop)
  );

  // ── Per-slot pipeline results ────────────────────────────────────────────
  // Captured on u_proc.out_valid (the data-ALIGNED valid) into slot cmp_slot.
  // The output PHV is stored, not an overlaid byte image, because at
  // completion the slot's later header rows may not have arrived yet
  // (cut-through): the overlay is done at TX time, when TX waits for them.
  logic slot_phv_eth_valid [0:NSLOT-1];
  logic [47:0] slot_phv_eth_dst [0:NSLOT-1];
  logic [47:0] slot_phv_eth_src [0:NSLOT-1];
  logic [15:0] slot_phv_eth_etype [0:NSLOT-1];
  logic [7:0] slot_meta_colour [0:NSLOT-1];
  logic [15:0] slot_meta_midx [0:NSLOT-1];

  // ── RX (ingest) ──────────────────────────────────────────────────────────
  // Accept whenever the next slot is free and the payload FIFO has room.
  // Never because the pipeline or TX is busy -- that is the whole point.
  assign s_axis_tready = rx_slot_free && !pfifo_full;
  wire accept_beat = s_axis_tvalid && s_axis_tready;
  wire [8:0] rx_beat_cnt = slot_beat_cnt[wr_slot];
  wire accept_payload_beat = accept_beat && (rx_beat_cnt >= HDR_MAX_BEATS) && (rx_beat_cnt < MAX_PKT_BEATS);
  assign pfifo_wr_en   = accept_payload_beat;
  assign pfifo_wr_data = { (s_axis_tlast || (rx_beat_cnt == MAX_PKT_BEATS - 1)),
                            s_axis_tkeep, s_axis_tdata };

  logic rx_active;   // a packet is being received into wr_slot
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      wr_ptr <= '0;
      rel_ptr <= '0;
      rx_active <= 1'b0;
      for (int sl = 0; sl < NSLOT; sl++) begin
        slot_beat_cnt[sl] <= '0; slot_done[sl] <= 1'b0; slot_overflow[sl] <= 1'b0;
        slot_txdone[sl] <= 1'b0;
      end
    end else begin
      if (accept_beat) begin
        if (rx_beat_cnt < HDR_MAX_BEATS) begin
          for (int i = 0; i < 32; i++)
            if (s_axis_tkeep[i])
              slot_hdr[wr_slot*HDR_MAX_BYTES + rx_beat_cnt*32 + i] <= s_axis_tdata[i*8 +: 8];
          slot_keep[wr_slot*HDR_MAX_BEATS + rx_beat_cnt] <= s_axis_tkeep;
          slot_beat_cnt[wr_slot] <= rx_beat_cnt + 9'd1;
        end else if (rx_beat_cnt < MAX_PKT_BEATS) begin
          slot_beat_cnt[wr_slot] <= rx_beat_cnt + 9'd1;
        end else begin
          slot_overflow[wr_slot] <= 1'b1;   // truncated; FIFO entry already marked last
        end
        rx_active <= !s_axis_tlast;
        if (s_axis_tlast) begin
          slot_done[wr_slot] <= 1'b1;
          wr_ptr <= wr_ptr + 1'b1;
        end
      end
      // slot release: TX has moved past rel_slot AND its tlast has arrived
      // TX finished with a slot: mark it, so release (which happens in
      // arrival order) can tell which slots are done under reordering.
      if (tx_finish) slot_txdone[tx_slot] <= 1'b1;
      if (slot_release) begin
        rel_ptr <= rel_ptr + 1'b1;
        slot_txdone[rel_slot] <= 1'b0;
        slot_beat_cnt[rel_slot] <= '0; slot_done[rel_slot] <= 1'b0; slot_overflow[rel_slot] <= 1'b0;
      end
    end
  end

  // ── Issue (one-cycle valid_in pulse per packet) ──────────────────────────
  // Slot iss_slot is issuable once it is allocated (RX has at least started
  // it) and its header region has arrived -- the same cutoff the old shell
  // armed on. u_proc is a free-running pipeline: it captures the w_* inputs
  // on the issue edge, so nothing has to be held afterwards and the next
  // slot can be issued on the very next cycle.
  // iss_ptr can legitimately be ONE ahead of wr_ptr (a packet issued cut-
  // through before its tlast). "Behind" therefore has to exclude that case,
  // or an empty future slot would look allocated.
  wire iss_behind_wr = (iss_ptr != wr_ptr) && (iss_ptr != wr_ptr + 1'b1);
  // "RX is mid-packet in wr_slot" is tracked EXPLICITLY (rx_active), not
  // inferred from slot_beat_cnt != 0: wr_ptr advances on tlast even when the
  // next slot still holds an older packet awaiting TX, and that packet's
  // beat count is nonzero too -- inferring from it re-issued a stale slot.
  wire iss_allocated = iss_behind_wr || ((iss_ptr == wr_ptr) && rx_active);
  wire iss_hdr_ready = (slot_beat_cnt[iss_slot] * BEAT_BYTES >= cutoff_byte) || slot_done[iss_slot];
  assign iss_fire = iss_allocated && iss_hdr_ready;
  always_ff @(posedge clk) begin
    if (!rst_n) iss_ptr <= '0;
    else if (iss_fire) begin
      iss_ptr <= iss_ptr + 1'b1;
    end
  end

  // ── Enqueue (ingress done) and capture (egress done) ─────────────────────
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      cmp_ptr <= '0;
    end else begin
      if (proc_out_valid) begin
        cmp_ptr <= cmp_ptr + 1'b1;
        slot_drop[cmp_slot] <= proc_drop;
        slot_phv_eth_valid[cmp_slot] <= out_eth_valid;
        slot_phv_eth_dst[cmp_slot] <= out_eth_dst;
        slot_phv_eth_src[cmp_slot] <= out_eth_src;
        slot_phv_eth_etype[cmp_slot] <= out_eth_etype;
        slot_meta_colour[cmp_slot] <= proc_out_meta_colour;
        slot_meta_midx[cmp_slot] <= proc_out_meta_midx;
        slot_std_meta_egress_port[cmp_slot] <= ig_out_std_meta_egress_port;
      end
    end
  end

  // ── Transmit queue (no egress stage: completion is issue order) ─────────
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      txq_wr <= '0; txq_rd <= '0;
    end else begin
      if (proc_out_valid) begin
        txq_mem[txq_wr[SLOT_AW-1:0]] <= cmp_slot;
        txq_wr <= txq_wr + 1'b1;
      end
      if (tx_finish) txq_rd <= txq_rd + 1'b1;
    end
  end

  // ── TX-side view of slot tx_slot ─────────────────────────────────────────
  logic [7:0] t_hdr [0:HDR_MAX_BYTES-1];
  always_comb for (int i = 0; i < HDR_MAX_BYTES; i++) t_hdr[i] = slot_hdr[tx_slot*HDR_MAX_BYTES + i];
  wire phv_eth_valid = slot_phv_eth_valid[tx_slot];
  wire [47:0] phv_eth_dst = slot_phv_eth_dst[tx_slot];
  wire [47:0] phv_eth_src = slot_phv_eth_src[tx_slot];
  wire [15:0] phv_eth_etype = slot_phv_eth_etype[tx_slot];

  // Declared here, driven further down. The output-image block below reads
  // it, and xvlog will not accept a use that precedes the declaration.
  logic [7:0] hdr_out [0:HDR_MAX_BYTES-1];
  // ── Deparser: header-region assembly for slot tx_slot ────────────────────
  // Received bytes of the slot with its stored output PHV overlaid at each
  // header's layout offset, guarded by the stored output validity.
  always_comb begin
    for (int i = 0; i < HDR_MAX_BYTES; i++) hdr_out[i] = t_hdr[i];
    hdr_out[0] = phv_eth_dst[47:40];
    hdr_out[1] = phv_eth_dst[39:32];
    hdr_out[2] = phv_eth_dst[31:24];
    hdr_out[3] = phv_eth_dst[23:16];
    hdr_out[4] = phv_eth_dst[15:8];
    hdr_out[5] = phv_eth_dst[7:0];
    hdr_out[6] = phv_eth_src[47:40];
    hdr_out[7] = phv_eth_src[39:32];
    hdr_out[8] = phv_eth_src[31:24];
    hdr_out[9] = phv_eth_src[23:16];
    hdr_out[10] = phv_eth_src[15:8];
    hdr_out[11] = phv_eth_src[7:0];
    hdr_out[12] = phv_eth_etype[15:8];
    hdr_out[13] = phv_eth_etype[7:0];
  end

  // ── TX (egress) ──────────────────────────────────────────────────────────
  // No start cycle and no finish-on-consume: the slot at tx_slot is "live"
  // the moment its result is captured (cmp_ptr != tx_ptr), its first row
  // loads on any cycle the output register is free, and the packet is
  // FINISHED when its last beat is LOADED into tx_out (the data is a copy,
  // so the slot can be released right then). tx_ptr advances on that
  // edge, so on the cycle the last beat is consumed the next slot's first
  // row is already loading -- one beat per cycle across packet boundaries.
  // Before this TX cost ~2.5 cycles per packet on top of its beats (a
  // start cycle plus finish-on-consume), which was the whole gap to ideal.
  // Per-slot facts (drop, metadata, counter request) are read straight
  // from the slot each cycle -- they are stable for the slot's lifetime --
  // so nothing needs latching at a start event. The metadata sideband
  // rides in tx_out with the beat, so it changes exactly when the first
  // beat of the next packet is presented.
  wire tx_consumed  = tx_out_valid && m_axis_tready;
  wire tx_slot_free = !tx_out_valid || tx_consumed;
  wire slot_live    = (txq_wr != txq_rd);
  wire cur_discard  = slot_drop[tx_slot];
  wire [8:0] tx_beat_cnt_s = slot_beat_cnt[tx_slot];
  wire tx_done_s        = slot_done[tx_slot];
  wire pkt_ends_in_hdr  = tx_done_s && (tx_beat_cnt_s <= HDR_MAX_BEATS);
  wire hdr_row_ready    = (tx_hdr_row < tx_beat_cnt_s) && (tx_hdr_row < HDR_MAX_BEATS);
  wire hdr_row_is_last  = tx_done_s && (tx_hdr_row == tx_beat_cnt_s - 9'd1);
  wire emit_hdr    = slot_live && !cur_discard && !tx_in_payload && hdr_row_ready && tx_slot_free;
  wire emit_pl     = slot_live && !cur_discard &&  tx_in_payload && pfifo_rd_valid && tx_slot_free;
  wire discard_pop = slot_live &&  cur_discard && pfifo_rd_valid;
  assign pfifo_rd_en = emit_pl || discard_pop;
  wire last_loaded  = (emit_hdr && hdr_row_is_last) || (emit_pl && pfifo_head_last);
  wire discard_done = slot_live && cur_discard && (pkt_ends_in_hdr || (discard_pop && pfifo_head_last));
  assign tx_finish  = last_loaded || discard_done;

  // ── Payload buffer recycle controls ──────────────────────────────────────
  // A SEPARATE always_comb from the one that produces pfifo_rd_valid. Both
  // of these depend on tx_finish, which depends on pfifo_rd_valid -- driving
  // them from that same block makes it sensitive to its own output, and
  // iverilog then re-triggers it forever, stopping simulation time with no
  // error at all.
  always_comb begin
    for (int sl = 0; sl < NSLOT; sl++) begin
      // Reads do not consume, so the buffer is emptied explicitly when
      // the slot is released. Nothing rewinds it: one packet per slot is
      // transmitted exactly once.
      pfifo_clear_v[sl]  = slot_release && (rel_slot == sl[SLOT_AW-1:0]);
      pfifo_rewind_v[sl] = 1'b0;
    end
  end
  assign slot_release = slot_done[rel_slot] && slot_txdone[rel_slot];

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      tx_in_payload <= 1'b0;
      tx_hdr_row    <= '0;
      tx_out_valid  <= 1'b0;
      tx_out_data   <= '0;
      tx_out_keep   <= '0;
      tx_out_last   <= 1'b0;
      out_meta_colour <= '0;
      out_meta_midx <= '0;
      out_std_meta_egress_port <= '0;
    end else begin
      if (tx_consumed) tx_out_valid <= 1'b0;
      if (emit_hdr) begin
        tx_out_valid <= 1'b1;
        for (int i = 0; i < 32; i++)
          tx_out_data[i*8 +: 8] <= hdr_out[tx_hdr_row * 32 + i];
        tx_out_keep  <= slot_keep[tx_slot*HDR_MAX_BEATS + tx_hdr_row];
        tx_out_last  <= hdr_row_is_last;
        tx_hdr_row   <= tx_hdr_row + 9'd1;
        if (!hdr_row_is_last && tx_hdr_row == HDR_MAX_BEATS - 1) tx_in_payload <= 1'b1;
        out_meta_colour <= slot_meta_colour[tx_slot];
        out_meta_midx <= slot_meta_midx[tx_slot];
        out_std_meta_egress_port <= slot_std_meta_egress_port[tx_slot];
      end else if (emit_pl) begin
        tx_out_valid <= 1'b1;
        tx_out_data  <= pfifo_head_data;
        tx_out_keep  <= pfifo_head_keep;
        tx_out_last  <= pfifo_head_last;
        out_meta_colour <= slot_meta_colour[tx_slot];
        out_meta_midx <= slot_meta_midx[tx_slot];
        out_std_meta_egress_port <= slot_std_meta_egress_port[tx_slot];
      end
      if (tx_finish) begin
        tx_in_payload <= 1'b0;
        tx_hdr_row    <= '0;
      end
    end
  end

  // ── TX output ────────────────────────────────────────────────────────────
  // Plain registered pass-through -- see the always_ff above for the fetch/
  // issue logic that fills tx_out_*. tlast is additionally gated on tx_out_valid
  // defensively (tx_out_last could otherwise hold a stale value across a clear).
  assign m_axis_tvalid = tx_out_valid;
  assign m_axis_tdata  = tx_out_data;
  assign m_axis_tkeep  = tx_out_keep;
  assign m_axis_tlast  = tx_out_valid && tx_out_last;

endmodule
