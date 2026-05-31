// ============================================================================
// tb_load_balance.sv — Self-checking testbench for load_balance.p4 pipeline
//
// Pipeline: V1Switch → MyIngress used as processing_generated
//           parser_generated / processing_generated / deparser_generated
//
// Coverage:
//   Section 1 — Parser FSM       (P1-P4): Eth→IPv4→TCP, IPv4-only, ARP, VLAN
//   Section 2 — Processing stubs (PR1-PR5): table stubs (hit=0), pass-through,
//               TTL=0 guard, ipv4_valid=0 guard, valid_out latency
//   Section 3 — Deparser packing (D1-D4): all/eth-only/no-headers/len check
//   Section 4 — Integration      (INT1-INT2): processing→deparser, valid_out
//
// NOTE: ecmp_group and ecmp_nhop tables are RTL-stubbed (hit always 0).
//       ecmp_group_hit_out is exposed as an output for external CAM connection.
//
// Compile (from this directory):
//   iverilog -g2012 -o sim tb_load_balance.sv \
//     ../parser_generated.sv ../processing_generated.sv ../deparser_generated.sv
//   vvp sim
// ============================================================================
`timescale 1ns/1ps

module tb_load_balance;

  // ── Clock ───────────────────────────────────────────────────────────────────
  localparam CLK_T = 10;
  logic clk = 0;
  always #(CLK_T/2) clk = ~clk;
  logic rst_n;

  // ============================================================================
  // 1. PARSER DUT
  //    select fields: ethernet_etherType [15:0], ipv4_protocol [7:0]
  // ============================================================================
  logic        p_valid_in    = 0;
  logic [15:0] p_eth_type    = 0;
  logic  [7:0] p_ipv4_proto  = 0;

  logic p_ext_eth, p_ext_ipv4, p_ext_tcp, p_done;

  parser_generated parser_dut (
    .clk                 (clk),
    .rst_n               (rst_n),
    .valid_in            (p_valid_in),
    .ethernet_etherType  (p_eth_type),
    .ipv4_protocol       (p_ipv4_proto),
    .extract_ethernet    (p_ext_eth),
    .extract_ipv4        (p_ext_ipv4),
    .extract_tcp         (p_ext_tcp),
    .done                (p_done)
  );

  // ============================================================================
  // 2. PROCESSING DUT  (MyIngress)
  // ============================================================================
  logic        pr_valid_in     = 0;
  logic        pr_eth_valid    = 0;
  logic        pr_ipv4_valid   = 0;
  logic        pr_tcp_valid    = 0;

  logic [47:0] pr_eth_dst      = 0;  logic [47:0] pr_eth_src      = 0;
  logic [15:0] pr_eth_type     = 0;
  logic  [3:0] pr_ipv4_ver     = 0;  logic  [3:0] pr_ipv4_ihl     = 0;
  logic  [7:0] pr_ipv4_ds      = 0;  logic [15:0] pr_ipv4_len     = 0;
  logic [15:0] pr_ipv4_id      = 0;  logic  [2:0] pr_ipv4_flg     = 0;
  logic [12:0] pr_ipv4_off     = 0;  logic  [7:0] pr_ipv4_ttl     = 0;
  logic  [7:0] pr_ipv4_proto   = 0;  logic [15:0] pr_ipv4_chk     = 0;
  logic [31:0] pr_ipv4_src     = 0;  logic [31:0] pr_ipv4_dst     = 0;
  logic [15:0] pr_tcp_sp       = 0;  logic [15:0] pr_tcp_dp       = 0;
  logic [31:0] pr_tcp_seq      = 0;  logic [31:0] pr_tcp_ack      = 0;
  logic  [3:0] pr_tcp_doff     = 0;  logic  [2:0] pr_tcp_res      = 0;
  logic  [2:0] pr_tcp_ecn      = 0;  logic  [5:0] pr_tcp_ctrl     = 0;
  logic [15:0] pr_tcp_win      = 0;  logic [15:0] pr_tcp_csum     = 0;
  logic [15:0] pr_tcp_urg      = 0;
  logic [13:0] pr_meta_ecmp    = 0;

  logic [47:0] pr_o_eth_dst,  pr_o_eth_src;
  logic [15:0] pr_o_eth_type;
  logic  [7:0] pr_o_ipv4_ttl, pr_o_ipv4_proto;
  logic [31:0] pr_o_ipv4_src, pr_o_ipv4_dst;
  logic [15:0] pr_o_ipv4_chk;
  logic  [3:0] pr_o_ipv4_ver, pr_o_ipv4_ihl;
  logic  [7:0] pr_o_ipv4_ds;  logic [15:0] pr_o_ipv4_len;
  logic [15:0] pr_o_ipv4_id;  logic  [2:0] pr_o_ipv4_flg;
  logic [12:0] pr_o_ipv4_off;
  logic [15:0] pr_o_tcp_sp, pr_o_tcp_dp;
  logic [31:0] pr_o_tcp_seq, pr_o_tcp_ack;
  logic  [3:0] pr_o_tcp_doff; logic  [2:0] pr_o_tcp_res;
  logic  [2:0] pr_o_tcp_ecn;  logic  [5:0] pr_o_tcp_ctrl;
  logic [15:0] pr_o_tcp_win, pr_o_tcp_csum, pr_o_tcp_urg;
  logic        pr_hit_out, pr_valid_out, pr_drop;

  processing_generated proc_dut (
    .clk                     (clk),               .rst_n              (rst_n),
    .valid_in                (pr_valid_in),
    .ethernet_valid          (pr_eth_valid),       .ipv4_valid         (pr_ipv4_valid),
    .tcp_valid               (pr_tcp_valid),
    .ethernet_dstAddr        (pr_eth_dst),         .ethernet_srcAddr   (pr_eth_src),
    .ethernet_etherType      (pr_eth_type),
    .ipv4_version            (pr_ipv4_ver),        .ipv4_ihl           (pr_ipv4_ihl),
    .ipv4_diffserv           (pr_ipv4_ds),         .ipv4_totalLen      (pr_ipv4_len),
    .ipv4_identification     (pr_ipv4_id),         .ipv4_flags         (pr_ipv4_flg),
    .ipv4_fragOffset         (pr_ipv4_off),        .ipv4_ttl           (pr_ipv4_ttl),
    .ipv4_protocol           (pr_ipv4_proto),      .ipv4_hdrChecksum   (pr_ipv4_chk),
    .ipv4_srcAddr            (pr_ipv4_src),        .ipv4_dstAddr       (pr_ipv4_dst),
    .tcp_srcPort             (pr_tcp_sp),          .tcp_dstPort        (pr_tcp_dp),
    .tcp_seqNo               (pr_tcp_seq),         .tcp_ackNo          (pr_tcp_ack),
    .tcp_dataOffset          (pr_tcp_doff),        .tcp_res            (pr_tcp_res),
    .tcp_ecn                 (pr_tcp_ecn),         .tcp_ctrl           (pr_tcp_ctrl),
    .tcp_window              (pr_tcp_win),         .tcp_checksum       (pr_tcp_csum),
    .tcp_urgentPtr           (pr_tcp_urg),
    .meta_ecmp_select        (pr_meta_ecmp),
    .out_ethernet_dstAddr    (pr_o_eth_dst),       .out_ethernet_srcAddr(pr_o_eth_src),
    .out_ethernet_etherType  (pr_o_eth_type),
    .out_ipv4_version        (pr_o_ipv4_ver),      .out_ipv4_ihl       (pr_o_ipv4_ihl),
    .out_ipv4_diffserv       (pr_o_ipv4_ds),       .out_ipv4_totalLen  (pr_o_ipv4_len),
    .out_ipv4_identification (pr_o_ipv4_id),       .out_ipv4_flags     (pr_o_ipv4_flg),
    .out_ipv4_fragOffset     (pr_o_ipv4_off),      .out_ipv4_ttl       (pr_o_ipv4_ttl),
    .out_ipv4_protocol       (pr_o_ipv4_proto),    .out_ipv4_hdrChecksum(pr_o_ipv4_chk),
    .out_ipv4_srcAddr        (pr_o_ipv4_src),      .out_ipv4_dstAddr   (pr_o_ipv4_dst),
    .out_tcp_srcPort         (pr_o_tcp_sp),        .out_tcp_dstPort    (pr_o_tcp_dp),
    .out_tcp_seqNo           (pr_o_tcp_seq),       .out_tcp_ackNo      (pr_o_tcp_ack),
    .out_tcp_dataOffset      (pr_o_tcp_doff),      .out_tcp_res        (pr_o_tcp_res),
    .out_tcp_ecn             (pr_o_tcp_ecn),       .out_tcp_ctrl       (pr_o_tcp_ctrl),
    .out_tcp_window          (pr_o_tcp_win),       .out_tcp_checksum   (pr_o_tcp_csum),
    .out_tcp_urgentPtr       (pr_o_tcp_urg),
    .ecmp_group_hit_out      (pr_hit_out),
    .valid_out               (pr_valid_out),       .drop               (pr_drop)
  );

  // ============================================================================
  // 3. DEPARSER DUT
  //   pkt_hdr_out[431:0] layout:
  //     [431:320] ethernet  112b  {dstAddr,srcAddr,etherType}
  //     [319:160] ipv4      160b
  //     [159:  0] tcp       160b  {srcPort,dstPort,seqNo,ackNo,...}
  // ============================================================================
  localparam ETH_HI    = 431; localparam ETH_LO    = 320;
  localparam IPV4_HI   = 319; localparam IPV4_LO   = 160;
  localparam TCP_HI    = 159; localparam TCP_LO    = 0;
  localparam DST_HI    = 431; localparam DST_LO    = 384;
  localparam SRC_HI    = 383; localparam SRC_LO    = 336;
  localparam TYPE_HI   = 335; localparam TYPE_LO   = 320;
  localparam TTL_HI    = 255; localparam TTL_LO    = 248;
  localparam ISRC_HI   = 223; localparam ISRC_LO   = 192;
  localparam IDST_HI   = 191; localparam IDST_LO   = 160;
  localparam TCP_SP_HI = 159; localparam TCP_SP_LO = 144;
  localparam TCP_DP_HI = 143; localparam TCP_DP_LO = 128;

  logic        dep_valid_in  = 0;
  logic        dep_eth_valid = 0;
  logic        dep_ipv4_valid= 0;
  logic        dep_tcp_valid = 0;

  logic [47:0] dep_eth_dst   = 0;  logic [47:0] dep_eth_src   = 0;
  logic [15:0] dep_eth_type  = 0;
  logic  [3:0] dep_ipv4_ver  = 0;  logic  [3:0] dep_ipv4_ihl  = 0;
  logic  [7:0] dep_ipv4_ds   = 0;  logic [15:0] dep_ipv4_len  = 0;
  logic [15:0] dep_ipv4_id   = 0;  logic  [2:0] dep_ipv4_flg  = 0;
  logic [12:0] dep_ipv4_off  = 0;  logic  [7:0] dep_ipv4_ttl  = 0;
  logic  [7:0] dep_ipv4_proto= 0;  logic [15:0] dep_ipv4_chk  = 0;
  logic [31:0] dep_ipv4_src  = 0;  logic [31:0] dep_ipv4_dst  = 0;
  logic [15:0] dep_tcp_sp    = 0;  logic [15:0] dep_tcp_dp    = 0;
  logic [31:0] dep_tcp_seq   = 0;  logic [31:0] dep_tcp_ack   = 0;
  logic  [3:0] dep_tcp_doff  = 0;  logic  [2:0] dep_tcp_res   = 0;
  logic  [2:0] dep_tcp_ecn   = 0;  logic  [5:0] dep_tcp_ctrl  = 0;
  logic [15:0] dep_tcp_win   = 0;  logic [15:0] dep_tcp_csum  = 0;
  logic [15:0] dep_tcp_urg   = 0;

  logic [431:0] dep_pkt_out;
  logic [15:0]  dep_pkt_len;
  logic         dep_valid_out;

  deparser_generated dep_dut (
    .clk                     (clk),               .rst_n          (rst_n),
    .valid_in                (dep_valid_in),
    .ethernet_valid          (dep_eth_valid),      .ipv4_valid     (dep_ipv4_valid),
    .tcp_valid               (dep_tcp_valid),
    .ethernet_dstAddr        (dep_eth_dst),        .ethernet_srcAddr(dep_eth_src),
    .ethernet_etherType      (dep_eth_type),
    .ipv4_version            (dep_ipv4_ver),       .ipv4_ihl       (dep_ipv4_ihl),
    .ipv4_diffserv           (dep_ipv4_ds),        .ipv4_totalLen  (dep_ipv4_len),
    .ipv4_identification     (dep_ipv4_id),        .ipv4_flags     (dep_ipv4_flg),
    .ipv4_fragOffset         (dep_ipv4_off),       .ipv4_ttl       (dep_ipv4_ttl),
    .ipv4_protocol           (dep_ipv4_proto),     .ipv4_hdrChecksum(dep_ipv4_chk),
    .ipv4_srcAddr            (dep_ipv4_src),       .ipv4_dstAddr   (dep_ipv4_dst),
    .tcp_srcPort             (dep_tcp_sp),         .tcp_dstPort    (dep_tcp_dp),
    .tcp_seqNo               (dep_tcp_seq),        .tcp_ackNo      (dep_tcp_ack),
    .tcp_dataOffset          (dep_tcp_doff),       .tcp_res        (dep_tcp_res),
    .tcp_ecn                 (dep_tcp_ecn),        .tcp_ctrl       (dep_tcp_ctrl),
    .tcp_window              (dep_tcp_win),        .tcp_checksum   (dep_tcp_csum),
    .tcp_urgentPtr           (dep_tcp_urg),
    .pkt_hdr_out             (dep_pkt_out),        .pkt_hdr_len    (dep_pkt_len),
    .valid_out               (dep_valid_out)
  );

  // ============================================================================
  // Test infrastructure
  // ============================================================================
  int pass_cnt = 0, fail_cnt = 0;

  task automatic chk(input string name, input logic cond);
    if (cond) begin $display("    [PASS] %s", name); pass_cnt++; end
    else      begin $display("    [FAIL] %s", name); fail_cnt++; end
  endtask

  task do_reset;
    rst_n = 0; p_valid_in = 0;
    repeat (3) @(posedge clk); @(negedge clk);
    rst_n = 1; @(posedge clk); #1;
  endtask

  // ============================================================================
  // MAIN
  // ============================================================================
  initial begin
    $dumpfile("tb_load_balance.vcd");
    $dumpvars(0, tb_load_balance);

    // ──────────────────────────────────────────────────────────────────────────
    // SECTION 1 — PARSER FSM
    // ──────────────────────────────────────────────────────────────────────────
    $display("\n══ Section 1: Parser FSM ══════════════════════════════════════");

    // ── P1: IPv4/TCP full parse ───────────────────────────────────────────────
    $display("  P1: IPv4/TCP full parse (0x0800 → ETH→IPV4→TCP)");
    do_reset();
    p_eth_type = 16'h0800; p_ipv4_proto = 8'd6; p_valid_in = 1; #1;
    chk("P1 START: no extract_eth",        !p_ext_eth);
    @(posedge clk); #1;               // → PARSE_ETHERNET
    chk("P1 PARSE_ETH: extract_eth",       p_ext_eth);
    @(posedge clk); #1;               // → PARSE_IPV4
    chk("P1 PARSE_IPV4: extract_ipv4",     p_ext_ipv4);
    chk("P1 PARSE_IPV4: no extract_tcp",   !p_ext_tcp);
    @(posedge clk); #1;               // → PARSE_TCP
    chk("P1 PARSE_TCP: extract_tcp",       p_ext_tcp);
    @(posedge clk); #1;               // → ACCEPT
    chk("P1 ACCEPT: done",                 p_done);
    p_valid_in = 0;

    // ── P2: IPv4 non-TCP (e.g. UDP proto=17) → no extract_tcp ───────────────
    $display("  P2: IPv4/UDP (proto=17) → no TCP extraction");
    do_reset();
    p_eth_type = 16'h0800; p_ipv4_proto = 8'd17; p_valid_in = 1;
    @(posedge clk); #1;               // PARSE_ETH
    @(posedge clk); #1;               // PARSE_IPV4
    @(posedge clk); #1;               // ACCEPT (default)
    chk("P2 ACCEPT: done",                 p_done);
    chk("P2 ACCEPT: no extract_tcp",       !p_ext_tcp);
    p_valid_in = 0;

    // ── P3: ARP → early accept ───────────────────────────────────────────────
    $display("  P3: ARP (0x0806) → early accept");
    do_reset();
    p_eth_type = 16'h0806; p_valid_in = 1;
    @(posedge clk); #1;               // PARSE_ETH
    @(posedge clk); #1;               // ACCEPT
    chk("P3 ACCEPT: done",                 p_done);
    chk("P3: no extract_ipv4",             !p_ext_ipv4);
    p_valid_in = 0;

    // ── P4: IPv6 (0x86DD) → early accept ────────────────────────────────────
    $display("  P4: IPv6 (0x86DD) → early accept after PARSE_ETH");
    do_reset();
    p_eth_type = 16'h86DD; p_valid_in = 1;
    @(posedge clk); #1;               // PARSE_ETH
    @(posedge clk); #1;               // ACCEPT
    chk("P4 ACCEPT: done",                 p_done);
    chk("P4: no extract_ipv4",             !p_ext_ipv4);
    p_valid_in = 0;

    // ──────────────────────────────────────────────────────────────────────────
    // SECTION 2 — PROCESSING (TABLE STUBS)
    // ──────────────────────────────────────────────────────────────────────────
    $display("\n══ Section 2: Processing (Table Stubs) ═══════════════════════");

    // Stable defaults
    pr_eth_valid = 1; pr_ipv4_valid = 1; pr_tcp_valid = 0;
    pr_eth_dst  = 48'hAABBCCDDEEFF; pr_eth_src  = 48'h112233445566;
    pr_eth_type = 16'h0800;
    pr_ipv4_ver = 4'h4; pr_ipv4_ihl = 4'h5; pr_ipv4_ds = 8'h00;
    pr_ipv4_len = 16'd40; pr_ipv4_id = 16'd1; pr_ipv4_flg = 3'b010;
    pr_ipv4_off = 13'd0; pr_ipv4_ttl = 8'd64; pr_ipv4_proto = 8'd6;
    pr_ipv4_chk = 16'hBEEF;
    pr_ipv4_src = 32'hC0A80001; pr_ipv4_dst = 32'h08080808;
    pr_meta_ecmp = 14'd0;

    // ── PR1: hit=0 stub, all fields pass-through ─────────────────────────────
    $display("  PR1: table stub hit=0 → all fields pass-through");
    #1;
    chk("PR1: hit_out = 0",                !pr_hit_out);
    chk("PR1: eth_dst pass-through",       pr_o_eth_dst == 48'hAABBCCDDEEFF);
    chk("PR1: ipv4_src pass-through",      pr_o_ipv4_src == 32'hC0A80001);
    chk("PR1: ipv4_dst pass-through",      pr_o_ipv4_dst == 32'h08080808);
    chk("PR1: not dropped",                !pr_drop);

    // ── PR2: ipv4_valid=1, ttl=64 > 0 → outer if passes, stub active ─────────
    $display("  PR2: ipv4_valid=1, ttl=64 → outer guard passes, stub hit=0");
    pr_ipv4_ttl = 8'd64; pr_ipv4_valid = 1; #1;
    chk("PR2: hit=0 (ecmp stub)",          !pr_hit_out);
    chk("PR2: eth_dst unchanged",          pr_o_eth_dst == 48'hAABBCCDDEEFF);

    // ── PR3: ttl=0 → outer if (ttl>0) fails → nothing changes ────────────────
    $display("  PR3: ttl=0 → condition ipv4_ttl>0 fails → full pass-through");
    pr_ipv4_ttl = 8'd0; #1;
    chk("PR3: hit=0 (condition failed)",   !pr_hit_out);
    chk("PR3: eth_dst unchanged",          pr_o_eth_dst == 48'hAABBCCDDEEFF);
    pr_ipv4_ttl = 8'd64;

    // ── PR4: ipv4_valid=0 → outer if fails entirely ───────────────────────────
    $display("  PR4: ipv4_valid=0 → apply block skipped");
    pr_ipv4_valid = 0; #1;
    chk("PR4: hit=0",                      !pr_hit_out);
    chk("PR4: eth_dst unchanged",          pr_o_eth_dst == 48'hAABBCCDDEEFF);
    pr_ipv4_valid = 1;

    // ── PR5: valid_out pipeline register ──────────────────────────────────────
    $display("  PR5: valid_out is one-cycle registered");
    do_reset();
    pr_valid_in = 1; #1;
    chk("PR5: valid_out=0 before posedge", !pr_valid_out);
    @(posedge clk); #1;
    chk("PR5: valid_out=1 after posedge",  pr_valid_out);
    pr_valid_in = 0;
    @(posedge clk); #1;
    chk("PR5: valid_out=0 after deassert", !pr_valid_out);

    // ──────────────────────────────────────────────────────────────────────────
    // SECTION 3 — DEPARSER PACKING  (432-bit bus)
    // ──────────────────────────────────────────────────────────────────────────
    $display("\n══ Section 3: Deparser Packing ════════════════════════════════");

    dep_eth_dst   = 48'hAABBCCDDEEFF; dep_eth_src   = 48'h112233445566;
    dep_eth_type  = 16'h0800;
    dep_ipv4_ver  = 4'h4; dep_ipv4_ihl = 4'h5; dep_ipv4_ds = 8'h00;
    dep_ipv4_len  = 16'd40; dep_ipv4_id = 16'd1; dep_ipv4_flg = 3'b010;
    dep_ipv4_off  = 13'd0; dep_ipv4_ttl = 8'd64; dep_ipv4_proto = 8'd6;
    dep_ipv4_chk  = 16'hBEEF;
    dep_ipv4_src  = 32'hC0A80001; dep_ipv4_dst = 32'h08080808;
    dep_tcp_sp    = 16'hAAAA; dep_tcp_dp = 16'hBBBB;
    dep_tcp_seq   = 32'h12345678; dep_tcp_ack = 32'h9ABCDEF0;
    dep_tcp_doff  = 4'h5; dep_tcp_res = 3'd0; dep_tcp_ecn = 3'd0;
    dep_tcp_ctrl  = 6'h02; dep_tcp_win = 16'hFFFF;
    dep_tcp_csum  = 16'hCAFE; dep_tcp_urg = 16'd0;

    // ── D1: All three headers valid → pkt_hdr_len=432 ────────────────────────
    $display("  D1: eth+ipv4+tcp valid → pkt_hdr_len=432");
    dep_eth_valid = 1; dep_ipv4_valid = 1; dep_tcp_valid = 1; #1;
    chk("D1: pkt_hdr_len = 432",           dep_pkt_len == 16'd432);
    chk("D1: eth dst at [431:384]",        dep_pkt_out[DST_HI:DST_LO] == 48'hAABBCCDDEEFF);
    chk("D1: eth src at [383:336]",        dep_pkt_out[SRC_HI:SRC_LO] == 48'h112233445566);
    chk("D1: eth type at [335:320]",       dep_pkt_out[TYPE_HI:TYPE_LO] == 16'h0800);
    chk("D1: ipv4 ttl at [255:248]",       dep_pkt_out[TTL_HI:TTL_LO] == 8'd64);
    chk("D1: ipv4 src at [223:192]",       dep_pkt_out[ISRC_HI:ISRC_LO] == 32'hC0A80001);
    chk("D1: ipv4 dst at [191:160]",       dep_pkt_out[IDST_HI:IDST_LO] == 32'h08080808);
    chk("D1: tcp sp at [159:144]",         dep_pkt_out[TCP_SP_HI:TCP_SP_LO] == 16'hAAAA);
    chk("D1: tcp dp at [143:128]",         dep_pkt_out[TCP_DP_HI:TCP_DP_LO] == 16'hBBBB);

    // ── D2: Only ethernet valid → pkt_hdr_len=112 ────────────────────────────
    $display("  D2: eth only → pkt_hdr_len=112");
    dep_eth_valid = 1; dep_ipv4_valid = 0; dep_tcp_valid = 0; #1;
    chk("D2: pkt_hdr_len = 112",           dep_pkt_len == 16'd112);
    chk("D2: eth dst present",             dep_pkt_out[DST_HI:DST_LO] == 48'hAABBCCDDEEFF);
    chk("D2: ipv4 slot zeroed",            dep_pkt_out[IPV4_HI:IPV4_LO] == 160'h0);
    chk("D2: tcp slot zeroed",             dep_pkt_out[TCP_HI:TCP_LO] == 160'h0);

    // ── D3: eth+ipv4 only (no TCP) → pkt_hdr_len=272 ─────────────────────────
    $display("  D3: eth+ipv4 only → pkt_hdr_len=272");
    dep_eth_valid = 1; dep_ipv4_valid = 1; dep_tcp_valid = 0; #1;
    chk("D3: pkt_hdr_len = 272",           dep_pkt_len == 16'd272);
    chk("D3: tcp slot zeroed",             dep_pkt_out[TCP_HI:TCP_LO] == 160'h0);

    // ── D4: No headers → zero ─────────────────────────────────────────────────
    $display("  D4: no headers valid → all zeros");
    dep_eth_valid = 0; dep_ipv4_valid = 0; dep_tcp_valid = 0; #1;
    chk("D4: pkt_hdr_len = 0",             dep_pkt_len == 16'd0);
    chk("D4: pkt_hdr_out all zeros",       dep_pkt_out == 432'h0);

    // ──────────────────────────────────────────────────────────────────────────
    // SECTION 4 — INTEGRATION
    // ──────────────────────────────────────────────────────────────────────────
    $display("\n══ Section 4: Integration Tests ═══════════════════════════════");

    // ── INT1: processing pass-through → deparser correct ─────────────────────
    $display("  INT1: processing outputs routed to deparser (stub hit=0)");
    pr_eth_valid = 1; pr_ipv4_valid = 1; pr_tcp_valid = 1;
    pr_eth_dst   = 48'hDEADBEEFCAFE; pr_eth_src = 48'hCAFEBEEFDEAD;
    pr_eth_type  = 16'h0800;
    pr_ipv4_ver  = 4'h4; pr_ipv4_ihl = 4'h5; pr_ipv4_ds = 8'd0;
    pr_ipv4_len  = 16'd60; pr_ipv4_id = 16'd7; pr_ipv4_flg = 3'd0;
    pr_ipv4_off  = 13'd0; pr_ipv4_ttl = 8'd128; pr_ipv4_proto = 8'd6;
    pr_ipv4_chk  = 16'h1234;
    pr_ipv4_src  = 32'h0A000001; pr_ipv4_dst = 32'h0A000002;
    pr_tcp_sp    = 16'h1234; pr_tcp_dp = 16'h5000;
    pr_tcp_seq   = 32'hDEAD; pr_tcp_ack = 32'hBEEF;
    pr_tcp_doff  = 4'h5; pr_tcp_res = 3'd0; pr_tcp_ecn = 3'd0;
    pr_tcp_ctrl  = 6'h02; pr_tcp_win = 16'h4000;
    pr_tcp_csum  = 16'hABCD; pr_tcp_urg = 16'd0;
    pr_meta_ecmp = 14'd0; #1;

    dep_eth_valid = 1; dep_ipv4_valid = 1; dep_tcp_valid = 1;
    dep_eth_dst   = pr_o_eth_dst; dep_eth_src  = pr_o_eth_src;
    dep_eth_type  = pr_o_eth_type;
    dep_ipv4_ver  = pr_o_ipv4_ver; dep_ipv4_ihl = pr_o_ipv4_ihl;
    dep_ipv4_ds   = pr_o_ipv4_ds; dep_ipv4_len  = pr_o_ipv4_len;
    dep_ipv4_id   = pr_o_ipv4_id; dep_ipv4_flg  = pr_o_ipv4_flg;
    dep_ipv4_off  = pr_o_ipv4_off; dep_ipv4_ttl = pr_o_ipv4_ttl;
    dep_ipv4_proto= pr_o_ipv4_proto; dep_ipv4_chk = pr_o_ipv4_chk;
    dep_ipv4_src  = pr_o_ipv4_src; dep_ipv4_dst  = pr_o_ipv4_dst;
    dep_tcp_sp    = pr_o_tcp_sp; dep_tcp_dp     = pr_o_tcp_dp;
    dep_tcp_seq   = pr_o_tcp_seq; dep_tcp_ack   = pr_o_tcp_ack;
    dep_tcp_doff  = pr_o_tcp_doff; dep_tcp_res   = pr_o_tcp_res;
    dep_tcp_ecn   = pr_o_tcp_ecn; dep_tcp_ctrl   = pr_o_tcp_ctrl;
    dep_tcp_win   = pr_o_tcp_win; dep_tcp_csum   = pr_o_tcp_csum;
    dep_tcp_urg   = pr_o_tcp_urg; #1;

    chk("INT1: dep eth dst at [431:384]",  dep_pkt_out[DST_HI:DST_LO] == 48'hDEADBEEFCAFE);
    chk("INT1: dep ipv4 src at [223:192]", dep_pkt_out[ISRC_HI:ISRC_LO] == 32'h0A000001);
    chk("INT1: dep tcp sp at [159:144]",   dep_pkt_out[TCP_SP_HI:TCP_SP_LO] == 16'h1234);
    chk("INT1: pkt_hdr_len = 432",         dep_pkt_len == 16'd432);

    // ── INT2: valid_out pipeline latency ──────────────────────────────────────
    $display("  INT2: deparser valid_out one-cycle registered");
    do_reset();
    dep_eth_valid = 1; dep_ipv4_valid = 0; dep_tcp_valid = 0;
    dep_valid_in = 1; #1;
    chk("INT2: valid_out=0 before posedge", !dep_valid_out);
    @(posedge clk); #1;
    chk("INT2: valid_out=1 after posedge",  dep_valid_out);
    dep_valid_in = 0;
    @(posedge clk); #1;
    chk("INT2: valid_out=0 after deassert", !dep_valid_out);

    // ──────────────────────────────────────────────────────────────────────────
    $display("\n════════════════════════════════════════════════════════════════");
    $display("  Results: %0d passed, %0d failed  (total %0d)",
             pass_cnt, fail_cnt, pass_cnt + fail_cnt);
    $display("════════════════════════════════════════════════════════════════");
    if (fail_cnt == 0)
      $display("  ALL TESTS PASSED");
    else
      $display("  FAILURES DETECTED — see [FAIL] lines above");
    $display("\n  NOTE: ecmp_group / ecmp_nhop tables are RTL-stubbed (hit=0).\n");
    $finish;
  end

  initial begin #300000; $display("[TIMEOUT]"); $finish; end

endmodule
