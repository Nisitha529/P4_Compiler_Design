// ============================================================================
// tb_PacketCounter_standalone.sv -- correctness check for the PACKETS-type
// Counter extern's real storage/increment/query module (emit_counters.py).
// Standalone (bypasses processing_generated and the AXI4-Lite bus entirely)
// to isolate exactly the new increment-request-latch / registered
// read-modify-write / CP-query pipeline this feature adds -- does not touch
// or replace tb_fiveTuple_top.sv's cycle-exact datapath regression, which
// already re-confirms this module's END-TO-END wiring is undisturbed.
//
// DEPTH is overridden small (8, not the real app's 8192) purely to keep the
// power-on clear FSM's DEPTH-cycle walk fast in simulation -- the clear
// FSM's own correctness isn't otherwise app-specific.
//
// Compile:
//   iverilog -g2012 -o sim tb_PacketCounter_standalone.sv ../PacketCounter_counter.sv
//   vvp sim
// ============================================================================
`timescale 1ns/1ps

module tb_PacketCounter_standalone;

  localparam CLK_T = 10;
  logic clk = 0;
  always #(CLK_T/2) clk = ~clk;
  logic rst_n;

  localparam int DEPTH = 8;
  // The DUT's real incr_idx/cp_query_idx port width is fixed at generation
  // time from the app's actual counter size (8192 -> 13 bits) and does NOT
  // shrink just because DEPTH is overridden smaller here for simulation
  // speed -- so these signals must match that real width, even though only
  // values 0..DEPTH-1 are ever driven.
  localparam int IDX_W = 13;

  logic              incr_req;
  logic [IDX_W-1:0]  incr_idx;
  logic              incr_fire;
  logic              cp_query_en;
  logic [IDX_W-1:0]  cp_query_idx;
  logic              cp_query_busy;
  logic [63:0]       cp_query_pkt_value;

  PacketCounter_counter #(.DEPTH(DEPTH)) dut (
    .clk (clk), .rst_n (rst_n),
    .incr_req (incr_req), .incr_idx (incr_idx),
    .incr_fire (incr_fire),
    .cp_query_en (cp_query_en), .cp_query_idx (cp_query_idx),
    .cp_query_busy (cp_query_busy),
    .cp_query_pkt_value (cp_query_pkt_value)
  );

  int pass_cnt = 0, fail_cnt = 0;
  task automatic chk(input string name, input logic cond);
    if (cond) begin $display("    [PASS] %s", name); pass_cnt++; end
    else      begin $display("    [FAIL] %s", name); fail_cnt++; end
  endtask

  task automatic do_reset;
    rst_n = 0; incr_req = 0; incr_idx = 0;
    incr_fire = 0;
    cp_query_en = 0; cp_query_idx = 0;
    repeat(5) @(posedge clk); @(negedge clk);
    rst_n = 1; @(posedge clk); #1;
    // Wait out the power-on clear FSM (DEPTH cycles) before any real traffic.
    repeat(DEPTH + 4) @(posedge clk);
    #1;
  endtask

  // One request per packet: everything valid on the incr_fire cycle. The
  // pipelined RMW issues the read on that edge (stage A) and writes on the
  // next (stage B), so the value is applied two edges after the request.
  task automatic do_count(input [IDX_W-1:0] idx);
    @(negedge clk);
    incr_req = 1; incr_idx = idx; incr_fire = 1;
    @(posedge clk); #1;      // stage A: read issued
    incr_req = 0; incr_fire = 0;
    @(posedge clk); #1;      // stage B: pkt_mem[idx] written on this edge
  endtask

  task automatic cp_query(input [IDX_W-1:0] idx);
    @(negedge clk);
    cp_query_idx = idx;
    cp_query_en = 1;
    @(posedge clk); #1;
    cp_query_en = 0;
    while (cp_query_busy) @(posedge clk);
    #1;
  endtask

  initial begin
    $display("== tb_PacketCounter_standalone: PACKETS-type counter regression ==\n");
    do_reset();

    // -- T1: single increment, then query -----------------------------------
    $display("== T1: single increment ==");
    do_count(3'd2);
    cp_query(3'd2);
    chk("T1: idx=2 reads back 1 after one count()", cp_query_pkt_value == 64'd1);

    // -- T2: repeated increments to the same index accumulate ---------------
    $display("\n== T2: repeated increments accumulate ==");
    do_count(3'd2);
    do_count(3'd2);
    do_count(3'd2);
    cp_query(3'd2);
    chk("T2: idx=2 reads back 4 after 4 total count()s", cp_query_pkt_value == 64'd4);

    // -- T3: different indices don't cross-contaminate -----------------------
    $display("\n== T3: independent indices ==");
    do_count(3'd5);
    do_count(3'd5);
    cp_query(3'd5);
    chk("T3: idx=5 reads back 2", cp_query_pkt_value == 64'd2);
    cp_query(3'd2);
    chk("T3: idx=2 unaffected by idx=5's increments, still 4", cp_query_pkt_value == 64'd4);
    cp_query(3'd0);
    chk("T3: never-incremented idx=0 reads back 0", cp_query_pkt_value == 64'd0);

    // -- T4: query-vs-increment same-cycle collision -------------------------
    // Issue a query for the same index on the EXACT edge stage B writes
    // pkt_mem[idx] <= new value. Documented, accepted behavior (same class
    // as exact-match tables' own CP-query-vs-write collision window): the
    // query's registered read is a non-blocking sample of the SAME cycle's
    // pre-write memory content, so it reads the PRE-increment value.
    $display("\n== T4: query/increment same-cycle collision ==");
    begin
      @(negedge clk);
      incr_req = 1; incr_idx = 3'd6; incr_fire = 1;
      @(posedge clk); #1;      // stage A: read issued
      incr_req = 0; incr_fire = 0;
      // The NEXT edge is when stage B writes pkt_mem[6] -- issue the query
      // so its own accept-and-read lands on that same edge.
      @(negedge clk);
      cp_query_idx = 3'd6;
      cp_query_en = 1;
      @(posedge clk); #1;      // collision edge: stage B writes AND query reads
      cp_query_en = 0;
      while (cp_query_busy) @(posedge clk);
      #1;
      chk("T4: same-cycle query reads pre-increment value (0)", cp_query_pkt_value == 64'd0);
    end
    cp_query(3'd6);
    chk("T4: a later query correctly sees the applied increment (1)", cp_query_pkt_value == 64'd1);


    // Consecutive-cycle requests. Same index twice in a row exercises the
    // stage-B -> stage-A bypass (the old 2-cycle FSM lost one of these);
    // then a different index right behind them checks the bypass is
    // index-qualified and doesn't leak the wrong value across.
    $display("\n== T5: back-to-back requests (bypass) ==");
    begin
      @(negedge clk);
      incr_req = 1; incr_fire = 1; incr_idx = 3'd2;   // cycle 1: idx 2
      @(posedge clk); #1;
      incr_idx = 3'd2;                                  // cycle 2: idx 2 again
      @(posedge clk); #1;
      incr_idx = 3'd2;                                  // cycle 3: idx 2 again
      @(posedge clk); #1;
      incr_idx = 3'd5;                                  // cycle 4: idx 5
      @(posedge clk); #1;
      incr_req = 0; incr_fire = 0;
      repeat (3) @(posedge clk); #1;
    end
    cp_query(3'd2);
    chk("T5: idx 2 = 4 + three back-to-back hits", cp_query_pkt_value == 64'd7);
    cp_query(3'd5);
    chk("T5: idx 5 = 2 + exactly one (no bypass leak)", cp_query_pkt_value == 64'd3);
    cp_query(3'd6);
    chk("T5: idx 6 untouched by the burst", cp_query_pkt_value == 64'd1);

    $display("\n================================================================");
    $display("  Results: %0d passed, %0d failed  (total %0d)", pass_cnt, fail_cnt, pass_cnt+fail_cnt);
    $display("================================================================");
    if (fail_cnt == 0) $display("  ALL TESTS PASSED");
    else                $display("  SOME TESTS FAILED");
    $finish;
  end

endmodule
