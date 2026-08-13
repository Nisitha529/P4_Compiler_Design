// ============================================================================
// tb_basic_tunnel.sv — Comprehensive self-checking testbench for basic_tunnel.p4
//
// Pipeline: V1Switch → MyIngress (processing_generated)
//
// P4 basic_tunnel semantics under test:
//   ipv4_lpm table (LPM on hdr.ipv4.dstAddr), applied only when
//     hdr.ipv4.isValid() && !hdr.myTunnel.isValid() -- non-tunneled IPv4
//     only. default_action = drop().
//   myTunnel_exact table (exact match on hdr.myTunnel.dst_id), applied
//     only when hdr.myTunnel.isValid() -- tunneled packets, regardless of
//     whether the decapsulated ipv4 header also happens to be valid.
//     default_action = drop().
//   This sibling-if (not if/else) apply-block shape is exactly the
//   pattern that exposed the DAG-reconvergence-duplication bug fixed
//   earlier in this project (ingest_bmv2.py's _reconstruct_flow) -- two
//   independent conditions gated on the same header's validity in
//   opposite senses. Section 3 below specifically re-verifies that fix:
//   a tunneled packet (myTunnel valid) must NOT also trigger ipv4_lpm's
//   action, even though its decapsulated ipv4 header is valid too.
//
// Three-header parser: Ethernet → (myTunnel → IPv4 | IPv4 | accept)
// n_bounds = 4 (two keyed tables, 2-cycle latency each) — valid_out is
// 5 cycles after valid_in (1 baseline + 4 boundary), same convention as
// tb_firewall.sv's INT5.
//
// Compile (from this directory):
//   iverilog -g2012 -o sim tb_basic_tunnel.sv \
//     ../parser_generated.sv ../processing_generated.sv \
//     ../deparser_generated.sv \
//     ../ipv4_lpm_table.sv ../myTunnel_exact_table.sv
//   vvp sim
// ============================================================================
`timescale 1ns/1ps

module tb_basic_tunnel;

  // ── Clock ──────────────────────────────────────────────────────────────
  localparam CLK_T = 10;
  logic clk = 0;
  always #(CLK_T/2) clk = ~clk;
  logic rst_n;

  // ==========================================================================
  // 1.  PARSER DUT
  // ==========================================================================
  logic        p_valid_in     = 0;
  logic [15:0] p_eth_type     = 0;
  logic [15:0] p_tun_proto    = 0;
  logic        p_ext_eth, p_ext_ipv4, p_ext_tun, p_done;

  parser_generated parser_dut (
    .clk               (clk),
    .rst_n             (rst_n),
    .valid_in          (p_valid_in),
    .ethernet_etherType(p_eth_type),
    .myTunnel_proto_id (p_tun_proto),
    .extract_ethernet  (p_ext_eth),
    .extract_ipv4      (p_ext_ipv4),
    .extract_myTunnel  (p_ext_tun),
    .done              (p_done)
  );

  // ==========================================================================
  // 2.  PROCESSING DUT  (MyIngress)
  // ==========================================================================
  logic        pr_valid_in    = 0;
  logic        pr_eth_valid   = 1;
  logic        pr_tun_valid   = 0;
  logic        pr_ipv4_valid  = 1;

  logic [47:0] pr_eth_dst     = 48'hAABBCCDDEEFF;
  logic [47:0] pr_eth_src     = 48'h112233445566;
  logic [15:0] pr_eth_type    = 16'h0800;
  logic [15:0] pr_tun_proto   = 16'h0800;
  logic [15:0] pr_tun_dstid   = 0;
  logic  [3:0] pr_ipv4_ver    = 4;
  logic  [3:0] pr_ipv4_ihl    = 5;
  logic  [7:0] pr_ipv4_ds     = 0;
  logic [15:0] pr_ipv4_len    = 20;
  logic [15:0] pr_ipv4_id     = 1;
  logic  [2:0] pr_ipv4_flg    = 3'b010;
  logic [12:0] pr_ipv4_off    = 0;
  logic  [7:0] pr_ipv4_ttl    = 64;
  logic  [7:0] pr_ipv4_proto  = 8'd6;
  logic [15:0] pr_ipv4_chk    = 16'hBEEF;
  logic [31:0] pr_ipv4_src    = 32'hC0A80001;
  logic [31:0] pr_ipv4_dst    = 32'h0A000001;

  logic [47:0] pr_o_eth_dst, pr_o_eth_src;
  logic [15:0] pr_o_eth_type;
  logic [15:0] pr_o_tun_proto, pr_o_tun_dstid;
  logic  [7:0] pr_o_ipv4_ttl;
  logic [31:0] pr_o_ipv4_dst;
  logic  [8:0] pr_o_egress_spec;
  logic        pr_valid_out, pr_drop;
  logic        pr_lpm_hit_out, pr_tun_hit_out;

  // CP write signals — ipv4_lpm
  logic        lpm_cp_en   = 0;
  logic  [9:0] lpm_cp_idx  = 0;
  logic [31:0] lpm_cp_key  = 0;
  logic  [5:0] lpm_cp_pfx  = 0;
  logic  [1:0] lpm_cp_act  = 0;
  logic [47:0] lpm_cp_dstM = 0;
  logic  [8:0] lpm_cp_port = 0;

  // CP write signals — myTunnel_exact
  logic        tun_cp_en   = 0;
  logic  [9:0] tun_cp_idx  = 0;
  logic [15:0] tun_cp_key  = 0;
  logic  [1:0] tun_cp_act  = 0;
  logic  [8:0] tun_cp_port = 0;

  processing_generated proc_dut (
    .clk                          (clk),
    .rst_n                        (rst_n),
    .valid_in                     (pr_valid_in),
    .ethernet_valid                (pr_eth_valid),
    .myTunnel_valid                (pr_tun_valid),
    .ipv4_valid                    (pr_ipv4_valid),
    .ethernet_dstAddr              (pr_eth_dst),
    .ethernet_srcAddr              (pr_eth_src),
    .ethernet_etherType            (pr_eth_type),
    .myTunnel_proto_id             (pr_tun_proto),
    .myTunnel_dst_id               (pr_tun_dstid),
    .ipv4_version                  (pr_ipv4_ver),
    .ipv4_ihl                      (pr_ipv4_ihl),
    .ipv4_diffserv                 (pr_ipv4_ds),
    .ipv4_totalLen                 (pr_ipv4_len),
    .ipv4_identification           (pr_ipv4_id),
    .ipv4_flags                    (pr_ipv4_flg),
    .ipv4_fragOffset               (pr_ipv4_off),
    .ipv4_ttl                      (pr_ipv4_ttl),
    .ipv4_protocol                 (pr_ipv4_proto),
    .ipv4_hdrChecksum              (pr_ipv4_chk),
    .ipv4_srcAddr                  (pr_ipv4_src),
    .ipv4_dstAddr                  (pr_ipv4_dst),
    .out_ethernet_valid            (),
    .out_myTunnel_valid            (),
    .out_ipv4_valid                (),
    .out_ethernet_dstAddr          (pr_o_eth_dst),
    .out_ethernet_srcAddr          (pr_o_eth_src),
    .out_ethernet_etherType        (pr_o_eth_type),
    .out_myTunnel_proto_id         (pr_o_tun_proto),
    .out_myTunnel_dst_id           (pr_o_tun_dstid),
    .out_ipv4_version              (),
    .out_ipv4_ihl                  (),
    .out_ipv4_diffserv             (),
    .out_ipv4_totalLen             (),
    .out_ipv4_identification       (),
    .out_ipv4_flags                (),
    .out_ipv4_fragOffset           (),
    .out_ipv4_ttl                  (pr_o_ipv4_ttl),
    .out_ipv4_protocol             (),
    .out_ipv4_hdrChecksum          (),
    .out_ipv4_srcAddr              (),
    .out_ipv4_dstAddr              (pr_o_ipv4_dst),
    .out_std_meta_egress_spec      (pr_o_egress_spec),
    .ipv4_lpm_cp_wr_en             (lpm_cp_en),
    .ipv4_lpm_cp_wr_idx            (lpm_cp_idx),
    .ipv4_lpm_cp_wr_key_dstAddr    (lpm_cp_key),
    .ipv4_lpm_cp_wr_pfx_len        (lpm_cp_pfx),
    .ipv4_lpm_cp_wr_action         (lpm_cp_act),
    .ipv4_lpm_cp_wr_p_dstAddr      (lpm_cp_dstM),
    .ipv4_lpm_cp_wr_p_port         (lpm_cp_port),
    .myTunnel_exact_cp_wr_en       (tun_cp_en),
    .myTunnel_exact_cp_wr_idx      (tun_cp_idx),
    .myTunnel_exact_cp_wr_key_dst_id(tun_cp_key),
    .myTunnel_exact_cp_wr_action   (tun_cp_act),
    .myTunnel_exact_cp_wr_p_port   (tun_cp_port),
    .ipv4_lpm_hit_out              (pr_lpm_hit_out),
    .myTunnel_exact_hit_out        (pr_tun_hit_out),
    .valid_out                     (pr_valid_out),
    .drop                          (pr_drop)
  );

  // ==========================================================================
  // 3.  DEPARSER DUT
  //     Ethernet=112b  myTunnel=32b  IPv4=160b → total 304b
  //     Layout: [303:192]=Ethernet [191:160]=myTunnel [159:0]=IPv4
  // ==========================================================================
  localparam DEP_W = 304;

  logic        dep_valid_in    = 0;
  logic        dep_eth_valid   = 0;
  logic        dep_tun_valid   = 0;
  logic        dep_ipv4_valid  = 0;

  logic [47:0] dep_eth_dst = 0;  logic [47:0] dep_eth_src  = 0;
  logic [15:0] dep_eth_type = 0;
  logic [15:0] dep_tun_proto = 0; logic [15:0] dep_tun_dstid = 0;
  logic  [3:0] dep_ipv4_ver = 0; logic  [3:0] dep_ipv4_ihl = 0;
  logic  [7:0] dep_ipv4_ds  = 0;
  logic [15:0] dep_ipv4_len = 0; logic [15:0] dep_ipv4_id  = 0;
  logic  [2:0] dep_ipv4_flg = 0; logic [12:0] dep_ipv4_off = 0;
  logic  [7:0] dep_ipv4_ttl = 0; logic  [7:0] dep_ipv4_proto = 0;
  logic [15:0] dep_ipv4_chk = 0;
  logic [31:0] dep_ipv4_src = 0; logic [31:0] dep_ipv4_dst = 0;

  logic [DEP_W-1:0] dep_pkt_out;
  logic [15:0]      dep_pkt_len;
  logic              dep_valid_out;

  deparser_generated deparser_dut (
    .clk               (clk),
    .rst_n             (rst_n),
    .valid_in          (dep_valid_in),
    .ethernet_valid    (dep_eth_valid),
    .myTunnel_valid    (dep_tun_valid),
    .ipv4_valid        (dep_ipv4_valid),
    .ethernet_dstAddr  (dep_eth_dst),
    .ethernet_srcAddr  (dep_eth_src),
    .ethernet_etherType(dep_eth_type),
    .myTunnel_proto_id (dep_tun_proto),
    .myTunnel_dst_id   (dep_tun_dstid),
    .ipv4_version      (dep_ipv4_ver),
    .ipv4_ihl          (dep_ipv4_ihl),
    .ipv4_diffserv     (dep_ipv4_ds),
    .ipv4_totalLen     (dep_ipv4_len),
    .ipv4_identification(dep_ipv4_id),
    .ipv4_flags        (dep_ipv4_flg),
    .ipv4_fragOffset   (dep_ipv4_off),
    .ipv4_ttl          (dep_ipv4_ttl),
    .ipv4_protocol     (dep_ipv4_proto),
    .ipv4_hdrChecksum  (dep_ipv4_chk),
    .ipv4_srcAddr      (dep_ipv4_src),
    .ipv4_dstAddr      (dep_ipv4_dst),
    .pkt_hdr_out       (dep_pkt_out),
    .pkt_hdr_len       (dep_pkt_len),
    .valid_out         (dep_valid_out)
  );

  // ==========================================================================
  // Test infrastructure
  // ==========================================================================
  int pass_cnt = 0, fail_cnt = 0;

  task automatic chk(input string name, input logic cond);
    if (cond) begin $display("    [PASS] %s", name); pass_cnt++; end
    else      begin $display("    [FAIL] %s", name); fail_cnt++; end
  endtask

  task do_reset;
    rst_n = 0; p_valid_in = 0; pr_valid_in = 0;
    pr_eth_valid = 0; pr_tun_valid = 0; pr_ipv4_valid = 0;
    dep_eth_valid = 0; dep_tun_valid = 0; dep_ipv4_valid = 0;
    repeat(5) @(posedge clk); @(negedge clk);
    rst_n = 1; @(posedge clk); #1;
  endtask

  task lpm_write(input [9:0] idx, input [31:0] key, input [5:0] pfx,
                 input [1:0] act,  input [47:0] dstM, input [8:0] portn);
    @(negedge clk);
    lpm_cp_idx=idx; lpm_cp_key=key; lpm_cp_pfx=pfx;
    lpm_cp_act=act; lpm_cp_dstM=dstM; lpm_cp_port=portn;
    lpm_cp_en=1;
    @(posedge clk); #1;
    lpm_cp_en=0;
  endtask

  task tun_write(input [9:0] idx, input [15:0] key, input [1:0] act, input [8:0] portn);
    @(negedge clk);
    tun_cp_idx=idx; tun_cp_key=key; tun_cp_act=act; tun_cp_port=portn;
    tun_cp_en=1;
    @(posedge clk); #1;
    tun_cp_en=0;
  endtask

  // n_bounds=4 -> valid_out is 5 cycles after valid_in (1 baseline + 4 boundary)
  task send_packet;
    pr_valid_in=1; @(posedge clk); #1; pr_valid_in=0;
    @(posedge clk); #1;
    @(posedge clk); #1;
    @(posedge clk); #1;
    @(posedge clk); #1;
  endtask

  // ==========================================================================
  // MAIN TEST
  // ==========================================================================
  initial begin
    $display("== tb_basic_tunnel: basic_tunnel.p4 self-checking regression ==\n");

    // ──────────────────────────────────────────────────────────────────────
    // SECTION 1 — PARSER
    // ──────────────────────────────────────────────────────────────────────
    $display("══ Section 1: Parser FSM ══════════════════════════════════════");

    // P1: direct IPv4 (0x0800) -> eth -> ipv4 -> accept (3 edges)
    $display("  P1: 0x0800 -> eth->ipv4->accept (no tunnel)");
    do_reset();
    p_eth_type=16'h0800; p_valid_in=1;
    @(posedge clk); #1;
    chk("P1 ETH: ext_eth",   p_ext_eth);
    @(posedge clk); #1;
    chk("P1 IPV4: ext_ipv4", p_ext_ipv4);
    @(posedge clk); #1;
    chk("P1 ACCEPT: done",   p_done);
    chk("P1 !tunnel",        !p_ext_tun);
    p_valid_in=0;

    // P2: tunneled IPv4 (0x1212, proto_id=0x0800) -> eth->tun->ipv4->accept (4 edges)
    $display("  P2: 0x1212/proto=0x0800 -> eth->tun->ipv4->accept");
    do_reset();
    p_eth_type=16'h1212; p_tun_proto=16'h0800; p_valid_in=1;
    @(posedge clk); #1;
    chk("P2 ETH: ext_eth", p_ext_eth);
    @(posedge clk); #1;
    chk("P2 TUN: ext_tun", p_ext_tun);
    @(posedge clk); #1;
    chk("P2 IPV4: ext_ipv4", p_ext_ipv4);
    @(posedge clk); #1;
    chk("P2 ACCEPT: done", p_done);
    p_valid_in=0;

    // P3: tunnel header with unknown proto_id -> eth->tun->accept (3 edges, no ipv4)
    $display("  P3: 0x1212/proto=0x9999 -> eth->tun->accept (no ipv4)");
    do_reset();
    p_eth_type=16'h1212; p_tun_proto=16'h9999; p_valid_in=1;
    @(posedge clk); #1; @(posedge clk); #1;
    chk("P3 TUN: ext_tun", p_ext_tun);
    @(posedge clk); #1;
    chk("P3 ACCEPT: done", p_done);
    chk("P3 !ipv4",        !p_ext_ipv4);
    p_valid_in=0;

    // P4: unknown etherType -> eth->accept (2 edges)
    $display("  P4: 0x0806 (ARP) -> eth->accept");
    do_reset();
    p_eth_type=16'h0806; p_valid_in=1;
    @(posedge clk); #1; @(posedge clk); #1;
    chk("P4 ACCEPT: done", p_done);
    chk("P4 !tunnel",      !p_ext_tun);
    chk("P4 !ipv4",        !p_ext_ipv4);
    p_valid_in=0;

    // ──────────────────────────────────────────────────────────────────────
    // SECTION 2 — non-tunneled IPv4 (ipv4_lpm only)
    // ──────────────────────────────────────────────────────────────────────
    $display("\n══ Section 2: Non-tunneled IPv4 (ipv4_lpm) ═════════════════════");
    do_reset();

    // 10.0.0.0/8 -> ipv4_forward, dstMAC=AABBCCDDEEFF, port=3
    lpm_write(0, 32'h0A000000, 6'd8, 2'd1, 48'hAABBCCDDEEFF, 9'd3);

    // L1: hit -> forwarded
    pr_eth_valid=1; pr_tun_valid=0; pr_ipv4_valid=1;
    pr_ipv4_dst = 32'h0A010203; // 10.1.2.3
    pr_ipv4_ttl = 64;
    send_packet();
    chk("L1: not dropped",      !pr_drop);
    chk("L1: dstAddr rewritten", pr_o_eth_dst === 48'hAABBCCDDEEFF);
    chk("L1: ttl decremented",   pr_o_ipv4_ttl === 8'd63);
    chk("L1: egress_spec=3",     pr_o_egress_spec === 9'd3);

    // L2: miss -> default_action=drop()
    pr_ipv4_dst = 32'h08080808; // 8.8.8.8, no matching entry
    send_packet();
    chk("L2: miss -> dropped", pr_drop);

    // ──────────────────────────────────────────────────────────────────────
    // SECTION 3 — tunneled packets (myTunnel_exact only) + DAG-reconvergence
    // regression: myTunnel valid AND ipv4 valid (as it always is post-decap)
    // must NOT also fire ipv4_lpm's action.
    // ──────────────────────────────────────────────────────────────────────
    $display("\n══ Section 3: Tunneled packets (myTunnel_exact) + reconvergence ══");
    do_reset();

    // dst_id=0x0042 -> myTunnel_forward, port=5
    tun_write(0, 16'h0042, 2'd1, 9'd5);

    // T1: tunnel hit, decapsulated ipv4 ALSO valid and ALSO matches the
    // ipv4_lpm entry from Section 2 (dst=10.1.2.3) -- if the reconvergence
    // bug were present, ipv4_lpm's action would ALSO fire here (ttl-1,
    // MAC rewrite, egress_spec=3 instead of 5).
    pr_eth_valid=1; pr_tun_valid=1; pr_ipv4_valid=1;
    pr_tun_dstid = 16'h0042;
    pr_ipv4_dst  = 32'h0A010203; // matches the ipv4_lpm /8 entry too
    pr_ipv4_ttl  = 64;
    pr_eth_dst   = 48'h999999999999; // sentinel: must NOT be overwritten by ipv4_forward
    send_packet();
    chk("T1: not dropped",             !pr_drop);
    chk("T1: egress_spec=5 (myTunnel, not ipv4_lpm's 3)", pr_o_egress_spec === 9'd5);
    chk("T1: ttl UNCHANGED (ipv4_lpm did not also fire)", pr_o_ipv4_ttl === 8'd64);
    chk("T1: eth dstAddr UNCHANGED (ipv4_lpm did not also fire)", pr_o_eth_dst === 48'h999999999999);

    // T2: tunnel miss -> default_action=drop()
    pr_tun_dstid = 16'h00FF; // no matching entry
    send_packet();
    chk("T2: tunnel miss -> dropped", pr_drop);

    // T3: tunneled packet whose decapsulated ipv4 is INVALID (e.g. tunnel
    // carrying a non-IPv4 payload) -- myTunnel_exact must still apply.
    pr_tun_valid=1; pr_ipv4_valid=0;
    pr_tun_dstid = 16'h0042;
    send_packet();
    chk("T3: myTunnel still applies with ipv4 invalid", !pr_drop);
    chk("T3: egress_spec=5", pr_o_egress_spec === 9'd5);

    // ──────────────────────────────────────────────────────────────────────
    // SECTION 4 — neither header valid: no table applies, no drop
    // ──────────────────────────────────────────────────────────────────────
    $display("\n══ Section 4: Neither ipv4 nor myTunnel valid ══════════════════");
    do_reset();
    pr_eth_valid=1; pr_tun_valid=0; pr_ipv4_valid=0;
    send_packet();
    chk("N1: no table applies -> not dropped", !pr_drop);
    chk("N1: egress_spec=0 (default)", pr_o_egress_spec === 9'd0);

    // ──────────────────────────────────────────────────────────────────────
    // SECTION 5 — valid_out latency (5-cycle: 1 baseline + 4 boundary)
    // ──────────────────────────────────────────────────────────────────────
    $display("\n══ Section 5: valid_out latency ═════════════════════════════════");
    do_reset();
    pr_eth_valid=1; pr_tun_valid=0; pr_ipv4_valid=1;
    pr_ipv4_dst = 32'h0A010203;
    pr_valid_in=1; @(posedge clk); #1; pr_valid_in=0;
    chk("V1: valid_out=0 after 1st edge", !pr_valid_out);
    @(posedge clk); #1;
    chk("V1: valid_out=0 after 2nd edge", !pr_valid_out);
    @(posedge clk); #1;
    chk("V1: valid_out=0 after 3rd edge", !pr_valid_out);
    @(posedge clk); #1;
    chk("V1: valid_out=0 after 4th edge", !pr_valid_out);
    @(posedge clk); #1;
    chk("V1: valid_out=1 after 5th edge", pr_valid_out);
    @(posedge clk); #1;
    chk("V1: valid_out=0 deasserted", !pr_valid_out);

    // ──────────────────────────────────────────────────────────────────────
    // SECTION 6 — DEPARSER
    // ──────────────────────────────────────────────────────────────────────
    $display("\n══ Section 6: Deparser ══════════════════════════════════════════");

    // D1: all three headers valid
    dep_eth_valid=1; dep_tun_valid=1; dep_ipv4_valid=1;
    dep_eth_dst = 48'hAAAAAAAAAAAA; dep_eth_src = 48'hBBBBBBBBBBBB; dep_eth_type = 16'h1212;
    dep_tun_proto = 16'h0800; dep_tun_dstid = 16'h0042;
    dep_ipv4_ver=4; dep_ipv4_ihl=5; dep_ipv4_ds=0; dep_ipv4_len=20; dep_ipv4_id=1;
    dep_ipv4_flg=0; dep_ipv4_off=0; dep_ipv4_ttl=64; dep_ipv4_proto=6; dep_ipv4_chk=16'hBEEF;
    dep_ipv4_src=32'hC0A80001; dep_ipv4_dst=32'h0A010203;
    #1;
    chk("D1: dep ethernet at [303:192]", dep_pkt_out[303:256] === dep_eth_dst);
    chk("D1: dep myTunnel at [191:160]", dep_pkt_out[191:176] === dep_tun_proto);
    chk("D1: dep ipv4 dstAddr at [31:0]", dep_pkt_out[31:0] === dep_ipv4_dst);
    chk("D1: pkt_hdr_len = 304 (112+32+160)", dep_pkt_len === 16'd304);

    // D2: myTunnel invalid -> its slice reads back 0, len drops by 32
    dep_tun_valid = 0;
    #1;
    chk("D2: myTunnel slice zeroed", dep_pkt_out[191:160] === 32'd0);
    chk("D2: pkt_hdr_len = 272 (112+160)", dep_pkt_len === 16'd272);

    // D3: only ethernet valid
    dep_ipv4_valid = 0;
    #1;
    chk("D3: pkt_hdr_len = 112 (ethernet only)", dep_pkt_len === 16'd112);
    chk("D3: ipv4 slice zeroed", dep_pkt_out[159:0] === 160'd0);

    // D4: valid_out one-cycle registered
    dep_eth_valid=1; dep_tun_valid=1; dep_ipv4_valid=1;
    dep_valid_in = 1; @(posedge clk); #1;
    chk("D4: valid_out=1 after posedge", dep_valid_out);
    dep_valid_in = 0; @(posedge clk); #1;
    chk("D4: valid_out=0 after deassert", !dep_valid_out);

    // ──────────────────────────────────────────────────────────────────────
    $display("");
    $display("════════════════════════════════════════════════════════════════");
    $display("  Results: %0d passed, %0d failed  (total %0d)", pass_cnt, fail_cnt, pass_cnt+fail_cnt);
    $display("════════════════════════════════════════════════════════════════");
    if (fail_cnt == 0) $display("  ALL TESTS PASSED");
    else                $display("  FAILURES DETECTED — see [FAIL] lines above");

    $finish;
  end

endmodule
