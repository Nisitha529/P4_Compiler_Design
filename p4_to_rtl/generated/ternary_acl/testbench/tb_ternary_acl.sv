// ============================================================================
// tb_ternary_acl.sv — Comprehensive self-checking testbench for ternary_acl.p4
//
// Pipeline: V1Switch → MyIngress (processing_generated)
//
// Purpose: this app exists solely to exercise `ternary` matching for real --
// no other app in this project uses it. `acl` table:
//   key = { hdr.ipv4.srcAddr: ternary; hdr.ipv4.protocol: ternary; }
//   actions = { permit(port); deny; NoAction; }  default_action = NoAction
// Ternary uses an explicit control-plane-supplied mask per field (arbitrary
// bit pattern, not a derived prefix mask like LPM) -- confirmed directly in
// the generated RTL: `(lkp_srcAddr & mask) == (key & mask)`, same for
// protocol. Both fields share the balanced-binary-tree priority-match
// reduction as LPM (lowest index wins), but this is the first testbench in
// the project to actually drive that path with wildcard/overlapping entries.
//
// Ingress n_bounds=2 (1 keyed table) -> valid_out 3 cycles after valid_in
// (identical structure to multicast.p4's mac_lookup).
// Parser: Ethernet -> [IPv4] -> accept, 3 states -> 3 edges to `done` when
// etherType=0x0800, 2 edges when it isn't (skips PARSE_IPV4 entirely).
//
// Compile (from this directory):
//   iverilog -g2012 -o sim tb_ternary_acl.sv \
//     ../parser_generated.sv ../processing_generated.sv \
//     ../deparser_generated.sv ../acl_table.sv
//   vvp sim
// ============================================================================
`timescale 1ns/1ps

module tb_ternary_acl;

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
  logic        p_ext_eth, p_ext_ipv4, p_done;

  parser_generated parser_dut (
    .clk               (clk),
    .rst_n             (rst_n),
    .valid_in          (p_valid_in),
    .ethernet_etherType(p_eth_type),
    .extract_ethernet  (p_ext_eth),
    .extract_ipv4      (p_ext_ipv4),
    .done              (p_done)
  );

  // ==========================================================================
  // 2.  INGRESS PROCESSING DUT
  // ==========================================================================
  logic        pr_valid_in   = 0;
  logic        pr_eth_valid  = 0;
  logic        pr_ipv4_valid = 0;

  logic [47:0] pr_eth_dst  = 48'hAABBCCDDEEFF;
  logic [47:0] pr_eth_src  = 48'h112233445566;
  logic [15:0] pr_eth_type = 16'h0800;
  logic  [3:0] pr_ipv4_ver = 4;
  logic  [3:0] pr_ipv4_ihl = 5;
  logic  [7:0] pr_ipv4_ds  = 0;
  logic [15:0] pr_ipv4_len = 40;
  logic [15:0] pr_ipv4_id  = 1;
  logic  [2:0] pr_ipv4_flg = 3'b010;
  logic [12:0] pr_ipv4_off = 0;
  logic  [7:0] pr_ipv4_ttl = 64;
  logic  [7:0] pr_ipv4_proto = 6;
  logic [15:0] pr_ipv4_chk = 0;
  logic [31:0] pr_ipv4_src = 0;
  logic [31:0] pr_ipv4_dst = 32'hC0A80001;

  logic  [8:0] pr_o_egress_spec;
  logic        pr_valid_out, pr_drop, pr_hit_out;

  logic        acl_cp_en   = 0;
  logic  [7:0] acl_cp_idx  = 0;
  logic [31:0] acl_cp_key_srcAddr  = 0;
  logic  [7:0] acl_cp_key_protocol = 0;
  logic [31:0] acl_cp_mask_srcAddr  = 0;
  logic  [7:0] acl_cp_mask_protocol = 0;
  logic  [1:0] acl_cp_act  = 0;
  logic  [8:0] acl_cp_port = 0;

  processing_generated proc_dut (
    .clk                        (clk),
    .rst_n                      (rst_n),
    .valid_in                   (pr_valid_in),
    .ethernet_valid              (pr_eth_valid),
    .ipv4_valid                  (pr_ipv4_valid),
    .ethernet_dstAddr            (pr_eth_dst),
    .ethernet_srcAddr            (pr_eth_src),
    .ethernet_etherType          (pr_eth_type),
    .ipv4_version                (pr_ipv4_ver),
    .ipv4_ihl                    (pr_ipv4_ihl),
    .ipv4_diffserv               (pr_ipv4_ds),
    .ipv4_totalLen               (pr_ipv4_len),
    .ipv4_identification         (pr_ipv4_id),
    .ipv4_flags                  (pr_ipv4_flg),
    .ipv4_fragOffset             (pr_ipv4_off),
    .ipv4_ttl                    (pr_ipv4_ttl),
    .ipv4_protocol               (pr_ipv4_proto),
    .ipv4_hdrChecksum            (pr_ipv4_chk),
    .ipv4_srcAddr                (pr_ipv4_src),
    .ipv4_dstAddr                (pr_ipv4_dst),
    .out_ethernet_valid          (),
    .out_ipv4_valid              (),
    .out_ethernet_dstAddr        (),
    .out_ethernet_srcAddr        (),
    .out_ethernet_etherType      (),
    .out_ipv4_version            (),
    .out_ipv4_ihl                (),
    .out_ipv4_diffserv           (),
    .out_ipv4_totalLen           (),
    .out_ipv4_identification     (),
    .out_ipv4_flags              (),
    .out_ipv4_fragOffset         (),
    .out_ipv4_ttl                (),
    .out_ipv4_protocol           (),
    .out_ipv4_hdrChecksum        (),
    .out_ipv4_srcAddr            (),
    .out_ipv4_dstAddr            (),
    .out_std_meta_egress_spec    (pr_o_egress_spec),
    .acl_cp_wr_en                (acl_cp_en),
    .acl_cp_wr_idx               (acl_cp_idx),
    .acl_cp_wr_key_srcAddr       (acl_cp_key_srcAddr),
    .acl_cp_wr_key_protocol      (acl_cp_key_protocol),
    .acl_cp_wr_mask_srcAddr      (acl_cp_mask_srcAddr),
    .acl_cp_wr_mask_protocol     (acl_cp_mask_protocol),
    .acl_cp_wr_action            (acl_cp_act),
    .acl_cp_wr_p_port            (acl_cp_port),
    .acl_hit_out                 (pr_hit_out),
    .valid_out                   (pr_valid_out),
    .drop                        (pr_drop)
  );

  // ==========================================================================
  // 3.  DEPARSER DUT — Ethernet(112b) | IPv4(160b) = 272b
  // ==========================================================================
  logic        dep_valid_in   = 0;
  logic        dep_eth_valid  = 0;
  logic        dep_ipv4_valid = 0;
  logic [47:0] dep_eth_dst = 0, dep_eth_src = 0;
  logic [15:0] dep_eth_type = 0;
  logic  [3:0] dep_ipv4_ver = 0, dep_ipv4_ihl = 0;
  logic  [7:0] dep_ipv4_ds = 0, dep_ipv4_ttl = 0, dep_ipv4_proto = 0;
  logic [15:0] dep_ipv4_len = 0, dep_ipv4_id = 0, dep_ipv4_chk = 0;
  logic  [2:0] dep_ipv4_flg = 0;
  logic [12:0] dep_ipv4_off = 0;
  logic [31:0] dep_ipv4_src = 0, dep_ipv4_dst = 0;
  logic [271:0] dep_pkt_out;
  logic [15:0]  dep_pkt_len;
  logic         dep_valid_out;

  deparser_generated deparser_dut (
    .clk               (clk),
    .rst_n             (rst_n),
    .valid_in          (dep_valid_in),
    .ethernet_valid    (dep_eth_valid),
    .ipv4_valid        (dep_ipv4_valid),
    .ethernet_dstAddr  (dep_eth_dst),
    .ethernet_srcAddr  (dep_eth_src),
    .ethernet_etherType(dep_eth_type),
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
    rst_n = 0; p_valid_in = 0; pr_valid_in = 0; dep_valid_in = 0;
    pr_eth_valid = 0; pr_ipv4_valid = 0;
    repeat(5) @(posedge clk); @(negedge clk);
    rst_n = 1; @(posedge clk); #1;
  endtask

  task acl_write(input [7:0] idx, input [31:0] keyS, input [31:0] maskS,
                  input [7:0] keyP, input [7:0] maskP,
                  input [1:0] act, input [8:0] portn);
    @(negedge clk);
    acl_cp_idx=idx;
    acl_cp_key_srcAddr=keyS; acl_cp_mask_srcAddr=maskS;
    acl_cp_key_protocol=keyP; acl_cp_mask_protocol=maskP;
    acl_cp_act=act; acl_cp_port=portn;
    acl_cp_en=1;
    @(posedge clk); #1;
    acl_cp_en=0;
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
    $display("== tb_ternary_acl: ternary_acl.p4 self-checking regression ==\n");

    // ──────────────────────────────────────────────────────────────────────
    // SECTION 1 — PARSER
    // ──────────────────────────────────────────────────────────────────────
    $display("══ Section 1: Parser FSM ══════════════════════════════════════");
    do_reset();
    p_eth_type=16'h0800; p_valid_in=1;
    @(posedge clk); #1;
    chk("P1 ETH: ext_eth", p_ext_eth);
    @(posedge clk); #1;
    chk("P1 IPV4: ext_ipv4", p_ext_ipv4);
    @(posedge clk); #1;
    chk("P1 ACCEPT: done", p_done);
    p_valid_in=0;

    do_reset();
    p_eth_type=16'h1234; p_valid_in=1; // non-IPv4 -> skip parse_ipv4 entirely
    @(posedge clk); #1;
    chk("P2 ETH: ext_eth", p_ext_eth);
    @(posedge clk); #1;
    chk("P2 ACCEPT (skipped ipv4): done", p_done);
    p_valid_in=0;

    // ──────────────────────────────────────────────────────────────────────
    // SECTION 2 — INGRESS: acl (ternary match, arbitrary bit-pattern masks)
    // ──────────────────────────────────────────────────────────────────────
    $display("\n══ Section 2: Ingress acl (ternary) ═══════════════════════════");
    do_reset();
    pr_eth_valid = 1; pr_ipv4_valid = 1;

    // idx0: match only srcAddr bytes [31:24] and [15:8] (non-contiguous ->
    // genuinely ternary, not expressible as an LPM prefix), protocol exact=6.
    acl_write(0, 32'h0A00C800, 32'hFF00FF00, 8'd6, 8'hFF, 2'd1, 9'd3);   // permit, port=3
    // idx1: full exact srcAddr, protocol wildcard (mask=0 -> any protocol).
    acl_write(1, 32'hC0A80005, 32'hFFFFFFFF, 8'd0, 8'h00, 2'd2, 9'd0);   // deny
    // idx2: full exact srcAddr, protocol exact=6.
    acl_write(2, 32'hC0A80099, 32'hFFFFFFFF, 8'd6, 8'hFF, 2'd1, 9'd9);   // permit, port=9
    // idx3: identical match criteria to idx0 but action=deny -- tests that
    // the priority-match tree picks the LOWEST index (idx0) on a tie.
    acl_write(3, 32'h0A00C800, 32'hFF00FF00, 8'd6, 8'hFF, 2'd2, 9'd0);   // deny

    // T1: matches idx0 AND idx3 (identical mask/key) -> idx0 (lower index)
    // must win -> permit, port=3, not dropped.
    pr_ipv4_src = 32'h0A11C822; pr_ipv4_proto = 6;
    send_ingress_packet();
    chk("T1: priority -> idx0 wins over idx3 -> not dropped", !pr_drop);
    chk("T1: priority -> idx0 wins -> egress_spec=3", pr_o_egress_spec === 9'd3);

    // T2: srcAddr byte[31:24] mismatches idx0/idx3's masked pattern, and
    // doesn't match idx1/idx2's exact srcAddr either -> miss -> NoAction.
    pr_ipv4_src = 32'h0B11C822; pr_ipv4_proto = 6;
    send_ingress_packet();
    chk("T2: miss -> not dropped",        !pr_drop);
    chk("T2: miss -> egress_spec=0 (NoAction)", pr_o_egress_spec === 9'd0);
    chk("T2: miss -> hit_out=0",           !pr_hit_out);

    // T3: exact srcAddr match on idx1, protocol wildcarded (mask=0) so an
    // arbitrary protocol value (17=UDP) still hits -> deny -> dropped.
    pr_ipv4_src = 32'hC0A80005; pr_ipv4_proto = 17;
    send_ingress_packet();
    chk("T3: wildcard protocol -> idx1 hits regardless of value -> dropped", pr_drop);

    // T4: same srcAddr, different protocol value (6) -- still hits idx1
    // since the mask genuinely ignores the field, confirming it's not
    // coincidentally matching a specific value.
    pr_ipv4_src = 32'hC0A80005; pr_ipv4_proto = 6;
    send_ingress_packet();
    chk("T4: wildcard protocol -> idx1 still hits with a different value -> dropped", pr_drop);

    // T5: exact match on idx2 (srcAddr + protocol both exact) -> permit,
    // port=9.
    pr_ipv4_src = 32'hC0A80099; pr_ipv4_proto = 6;
    send_ingress_packet();
    chk("T5: exact match idx2 -> not dropped", !pr_drop);
    chk("T5: exact match idx2 -> egress_spec=9", pr_o_egress_spec === 9'd9);

    // T6: idx2's srcAddr matches but protocol (17) doesn't (mask=FF, exact
    // required) -> miss on idx2, and no other entry's srcAddr matches ->
    // total miss -> NoAction.
    pr_ipv4_src = 32'hC0A80099; pr_ipv4_proto = 17;
    send_ingress_packet();
    chk("T6: protocol exact-match miss -> not dropped", !pr_drop);
    chk("T6: protocol exact-match miss -> egress_spec=0 (NoAction)", pr_o_egress_spec === 9'd0);

    // ──────────────────────────────────────────────────────────────────────
    // SECTION 3 — Ingress valid_out latency (3-cycle)
    // ──────────────────────────────────────────────────────────────────────
    $display("\n══ Section 3: Ingress valid_out latency ═════════════════════════");
    do_reset();
    pr_eth_valid = 1; pr_ipv4_valid = 1;
    pr_valid_in=1; @(posedge clk); #1; pr_valid_in=0;
    chk("IV1: valid_out=0 after 1st edge", !pr_valid_out);
    @(posedge clk); #1;
    chk("IV1: valid_out=0 after 2nd edge", !pr_valid_out);
    @(posedge clk); #1;
    chk("IV1: valid_out=1 after 3rd edge", pr_valid_out);
    @(posedge clk); #1;
    chk("IV1: valid_out=0 deasserted", !pr_valid_out);

    // ──────────────────────────────────────────────────────────────────────
    // SECTION 4 — DEPARSER
    // ──────────────────────────────────────────────────────────────────────
    $display("\n══ Section 4: Deparser ══════════════════════════════════════════");

    dep_eth_valid = 1; dep_ipv4_valid = 0;
    dep_eth_dst = 48'hAAAAAAAAAAAA; dep_eth_src = 48'hBBBBBBBBBBBB; dep_eth_type = 16'h0800;
    #1;
    chk("D1: ethernet-only packed correctly",
        dep_pkt_out[271:160] === {dep_eth_dst, dep_eth_src, dep_eth_type});
    chk("D1: ipv4 half zeroed",  dep_pkt_out[159:0] === 160'd0);
    chk("D1: pkt_hdr_len = 112", dep_pkt_len === 16'd112);

    dep_ipv4_valid = 1;
    dep_ipv4_ver = 4; dep_ipv4_ihl = 5; dep_ipv4_ds = 0; dep_ipv4_len = 40;
    dep_ipv4_id = 1; dep_ipv4_flg = 3'b010; dep_ipv4_off = 0; dep_ipv4_ttl = 64;
    dep_ipv4_proto = 6; dep_ipv4_chk = 16'hBEEF;
    dep_ipv4_src = 32'h0A11C822; dep_ipv4_dst = 32'hC0A80005;
    #1;
    chk("D2: ethernet+ipv4 packed correctly",
        dep_pkt_out === {dep_eth_dst, dep_eth_src, dep_eth_type,
                          dep_ipv4_ver, dep_ipv4_ihl, dep_ipv4_ds, dep_ipv4_len,
                          dep_ipv4_id, dep_ipv4_flg, dep_ipv4_off, dep_ipv4_ttl,
                          dep_ipv4_proto, dep_ipv4_chk, dep_ipv4_src, dep_ipv4_dst});
    chk("D2: pkt_hdr_len = 272", dep_pkt_len === 16'd272);

    dep_eth_valid = 0; dep_ipv4_valid = 0;
    #1;
    chk("D3: pkt_hdr_len = 0 (invalid)", dep_pkt_len === 16'd0);
    chk("D3: pkt_hdr_out zeroed",        dep_pkt_out === 272'd0);

    dep_eth_valid = 1;
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
