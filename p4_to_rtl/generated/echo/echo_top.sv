module echo_top #(
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
    output logic [15:0] out_meta_echo_port
);

  localparam int BEAT_BYTES    = AXI_DATA_W / 8;  // 32
  localparam int MAX_PKT_BEATS = 256;
  localparam int MAX_PKT_BYTES = MAX_PKT_BEATS * BEAT_BYTES;  // 8192
  localparam int HDR_MAX_BYTES = 128;
  localparam int HDR_MAX_BEATS = 4;
  localparam int PAYLOAD_MAX_BYTES = MAX_PKT_BYTES - HDR_MAX_BYTES;  // 8064
  localparam int PAYLOAD_MAX_BEATS = PAYLOAD_MAX_BYTES / BEAT_BYTES;  // 252

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

  // eth — base: 0
  wire [47:0] w_eth_dmac = {pkt_buf_hdr[0], pkt_buf_hdr[1], pkt_buf_hdr[2], pkt_buf_hdr[3], pkt_buf_hdr[4], pkt_buf_hdr[5]};
  wire [47:0] w_eth_smac = {pkt_buf_hdr[6], pkt_buf_hdr[7], pkt_buf_hdr[8], pkt_buf_hdr[9], pkt_buf_hdr[10], pkt_buf_hdr[11]};
  wire [15:0] w_eth_type = {pkt_buf_hdr[12], pkt_buf_hdr[13]};

  // vlan_0 — base: 14
  wire [2:0] w_vlan_0_pcp = pkt_buf_hdr[14][7:5];
  wire [0:0] w_vlan_0_cfi = pkt_buf_hdr[14][4:4];
  wire [11:0] w_vlan_0_vid = {pkt_buf_hdr[14][3:0], pkt_buf_hdr[14+1]};
  wire [15:0] w_vlan_0_tpid = {pkt_buf_hdr[14+2], pkt_buf_hdr[14+3]};

  wire [13:0] w_ipv4_base = 14 + ((w_eth_type == 16'h8100) ? 4 : 0) + (((w_eth_type == 16'h8100) && (w_vlan_0_tpid == 16'h8100)) ? 4 : 0);
  // ipv4 — base: w_ipv4_base
  wire [3:0] w_ipv4_version = pkt_buf_hdr[w_ipv4_base][7:4];
  wire [3:0] w_ipv4_hdr_len = pkt_buf_hdr[w_ipv4_base][3:0];
  wire [7:0] w_ipv4_tos = pkt_buf_hdr[w_ipv4_base+1];
  wire [15:0] w_ipv4_length = {pkt_buf_hdr[w_ipv4_base+2], pkt_buf_hdr[w_ipv4_base+3]};
  wire [15:0] w_ipv4_id = {pkt_buf_hdr[w_ipv4_base+4], pkt_buf_hdr[w_ipv4_base+5]};
  wire [2:0] w_ipv4_flags = pkt_buf_hdr[w_ipv4_base+6][7:5];
  wire [12:0] w_ipv4_offset = {pkt_buf_hdr[w_ipv4_base+6][4:0], pkt_buf_hdr[w_ipv4_base+7]};
  wire [7:0] w_ipv4_ttl = pkt_buf_hdr[w_ipv4_base+8];
  wire [7:0] w_ipv4_protocol = pkt_buf_hdr[w_ipv4_base+9];
  wire [15:0] w_ipv4_hdr_chk = {pkt_buf_hdr[w_ipv4_base+10], pkt_buf_hdr[w_ipv4_base+11]};
  wire [31:0] w_ipv4_src = {pkt_buf_hdr[w_ipv4_base+12], pkt_buf_hdr[w_ipv4_base+13], pkt_buf_hdr[w_ipv4_base+14], pkt_buf_hdr[w_ipv4_base+15]};
  wire [31:0] w_ipv4_dst = {pkt_buf_hdr[w_ipv4_base+16], pkt_buf_hdr[w_ipv4_base+17], pkt_buf_hdr[w_ipv4_base+18], pkt_buf_hdr[w_ipv4_base+19]};

  wire [13:0] w_ipv4_hdr_bytes = {10'b0, w_ipv4_hdr_len} << 2;
  wire [13:0] w_ipv4opt_base = w_ipv4_base + w_ipv4_hdr_bytes;
  // ipv4opt — base: w_ipv4opt_base
  wire [319:0] w_ipv4opt_options = {pkt_buf_hdr[w_ipv4opt_base], pkt_buf_hdr[w_ipv4opt_base+1], pkt_buf_hdr[w_ipv4opt_base+2], pkt_buf_hdr[w_ipv4opt_base+3], pkt_buf_hdr[w_ipv4opt_base+4], pkt_buf_hdr[w_ipv4opt_base+5], pkt_buf_hdr[w_ipv4opt_base+6], pkt_buf_hdr[w_ipv4opt_base+7], pkt_buf_hdr[w_ipv4opt_base+8], pkt_buf_hdr[w_ipv4opt_base+9], pkt_buf_hdr[w_ipv4opt_base+10], pkt_buf_hdr[w_ipv4opt_base+11], pkt_buf_hdr[w_ipv4opt_base+12], pkt_buf_hdr[w_ipv4opt_base+13], pkt_buf_hdr[w_ipv4opt_base+14], pkt_buf_hdr[w_ipv4opt_base+15], pkt_buf_hdr[w_ipv4opt_base+16], pkt_buf_hdr[w_ipv4opt_base+17], pkt_buf_hdr[w_ipv4opt_base+18], pkt_buf_hdr[w_ipv4opt_base+19], pkt_buf_hdr[w_ipv4opt_base+20], pkt_buf_hdr[w_ipv4opt_base+21], pkt_buf_hdr[w_ipv4opt_base+22], pkt_buf_hdr[w_ipv4opt_base+23], pkt_buf_hdr[w_ipv4opt_base+24], pkt_buf_hdr[w_ipv4opt_base+25], pkt_buf_hdr[w_ipv4opt_base+26], pkt_buf_hdr[w_ipv4opt_base+27], pkt_buf_hdr[w_ipv4opt_base+28], pkt_buf_hdr[w_ipv4opt_base+29], pkt_buf_hdr[w_ipv4opt_base+30], pkt_buf_hdr[w_ipv4opt_base+31], pkt_buf_hdr[w_ipv4opt_base+32], pkt_buf_hdr[w_ipv4opt_base+33], pkt_buf_hdr[w_ipv4opt_base+34], pkt_buf_hdr[w_ipv4opt_base+35], pkt_buf_hdr[w_ipv4opt_base+36], pkt_buf_hdr[w_ipv4opt_base+37], pkt_buf_hdr[w_ipv4opt_base+38], pkt_buf_hdr[w_ipv4opt_base+39]};

  // vlan_1 — base: 18
  wire [2:0] w_vlan_1_pcp = pkt_buf_hdr[18][7:5];
  wire [0:0] w_vlan_1_cfi = pkt_buf_hdr[18][4:4];
  wire [11:0] w_vlan_1_vid = {pkt_buf_hdr[18][3:0], pkt_buf_hdr[18+1]};
  wire [15:0] w_vlan_1_tpid = {pkt_buf_hdr[18+2], pkt_buf_hdr[18+3]};

  wire [13:0] w_udp_base = w_ipv4_base + w_ipv4_hdr_bytes;
  // udp — base: w_udp_base
  wire [15:0] w_udp_src_port = {pkt_buf_hdr[w_udp_base], pkt_buf_hdr[w_udp_base+1]};
  wire [15:0] w_udp_dst_port = {pkt_buf_hdr[w_udp_base+2], pkt_buf_hdr[w_udp_base+3]};
  wire [15:0] w_udp_length = {pkt_buf_hdr[w_udp_base+4], pkt_buf_hdr[w_udp_base+5]};
  wire [15:0] w_udp_checksum = {pkt_buf_hdr[w_udp_base+6], pkt_buf_hdr[w_udp_base+7]};

  // ── Header validity (derived from extracted fields) ──────────────────────
  wire w_eth_valid = 1'b1;
  wire w_vlan_0_valid = (w_eth_type == 16'h8100);
  wire w_ipv4_valid = (((w_eth_type == 16'h0800) || ((w_eth_type == 16'h8100) && (w_vlan_0_tpid == 16'h0800))) || (((w_eth_type == 16'h8100) && (w_vlan_0_tpid == 16'h8100)) && (w_vlan_1_tpid == 16'h0800)));
  wire w_ipv4opt_valid = (((w_eth_type == 16'h0800) || ((w_eth_type == 16'h8100) && (w_vlan_0_tpid == 16'h0800))) || (((w_eth_type == 16'h8100) && (w_vlan_0_tpid == 16'h8100)) && (w_vlan_1_tpid == 16'h0800)));
  wire w_vlan_1_valid = ((w_eth_type == 16'h8100) && (w_vlan_0_tpid == 16'h8100));
  wire w_udp_valid = ((((w_eth_type == 16'h0800) || ((w_eth_type == 16'h8100) && (w_vlan_0_tpid == 16'h0800))) || (((w_eth_type == 16'h8100) && (w_vlan_0_tpid == 16'h8100)) && (w_vlan_1_tpid == 16'h0800))) && (w_ipv4_protocol == 8'h11));

  // ── Header-region cutoff ──────────────────────────────────────────────────
  wire [13:0] w_eth_cutoff_term = 0 + 14;
  wire [13:0] w_vlan_0_cutoff_term = (w_eth_type == 16'h8100) ? (14 + 4) : 14'd0;
  wire [13:0] w_ipv4_cutoff_term = (((w_eth_type == 16'h0800) || ((w_eth_type == 16'h8100) && (w_vlan_0_tpid == 16'h0800))) || (((w_eth_type == 16'h8100) && (w_vlan_0_tpid == 16'h8100)) && (w_vlan_1_tpid == 16'h0800))) ? (w_ipv4_base + 20) : 14'd0;
  wire [13:0] w_ipv4opt_cutoff_term = (((w_eth_type == 16'h0800) || ((w_eth_type == 16'h8100) && (w_vlan_0_tpid == 16'h0800))) || (((w_eth_type == 16'h8100) && (w_vlan_0_tpid == 16'h8100)) && (w_vlan_1_tpid == 16'h0800))) ? (w_ipv4opt_base + 40) : 14'd0;
  wire [13:0] w_vlan_1_cutoff_term = ((w_eth_type == 16'h8100) && (w_vlan_0_tpid == 16'h8100)) ? (18 + 4) : 14'd0;
  wire [13:0] w_udp_cutoff_term = ((((w_eth_type == 16'h0800) || ((w_eth_type == 16'h8100) && (w_vlan_0_tpid == 16'h0800))) || (((w_eth_type == 16'h8100) && (w_vlan_0_tpid == 16'h8100)) && (w_vlan_1_tpid == 16'h0800))) && (w_ipv4_protocol == 8'h11)) ? (w_udp_base + 8) : 14'd0;
  wire [13:0] w_cutoff_max_1 = (w_eth_cutoff_term > w_vlan_0_cutoff_term) ? w_eth_cutoff_term : w_vlan_0_cutoff_term;
  wire [13:0] w_cutoff_max_2 = (w_cutoff_max_1 > w_ipv4_cutoff_term) ? w_cutoff_max_1 : w_ipv4_cutoff_term;
  wire [13:0] w_cutoff_max_3 = (w_cutoff_max_2 > w_ipv4opt_cutoff_term) ? w_cutoff_max_2 : w_ipv4opt_cutoff_term;
  wire [13:0] w_cutoff_max_4 = (w_cutoff_max_3 > w_vlan_1_cutoff_term) ? w_cutoff_max_3 : w_vlan_1_cutoff_term;
  wire [13:0] w_cutoff_max_5 = (w_cutoff_max_4 > w_udp_cutoff_term) ? w_cutoff_max_4 : w_udp_cutoff_term;
  wire [13:0] cutoff_byte = w_cutoff_max_5;

  // ── processing_generated ─────────────────────────────────────────────────
  //    Signals prefixed proc_out_* are the match-action outputs.

  wire out_eth_valid;
  wire [47:0] out_eth_dmac;
  wire [47:0] out_eth_smac;
  wire [15:0] out_eth_type;
  wire out_vlan_0_valid;
  wire [2:0] out_vlan_0_pcp;
  wire [0:0] out_vlan_0_cfi;
  wire [11:0] out_vlan_0_vid;
  wire [15:0] out_vlan_0_tpid;
  wire out_ipv4_valid;
  wire [3:0] out_ipv4_version;
  wire [3:0] out_ipv4_hdr_len;
  wire [7:0] out_ipv4_tos;
  wire [15:0] out_ipv4_length;
  wire [15:0] out_ipv4_id;
  wire [2:0] out_ipv4_flags;
  wire [12:0] out_ipv4_offset;
  wire [7:0] out_ipv4_ttl;
  wire [7:0] out_ipv4_protocol;
  wire [15:0] out_ipv4_hdr_chk;
  wire [31:0] out_ipv4_src;
  wire [31:0] out_ipv4_dst;
  wire out_ipv4opt_valid;
  wire [319:0] out_ipv4opt_options;
  wire out_vlan_1_valid;
  wire [2:0] out_vlan_1_pcp;
  wire [0:0] out_vlan_1_cfi;
  wire [11:0] out_vlan_1_vid;
  wire [15:0] out_vlan_1_tpid;
  wire out_udp_valid;
  wire [15:0] out_udp_src_port;
  wire [15:0] out_udp_dst_port;
  wire [15:0] out_udp_length;
  wire [15:0] out_udp_checksum;
  wire proc_valid_out;
  wire proc_drop;
  wire [15:0] proc_out_meta_echo_port;



  processing_generated u_proc (
    .clk       (clk),
    .rst_n     (rst_n),
    .valid_in  (proc_armed),
    .eth_valid     (w_eth_valid),
    .vlan_0_valid     (w_vlan_0_valid),
    .ipv4_valid     (w_ipv4_valid),
    .ipv4opt_valid     (w_ipv4opt_valid),
    .vlan_1_valid     (w_vlan_1_valid),
    .udp_valid     (w_udp_valid),
    .eth_dmac  (w_eth_dmac),
    .eth_smac  (w_eth_smac),
    .eth_type  (w_eth_type),
    .vlan_0_pcp  (w_vlan_0_pcp),
    .vlan_0_cfi  (w_vlan_0_cfi),
    .vlan_0_vid  (w_vlan_0_vid),
    .vlan_0_tpid  (w_vlan_0_tpid),
    .ipv4_version  (w_ipv4_version),
    .ipv4_hdr_len  (w_ipv4_hdr_len),
    .ipv4_tos  (w_ipv4_tos),
    .ipv4_length  (w_ipv4_length),
    .ipv4_id  (w_ipv4_id),
    .ipv4_flags  (w_ipv4_flags),
    .ipv4_offset  (w_ipv4_offset),
    .ipv4_ttl  (w_ipv4_ttl),
    .ipv4_protocol  (w_ipv4_protocol),
    .ipv4_hdr_chk  (w_ipv4_hdr_chk),
    .ipv4_src  (w_ipv4_src),
    .ipv4_dst  (w_ipv4_dst),
    .ipv4opt_options  (w_ipv4opt_options),
    .vlan_1_pcp  (w_vlan_1_pcp),
    .vlan_1_cfi  (w_vlan_1_cfi),
    .vlan_1_vid  (w_vlan_1_vid),
    .vlan_1_tpid  (w_vlan_1_tpid),
    .udp_src_port  (w_udp_src_port),
    .udp_dst_port  (w_udp_dst_port),
    .udp_length  (w_udp_length),
    .udp_checksum  (w_udp_checksum),
    .meta_echo_port  (16'b0),
    .out_eth_valid     (out_eth_valid),
    .out_vlan_0_valid     (out_vlan_0_valid),
    .out_ipv4_valid     (out_ipv4_valid),
    .out_ipv4opt_valid     (out_ipv4opt_valid),
    .out_vlan_1_valid     (out_vlan_1_valid),
    .out_udp_valid     (out_udp_valid),
    .out_eth_dmac  (out_eth_dmac),
    .out_eth_smac  (out_eth_smac),
    .out_eth_type  (out_eth_type),
    .out_vlan_0_pcp  (out_vlan_0_pcp),
    .out_vlan_0_cfi  (out_vlan_0_cfi),
    .out_vlan_0_vid  (out_vlan_0_vid),
    .out_vlan_0_tpid  (out_vlan_0_tpid),
    .out_ipv4_version  (out_ipv4_version),
    .out_ipv4_hdr_len  (out_ipv4_hdr_len),
    .out_ipv4_tos  (out_ipv4_tos),
    .out_ipv4_length  (out_ipv4_length),
    .out_ipv4_id  (out_ipv4_id),
    .out_ipv4_flags  (out_ipv4_flags),
    .out_ipv4_offset  (out_ipv4_offset),
    .out_ipv4_ttl  (out_ipv4_ttl),
    .out_ipv4_protocol  (out_ipv4_protocol),
    .out_ipv4_hdr_chk  (out_ipv4_hdr_chk),
    .out_ipv4_src  (out_ipv4_src),
    .out_ipv4_dst  (out_ipv4_dst),
    .out_ipv4opt_options  (out_ipv4opt_options),
    .out_vlan_1_pcp  (out_vlan_1_pcp),
    .out_vlan_1_cfi  (out_vlan_1_cfi),
    .out_vlan_1_vid  (out_vlan_1_vid),
    .out_vlan_1_tpid  (out_vlan_1_tpid),
    .out_udp_src_port  (out_udp_src_port),
    .out_udp_dst_port  (out_udp_dst_port),
    .out_udp_length  (out_udp_length),
    .out_udp_checksum  (out_udp_checksum),
    .out_meta_echo_port  (proc_out_meta_echo_port),
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
      pkt_buf_hdr[0] <= out_eth_dmac[47:40];
      pkt_buf_hdr[1] <= out_eth_dmac[39:32];
      pkt_buf_hdr[2] <= out_eth_dmac[31:24];
      pkt_buf_hdr[3] <= out_eth_dmac[23:16];
      pkt_buf_hdr[4] <= out_eth_dmac[15:8];
      pkt_buf_hdr[5] <= out_eth_dmac[7:0];
      pkt_buf_hdr[6] <= out_eth_smac[47:40];
      pkt_buf_hdr[7] <= out_eth_smac[39:32];
      pkt_buf_hdr[8] <= out_eth_smac[31:24];
      pkt_buf_hdr[9] <= out_eth_smac[23:16];
      pkt_buf_hdr[10] <= out_eth_smac[15:8];
      pkt_buf_hdr[11] <= out_eth_smac[7:0];
      pkt_buf_hdr[12] <= out_eth_type[15:8];
      pkt_buf_hdr[13] <= out_eth_type[7:0];
      if (out_vlan_0_valid) begin
          pkt_buf_hdr[14] <= {out_vlan_0_pcp, out_vlan_0_cfi, out_vlan_0_vid[11:8]};
          pkt_buf_hdr[14+1] <= out_vlan_0_vid[7:0];
          pkt_buf_hdr[14+2] <= out_vlan_0_tpid[15:8];
          pkt_buf_hdr[14+3] <= out_vlan_0_tpid[7:0];
      end
      if (out_ipv4_valid) begin
          pkt_buf_hdr[w_ipv4_base] <= {out_ipv4_version, out_ipv4_hdr_len};
          pkt_buf_hdr[w_ipv4_base+1] <= out_ipv4_tos;
          pkt_buf_hdr[w_ipv4_base+2] <= out_ipv4_length[15:8];
          pkt_buf_hdr[w_ipv4_base+3] <= out_ipv4_length[7:0];
          pkt_buf_hdr[w_ipv4_base+4] <= out_ipv4_id[15:8];
          pkt_buf_hdr[w_ipv4_base+5] <= out_ipv4_id[7:0];
          pkt_buf_hdr[w_ipv4_base+6] <= {out_ipv4_flags, out_ipv4_offset[12:8]};
          pkt_buf_hdr[w_ipv4_base+7] <= out_ipv4_offset[7:0];
          pkt_buf_hdr[w_ipv4_base+8] <= out_ipv4_ttl;
          pkt_buf_hdr[w_ipv4_base+9] <= out_ipv4_protocol;
          pkt_buf_hdr[w_ipv4_base+10] <= out_ipv4_hdr_chk[15:8];
          pkt_buf_hdr[w_ipv4_base+11] <= out_ipv4_hdr_chk[7:0];
          pkt_buf_hdr[w_ipv4_base+12] <= out_ipv4_src[31:24];
          pkt_buf_hdr[w_ipv4_base+13] <= out_ipv4_src[23:16];
          pkt_buf_hdr[w_ipv4_base+14] <= out_ipv4_src[15:8];
          pkt_buf_hdr[w_ipv4_base+15] <= out_ipv4_src[7:0];
          pkt_buf_hdr[w_ipv4_base+16] <= out_ipv4_dst[31:24];
          pkt_buf_hdr[w_ipv4_base+17] <= out_ipv4_dst[23:16];
          pkt_buf_hdr[w_ipv4_base+18] <= out_ipv4_dst[15:8];
          pkt_buf_hdr[w_ipv4_base+19] <= out_ipv4_dst[7:0];
      end
      if (out_ipv4opt_valid) begin
          pkt_buf_hdr[w_ipv4opt_base] <= out_ipv4opt_options[319:312];
          pkt_buf_hdr[w_ipv4opt_base+1] <= out_ipv4opt_options[311:304];
          pkt_buf_hdr[w_ipv4opt_base+2] <= out_ipv4opt_options[303:296];
          pkt_buf_hdr[w_ipv4opt_base+3] <= out_ipv4opt_options[295:288];
          pkt_buf_hdr[w_ipv4opt_base+4] <= out_ipv4opt_options[287:280];
          pkt_buf_hdr[w_ipv4opt_base+5] <= out_ipv4opt_options[279:272];
          pkt_buf_hdr[w_ipv4opt_base+6] <= out_ipv4opt_options[271:264];
          pkt_buf_hdr[w_ipv4opt_base+7] <= out_ipv4opt_options[263:256];
          pkt_buf_hdr[w_ipv4opt_base+8] <= out_ipv4opt_options[255:248];
          pkt_buf_hdr[w_ipv4opt_base+9] <= out_ipv4opt_options[247:240];
          pkt_buf_hdr[w_ipv4opt_base+10] <= out_ipv4opt_options[239:232];
          pkt_buf_hdr[w_ipv4opt_base+11] <= out_ipv4opt_options[231:224];
          pkt_buf_hdr[w_ipv4opt_base+12] <= out_ipv4opt_options[223:216];
          pkt_buf_hdr[w_ipv4opt_base+13] <= out_ipv4opt_options[215:208];
          pkt_buf_hdr[w_ipv4opt_base+14] <= out_ipv4opt_options[207:200];
          pkt_buf_hdr[w_ipv4opt_base+15] <= out_ipv4opt_options[199:192];
          pkt_buf_hdr[w_ipv4opt_base+16] <= out_ipv4opt_options[191:184];
          pkt_buf_hdr[w_ipv4opt_base+17] <= out_ipv4opt_options[183:176];
          pkt_buf_hdr[w_ipv4opt_base+18] <= out_ipv4opt_options[175:168];
          pkt_buf_hdr[w_ipv4opt_base+19] <= out_ipv4opt_options[167:160];
          pkt_buf_hdr[w_ipv4opt_base+20] <= out_ipv4opt_options[159:152];
          pkt_buf_hdr[w_ipv4opt_base+21] <= out_ipv4opt_options[151:144];
          pkt_buf_hdr[w_ipv4opt_base+22] <= out_ipv4opt_options[143:136];
          pkt_buf_hdr[w_ipv4opt_base+23] <= out_ipv4opt_options[135:128];
          pkt_buf_hdr[w_ipv4opt_base+24] <= out_ipv4opt_options[127:120];
          pkt_buf_hdr[w_ipv4opt_base+25] <= out_ipv4opt_options[119:112];
          pkt_buf_hdr[w_ipv4opt_base+26] <= out_ipv4opt_options[111:104];
          pkt_buf_hdr[w_ipv4opt_base+27] <= out_ipv4opt_options[103:96];
          pkt_buf_hdr[w_ipv4opt_base+28] <= out_ipv4opt_options[95:88];
          pkt_buf_hdr[w_ipv4opt_base+29] <= out_ipv4opt_options[87:80];
          pkt_buf_hdr[w_ipv4opt_base+30] <= out_ipv4opt_options[79:72];
          pkt_buf_hdr[w_ipv4opt_base+31] <= out_ipv4opt_options[71:64];
          pkt_buf_hdr[w_ipv4opt_base+32] <= out_ipv4opt_options[63:56];
          pkt_buf_hdr[w_ipv4opt_base+33] <= out_ipv4opt_options[55:48];
          pkt_buf_hdr[w_ipv4opt_base+34] <= out_ipv4opt_options[47:40];
          pkt_buf_hdr[w_ipv4opt_base+35] <= out_ipv4opt_options[39:32];
          pkt_buf_hdr[w_ipv4opt_base+36] <= out_ipv4opt_options[31:24];
          pkt_buf_hdr[w_ipv4opt_base+37] <= out_ipv4opt_options[23:16];
          pkt_buf_hdr[w_ipv4opt_base+38] <= out_ipv4opt_options[15:8];
          pkt_buf_hdr[w_ipv4opt_base+39] <= out_ipv4opt_options[7:0];
      end
      if (out_vlan_1_valid) begin
          pkt_buf_hdr[18] <= {out_vlan_1_pcp, out_vlan_1_cfi, out_vlan_1_vid[11:8]};
          pkt_buf_hdr[18+1] <= out_vlan_1_vid[7:0];
          pkt_buf_hdr[18+2] <= out_vlan_1_tpid[15:8];
          pkt_buf_hdr[18+3] <= out_vlan_1_tpid[7:0];
      end
      if (out_udp_valid) begin
          pkt_buf_hdr[w_udp_base] <= out_udp_src_port[15:8];
          pkt_buf_hdr[w_udp_base+1] <= out_udp_src_port[7:0];
          pkt_buf_hdr[w_udp_base+2] <= out_udp_dst_port[15:8];
          pkt_buf_hdr[w_udp_base+3] <= out_udp_dst_port[7:0];
          pkt_buf_hdr[w_udp_base+4] <= out_udp_length[15:8];
          pkt_buf_hdr[w_udp_base+5] <= out_udp_length[7:0];
          pkt_buf_hdr[w_udp_base+6] <= out_udp_checksum[15:8];
          pkt_buf_hdr[w_udp_base+7] <= out_udp_checksum[7:0];
      end
    end
  `ifndef SYNTHESIS
    if (accept_beat && rx_beat_cnt < HDR_MAX_BEATS &&
        proc_settle && !proc_committed && !proc_drop)
      $error("pkt_buf_hdr write collision: RX and PROC write-back fired the same cycle");
  `endif
  end

  // ── Metadata sideband capture ──────────────────────────────────────────
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      out_meta_echo_port <= '0;
    end else if (proc_settle && !proc_committed && !proc_drop) begin
      out_meta_echo_port <= proc_out_meta_echo_port;
    end
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
