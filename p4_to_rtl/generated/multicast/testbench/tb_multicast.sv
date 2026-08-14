// ============================================================================
// tb_multicast.sv — Comprehensive self-checking testbench for multicast.p4
//
// Pipeline: V1Switch → MyIngress (processing_generated) → MyEgress
//           (egress_processing_generated)
//
// P4 multicast semantics under test:
//   Ingress: mac_lookup table (exact match on hdr.ethernet.dstAddr).
//     default_action = multicast -- unlike every other app's ipv4_lpm
//     (NoAction/drop on miss), a MISS here has a REAL side effect: the
//     table's own action-dispatch case statement's `else` branch
//     explicitly executes multicast()'s body (out_std_meta_mcast_grp=1),
//     confirmed directly in the generated RTL (`end else begin //
//     multicast on miss ... out_std_meta_mcast_grp = 'h0001; end`).
//   Egress: no keyed table. Loop-prevention: drop() if
//     standard_metadata.egress_port == standard_metadata.ingress_port.
//     (Only the linear, single-packet check is modeled -- this compiler's
//     egress doesn't support true multicast replication; see project
//     memory.)
//
// Ingress n_bounds=2 (1 keyed table) -> valid_out 3 cycles after valid_in.
// Egress has no keyed tables -> valid_out 1 cycle after valid_in.
// Parser: single-state (ethernet only, transitions to ACCEPT
// unconditionally regardless of etherType) -> 2 edges to `done`.
//
// Compile (from this directory):
//   iverilog -g2012 -o sim tb_multicast.sv \
//     ../parser_generated.sv ../processing_generated.sv \
//     ../egress_processing_generated.sv ../deparser_generated.sv \
//     ../mac_lookup_table.sv
//   vvp sim
// ============================================================================
`timescale 1ns/1ps

module tb_multicast;

  // ── Clock ──────────────────────────────────────────────────────────────
  localparam CLK_T = 10;
  logic clk = 0;
  always #(CLK_T/2) clk = ~clk;
  logic rst_n;

  // ==========================================================================
  // 1.  PARSER DUT
  // ==========================================================================
  logic        p_valid_in = 0;
  logic [15:0] p_eth_type = 0;
  logic        p_ext_eth, p_done;

  parser_generated parser_dut (
    .clk               (clk),
    .rst_n             (rst_n),
    .valid_in          (p_valid_in),
    .ethernet_etherType(p_eth_type),
    .extract_ethernet  (p_ext_eth),
    .done              (p_done)
  );

  // ==========================================================================
  // 2.  INGRESS PROCESSING DUT
  // ==========================================================================
  logic        pr_valid_in  = 0;
  logic        pr_eth_valid = 0;
  logic [47:0] pr_eth_dst  = 48'hAABBCCDDEEFF;
  logic [47:0] pr_eth_src  = 48'h112233445566;
  logic [15:0] pr_eth_type = 16'h0800;

  logic [47:0] pr_o_eth_dst;
  logic  [8:0] pr_o_egress_spec;
  logic [15:0] pr_o_mcast_grp;
  logic        pr_valid_out, pr_drop, pr_hit_out;

  logic        mac_cp_en   = 0;
  logic  [9:0] mac_cp_idx  = 0;
  logic [47:0] mac_cp_key  = 0;
  logic  [1:0] mac_cp_act  = 0;
  logic  [8:0] mac_cp_port = 0;

  processing_generated proc_dut (
    .clk                      (clk),
    .rst_n                    (rst_n),
    .valid_in                 (pr_valid_in),
    .ethernet_valid            (pr_eth_valid),
    .ethernet_dstAddr          (pr_eth_dst),
    .ethernet_srcAddr          (pr_eth_src),
    .ethernet_etherType        (pr_eth_type),
    .out_ethernet_valid        (),
    .out_ethernet_dstAddr      (pr_o_eth_dst),
    .out_ethernet_srcAddr      (),
    .out_ethernet_etherType    (),
    .out_std_meta_egress_spec  (pr_o_egress_spec),
    .out_std_meta_mcast_grp    (pr_o_mcast_grp),
    .mac_lookup_cp_wr_en       (mac_cp_en),
    .mac_lookup_cp_wr_idx      (mac_cp_idx),
    .mac_lookup_cp_wr_key_dstAddr(mac_cp_key),
    .mac_lookup_cp_wr_action   (mac_cp_act),
    .mac_lookup_cp_wr_p_port   (mac_cp_port),
    .mac_lookup_hit_out        (pr_hit_out),
    .valid_out                 (pr_valid_out),
    .drop                      (pr_drop)
  );

  // ==========================================================================
  // 3.  EGRESS PROCESSING DUT
  // ==========================================================================
  logic        eg_valid_in = 0;
  logic        eg_eth_valid = 1;
  logic [47:0] eg_eth_dst = 0, eg_eth_src = 0;
  logic [15:0] eg_eth_type = 0;
  logic  [8:0] eg_egress_port = 0, eg_ingress_port = 0;
  logic        eg_valid_out, eg_drop;

  egress_processing_generated egress_dut (
    .clk                   (clk),
    .rst_n                 (rst_n),
    .valid_in              (eg_valid_in),
    .ethernet_valid         (eg_eth_valid),
    .ethernet_dstAddr       (eg_eth_dst),
    .ethernet_srcAddr       (eg_eth_src),
    .ethernet_etherType     (eg_eth_type),
    .std_meta_egress_port   (eg_egress_port),
    .std_meta_ingress_port  (eg_ingress_port),
    .out_ethernet_valid     (),
    .out_ethernet_dstAddr   (),
    .out_ethernet_srcAddr   (),
    .out_ethernet_etherType (),
    .valid_out              (eg_valid_out),
    .drop                   (eg_drop)
  );

  // ==========================================================================
  // 4.  DEPARSER DUT — Ethernet only (112b)
  // ==========================================================================
  logic        dep_valid_in  = 0;
  logic        dep_eth_valid = 0;
  logic [47:0] dep_eth_dst = 0, dep_eth_src = 0;
  logic [15:0] dep_eth_type = 0;
  logic [111:0] dep_pkt_out;
  logic [15:0]  dep_pkt_len;
  logic         dep_valid_out;

  deparser_generated deparser_dut (
    .clk               (clk),
    .rst_n             (rst_n),
    .valid_in          (dep_valid_in),
    .ethernet_valid    (dep_eth_valid),
    .ethernet_dstAddr  (dep_eth_dst),
    .ethernet_srcAddr  (dep_eth_src),
    .ethernet_etherType(dep_eth_type),
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
    rst_n = 0; p_valid_in = 0; pr_valid_in = 0; eg_valid_in = 0; dep_valid_in = 0;
    pr_eth_valid = 0;
    repeat(5) @(posedge clk); @(negedge clk);
    rst_n = 1; @(posedge clk); #1;
  endtask

  task mac_write(input [9:0] idx, input [47:0] key, input [1:0] act, input [8:0] portn);
    @(negedge clk);
    mac_cp_idx=idx; mac_cp_key=key; mac_cp_act=act; mac_cp_port=portn;
    mac_cp_en=1;
    @(posedge clk); #1;
    mac_cp_en=0;
  endtask

  // n_bounds=2 -> valid_out is 3 cycles after valid_in
  task send_ingress_packet;
    pr_valid_in=1; @(posedge clk); #1; pr_valid_in=0;
    @(posedge clk); #1;
    @(posedge clk); #1;
  endtask

  // ==========================================================================
  // MAIN TEST
  // ==========================================================================
  initial begin
    $display("== tb_multicast: multicast.p4 self-checking regression ==\n");

    // ──────────────────────────────────────────────────────────────────────
    // SECTION 1 — PARSER
    // ──────────────────────────────────────────────────────────────────────
    $display("══ Section 1: Parser FSM ══════════════════════════════════════");
    do_reset();
    p_eth_type=16'h1234; p_valid_in=1; // etherType is irrelevant -- always -> accept
    @(posedge clk); #1;
    chk("P1 ETH: ext_eth", p_ext_eth);
    @(posedge clk); #1;
    chk("P1 ACCEPT: done", p_done);
    p_valid_in=0;

    // ──────────────────────────────────────────────────────────────────────
    // SECTION 2 — INGRESS: mac_lookup (exact match, default_action=multicast)
    // ──────────────────────────────────────────────────────────────────────
    $display("\n══ Section 2: Ingress mac_lookup ══════════════════════════════");
    do_reset();
    pr_eth_valid = 1;

    mac_write(0, 48'hAAAAAAAAAAAA, 2'd1, 9'd0);   // hit -> multicast
    mac_write(1, 48'hBBBBBBBBBBBB, 2'd2, 9'd7);   // hit -> mac_forward, port=7
    mac_write(2, 48'hCCCCCCCCCCCC, 2'd3, 9'd0);   // hit -> drop

    // L1: hit, action=multicast -> mcast_grp=1
    pr_eth_dst = 48'hAAAAAAAAAAAA;
    send_ingress_packet();
    chk("L1: not dropped",   !pr_drop);
    chk("L1: mcast_grp=1",   pr_o_mcast_grp === 16'd1);
    chk("L1: egress_spec=0", pr_o_egress_spec === 9'd0);

    // L2: hit, action=mac_forward -> egress_spec=7, mcast_grp stays 0
    pr_eth_dst = 48'hBBBBBBBBBBBB;
    send_ingress_packet();
    chk("L2: not dropped",   !pr_drop);
    chk("L2: egress_spec=7", pr_o_egress_spec === 9'd7);
    chk("L2: mcast_grp=0 (mac_forward doesn't touch it)", pr_o_mcast_grp === 16'd0);

    // L3: hit, action=drop
    pr_eth_dst = 48'hCCCCCCCCCCCC;
    send_ingress_packet();
    chk("L3: dropped", pr_drop);

    // L4: miss -> default_action=multicast fires its REAL side effect
    // (mcast_grp=1), not a no-op or a drop.
    pr_eth_dst = 48'hDDDDDDDDDDDD;
    send_ingress_packet();
    chk("L4: miss -> NOT dropped",              !pr_drop);
    chk("L4: miss -> default action mcast_grp=1", pr_o_mcast_grp === 16'd1);

    // ──────────────────────────────────────────────────────────────────────
    // SECTION 3 — Ingress valid_out latency (3-cycle)
    // ──────────────────────────────────────────────────────────────────────
    $display("\n══ Section 3: Ingress valid_out latency ═════════════════════════");
    do_reset();
    pr_eth_valid = 1;
    pr_valid_in=1; @(posedge clk); #1; pr_valid_in=0;
    chk("IV1: valid_out=0 after 1st edge", !pr_valid_out);
    @(posedge clk); #1;
    chk("IV1: valid_out=0 after 2nd edge", !pr_valid_out);
    @(posedge clk); #1;
    chk("IV1: valid_out=1 after 3rd edge", pr_valid_out);
    @(posedge clk); #1;
    chk("IV1: valid_out=0 deasserted", !pr_valid_out);

    // ──────────────────────────────────────────────────────────────────────
    // SECTION 4 — EGRESS: loop-prevention (egress_port == ingress_port)
    // ──────────────────────────────────────────────────────────────────────
    $display("\n══ Section 4: Egress loop-prevention ══════════════════════════");

    eg_egress_port = 9'd3; eg_ingress_port = 9'd3;
    #1;
    chk("E1: egress_port==ingress_port -> dropped", eg_drop);

    eg_egress_port = 9'd3; eg_ingress_port = 9'd5;
    #1;
    chk("E2: egress_port!=ingress_port -> not dropped", !eg_drop);

    // ──────────────────────────────────────────────────────────────────────
    // SECTION 5 — Egress valid_out latency (1-cycle)
    // ──────────────────────────────────────────────────────────────────────
    $display("\n══ Section 5: Egress valid_out latency ══════════════════════════");
    eg_valid_in = 1; @(posedge clk); #1;
    chk("EV1: valid_out=1 after posedge", eg_valid_out);
    eg_valid_in = 0; @(posedge clk); #1;
    chk("EV1: valid_out=0 after deassert", !eg_valid_out);

    // ──────────────────────────────────────────────────────────────────────
    // SECTION 6 — DEPARSER
    // ──────────────────────────────────────────────────────────────────────
    $display("\n══ Section 6: Deparser ══════════════════════════════════════════");

    dep_eth_valid = 1;
    dep_eth_dst = 48'hAAAAAAAAAAAA; dep_eth_src = 48'hBBBBBBBBBBBB; dep_eth_type = 16'h0800;
    #1;
    chk("D1: dep ethernet packed correctly", dep_pkt_out === {dep_eth_dst, dep_eth_src, dep_eth_type});
    chk("D1: pkt_hdr_len = 112", dep_pkt_len === 16'd112);

    dep_eth_valid = 0;
    #1;
    chk("D2: pkt_hdr_len = 0 (invalid)", dep_pkt_len === 16'd0);
    chk("D2: pkt_hdr_out zeroed",        dep_pkt_out === 112'd0);

    dep_eth_valid = 1;
    dep_valid_in = 1; @(posedge clk); #1;
    chk("D3: valid_out=1 after posedge", dep_valid_out);
    dep_valid_in = 0; @(posedge clk); #1;
    chk("D3: valid_out=0 after deassert", !dep_valid_out);

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
