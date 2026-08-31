// ============================================================================
// tb_ByteCounter_standalone.sv -- correctness check for the BYTES-type
// Counter extern's real storage/increment/query module (emit_counters.py).
// Companion to tb_PacketCounter_standalone.sv; the only real difference this
// exercises is pkt_byte_len driving the increment DELTA (packet length,
// not a flat +1) -- see that file for the shared rationale on why DEPTH is
// overridden small and why do_count() waits out both RMW cycles.
//
// Compile:
//   iverilog -g2012 -o sim tb_ByteCounter_standalone.sv ../ByteCounter_counter.sv
//   vvp sim
// ============================================================================
`timescale 1ns/1ps

module tb_ByteCounter_standalone;

  localparam CLK_T = 10;
  logic clk = 0;
  always #(CLK_T/2) clk = ~clk;
  logic rst_n;

  localparam int DEPTH = 8;
  localparam int IDX_W = 13;  // real port width, fixed at generation time -- see
                               // tb_PacketCounter_standalone.sv's IDX_W comment

  logic              incr_req;
  logic [IDX_W-1:0]  incr_idx;
  logic              pkt_commit;
  logic              pkt_done;
  logic [15:0]       pkt_byte_len;
  logic              cp_query_en;
  logic [IDX_W-1:0]  cp_query_idx;
  logic              cp_query_busy;
  logic [63:0]       cp_query_byte_value;

  ByteCounter_counter #(.DEPTH(DEPTH)) dut (
    .clk (clk), .rst_n (rst_n),
    .incr_req (incr_req), .incr_idx (incr_idx),
    .pkt_commit (pkt_commit), .pkt_done (pkt_done),
    .pkt_byte_len (pkt_byte_len),
    .cp_query_en (cp_query_en), .cp_query_idx (cp_query_idx),
    .cp_query_busy (cp_query_busy),
    .cp_query_byte_value (cp_query_byte_value)
  );

  int pass_cnt = 0, fail_cnt = 0;
  task automatic chk(input string name, input logic cond);
    if (cond) begin $display("    [PASS] %s", name); pass_cnt++; end
    else      begin $display("    [FAIL] %s", name); fail_cnt++; end
  endtask

  task automatic do_reset;
    rst_n = 0; incr_req = 0; incr_idx = 0;
    pkt_commit = 0; pkt_done = 0; pkt_byte_len = 0;
    cp_query_en = 0; cp_query_idx = 0;
    repeat(5) @(posedge clk); @(negedge clk);
    rst_n = 1; @(posedge clk); #1;
    repeat(DEPTH + 4) @(posedge clk);
    #1;
  endtask

  // Simulates one packet's worth of .count(idx) with a given packet length
  // -- pkt_byte_len is held stable across the whole commit->done window,
  // mirroring how emit_top.py's real accumulator freezes once rx_done
  // latches (i.e. well before pkt_ready_to_clear/pkt_done fires).
  task automatic do_count(input [IDX_W-1:0] idx, input [15:0] byte_len);
    pkt_byte_len = byte_len;
    @(negedge clk);
    incr_req = 1; incr_idx = idx; pkt_commit = 1;
    @(posedge clk); #1;
    incr_req = 0; pkt_commit = 0;
    repeat(2) @(posedge clk);
    @(negedge clk);
    pkt_done = 1;
    @(posedge clk); #1;      // IDLE -> APPLY transition
    pkt_done = 0;
    @(posedge clk); #1;      // APPLY commits byte_mem[idx]
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
    $display("== tb_ByteCounter_standalone: BYTES-type counter regression ==\n");
    do_reset();

    // -- T1: single packet, length drives the increment delta ---------------
    $display("== T1: single packet, byte-length delta ==");
    do_count(13'd1, 16'd64);
    cp_query(13'd1);
    chk("T1: idx=1 reads back 64 after one 64-byte packet", cp_query_byte_value == 64'd64);

    // -- T2: varying packet lengths to the same index sum correctly ---------
    $display("\n== T2: varying lengths accumulate as a real sum ==");
    do_count(13'd1, 16'd128);
    do_count(13'd1, 16'd1500);
    cp_query(13'd1);
    chk("T2: idx=1 reads back 64+128+1500=1692", cp_query_byte_value == 64'd1692);

    // -- T3: independent indices don't cross-contaminate --------------------
    $display("\n== T3: independent indices ==");
    do_count(13'd4, 16'd42);
    cp_query(13'd4);
    chk("T3: idx=4 reads back 42", cp_query_byte_value == 64'd42);
    cp_query(13'd1);
    chk("T3: idx=1 unaffected by idx=4's packet, still 1692", cp_query_byte_value == 64'd1692);

    $display("\n================================================================");
    $display("  Results: %0d passed, %0d failed  (total %0d)", pass_cnt, fail_cnt, pass_cnt+fail_cnt);
    $display("================================================================");
    if (fail_cnt == 0) $display("  ALL TESTS PASSED");
    else                $display("  SOME TESTS FAILED");
    $finish;
  end

endmodule
