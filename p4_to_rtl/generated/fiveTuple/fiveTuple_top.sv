module fiveTuple_top #(
    parameter int AXI_DATA_W  = 64,
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

  localparam int BEAT_BYTES    = AXI_DATA_W / 8;  // 8
  localparam int MAX_PKT_BEATS = 256;
  localparam int MAX_PKT_BYTES = MAX_PKT_BEATS * BEAT_BYTES;  // 2048

  // ── Packet buffer ────────────────────────────────────────────────────────
  (* ram_style = "block" *)
  logic [7:0]                              pkt_buf  [0:MAX_PKT_BYTES-1];
  logic [AXI_DATA_W/8-1:0]               pkt_keep [255:0];
  logic [8:0]               beat_cnt;  // beats received
  logic [8:0]               tx_beat;   // beat being transmitted

  // ── State machine ────────────────────────────────────────────────────────
  typedef enum logic [2:0] {
    ST_IDLE = 3'd0,
    ST_RX   = 3'd1,
    ST_PROC = 3'd2,
    ST_TX   = 3'd3,
    ST_DROP = 3'd4
  } state_t;
  state_t state;

  // ── Header field extraction from pkt_buf ────────────────────────────────
  //    Fields extracted using big-endian (network byte order) bit mapping.

  wire [11:0] w_ipv4_base = 14 + ((w_eth_type == 16'h8100) ? 4 : 0);
  wire [11:0] w_ipv4_hdr_bytes = {8'b0, w_ipv4_hdr_len} << 2;
  wire [11:0] w_ipv4opt_base = w_ipv4_base + w_ipv4_hdr_bytes;
  wire [11:0] w_tcp_base = w_ipv4_base + w_ipv4_hdr_bytes;
  wire [11:0] w_tcpopt_base = w_ipv4_base + w_ipv4_hdr_bytes;
  wire [11:0] w_udp_base = w_ipv4_base + w_ipv4_hdr_bytes;

  // eth — base: 0
  wire [47:0] w_eth_dmac = {pkt_buf[0], pkt_buf[1], pkt_buf[2], pkt_buf[3], pkt_buf[4], pkt_buf[5]};
  wire [47:0] w_eth_smac = {pkt_buf[6], pkt_buf[7], pkt_buf[8], pkt_buf[9], pkt_buf[10], pkt_buf[11]};
  wire [15:0] w_eth_type = {pkt_buf[12], pkt_buf[13]};

  // vlan — base: 14
  wire [2:0] w_vlan_pcp = pkt_buf[14][7:5];
  wire [0:0] w_vlan_cfi = pkt_buf[14][4:4];
  wire [11:0] w_vlan_vid = {pkt_buf[14][3:0], pkt_buf[14+1]};
  wire [15:0] w_vlan_tpid = {pkt_buf[14+2], pkt_buf[14+3]};

  // ipv4 — base: w_ipv4_base
  wire [3:0] w_ipv4_version = pkt_buf[w_ipv4_base][7:4];
  wire [3:0] w_ipv4_hdr_len = pkt_buf[w_ipv4_base][3:0];
  wire [7:0] w_ipv4_tos = pkt_buf[w_ipv4_base+1];
  wire [15:0] w_ipv4_length = {pkt_buf[w_ipv4_base+2], pkt_buf[w_ipv4_base+3]};
  wire [15:0] w_ipv4_id = {pkt_buf[w_ipv4_base+4], pkt_buf[w_ipv4_base+5]};
  wire [2:0] w_ipv4_flags = pkt_buf[w_ipv4_base+6][7:5];
  wire [12:0] w_ipv4_offset = {pkt_buf[w_ipv4_base+6][4:0], pkt_buf[w_ipv4_base+7]};
  wire [7:0] w_ipv4_ttl = pkt_buf[w_ipv4_base+8];
  wire [7:0] w_ipv4_protocol = pkt_buf[w_ipv4_base+9];
  wire [15:0] w_ipv4_hdr_chk = {pkt_buf[w_ipv4_base+10], pkt_buf[w_ipv4_base+11]};
  wire [31:0] w_ipv4_src = {pkt_buf[w_ipv4_base+12], pkt_buf[w_ipv4_base+13], pkt_buf[w_ipv4_base+14], pkt_buf[w_ipv4_base+15]};
  wire [31:0] w_ipv4_dst = {pkt_buf[w_ipv4_base+16], pkt_buf[w_ipv4_base+17], pkt_buf[w_ipv4_base+18], pkt_buf[w_ipv4_base+19]};

  // ipv4opt — base: w_ipv4opt_base
  wire [319:0] w_ipv4opt_options = {pkt_buf[w_ipv4opt_base], pkt_buf[w_ipv4opt_base+1], pkt_buf[w_ipv4opt_base+2], pkt_buf[w_ipv4opt_base+3], pkt_buf[w_ipv4opt_base+4], pkt_buf[w_ipv4opt_base+5], pkt_buf[w_ipv4opt_base+6], pkt_buf[w_ipv4opt_base+7], pkt_buf[w_ipv4opt_base+8], pkt_buf[w_ipv4opt_base+9], pkt_buf[w_ipv4opt_base+10], pkt_buf[w_ipv4opt_base+11], pkt_buf[w_ipv4opt_base+12], pkt_buf[w_ipv4opt_base+13], pkt_buf[w_ipv4opt_base+14], pkt_buf[w_ipv4opt_base+15], pkt_buf[w_ipv4opt_base+16], pkt_buf[w_ipv4opt_base+17], pkt_buf[w_ipv4opt_base+18], pkt_buf[w_ipv4opt_base+19], pkt_buf[w_ipv4opt_base+20], pkt_buf[w_ipv4opt_base+21], pkt_buf[w_ipv4opt_base+22], pkt_buf[w_ipv4opt_base+23], pkt_buf[w_ipv4opt_base+24], pkt_buf[w_ipv4opt_base+25], pkt_buf[w_ipv4opt_base+26], pkt_buf[w_ipv4opt_base+27], pkt_buf[w_ipv4opt_base+28], pkt_buf[w_ipv4opt_base+29], pkt_buf[w_ipv4opt_base+30], pkt_buf[w_ipv4opt_base+31], pkt_buf[w_ipv4opt_base+32], pkt_buf[w_ipv4opt_base+33], pkt_buf[w_ipv4opt_base+34], pkt_buf[w_ipv4opt_base+35], pkt_buf[w_ipv4opt_base+36], pkt_buf[w_ipv4opt_base+37], pkt_buf[w_ipv4opt_base+38], pkt_buf[w_ipv4opt_base+39]};

  // tcp — base: w_tcp_base
  wire [15:0] w_tcp_src_port = {pkt_buf[w_tcp_base], pkt_buf[w_tcp_base+1]};
  wire [15:0] w_tcp_dst_port = {pkt_buf[w_tcp_base+2], pkt_buf[w_tcp_base+3]};
  wire [31:0] w_tcp_seqNum = {pkt_buf[w_tcp_base+4], pkt_buf[w_tcp_base+5], pkt_buf[w_tcp_base+6], pkt_buf[w_tcp_base+7]};
  wire [31:0] w_tcp_ackNum = {pkt_buf[w_tcp_base+8], pkt_buf[w_tcp_base+9], pkt_buf[w_tcp_base+10], pkt_buf[w_tcp_base+11]};
  wire [3:0] w_tcp_dataOffset = pkt_buf[w_tcp_base+12][7:4];
  wire [5:0] w_tcp_resv = {pkt_buf[w_tcp_base+12][3:0], pkt_buf[w_tcp_base+13][7:6]};
  wire [5:0] w_tcp_flags = pkt_buf[w_tcp_base+13][5:0];
  wire [15:0] w_tcp_window = {pkt_buf[w_tcp_base+14], pkt_buf[w_tcp_base+15]};
  wire [15:0] w_tcp_checksum = {pkt_buf[w_tcp_base+16], pkt_buf[w_tcp_base+17]};
  wire [15:0] w_tcp_urgPtr = {pkt_buf[w_tcp_base+18], pkt_buf[w_tcp_base+19]};

  // tcpopt — base: w_tcpopt_base
  wire [319:0] w_tcpopt_options = {pkt_buf[w_tcpopt_base], pkt_buf[w_tcpopt_base+1], pkt_buf[w_tcpopt_base+2], pkt_buf[w_tcpopt_base+3], pkt_buf[w_tcpopt_base+4], pkt_buf[w_tcpopt_base+5], pkt_buf[w_tcpopt_base+6], pkt_buf[w_tcpopt_base+7], pkt_buf[w_tcpopt_base+8], pkt_buf[w_tcpopt_base+9], pkt_buf[w_tcpopt_base+10], pkt_buf[w_tcpopt_base+11], pkt_buf[w_tcpopt_base+12], pkt_buf[w_tcpopt_base+13], pkt_buf[w_tcpopt_base+14], pkt_buf[w_tcpopt_base+15], pkt_buf[w_tcpopt_base+16], pkt_buf[w_tcpopt_base+17], pkt_buf[w_tcpopt_base+18], pkt_buf[w_tcpopt_base+19], pkt_buf[w_tcpopt_base+20], pkt_buf[w_tcpopt_base+21], pkt_buf[w_tcpopt_base+22], pkt_buf[w_tcpopt_base+23], pkt_buf[w_tcpopt_base+24], pkt_buf[w_tcpopt_base+25], pkt_buf[w_tcpopt_base+26], pkt_buf[w_tcpopt_base+27], pkt_buf[w_tcpopt_base+28], pkt_buf[w_tcpopt_base+29], pkt_buf[w_tcpopt_base+30], pkt_buf[w_tcpopt_base+31], pkt_buf[w_tcpopt_base+32], pkt_buf[w_tcpopt_base+33], pkt_buf[w_tcpopt_base+34], pkt_buf[w_tcpopt_base+35], pkt_buf[w_tcpopt_base+36], pkt_buf[w_tcpopt_base+37], pkt_buf[w_tcpopt_base+38], pkt_buf[w_tcpopt_base+39]};

  // udp — base: w_udp_base
  wire [15:0] w_udp_src_port = {pkt_buf[w_udp_base], pkt_buf[w_udp_base+1]};
  wire [15:0] w_udp_dst_port = {pkt_buf[w_udp_base+2], pkt_buf[w_udp_base+3]};
  wire [15:0] w_udp_length = {pkt_buf[w_udp_base+4], pkt_buf[w_udp_base+5]};
  wire [15:0] w_udp_checksum = {pkt_buf[w_udp_base+6], pkt_buf[w_udp_base+7]};

  // ── Header validity (derived from extracted fields) ──────────────────────
  wire w_eth_valid = 1'b1;
  wire w_vlan_valid = (w_eth_type == 16'h8100);
  wire w_ipv4_valid = ((w_eth_type == 16'h0800) || ((w_eth_type == 16'h8100) && (w_vlan_tpid == 16'h0800)));
  wire w_ipv4opt_valid = ((w_eth_type == 16'h0800) || ((w_eth_type == 16'h8100) && (w_vlan_tpid == 16'h0800)));
  wire w_tcp_valid = (((w_eth_type == 16'h0800) || ((w_eth_type == 16'h8100) && (w_vlan_tpid == 16'h0800))) && (w_ipv4_protocol == 8'h06));
  wire w_tcpopt_valid = (((w_eth_type == 16'h0800) || ((w_eth_type == 16'h8100) && (w_vlan_tpid == 16'h0800))) && (w_ipv4_protocol == 8'h06));
  wire w_udp_valid = (((w_eth_type == 16'h0800) || ((w_eth_type == 16'h8100) && (w_vlan_tpid == 16'h0800))) && (w_ipv4_protocol == 8'h11));
  wire w_new_vlan_valid = 1'b0;

  // Action-only headers (not in received packet; inputs tied to 0)
  wire [2:0] w_new_vlan_pcp = '0;
  wire [0:0] w_new_vlan_cfi = '0;
  wire [11:0] w_new_vlan_vid = '0;
  wire [15:0] w_new_vlan_tpid = '0;

  // ── processing_generated ─────────────────────────────────────────────────
  //    Signals prefixed proc_out_* are the match-action outputs.

  wire out_eth_valid;
  wire [47:0] out_eth_dmac;
  wire [47:0] out_eth_smac;
  wire [15:0] out_eth_type;
  wire out_vlan_valid;
  wire [2:0] out_vlan_pcp;
  wire [0:0] out_vlan_cfi;
  wire [11:0] out_vlan_vid;
  wire [15:0] out_vlan_tpid;
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
  wire out_tcp_valid;
  wire [15:0] out_tcp_src_port;
  wire [15:0] out_tcp_dst_port;
  wire [31:0] out_tcp_seqNum;
  wire [31:0] out_tcp_ackNum;
  wire [3:0] out_tcp_dataOffset;
  wire [5:0] out_tcp_resv;
  wire [5:0] out_tcp_flags;
  wire [15:0] out_tcp_window;
  wire [15:0] out_tcp_checksum;
  wire [15:0] out_tcp_urgPtr;
  wire out_tcpopt_valid;
  wire [319:0] out_tcpopt_options;
  wire out_udp_valid;
  wire [15:0] out_udp_src_port;
  wire [15:0] out_udp_dst_port;
  wire [15:0] out_udp_length;
  wire [15:0] out_udp_checksum;
  wire out_new_vlan_valid;
  wire [2:0] out_new_vlan_pcp;
  wire [0:0] out_new_vlan_cfi;
  wire [11:0] out_new_vlan_vid;
  wire [15:0] out_new_vlan_tpid;
  wire proc_valid_out;
  wire proc_drop;

  wire [12:0] FiveTuple_cp_wr_idx = r_FiveTuple_cp_wr_idx;
  wire [0:0] FiveTuple_cp_wr_action = r_FiveTuple_cp_wr_action;
  wire [31:0] FiveTuple_cp_wr_key_ipv4_src = r_FiveTuple_cp_wr_key_ipv4_src;
  wire [31:0] FiveTuple_cp_wr_key_ipv4_dst = r_FiveTuple_cp_wr_key_ipv4_dst;
  wire [7:0] FiveTuple_cp_wr_key_ipv4_protocol = r_FiveTuple_cp_wr_key_ipv4_protocol;
  wire [15:0] FiveTuple_cp_wr_key_table_key_sport = r_FiveTuple_cp_wr_key_table_key_sport;
  wire [15:0] FiveTuple_cp_wr_key_table_key_dport = r_FiveTuple_cp_wr_key_table_key_dport;
  wire [12:0] FiveTuple_cp_wr_p_counter_index = r_FiveTuple_cp_wr_p_counter_index;
  wire [2:0] FiveTuple_cp_wr_p_pcp = r_FiveTuple_cp_wr_p_pcp;
  wire [0:0] FiveTuple_cp_wr_p_cfi = r_FiveTuple_cp_wr_p_cfi;
  wire [11:0] FiveTuple_cp_wr_p_vid = r_FiveTuple_cp_wr_p_vid;
  wire FiveTuple_cp_wr_en = r_FiveTuple_cp_wr_en;
  wire FiveTuple_hit_out;

  processing_generated u_proc (
    .clk       (clk),
    .rst_n     (rst_n),
    .valid_in  (state == ST_PROC),
    .eth_valid     (w_eth_valid),
    .vlan_valid     (w_vlan_valid),
    .ipv4_valid     (w_ipv4_valid),
    .ipv4opt_valid     (w_ipv4opt_valid),
    .tcp_valid     (w_tcp_valid),
    .tcpopt_valid     (w_tcpopt_valid),
    .udp_valid     (w_udp_valid),
    .new_vlan_valid     (w_new_vlan_valid),
    .eth_dmac  (w_eth_dmac),
    .eth_smac  (w_eth_smac),
    .eth_type  (w_eth_type),
    .vlan_pcp  (w_vlan_pcp),
    .vlan_cfi  (w_vlan_cfi),
    .vlan_vid  (w_vlan_vid),
    .vlan_tpid  (w_vlan_tpid),
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
    .tcp_src_port  (w_tcp_src_port),
    .tcp_dst_port  (w_tcp_dst_port),
    .tcp_seqNum  (w_tcp_seqNum),
    .tcp_ackNum  (w_tcp_ackNum),
    .tcp_dataOffset  (w_tcp_dataOffset),
    .tcp_resv  (w_tcp_resv),
    .tcp_flags  (w_tcp_flags),
    .tcp_window  (w_tcp_window),
    .tcp_checksum  (w_tcp_checksum),
    .tcp_urgPtr  (w_tcp_urgPtr),
    .tcpopt_options  (w_tcpopt_options),
    .udp_src_port  (w_udp_src_port),
    .udp_dst_port  (w_udp_dst_port),
    .udp_length  (w_udp_length),
    .udp_checksum  (w_udp_checksum),
    .new_vlan_pcp  (w_new_vlan_pcp),
    .new_vlan_cfi  (w_new_vlan_cfi),
    .new_vlan_vid  (w_new_vlan_vid),
    .new_vlan_tpid  (w_new_vlan_tpid),
    .out_eth_valid     (out_eth_valid),
    .out_vlan_valid     (out_vlan_valid),
    .out_ipv4_valid     (out_ipv4_valid),
    .out_ipv4opt_valid     (out_ipv4opt_valid),
    .out_tcp_valid     (out_tcp_valid),
    .out_tcpopt_valid     (out_tcpopt_valid),
    .out_udp_valid     (out_udp_valid),
    .out_new_vlan_valid     (out_new_vlan_valid),
    .out_eth_dmac  (out_eth_dmac),
    .out_eth_smac  (out_eth_smac),
    .out_eth_type  (out_eth_type),
    .out_vlan_pcp  (out_vlan_pcp),
    .out_vlan_cfi  (out_vlan_cfi),
    .out_vlan_vid  (out_vlan_vid),
    .out_vlan_tpid  (out_vlan_tpid),
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
    .out_tcp_src_port  (out_tcp_src_port),
    .out_tcp_dst_port  (out_tcp_dst_port),
    .out_tcp_seqNum  (out_tcp_seqNum),
    .out_tcp_ackNum  (out_tcp_ackNum),
    .out_tcp_dataOffset  (out_tcp_dataOffset),
    .out_tcp_resv  (out_tcp_resv),
    .out_tcp_flags  (out_tcp_flags),
    .out_tcp_window  (out_tcp_window),
    .out_tcp_checksum  (out_tcp_checksum),
    .out_tcp_urgPtr  (out_tcp_urgPtr),
    .out_tcpopt_options  (out_tcpopt_options),
    .out_udp_src_port  (out_udp_src_port),
    .out_udp_dst_port  (out_udp_dst_port),
    .out_udp_length  (out_udp_length),
    .out_udp_checksum  (out_udp_checksum),
    .out_new_vlan_pcp  (out_new_vlan_pcp),
    .out_new_vlan_cfi  (out_new_vlan_cfi),
    .out_new_vlan_vid  (out_new_vlan_vid),
    .out_new_vlan_tpid  (out_new_vlan_tpid),
    .FiveTuple_cp_wr_en  (FiveTuple_cp_wr_en),
    .FiveTuple_cp_wr_idx (FiveTuple_cp_wr_idx),
    .FiveTuple_cp_wr_action (FiveTuple_cp_wr_action),
    .FiveTuple_cp_wr_key_ipv4_src (FiveTuple_cp_wr_key_ipv4_src),
    .FiveTuple_cp_wr_key_ipv4_dst (FiveTuple_cp_wr_key_ipv4_dst),
    .FiveTuple_cp_wr_key_ipv4_protocol (FiveTuple_cp_wr_key_ipv4_protocol),
    .FiveTuple_cp_wr_key_table_key_sport (FiveTuple_cp_wr_key_table_key_sport),
    .FiveTuple_cp_wr_key_table_key_dport (FiveTuple_cp_wr_key_table_key_dport),
    .FiveTuple_cp_wr_p_counter_index (FiveTuple_cp_wr_p_counter_index),
    .FiveTuple_cp_wr_p_pcp (FiveTuple_cp_wr_p_pcp),
    .FiveTuple_cp_wr_p_cfi (FiveTuple_cp_wr_p_cfi),
    .FiveTuple_cp_wr_p_vid (FiveTuple_cp_wr_p_vid),
    .FiveTuple_hit_out  (FiveTuple_hit_out),
    .valid_out (proc_valid_out),
    .drop      (proc_drop)
  );


  // ── AXI4-Lite staging registers ─────────────────────────────────────────
  logic [12:0] r_FiveTuple_cp_wr_idx;
  logic [0:0] r_FiveTuple_cp_wr_action;
  logic [31:0] r_FiveTuple_cp_wr_key_ipv4_src;
  logic [31:0] r_FiveTuple_cp_wr_key_ipv4_dst;
  logic [7:0] r_FiveTuple_cp_wr_key_ipv4_protocol;
  logic [15:0] r_FiveTuple_cp_wr_key_table_key_sport;
  logic [15:0] r_FiveTuple_cp_wr_key_table_key_dport;
  logic [12:0] r_FiveTuple_cp_wr_p_counter_index;
  logic [2:0] r_FiveTuple_cp_wr_p_pcp;
  logic [0:0] r_FiveTuple_cp_wr_p_cfi;
  logic [11:0] r_FiveTuple_cp_wr_p_vid;
  logic r_FiveTuple_cp_wr_en;

  // AXI4-Lite write channel state machine
  typedef enum logic [1:0] {
    AXIL_IDLE  = 2'd0,
    AXIL_WDATA = 2'd1,
    AXIL_BRESP = 2'd2
  } axil_st_t;

  axil_st_t               axil_st;
  logic [AXIL_ADDR_W-1:0] axil_awaddr_r;

  assign s_axil_awready = (axil_st == AXIL_IDLE);
  assign s_axil_wready  = (axil_st == AXIL_WDATA);
  assign s_axil_bvalid  = (axil_st == AXIL_BRESP);
  assign s_axil_bresp   = 2'b00;

  // AXI4-Lite read channel — tables are write-only; always acknowledge with 0
  assign s_axil_arready = 1'b1;
  assign s_axil_rdata   = '0;
  assign s_axil_rresp   = 2'b00;
  assign s_axil_rvalid  = s_axil_arvalid;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      axil_st <= AXIL_IDLE;
      r_FiveTuple_cp_wr_en <= 1'b0;
    end else begin
      r_FiveTuple_cp_wr_en <= 1'b0;
      case (axil_st)
        AXIL_IDLE: begin
          if (s_axil_awvalid) begin
            axil_awaddr_r <= s_axil_awaddr;
            axil_st       <= AXIL_WDATA;
          end
        end
        AXIL_WDATA: begin
          if (s_axil_wvalid) begin
            case (axil_awaddr_r[AXIL_ADDR_W-1:2])  // word address
              14'd0: r_FiveTuple_cp_wr_idx <= s_axil_wdata[12:0]; // wr_idx
              14'd1: r_FiveTuple_cp_wr_action <= s_axil_wdata[0:0]; // wr_action
              14'd2: r_FiveTuple_cp_wr_key_ipv4_src <= s_axil_wdata[31:0]; // key_ipv4_src
              14'd3: r_FiveTuple_cp_wr_key_ipv4_dst <= s_axil_wdata[31:0]; // key_ipv4_dst
              14'd4: r_FiveTuple_cp_wr_key_ipv4_protocol <= s_axil_wdata[7:0]; // key_ipv4_protocol
              14'd5: r_FiveTuple_cp_wr_key_table_key_sport <= s_axil_wdata[15:0]; // key_table_key_sport
              14'd6: r_FiveTuple_cp_wr_key_table_key_dport <= s_axil_wdata[15:0]; // key_table_key_dport
              14'd7: r_FiveTuple_cp_wr_p_counter_index <= s_axil_wdata[12:0]; // p_counter_index
              14'd8: r_FiveTuple_cp_wr_p_pcp <= s_axil_wdata[2:0]; // p_pcp
              14'd9: r_FiveTuple_cp_wr_p_cfi <= s_axil_wdata[0:0]; // p_cfi
              14'd10: r_FiveTuple_cp_wr_p_vid <= s_axil_wdata[11:0]; // p_vid
              14'd11: r_FiveTuple_cp_wr_en <= 1'b1; // FiveTuple commit
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

  // ── RX / state machine ───────────────────────────────────────────────────
  assign s_axis_tready = (state == ST_IDLE) || (state == ST_RX);

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      state    <= ST_IDLE;
      beat_cnt <= '0;
      tx_beat  <= '0;
    end else case (state)

      ST_IDLE: begin
        if (s_axis_tvalid) begin
          beat_cnt <= '0;
          state    <= ST_RX;
        end
      end

      ST_RX: begin
        if (s_axis_tvalid && s_axis_tready) begin
          // Capture one beat (AXI4-Stream byte 0 = tdata[7:0])
          for (int i = 0; i < 8; i++)
            if (s_axis_tkeep[i])
              pkt_buf[beat_cnt * 8 + i] <= s_axis_tdata[i*8 +: 8];
          pkt_keep[beat_cnt] <= s_axis_tkeep;
          beat_cnt          <= beat_cnt + 9'd1;
          if (s_axis_tlast) state <= ST_PROC;
        end
      end

      ST_PROC: begin
        if (proc_valid_out) begin
          // Write-back modified header fields into pkt_buf
          if (!proc_drop) begin
            pkt_buf[0] <= out_eth_dmac[47:40];
            pkt_buf[1] <= out_eth_dmac[39:32];
            pkt_buf[2] <= out_eth_dmac[31:24];
            pkt_buf[3] <= out_eth_dmac[23:16];
            pkt_buf[4] <= out_eth_dmac[15:8];
            pkt_buf[5] <= out_eth_dmac[7:0];
            pkt_buf[6] <= out_eth_smac[47:40];
            pkt_buf[7] <= out_eth_smac[39:32];
            pkt_buf[8] <= out_eth_smac[31:24];
            pkt_buf[9] <= out_eth_smac[23:16];
            pkt_buf[10] <= out_eth_smac[15:8];
            pkt_buf[11] <= out_eth_smac[7:0];
            pkt_buf[12] <= out_eth_type[15:8];
            pkt_buf[13] <= out_eth_type[7:0];
            if (out_vlan_valid) begin
                pkt_buf[14] <= {out_vlan_pcp, out_vlan_cfi, out_vlan_vid[11:8]};
                pkt_buf[14+1] <= out_vlan_vid[7:0];
                pkt_buf[14+2] <= out_vlan_tpid[15:8];
                pkt_buf[14+3] <= out_vlan_tpid[7:0];
            end
            if (out_ipv4_valid) begin
                pkt_buf[w_ipv4_base] <= {out_ipv4_version, out_ipv4_hdr_len};
                pkt_buf[w_ipv4_base+1] <= out_ipv4_tos;
                pkt_buf[w_ipv4_base+2] <= out_ipv4_length[15:8];
                pkt_buf[w_ipv4_base+3] <= out_ipv4_length[7:0];
                pkt_buf[w_ipv4_base+4] <= out_ipv4_id[15:8];
                pkt_buf[w_ipv4_base+5] <= out_ipv4_id[7:0];
                pkt_buf[w_ipv4_base+6] <= {out_ipv4_flags, out_ipv4_offset[12:8]};
                pkt_buf[w_ipv4_base+7] <= out_ipv4_offset[7:0];
                pkt_buf[w_ipv4_base+8] <= out_ipv4_ttl;
                pkt_buf[w_ipv4_base+9] <= out_ipv4_protocol;
                pkt_buf[w_ipv4_base+10] <= out_ipv4_hdr_chk[15:8];
                pkt_buf[w_ipv4_base+11] <= out_ipv4_hdr_chk[7:0];
                pkt_buf[w_ipv4_base+12] <= out_ipv4_src[31:24];
                pkt_buf[w_ipv4_base+13] <= out_ipv4_src[23:16];
                pkt_buf[w_ipv4_base+14] <= out_ipv4_src[15:8];
                pkt_buf[w_ipv4_base+15] <= out_ipv4_src[7:0];
                pkt_buf[w_ipv4_base+16] <= out_ipv4_dst[31:24];
                pkt_buf[w_ipv4_base+17] <= out_ipv4_dst[23:16];
                pkt_buf[w_ipv4_base+18] <= out_ipv4_dst[15:8];
                pkt_buf[w_ipv4_base+19] <= out_ipv4_dst[7:0];
            end
            if (out_ipv4opt_valid) begin
                pkt_buf[w_ipv4opt_base] <= out_ipv4opt_options[319:312];
                pkt_buf[w_ipv4opt_base+1] <= out_ipv4opt_options[311:304];
                pkt_buf[w_ipv4opt_base+2] <= out_ipv4opt_options[303:296];
                pkt_buf[w_ipv4opt_base+3] <= out_ipv4opt_options[295:288];
                pkt_buf[w_ipv4opt_base+4] <= out_ipv4opt_options[287:280];
                pkt_buf[w_ipv4opt_base+5] <= out_ipv4opt_options[279:272];
                pkt_buf[w_ipv4opt_base+6] <= out_ipv4opt_options[271:264];
                pkt_buf[w_ipv4opt_base+7] <= out_ipv4opt_options[263:256];
                pkt_buf[w_ipv4opt_base+8] <= out_ipv4opt_options[255:248];
                pkt_buf[w_ipv4opt_base+9] <= out_ipv4opt_options[247:240];
                pkt_buf[w_ipv4opt_base+10] <= out_ipv4opt_options[239:232];
                pkt_buf[w_ipv4opt_base+11] <= out_ipv4opt_options[231:224];
                pkt_buf[w_ipv4opt_base+12] <= out_ipv4opt_options[223:216];
                pkt_buf[w_ipv4opt_base+13] <= out_ipv4opt_options[215:208];
                pkt_buf[w_ipv4opt_base+14] <= out_ipv4opt_options[207:200];
                pkt_buf[w_ipv4opt_base+15] <= out_ipv4opt_options[199:192];
                pkt_buf[w_ipv4opt_base+16] <= out_ipv4opt_options[191:184];
                pkt_buf[w_ipv4opt_base+17] <= out_ipv4opt_options[183:176];
                pkt_buf[w_ipv4opt_base+18] <= out_ipv4opt_options[175:168];
                pkt_buf[w_ipv4opt_base+19] <= out_ipv4opt_options[167:160];
                pkt_buf[w_ipv4opt_base+20] <= out_ipv4opt_options[159:152];
                pkt_buf[w_ipv4opt_base+21] <= out_ipv4opt_options[151:144];
                pkt_buf[w_ipv4opt_base+22] <= out_ipv4opt_options[143:136];
                pkt_buf[w_ipv4opt_base+23] <= out_ipv4opt_options[135:128];
                pkt_buf[w_ipv4opt_base+24] <= out_ipv4opt_options[127:120];
                pkt_buf[w_ipv4opt_base+25] <= out_ipv4opt_options[119:112];
                pkt_buf[w_ipv4opt_base+26] <= out_ipv4opt_options[111:104];
                pkt_buf[w_ipv4opt_base+27] <= out_ipv4opt_options[103:96];
                pkt_buf[w_ipv4opt_base+28] <= out_ipv4opt_options[95:88];
                pkt_buf[w_ipv4opt_base+29] <= out_ipv4opt_options[87:80];
                pkt_buf[w_ipv4opt_base+30] <= out_ipv4opt_options[79:72];
                pkt_buf[w_ipv4opt_base+31] <= out_ipv4opt_options[71:64];
                pkt_buf[w_ipv4opt_base+32] <= out_ipv4opt_options[63:56];
                pkt_buf[w_ipv4opt_base+33] <= out_ipv4opt_options[55:48];
                pkt_buf[w_ipv4opt_base+34] <= out_ipv4opt_options[47:40];
                pkt_buf[w_ipv4opt_base+35] <= out_ipv4opt_options[39:32];
                pkt_buf[w_ipv4opt_base+36] <= out_ipv4opt_options[31:24];
                pkt_buf[w_ipv4opt_base+37] <= out_ipv4opt_options[23:16];
                pkt_buf[w_ipv4opt_base+38] <= out_ipv4opt_options[15:8];
                pkt_buf[w_ipv4opt_base+39] <= out_ipv4opt_options[7:0];
            end
            if (out_tcp_valid) begin
                pkt_buf[w_tcp_base] <= out_tcp_src_port[15:8];
                pkt_buf[w_tcp_base+1] <= out_tcp_src_port[7:0];
                pkt_buf[w_tcp_base+2] <= out_tcp_dst_port[15:8];
                pkt_buf[w_tcp_base+3] <= out_tcp_dst_port[7:0];
                pkt_buf[w_tcp_base+4] <= out_tcp_seqNum[31:24];
                pkt_buf[w_tcp_base+5] <= out_tcp_seqNum[23:16];
                pkt_buf[w_tcp_base+6] <= out_tcp_seqNum[15:8];
                pkt_buf[w_tcp_base+7] <= out_tcp_seqNum[7:0];
                pkt_buf[w_tcp_base+8] <= out_tcp_ackNum[31:24];
                pkt_buf[w_tcp_base+9] <= out_tcp_ackNum[23:16];
                pkt_buf[w_tcp_base+10] <= out_tcp_ackNum[15:8];
                pkt_buf[w_tcp_base+11] <= out_tcp_ackNum[7:0];
                pkt_buf[w_tcp_base+12] <= {out_tcp_dataOffset, out_tcp_resv[5:2]};
                pkt_buf[w_tcp_base+13] <= {out_tcp_resv[1:0], out_tcp_flags};
                pkt_buf[w_tcp_base+14] <= out_tcp_window[15:8];
                pkt_buf[w_tcp_base+15] <= out_tcp_window[7:0];
                pkt_buf[w_tcp_base+16] <= out_tcp_checksum[15:8];
                pkt_buf[w_tcp_base+17] <= out_tcp_checksum[7:0];
                pkt_buf[w_tcp_base+18] <= out_tcp_urgPtr[15:8];
                pkt_buf[w_tcp_base+19] <= out_tcp_urgPtr[7:0];
            end
            if (out_tcpopt_valid) begin
                pkt_buf[w_tcpopt_base] <= out_tcpopt_options[319:312];
                pkt_buf[w_tcpopt_base+1] <= out_tcpopt_options[311:304];
                pkt_buf[w_tcpopt_base+2] <= out_tcpopt_options[303:296];
                pkt_buf[w_tcpopt_base+3] <= out_tcpopt_options[295:288];
                pkt_buf[w_tcpopt_base+4] <= out_tcpopt_options[287:280];
                pkt_buf[w_tcpopt_base+5] <= out_tcpopt_options[279:272];
                pkt_buf[w_tcpopt_base+6] <= out_tcpopt_options[271:264];
                pkt_buf[w_tcpopt_base+7] <= out_tcpopt_options[263:256];
                pkt_buf[w_tcpopt_base+8] <= out_tcpopt_options[255:248];
                pkt_buf[w_tcpopt_base+9] <= out_tcpopt_options[247:240];
                pkt_buf[w_tcpopt_base+10] <= out_tcpopt_options[239:232];
                pkt_buf[w_tcpopt_base+11] <= out_tcpopt_options[231:224];
                pkt_buf[w_tcpopt_base+12] <= out_tcpopt_options[223:216];
                pkt_buf[w_tcpopt_base+13] <= out_tcpopt_options[215:208];
                pkt_buf[w_tcpopt_base+14] <= out_tcpopt_options[207:200];
                pkt_buf[w_tcpopt_base+15] <= out_tcpopt_options[199:192];
                pkt_buf[w_tcpopt_base+16] <= out_tcpopt_options[191:184];
                pkt_buf[w_tcpopt_base+17] <= out_tcpopt_options[183:176];
                pkt_buf[w_tcpopt_base+18] <= out_tcpopt_options[175:168];
                pkt_buf[w_tcpopt_base+19] <= out_tcpopt_options[167:160];
                pkt_buf[w_tcpopt_base+20] <= out_tcpopt_options[159:152];
                pkt_buf[w_tcpopt_base+21] <= out_tcpopt_options[151:144];
                pkt_buf[w_tcpopt_base+22] <= out_tcpopt_options[143:136];
                pkt_buf[w_tcpopt_base+23] <= out_tcpopt_options[135:128];
                pkt_buf[w_tcpopt_base+24] <= out_tcpopt_options[127:120];
                pkt_buf[w_tcpopt_base+25] <= out_tcpopt_options[119:112];
                pkt_buf[w_tcpopt_base+26] <= out_tcpopt_options[111:104];
                pkt_buf[w_tcpopt_base+27] <= out_tcpopt_options[103:96];
                pkt_buf[w_tcpopt_base+28] <= out_tcpopt_options[95:88];
                pkt_buf[w_tcpopt_base+29] <= out_tcpopt_options[87:80];
                pkt_buf[w_tcpopt_base+30] <= out_tcpopt_options[79:72];
                pkt_buf[w_tcpopt_base+31] <= out_tcpopt_options[71:64];
                pkt_buf[w_tcpopt_base+32] <= out_tcpopt_options[63:56];
                pkt_buf[w_tcpopt_base+33] <= out_tcpopt_options[55:48];
                pkt_buf[w_tcpopt_base+34] <= out_tcpopt_options[47:40];
                pkt_buf[w_tcpopt_base+35] <= out_tcpopt_options[39:32];
                pkt_buf[w_tcpopt_base+36] <= out_tcpopt_options[31:24];
                pkt_buf[w_tcpopt_base+37] <= out_tcpopt_options[23:16];
                pkt_buf[w_tcpopt_base+38] <= out_tcpopt_options[15:8];
                pkt_buf[w_tcpopt_base+39] <= out_tcpopt_options[7:0];
            end
            if (out_udp_valid) begin
                pkt_buf[w_udp_base] <= out_udp_src_port[15:8];
                pkt_buf[w_udp_base+1] <= out_udp_src_port[7:0];
                pkt_buf[w_udp_base+2] <= out_udp_dst_port[15:8];
                pkt_buf[w_udp_base+3] <= out_udp_dst_port[7:0];
                pkt_buf[w_udp_base+4] <= out_udp_length[15:8];
                pkt_buf[w_udp_base+5] <= out_udp_length[7:0];
                pkt_buf[w_udp_base+6] <= out_udp_checksum[15:8];
                pkt_buf[w_udp_base+7] <= out_udp_checksum[7:0];
            end
          end
          tx_beat <= '0;
          state   <= proc_drop ? ST_IDLE : ST_TX;
        end
      end

      ST_TX: begin
        if (m_axis_tvalid && m_axis_tready) begin
          if (tx_beat == beat_cnt - 9'd1)
            state <= ST_IDLE;
          else
            tx_beat <= tx_beat + 9'd1;
        end
      end

      default: state <= ST_IDLE;
    endcase
  end

  // ── TX output ─────────────────────────────────────────────────────────────
  always_comb begin
    m_axis_tdata  = '0;
    m_axis_tkeep  = '0;
    m_axis_tlast  = 1'b0;
    m_axis_tvalid = 1'b0;
    if (state == ST_TX) begin
      m_axis_tvalid = 1'b1;
      m_axis_tkeep  = pkt_keep[tx_beat];
      m_axis_tlast  = (tx_beat == beat_cnt - 9'd1);
      for (int i = 0; i < 8; i++)
        m_axis_tdata[i*8 +: 8] = pkt_buf[tx_beat * 8 + i];
    end
  end

endmodule
