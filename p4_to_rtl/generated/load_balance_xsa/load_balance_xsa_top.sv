module load_balance_xsa_top #(
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
    input  logic                      s_axil_rready
);

  localparam int BEAT_BYTES    = AXI_DATA_W / 8;  // 32
  localparam int MAX_PKT_BEATS = 256;
  localparam int MAX_PKT_BYTES = MAX_PKT_BEATS * BEAT_BYTES;  // 8192
  localparam int HDR_MAX_BYTES = 96;
  localparam int HDR_MAX_BEATS = 3;
  localparam int PAYLOAD_MAX_BYTES = MAX_PKT_BYTES - HDR_MAX_BYTES;  // 8096
  localparam int PAYLOAD_MAX_BEATS = PAYLOAD_MAX_BYTES / BEAT_BYTES;  // 253

  // ── Packet buffer (header region / payload region, see above) ───────────────
  logic [7:0] pkt_buf_hdr     [0:HDR_MAX_BYTES-1];
  (* ram_style = "block" *)
  logic [BEAT_BYTES-1:0][7:0] pkt_buf_payload [0:PAYLOAD_MAX_BEATS-1];
  `ifndef SYNTHESIS
  // synthesis translate_off
  initial begin
    for (int i = 0; i < HDR_MAX_BYTES; i++) pkt_buf_hdr[i] = 8'd0;
    for (int r = 0; r < PAYLOAD_MAX_BEATS; r++)
      for (int b = 0; b < BEAT_BYTES; b++) pkt_buf_payload[r][b] = 8'd0;
  end
  // synthesis translate_on
  `endif
  logic [AXI_DATA_W/8-1:0] pkt_keep [0:MAX_PKT_BEATS-1];

  // ── State registers ──────────────────────────────────────────────────────
  //   pkt_busy   : a packet currently owns the pipeline (any stage). The
  //                single-packet-in-flight invariant -- packet N+1 cannot
  //                start until N has drained from BOTH RX and TX.
  //   rx_done    : RX captured this packet's tlast beat (or the overflow
  //                path below completed). Reset to 0 whenever pkt_busy is 0,
  //                by construction of the RX block's own logic -- so
  //                s_axis_tready = !rx_done is correct on its own.
  //   rx_beat_cnt: beats captured so far. Freezes automatically once rx_done
  //                latches (increment is gated on !rx_done) -- no separate
  //                "final beat count" register needed, TX reads this directly.
  //   overflow   : this packet exceeded MAX_PKT_BEATS -- diagnostic only, does
  //                NOT suppress TX (which may already be transmitting by the
  //                time this is discovered, deep in the payload region -- a
  //                real cut-through design cannot "unsend" bytes already on
  //                the wire). The transmitted packet is simply truncated to
  //                MAX_PKT_BEATS beats with a correctly-placed tlast.
  //   proc_armed : drives processing_generated.valid_in. Set once
  //                rx_beat_cnt*BEAT_BYTES >= cutoff_byte and held sticky-high
  //                for the rest of the packet (processing_generated's lkp_*
  //                inputs must stay stable from trigger until valid_out).
  //   proc_settle: one-cycle buffer set the first cycle proc_valid_out fires
  //                (gated on proc_armed too -- without that qualifier, a
  //                residual valid_out tail from a JUST-cleared previous packet
  //                could spuriously re-trigger for a new packet that hasn't
  //                reached its own cutoff yet, since valid_out lags valid_in by
  //                processing_generated's own pipeline depth). Exists because
  //                processing_generated's own out_* pass-through signals were
  //                observed (via this app's from-scratch top-level testbench --
  //                none existed before) to still reflect the PREVIOUS packet's
  //                values for one more cycle after proc_valid_out first rises,
  //                a pre-existing processing_generated timing subtlety never
  //                exercised until now.
  //   proc_committed: one-shot latch, set the cycle AFTER proc_settle -- gates
  //                write-back and arming TX so they fire exactly once per packet,
  //                using out_* only once it has genuinely settled.
  //   tx_active  : armed by proc_settle && !proc_committed && !proc_drop (the
  //                exact same pre-edge condition proc_committed itself latches
  //                on, so both fire together); cleared once TX's last beat is
  //                accepted.
  //   tx_beat_cnt: the FETCH-ISSUE pointer -- the row TX is about to read this
  //                cycle, one row ahead of what tx_out_* is currently presenting
  //                (pkt_buf_payload is real BRAM now, needing a 1-cycle registered
  //                read; see the TX section below). Issue/advance gated on
  //                tx_beat_cnt < rx_beat_cnt (never read a beat RX hasn't
  //                captured yet -- this is what makes TX correctly chase RX's
  //                arrival frontier instead of racing ahead). tlast is computed
  //                at issue-time from (rx_done||overflow), to distinguish "caught
  //                up to RX's live frontier, more beats still coming" from "this
  //                really is the last beat of the whole packet".
  //   tx_out_*   : registered output stage -- what m_axis_* actually presents,
  //                one cycle behind tx_beat_cnt's own fetch-issue.
  logic pkt_busy;
  logic rx_done;
  logic overflow;
  logic proc_armed;
  logic proc_settle;
  logic proc_committed;
  logic tx_active;
  logic [8:0] rx_beat_cnt;
  logic [8:0] tx_beat_cnt;
  logic tx_out_valid;
  logic [255:0] tx_out_data;
  logic [31:0] tx_out_keep;
  logic tx_out_last;
  // 2-stage issue/commit pipeline for TX's own fetch, needed because
  // pkt_buf_payload is real BRAM (1-cycle registered read) -- see the TX
  // section below for the full design rationale.
  logic tx_pend_valid, tx_pend_ready, tx_pend_is_hdr, tx_pend_last;
  logic [8:0] tx_pend_row;
  logic [31:0] tx_pend_keep;
  logic [8:0] payload_fetch_addr;
  logic [255:0] payload_rd_data;

  // ── Header field extraction from pkt_buf ────────────────────────────────
  //    Fields extracted using big-endian (network byte order) bit mapping.

  // ethernet — base: 0
  wire [47:0] w_ethernet_dstAddr = {pkt_buf_hdr[0], pkt_buf_hdr[1], pkt_buf_hdr[2], pkt_buf_hdr[3], pkt_buf_hdr[4], pkt_buf_hdr[5]};
  wire [47:0] w_ethernet_srcAddr = {pkt_buf_hdr[6], pkt_buf_hdr[7], pkt_buf_hdr[8], pkt_buf_hdr[9], pkt_buf_hdr[10], pkt_buf_hdr[11]};
  wire [15:0] w_ethernet_etherType = {pkt_buf_hdr[12], pkt_buf_hdr[13]};

  // ipv4 — base: 14
  wire [3:0] w_ipv4_version = pkt_buf_hdr[14][7:4];
  wire [3:0] w_ipv4_ihl = pkt_buf_hdr[14][3:0];
  wire [7:0] w_ipv4_diffserv = pkt_buf_hdr[14+1];
  wire [15:0] w_ipv4_totalLen = {pkt_buf_hdr[14+2], pkt_buf_hdr[14+3]};
  wire [15:0] w_ipv4_identification = {pkt_buf_hdr[14+4], pkt_buf_hdr[14+5]};
  wire [2:0] w_ipv4_flags = pkt_buf_hdr[14+6][7:5];
  wire [12:0] w_ipv4_fragOffset = {pkt_buf_hdr[14+6][4:0], pkt_buf_hdr[14+7]};
  wire [7:0] w_ipv4_ttl = pkt_buf_hdr[14+8];
  wire [7:0] w_ipv4_protocol = pkt_buf_hdr[14+9];
  wire [15:0] w_ipv4_hdrChecksum = {pkt_buf_hdr[14+10], pkt_buf_hdr[14+11]};
  wire [31:0] w_ipv4_srcAddr = {pkt_buf_hdr[14+12], pkt_buf_hdr[14+13], pkt_buf_hdr[14+14], pkt_buf_hdr[14+15]};
  wire [31:0] w_ipv4_dstAddr = {pkt_buf_hdr[14+16], pkt_buf_hdr[14+17], pkt_buf_hdr[14+18], pkt_buf_hdr[14+19]};

  wire [13:0] w_ipv4_hdr_bytes = {10'b0, w_ipv4_ihl} << 2;
  wire [13:0] w_tcp_base = 14 + w_ipv4_hdr_bytes;
  // tcp — base: w_tcp_base
  wire [15:0] w_tcp_srcPort = {pkt_buf_hdr[w_tcp_base], pkt_buf_hdr[w_tcp_base+1]};
  wire [15:0] w_tcp_dstPort = {pkt_buf_hdr[w_tcp_base+2], pkt_buf_hdr[w_tcp_base+3]};
  wire [31:0] w_tcp_seqNo = {pkt_buf_hdr[w_tcp_base+4], pkt_buf_hdr[w_tcp_base+5], pkt_buf_hdr[w_tcp_base+6], pkt_buf_hdr[w_tcp_base+7]};
  wire [31:0] w_tcp_ackNo = {pkt_buf_hdr[w_tcp_base+8], pkt_buf_hdr[w_tcp_base+9], pkt_buf_hdr[w_tcp_base+10], pkt_buf_hdr[w_tcp_base+11]};
  wire [3:0] w_tcp_dataOffset = pkt_buf_hdr[w_tcp_base+12][7:4];
  wire [2:0] w_tcp_res = pkt_buf_hdr[w_tcp_base+12][3:1];
  wire [2:0] w_tcp_ecn = {pkt_buf_hdr[w_tcp_base+12][0:0], pkt_buf_hdr[w_tcp_base+13][7:6]};
  wire [5:0] w_tcp_ctrl = pkt_buf_hdr[w_tcp_base+13][5:0];
  wire [15:0] w_tcp_window = {pkt_buf_hdr[w_tcp_base+14], pkt_buf_hdr[w_tcp_base+15]};
  wire [15:0] w_tcp_checksum = {pkt_buf_hdr[w_tcp_base+16], pkt_buf_hdr[w_tcp_base+17]};
  wire [15:0] w_tcp_urgentPtr = {pkt_buf_hdr[w_tcp_base+18], pkt_buf_hdr[w_tcp_base+19]};

  // ── Header validity (derived from extracted fields) ──────────────────────
  wire w_ethernet_valid = 1'b1;
  wire w_ipv4_valid = (w_ethernet_etherType == 16'h0800);
  wire w_tcp_valid = ((w_ethernet_etherType == 16'h0800) && (w_ipv4_protocol == 8'd6));

  // ── Header-region cutoff ──────────────────────────────────────────────────
  wire [13:0] w_ethernet_cutoff_term = 0 + 14;
  wire [13:0] w_ipv4_cutoff_term = (w_ethernet_etherType == 16'h0800) ? (14 + 20) : 14'd0;
  wire [13:0] w_tcp_cutoff_term = ((w_ethernet_etherType == 16'h0800) && (w_ipv4_protocol == 8'd6)) ? (w_tcp_base + 20) : 14'd0;
  wire [13:0] w_cutoff_max_1 = (w_ethernet_cutoff_term > w_ipv4_cutoff_term) ? w_ethernet_cutoff_term : w_ipv4_cutoff_term;
  wire [13:0] w_cutoff_max_2 = (w_cutoff_max_1 > w_tcp_cutoff_term) ? w_cutoff_max_1 : w_tcp_cutoff_term;
  wire [13:0] cutoff_byte = w_cutoff_max_2;

  // ── processing_generated ─────────────────────────────────────────────────
  //    Signals prefixed proc_out_* are the match-action outputs.

  wire out_ethernet_valid;
  wire [47:0] out_ethernet_dstAddr;
  wire [47:0] out_ethernet_srcAddr;
  wire [15:0] out_ethernet_etherType;
  wire out_ipv4_valid;
  wire [3:0] out_ipv4_version;
  wire [3:0] out_ipv4_ihl;
  wire [7:0] out_ipv4_diffserv;
  wire [15:0] out_ipv4_totalLen;
  wire [15:0] out_ipv4_identification;
  wire [2:0] out_ipv4_flags;
  wire [12:0] out_ipv4_fragOffset;
  wire [7:0] out_ipv4_ttl;
  wire [7:0] out_ipv4_protocol;
  wire [15:0] out_ipv4_hdrChecksum;
  wire [31:0] out_ipv4_srcAddr;
  wire [31:0] out_ipv4_dstAddr;
  wire out_tcp_valid;
  wire [15:0] out_tcp_srcPort;
  wire [15:0] out_tcp_dstPort;
  wire [31:0] out_tcp_seqNo;
  wire [31:0] out_tcp_ackNo;
  wire [3:0] out_tcp_dataOffset;
  wire [2:0] out_tcp_res;
  wire [2:0] out_tcp_ecn;
  wire [5:0] out_tcp_ctrl;
  wire [15:0] out_tcp_window;
  wire [15:0] out_tcp_checksum;
  wire [15:0] out_tcp_urgentPtr;
  wire proc_valid_out;
  wire proc_drop;

  wire ecmp_nhop_cp_query_busy;
  wire ecmp_nhop_cp_query_hit;
  wire [1:0] ecmp_nhop_cp_query_action_id;
  wire [47:0] ecmp_nhop_cp_query_p_nhop_dmac;
  wire [31:0] ecmp_nhop_cp_query_p_nhop_ipv4;
  wire [8:0] ecmp_nhop_cp_query_p_port;
  wire send_frame_cp_query_busy;
  wire send_frame_cp_query_hit;
  wire [1:0] send_frame_cp_query_action_id;
  wire [47:0] send_frame_cp_query_p_smac;


  // ── AXI4-Lite staging registers ─────────────────────────────────────────
  logic [5:0] r_ecmp_group_cp_wr_idx;
  logic [1:0] r_ecmp_group_cp_wr_action;
  logic [31:0] r_ecmp_group_cp_wr_key_dstAddr;
  logic [5:0] r_ecmp_group_cp_wr_pfx_len;
  logic [13:0] r_ecmp_group_cp_wr_p_ecmp_base;
  logic [15:0] r_ecmp_group_cp_wr_p_ecmp_mask;
  logic [3:0] r_ecmp_nhop_cp_wr_idx;
  logic [1:0] r_ecmp_nhop_cp_wr_action;
  logic [13:0] r_ecmp_nhop_cp_wr_key_ecmp_select;
  logic [47:0] r_ecmp_nhop_cp_wr_p_nhop_dmac;
  logic [31:0] r_ecmp_nhop_cp_wr_p_nhop_ipv4;
  logic [8:0] r_ecmp_nhop_cp_wr_p_port;
  logic [13:0] r_ecmp_nhop_cp_query_key_ecmp_select;
  logic r_ecmp_nhop_cp_query_del;
  logic [3:0] r_send_frame_cp_wr_idx;
  logic [1:0] r_send_frame_cp_wr_action;
  logic [8:0] r_send_frame_cp_wr_key_egress_port;
  logic [47:0] r_send_frame_cp_wr_p_smac;
  logic [8:0] r_send_frame_cp_query_key_egress_port;
  logic r_send_frame_cp_query_del;
  logic r_ecmp_group_cp_wr_en;
  logic r_ecmp_nhop_cp_wr_en;
  logic r_ecmp_nhop_cp_query_en;
  logic r_send_frame_cp_wr_en;
  logic r_send_frame_cp_query_en;

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
      14'd70: pending_commit_busy = ecmp_nhop_cp_query_busy;
      14'd72: pending_commit_busy = ecmp_nhop_cp_query_busy;
      14'd73: pending_commit_busy = ecmp_nhop_cp_query_busy;
      14'd132: pending_commit_busy = send_frame_cp_query_busy;
      14'd134: pending_commit_busy = send_frame_cp_query_busy;
      14'd135: pending_commit_busy = send_frame_cp_query_busy;
      default: pending_commit_busy = 1'b0;
    endcase
  end
  assign s_axil_wready = (axil_st == AXIL_WDATA) && !pending_commit_busy;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      axil_st <= AXIL_IDLE;
      r_ecmp_group_cp_wr_en <= 1'b0;
      r_ecmp_nhop_cp_wr_en <= 1'b0;
      r_ecmp_nhop_cp_query_en <= 1'b0;
      r_send_frame_cp_wr_en <= 1'b0;
      r_send_frame_cp_query_en <= 1'b0;
    end else begin
      r_ecmp_group_cp_wr_en <= 1'b0;
      r_ecmp_nhop_cp_wr_en <= 1'b0;
      r_ecmp_nhop_cp_query_en <= 1'b0;
      r_send_frame_cp_wr_en <= 1'b0;
      r_send_frame_cp_query_en <= 1'b0;
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
              14'd0: r_ecmp_group_cp_wr_idx <= s_axil_wdata[5:0]; // wr_idx
              14'd1: r_ecmp_group_cp_wr_action <= s_axil_wdata[1:0]; // wr_action
              14'd2: r_ecmp_group_cp_wr_key_dstAddr <= s_axil_wdata[31:0]; // key_dstAddr
              14'd3: r_ecmp_group_cp_wr_pfx_len <= s_axil_wdata[5:0]; // wr_pfx_len
              14'd4: r_ecmp_group_cp_wr_p_ecmp_base <= s_axil_wdata[13:0]; // p_ecmp_base
              14'd5: r_ecmp_group_cp_wr_p_ecmp_mask <= s_axil_wdata[15:0]; // p_ecmp_mask
              14'd6: r_ecmp_group_cp_wr_en <= 1'b1; // ecmp_group commit
              14'd64: r_ecmp_nhop_cp_wr_idx <= s_axil_wdata[3:0]; // wr_idx
              14'd65: r_ecmp_nhop_cp_wr_action <= s_axil_wdata[1:0]; // wr_action
              14'd66: r_ecmp_nhop_cp_wr_key_ecmp_select <= s_axil_wdata[13:0]; // key_ecmp_select
              14'd67: r_ecmp_nhop_cp_wr_p_nhop_dmac <= s_axil_wdata[31:0]; // p_nhop_dmac
              14'd68: r_ecmp_nhop_cp_wr_p_nhop_ipv4 <= s_axil_wdata[31:0]; // p_nhop_ipv4
              14'd69: r_ecmp_nhop_cp_wr_p_port <= s_axil_wdata[8:0]; // p_port
              14'd70: r_ecmp_nhop_cp_wr_en <= 1'b1; // ecmp_nhop commit
              14'd71: r_ecmp_nhop_cp_query_key_ecmp_select <= s_axil_wdata[13:0]; // query_key_ecmp_select
              14'd72: begin r_ecmp_nhop_cp_query_en <= 1'b1; r_ecmp_nhop_cp_query_del <= 1'b0; end // ecmp_nhop query
              14'd73: begin r_ecmp_nhop_cp_query_en <= 1'b1; r_ecmp_nhop_cp_query_del <= 1'b1; end // ecmp_nhop delete
              14'd128: r_send_frame_cp_wr_idx <= s_axil_wdata[3:0]; // wr_idx
              14'd129: r_send_frame_cp_wr_action <= s_axil_wdata[1:0]; // wr_action
              14'd130: r_send_frame_cp_wr_key_egress_port <= s_axil_wdata[8:0]; // key_egress_port
              14'd131: r_send_frame_cp_wr_p_smac <= s_axil_wdata[31:0]; // p_smac
              14'd132: r_send_frame_cp_wr_en <= 1'b1; // send_frame commit
              14'd133: r_send_frame_cp_query_key_egress_port <= s_axil_wdata[8:0]; // query_key_egress_port
              14'd134: begin r_send_frame_cp_query_en <= 1'b1; r_send_frame_cp_query_del <= 1'b0; end // send_frame query
              14'd135: begin r_send_frame_cp_query_en <= 1'b1; r_send_frame_cp_query_del <= 1'b1; end // send_frame delete
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
              14'd74: r_rdata <= {30'd0, ecmp_nhop_cp_query_hit, ecmp_nhop_cp_query_busy}; // ecmp_nhop query_status
              14'd75: r_rdata <= {30'd0, ecmp_nhop_cp_query_action_id}; // ecmp_nhop query_action_id
              14'd76: r_rdata <= ecmp_nhop_cp_query_p_nhop_dmac; // ecmp_nhop query_p_nhop_dmac
              14'd77: r_rdata <= ecmp_nhop_cp_query_p_nhop_ipv4; // ecmp_nhop query_p_nhop_ipv4
              14'd78: r_rdata <= {23'd0, ecmp_nhop_cp_query_p_port}; // ecmp_nhop query_p_port
              14'd136: r_rdata <= {30'd0, send_frame_cp_query_hit, send_frame_cp_query_busy}; // send_frame query_status
              14'd137: r_rdata <= {30'd0, send_frame_cp_query_action_id}; // send_frame query_action_id
              14'd138: r_rdata <= send_frame_cp_query_p_smac; // send_frame query_p_smac
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

  wire [5:0] ecmp_group_cp_wr_idx = r_ecmp_group_cp_wr_idx;
  wire [1:0] ecmp_group_cp_wr_action = r_ecmp_group_cp_wr_action;
  wire [31:0] ecmp_group_cp_wr_key_dstAddr = r_ecmp_group_cp_wr_key_dstAddr;
  wire [5:0] ecmp_group_cp_wr_pfx_len = r_ecmp_group_cp_wr_pfx_len;
  wire [13:0] ecmp_group_cp_wr_p_ecmp_base = r_ecmp_group_cp_wr_p_ecmp_base;
  wire [15:0] ecmp_group_cp_wr_p_ecmp_mask = r_ecmp_group_cp_wr_p_ecmp_mask;
  wire ecmp_group_cp_wr_en = r_ecmp_group_cp_wr_en;
  wire ecmp_group_hit_out;
  wire [3:0] ecmp_nhop_cp_wr_idx = r_ecmp_nhop_cp_wr_idx;
  wire [1:0] ecmp_nhop_cp_wr_action = r_ecmp_nhop_cp_wr_action;
  wire [13:0] ecmp_nhop_cp_wr_key_ecmp_select = r_ecmp_nhop_cp_wr_key_ecmp_select;
  wire [47:0] ecmp_nhop_cp_wr_p_nhop_dmac = r_ecmp_nhop_cp_wr_p_nhop_dmac;
  wire [31:0] ecmp_nhop_cp_wr_p_nhop_ipv4 = r_ecmp_nhop_cp_wr_p_nhop_ipv4;
  wire [8:0] ecmp_nhop_cp_wr_p_port = r_ecmp_nhop_cp_wr_p_port;
  wire ecmp_nhop_cp_wr_en = r_ecmp_nhop_cp_wr_en;
  wire [13:0] ecmp_nhop_cp_query_key_ecmp_select = r_ecmp_nhop_cp_query_key_ecmp_select;
  wire ecmp_nhop_cp_query_en  = r_ecmp_nhop_cp_query_en;
  wire ecmp_nhop_cp_query_del = r_ecmp_nhop_cp_query_del;
  wire ecmp_nhop_hit_out;
  wire [3:0] send_frame_cp_wr_idx = r_send_frame_cp_wr_idx;
  wire [1:0] send_frame_cp_wr_action = r_send_frame_cp_wr_action;
  wire [8:0] send_frame_cp_wr_key_egress_port = r_send_frame_cp_wr_key_egress_port;
  wire [47:0] send_frame_cp_wr_p_smac = r_send_frame_cp_wr_p_smac;
  wire send_frame_cp_wr_en = r_send_frame_cp_wr_en;
  wire [8:0] send_frame_cp_query_key_egress_port = r_send_frame_cp_query_key_egress_port;
  wire send_frame_cp_query_en  = r_send_frame_cp_query_en;
  wire send_frame_cp_query_del = r_send_frame_cp_query_del;
  wire send_frame_hit_out;

  processing_generated u_proc (
    .clk       (clk),
    .rst_n     (rst_n),
    .valid_in  (proc_armed),
    .ethernet_valid     (w_ethernet_valid),
    .ipv4_valid     (w_ipv4_valid),
    .tcp_valid     (w_tcp_valid),
    .ethernet_dstAddr  (w_ethernet_dstAddr),
    .ethernet_srcAddr  (w_ethernet_srcAddr),
    .ethernet_etherType  (w_ethernet_etherType),
    .ipv4_version  (w_ipv4_version),
    .ipv4_ihl  (w_ipv4_ihl),
    .ipv4_diffserv  (w_ipv4_diffserv),
    .ipv4_totalLen  (w_ipv4_totalLen),
    .ipv4_identification  (w_ipv4_identification),
    .ipv4_flags  (w_ipv4_flags),
    .ipv4_fragOffset  (w_ipv4_fragOffset),
    .ipv4_ttl  (w_ipv4_ttl),
    .ipv4_protocol  (w_ipv4_protocol),
    .ipv4_hdrChecksum  (w_ipv4_hdrChecksum),
    .ipv4_srcAddr  (w_ipv4_srcAddr),
    .ipv4_dstAddr  (w_ipv4_dstAddr),
    .tcp_srcPort  (w_tcp_srcPort),
    .tcp_dstPort  (w_tcp_dstPort),
    .tcp_seqNo  (w_tcp_seqNo),
    .tcp_ackNo  (w_tcp_ackNo),
    .tcp_dataOffset  (w_tcp_dataOffset),
    .tcp_res  (w_tcp_res),
    .tcp_ecn  (w_tcp_ecn),
    .tcp_ctrl  (w_tcp_ctrl),
    .tcp_window  (w_tcp_window),
    .tcp_checksum  (w_tcp_checksum),
    .tcp_urgentPtr  (w_tcp_urgentPtr),
    .out_ethernet_valid     (out_ethernet_valid),
    .out_ipv4_valid     (out_ipv4_valid),
    .out_tcp_valid     (out_tcp_valid),
    .out_ethernet_dstAddr  (out_ethernet_dstAddr),
    .out_ethernet_srcAddr  (out_ethernet_srcAddr),
    .out_ethernet_etherType  (out_ethernet_etherType),
    .out_ipv4_version  (out_ipv4_version),
    .out_ipv4_ihl  (out_ipv4_ihl),
    .out_ipv4_diffserv  (out_ipv4_diffserv),
    .out_ipv4_totalLen  (out_ipv4_totalLen),
    .out_ipv4_identification  (out_ipv4_identification),
    .out_ipv4_flags  (out_ipv4_flags),
    .out_ipv4_fragOffset  (out_ipv4_fragOffset),
    .out_ipv4_ttl  (out_ipv4_ttl),
    .out_ipv4_protocol  (out_ipv4_protocol),
    .out_ipv4_hdrChecksum  (out_ipv4_hdrChecksum),
    .out_ipv4_srcAddr  (out_ipv4_srcAddr),
    .out_ipv4_dstAddr  (out_ipv4_dstAddr),
    .out_tcp_srcPort  (out_tcp_srcPort),
    .out_tcp_dstPort  (out_tcp_dstPort),
    .out_tcp_seqNo  (out_tcp_seqNo),
    .out_tcp_ackNo  (out_tcp_ackNo),
    .out_tcp_dataOffset  (out_tcp_dataOffset),
    .out_tcp_res  (out_tcp_res),
    .out_tcp_ecn  (out_tcp_ecn),
    .out_tcp_ctrl  (out_tcp_ctrl),
    .out_tcp_window  (out_tcp_window),
    .out_tcp_checksum  (out_tcp_checksum),
    .out_tcp_urgentPtr  (out_tcp_urgentPtr),
    .ecmp_group_cp_wr_en  (ecmp_group_cp_wr_en),
    .ecmp_group_cp_wr_idx (ecmp_group_cp_wr_idx),
    .ecmp_group_cp_wr_action (ecmp_group_cp_wr_action),
    .ecmp_group_cp_wr_key_dstAddr (ecmp_group_cp_wr_key_dstAddr),
    .ecmp_group_cp_wr_pfx_len (ecmp_group_cp_wr_pfx_len),
    .ecmp_group_cp_wr_p_ecmp_base (ecmp_group_cp_wr_p_ecmp_base),
    .ecmp_group_cp_wr_p_ecmp_mask (ecmp_group_cp_wr_p_ecmp_mask),
    .ecmp_group_hit_out  (ecmp_group_hit_out),
    .ecmp_nhop_cp_wr_en  (ecmp_nhop_cp_wr_en),
    .ecmp_nhop_cp_wr_idx (ecmp_nhop_cp_wr_idx),
    .ecmp_nhop_cp_wr_action (ecmp_nhop_cp_wr_action),
    .ecmp_nhop_cp_wr_key_ecmp_select (ecmp_nhop_cp_wr_key_ecmp_select),
    .ecmp_nhop_cp_wr_p_nhop_dmac (ecmp_nhop_cp_wr_p_nhop_dmac),
    .ecmp_nhop_cp_wr_p_nhop_ipv4 (ecmp_nhop_cp_wr_p_nhop_ipv4),
    .ecmp_nhop_cp_wr_p_port (ecmp_nhop_cp_wr_p_port),
    .ecmp_nhop_cp_query_key_ecmp_select (ecmp_nhop_cp_query_key_ecmp_select),
    .ecmp_nhop_cp_query_en  (ecmp_nhop_cp_query_en),
    .ecmp_nhop_cp_query_del (ecmp_nhop_cp_query_del),
    .ecmp_nhop_cp_query_busy (ecmp_nhop_cp_query_busy),
    .ecmp_nhop_cp_query_hit  (ecmp_nhop_cp_query_hit),
    .ecmp_nhop_cp_query_action_id (ecmp_nhop_cp_query_action_id),
    .ecmp_nhop_cp_query_p_nhop_dmac (ecmp_nhop_cp_query_p_nhop_dmac),
    .ecmp_nhop_cp_query_p_nhop_ipv4 (ecmp_nhop_cp_query_p_nhop_ipv4),
    .ecmp_nhop_cp_query_p_port (ecmp_nhop_cp_query_p_port),
    .ecmp_nhop_hit_out  (ecmp_nhop_hit_out),
    .send_frame_cp_wr_en  (send_frame_cp_wr_en),
    .send_frame_cp_wr_idx (send_frame_cp_wr_idx),
    .send_frame_cp_wr_action (send_frame_cp_wr_action),
    .send_frame_cp_wr_key_egress_port (send_frame_cp_wr_key_egress_port),
    .send_frame_cp_wr_p_smac (send_frame_cp_wr_p_smac),
    .send_frame_cp_query_key_egress_port (send_frame_cp_query_key_egress_port),
    .send_frame_cp_query_en  (send_frame_cp_query_en),
    .send_frame_cp_query_del (send_frame_cp_query_del),
    .send_frame_cp_query_busy (send_frame_cp_query_busy),
    .send_frame_cp_query_hit  (send_frame_cp_query_hit),
    .send_frame_cp_query_action_id (send_frame_cp_query_action_id),
    .send_frame_cp_query_p_smac (send_frame_cp_query_p_smac),
    .send_frame_hit_out  (send_frame_hit_out),
    .valid_out (proc_valid_out),
    .drop      (proc_drop)
  );

  // ── Cross-block wiring ───────────────────────────────────────────────────
  // A new packet may start only once the current one has drained from BOTH
  // RX and TX (the single-packet-in-flight invariant -- avoids needing a
  // double-buffered pkt_buf).
  wire pkt_ready_to_clear = pkt_busy && rx_done && proc_committed && !tx_active;

  // ── RX (ingest) ──────────────────────────────────────────────────────────
  assign s_axis_tready = !rx_done;
  wire accept_beat = s_axis_tvalid && s_axis_tready;
  wire accept_payload_beat = accept_beat && (rx_beat_cnt >= HDR_MAX_BEATS) && (rx_beat_cnt < MAX_PKT_BEATS);

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      pkt_busy    <= 1'b0;
      rx_done     <= 1'b0;
      rx_beat_cnt <= '0;
      overflow    <= 1'b0;
    end else begin
      if (accept_beat) begin
        pkt_busy <= 1'b1;
        if (rx_beat_cnt < HDR_MAX_BEATS) begin
          pkt_keep[rx_beat_cnt] <= s_axis_tkeep;
          rx_beat_cnt <= rx_beat_cnt + 9'd1;
        end else if (rx_beat_cnt < MAX_PKT_BEATS) begin
          // pkt_buf_payload's own byte-enable write lives in a separate,
          // dedicated always_ff below (accept_payload_beat) -- Quartus's RAM
          // inference template was found not to match when the byte-enable
          // write is nested two if-levels deep (accept_beat -> this branch);
          // one level (a single derived enable wire) is required.
          pkt_keep[rx_beat_cnt] <= s_axis_tkeep;
          rx_beat_cnt <= rx_beat_cnt + 9'd1;
        end else begin
          // Beyond MAX_PKT_BEATS: stop capturing (memory-safety truncation,
          // not a drop -- TX may already be transmitting this packet by now,
          // see the `overflow` declaration comment above). rx_beat_cnt stays
          // frozen at MAX_PKT_BEATS, which TX will correctly treat as the
          // final count once rx_done latches below.
          overflow <= 1'b1;
        end
        if (s_axis_tlast) rx_done <= 1'b1;
      end
      if (pkt_ready_to_clear) begin
        pkt_busy    <= 1'b0;
        rx_done     <= 1'b0;
        rx_beat_cnt <= '0;
        overflow    <= 1'b0;
      end
    end
  end

  // pkt_buf_payload's only writer, isolated in its own always_ff with a
  // single derived enable and no other nesting -- see accept_payload_beat
  // above and the comment in the RX block for why this had to be pulled out
  // (Quartus's byte-enable RAM inference template requires this shape;
  // nested two if-levels deep inside RX's own always_ff, it silently failed
  // to infer -- confirmed via a real Quartus run's explicit "can't infer
  // memory... with attribute M9K" warning).
  always_ff @(posedge clk) begin
    if (accept_payload_beat) begin
      if (s_axis_tkeep[0]) pkt_buf_payload[rx_beat_cnt - HDR_MAX_BEATS][0] <= s_axis_tdata[0 +: 8];
      if (s_axis_tkeep[1]) pkt_buf_payload[rx_beat_cnt - HDR_MAX_BEATS][1] <= s_axis_tdata[8 +: 8];
      if (s_axis_tkeep[2]) pkt_buf_payload[rx_beat_cnt - HDR_MAX_BEATS][2] <= s_axis_tdata[16 +: 8];
      if (s_axis_tkeep[3]) pkt_buf_payload[rx_beat_cnt - HDR_MAX_BEATS][3] <= s_axis_tdata[24 +: 8];
      if (s_axis_tkeep[4]) pkt_buf_payload[rx_beat_cnt - HDR_MAX_BEATS][4] <= s_axis_tdata[32 +: 8];
      if (s_axis_tkeep[5]) pkt_buf_payload[rx_beat_cnt - HDR_MAX_BEATS][5] <= s_axis_tdata[40 +: 8];
      if (s_axis_tkeep[6]) pkt_buf_payload[rx_beat_cnt - HDR_MAX_BEATS][6] <= s_axis_tdata[48 +: 8];
      if (s_axis_tkeep[7]) pkt_buf_payload[rx_beat_cnt - HDR_MAX_BEATS][7] <= s_axis_tdata[56 +: 8];
      if (s_axis_tkeep[8]) pkt_buf_payload[rx_beat_cnt - HDR_MAX_BEATS][8] <= s_axis_tdata[64 +: 8];
      if (s_axis_tkeep[9]) pkt_buf_payload[rx_beat_cnt - HDR_MAX_BEATS][9] <= s_axis_tdata[72 +: 8];
      if (s_axis_tkeep[10]) pkt_buf_payload[rx_beat_cnt - HDR_MAX_BEATS][10] <= s_axis_tdata[80 +: 8];
      if (s_axis_tkeep[11]) pkt_buf_payload[rx_beat_cnt - HDR_MAX_BEATS][11] <= s_axis_tdata[88 +: 8];
      if (s_axis_tkeep[12]) pkt_buf_payload[rx_beat_cnt - HDR_MAX_BEATS][12] <= s_axis_tdata[96 +: 8];
      if (s_axis_tkeep[13]) pkt_buf_payload[rx_beat_cnt - HDR_MAX_BEATS][13] <= s_axis_tdata[104 +: 8];
      if (s_axis_tkeep[14]) pkt_buf_payload[rx_beat_cnt - HDR_MAX_BEATS][14] <= s_axis_tdata[112 +: 8];
      if (s_axis_tkeep[15]) pkt_buf_payload[rx_beat_cnt - HDR_MAX_BEATS][15] <= s_axis_tdata[120 +: 8];
      if (s_axis_tkeep[16]) pkt_buf_payload[rx_beat_cnt - HDR_MAX_BEATS][16] <= s_axis_tdata[128 +: 8];
      if (s_axis_tkeep[17]) pkt_buf_payload[rx_beat_cnt - HDR_MAX_BEATS][17] <= s_axis_tdata[136 +: 8];
      if (s_axis_tkeep[18]) pkt_buf_payload[rx_beat_cnt - HDR_MAX_BEATS][18] <= s_axis_tdata[144 +: 8];
      if (s_axis_tkeep[19]) pkt_buf_payload[rx_beat_cnt - HDR_MAX_BEATS][19] <= s_axis_tdata[152 +: 8];
      if (s_axis_tkeep[20]) pkt_buf_payload[rx_beat_cnt - HDR_MAX_BEATS][20] <= s_axis_tdata[160 +: 8];
      if (s_axis_tkeep[21]) pkt_buf_payload[rx_beat_cnt - HDR_MAX_BEATS][21] <= s_axis_tdata[168 +: 8];
      if (s_axis_tkeep[22]) pkt_buf_payload[rx_beat_cnt - HDR_MAX_BEATS][22] <= s_axis_tdata[176 +: 8];
      if (s_axis_tkeep[23]) pkt_buf_payload[rx_beat_cnt - HDR_MAX_BEATS][23] <= s_axis_tdata[184 +: 8];
      if (s_axis_tkeep[24]) pkt_buf_payload[rx_beat_cnt - HDR_MAX_BEATS][24] <= s_axis_tdata[192 +: 8];
      if (s_axis_tkeep[25]) pkt_buf_payload[rx_beat_cnt - HDR_MAX_BEATS][25] <= s_axis_tdata[200 +: 8];
      if (s_axis_tkeep[26]) pkt_buf_payload[rx_beat_cnt - HDR_MAX_BEATS][26] <= s_axis_tdata[208 +: 8];
      if (s_axis_tkeep[27]) pkt_buf_payload[rx_beat_cnt - HDR_MAX_BEATS][27] <= s_axis_tdata[216 +: 8];
      if (s_axis_tkeep[28]) pkt_buf_payload[rx_beat_cnt - HDR_MAX_BEATS][28] <= s_axis_tdata[224 +: 8];
      if (s_axis_tkeep[29]) pkt_buf_payload[rx_beat_cnt - HDR_MAX_BEATS][29] <= s_axis_tdata[232 +: 8];
      if (s_axis_tkeep[30]) pkt_buf_payload[rx_beat_cnt - HDR_MAX_BEATS][30] <= s_axis_tdata[240 +: 8];
      if (s_axis_tkeep[31]) pkt_buf_payload[rx_beat_cnt - HDR_MAX_BEATS][31] <= s_axis_tdata[248 +: 8];
    end
  end

  // ── PROC (match-action trigger + write-back) ────────────────────────────
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      proc_armed     <= 1'b0;
      proc_settle    <= 1'b0;
      proc_committed <= 1'b0;
    end else begin
      // Trigger as soon as the header region has fully arrived -- not
      // waiting for the whole packet. This is the cut-through trigger.
      // Also trigger on rx_done alone (packet ended before reaching the
      // theoretical cutoff): once RX has finished, no more bytes will EVER
      // arrive, so waiting further would deadlock -- this is a real case,
      // not just defensive, since header-region sizing accounts for the
      // worst-case runtime length of every var_pred field (see
      // _worst_case_hdr_bytes) and can legitimately exceed a specific
      // packet's actual total length.
      if (!proc_armed && pkt_busy &&
          ((rx_beat_cnt * BEAT_BYTES >= cutoff_byte) || rx_done)) begin
        proc_armed <= 1'b1;
      end
      // proc_armed is required here (not just !proc_committed) so a residual
      // valid_out tail from a just-cleared previous packet can never be
      // mistaken for this packet's own result -- processing_generated's
      // valid_out lags valid_in by its own pipeline depth, so it can still
      // read high for a few cycles after proc_armed drops back to 0.
      //
      // proc_settle: a one-cycle buffer between first observing proc_valid_out
      // and actually reading out_* / committing write-back. processing_generated's
      // own out_* pass-through signals are staged (forwarded through the same
      // number of pipeline registers as valid_out itself) but were observed
      // (via a from-scratch top-level testbench -- this app never had one before)
      // to still reflect the PREVIOUS packet's values for one more cycle after
      // proc_valid_out first rises, specifically when valid_in is held
      // continuously high across back-to-back packets (as this design does,
      // and as the direct-mapped store-and-forward design also always did --
      // this is a pre-existing processing_generated timing subtlety, not
      // something this redesign introduces; it was simply never exercised
      // before, since no integrated top-level testbench existed). Waiting one
      // extra cycle before committing is a real, necessary fix, not a stylistic
      // choice -- confirmed empirically against the actual generated RTL.
      if (proc_armed && proc_valid_out && !proc_settle && !proc_committed) begin
        proc_settle <= 1'b1;
      end
      if (proc_settle && !proc_committed) begin
        proc_committed <= 1'b1;
      end
      if (pkt_ready_to_clear) begin
        proc_armed     <= 1'b0;
        proc_settle    <= 1'b0;
        proc_committed <= 1'b0;
      end
    end
  end

  // ── HDR write arbitration (RX ingest vs PROC write-back) ────────────────
  // pkt_buf_hdr has exactly one driver: this block. RX header-capture and
  // PROC write-back both target pkt_buf_hdr -- two independent always_ff
  // blocks driving the same net is tolerated by iverilog/xsim but rejected
  // by Quartus/Cyclone IV E synthesis ("multiple constant drivers"), so both
  // writes must live in one block. The two conditions are verified disjoint
  // for every packet shape reachable by this app -- see the simulation-only
  // assertion below, which fails loudly (rather than silently dropping one
  // side's write) if that ever stops holding for a future app/config.
  always_ff @(posedge clk) begin
    if (accept_beat && rx_beat_cnt < HDR_MAX_BEATS) begin
      for (int i = 0; i < 32; i++)
        if (s_axis_tkeep[i])
          pkt_buf_hdr[rx_beat_cnt * 32 + i] <= s_axis_tdata[i*8 +: 8];
    end else if (proc_settle && !proc_committed && !proc_drop) begin
      pkt_buf_hdr[0] <= out_ethernet_dstAddr[47:40];
      pkt_buf_hdr[1] <= out_ethernet_dstAddr[39:32];
      pkt_buf_hdr[2] <= out_ethernet_dstAddr[31:24];
      pkt_buf_hdr[3] <= out_ethernet_dstAddr[23:16];
      pkt_buf_hdr[4] <= out_ethernet_dstAddr[15:8];
      pkt_buf_hdr[5] <= out_ethernet_dstAddr[7:0];
      pkt_buf_hdr[6] <= out_ethernet_srcAddr[47:40];
      pkt_buf_hdr[7] <= out_ethernet_srcAddr[39:32];
      pkt_buf_hdr[8] <= out_ethernet_srcAddr[31:24];
      pkt_buf_hdr[9] <= out_ethernet_srcAddr[23:16];
      pkt_buf_hdr[10] <= out_ethernet_srcAddr[15:8];
      pkt_buf_hdr[11] <= out_ethernet_srcAddr[7:0];
      pkt_buf_hdr[12] <= out_ethernet_etherType[15:8];
      pkt_buf_hdr[13] <= out_ethernet_etherType[7:0];
      if (out_ipv4_valid) begin
          pkt_buf_hdr[14] <= {out_ipv4_version, out_ipv4_ihl};
          pkt_buf_hdr[14+1] <= out_ipv4_diffserv;
          pkt_buf_hdr[14+2] <= out_ipv4_totalLen[15:8];
          pkt_buf_hdr[14+3] <= out_ipv4_totalLen[7:0];
          pkt_buf_hdr[14+4] <= out_ipv4_identification[15:8];
          pkt_buf_hdr[14+5] <= out_ipv4_identification[7:0];
          pkt_buf_hdr[14+6] <= {out_ipv4_flags, out_ipv4_fragOffset[12:8]};
          pkt_buf_hdr[14+7] <= out_ipv4_fragOffset[7:0];
          pkt_buf_hdr[14+8] <= out_ipv4_ttl;
          pkt_buf_hdr[14+9] <= out_ipv4_protocol;
          pkt_buf_hdr[14+10] <= out_ipv4_hdrChecksum[15:8];
          pkt_buf_hdr[14+11] <= out_ipv4_hdrChecksum[7:0];
          pkt_buf_hdr[14+12] <= out_ipv4_srcAddr[31:24];
          pkt_buf_hdr[14+13] <= out_ipv4_srcAddr[23:16];
          pkt_buf_hdr[14+14] <= out_ipv4_srcAddr[15:8];
          pkt_buf_hdr[14+15] <= out_ipv4_srcAddr[7:0];
          pkt_buf_hdr[14+16] <= out_ipv4_dstAddr[31:24];
          pkt_buf_hdr[14+17] <= out_ipv4_dstAddr[23:16];
          pkt_buf_hdr[14+18] <= out_ipv4_dstAddr[15:8];
          pkt_buf_hdr[14+19] <= out_ipv4_dstAddr[7:0];
      end
      if (out_tcp_valid) begin
          pkt_buf_hdr[w_tcp_base] <= out_tcp_srcPort[15:8];
          pkt_buf_hdr[w_tcp_base+1] <= out_tcp_srcPort[7:0];
          pkt_buf_hdr[w_tcp_base+2] <= out_tcp_dstPort[15:8];
          pkt_buf_hdr[w_tcp_base+3] <= out_tcp_dstPort[7:0];
          pkt_buf_hdr[w_tcp_base+4] <= out_tcp_seqNo[31:24];
          pkt_buf_hdr[w_tcp_base+5] <= out_tcp_seqNo[23:16];
          pkt_buf_hdr[w_tcp_base+6] <= out_tcp_seqNo[15:8];
          pkt_buf_hdr[w_tcp_base+7] <= out_tcp_seqNo[7:0];
          pkt_buf_hdr[w_tcp_base+8] <= out_tcp_ackNo[31:24];
          pkt_buf_hdr[w_tcp_base+9] <= out_tcp_ackNo[23:16];
          pkt_buf_hdr[w_tcp_base+10] <= out_tcp_ackNo[15:8];
          pkt_buf_hdr[w_tcp_base+11] <= out_tcp_ackNo[7:0];
          pkt_buf_hdr[w_tcp_base+12] <= {out_tcp_dataOffset, out_tcp_res, out_tcp_ecn[2]};
          pkt_buf_hdr[w_tcp_base+13] <= {out_tcp_ecn[1:0], out_tcp_ctrl};
          pkt_buf_hdr[w_tcp_base+14] <= out_tcp_window[15:8];
          pkt_buf_hdr[w_tcp_base+15] <= out_tcp_window[7:0];
          pkt_buf_hdr[w_tcp_base+16] <= out_tcp_checksum[15:8];
          pkt_buf_hdr[w_tcp_base+17] <= out_tcp_checksum[7:0];
          pkt_buf_hdr[w_tcp_base+18] <= out_tcp_urgentPtr[15:8];
          pkt_buf_hdr[w_tcp_base+19] <= out_tcp_urgentPtr[7:0];
      end
    end
  `ifndef SYNTHESIS
    if (accept_beat && rx_beat_cnt < HDR_MAX_BEATS &&
        proc_settle && !proc_committed && !proc_drop)
      $error("pkt_buf_hdr write collision: RX and PROC write-back fired the same cycle");
  `endif
  end

  // ── TX (egress) ──────────────────────────────────────────────────────────
  // pkt_buf_payload is real BRAM (1-cycle registered read), so TX needs a real
  // issue/commit pipeline, not a single same-cycle read -- pkt_buf_hdr stays a
  // plain register array (fresh combinational read, no latency) but is routed
  // through the SAME 2-cycle pipeline for uniformity/simplicity rather than
  // special-cased, at the cost of one harmless extra cycle for header beats.
  //
  // Stage 1 (issue, tx_beat_cnt<rx_beat_cnt gate -- same cut-through chase as
  // before): latches which row/whether-header/keep/last this beat needs, and
  // -- for the payload case -- updates payload_fetch_addr, which ONLY changes
  // on an issue (holds steady otherwise, safe to sit for however long stage 2
  // is backpressured, since the free-running read below just keeps re-settling
  // on the same correct row while it holds).
  //
  // Stage 2 (commit, gated on tx_pend_ready AND tx_pend_valid together --
  // BOTH are required, not tx_pend_ready alone): tx_pend_ready is tx_pend_valid
  // delayed by exactly one more cycle (see the shadow register below), which is
  // what guarantees payload_rd_data has caught up to payload_fetch_addr's new
  // value by the time it's consumed -- gating on tx_pend_valid alone would read
  // payload_rd_data one cycle too early (its previous, stale row). But
  // tx_pend_ready, being a plain shadow register, itself stays high for one
  // extra cycle AFTER tx_pend_valid is cleared by a commit -- gating on
  // tx_pend_ready alone let stage 2 fire a SECOND time on that trailing-high
  // cycle, re-committing the same already-consumed pend (a real, silent
  // duplicate-beat bug caught only by simulation content mismatches, not by
  // any structural warning). tx_pend_valid in the gate is what stops that.
  //
  // Non-pipelined by construction (stage 1 requires !tx_pend_valid, so a new
  // issue can never overlap an uncommitted pend) -- 2 cycles/beat instead of
  // 1, accepted for correctness/simplicity; nothing in this project asserts an
  // exact TX throughput, only loose cut-through-ordering inequalities.
  wire tx_consumed = tx_out_valid && m_axis_tready;
  wire tx_stage1_issue = !tx_pend_valid && (!tx_out_valid || tx_consumed) && tx_active && (tx_beat_cnt < rx_beat_cnt);

  always_ff @(posedge clk)
    if (tx_stage1_issue) payload_fetch_addr <= tx_beat_cnt - HDR_MAX_BEATS;

  always_ff @(posedge clk) payload_rd_data <= pkt_buf_payload[payload_fetch_addr];

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      tx_active    <= 1'b0;
      tx_beat_cnt  <= '0;
      tx_out_valid <= 1'b0;
      tx_out_data  <= '0;
      tx_out_keep  <= '0;
      tx_out_last  <= 1'b0;
      tx_pend_valid <= 1'b0;
      tx_pend_ready <= 1'b0;
    end else begin
      tx_pend_ready <= tx_pend_valid;  // unconditional shadow, one cycle behind
      // Unconditional drain-on-consume, overridden below by stage 2's own
      // tx_out_valid<=1 when it ALSO fires this same cycle (NBA "last write
      // wins" for the same signal in the same always_ff) -- without this,
      // a cycle where the current beat is consumed AND stage 1 issues a new
      // fetch (instead of stage 2 committing) would leave tx_out_valid/data
      // stuck at the just-consumed beat's stale value for another cycle,
      // presenting it a second time.
      if (tx_consumed) tx_out_valid <= 1'b0;
      // Armed on the exact same pre-edge condition that latches
      // proc_committed above (proc_settle && !proc_committed), so both fire
      // together on the true commit cycle (never the cycle write-back's own
      // commit happens on -- write-back and this arm both become visible
      // starting the next cycle, so TX only ever fetches pkt_buf_hdr/payload
      // after write-back landed).
      if (!tx_active && proc_settle && !proc_committed && !proc_drop) begin
        tx_active     <= 1'b1;
        tx_beat_cnt   <= '0;
        tx_out_valid  <= 1'b0;
        tx_pend_valid <= 1'b0;
      end else if (tx_consumed && tx_out_last) begin
        tx_active    <= 1'b0;
        tx_out_valid <= 1'b0;
      end else if (tx_pend_ready && tx_pend_valid && (!tx_out_valid || tx_consumed)) begin
        // Stage 2: commit. payload_rd_data is guaranteed fresh here -- see the
        // tx_pend_ready shadow-register comment above.
        tx_out_valid  <= 1'b1;
        tx_out_keep   <= tx_pend_keep;
        tx_out_last   <= tx_pend_last;
        if (tx_pend_is_hdr) begin
          for (int i = 0; i < 32; i++)
            tx_out_data[i*8 +: 8] <= pkt_buf_hdr[tx_pend_row * 32 + i];
        end else begin
          tx_out_data <= payload_rd_data;
        end
        tx_pend_valid <= 1'b0;
      end else if (tx_stage1_issue) begin
        // Stage 1: issue. payload_fetch_addr is updated above, same condition.
        tx_pend_valid  <= 1'b1;
        tx_pend_is_hdr <= (tx_beat_cnt < HDR_MAX_BEATS);
        tx_pend_row    <= tx_beat_cnt;
        tx_pend_keep   <= pkt_keep[tx_beat_cnt];
        tx_pend_last   <= (rx_done || overflow) && (tx_beat_cnt == rx_beat_cnt - 9'd1);
        tx_beat_cnt    <= tx_beat_cnt + 9'd1;
      end
      // (no separate "else if (tx_consumed) tx_out_valid<=0" branch needed --
      // the unconditional drain-on-consume above already covers the case
      // where none of the branches above fire: next row not yet arrived from
      // RX, so tx_out_valid correctly drops and stays a bubble.)
      if (pkt_ready_to_clear) begin
        tx_active     <= 1'b0;
        tx_beat_cnt   <= '0;
        tx_out_valid  <= 1'b0;
        tx_pend_valid <= 1'b0;
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
