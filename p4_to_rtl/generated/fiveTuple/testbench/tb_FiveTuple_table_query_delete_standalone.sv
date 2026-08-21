// ============================================================================
// tb_FiveTuple_table_query_delete_standalone.sv -- control-plane query/delete
// correctness check for the plain (direct-mapped, ways=1) exact-match table.
// NOT a replacement for tb_fiveTuple_top.sv's cycle-exact functional
// regression suite, and does not edit it -- that suite covers the datapath
// (packet lookup / cut-through) and pre-existing AXI4-Lite writes, none of
// which this feature changes (default behavior for every app that doesn't
// reach the p4test/XSA frontend stays byte-identical, verified separately
// via full bmv2 regression). Purpose: isolate exactly the new code path
// emit_table.py's _emit_exact_match_table() adds when enable_query=True --
// the query/delete port-B pipeline (cp_query_en/cp_query_del/cp_query_busy/
// cp_query_hit/...) -- independent of the AXI4-Lite decoder that drives it
// in the real design.
//
// This table (unlike the d-way associative table) has no cp_wr_busy port:
// a plain write commits in a single cycle. The query/delete pipeline is a
// separate 2-stage (accept, resolve) sequence that time-multiplexes the
// same port-B memory access; a plain write and an in-flight query/delete
// are mutually exclusive by construction (see FiveTuple_table.sv's single
// always_ff driving mem_valid). Tests 5/6 below exercise both directions of
// that exclusion.
//
// Run directly against the committed generated/fiveTuple/FiveTuple_table.sv
// -- query/delete is automatically enabled for the p4test/XSA frontend
// (enable_query = (frontend == 'p4test') in main.py), so no special
// regeneration flags are needed, unlike the --exact-match-ways feature.
//
// Compile:
//   iverilog -g2012 -o sim tb_FiveTuple_table_query_delete_standalone.sv ../FiveTuple_table.sv
//   vvp sim
// ============================================================================
`timescale 1ns/1ps

module tb_FiveTuple_table_query_delete_standalone;

  localparam CLK_T = 10;
  logic clk = 0;
  always #(CLK_T/2) clk = ~clk;
  logic rst_n;

  // Generous, budget-independent wait for a packet lookup to settle.
  localparam int WAIT_CYCLES = 8;

  logic [31:0] lkp_src, lkp_dst;
  logic [7:0]  lkp_protocol;
  logic [15:0] lkp_table_key_sport, lkp_table_key_dport;
  logic        hit;
  logic [0:0]  action_id;
  logic [12:0] p_counter_index;
  logic [2:0]  p_pcp;
  logic [0:0]  p_cfi;
  logic [11:0] p_vid;

  logic        cp_wr_en;
  logic [12:0] cp_wr_idx = 0;
  logic [31:0] cp_wr_key_src, cp_wr_key_dst;
  logic [7:0]  cp_wr_key_protocol;
  logic [15:0] cp_wr_key_table_key_sport, cp_wr_key_table_key_dport;
  logic [0:0]  cp_wr_action;
  logic [12:0] cp_wr_p_counter_index;
  logic [2:0]  cp_wr_p_pcp;
  logic [0:0]  cp_wr_p_cfi;
  logic [11:0] cp_wr_p_vid;

  logic        cp_query_en;
  logic        cp_query_del;
  logic [31:0] cp_query_key_src, cp_query_key_dst;
  logic [7:0]  cp_query_key_protocol;
  logic [15:0] cp_query_key_table_key_sport, cp_query_key_table_key_dport;
  logic        cp_query_busy;
  logic        cp_query_hit;
  logic [0:0]  cp_query_action_id;
  logic [12:0] cp_query_p_counter_index;
  logic [2:0]  cp_query_p_pcp;
  logic [0:0]  cp_query_p_cfi;
  logic [11:0] cp_query_p_vid;

  FiveTuple_table dut (
    .clk                          (clk),
    .rst_n                        (rst_n),
    .lkp_src                      (lkp_src),
    .lkp_dst                      (lkp_dst),
    .lkp_protocol                 (lkp_protocol),
    .lkp_table_key_sport          (lkp_table_key_sport),
    .lkp_table_key_dport          (lkp_table_key_dport),
    .hit                          (hit),
    .action_id                    (action_id),
    .p_counter_index              (p_counter_index),
    .p_pcp                        (p_pcp),
    .p_cfi                        (p_cfi),
    .p_vid                        (p_vid),
    .cp_wr_en                     (cp_wr_en),
    .cp_wr_idx                    (cp_wr_idx),
    .cp_wr_key_src                (cp_wr_key_src),
    .cp_wr_key_dst                (cp_wr_key_dst),
    .cp_wr_key_protocol           (cp_wr_key_protocol),
    .cp_wr_key_table_key_sport    (cp_wr_key_table_key_sport),
    .cp_wr_key_table_key_dport    (cp_wr_key_table_key_dport),
    .cp_wr_action                 (cp_wr_action),
    .cp_wr_p_counter_index        (cp_wr_p_counter_index),
    .cp_wr_p_pcp                  (cp_wr_p_pcp),
    .cp_wr_p_cfi                  (cp_wr_p_cfi),
    .cp_wr_p_vid                  (cp_wr_p_vid),
    .cp_query_en                  (cp_query_en),
    .cp_query_del                 (cp_query_del),
    .cp_query_key_src             (cp_query_key_src),
    .cp_query_key_dst             (cp_query_key_dst),
    .cp_query_key_protocol        (cp_query_key_protocol),
    .cp_query_key_table_key_sport (cp_query_key_table_key_sport),
    .cp_query_key_table_key_dport (cp_query_key_table_key_dport),
    .cp_query_busy                (cp_query_busy),
    .cp_query_hit                 (cp_query_hit),
    .cp_query_action_id           (cp_query_action_id),
    .cp_query_p_counter_index     (cp_query_p_counter_index),
    .cp_query_p_pcp               (cp_query_p_pcp),
    .cp_query_p_cfi               (cp_query_p_cfi),
    .cp_query_p_vid               (cp_query_p_vid)
  );

  int pass_cnt = 0, fail_cnt = 0;
  task automatic chk(input string name, input logic cond);
    if (cond) begin $display("    [PASS] %s", name); pass_cnt++; end
    else      begin $display("    [FAIL] %s", name); fail_cnt++; end
  endtask

  task automatic do_reset;
    rst_n = 0; cp_wr_en = 0; cp_query_en = 0; cp_query_del = 0;
    lkp_src = 0; lkp_dst = 0; lkp_protocol = 0;
    lkp_table_key_sport = 0; lkp_table_key_dport = 0;
    repeat(5) @(posedge clk); @(negedge clk);
    rst_n = 1; @(posedge clk); #1;
  endtask

  // Plain write: this table has no cp_wr_busy (single-cycle commit, unlike
  // the d-way associative table), so a one-cycle pulse is the whole task.
  task automatic cp_write(input [31:0] src, input [31:0] dst, input [7:0] proto,
                           input [15:0] sport, input [15:0] dport,
                           input [0:0] act, input [12:0] c_idx,
                           input [2:0] pcp, input [0:0] cfi, input [11:0] vid);
    @(negedge clk);
    cp_wr_key_src = src; cp_wr_key_dst = dst; cp_wr_key_protocol = proto;
    cp_wr_key_table_key_sport = sport; cp_wr_key_table_key_dport = dport;
    cp_wr_action = act; cp_wr_p_counter_index = c_idx;
    cp_wr_p_pcp = pcp; cp_wr_p_cfi = cfi; cp_wr_p_vid = vid;
    cp_wr_en = 1;
    @(posedge clk); #1;
    cp_wr_en = 0;
  endtask

  // Well-behaved query/delete: waits for cp_query_busy to clear before
  // returning. Results are then readable directly off the DUT's sticky
  // cp_query_hit/cp_query_action_id/cp_query_p_* outputs.
  task automatic cp_query(input [31:0] src, input [31:0] dst, input [7:0] proto,
                           input [15:0] sport, input [15:0] dport, input del);
    @(negedge clk);
    cp_query_key_src = src; cp_query_key_dst = dst; cp_query_key_protocol = proto;
    cp_query_key_table_key_sport = sport; cp_query_key_table_key_dport = dport;
    cp_query_del = del;
    cp_query_en = 1;
    @(posedge clk); #1;
    cp_query_en = 0;
    while (cp_query_busy) @(posedge clk);
    #1;
  endtask

  task automatic do_lookup(input [31:0] src, input [31:0] dst, input [7:0] proto,
                            input [15:0] sport, input [15:0] dport);
    lkp_src = src; lkp_dst = dst; lkp_protocol = proto;
    lkp_table_key_sport = sport; lkp_table_key_dport = dport;
    repeat (WAIT_CYCLES) @(posedge clk);
    #1;
  endtask

  // Test keys -- distinct field values, no collision requirement (this
  // feature's correctness doesn't depend on bucket collisions).
  // KeyA: written, queried, deleted across T1/T3/T7.
  localparam [31:0] A_SRC = 32'hAAAA_0001, A_DST = 32'hBBBB_0001;
  localparam [7:0]  A_PROTO = 8'h11;
  localparam [15:0] A_SPORT = 16'd1000, A_DPORT = 16'd2000;
  localparam [0:0]  A_ACT = 1'd1;
  localparam [12:0] A_CIDX = 13'd100;
  localparam [2:0]  A_PCP = 3'd5;
  localparam [0:0]  A_CFI = 1'd1;
  localparam [11:0] A_VID = 12'd42;

  // KeyC: never written -- used for miss tests.
  localparam [31:0] C_SRC = 32'hCCCC_0001, C_DST = 32'hDDDD_0001;
  localparam [7:0]  C_PROTO = 8'h01;
  localparam [15:0] C_SPORT = 16'd3000, C_DPORT = 16'd4000;

  // KeyD: attempted write while a query is busy -- must be dropped.
  localparam [31:0] D_SRC = 32'hEEEE_0001, D_DST = 32'hFFFF_0001;
  localparam [7:0]  D_PROTO = 8'h06;
  localparam [15:0] D_SPORT = 16'd1234, D_DPORT = 16'd5678;
  localparam [0:0]  D_ACT = 1'd1;
  localparam [12:0] D_CIDX = 13'd7;
  localparam [2:0]  D_PCP = 3'd2;
  localparam [0:0]  D_CFI = 1'd0;
  localparam [11:0] D_VID = 12'd9;

  // KeyE: written normally during the T6 (direction-B) test, to confirm
  // that write still lands correctly once the rejected query is retried.
  localparam [31:0] E_SRC = 32'h1111_0002, E_DST = 32'h2222_0002;
  localparam [7:0]  E_PROTO = 8'h02;
  localparam [15:0] E_SPORT = 16'd11, E_DPORT = 16'd22;
  localparam [0:0]  E_ACT = 1'd1;
  localparam [12:0] E_CIDX = 13'd55;
  localparam [2:0]  E_PCP = 3'd3;
  localparam [0:0]  E_CFI = 1'd1;
  localparam [11:0] E_VID = 12'd66;

  initial begin
    $display("== tb_FiveTuple_table_query_delete_standalone: control-plane query/delete regression ==\n");

    // ────────────────────────────────────────────────────────────────────
    // T1 -- write an entry, query it -> hit, correct action/params.
    // ────────────────────────────────────────────────────────────────────
    $display("══ T1: write + query -> hit ═══════════════════════════════════════");
    do_reset();
    cp_write(A_SRC, A_DST, A_PROTO, A_SPORT, A_DPORT, A_ACT, A_CIDX, A_PCP, A_CFI, A_VID);
    cp_query(A_SRC, A_DST, A_PROTO, A_SPORT, A_DPORT, 0);
    chk("T1: query hit", cp_query_hit);
    chk("T1: query action_id correct", cp_query_action_id === A_ACT);
    chk("T1: query p_counter_index correct", cp_query_p_counter_index === A_CIDX);
    chk("T1: query p_pcp correct", cp_query_p_pcp === A_PCP);
    chk("T1: query p_cfi correct", cp_query_p_cfi === A_CFI);
    chk("T1: query p_vid correct", cp_query_p_vid === A_VID);

    // ────────────────────────────────────────────────────────────────────
    // T2 -- query a never-written key -> miss, results read as 0.
    // ────────────────────────────────────────────────────────────────────
    $display("\n══ T2: query never-written key -> miss, zeroed results ═══════════");
    cp_query(C_SRC, C_DST, C_PROTO, C_SPORT, C_DPORT, 0);
    chk("T2: query miss", !cp_query_hit);
    chk("T2: action_id zeroed on miss", cp_query_action_id === 1'd0);
    chk("T2: p_counter_index zeroed on miss", cp_query_p_counter_index === 13'd0);
    chk("T2: p_pcp zeroed on miss", cp_query_p_pcp === 3'd0);
    chk("T2: p_cfi zeroed on miss", cp_query_p_cfi === 1'd0);
    chk("T2: p_vid zeroed on miss", cp_query_p_vid === 12'd0);

    // ────────────────────────────────────────────────────────────────────
    // T3 -- delete an existing entry (the delete itself must report
    // hit=1, i.e. it found something), then query the same key -> miss.
    // ────────────────────────────────────────────────────────────────────
    $display("\n══ T3: delete existing entry -> hit=1, then query -> miss ════════");
    cp_query(A_SRC, A_DST, A_PROTO, A_SPORT, A_DPORT, 1);  // del=1
    chk("T3: delete reports hit=1 (found the entry)", cp_query_hit);
    chk("T3: delete's own result still shows correct action_id", cp_query_action_id === A_ACT);
    cp_query(A_SRC, A_DST, A_PROTO, A_SPORT, A_DPORT, 0);  // re-query, read-only
    chk("T3: post-delete query -> miss", !cp_query_hit);

    // ────────────────────────────────────────────────────────────────────
    // T4 -- delete a nonexistent key -> hit=0, busy still resolves
    // cleanly, no corruption elsewhere.
    // ────────────────────────────────────────────────────────────────────
    $display("\n══ T4: delete nonexistent key -> hit=0, clean resolution ═════════");
    cp_write(E_SRC, E_DST, E_PROTO, E_SPORT, E_DPORT, E_ACT, E_CIDX, E_PCP, E_CFI, E_VID);
    cp_query(C_SRC, C_DST, C_PROTO, C_SPORT, C_DPORT, 1);  // del=1, never written
    chk("T4: delete of nonexistent key -> hit=0", !cp_query_hit);
    cp_query(E_SRC, E_DST, E_PROTO, E_SPORT, E_DPORT, 0);
    chk("T4: unrelated entry (KeyE) untouched by the failed delete", cp_query_hit && cp_query_action_id === E_ACT);
    cp_query(C_SRC, C_DST, C_PROTO, C_SPORT, C_DPORT, 1);  // delete KeyE-unrelated cleanup not needed
    // (leave state as-is; next test does its own reset)

    // ────────────────────────────────────────────────────────────────────
    // T5 -- busy-gate direction A: pulse cp_wr_en while a query/delete is
    // in flight (cp_query_busy high) -> the write must be dropped, not
    // corrupt anything, no X-propagation.
    // ────────────────────────────────────────────────────────────────────
    $display("\n══ T5: busy-gate A -- write dropped during in-flight query ═══════");
    do_reset();
    cp_write(A_SRC, A_DST, A_PROTO, A_SPORT, A_DPORT, A_ACT, A_CIDX, A_PCP, A_CFI, A_VID);
    // Start a query of KeyA (accept edge), then -- while cp_query_busy is
    // high for its one-cycle resolve window -- pulse a write of KeyD.
    @(negedge clk);
    cp_query_key_src = A_SRC; cp_query_key_dst = A_DST; cp_query_key_protocol = A_PROTO;
    cp_query_key_table_key_sport = A_SPORT; cp_query_key_table_key_dport = A_DPORT;
    cp_query_del = 0;
    cp_query_en = 1;
    @(posedge clk); #1;                 // accept edge: q_pend_valid becomes 1
    cp_query_en = 0;
    chk("T5: cp_query_busy asserted right after accept", cp_query_busy);
    // Same (resolve) window: attempt a write -- must be dropped.
    @(negedge clk);
    cp_wr_key_src = D_SRC; cp_wr_key_dst = D_DST; cp_wr_key_protocol = D_PROTO;
    cp_wr_key_table_key_sport = D_SPORT; cp_wr_key_table_key_dport = D_DPORT;
    cp_wr_action = D_ACT; cp_wr_p_counter_index = D_CIDX;
    cp_wr_p_pcp = D_PCP; cp_wr_p_cfi = D_CFI; cp_wr_p_vid = D_VID;
    cp_wr_en = 1;
    @(posedge clk); #1;                 // resolve edge: query resolves, write dropped here
    cp_wr_en = 0;
    while (cp_query_busy) @(posedge clk);
    #1;
    chk("T5: query itself still resolved correctly (hit KeyA)", cp_query_hit && cp_query_action_id === A_ACT);
    cp_query(D_SRC, D_DST, D_PROTO, D_SPORT, D_DPORT, 0);
    chk("T5: KeyD write was dropped -> query miss", !cp_query_hit);
    cp_query(A_SRC, A_DST, A_PROTO, A_SPORT, A_DPORT, 0);
    chk("T5: KeyA entry undisturbed by the dropped write", cp_query_hit && cp_query_action_id === A_ACT
        && cp_query_p_counter_index === A_CIDX && cp_query_p_pcp === A_PCP
        && cp_query_p_cfi === A_CFI && cp_query_p_vid === A_VID);

    // ────────────────────────────────────────────────────────────────────
    // T6 -- busy-gate direction B: pulse cp_query_en on the same cycle as
    // a plain write's cp_wr_en -> the query must be cleanly rejected at
    // accept (never asserts busy), then succeeds once retried without a
    // concurrent write.
    // ────────────────────────────────────────────────────────────────────
    $display("\n══ T6: busy-gate B -- query rejected during a concurrent write ═══");
    do_reset();
    @(negedge clk);
    cp_wr_key_src = E_SRC; cp_wr_key_dst = E_DST; cp_wr_key_protocol = E_PROTO;
    cp_wr_key_table_key_sport = E_SPORT; cp_wr_key_table_key_dport = E_DPORT;
    cp_wr_action = E_ACT; cp_wr_p_counter_index = E_CIDX;
    cp_wr_p_pcp = E_PCP; cp_wr_p_cfi = E_CFI; cp_wr_p_vid = E_VID;
    cp_wr_en = 1;
    cp_query_key_src = A_SRC; cp_query_key_dst = A_DST; cp_query_key_protocol = A_PROTO;
    cp_query_key_table_key_sport = A_SPORT; cp_query_key_table_key_dport = A_DPORT;
    cp_query_del = 0;
    cp_query_en = 1;                    // asserted the SAME cycle as cp_wr_en
    @(posedge clk); #1;
    cp_wr_en = 0;
    cp_query_en = 0;
    chk("T6: query rejected at accept -> busy never asserts", !cp_query_busy);
    @(posedge clk); #1;
    chk("T6: still not busy one cycle later (nothing pending)", !cp_query_busy);
    cp_query(E_SRC, E_DST, E_PROTO, E_SPORT, E_DPORT, 0);
    chk("T6: concurrent write still landed correctly", cp_query_hit && cp_query_action_id === E_ACT
        && cp_query_p_counter_index === E_CIDX);
    cp_query(A_SRC, A_DST, A_PROTO, A_SPORT, A_DPORT, 0);
    // mem_valid is a BRAM array, only initialized once at time 0 -- it is
    // NOT cleared by do_reset()'s rst_n pulse (matches real hardware: table
    // contents survive a datapath reset). KeyA was re-written during T5, so
    // it is still present here -- this retried query must succeed as a hit.
    chk("T6: retried query (no concurrent write) succeeds -> hit (KeyA persists from T5)",
        cp_query_hit && cp_query_action_id === A_ACT && cp_query_p_counter_index === A_CIDX);

    // ────────────────────────────────────────────────────────────────────
    // T7 -- port-A non-interference: continuous packet lookups on KeyA
    // while KeyA is deleted via the control plane; port A (hit) must only
    // reflect the deletion starting exactly the cycle after it commits --
    // same 2-cycle read-pipeline latency contract writes already have.
    // ────────────────────────────────────────────────────────────────────
    $display("\n══ T7: port-A non-interference around a concurrent delete ════════");
    do_reset();
    cp_write(A_SRC, A_DST, A_PROTO, A_SPORT, A_DPORT, A_ACT, A_CIDX, A_PCP, A_CFI, A_VID);
    lkp_src = A_SRC; lkp_dst = A_DST; lkp_protocol = A_PROTO;
    lkp_table_key_sport = A_SPORT; lkp_table_key_dport = A_DPORT;
    repeat (WAIT_CYCLES) @(posedge clk);
    #1;
    chk("T7: port-A sees KeyA hit before the delete", hit);

    begin
      int commit_cycle, hit_drop_cycle, cyc;
      logic prev_mem_valid, prev_hit;
      logic timed_out;
      cyc = 0;
      commit_cycle = -1;
      hit_drop_cycle = -1;
      timed_out = 1'b0;
      prev_mem_valid = dut.mem_valid[dut.lkp_addr];
      prev_hit = hit;

      // Kick off the delete (accept edge only -- don't block on busy here,
      // we need to keep sampling every cycle through the resolve edge).
      @(negedge clk);
      cp_query_key_src = A_SRC; cp_query_key_dst = A_DST; cp_query_key_protocol = A_PROTO;
      cp_query_key_table_key_sport = A_SPORT; cp_query_key_table_key_dport = A_DPORT;
      cp_query_del = 1;
      cp_query_en = 1;
      @(posedge clk); #1;
      cp_query_en = 0;

      // Sample every subsequent cycle until both mem_valid and hit have
      // dropped, recording the exact cycle each transition happens on.
      while (!timed_out && (hit_drop_cycle < 0 || commit_cycle < 0)) begin
        @(posedge clk); #1;
        cyc = cyc + 1;
        if (commit_cycle < 0 && prev_mem_valid && !dut.mem_valid[dut.lkp_addr])
          commit_cycle = cyc;
        if (hit_drop_cycle < 0 && prev_hit && !hit)
          hit_drop_cycle = cyc;
        prev_mem_valid = dut.mem_valid[dut.lkp_addr];
        prev_hit = hit;
        if (cyc > 20)
          timed_out = 1'b1;
      end
      chk("T7: delete/hit-drop observed within a bounded window", !timed_out);

      chk("T7: mem_valid actually cleared (delete committed)", commit_cycle > 0);
      chk("T7: hit dropped exactly 2 cycles after mem_valid cleared",
          hit_drop_cycle == commit_cycle + 2);
    end

    // ────────────────────────────────────────────────────────────────────
    $display("");
    $display("════════════════════════════════════════════════════════════════");
    $display("  Results: %0d passed, %0d failed  (total %0d)", pass_cnt, fail_cnt, pass_cnt+fail_cnt);
    $display("════════════════════════════════════════════════════════════════");
    if (fail_cnt == 0) $display("  ALL TESTS PASSED");
    else                $display("  FAILURES DETECTED — see [FAIL] lines above");

    $finish;
  end

endmodule
