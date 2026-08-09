// ============================================================================
// tb_ipv4_lpm_table_standalone.sv -- opt-in table-tree-splitting correctness
// check (Phase 5, architecture-redesign effort). NOT a replacement for
// tb_firewall.sv's cycle-exact functional regression suite, and does not
// edit it. Purpose: isolate exactly the code path that changes when
// --target-freq-mhz forces emit_table.py to split an LPM table's internal
// priority-match tree across extra pipeline registers (see
// timing_model.table_tree_stages()), independent of the rest of the
// pipeline. Deliberately does NOT assert an exact cycle count -- that
// count is supposed to change with --target-freq-mhz -- it waits a
// generous, budget-independent bound and checks final correctness only.
//
// Run against two separately-generated copies of ipv4_lpm_table.sv:
//   1. budget_levels=None (plain `python3 main.py firewall`)      -- sanity
//      check the harness itself against already-verified 2-cycle behavior.
//   2. `python3 main.py firewall --target-freq-mhz 400 --device artix7`
//      (budget_levels=4 -> table_tree_stages(1024,4)=3, i.e. 2 mid-tree
//      pipeline registers) -- validates the new splitting.
//
// Compile (from this directory, against whichever ipv4_lpm_table.sv is
// currently generated one directory up):
//   iverilog -g2012 -o sim tb_ipv4_lpm_table_standalone.sv ../ipv4_lpm_table.sv
//   vvp sim
// ============================================================================
`timescale 1ns/1ps

module tb_ipv4_lpm_table_standalone;

  localparam CLK_T = 10;
  logic clk = 0;
  always #(CLK_T/2) clk = ~clk;
  logic rst_n;

  // Generous, budget-independent wait: worst case is budget_levels=1 on a
  // DEPTH=1024 table (table_tree_stages=10, i.e. 11 total cycles). 32 is
  // comfortably above that for any budget_levels this compiler would ever
  // realistically be asked to hit.
  localparam int WAIT_CYCLES = 32;

  logic [31:0] lkp_dstAddr;
  logic        hit;
  logic [1:0]  action_id;
  logic [47:0] p_dstAddr;
  logic [8:0]  p_port;

  logic        cp_wr_en;
  logic [9:0]  cp_wr_idx;
  logic [31:0] cp_wr_key_dstAddr;
  logic [5:0]  cp_wr_pfx_len;
  logic [1:0]  cp_wr_action;
  logic [47:0] cp_wr_p_dstAddr;
  logic [8:0]  cp_wr_p_port;

  ipv4_lpm_table #(.DEPTH(1024)) dut (
    .clk    (clk),
    .rst_n  (rst_n),
    .lkp_dstAddr (lkp_dstAddr),
    .hit       (hit),
    .action_id (action_id),
    .p_dstAddr (p_dstAddr),
    .p_port    (p_port),
    .cp_wr_en  (cp_wr_en),
    .cp_wr_idx (cp_wr_idx),
    .cp_wr_key_dstAddr (cp_wr_key_dstAddr),
    .cp_wr_pfx_len     (cp_wr_pfx_len),
    .cp_wr_action      (cp_wr_action),
    .cp_wr_p_dstAddr   (cp_wr_p_dstAddr),
    .cp_wr_p_port      (cp_wr_p_port)
  );

  int pass_count = 0;
  int fail_count = 0;

  task automatic check(string name, logic got, logic exp);
    if (got === exp) begin
      pass_count++;
      $display("    [PASS] %s", name);
    end else begin
      fail_count++;
      $display("    [FAIL] %s (got=%0b exp=%0b)", name, got, exp);
    end
  endtask

  task automatic check_bits(string name, logic [63:0] got, logic [63:0] exp, logic [63:0] mask);
    if ((got & mask) === (exp & mask)) begin
      pass_count++;
      $display("    [PASS] %s", name);
    end else begin
      fail_count++;
      $display("    [FAIL] %s (got=%0h exp=%0h)", name, got & mask, exp & mask);
    end
  endtask

  task automatic cp_write(int idx, logic [31:0] key, logic [5:0] pfx_len,
                           logic [1:0] act, logic [47:0] p_mac, logic [8:0] p_port_val);
    @(posedge clk);
    cp_wr_en          <= 1'b1;
    cp_wr_idx          = idx[9:0];
    cp_wr_key_dstAddr  = key;
    cp_wr_pfx_len      = pfx_len;
    cp_wr_action       = act;
    cp_wr_p_dstAddr    = p_mac;
    cp_wr_p_port       = p_port_val;
    @(posedge clk);
    cp_wr_en <= 1'b0;
  endtask

  task automatic do_lookup(logic [31:0] key);
    lkp_dstAddr = key;
    repeat (WAIT_CYCLES) @(posedge clk);
  endtask

  initial begin
    rst_n = 0;
    cp_wr_en = 0;
    lkp_dstAddr = '0;
    repeat (3) @(posedge clk);
    rst_n = 1;
    repeat (2) @(posedge clk);

    // Entry 0: 192.168.0.0/24 -> ipv4_forward (action_id=1), dstAddr=AA:BB:CC:DD:EE:FF, port=3
    cp_write(0, 32'hC0A80000, 6'd24, 2'd1, 48'hAABBCCDDEEFF, 9'd3);
    // Entry 1: 10.0.0.0/8 -> drop (action_id=2)
    cp_write(1, 32'h0A000000, 6'd8, 2'd2, 48'h0, 9'd0);
    // Entry 2: 192.168.0.0/16 (shorter prefix, same top bits as entry 0) -> ipv4_forward, different params
    cp_write(2, 32'hC0A80000, 6'd16, 2'd1, 48'h112233445566, 9'd7);

    $display("== ipv4_lpm_table standalone opt-in correctness check ==");

    // T1: exact hit on the /24 entry (also matches the /16 entry -- lowest
    // index wins, so entry 0 (the /24) must win over entry 2 (the /16)).
    do_lookup(32'hC0A80001); // 192.168.0.1
    check("T1: hit", hit, 1'b1);
    check_bits("T1: action_id == ipv4_forward", action_id, 2'd1, 64'h3);
    check_bits("T1: p_dstAddr == entry0 mac", p_dstAddr, 48'hAABBCCDDEEFF, 64'hFFFFFFFFFFFF);
    check_bits("T1: p_port == entry0 port", p_port, 9'd3, 64'h1FF);

    // T2: falls outside the /24 but inside the /16 -- entry 2 should win.
    do_lookup(32'hC0A80101); // 192.168.1.1
    check("T2: hit", hit, 1'b1);
    check_bits("T2: action_id == ipv4_forward", action_id, 2'd1, 64'h3);
    check_bits("T2: p_dstAddr == entry2 mac", p_dstAddr, 48'h112233445566, 64'hFFFFFFFFFFFF);
    check_bits("T2: p_port == entry2 port", p_port, 9'd7, 64'h1FF);

    // T3: matches the /8 drop entry.
    do_lookup(32'h0A010203); // 10.1.2.3
    check("T3: hit", hit, 1'b1);
    check_bits("T3: action_id == drop", action_id, 2'd2, 64'h3);

    // T4: no match at all.
    do_lookup(32'h08080808); // 8.8.8.8
    check("T4: miss -> hit=0", hit, 1'b0);

    $display("");
    $display("========================================");
    $display("  Results: %0d passed, %0d failed (total %0d)", pass_count, fail_count, pass_count + fail_count);
    $display("========================================");
    if (fail_count == 0) $display("  ALL TESTS PASSED");
    else $display("  SOME TESTS FAILED");

    $finish;
  end

endmodule
