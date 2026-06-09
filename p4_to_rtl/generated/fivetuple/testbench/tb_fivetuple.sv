// ============================================================================
// tb_fivetuple.sv — Self-checking testbench for the fiveTuple.p4 pipeline
//
// Pipeline: parser_generated → processing_generated → deparser_generated
//
// Coverage:
//   Section 1 — Parser FSM       (P1-P5): UDP, TCP, VLAN, ARP, VLAN+TCP
//   Section 2 — Processing stubs (PR1-PR5): table key capture, hit=0 default,
//               eth_type unchanged when no hit, valid_out latency
//   Section 3 — Deparser packing (D1-D4): all headers, TCP only, UDP only,
//               new_vlan slot
//   Section 4 — Integration      (INT1-INT2): UDP path through deparser,
//               valid_out pipeline
//
// NOTE: The FiveTuple table is generated as a RTL stub (hit always 0).
//       Tests verify deterministic stub behaviour. Full table testing
//       requires connecting a CAM lookup module and driving hit externally.
//
// Compile & run (Icarus Verilog — from this directory):
//   iverilog -g2012 -o sim tb_fivetuple.sv \
//     ../parser_generated.sv \
//     ../processing_generated.sv \
//     ../deparser_generated.sv
//   vvp sim
// ============================================================================
`timescale 1ns/1ps

module tb_fivetuple;

  // ── Clock ───────────────────────────────────────────────────────────────────
  localparam CLK_T = 10;
  logic clk = 0;
  always #(CLK_T/2) clk = ~clk;
  logic rst_n;

  // ============================================================================
  // 1. PARSER DUT
  //    Select inputs:  eth_type, vlan_tpid, ipv4_protocol
  //    Extract outputs: extract_eth, _vlan, _ipv4, _ipv4opt, _tcp, _tcpopt, _udp
  // ============================================================================
  logic        p_valid_in   = 0;
  logic [15:0] p_eth_type   = 0;
  logic [15:0] p_vlan_tpid  = 0;
  logic  [7:0] p_ipv4_proto = 0;

  logic p_ext_eth, p_ext_vlan, p_ext_ipv4, p_ext_ipv4opt;
  logic p_ext_tcp, p_ext_tcpopt, p_ext_udp, p_done;

  parser_generated parser_dut (
    .clk            (clk),
    .rst_n          (rst_n),
    .valid_in       (p_valid_in),
    .eth_type       (p_eth_type),
    .vlan_tpid      (p_vlan_tpid),
    .ipv4_protocol  (p_ipv4_proto),
    .extract_eth    (p_ext_eth),
    .extract_vlan   (p_ext_vlan),
    .extract_ipv4   (p_ext_ipv4),
    .extract_ipv4opt(p_ext_ipv4opt),
    .extract_tcp    (p_ext_tcp),
    .extract_tcpopt (p_ext_tcpopt),
    .extract_udp    (p_ext_udp),
    .done           (p_done)
  );

  // ============================================================================
  // 2. PROCESSING DUT
  // ============================================================================
  logic        pr_valid_in      = 0;
  logic        pr_eth_valid     = 0;
  logic        pr_new_vlan_valid= 0;
  logic        pr_vlan_valid    = 0;
  logic        pr_ipv4_valid    = 0;
  logic        pr_opt_valid     = 0;
  logic        pr_tcp_valid     = 0;
  logic        pr_tcpopt_valid  = 0;
  logic        pr_udp_valid     = 0;

  logic [47:0] pr_eth_dmac      = 0;  logic [47:0] pr_eth_smac      = 0;
  logic [15:0] pr_eth_type      = 0;
  logic  [2:0] pr_nv_pcp        = 0;  logic  [0:0] pr_nv_cfi        = 0;
  logic [11:0] pr_nv_vid        = 0;  logic [15:0] pr_nv_tpid       = 0;
  logic  [2:0] pr_vl_pcp        = 0;  logic  [0:0] pr_vl_cfi        = 0;
  logic [11:0] pr_vl_vid        = 0;  logic [15:0] pr_vl_tpid       = 0;
  logic  [3:0] pr_ipv4_ver      = 0;  logic  [3:0] pr_ipv4_ihl      = 0;
  logic  [7:0] pr_ipv4_tos      = 0;  logic [15:0] pr_ipv4_len      = 0;
  logic [15:0] pr_ipv4_id       = 0;  logic  [2:0] pr_ipv4_flg      = 0;
  logic [12:0] pr_ipv4_off      = 0;  logic  [7:0] pr_ipv4_ttl      = 0;
  logic  [7:0] pr_ipv4_proto    = 0;  logic [15:0] pr_ipv4_chk      = 0;
  logic [31:0] pr_ipv4_src      = 0;  logic [31:0] pr_ipv4_dst      = 0;
  logic [319:0] pr_opt_data     = 0;
  logic [15:0] pr_tcp_sp        = 0;  logic [15:0] pr_tcp_dp        = 0;
  logic [31:0] pr_tcp_seq       = 0;  logic [31:0] pr_tcp_ack       = 0;
  logic  [3:0] pr_tcp_doff      = 0;  logic  [5:0] pr_tcp_resv      = 0;
  logic  [5:0] pr_tcp_flags     = 0;  logic [15:0] pr_tcp_win       = 0;
  logic [15:0] pr_tcp_csum      = 0;  logic [15:0] pr_tcp_urg       = 0;
  logic [319:0] pr_tcpopt_data  = 0;
  logic [15:0] pr_udp_sp        = 0;  logic [15:0] pr_udp_dp        = 0;
  logic [15:0] pr_udp_len       = 0;  logic [15:0] pr_udp_csum      = 0;

  logic [15:0] pr_o_eth_type;
  logic [47:0] pr_o_eth_dmac, pr_o_eth_smac;
  logic  [2:0] pr_o_nv_pcp;  logic  [0:0] pr_o_nv_cfi;
  logic [11:0] pr_o_nv_vid;  logic [15:0] pr_o_nv_tpid;
  logic  [2:0] pr_o_vl_pcp;  logic  [0:0] pr_o_vl_cfi;
  logic [11:0] pr_o_vl_vid;  logic [15:0] pr_o_vl_tpid;
  logic  [3:0] pr_o_ipv4_ver, pr_o_ipv4_ihl;
  logic  [7:0] pr_o_ipv4_tos;  logic [15:0] pr_o_ipv4_len;
  logic [15:0] pr_o_ipv4_id;   logic  [2:0] pr_o_ipv4_flg;
  logic [12:0] pr_o_ipv4_off;  logic  [7:0] pr_o_ipv4_ttl;
  logic  [7:0] pr_o_ipv4_proto; logic [15:0] pr_o_ipv4_chk;
  logic [31:0] pr_o_ipv4_src, pr_o_ipv4_dst;
  logic [319:0] pr_o_opt_data;
  logic [15:0] pr_o_tcp_sp, pr_o_tcp_dp;
  logic [31:0] pr_o_tcp_seq, pr_o_tcp_ack;
  logic  [3:0] pr_o_tcp_doff;  logic  [5:0] pr_o_tcp_resv;
  logic  [5:0] pr_o_tcp_flags; logic [15:0] pr_o_tcp_win;
  logic [15:0] pr_o_tcp_csum, pr_o_tcp_urg;
  logic [319:0] pr_o_tcpopt_data;
  logic [15:0] pr_o_udp_sp, pr_o_udp_dp, pr_o_udp_len, pr_o_udp_csum;
  logic        pr_hit_out, pr_valid_out, pr_drop;

  processing_generated proc_dut (
    .clk              (clk),               .rst_n              (rst_n),
    .valid_in         (pr_valid_in),
    .eth_valid        (pr_eth_valid),      .new_vlan_valid     (pr_new_vlan_valid),
    .vlan_valid       (pr_vlan_valid),     .ipv4_valid         (pr_ipv4_valid),
    .ipv4opt_valid    (pr_opt_valid),      .tcp_valid          (pr_tcp_valid),
    .tcpopt_valid     (pr_tcpopt_valid),   .udp_valid          (pr_udp_valid),
    .eth_dmac         (pr_eth_dmac),       .eth_smac           (pr_eth_smac),
    .eth_type         (pr_eth_type),
    .new_vlan_pcp     (pr_nv_pcp),         .new_vlan_cfi       (pr_nv_cfi),
    .new_vlan_vid     (pr_nv_vid),         .new_vlan_tpid      (pr_nv_tpid),
    .vlan_pcp         (pr_vl_pcp),         .vlan_cfi           (pr_vl_cfi),
    .vlan_vid         (pr_vl_vid),         .vlan_tpid          (pr_vl_tpid),
    .ipv4_version     (pr_ipv4_ver),       .ipv4_hdr_len       (pr_ipv4_ihl),
    .ipv4_tos         (pr_ipv4_tos),       .ipv4_length        (pr_ipv4_len),
    .ipv4_id          (pr_ipv4_id),        .ipv4_flags         (pr_ipv4_flg),
    .ipv4_offset      (pr_ipv4_off),       .ipv4_ttl           (pr_ipv4_ttl),
    .ipv4_protocol    (pr_ipv4_proto),     .ipv4_hdr_chk       (pr_ipv4_chk),
    .ipv4_src         (pr_ipv4_src),       .ipv4_dst           (pr_ipv4_dst),
    .ipv4opt_options  (pr_opt_data),
    .tcp_src_port     (pr_tcp_sp),         .tcp_dst_port       (pr_tcp_dp),
    .tcp_seqNum       (pr_tcp_seq),        .tcp_ackNum         (pr_tcp_ack),
    .tcp_dataOffset   (pr_tcp_doff),       .tcp_resv           (pr_tcp_resv),
    .tcp_flags        (pr_tcp_flags),      .tcp_window         (pr_tcp_win),
    .tcp_checksum     (pr_tcp_csum),       .tcp_urgPtr         (pr_tcp_urg),
    .tcpopt_options   (pr_tcpopt_data),
    .udp_src_port     (pr_udp_sp),         .udp_dst_port       (pr_udp_dp),
    .udp_length       (pr_udp_len),        .udp_checksum       (pr_udp_csum),
    .out_eth_dmac     (pr_o_eth_dmac),     .out_eth_smac       (pr_o_eth_smac),
    .out_eth_type     (pr_o_eth_type),
    .out_new_vlan_pcp (pr_o_nv_pcp),       .out_new_vlan_cfi   (pr_o_nv_cfi),
    .out_new_vlan_vid (pr_o_nv_vid),       .out_new_vlan_tpid  (pr_o_nv_tpid),
    .out_vlan_pcp     (pr_o_vl_pcp),       .out_vlan_cfi       (pr_o_vl_cfi),
    .out_vlan_vid     (pr_o_vl_vid),       .out_vlan_tpid      (pr_o_vl_tpid),
    .out_ipv4_version (pr_o_ipv4_ver),     .out_ipv4_hdr_len   (pr_o_ipv4_ihl),
    .out_ipv4_tos     (pr_o_ipv4_tos),     .out_ipv4_length    (pr_o_ipv4_len),
    .out_ipv4_id      (pr_o_ipv4_id),      .out_ipv4_flags     (pr_o_ipv4_flg),
    .out_ipv4_offset  (pr_o_ipv4_off),     .out_ipv4_ttl       (pr_o_ipv4_ttl),
    .out_ipv4_protocol(pr_o_ipv4_proto),   .out_ipv4_hdr_chk   (pr_o_ipv4_chk),
    .out_ipv4_src     (pr_o_ipv4_src),     .out_ipv4_dst       (pr_o_ipv4_dst),
    .out_ipv4opt_options(pr_o_opt_data),
    .out_tcp_src_port (pr_o_tcp_sp),       .out_tcp_dst_port   (pr_o_tcp_dp),
    .out_tcp_seqNum   (pr_o_tcp_seq),      .out_tcp_ackNum     (pr_o_tcp_ack),
    .out_tcp_dataOffset(pr_o_tcp_doff),    .out_tcp_resv       (pr_o_tcp_resv),
    .out_tcp_flags    (pr_o_tcp_flags),    .out_tcp_window     (pr_o_tcp_win),
    .out_tcp_checksum (pr_o_tcp_csum),     .out_tcp_urgPtr     (pr_o_tcp_urg),
    .out_tcpopt_options(pr_o_tcpopt_data),
    .out_udp_src_port (pr_o_udp_sp),       .out_udp_dst_port   (pr_o_udp_dp),
    .out_udp_length   (pr_o_udp_len),      .out_udp_checksum   (pr_o_udp_csum),
    .FiveTuple_hit_out (pr_hit_out),
    .valid_out        (pr_valid_out),      .drop               (pr_drop)
  );

  // ============================================================================
  // 3. DEPARSER DUT
  //
  //  pkt_hdr_out[1199:0] layout (MSB first, 1200b total):
  //    [1199:1088] eth      112b  {dmac,smac,type}
  //    [1087:1056] new_vlan  32b  {pcp,cfi,vid,tpid}
  //    [1055:1024] vlan      32b
  //    [1023: 864] ipv4     160b
  //    [ 863: 544] ipv4opt  320b
  //    [ 543: 384] tcp      160b  {sp,dp,seq,ack,doff,resv,flags,win,csum,urg}
  //    [ 383:  64] tcpopt   320b
  //    [  63:   0] udp       64b  {sp,dp,len,csum}
  // ============================================================================
  localparam ETH_HI      = 1199; localparam ETH_LO      = 1088;
  localparam NV_HI       = 1087; localparam NV_LO       = 1056;
  localparam VL_HI       = 1055; localparam VL_LO       = 1024;
  localparam IPV4_HI     = 1023; localparam IPV4_LO     = 864;
  localparam TCP_HI      =  543; localparam TCP_LO      = 384;
  localparam UDP_HI      =   63; localparam UDP_LO      = 0;
  // Field offsets within eth slot
  localparam DMAC_HI     = 1199; localparam DMAC_LO     = 1152;
  localparam SMAC_HI     = 1151; localparam SMAC_LO     = 1104;
  localparam ETYPE_HI    = 1103; localparam ETYPE_LO    = 1088;
  // ipv4 src/dst within ipv4 slot [1023:864]
  localparam ISRC_HI     =  927; localparam ISRC_LO     = 896;
  localparam IDST_HI     =  895; localparam IDST_LO     = 864;
  // tcp sp/dp within tcp slot [543:384]
  localparam TCP_SP_HI   =  543; localparam TCP_SP_LO   = 528;
  localparam TCP_DP_HI   =  527; localparam TCP_DP_LO   = 512;
  // udp sp/dp within udp slot [63:0]
  localparam UDP_SP_HI   =   63; localparam UDP_SP_LO   = 48;
  localparam UDP_DP_HI   =   47; localparam UDP_DP_LO   = 32;

  logic        dep_valid_in     = 0;
  logic        dep_eth_valid    = 0;
  logic        dep_nv_valid     = 0;
  logic        dep_vlan_valid   = 0;
  logic        dep_ipv4_valid   = 0;
  logic        dep_opt_valid    = 0;
  logic        dep_tcp_valid    = 0;
  logic        dep_tcpopt_valid = 0;
  logic        dep_udp_valid    = 0;

  logic [47:0] dep_eth_dmac     = 0;  logic [47:0] dep_eth_smac     = 0;
  logic [15:0] dep_eth_type     = 0;
  logic  [2:0] dep_nv_pcp       = 0;  logic  [0:0] dep_nv_cfi       = 0;
  logic [11:0] dep_nv_vid       = 0;  logic [15:0] dep_nv_tpid      = 0;
  logic  [2:0] dep_vl_pcp       = 0;  logic  [0:0] dep_vl_cfi       = 0;
  logic [11:0] dep_vl_vid       = 0;  logic [15:0] dep_vl_tpid      = 0;
  logic  [3:0] dep_ipv4_ver     = 0;  logic  [3:0] dep_ipv4_ihl     = 0;
  logic  [7:0] dep_ipv4_tos     = 0;  logic [15:0] dep_ipv4_len     = 0;
  logic [15:0] dep_ipv4_id      = 0;  logic  [2:0] dep_ipv4_flg     = 0;
  logic [12:0] dep_ipv4_off     = 0;  logic  [7:0] dep_ipv4_ttl     = 0;
  logic  [7:0] dep_ipv4_proto   = 0;  logic [15:0] dep_ipv4_chk     = 0;
  logic [31:0] dep_ipv4_src     = 0;  logic [31:0] dep_ipv4_dst     = 0;
  logic [319:0] dep_opt_data    = 0;
  logic [15:0] dep_tcp_sp       = 0;  logic [15:0] dep_tcp_dp       = 0;
  logic [31:0] dep_tcp_seq      = 0;  logic [31:0] dep_tcp_ack      = 0;
  logic  [3:0] dep_tcp_doff     = 0;  logic  [5:0] dep_tcp_resv     = 0;
  logic  [5:0] dep_tcp_flags    = 0;  logic [15:0] dep_tcp_win      = 0;
  logic [15:0] dep_tcp_csum     = 0;  logic [15:0] dep_tcp_urg      = 0;
  logic [319:0] dep_tcpopt_data = 0;
  logic [15:0] dep_udp_sp       = 0;  logic [15:0] dep_udp_dp       = 0;
  logic [15:0] dep_udp_len      = 0;  logic [15:0] dep_udp_csum     = 0;

  logic [1199:0] dep_pkt_out;
  logic  [15:0]  dep_pkt_len;
  logic          dep_valid_out;

  deparser_generated dep_dut (
    .clk            (clk),              .rst_n          (rst_n),
    .valid_in       (dep_valid_in),
    .eth_valid      (dep_eth_valid),    .new_vlan_valid (dep_nv_valid),
    .vlan_valid     (dep_vlan_valid),   .ipv4_valid     (dep_ipv4_valid),
    .ipv4opt_valid  (dep_opt_valid),    .tcp_valid      (dep_tcp_valid),
    .tcpopt_valid   (dep_tcpopt_valid), .udp_valid      (dep_udp_valid),
    .eth_dmac       (dep_eth_dmac),     .eth_smac       (dep_eth_smac),
    .eth_type       (dep_eth_type),
    .new_vlan_pcp   (dep_nv_pcp),       .new_vlan_cfi   (dep_nv_cfi),
    .new_vlan_vid   (dep_nv_vid),       .new_vlan_tpid  (dep_nv_tpid),
    .vlan_pcp       (dep_vl_pcp),       .vlan_cfi       (dep_vl_cfi),
    .vlan_vid       (dep_vl_vid),       .vlan_tpid      (dep_vl_tpid),
    .ipv4_version   (dep_ipv4_ver),     .ipv4_hdr_len   (dep_ipv4_ihl),
    .ipv4_tos       (dep_ipv4_tos),     .ipv4_length    (dep_ipv4_len),
    .ipv4_id        (dep_ipv4_id),      .ipv4_flags     (dep_ipv4_flg),
    .ipv4_offset    (dep_ipv4_off),     .ipv4_ttl       (dep_ipv4_ttl),
    .ipv4_protocol  (dep_ipv4_proto),   .ipv4_hdr_chk   (dep_ipv4_chk),
    .ipv4_src       (dep_ipv4_src),     .ipv4_dst       (dep_ipv4_dst),
    .ipv4opt_options(dep_opt_data),
    .tcp_src_port   (dep_tcp_sp),       .tcp_dst_port   (dep_tcp_dp),
    .tcp_seqNum     (dep_tcp_seq),      .tcp_ackNum     (dep_tcp_ack),
    .tcp_dataOffset (dep_tcp_doff),     .tcp_resv       (dep_tcp_resv),
    .tcp_flags      (dep_tcp_flags),    .tcp_window     (dep_tcp_win),
    .tcp_checksum   (dep_tcp_csum),     .tcp_urgPtr     (dep_tcp_urg),
    .tcpopt_options (dep_tcpopt_data),
    .udp_src_port   (dep_udp_sp),       .udp_dst_port   (dep_udp_dp),
    .udp_length     (dep_udp_len),      .udp_checksum   (dep_udp_csum),
    .pkt_hdr_out    (dep_pkt_out),      .pkt_hdr_len    (dep_pkt_len),
    .valid_out      (dep_valid_out)
  );

  // ============================================================================
  // Test infrastructure
  // ============================================================================
  int pass_cnt = 0, fail_cnt = 0;

  task automatic chk(input string name, input logic cond);
    if (cond) begin
      $display("    [PASS] %s", name);
      pass_cnt++;
    end else begin
      $display("    [FAIL] %s", name);
      fail_cnt++;
    end
  endtask

  task do_reset;
    rst_n      = 0;
    p_valid_in = 0;
    repeat (3) @(posedge clk);
    @(negedge clk);
    rst_n = 1;
    @(posedge clk); #1;
  endtask

  // ============================================================================
  // MAIN TEST SEQUENCE
  // ============================================================================
  initial begin
    $dumpfile("tb_fivetuple.vcd");
    $dumpvars(0, tb_fivetuple);

    // ──────────────────────────────────────────────────────────────────────────
    // SECTION 1 — PARSER FSM
    // ──────────────────────────────────────────────────────────────────────────
    $display("\n══ Section 1: Parser FSM ══════════════════════════════════════");

    // ── P1: Full IPv4/UDP parse path ─────────────────────────────────────────
    $display("  P1: IPv4/UDP full parse");
    do_reset();
    p_eth_type = 16'h0800; p_ipv4_proto = 8'h11; p_valid_in = 1; #1;
    chk("P1 START: no extract_eth",       !p_ext_eth);
    @(posedge clk); #1;               // → PARSE_ETH
    chk("P1 PARSE_ETH: extract_eth",      p_ext_eth);
    @(posedge clk); #1;               // → PARSE_IPV4
    chk("P1 PARSE_IPV4: extract_ipv4",    p_ext_ipv4);
    chk("P1 PARSE_IPV4: extract_ipv4opt", p_ext_ipv4opt);
    chk("P1 PARSE_IPV4: no extract_tcp",  !p_ext_tcp);
    @(posedge clk); #1;               // → PARSE_UDP
    chk("P1 PARSE_UDP: extract_udp",      p_ext_udp);
    chk("P1 PARSE_UDP: no extract_tcp",   !p_ext_tcp);
    @(posedge clk); #1;               // → ACCEPT
    chk("P1 ACCEPT: done",                p_done);
    p_valid_in = 0;

    // ── P2: Full IPv4/TCP parse path ─────────────────────────────────────────
    $display("  P2: IPv4/TCP full parse");
    do_reset();
    p_eth_type = 16'h0800; p_ipv4_proto = 8'h06; p_valid_in = 1;
    @(posedge clk); #1;               // → PARSE_ETH
    chk("P2 PARSE_ETH: extract_eth",      p_ext_eth);
    @(posedge clk); #1;               // → PARSE_IPV4
    chk("P2 PARSE_IPV4: extract_ipv4",    p_ext_ipv4);
    @(posedge clk); #1;               // → PARSE_TCP
    chk("P2 PARSE_TCP: extract_tcp",      p_ext_tcp);
    chk("P2 PARSE_TCP: extract_tcpopt",   p_ext_tcpopt);
    chk("P2 PARSE_TCP: no extract_udp",   !p_ext_udp);
    @(posedge clk); #1;               // → ACCEPT
    chk("P2 ACCEPT: done",                p_done);
    p_valid_in = 0;

    // ── P3: VLAN-tagged IPv4/UDP ─────────────────────────────────────────────
    $display("  P3: VLAN-tagged IPv4/UDP");
    do_reset();
    p_eth_type  = 16'h8100;
    p_vlan_tpid = 16'h0800;
    p_ipv4_proto = 8'h11; p_valid_in = 1;
    @(posedge clk); #1;               // → PARSE_ETH
    chk("P3 PARSE_ETH: extract_eth",      p_ext_eth);
    @(posedge clk); #1;               // → PARSE_VLAN
    chk("P3 PARSE_VLAN: extract_vlan",    p_ext_vlan);
    chk("P3 PARSE_VLAN: no extract_ipv4", !p_ext_ipv4);
    @(posedge clk); #1;               // → PARSE_IPV4
    chk("P3 PARSE_IPV4: extract_ipv4",    p_ext_ipv4);
    @(posedge clk); #1;               // → PARSE_UDP
    chk("P3 PARSE_UDP: extract_udp",      p_ext_udp);
    @(posedge clk); #1;               // → ACCEPT
    chk("P3 ACCEPT: done",                p_done);
    p_valid_in = 0;

    // ── P4: ARP → early accept ───────────────────────────────────────────────
    $display("  P4: ARP (0x0806) → early accept after PARSE_ETH");
    do_reset();
    p_eth_type = 16'h0806; p_valid_in = 1;
    @(posedge clk); #1;               // → PARSE_ETH
    @(posedge clk); #1;               // → ACCEPT
    chk("P4 ACCEPT: done",                p_done);
    chk("P4 ACCEPT: no extract_ipv4",     !p_ext_ipv4);
    p_valid_in = 0;

    // ── P5: IPv4 non-TCP/UDP (ICMP 0x01) → ACCEPT without L4 ───────────────
    $display("  P5: IPv4/ICMP (proto=0x01) → accept without L4");
    do_reset();
    p_eth_type = 16'h0800; p_ipv4_proto = 8'h01; p_valid_in = 1;
    @(posedge clk); #1;               // PARSE_ETH
    @(posedge clk); #1;               // PARSE_IPV4
    @(posedge clk); #1;               // ACCEPT (default)
    chk("P5 ACCEPT: done",                p_done);
    chk("P5 ACCEPT: no extract_tcp",      !p_ext_tcp);
    chk("P5 ACCEPT: no extract_udp",      !p_ext_udp);
    p_valid_in = 0;

    // ──────────────────────────────────────────────────────────────────────────
    // SECTION 2 — PROCESSING (TABLE STUB)
    // ──────────────────────────────────────────────────────────────────────────
    $display("\n══ Section 2: Processing (Table Stub) ════════════════════════");

    // Stable defaults
    pr_eth_valid = 1; pr_ipv4_valid = 1; pr_udp_valid = 1;
    pr_new_vlan_valid = 0; pr_vlan_valid = 0;
    pr_tcp_valid = 0; pr_opt_valid = 0; pr_tcpopt_valid = 0;
    pr_eth_type  = 16'h0800;
    pr_ipv4_ver = 4'h4; pr_ipv4_ihl = 4'h5; pr_ipv4_tos = 8'h00;
    pr_ipv4_len = 16'd40; pr_ipv4_id = 16'd1; pr_ipv4_flg = 3'b010;
    pr_ipv4_off = 13'd0; pr_ipv4_ttl = 8'd64; pr_ipv4_proto = 8'h11;
    pr_ipv4_chk = 16'hBEEF;
    pr_eth_dmac = 48'hAABBCCDDEEFF; pr_eth_smac = 48'h112233445566;
    pr_ipv4_src = 32'hC0A80001;     pr_ipv4_dst = 32'hC0A80002;
    pr_udp_sp   = 16'h1234;         pr_udp_dp   = 16'h5678;
    pr_udp_len  = 16'd20;           pr_udp_csum = 16'hCAFE;
    pr_opt_data = '0;

    // ── PR1: hit=0 by default (table stub) ───────────────────────────────────
    $display("  PR1: table stub → hit=0, eth_type unchanged");
    #1;
    chk("PR1: hit_out = 0",           !pr_hit_out);
    chk("PR1: eth_type unchanged",    pr_o_eth_type == 16'h0800);
    chk("PR1: dmac pass-through",     pr_o_eth_dmac == 48'hAABBCCDDEEFF);
    chk("PR1: not dropped",           !pr_drop);

    // ── PR2: UDP path → table_key ports captured (stub; not directly visible
    //         but hit=0 means no eth_type change) ────────────────────────────
    $display("  PR2: UDP valid → table_key assigned, no hit → eth_type stays");
    pr_udp_valid = 1; pr_tcp_valid = 0;
    pr_udp_sp = 16'hAAAA; pr_udp_dp = 16'hBBBB; #1;
    chk("PR2: no hit",                !pr_hit_out);
    chk("PR2: eth_type = 0x0800",     pr_o_eth_type == 16'h0800);

    // ── PR3: TCP path (udp_valid=0, tcp_valid=1) ─────────────────────────────
    $display("  PR3: TCP valid → tcp path taken, hit=0 still");
    pr_udp_valid = 0; pr_tcp_valid = 1;
    pr_tcp_sp = 16'h1234; pr_tcp_dp = 16'h5000; #1;
    chk("PR3: no hit (tcp path)",     !pr_hit_out);
    chk("PR3: eth_type unchanged",    pr_o_eth_type == 16'h0800);
    chk("PR3: tcp fields pass-thru",  pr_o_tcp_sp == 16'h1234);
    pr_tcp_valid = 0; pr_udp_valid = 1;

    // ── PR4: vlan_valid=1, hit=0 → eth_type stays unchanged ─────────────────
    $display("  PR4: vlan_valid=1 + hit=0 → eth_type NOT modified");
    pr_vlan_valid = 1; pr_udp_valid = 1; #1;
    chk("PR4: hit=0 → no eth_type change", pr_o_eth_type == 16'h0800);
    pr_vlan_valid = 0;

    // ── PR5: valid_out pipeline register ─────────────────────────────────────
    $display("  PR5: valid_out registered (1-cycle latency)");
    do_reset();
    pr_valid_in = 1; #1;
    chk("PR5: valid_out=0 before posedge",  !pr_valid_out);
    @(posedge clk); #1;
    chk("PR5: valid_out=1 after posedge",   pr_valid_out);
    pr_valid_in = 0;
    @(posedge clk); #1;
    chk("PR5: valid_out=0 after deassert",  !pr_valid_out);

    // ──────────────────────────────────────────────────────────────────────────
    // SECTION 3 — DEPARSER PACKING  (1200-bit output bus)
    // ──────────────────────────────────────────────────────────────────────────
    $display("\n══ Section 3: Deparser Packing ════════════════════════════════");

    dep_eth_dmac  = 48'hAABBCCDDEEFF; dep_eth_smac  = 48'h112233445566;
    dep_eth_type  = 16'h0800;
    dep_nv_pcp    = 3'b010; dep_nv_cfi = 1'b0; dep_nv_vid = 12'hABC;
    dep_nv_tpid   = 16'h0800;
    dep_vl_pcp    = 3'd0; dep_vl_cfi = 1'b0; dep_vl_vid = 12'd100;
    dep_vl_tpid   = 16'h0800;
    dep_ipv4_ver  = 4'h4; dep_ipv4_ihl = 4'h5; dep_ipv4_tos  = 8'd0;
    dep_ipv4_len  = 16'd40; dep_ipv4_id = 16'd1; dep_ipv4_flg  = 3'b010;
    dep_ipv4_off  = 13'd0; dep_ipv4_ttl = 8'd64; dep_ipv4_proto = 8'h11;
    dep_ipv4_chk  = 16'hBEEF; dep_ipv4_src = 32'hC0A80001;
    dep_ipv4_dst  = 32'hC0A80002;
    dep_opt_data  = '0;
    dep_tcp_sp    = 16'h1234; dep_tcp_dp = 16'h5000;
    dep_tcp_seq   = 32'hDEADBEEF; dep_tcp_ack = 32'hCAFEBABE;
    dep_tcp_doff  = 4'h5; dep_tcp_resv = 6'd0; dep_tcp_flags = 6'h02;
    dep_tcp_win   = 16'hFFFF; dep_tcp_csum = 16'hBEEF; dep_tcp_urg = 16'd0;
    dep_tcpopt_data = '0;
    dep_udp_sp    = 16'h1234; dep_udp_dp = 16'h5678;
    dep_udp_len   = 16'd20;   dep_udp_csum = 16'hCAFE;

    // ── D1: UDP packet (eth+ipv4+udp) → len=336 ─────────────────────────────
    $display("  D1: eth+ipv4+udp valid → pkt_hdr_len=336");
    dep_eth_valid = 1; dep_nv_valid = 0; dep_vlan_valid = 0;
    dep_ipv4_valid = 1; dep_opt_valid = 0; dep_tcp_valid = 0;
    dep_tcpopt_valid = 0; dep_udp_valid = 1;
    #1;
    chk("D1: pkt_hdr_len = 336",         dep_pkt_len == 16'd336);
    chk("D1: eth dmac at [1199:1152]",   dep_pkt_out[DMAC_HI:DMAC_LO] == 48'hAABBCCDDEEFF);
    chk("D1: eth smac at [1151:1104]",   dep_pkt_out[SMAC_HI:SMAC_LO] == 48'h112233445566);
    chk("D1: eth type at [1103:1088]",   dep_pkt_out[ETYPE_HI:ETYPE_LO] == 16'h0800);
    chk("D1: ipv4 src at [991:960]",     dep_pkt_out[ISRC_HI:ISRC_LO] == 32'hC0A80001);
    chk("D1: udp sp at [63:48]",         dep_pkt_out[UDP_SP_HI:UDP_SP_LO] == 16'h1234);
    chk("D1: udp dp at [47:32]",         dep_pkt_out[UDP_DP_HI:UDP_DP_LO] == 16'h5678);
    chk("D1: new_vlan slot zeroed",      dep_pkt_out[NV_HI:NV_LO] == 32'h0);
    chk("D1: tcp slot zeroed",           dep_pkt_out[TCP_HI:TCP_LO] == 160'h0);

    // ── D2: TCP packet (eth+ipv4+tcp) → len=432 ─────────────────────────────
    $display("  D2: eth+ipv4+tcp valid → pkt_hdr_len=432");
    dep_eth_valid = 1; dep_nv_valid = 0; dep_vlan_valid = 0;
    dep_ipv4_valid = 1; dep_opt_valid = 0; dep_tcp_valid = 1;
    dep_tcpopt_valid = 0; dep_udp_valid = 0;
    #1;
    chk("D2: pkt_hdr_len = 432",         dep_pkt_len == 16'd432);
    chk("D2: tcp sp at [543:528]",       dep_pkt_out[TCP_SP_HI:TCP_SP_LO] == 16'h1234);
    chk("D2: tcp dp at [527:512]",       dep_pkt_out[TCP_DP_HI:TCP_DP_LO] == 16'h5000);
    chk("D2: udp slot zeroed",           dep_pkt_out[UDP_HI:UDP_LO] == 64'h0);

    // ── D3: All headers (eth+nv+vlan+ipv4+opt+tcp+tcpopt+udp) → len=1200 ────
    $display("  D3: all headers valid → pkt_hdr_len=1200");
    dep_eth_valid = 1; dep_nv_valid = 1; dep_vlan_valid = 1;
    dep_ipv4_valid = 1; dep_opt_valid = 1; dep_tcp_valid = 1;
    dep_tcpopt_valid = 1; dep_udp_valid = 1;
    #1;
    chk("D3: pkt_hdr_len = 1200",        dep_pkt_len == 16'd1200);
    chk("D3: eth dmac present",          dep_pkt_out[DMAC_HI:DMAC_LO] == 48'hAABBCCDDEEFF);

    // ── D4: No headers → all zeros ───────────────────────────────────────────
    $display("  D4: no headers valid → pkt_hdr_len=0");
    dep_eth_valid = 0; dep_nv_valid = 0; dep_vlan_valid = 0;
    dep_ipv4_valid = 0; dep_opt_valid = 0; dep_tcp_valid = 0;
    dep_tcpopt_valid = 0; dep_udp_valid = 0;
    #1;
    chk("D4: pkt_hdr_len = 0",           dep_pkt_len == 16'd0);
    chk("D4: pkt_hdr_out all zeros",     dep_pkt_out == 1200'h0);

    // ──────────────────────────────────────────────────────────────────────────
    // SECTION 4 — INTEGRATION
    // ──────────────────────────────────────────────────────────────────────────
    $display("\n══ Section 4: Integration Tests ═══════════════════════════════");

    // ── INT1: Processing outputs flow into deparser correctly (UDP path) ──────
    $display("  INT1: processing outputs routed to deparser (UDP path, hit=0)");
    pr_eth_valid = 1; pr_ipv4_valid = 1; pr_udp_valid = 1;
    pr_tcp_valid = 0; pr_vlan_valid = 0;
    pr_eth_dmac   = 48'hDEADBEEFCAFE; pr_eth_smac   = 48'hCAFEBEEFDEAD;
    pr_eth_type   = 16'h0800;
    pr_ipv4_src   = 32'h0A000001; pr_ipv4_dst = 32'h0A000002;
    pr_ipv4_ver   = 4'h4; pr_ipv4_ihl = 4'h5; pr_ipv4_tos = 8'd0;
    pr_ipv4_len   = 16'd40; pr_ipv4_id = 16'd5; pr_ipv4_flg = 3'b000;
    pr_ipv4_off   = 13'd0; pr_ipv4_ttl = 8'd128; pr_ipv4_proto = 8'h11;
    pr_ipv4_chk   = 16'h1234;
    pr_udp_sp     = 16'hAAAA; pr_udp_dp = 16'hBBBB;
    pr_udp_len    = 16'd20; pr_udp_csum = 16'hCCCC;
    pr_opt_data   = '0; #1;

    dep_eth_valid  = 1; dep_nv_valid = 0; dep_vlan_valid = 0;
    dep_ipv4_valid = 1; dep_opt_valid = 0; dep_tcp_valid = 0;
    dep_tcpopt_valid = 0; dep_udp_valid = 1;
    dep_eth_dmac   = pr_o_eth_dmac;  dep_eth_smac   = pr_o_eth_smac;
    dep_eth_type   = pr_o_eth_type;
    dep_ipv4_ver   = pr_o_ipv4_ver;  dep_ipv4_ihl   = pr_o_ipv4_ihl;
    dep_ipv4_tos   = pr_o_ipv4_tos;  dep_ipv4_len   = pr_o_ipv4_len;
    dep_ipv4_id    = pr_o_ipv4_id;   dep_ipv4_flg   = pr_o_ipv4_flg;
    dep_ipv4_off   = pr_o_ipv4_off;  dep_ipv4_ttl   = pr_o_ipv4_ttl;
    dep_ipv4_proto = pr_o_ipv4_proto; dep_ipv4_chk  = pr_o_ipv4_chk;
    dep_ipv4_src   = pr_o_ipv4_src;  dep_ipv4_dst   = pr_o_ipv4_dst;
    dep_udp_sp     = pr_o_udp_sp;    dep_udp_dp     = pr_o_udp_dp;
    dep_udp_len    = pr_o_udp_len;   dep_udp_csum   = pr_o_udp_csum;
    dep_opt_data   = '0; #1;

    chk("INT1: dep eth dmac at [1199:1152]",
        dep_pkt_out[DMAC_HI:DMAC_LO] == 48'hDEADBEEFCAFE);
    chk("INT1: dep ipv4 src at [991:960]",
        dep_pkt_out[ISRC_HI:ISRC_LO] == 32'h0A000001);
    chk("INT1: dep udp sp at [63:48]",
        dep_pkt_out[UDP_SP_HI:UDP_SP_LO] == 16'hAAAA);
    chk("INT1: pkt_hdr_len = 336 (eth+ipv4+udp)",
        dep_pkt_len == 16'd336);

    // ── INT2: deparser valid_out latency ────────────────────────────────────
    $display("  INT2: deparser valid_out one-cycle registered");
    do_reset();
    dep_eth_valid = 1; dep_ipv4_valid = 0; dep_udp_valid = 0;
    dep_tcp_valid = 0; dep_nv_valid = 0; dep_vlan_valid = 0;
    dep_valid_in  = 1; #1;
    chk("INT2: valid_out=0 before posedge", !dep_valid_out);
    @(posedge clk); #1;
    chk("INT2: valid_out=1 after posedge",  dep_valid_out);
    dep_valid_in = 0;
    @(posedge clk); #1;
    chk("INT2: valid_out=0 after deassert", !dep_valid_out);

    // ──────────────────────────────────────────────────────────────────────────
    // SUMMARY
    // ──────────────────────────────────────────────────────────────────────────
    $display("\n════════════════════════════════════════════════════════════════");
    $display("  Results: %0d passed, %0d failed  (total %0d)",
             pass_cnt, fail_cnt, pass_cnt + fail_cnt);
    $display("════════════════════════════════════════════════════════════════");
    if (fail_cnt == 0)
      $display("  ALL TESTS PASSED");
    else
      $display("  FAILURES DETECTED — see [FAIL] lines above");
    $display("\n  NOTE: FiveTuple table is RTL-stubbed (hit always 0).");
    $display("        For full table testing, connect a CAM lookup module");
    $display("        and drive hit_out externally.\n");
    $finish;
  end

  initial begin #500000; $display("[TIMEOUT]"); $finish; end

endmodule
