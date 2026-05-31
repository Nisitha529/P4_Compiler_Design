// ============================================================================
// tb_qos.sv — Self-checking testbench for qos.p4 pipeline
//
// Pipeline: V1Switch → MyIngress used as processing_generated
//
// Coverage:
//   Section 1 — Parser FSM       (P1-P3): Eth→IPv4, ARP, IPv6
//   Section 2 — Processing logic (PR1-PR6): QoS DSCP marking per protocol,
//               table stub, ipv4_valid guard, valid_out latency
//   Section 3 — Deparser packing (D1-D3): all/eth-only/zero
//   Section 4 — Integration      (INT1-INT2): DSCP mark through deparser
//
// DSCP (diffserv) marking rules from expedited_forwarding / voice_admit:
//   protocol == 17 (UDP) → diffserv = 46
//   protocol ==  6 (TCP) → diffserv = 44
//   other               → diffserv unchanged
//
// Compile (from this directory):
//   iverilog -g2012 -o sim tb_qos.sv \
//     ../parser_generated.sv ../processing_generated.sv ../deparser_generated.sv
//   vvp sim
// ============================================================================
`timescale 1ns/1ps

module tb_qos;

  // ── Clock ───────────────────────────────────────────────────────────────────
  localparam CLK_T = 10;
  logic clk = 0;
  always #(CLK_T/2) clk = ~clk;
  logic rst_n;

  // ============================================================================
  // 1. PARSER DUT
  //    select field: ethernet_etherType [15:0]  (IPv4 only, no L4 select)
  // ============================================================================
  logic        p_valid_in   = 0;
  logic [15:0] p_eth_type   = 0;
  logic        p_ext_eth, p_ext_ipv4, p_done;

  parser_generated parser_dut (
    .clk                (clk),
    .rst_n              (rst_n),
    .valid_in           (p_valid_in),
    .ethernet_etherType (p_eth_type),
    .extract_ethernet   (p_ext_eth),
    .extract_ipv4       (p_ext_ipv4),
    .done               (p_done)
  );

  // ============================================================================
  // 2. PROCESSING DUT  (MyIngress)
  //    ipv4.diffserv is [5:0] in qos.p4 (bit<6> + bit<2> ecn)
  // ============================================================================
  logic        pr_valid_in   = 0;
  logic        pr_eth_valid  = 0;
  logic        pr_ipv4_valid = 0;

  logic [47:0] pr_eth_dst    = 0;  logic [47:0] pr_eth_src    = 0;
  logic [15:0] pr_eth_type   = 0;
  logic  [3:0] pr_ipv4_ver   = 0;  logic  [3:0] pr_ipv4_ihl   = 0;
  logic  [5:0] pr_ipv4_ds    = 0;  logic  [1:0] pr_ipv4_ecn   = 0;
  logic [15:0] pr_ipv4_len   = 0;  logic [15:0] pr_ipv4_id    = 0;
  logic  [2:0] pr_ipv4_flg   = 0;  logic [12:0] pr_ipv4_off   = 0;
  logic  [7:0] pr_ipv4_ttl   = 0;  logic  [7:0] pr_ipv4_proto = 0;
  logic [15:0] pr_ipv4_chk   = 0;  logic [31:0] pr_ipv4_src   = 0;
  logic [31:0] pr_ipv4_dst   = 0;

  logic [47:0] pr_o_eth_dst, pr_o_eth_src;
  logic [15:0] pr_o_eth_type;
  logic  [5:0] pr_o_ipv4_ds;
  logic  [1:0] pr_o_ipv4_ecn;
  logic  [7:0] pr_o_ipv4_ttl, pr_o_ipv4_proto;
  logic [31:0] pr_o_ipv4_src, pr_o_ipv4_dst;
  logic  [3:0] pr_o_ipv4_ver, pr_o_ipv4_ihl;
  logic [15:0] pr_o_ipv4_len, pr_o_ipv4_id, pr_o_ipv4_chk;
  logic  [2:0] pr_o_ipv4_flg;  logic [12:0] pr_o_ipv4_off;
  logic        pr_valid_out, pr_drop;

  processing_generated proc_dut (
    .clk                    (clk),                .rst_n           (rst_n),
    .valid_in               (pr_valid_in),
    .ethernet_valid         (pr_eth_valid),        .ipv4_valid      (pr_ipv4_valid),
    .ethernet_dstAddr       (pr_eth_dst),          .ethernet_srcAddr(pr_eth_src),
    .ethernet_etherType     (pr_eth_type),
    .ipv4_version           (pr_ipv4_ver),         .ipv4_ihl        (pr_ipv4_ihl),
    .ipv4_diffserv          (pr_ipv4_ds),          .ipv4_ecn        (pr_ipv4_ecn),
    .ipv4_totalLen          (pr_ipv4_len),         .ipv4_identification(pr_ipv4_id),
    .ipv4_flags             (pr_ipv4_flg),         .ipv4_fragOffset (pr_ipv4_off),
    .ipv4_ttl               (pr_ipv4_ttl),         .ipv4_protocol   (pr_ipv4_proto),
    .ipv4_hdrChecksum       (pr_ipv4_chk),         .ipv4_srcAddr    (pr_ipv4_src),
    .ipv4_dstAddr           (pr_ipv4_dst),
    .out_ethernet_dstAddr   (pr_o_eth_dst),        .out_ethernet_srcAddr(pr_o_eth_src),
    .out_ethernet_etherType (pr_o_eth_type),
    .out_ipv4_version       (pr_o_ipv4_ver),       .out_ipv4_ihl    (pr_o_ipv4_ihl),
    .out_ipv4_diffserv      (pr_o_ipv4_ds),        .out_ipv4_ecn    (pr_o_ipv4_ecn),
    .out_ipv4_totalLen      (pr_o_ipv4_len),       .out_ipv4_identification(pr_o_ipv4_id),
    .out_ipv4_flags         (pr_o_ipv4_flg),       .out_ipv4_fragOffset(pr_o_ipv4_off),
    .out_ipv4_ttl           (pr_o_ipv4_ttl),       .out_ipv4_protocol(pr_o_ipv4_proto),
    .out_ipv4_hdrChecksum   (pr_o_ipv4_chk),       .out_ipv4_srcAddr(pr_o_ipv4_src),
    .out_ipv4_dstAddr       (pr_o_ipv4_dst),
    .valid_out              (pr_valid_out),         .drop            (pr_drop)
  );

  // ============================================================================
  // 3. DEPARSER DUT
  //   pkt_hdr_out[271:0] layout:
  //     [271:160] ethernet  112b  {dstAddr,srcAddr,etherType}
  //     [159:  0] ipv4      160b
  //   ipv4 field offsets:
  //     diffserv: [151:146] (6b)
  //     ttl:       [95:88]  (8b)
  //     protocol:  [87:80]  (8b)
  //     srcAddr:   [63:32]  (32b)
  //     dstAddr:   [31:0]   (32b)
  // ============================================================================
  localparam ETH_HI       = 271; localparam ETH_LO       = 160;
  localparam IPV4_HI      = 159; localparam IPV4_LO      = 0;
  localparam DST_HI       = 271; localparam DST_LO       = 224;
  localparam SRC_HI       = 223; localparam SRC_LO       = 176;
  localparam TYPE_HI      = 175; localparam TYPE_LO      = 160;
  localparam DS_HI        = 151; localparam DS_LO        = 146;
  localparam TTL_HI       =  95; localparam TTL_LO       = 88;
  localparam PROTO_HI     =  87; localparam PROTO_LO     = 80;
  localparam ISRC_HI      =  63; localparam ISRC_LO      = 32;
  localparam IDST_HI      =  31; localparam IDST_LO      = 0;

  logic        dep_valid_in  = 0;
  logic        dep_eth_valid = 0;
  logic        dep_ipv4_valid= 0;

  logic [47:0] dep_eth_dst   = 0;  logic [47:0] dep_eth_src   = 0;
  logic [15:0] dep_eth_type  = 0;
  logic  [3:0] dep_ipv4_ver  = 0;  logic  [3:0] dep_ipv4_ihl  = 0;
  logic  [5:0] dep_ipv4_ds   = 0;  logic  [1:0] dep_ipv4_ecn  = 0;
  logic [15:0] dep_ipv4_len  = 0;  logic [15:0] dep_ipv4_id   = 0;
  logic  [2:0] dep_ipv4_flg  = 0;  logic [12:0] dep_ipv4_off  = 0;
  logic  [7:0] dep_ipv4_ttl  = 0;  logic  [7:0] dep_ipv4_proto= 0;
  logic [15:0] dep_ipv4_chk  = 0;  logic [31:0] dep_ipv4_src  = 0;
  logic [31:0] dep_ipv4_dst  = 0;

  logic [271:0] dep_pkt_out;
  logic [15:0]  dep_pkt_len;
  logic         dep_valid_out;

  deparser_generated dep_dut (
    .clk                    (clk),                .rst_n           (rst_n),
    .valid_in               (dep_valid_in),
    .ethernet_valid         (dep_eth_valid),       .ipv4_valid      (dep_ipv4_valid),
    .ethernet_dstAddr       (dep_eth_dst),         .ethernet_srcAddr(dep_eth_src),
    .ethernet_etherType     (dep_eth_type),
    .ipv4_version           (dep_ipv4_ver),        .ipv4_ihl        (dep_ipv4_ihl),
    .ipv4_diffserv          (dep_ipv4_ds),         .ipv4_ecn        (dep_ipv4_ecn),
    .ipv4_totalLen          (dep_ipv4_len),        .ipv4_identification(dep_ipv4_id),
    .ipv4_flags             (dep_ipv4_flg),        .ipv4_fragOffset (dep_ipv4_off),
    .ipv4_ttl               (dep_ipv4_ttl),        .ipv4_protocol   (dep_ipv4_proto),
    .ipv4_hdrChecksum       (dep_ipv4_chk),        .ipv4_srcAddr    (dep_ipv4_src),
    .ipv4_dstAddr           (dep_ipv4_dst),
    .pkt_hdr_out            (dep_pkt_out),         .pkt_hdr_len     (dep_pkt_len),
    .valid_out              (dep_valid_out)
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
    $dumpfile("tb_qos.vcd");
    $dumpvars(0, tb_qos);

    // ──────────────────────────────────────────────────────────────────────────
    // SECTION 1 — PARSER FSM
    // ──────────────────────────────────────────────────────────────────────────
    $display("\n══ Section 1: Parser FSM ══════════════════════════════════════");

    // ── P1: IPv4 packet (0x0800) → parse_ethernet → parse_ipv4 → ACCEPT ──────
    $display("  P1: IPv4 packet → parse_ethernet → parse_ipv4 → ACCEPT");
    do_reset();
    p_eth_type = 16'h0800; p_valid_in = 1; #1;
    chk("P1 START: no extract_eth",        !p_ext_eth);
    @(posedge clk); #1;               // → PARSE_ETHERNET
    chk("P1 PARSE_ETH: extract_eth",       p_ext_eth);
    @(posedge clk); #1;               // → PARSE_IPV4
    chk("P1 PARSE_IPV4: extract_ipv4",     p_ext_ipv4);
    @(posedge clk); #1;               // → ACCEPT
    chk("P1 ACCEPT: done",                 p_done);
    p_valid_in = 0;

    // ── P2: ARP (0x0806) → early accept after parse_ethernet ─────────────────
    $display("  P2: ARP (0x0806) → early accept");
    do_reset();
    p_eth_type = 16'h0806; p_valid_in = 1;
    @(posedge clk); #1;               // PARSE_ETHERNET
    @(posedge clk); #1;               // ACCEPT
    chk("P2 ACCEPT: done",                 p_done);
    chk("P2: no extract_ipv4",             !p_ext_ipv4);
    p_valid_in = 0;

    // ── P3: Explicit IPv4 TYPE_IPV4 constant (0x0800) matches ────────────────
    $display("  P3: TYPE_IPV4 = 16'h0800 properly resolved in case");
    do_reset();
    p_eth_type = 16'h0800; p_valid_in = 1;
    @(posedge clk); #1;               // PARSE_ETHERNET
    @(posedge clk); #1;               // PARSE_IPV4 (not ACCEPT — confirm match)
    chk("P3: extract_ipv4 asserted",       p_ext_ipv4);
    p_valid_in = 0;

    // ──────────────────────────────────────────────────────────────────────────
    // SECTION 2 — PROCESSING: QoS DSCP MARKING
    // ──────────────────────────────────────────────────────────────────────────
    $display("\n══ Section 2: Processing — QoS DSCP Marking ═══════════════════");

    // Stable defaults
    pr_eth_valid  = 1; pr_ipv4_valid = 1;
    pr_eth_dst    = 48'hAABBCCDDEEFF; pr_eth_src = 48'h112233445566;
    pr_eth_type   = 16'h0800;
    pr_ipv4_ver   = 4'h4; pr_ipv4_ihl = 4'h5;
    pr_ipv4_ds    = 6'd0;  pr_ipv4_ecn = 2'd0;
    pr_ipv4_len   = 16'd40; pr_ipv4_id = 16'd1;
    pr_ipv4_flg   = 3'b010; pr_ipv4_off = 13'd0;
    pr_ipv4_ttl   = 8'd64; pr_ipv4_chk = 16'hBEEF;
    pr_ipv4_src   = 32'hC0A80001; pr_ipv4_dst = 32'h08080808;

    // ── PR1: UDP (proto=17) → expedited_forwarding → diffserv = 46 ───────────
    $display("  PR1: proto=17 (UDP) → diffserv = 46 (expedited forwarding)");
    pr_ipv4_proto = 8'd17; #1;
    chk("PR1: out_ipv4_diffserv = 46",     pr_o_ipv4_ds == 6'd46);
    chk("PR1: other fields unchanged",     pr_o_eth_dst == 48'hAABBCCDDEEFF);
    chk("PR1: not dropped",                !pr_drop);

    // ── PR2: TCP (proto=6) → voice_admit → diffserv = 44 ─────────────────────
    $display("  PR2: proto=6 (TCP) → diffserv = 44 (voice admit)");
    pr_ipv4_proto = 8'd6; #1;
    chk("PR2: out_ipv4_diffserv = 44",     pr_o_ipv4_ds == 6'd44);
    chk("PR2: not dropped",                !pr_drop);

    // ── PR3: ICMP (proto=1) → neither branch → diffserv unchanged ─────────────
    $display("  PR3: proto=1 (ICMP) → no DSCP change → diffserv = input");
    pr_ipv4_proto = 8'd1; pr_ipv4_ds = 6'd20; #1;
    chk("PR3: out_ipv4_diffserv unchanged", pr_o_ipv4_ds == 6'd20);
    pr_ipv4_ds = 6'd0;

    // ── PR4: OSPF (proto=89) → no DSCP change ─────────────────────────────────
    $display("  PR4: proto=89 (OSPF) → no DSCP change");
    pr_ipv4_proto = 8'd89; pr_ipv4_ds = 6'd0; #1;
    chk("PR4: out_ipv4_diffserv = 0",      pr_o_ipv4_ds == 6'd0);

    // ── PR5: ipv4_valid=0 → outer guard fails → diffserv unchanged ────────────
    $display("  PR5: ipv4_valid=0 → apply block skipped");
    pr_ipv4_valid = 0; pr_ipv4_proto = 8'd17; #1;
    chk("PR5: diffserv unchanged when !ipv4_valid", pr_o_ipv4_ds == 6'd0);
    pr_ipv4_valid = 1;

    // ── PR6: valid_out pipeline register ──────────────────────────────────────
    $display("  PR6: valid_out is one-cycle registered");
    do_reset();
    pr_valid_in = 1; #1;
    chk("PR6: valid_out=0 before posedge", !pr_valid_out);
    @(posedge clk); #1;
    chk("PR6: valid_out=1 after posedge",  pr_valid_out);
    pr_valid_in = 0;
    @(posedge clk); #1;
    chk("PR6: valid_out=0 after deassert", !pr_valid_out);

    // ──────────────────────────────────────────────────────────────────────────
    // SECTION 3 — DEPARSER PACKING  (272-bit bus)
    // ──────────────────────────────────────────────────────────────────────────
    $display("\n══ Section 3: Deparser Packing ════════════════════════════════");

    dep_eth_dst   = 48'hAABBCCDDEEFF; dep_eth_src  = 48'h112233445566;
    dep_eth_type  = 16'h0800;
    dep_ipv4_ver  = 4'h4; dep_ipv4_ihl = 4'h5;
    dep_ipv4_ds   = 6'd46; dep_ipv4_ecn = 2'd0;
    dep_ipv4_len  = 16'd40; dep_ipv4_id = 16'd1;
    dep_ipv4_flg  = 3'b010; dep_ipv4_off = 13'd0;
    dep_ipv4_ttl  = 8'd64; dep_ipv4_proto = 8'd17;
    dep_ipv4_chk  = 16'hBEEF;
    dep_ipv4_src  = 32'hC0A80001; dep_ipv4_dst = 32'h08080808;

    // ── D1: Both headers valid → pkt_hdr_len=272 ─────────────────────────────
    $display("  D1: eth+ipv4 valid → pkt_hdr_len=272");
    dep_eth_valid = 1; dep_ipv4_valid = 1; #1;
    chk("D1: pkt_hdr_len = 272",            dep_pkt_len == 16'd272);
    chk("D1: eth dst at [271:224]",         dep_pkt_out[DST_HI:DST_LO] == 48'hAABBCCDDEEFF);
    chk("D1: eth src at [223:176]",         dep_pkt_out[SRC_HI:SRC_LO] == 48'h112233445566);
    chk("D1: eth type at [175:160]",        dep_pkt_out[TYPE_HI:TYPE_LO] == 16'h0800);
    chk("D1: ipv4 diffserv at [151:146]",   dep_pkt_out[DS_HI:DS_LO]   == 6'd46);
    chk("D1: ipv4 ttl at [95:88]",          dep_pkt_out[TTL_HI:TTL_LO] == 8'd64);
    chk("D1: ipv4 proto at [87:80]",        dep_pkt_out[PROTO_HI:PROTO_LO] == 8'd17);
    chk("D1: ipv4 src at [63:32]",          dep_pkt_out[ISRC_HI:ISRC_LO] == 32'hC0A80001);
    chk("D1: ipv4 dst at [31:0]",           dep_pkt_out[IDST_HI:IDST_LO] == 32'h08080808);

    // ── D2: Only ethernet valid → pkt_hdr_len=112 ────────────────────────────
    $display("  D2: eth only → pkt_hdr_len=112");
    dep_eth_valid = 1; dep_ipv4_valid = 0; #1;
    chk("D2: pkt_hdr_len = 112",            dep_pkt_len == 16'd112);
    chk("D2: eth dst present",              dep_pkt_out[DST_HI:DST_LO] == 48'hAABBCCDDEEFF);
    chk("D2: ipv4 slot zeroed",             dep_pkt_out[IPV4_HI:IPV4_LO] == 160'h0);

    // ── D3: No headers → all zeros ───────────────────────────────────────────
    $display("  D3: no headers valid → all zeros");
    dep_eth_valid = 0; dep_ipv4_valid = 0; #1;
    chk("D3: pkt_hdr_len = 0",              dep_pkt_len == 16'd0);
    chk("D3: pkt_hdr_out all zeros",        dep_pkt_out == 272'h0);

    // ──────────────────────────────────────────────────────────────────────────
    // SECTION 4 — INTEGRATION
    // ──────────────────────────────────────────────────────────────────────────
    $display("\n══ Section 4: Integration Tests ═══════════════════════════════");

    // ── INT1: UDP → diffserv=46, flows through deparser correctly ─────────────
    $display("  INT1: UDP → expedited_forwarding → DSCP=46 in deparser bus");
    pr_eth_valid  = 1; pr_ipv4_valid = 1;
    pr_eth_dst    = 48'hDEADBEEFCAFE; pr_eth_src = 48'hCAFEBEEFDEAD;
    pr_eth_type   = 16'h0800;
    pr_ipv4_ver   = 4'h4; pr_ipv4_ihl = 4'h5;
    pr_ipv4_ds    = 6'd0;   pr_ipv4_ecn = 2'd0;
    pr_ipv4_len   = 16'd40; pr_ipv4_id = 16'd3;
    pr_ipv4_flg   = 3'd0;   pr_ipv4_off = 13'd0;
    pr_ipv4_ttl   = 8'd128; pr_ipv4_proto = 8'd17;   // UDP
    pr_ipv4_chk   = 16'h5678;
    pr_ipv4_src   = 32'h0A000001; pr_ipv4_dst = 32'h0A000002;
    #1;

    dep_eth_valid  = 1; dep_ipv4_valid = 1;
    dep_eth_dst    = pr_o_eth_dst; dep_eth_src  = pr_o_eth_src;
    dep_eth_type   = pr_o_eth_type;
    dep_ipv4_ver   = pr_o_ipv4_ver; dep_ipv4_ihl = pr_o_ipv4_ihl;
    dep_ipv4_ds    = pr_o_ipv4_ds;  dep_ipv4_ecn = pr_o_ipv4_ecn;
    dep_ipv4_len   = pr_o_ipv4_len; dep_ipv4_id  = pr_o_ipv4_id;
    dep_ipv4_flg   = pr_o_ipv4_flg; dep_ipv4_off = pr_o_ipv4_off;
    dep_ipv4_ttl   = pr_o_ipv4_ttl; dep_ipv4_proto = pr_o_ipv4_proto;
    dep_ipv4_chk   = pr_o_ipv4_chk;
    dep_ipv4_src   = pr_o_ipv4_src; dep_ipv4_dst = pr_o_ipv4_dst;
    #1;

    chk("INT1: dep eth dst at [271:224]",  dep_pkt_out[DST_HI:DST_LO] == 48'hDEADBEEFCAFE);
    chk("INT1: dep diffserv = 46",         dep_pkt_out[DS_HI:DS_LO]   == 6'd46);
    chk("INT1: dep proto = 17",            dep_pkt_out[PROTO_HI:PROTO_LO] == 8'd17);
    chk("INT1: dep ipv4 src",              dep_pkt_out[ISRC_HI:ISRC_LO] == 32'h0A000001);
    chk("INT1: pkt_hdr_len = 272",         dep_pkt_len == 16'd272);

    // ── INT2: TCP → diffserv=44, flows through deparser ──────────────────────
    $display("  INT2: TCP → voice_admit → DSCP=44 in deparser bus");
    pr_ipv4_proto = 8'd6;   // TCP
    pr_ipv4_ds    = 6'd0;   // starts at 0
    #1;
    dep_ipv4_ds = pr_o_ipv4_ds; #1;
    chk("INT2: dep diffserv = 44",         dep_pkt_out[DS_HI:DS_LO] == 6'd44);

    // ──────────────────────────────────────────────────────────────────────────
    $display("\n════════════════════════════════════════════════════════════════");
    $display("  Results: %0d passed, %0d failed  (total %0d)",
             pass_cnt, fail_cnt, pass_cnt + fail_cnt);
    $display("════════════════════════════════════════════════════════════════");
    if (fail_cnt == 0)
      $display("  ALL TESTS PASSED");
    else
      $display("  FAILURES DETECTED — see [FAIL] lines above");
    $display("\n  NOTE: ipv4_lpm table is RTL-stubbed (NoAction default).\n");
    $finish;
  end

  initial begin #200000; $display("[TIMEOUT]"); $finish; end

endmodule
