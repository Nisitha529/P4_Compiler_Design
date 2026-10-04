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
    output logic [15:0] out_meta_plen,
    output logic [15:0] out_meta_pbytes,
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
  // bytes the deparser adds or removes, and it is also the only honest
  // basis for the offsets at which the deparser reads the received bytes.
  logic slot_in_valid_eth [0:NSLOT-1];
  logic slot_in_valid_vlan [0:NSLOT-1];
  logic slot_in_valid_tag [0:NSLOT-1];
  logic slot_in_valid_tag2 [0:NSLOT-1];
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
  wire [15:0] proc_out_meta_plen;
  wire [15:0] proc_out_meta_pbytes;
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
    .meta_plen  (16'b0),
    .meta_pbytes  (16'b0),
    .std_meta_packet_length  (16'({slot_byte_len[iss_slot]})),  // final: issue waits for tlast
    .std_meta_parsed_bytes  (16'(cutoff_byte)),  // bytes consumed by extract()
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
    .out_meta_plen  (proc_out_meta_plen),
    .out_meta_pbytes  (proc_out_meta_pbytes),
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
  logic [15:0] slot_meta_plen [0:NSLOT-1];
  logic [15:0] slot_meta_pbytes [0:NSLOT-1];

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
  // This program reads standard_metadata.packet_length, which is the
  // whole frame's byte count and is therefore not known until tlast.
  // Issue waits for the complete packet: STORE-AND-FORWARD for this
  // app, cut-through for every app that does not read it.
  wire iss_hdr_ready = slot_done[iss_slot];
  assign iss_fire = iss_allocated && iss_hdr_ready;
  always_ff @(posedge clk) begin
    if (!rst_n) iss_ptr <= '0;
    else if (iss_fire) begin
      iss_ptr <= iss_ptr + 1'b1;
      slot_in_valid_eth[iss_slot] <= w_eth_valid;
      slot_in_valid_vlan[iss_slot] <= w_vlan_valid;
      slot_in_valid_tag[iss_slot] <= w_tag_valid;
      slot_in_valid_tag2[iss_slot] <= w_tag2_valid;
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
        slot_meta_plen[cmp_slot] <= proc_out_meta_plen;
        slot_meta_pbytes[cmp_slot] <= proc_out_meta_pbytes;
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
  // Validity as RECEIVED. hdr_out overlays the stored output PHV onto the
  // bytes that arrived, so its offsets must follow the INPUT layout. The
  // output validity is the wrong thing to ask, and so is re-evaluating the
  // parser transition conditions over the output PHV: this app rewrites
  // eth.type to 0x8100, which made the deparser read ipv4 at the offset a
  // VLAN-tagged frame would have had and duplicate four bytes.
  wire phv_in_valid_eth = slot_in_valid_eth[tx_slot];
  wire phv_in_valid_vlan = slot_in_valid_vlan[tx_slot];
  wire phv_in_valid_tag = slot_in_valid_tag[tx_slot];
  wire phv_in_valid_tag2 = slot_in_valid_tag2[tx_slot];

  // One read of the per-packet value computed at capture -- the same
  // shape as the phv_*_valid views above, which is what keeps it safe.
  wire signed [7:0] hdr_delta = slot_hdr_delta[tx_slot];

  // Declared here, driven further down. The output-image block below reads
  // it, and xvlog will not accept a use that precedes the declaration.
  logic [7:0] hdr_out [0:HDR_MAX_BYTES-1];
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
  // The shift, as a case over every achievable hdr_delta so that each
  // branch reads hdr_out at a CONSTANT offset, and each branch writes
  // every oimg element exactly once. A computed offset, or a second
  // write loop over oimg in this block, stops iverilog advancing
  // simulation time; see the comment in emit_top.py.
  always_comb begin
    // 1. the original stream, shifted
    case (hdr_delta)
      -8'sd12: for (int p = 0; p < HDR_OUT_BYTES; p++) oimg[p] = (p < 20) ? hdr_out[p + 12] : 8'h00;
      -8'sd8: for (int p = 0; p < HDR_OUT_BYTES; p++) oimg[p] = (p < 24) ? hdr_out[p + 8] : 8'h00;
      -8'sd4: for (int p = 0; p < HDR_OUT_BYTES; p++) oimg[p] = (p < 28) ? hdr_out[p + 4] : 8'h00;
      8'sd0: for (int p = 0; p < HDR_OUT_BYTES; p++) oimg[p] = (p < 32) ? hdr_out[p] : 8'h00;
      8'sd4: for (int p = 0; p < HDR_OUT_BYTES; p++) oimg[p] = (p >= 4 && p < 36) ? hdr_out[p - 4] : 8'h00;
      8'sd8: for (int p = 0; p < HDR_OUT_BYTES; p++) oimg[p] = (p >= 8 && p < 40) ? hdr_out[p - 8] : 8'h00;
      8'sd12: for (int p = 0; p < HDR_OUT_BYTES; p++) oimg[p] = (p >= 12 && p < 44) ? hdr_out[p - 12] : 8'h00;
      default: for (int p = 0; p < HDR_OUT_BYTES; p++) oimg[p] = 8'h00;
    endcase
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

  // Packed copy of the output image. The beat assembly reads the image at
  // a computed offset, and an unpacked read at a computed index inside
  // always_comb makes the reading block re-trigger itself forever. A
  // packed part-select with a variable base is safe to READ.
  logic [HDR_OUT_BYTES*8-1:0] oflat;
  always_comb begin
    oflat[7:0] = oimg[0];
    oflat[15:8] = oimg[1];
    oflat[23:16] = oimg[2];
    oflat[31:24] = oimg[3];
    oflat[39:32] = oimg[4];
    oflat[47:40] = oimg[5];
    oflat[55:48] = oimg[6];
    oflat[63:56] = oimg[7];
    oflat[71:64] = oimg[8];
    oflat[79:72] = oimg[9];
    oflat[87:80] = oimg[10];
    oflat[95:88] = oimg[11];
    oflat[103:96] = oimg[12];
    oflat[111:104] = oimg[13];
    oflat[119:112] = oimg[14];
    oflat[127:120] = oimg[15];
    oflat[135:128] = oimg[16];
    oflat[143:136] = oimg[17];
    oflat[151:144] = oimg[18];
    oflat[159:152] = oimg[19];
    oflat[167:160] = oimg[20];
    oflat[175:168] = oimg[21];
    oflat[183:176] = oimg[22];
    oflat[191:184] = oimg[23];
    oflat[199:192] = oimg[24];
    oflat[207:200] = oimg[25];
    oflat[215:208] = oimg[26];
    oflat[223:216] = oimg[27];
    oflat[231:224] = oimg[28];
    oflat[239:232] = oimg[29];
    oflat[247:240] = oimg[30];
    oflat[255:248] = oimg[31];
    oflat[263:256] = oimg[32];
    oflat[271:264] = oimg[33];
    oflat[279:272] = oimg[34];
    oflat[287:280] = oimg[35];
    oflat[295:288] = oimg[36];
    oflat[303:296] = oimg[37];
    oflat[311:304] = oimg[38];
    oflat[319:312] = oimg[39];
    oflat[327:320] = oimg[40];
    oflat[335:328] = oimg[41];
    oflat[343:336] = oimg[42];
    oflat[351:344] = oimg[43];
    oflat[359:352] = oimg[44];
    oflat[367:360] = oimg[45];
    oflat[375:368] = oimg[46];
    oflat[383:376] = oimg[47];
    oflat[391:384] = oimg[48];
    oflat[399:392] = oimg[49];
    oflat[407:400] = oimg[50];
    oflat[415:408] = oimg[51];
    oflat[423:416] = oimg[52];
    oflat[431:424] = oimg[53];
    oflat[439:432] = oimg[54];
    oflat[447:440] = oimg[55];
    oflat[455:448] = oimg[56];
    oflat[463:456] = oimg[57];
    oflat[471:464] = oimg[58];
    oflat[479:472] = oimg[59];
    oflat[487:480] = oimg[60];
    oflat[495:488] = oimg[61];
    oflat[503:496] = oimg[62];
    oflat[511:504] = oimg[63];
  end

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
    p = tx_out_byte + 0;
    if (p < tx_out_len) begin
      tx_beat_keep[0] = 1'b1;
      if (p < tx_pstart)
        tx_beat_data[7:0] = oflat[p*8 +: 8];
      else if (0 >= tx_rot)
        tx_beat_data[7:0] = pfifo_head_data[(0 - tx_rot)*8 +: 8];
      else
        tx_beat_data[7:0] = pl_prev[(BEAT_BYTES - tx_rot + 0)*8 +: 8];
    end
    p = tx_out_byte + 1;
    if (p < tx_out_len) begin
      tx_beat_keep[1] = 1'b1;
      if (p < tx_pstart)
        tx_beat_data[15:8] = oflat[p*8 +: 8];
      else if (1 >= tx_rot)
        tx_beat_data[15:8] = pfifo_head_data[(1 - tx_rot)*8 +: 8];
      else
        tx_beat_data[15:8] = pl_prev[(BEAT_BYTES - tx_rot + 1)*8 +: 8];
    end
    p = tx_out_byte + 2;
    if (p < tx_out_len) begin
      tx_beat_keep[2] = 1'b1;
      if (p < tx_pstart)
        tx_beat_data[23:16] = oflat[p*8 +: 8];
      else if (2 >= tx_rot)
        tx_beat_data[23:16] = pfifo_head_data[(2 - tx_rot)*8 +: 8];
      else
        tx_beat_data[23:16] = pl_prev[(BEAT_BYTES - tx_rot + 2)*8 +: 8];
    end
    p = tx_out_byte + 3;
    if (p < tx_out_len) begin
      tx_beat_keep[3] = 1'b1;
      if (p < tx_pstart)
        tx_beat_data[31:24] = oflat[p*8 +: 8];
      else if (3 >= tx_rot)
        tx_beat_data[31:24] = pfifo_head_data[(3 - tx_rot)*8 +: 8];
      else
        tx_beat_data[31:24] = pl_prev[(BEAT_BYTES - tx_rot + 3)*8 +: 8];
    end
    p = tx_out_byte + 4;
    if (p < tx_out_len) begin
      tx_beat_keep[4] = 1'b1;
      if (p < tx_pstart)
        tx_beat_data[39:32] = oflat[p*8 +: 8];
      else if (4 >= tx_rot)
        tx_beat_data[39:32] = pfifo_head_data[(4 - tx_rot)*8 +: 8];
      else
        tx_beat_data[39:32] = pl_prev[(BEAT_BYTES - tx_rot + 4)*8 +: 8];
    end
    p = tx_out_byte + 5;
    if (p < tx_out_len) begin
      tx_beat_keep[5] = 1'b1;
      if (p < tx_pstart)
        tx_beat_data[47:40] = oflat[p*8 +: 8];
      else if (5 >= tx_rot)
        tx_beat_data[47:40] = pfifo_head_data[(5 - tx_rot)*8 +: 8];
      else
        tx_beat_data[47:40] = pl_prev[(BEAT_BYTES - tx_rot + 5)*8 +: 8];
    end
    p = tx_out_byte + 6;
    if (p < tx_out_len) begin
      tx_beat_keep[6] = 1'b1;
      if (p < tx_pstart)
        tx_beat_data[55:48] = oflat[p*8 +: 8];
      else if (6 >= tx_rot)
        tx_beat_data[55:48] = pfifo_head_data[(6 - tx_rot)*8 +: 8];
      else
        tx_beat_data[55:48] = pl_prev[(BEAT_BYTES - tx_rot + 6)*8 +: 8];
    end
    p = tx_out_byte + 7;
    if (p < tx_out_len) begin
      tx_beat_keep[7] = 1'b1;
      if (p < tx_pstart)
        tx_beat_data[63:56] = oflat[p*8 +: 8];
      else if (7 >= tx_rot)
        tx_beat_data[63:56] = pfifo_head_data[(7 - tx_rot)*8 +: 8];
      else
        tx_beat_data[63:56] = pl_prev[(BEAT_BYTES - tx_rot + 7)*8 +: 8];
    end
    p = tx_out_byte + 8;
    if (p < tx_out_len) begin
      tx_beat_keep[8] = 1'b1;
      if (p < tx_pstart)
        tx_beat_data[71:64] = oflat[p*8 +: 8];
      else if (8 >= tx_rot)
        tx_beat_data[71:64] = pfifo_head_data[(8 - tx_rot)*8 +: 8];
      else
        tx_beat_data[71:64] = pl_prev[(BEAT_BYTES - tx_rot + 8)*8 +: 8];
    end
    p = tx_out_byte + 9;
    if (p < tx_out_len) begin
      tx_beat_keep[9] = 1'b1;
      if (p < tx_pstart)
        tx_beat_data[79:72] = oflat[p*8 +: 8];
      else if (9 >= tx_rot)
        tx_beat_data[79:72] = pfifo_head_data[(9 - tx_rot)*8 +: 8];
      else
        tx_beat_data[79:72] = pl_prev[(BEAT_BYTES - tx_rot + 9)*8 +: 8];
    end
    p = tx_out_byte + 10;
    if (p < tx_out_len) begin
      tx_beat_keep[10] = 1'b1;
      if (p < tx_pstart)
        tx_beat_data[87:80] = oflat[p*8 +: 8];
      else if (10 >= tx_rot)
        tx_beat_data[87:80] = pfifo_head_data[(10 - tx_rot)*8 +: 8];
      else
        tx_beat_data[87:80] = pl_prev[(BEAT_BYTES - tx_rot + 10)*8 +: 8];
    end
    p = tx_out_byte + 11;
    if (p < tx_out_len) begin
      tx_beat_keep[11] = 1'b1;
      if (p < tx_pstart)
        tx_beat_data[95:88] = oflat[p*8 +: 8];
      else if (11 >= tx_rot)
        tx_beat_data[95:88] = pfifo_head_data[(11 - tx_rot)*8 +: 8];
      else
        tx_beat_data[95:88] = pl_prev[(BEAT_BYTES - tx_rot + 11)*8 +: 8];
    end
    p = tx_out_byte + 12;
    if (p < tx_out_len) begin
      tx_beat_keep[12] = 1'b1;
      if (p < tx_pstart)
        tx_beat_data[103:96] = oflat[p*8 +: 8];
      else if (12 >= tx_rot)
        tx_beat_data[103:96] = pfifo_head_data[(12 - tx_rot)*8 +: 8];
      else
        tx_beat_data[103:96] = pl_prev[(BEAT_BYTES - tx_rot + 12)*8 +: 8];
    end
    p = tx_out_byte + 13;
    if (p < tx_out_len) begin
      tx_beat_keep[13] = 1'b1;
      if (p < tx_pstart)
        tx_beat_data[111:104] = oflat[p*8 +: 8];
      else if (13 >= tx_rot)
        tx_beat_data[111:104] = pfifo_head_data[(13 - tx_rot)*8 +: 8];
      else
        tx_beat_data[111:104] = pl_prev[(BEAT_BYTES - tx_rot + 13)*8 +: 8];
    end
    p = tx_out_byte + 14;
    if (p < tx_out_len) begin
      tx_beat_keep[14] = 1'b1;
      if (p < tx_pstart)
        tx_beat_data[119:112] = oflat[p*8 +: 8];
      else if (14 >= tx_rot)
        tx_beat_data[119:112] = pfifo_head_data[(14 - tx_rot)*8 +: 8];
      else
        tx_beat_data[119:112] = pl_prev[(BEAT_BYTES - tx_rot + 14)*8 +: 8];
    end
    p = tx_out_byte + 15;
    if (p < tx_out_len) begin
      tx_beat_keep[15] = 1'b1;
      if (p < tx_pstart)
        tx_beat_data[127:120] = oflat[p*8 +: 8];
      else if (15 >= tx_rot)
        tx_beat_data[127:120] = pfifo_head_data[(15 - tx_rot)*8 +: 8];
      else
        tx_beat_data[127:120] = pl_prev[(BEAT_BYTES - tx_rot + 15)*8 +: 8];
    end
    p = tx_out_byte + 16;
    if (p < tx_out_len) begin
      tx_beat_keep[16] = 1'b1;
      if (p < tx_pstart)
        tx_beat_data[135:128] = oflat[p*8 +: 8];
      else if (16 >= tx_rot)
        tx_beat_data[135:128] = pfifo_head_data[(16 - tx_rot)*8 +: 8];
      else
        tx_beat_data[135:128] = pl_prev[(BEAT_BYTES - tx_rot + 16)*8 +: 8];
    end
    p = tx_out_byte + 17;
    if (p < tx_out_len) begin
      tx_beat_keep[17] = 1'b1;
      if (p < tx_pstart)
        tx_beat_data[143:136] = oflat[p*8 +: 8];
      else if (17 >= tx_rot)
        tx_beat_data[143:136] = pfifo_head_data[(17 - tx_rot)*8 +: 8];
      else
        tx_beat_data[143:136] = pl_prev[(BEAT_BYTES - tx_rot + 17)*8 +: 8];
    end
    p = tx_out_byte + 18;
    if (p < tx_out_len) begin
      tx_beat_keep[18] = 1'b1;
      if (p < tx_pstart)
        tx_beat_data[151:144] = oflat[p*8 +: 8];
      else if (18 >= tx_rot)
        tx_beat_data[151:144] = pfifo_head_data[(18 - tx_rot)*8 +: 8];
      else
        tx_beat_data[151:144] = pl_prev[(BEAT_BYTES - tx_rot + 18)*8 +: 8];
    end
    p = tx_out_byte + 19;
    if (p < tx_out_len) begin
      tx_beat_keep[19] = 1'b1;
      if (p < tx_pstart)
        tx_beat_data[159:152] = oflat[p*8 +: 8];
      else if (19 >= tx_rot)
        tx_beat_data[159:152] = pfifo_head_data[(19 - tx_rot)*8 +: 8];
      else
        tx_beat_data[159:152] = pl_prev[(BEAT_BYTES - tx_rot + 19)*8 +: 8];
    end
    p = tx_out_byte + 20;
    if (p < tx_out_len) begin
      tx_beat_keep[20] = 1'b1;
      if (p < tx_pstart)
        tx_beat_data[167:160] = oflat[p*8 +: 8];
      else if (20 >= tx_rot)
        tx_beat_data[167:160] = pfifo_head_data[(20 - tx_rot)*8 +: 8];
      else
        tx_beat_data[167:160] = pl_prev[(BEAT_BYTES - tx_rot + 20)*8 +: 8];
    end
    p = tx_out_byte + 21;
    if (p < tx_out_len) begin
      tx_beat_keep[21] = 1'b1;
      if (p < tx_pstart)
        tx_beat_data[175:168] = oflat[p*8 +: 8];
      else if (21 >= tx_rot)
        tx_beat_data[175:168] = pfifo_head_data[(21 - tx_rot)*8 +: 8];
      else
        tx_beat_data[175:168] = pl_prev[(BEAT_BYTES - tx_rot + 21)*8 +: 8];
    end
    p = tx_out_byte + 22;
    if (p < tx_out_len) begin
      tx_beat_keep[22] = 1'b1;
      if (p < tx_pstart)
        tx_beat_data[183:176] = oflat[p*8 +: 8];
      else if (22 >= tx_rot)
        tx_beat_data[183:176] = pfifo_head_data[(22 - tx_rot)*8 +: 8];
      else
        tx_beat_data[183:176] = pl_prev[(BEAT_BYTES - tx_rot + 22)*8 +: 8];
    end
    p = tx_out_byte + 23;
    if (p < tx_out_len) begin
      tx_beat_keep[23] = 1'b1;
      if (p < tx_pstart)
        tx_beat_data[191:184] = oflat[p*8 +: 8];
      else if (23 >= tx_rot)
        tx_beat_data[191:184] = pfifo_head_data[(23 - tx_rot)*8 +: 8];
      else
        tx_beat_data[191:184] = pl_prev[(BEAT_BYTES - tx_rot + 23)*8 +: 8];
    end
    p = tx_out_byte + 24;
    if (p < tx_out_len) begin
      tx_beat_keep[24] = 1'b1;
      if (p < tx_pstart)
        tx_beat_data[199:192] = oflat[p*8 +: 8];
      else if (24 >= tx_rot)
        tx_beat_data[199:192] = pfifo_head_data[(24 - tx_rot)*8 +: 8];
      else
        tx_beat_data[199:192] = pl_prev[(BEAT_BYTES - tx_rot + 24)*8 +: 8];
    end
    p = tx_out_byte + 25;
    if (p < tx_out_len) begin
      tx_beat_keep[25] = 1'b1;
      if (p < tx_pstart)
        tx_beat_data[207:200] = oflat[p*8 +: 8];
      else if (25 >= tx_rot)
        tx_beat_data[207:200] = pfifo_head_data[(25 - tx_rot)*8 +: 8];
      else
        tx_beat_data[207:200] = pl_prev[(BEAT_BYTES - tx_rot + 25)*8 +: 8];
    end
    p = tx_out_byte + 26;
    if (p < tx_out_len) begin
      tx_beat_keep[26] = 1'b1;
      if (p < tx_pstart)
        tx_beat_data[215:208] = oflat[p*8 +: 8];
      else if (26 >= tx_rot)
        tx_beat_data[215:208] = pfifo_head_data[(26 - tx_rot)*8 +: 8];
      else
        tx_beat_data[215:208] = pl_prev[(BEAT_BYTES - tx_rot + 26)*8 +: 8];
    end
    p = tx_out_byte + 27;
    if (p < tx_out_len) begin
      tx_beat_keep[27] = 1'b1;
      if (p < tx_pstart)
        tx_beat_data[223:216] = oflat[p*8 +: 8];
      else if (27 >= tx_rot)
        tx_beat_data[223:216] = pfifo_head_data[(27 - tx_rot)*8 +: 8];
      else
        tx_beat_data[223:216] = pl_prev[(BEAT_BYTES - tx_rot + 27)*8 +: 8];
    end
    p = tx_out_byte + 28;
    if (p < tx_out_len) begin
      tx_beat_keep[28] = 1'b1;
      if (p < tx_pstart)
        tx_beat_data[231:224] = oflat[p*8 +: 8];
      else if (28 >= tx_rot)
        tx_beat_data[231:224] = pfifo_head_data[(28 - tx_rot)*8 +: 8];
      else
        tx_beat_data[231:224] = pl_prev[(BEAT_BYTES - tx_rot + 28)*8 +: 8];
    end
    p = tx_out_byte + 29;
    if (p < tx_out_len) begin
      tx_beat_keep[29] = 1'b1;
      if (p < tx_pstart)
        tx_beat_data[239:232] = oflat[p*8 +: 8];
      else if (29 >= tx_rot)
        tx_beat_data[239:232] = pfifo_head_data[(29 - tx_rot)*8 +: 8];
      else
        tx_beat_data[239:232] = pl_prev[(BEAT_BYTES - tx_rot + 29)*8 +: 8];
    end
    p = tx_out_byte + 30;
    if (p < tx_out_len) begin
      tx_beat_keep[30] = 1'b1;
      if (p < tx_pstart)
        tx_beat_data[247:240] = oflat[p*8 +: 8];
      else if (30 >= tx_rot)
        tx_beat_data[247:240] = pfifo_head_data[(30 - tx_rot)*8 +: 8];
      else
        tx_beat_data[247:240] = pl_prev[(BEAT_BYTES - tx_rot + 30)*8 +: 8];
    end
    p = tx_out_byte + 31;
    if (p < tx_out_len) begin
      tx_beat_keep[31] = 1'b1;
      if (p < tx_pstart)
        tx_beat_data[255:248] = oflat[p*8 +: 8];
      else if (31 >= tx_rot)
        tx_beat_data[255:248] = pfifo_head_data[(31 - tx_rot)*8 +: 8];
      else
        tx_beat_data[255:248] = pl_prev[(BEAT_BYTES - tx_rot + 31)*8 +: 8];
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
      out_meta_plen <= '0;
      out_meta_pbytes <= '0;
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
        out_meta_plen <= slot_meta_plen[tx_slot];
        out_meta_pbytes <= slot_meta_pbytes[tx_slot];
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
