module lenprobe_top #(
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
    output logic [15:0] out_meta_unused,
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
  logic [15:0] slot_byte_len [0:NSLOT-1];
  // Header validity as RECEIVED, sampled at issue. The output validity
  // lives in slot_phv_*_valid; the difference between the two is how many
  // bytes the deparser adds or removes.
  logic slot_in_valid_eth [0:NSLOT-1];
  logic slot_in_valid_tag [0:NSLOT-1];
  logic slot_in_valid_tag2 [0:NSLOT-1];
  logic slot_in_valid_vlan [0:NSLOT-1];
  // Bytes the deparser adds (+) or removes (-), computed ONCE per packet
  // when its result is captured. Deriving it combinationally at TX instead
  // -- six per-slot array reads at a combinational index, feeding the
  // output-image block -- stops iverilog advancing simulation time. It is
  // also just a per-packet fact, so a register is the honest home for it.
  logic signed [7:0] slot_hdr_delta [0:NSLOT-1];
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

  // vlan — base: 14
  logic [15:0] w_vlan_tci;
  logic [15:0] w_vlan_inner_etype;
  always_comb begin
    w_vlan_tci = {x_hdr[14], x_hdr[14+1]};
    w_vlan_inner_etype = {x_hdr[14+2], x_hdr[14+3]};
  end

  // ── Header validity (derived from extracted fields) ──────────────────────
  wire w_eth_valid = 1'b1;
  wire w_vlan_valid = (w_eth_etype == 16'h0003);
  wire w_tag_valid = 1'b0;
  wire w_tag2_valid = 1'b0;

  // ── Header-region cutoff ──────────────────────────────────────────────────
  wire [13:0] w_eth_cutoff_term = 0 + 14;
  wire [13:0] w_vlan_cutoff_term = (w_eth_etype == 16'h0003) ? (14 + 4) : 14'd0;
  wire [13:0] w_cutoff_max_1 = (w_eth_cutoff_term > w_vlan_cutoff_term) ? w_eth_cutoff_term : w_vlan_cutoff_term;
  wire [13:0] cutoff_byte = w_cutoff_max_1;

  // Action-only headers (not in received packet; inputs tied to 0)
  wire [15:0] w_tag_magic = '0;
  wire [15:0] w_tag_seq = '0;
  wire [15:0] w_tag2_magic2 = '0;
  wire [15:0] w_tag2_seq2 = '0;

  // ── processing_generated ─────────────────────────────────────────────────
  //    Signals prefixed proc_out_* are the match-action outputs.

  wire out_eth_valid;
  wire [47:0] out_eth_dst;
  wire [47:0] out_eth_src;
  wire [15:0] out_eth_etype;
  wire out_vlan_valid;
  wire [15:0] out_vlan_tci;
  wire [15:0] out_vlan_inner_etype;
  wire out_tag_valid;
  wire [15:0] out_tag_magic;
  wire [15:0] out_tag_seq;
  wire out_tag2_valid;
  wire [15:0] out_tag2_magic2;
  wire [15:0] out_tag2_seq2;
  wire proc_valid_out;
  wire proc_out_valid;
  wire proc_drop;
  logic iss_fire;
  wire [15:0] proc_out_meta_unused;
  wire [8:0] ig_out_std_meta_egress_port;

  wire cls_cp_query_busy;
  wire cls_cp_query_hit;
  wire [2:0] cls_cp_query_action_id;
  wire [8:0] cls_cp_query_p_port;


  // ── AXI4-Lite staging registers ─────────────────────────────────────────
  logic [3:0] r_cls_cp_wr_idx;
  logic [2:0] r_cls_cp_wr_action;
  logic [15:0] r_cls_cp_wr_key_etype;
  logic [8:0] r_cls_cp_wr_p_port;
  logic [15:0] r_cls_cp_query_key_etype;
  logic r_cls_cp_query_del;
  logic r_cls_cp_wr_en;
  logic r_cls_cp_query_en;

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
      14'd4: pending_commit_busy = cls_cp_query_busy;
      14'd6: pending_commit_busy = cls_cp_query_busy;
      14'd7: pending_commit_busy = cls_cp_query_busy;
      default: pending_commit_busy = 1'b0;
    endcase
  end
  assign s_axil_wready = (axil_st == AXIL_WDATA) && !pending_commit_busy;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      axil_st <= AXIL_IDLE;
      r_cls_cp_wr_en <= 1'b0;
      r_cls_cp_query_en <= 1'b0;
    end else begin
      r_cls_cp_wr_en <= 1'b0;
      r_cls_cp_query_en <= 1'b0;
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
              14'd0: r_cls_cp_wr_idx <= s_axil_wdata[3:0]; // wr_idx
              14'd1: r_cls_cp_wr_action <= s_axil_wdata[2:0]; // wr_action
              14'd2: r_cls_cp_wr_key_etype <= s_axil_wdata[15:0]; // key_etype
              14'd3: r_cls_cp_wr_p_port <= s_axil_wdata[8:0]; // p_port
              14'd4: r_cls_cp_wr_en <= 1'b1; // cls commit
              14'd5: r_cls_cp_query_key_etype <= s_axil_wdata[15:0]; // query_key_etype
              14'd6: begin r_cls_cp_query_en <= 1'b1; r_cls_cp_query_del <= 1'b0; end // cls query
              14'd7: begin r_cls_cp_query_en <= 1'b1; r_cls_cp_query_del <= 1'b1; end // cls delete
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
              14'd8: r_rdata <= {30'd0, cls_cp_query_hit, cls_cp_query_busy}; // cls query_status
              14'd9: r_rdata <= {29'd0, cls_cp_query_action_id}; // cls query_action_id
              14'd10: r_rdata <= {23'd0, cls_cp_query_p_port}; // cls query_p_port
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

  wire [3:0] cls_cp_wr_idx = r_cls_cp_wr_idx;
  wire [2:0] cls_cp_wr_action = r_cls_cp_wr_action;
  wire [15:0] cls_cp_wr_key_etype = r_cls_cp_wr_key_etype;
  wire [8:0] cls_cp_wr_p_port = r_cls_cp_wr_p_port;
  wire cls_cp_wr_en = r_cls_cp_wr_en;
  wire [15:0] cls_cp_query_key_etype = r_cls_cp_query_key_etype;
  wire cls_cp_query_en  = r_cls_cp_query_en;
  wire cls_cp_query_del = r_cls_cp_query_del;
  wire cls_hit_out;

  processing_generated u_proc (
    .clk       (clk),
    .rst_n     (rst_n),
    .valid_in  (iss_fire),
    .eth_valid     (w_eth_valid),
    .vlan_valid     (w_vlan_valid),
    .tag_valid     (w_tag_valid),
    .tag2_valid     (w_tag2_valid),
    .eth_dst  (w_eth_dst),
    .eth_src  (w_eth_src),
    .eth_etype  (w_eth_etype),
    .vlan_tci  (w_vlan_tci),
    .vlan_inner_etype  (w_vlan_inner_etype),
    .tag_magic  (w_tag_magic),
    .tag_seq  (w_tag_seq),
    .tag2_magic2  (w_tag2_magic2),
    .tag2_seq2  (w_tag2_seq2),
    .meta_unused  (16'b0),
    .out_eth_valid     (out_eth_valid),
    .out_vlan_valid     (out_vlan_valid),
    .out_tag_valid     (out_tag_valid),
    .out_tag2_valid     (out_tag2_valid),
    .out_eth_dst  (out_eth_dst),
    .out_eth_src  (out_eth_src),
    .out_eth_etype  (out_eth_etype),
    .out_vlan_tci  (out_vlan_tci),
    .out_vlan_inner_etype  (out_vlan_inner_etype),
    .out_tag_magic  (out_tag_magic),
    .out_tag_seq  (out_tag_seq),
    .out_tag2_magic2  (out_tag2_magic2),
    .out_tag2_seq2  (out_tag2_seq2),
    .out_meta_unused  (proc_out_meta_unused),
    .out_std_meta_egress_port  (ig_out_std_meta_egress_port),
    .cls_cp_wr_en  (cls_cp_wr_en),
    .cls_cp_wr_idx (cls_cp_wr_idx),
    .cls_cp_wr_action (cls_cp_wr_action),
    .cls_cp_wr_key_etype (cls_cp_wr_key_etype),
    .cls_cp_wr_p_port (cls_cp_wr_p_port),
    .cls_cp_query_key_etype (cls_cp_query_key_etype),
    .cls_cp_query_en  (cls_cp_query_en),
    .cls_cp_query_del (cls_cp_query_del),
    .cls_cp_query_busy (cls_cp_query_busy),
    .cls_cp_query_hit  (cls_cp_query_hit),
    .cls_cp_query_action_id (cls_cp_query_action_id),
    .cls_cp_query_p_port (cls_cp_query_p_port),
    .cls_hit_out  (cls_hit_out),
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
  logic slot_phv_vlan_valid [0:NSLOT-1];
  logic slot_phv_tag_valid [0:NSLOT-1];
  logic slot_phv_tag2_valid [0:NSLOT-1];
  logic [47:0] slot_phv_eth_dst [0:NSLOT-1];
  logic [47:0] slot_phv_eth_src [0:NSLOT-1];
  logic [15:0] slot_phv_eth_etype [0:NSLOT-1];
  logic [15:0] slot_phv_vlan_tci [0:NSLOT-1];
  logic [15:0] slot_phv_vlan_inner_etype [0:NSLOT-1];
  logic [15:0] slot_phv_tag_magic [0:NSLOT-1];
  logic [15:0] slot_phv_tag_seq [0:NSLOT-1];
  logic [15:0] slot_phv_tag2_magic2 [0:NSLOT-1];
  logic [15:0] slot_phv_tag2_seq2 [0:NSLOT-1];
  logic [15:0] slot_meta_unused [0:NSLOT-1];

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
        slot_byte_len[sl] <= '0;
      end
    end else begin
      if (accept_beat) begin
        slot_byte_len[wr_slot] <= slot_byte_len[wr_slot] + ({15'd0, s_axis_tkeep[0]} + {15'd0, s_axis_tkeep[1]} + {15'd0, s_axis_tkeep[2]} + {15'd0, s_axis_tkeep[3]} + {15'd0, s_axis_tkeep[4]} + {15'd0, s_axis_tkeep[5]} + {15'd0, s_axis_tkeep[6]} + {15'd0, s_axis_tkeep[7]} + {15'd0, s_axis_tkeep[8]} + {15'd0, s_axis_tkeep[9]} + {15'd0, s_axis_tkeep[10]} + {15'd0, s_axis_tkeep[11]} + {15'd0, s_axis_tkeep[12]} + {15'd0, s_axis_tkeep[13]} + {15'd0, s_axis_tkeep[14]} + {15'd0, s_axis_tkeep[15]} + {15'd0, s_axis_tkeep[16]} + {15'd0, s_axis_tkeep[17]} + {15'd0, s_axis_tkeep[18]} + {15'd0, s_axis_tkeep[19]} + {15'd0, s_axis_tkeep[20]} + {15'd0, s_axis_tkeep[21]} + {15'd0, s_axis_tkeep[22]} + {15'd0, s_axis_tkeep[23]} + {15'd0, s_axis_tkeep[24]} + {15'd0, s_axis_tkeep[25]} + {15'd0, s_axis_tkeep[26]} + {15'd0, s_axis_tkeep[27]} + {15'd0, s_axis_tkeep[28]} + {15'd0, s_axis_tkeep[29]} + {15'd0, s_axis_tkeep[30]} + {15'd0, s_axis_tkeep[31]});
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
        slot_byte_len[rel_slot] <= '0;
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
      slot_in_valid_eth[iss_slot] <= w_eth_valid;
      slot_in_valid_tag[iss_slot] <= w_tag_valid;
      slot_in_valid_tag2[iss_slot] <= w_tag2_valid;
      slot_in_valid_vlan[iss_slot] <= w_vlan_valid;
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
        slot_hdr_delta[cmp_slot] <=
            (out_eth_valid ? 8'sd14 : 8'sd0) - (slot_in_valid_eth[cmp_slot] ? 8'sd14 : 8'sd0)
          + (out_tag_valid ? 8'sd4 : 8'sd0) - (slot_in_valid_tag[cmp_slot] ? 8'sd4 : 8'sd0)
          + (out_tag2_valid ? 8'sd4 : 8'sd0) - (slot_in_valid_tag2[cmp_slot] ? 8'sd4 : 8'sd0)
          + (out_vlan_valid ? 8'sd4 : 8'sd0) - (slot_in_valid_vlan[cmp_slot] ? 8'sd4 : 8'sd0);
        slot_phv_eth_valid[cmp_slot] <= out_eth_valid;
        slot_phv_vlan_valid[cmp_slot] <= out_vlan_valid;
        slot_phv_tag_valid[cmp_slot] <= out_tag_valid;
        slot_phv_tag2_valid[cmp_slot] <= out_tag2_valid;
        slot_phv_eth_dst[cmp_slot] <= out_eth_dst;
        slot_phv_eth_src[cmp_slot] <= out_eth_src;
        slot_phv_eth_etype[cmp_slot] <= out_eth_etype;
        slot_phv_vlan_tci[cmp_slot] <= out_vlan_tci;
        slot_phv_vlan_inner_etype[cmp_slot] <= out_vlan_inner_etype;
        slot_phv_tag_magic[cmp_slot] <= out_tag_magic;
        slot_phv_tag_seq[cmp_slot] <= out_tag_seq;
        slot_phv_tag2_magic2[cmp_slot] <= out_tag2_magic2;
        slot_phv_tag2_seq2[cmp_slot] <= out_tag2_seq2;
        slot_meta_unused[cmp_slot] <= proc_out_meta_unused;
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
  wire phv_vlan_valid = slot_phv_vlan_valid[tx_slot];
  wire phv_tag_valid = slot_phv_tag_valid[tx_slot];
  wire phv_tag2_valid = slot_phv_tag2_valid[tx_slot];
  wire [47:0] phv_eth_dst = slot_phv_eth_dst[tx_slot];
  wire [47:0] phv_eth_src = slot_phv_eth_src[tx_slot];
  wire [15:0] phv_eth_etype = slot_phv_eth_etype[tx_slot];
  wire [15:0] phv_vlan_tci = slot_phv_vlan_tci[tx_slot];
  wire [15:0] phv_vlan_inner_etype = slot_phv_vlan_inner_etype[tx_slot];
  wire [15:0] phv_tag_magic = slot_phv_tag_magic[tx_slot];
  wire [15:0] phv_tag_seq = slot_phv_tag_seq[tx_slot];
  wire [15:0] phv_tag2_magic2 = slot_phv_tag2_magic2[tx_slot];
  wire [15:0] phv_tag2_seq2 = slot_phv_tag2_seq2[tx_slot];

  // One read of the per-packet value computed at capture -- the same
  // shape as the phv_*_valid views above, which is what keeps it safe.
  wire signed [7:0] hdr_delta = slot_hdr_delta[tx_slot];

  // ── Output header offsets (deparser emit order) ─────────────────────────
  // Running sum gated by OUTPUT validity. Only headers up to the last
  // changeable one need these: everything after keeps its internal layout
  // and is shifted wholesale, so the existing overlay covers it.
  wire [13:0] obase_eth = 14'd0;
  wire [13:0] obase_tag = obase_eth
      + (phv_eth_valid ? 14'd14 : 14'd0);
  wire [13:0] obase_tag2 = obase_tag
      + (phv_tag_valid ? 14'd4 : 14'd0);
  wire [13:0] obase_vlan = obase_tag2
      + (phv_tag2_valid ? 14'd4 : 14'd0);
  // Splice point: output bytes below this come from the re-placed header
  // image; at or above it, from the original stream shifted by hdr_delta.
  wire [13:0] tx_splice = obase_vlan
      + (phv_vlan_valid ? 14'd4 : 14'd0);

  // ── Output header image (length-changing deparser) ──────────────────────
  localparam int HDR_OUT_BYTES = 64;  // HDR_MAX_BYTES + max growth, beat-rounded
  logic [7:0] oimg [0:HDR_OUT_BYTES-1];
  // A PACKED copy of the overlay. The shifted read below indexes it at a
  // computed offset, and reading an UNPACKED array that way -- from inside
  // always_comb, at an index that is not the loop variable -- stops
  // iverilog advancing simulation time the moment the offset is non-zero.
  // A packed part-select with a variable base is fine. (Copying element by
  // element at the loop index is also fine, which is what this does.)
  logic [HDR_MAX_BYTES*8-1:0] hdr_out_flat;
  always_comb
    for (int i = 0; i < HDR_MAX_BYTES; i++) hdr_out_flat[i*8 +: 8] = hdr_out[i];
  always_comb begin
    int q;
    // 1. the original stream, shifted
    for (int p = 0; p < HDR_OUT_BYTES; p++) begin
      q = p - hdr_delta;
      oimg[p] = (q >= 0 && q < HDR_MAX_BYTES) ? hdr_out_flat[q*8 +: 8] : 8'h00;
    end
    // 2. the headers that moved differently, at their OUTPUT offsets
    if (phv_eth_valid) begin
        oimg[obase_eth] = phv_eth_dst[47:40];
        oimg[obase_eth+1] = phv_eth_dst[39:32];
        oimg[obase_eth+2] = phv_eth_dst[31:24];
        oimg[obase_eth+3] = phv_eth_dst[23:16];
        oimg[obase_eth+4] = phv_eth_dst[15:8];
        oimg[obase_eth+5] = phv_eth_dst[7:0];
        oimg[obase_eth+6] = phv_eth_src[47:40];
        oimg[obase_eth+7] = phv_eth_src[39:32];
        oimg[obase_eth+8] = phv_eth_src[31:24];
        oimg[obase_eth+9] = phv_eth_src[23:16];
        oimg[obase_eth+10] = phv_eth_src[15:8];
        oimg[obase_eth+11] = phv_eth_src[7:0];
        oimg[obase_eth+12] = phv_eth_etype[15:8];
        oimg[obase_eth+13] = phv_eth_etype[7:0];
    end
    if (phv_tag_valid) begin
        oimg[obase_tag] = phv_tag_magic[15:8];
        oimg[obase_tag+1] = phv_tag_magic[7:0];
        oimg[obase_tag+2] = phv_tag_seq[15:8];
        oimg[obase_tag+3] = phv_tag_seq[7:0];
    end
    if (phv_tag2_valid) begin
        oimg[obase_tag2] = phv_tag2_magic2[15:8];
        oimg[obase_tag2+1] = phv_tag2_magic2[7:0];
        oimg[obase_tag2+2] = phv_tag2_seq2[15:8];
        oimg[obase_tag2+3] = phv_tag2_seq2[7:0];
    end
    if (phv_vlan_valid) begin
        oimg[obase_vlan] = phv_vlan_tci[15:8];
        oimg[obase_vlan+1] = phv_vlan_tci[7:0];
        oimg[obase_vlan+2] = phv_vlan_inner_etype[15:8];
        oimg[obase_vlan+3] = phv_vlan_inner_etype[7:0];
    end
  end

  // ── Deparser: header-region assembly for slot tx_slot ────────────────────
  // Received bytes of the slot with its stored output PHV overlaid at each
  // header's layout offset, guarded by the stored output validity.
  logic [7:0] hdr_out [0:HDR_MAX_BYTES-1];
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
    if (phv_vlan_valid) begin
        hdr_out[14] = phv_vlan_tci[15:8];
        hdr_out[14+1] = phv_vlan_tci[7:0];
        hdr_out[14+2] = phv_vlan_inner_etype[15:8];
        hdr_out[14+3] = phv_vlan_inner_etype[7:0];
    end
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
  // ── Length-changing TX control ──────────────────────────────────────────
  // The output stream is oimg[0 .. tx_pstart) followed by the payload,
  // which therefore starts at a byte position that is NOT beat-aligned
  // when hdr_delta is not a multiple of the beat width. `tx_rot` is that
  // misalignment, constant for the whole packet, so every payload output
  // beat is one two-beat window selected at a fixed offset.
  // Every one of these mixes the unsigned byte counters with the SIGNED
  // hdr_delta, and Verilog makes the whole expression unsigned as soon as
  // one operand is -- so a negative delta silently becomes a huge positive
  // number. (A 64-byte packet shrinking by 4 came out as 316 bytes before
  // these casts.) Each one is therefore forced signed and narrowed back.
  // slot_byte_len counts every byte RECEIVED, including the ones RX
  // truncated on an oversize packet -- only MAX_PKT_BYTES were stored. A
  // length derived from the raw count would ask TX for beats that were
  // never written, so it is clamped to what the slot actually holds.
  wire [15:0] tx_in_raw   = slot_byte_len[tx_slot];
  wire [15:0] tx_in_len   = (tx_in_raw > MAX_PKT_BYTES[15:0])
                            ? MAX_PKT_BYTES[15:0] : tx_in_raw;
  wire signed [17:0] tx_out_len_s = $signed({2'b0, tx_in_len}) + hdr_delta;
  wire [15:0] tx_out_len  = tx_out_len_s[15:0];
  wire signed [17:0] tx_pstart_s  = $signed(18'd0 + HDR_MAX_BYTES) + hdr_delta;
  wire [15:0] tx_pstart   = tx_pstart_s[15:0];
  wire [4:0] tx_rot = tx_pstart[4:0];
  logic [15:0] tx_out_byte;   // output byte position of the next beat
  wire [15:0] tx_left     = tx_out_len - tx_out_byte;
  wire tx_last_beat       = tx_done_s && (tx_left <= BEAT_BYTES);
  wire discard_pop = slot_live &&  cur_discard && pfifo_rd_valid;
  // Does this beat reach into the payload region?
  wire tx_need_pl  = ((tx_out_byte + BEAT_BYTES) > tx_pstart);
  // Source bytes this beat reads, so the header part is only emitted once
  // the bytes it shifts FROM have actually arrived.
  wire signed [17:0] tx_src_need_s =
        $signed({2'b0, tx_out_byte}) + $signed(18'd0 + BEAT_BYTES) - hdr_delta;
  wire tx_src_ready = tx_done_s
        || ($signed(18'd0 + (tx_beat_cnt_s * BEAT_BYTES)) >= tx_src_need_s);
  // The two-beat payload window: the head is the beat this output beat
  // consumes, pl_prev the one before it (needed when tx_rot != 0). The
  // final beat of a grown packet may need ONLY pl_prev, which is why
  // pl_prev_v can stand in for the head being empty.
  logic [AXI_DATA_W-1:0] pl_prev;
  logic                  pl_prev_v;
  wire emit_beat = slot_live && !cur_discard && tx_slot_free && (tx_left != 0)
                   && (tx_need_pl ? (pfifo_rd_valid || pl_prev_v) : tx_src_ready);
  assign pfifo_rd_en = (emit_beat && tx_need_pl && pfifo_rd_valid) || discard_pop;
  wire last_loaded  = emit_beat && tx_last_beat;
  wire discard_done = slot_live && cur_discard && (pkt_ends_in_hdr || (discard_pop && pfifo_head_last));
  assign tx_finish  = last_loaded || discard_done;

  // ── Beat assembly ───────────────────────────────────────────────────────
  // Output byte p comes from the output header image below tx_pstart, and
  // from the payload above it. Because tx_pstart is not beat-aligned, the
  // payload lanes split: lanes at or above tx_rot come from the current
  // payload beat, lanes below it from the previous one. tkeep falls out of
  // the output length, which is how a shorter or longer packet terminates.
  logic [AXI_DATA_W-1:0]   tx_beat_data;
  logic [AXI_DATA_W/8-1:0] tx_beat_keep;
  always_comb begin
    int p;
    tx_beat_data = '0;
    tx_beat_keep = '0;
    for (int i = 0; i < BEAT_BYTES; i++) begin
      p = tx_out_byte + i;
      if (p < tx_out_len) begin
        tx_beat_keep[i] = 1'b1;
        if (p < tx_pstart)
          tx_beat_data[i*8 +: 8] = oimg[p];
        else if (i >= tx_rot)
          tx_beat_data[i*8 +: 8] = pfifo_head_data[(i - tx_rot)*8 +: 8];
        else
          tx_beat_data[i*8 +: 8] = pl_prev[(BEAT_BYTES - tx_rot + i)*8 +: 8];
      end
    end
  end

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
      tx_out_byte   <= '0;
      pl_prev       <= '0;
      pl_prev_v     <= 1'b0;
      tx_out_valid  <= 1'b0;
      tx_out_data   <= '0;
      tx_out_keep   <= '0;
      tx_out_last   <= 1'b0;
      out_meta_unused <= '0;
      out_std_meta_egress_port <= '0;
    end else begin
      if (tx_consumed) tx_out_valid <= 1'b0;
      if (emit_beat) begin
        tx_out_valid <= 1'b1;
        tx_out_data  <= tx_beat_data;
        tx_out_keep  <= tx_beat_keep;
        tx_out_last  <= tx_last_beat;
        tx_out_byte  <= tx_out_byte + BEAT_BYTES;
        // Slide the payload window only when a beat was actually taken.
        if (tx_need_pl && pfifo_rd_valid) begin
          pl_prev   <= pfifo_head_data;
          pl_prev_v <= 1'b1;
        end
        out_meta_unused <= slot_meta_unused[tx_slot];
        out_std_meta_egress_port <= slot_std_meta_egress_port[tx_slot];
      end
      if (tx_finish) begin
        tx_in_payload <= 1'b0;
        tx_hdr_row    <= '0;
        tx_out_byte   <= '0;
        pl_prev_v     <= 1'b0;
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
