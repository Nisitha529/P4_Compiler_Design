// ============================================================================
// tb_check_ports_table_standalone.sv -- opt-in exact-match tag-compare split
// correctness check (Phase 6, architecture-redesign effort). NOT a
// replacement for tb_firewall.sv's cycle-exact functional regression suite,
// and does not edit it. Purpose: isolate exactly the code path that changes
// when --target-freq-mhz forces emit_table.py to register the tag-compare
// (hit_c) out of the same cycle as the action-select mux (see
// timing_model.exact_match_tag_compare_stages()), independent of the rest
// of the pipeline. Deliberately does NOT assert an exact cycle count -- it
// waits a generous, budget-independent bound and checks final correctness
// only.
//
// Run against two separately-generated copies of check_ports_table.sv:
//   1. budget_levels=None (plain `python3 main.py firewall`) -- sanity
//      check the harness itself against already-verified 2-cycle behavior.
//   2. `python3 main.py firewall --target-freq-mhz 400 --device artix7`
//      (budget_levels=4 -> exact_match_tag_compare_stages([9,9],4)=2, i.e.
//      the tag-compare gets its own register) -- validates the new path.
//
// Compile (from this directory, against whichever check_ports_table.sv is
// currently generated one directory up):
//   iverilog -g2012 -o sim tb_check_ports_table_standalone.sv ../check_ports_table.sv
//   vvp sim
// ============================================================================
`timescale 1ns/1ps

module tb_check_ports_table_standalone;

  localparam CLK_T = 10;
  logic clk = 0;
  always #(CLK_T/2) clk = ~clk;
  logic rst_n;

  // Generous, budget-independent wait -- comfortably above the worst case
  // this feature would ever add (at most one extra register hop).
  localparam int WAIT_CYCLES = 16;

  logic [8:0] lkp_ingress_port;
  logic [8:0] lkp_egress_spec;
  logic       hit;
  logic [0:0] action_id;
  logic [0:0] p_dir;

  logic        cp_wr_en;
  logic [9:0]  cp_wr_idx;
  logic [8:0]  cp_wr_key_ingress_port;
  logic [8:0]  cp_wr_key_egress_spec;
  logic [0:0]  cp_wr_action;
  logic [0:0]  cp_wr_p_dir;

  check_ports_table #(.DEPTH(1024)) dut (
    .clk    (clk),
    .rst_n  (rst_n),
    .lkp_ingress_port (lkp_ingress_port),
    .lkp_egress_spec  (lkp_egress_spec),
    .hit       (hit),
    .action_id (action_id),
    .p_dir     (p_dir),
    .cp_wr_en  (cp_wr_en),
    .cp_wr_idx (cp_wr_idx),
    .cp_wr_key_ingress_port (cp_wr_key_ingress_port),
    .cp_wr_key_egress_spec  (cp_wr_key_egress_spec),
    .cp_wr_action           (cp_wr_action),
    .cp_wr_p_dir            (cp_wr_p_dir)
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

  task automatic cp_write(int idx, logic [8:0] ing, logic [8:0] egr,
                           logic [0:0] act, logic [0:0] dir);
    @(posedge clk);
    cp_wr_en                <= 1'b1;
    cp_wr_idx                 = idx[9:0];
    cp_wr_key_ingress_port     = ing;
    cp_wr_key_egress_spec      = egr;
    cp_wr_action                = act;
    cp_wr_p_dir                 = dir;
    @(posedge clk);
    cp_wr_en <= 1'b0;
  endtask

  task automatic do_lookup(logic [8:0] ing, logic [8:0] egr);
    lkp_ingress_port = ing;
    lkp_egress_spec  = egr;
    repeat (WAIT_CYCLES) @(posedge clk);
  endtask

  initial begin
    rst_n = 0;
    cp_wr_en = 0;
    lkp_ingress_port = '0;
    lkp_egress_spec  = '0;
    repeat (3) @(posedge clk);
    rst_n = 1;
    repeat (2) @(posedge clk);

    // Entry 0: ingress_port=1, egress_spec=2 -> set_direction(dir=1)
    cp_write(0, 9'd1, 9'd2, 1'd1, 1'b1);

    $display("== check_ports_table standalone opt-in correctness check ==");

    // T1: exact hit.
    do_lookup(9'd1, 9'd2);
    check("T1: hit", hit, 1'b1);
    check("T1: action_id == set_direction", action_id[0], 1'b1);
    check("T1: p_dir == 1", p_dir, 1'b1);

    // T2: miss (different ingress_port, doesn't tag-match the stored entry).
    do_lookup(9'd9, 9'd9);
    check("T2: miss -> hit=0", hit, 1'b0);
    check("T2: miss -> p_dir=0 (not stale)", p_dir, 1'b0);

    // T3: the regression case that actually exercises the fix -- a hit
    // lookup immediately followed by a miss lookup, no gap cycle. If the
    // new forwarding register (action_id_r2/p_r2_dir) were accidentally
    // hit-gated instead of updated unconditionally every cycle, a stale
    // p_dir=1 from this hit could leak into the very next miss.
    lkp_ingress_port = 9'd1; lkp_egress_spec = 9'd2; // hit
    @(posedge clk); #1;
    lkp_ingress_port = 9'd9; lkp_egress_spec = 9'd9; // miss, no gap cycle
    repeat (WAIT_CYCLES) @(posedge clk);
    check("T3: back-to-back hit-then-miss -> hit=0", hit, 1'b0);
    check("T3: back-to-back hit-then-miss -> p_dir=0 (no stale leak)", p_dir, 1'b0);

    $display("");
    $display("========================================");
    $display("  Results: %0d passed, %0d failed (total %0d)", pass_count, fail_count, pass_count + fail_count);
    $display("========================================");
    if (fail_count == 0) $display("  ALL TESTS PASSED");
    else $display("  SOME TESTS FAILED");

    $finish;
  end

endmodule
