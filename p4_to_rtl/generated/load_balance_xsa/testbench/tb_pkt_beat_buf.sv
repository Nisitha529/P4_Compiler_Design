// ============================================================================
// tb_pkt_beat_buf.sv -- unit test for the streaming shell's per-slot payload
// buffer, in isolation.
//
// This module used to be a first-word-fall-through FIFO (streaming shell step
// 1). Traffic-manager step 5 needed the payload to be RE-READABLE, because a
// FIFO's first reader consumes it and a replicated packet has more than one:
// the second multicast copy found an empty buffer, TX never finished it and
// the slot never released. So reads now advance a read pointer without
// destroying anything, `rewind` restarts at the first beat, and only `clear`
// empties the buffer.
//
// The scoreboard is the whole test: every beat written is remembered, and every
// beat read must equal the next one expected. That one check catches drops,
// duplicates and reordering.
//
//   T1  fill to full: `full` is honest, and reads do NOT free space
//   T2  read the whole packet back in order, with ZERO bubbles -- the
//       fall-through property the TX path is written against
//   T3  REWIND: read it all again and get byte-identical beats. This is what
//       a FIFO cannot do and multicast replication needs.
//   T4  rewind part-way through a read, not just at the end
//   T5  CLEAR: the buffer is empty afterwards and reusable for a new packet
//   T6  random read stalls over a filled buffer -- skid/room accounting
//   T7  write-then-read in the same cycle at empty: the beat comes out once
//
// Compile:
//   iverilog -g2012 -o sim tb_pkt_beat_buf.sv ../pkt_beat_buf.sv && vvp sim
// ============================================================================
`timescale 1ns/1ps

module tb_pkt_beat_buf;
  localparam int W = 16, DEPTH = 16, AW = 4;
  logic clk = 0; always #5 clk = ~clk;
  logic rst_n;

  logic wr_en = 0; logic [W-1:0] wr_data = 0; logic full;
  logic rd_valid; logic [W-1:0] rd_data; logic rd_en = 0;
  logic rewind_i = 0, clear_i = 0;
  logic [AW:0] occupancy;

  pkt_beat_buf #(.W(W), .DEPTH(DEPTH), .AW(AW)) dut (
    .clk(clk), .rst_n(rst_n),
    .wr_en(wr_en), .wr_data(wr_data), .full(full),
    .rd_valid(rd_valid), .rd_data(rd_data), .rd_en(rd_en),
    .rewind(rewind_i), .clear(clear_i), .occupancy(occupancy));

  int pass_cnt = 0, fail_cnt = 0;
  task automatic chk(input string name, input logic cond);
    if (cond) begin $display("    [PASS] %s", name); pass_cnt++; end
    else      begin $display("    [FAIL] %s", name); fail_cnt++; end
  endtask

  logic [W-1:0] stored [$];   // every beat the packet has, in order
  logic [W-1:0] got    [$];   // beats read out on the current pass
  int pushed, mismatches, bubbles, startup;

  task automatic do_reset;
    rst_n = 0; wr_en = 0; rd_en = 0; rewind_i = 0; clear_i = 0;
    repeat (4) @(posedge clk); @(negedge clk); rst_n = 1; @(posedge clk); #1;
  endtask

  // Write until `full`, remembering everything accepted.
  task automatic fill;
    stored.delete(); pushed = 0;
    // iverilog 11 has no `break`, so the bound lives in the loop condition.
    while (!full && pushed <= DEPTH + 4) begin
      @(negedge clk);
      wr_en = 1'b1; wr_data = W'(16'hA000 + pushed);
      @(posedge clk); #1;
      stored.push_back(W'(16'hA000 + pushed)); pushed++;
    end
    @(negedge clk); wr_en = 1'b0;
  endtask

  // Read `n` beats, counting cycles where nothing was available.
  // FWFT consumer pattern: rd_data is the head NOW, so it is sampled before
  // the edge that pops it. Sampling after the edge records the next head and
  // shifts everything by one.
  task automatic read_pass(input int n, input bit count_bubbles = 0);
    int taken;
    got.delete(); bubbles = 0; startup = 0; taken = 0;
    while (taken < n && (bubbles + startup) <= 200) begin
      @(negedge clk);
      if (rd_valid) begin
        got.push_back(rd_data);
        rd_en = 1'b1;
        taken++;
      end else begin
        rd_en = 1'b0;
        // Cycles before the FIRST beat are startup -- after a pointer reset
        // the skid is empty and the RAM read is registered, so the first beat
        // takes a couple of cycles. Cycles after it are real bubbles, and
        // those are what would cost line rate.
        if (taken == 0) startup++; else bubbles++;
      end
      @(posedge clk); #1;
    end
    @(negedge clk); rd_en = 1'b0;
  endtask

  function automatic int compare(input int n);
    int bad;
    bad = 0;
    if (got.size() < n) return 999;
    for (int i = 0; i < n; i++) if (got[i] !== stored[i]) bad++;
    return bad;
  endfunction

  int i, n;

  initial begin
    $display("\n== tb_pkt_beat_buf: re-readable per-slot payload buffer ==\n");
    do_reset();

    // ---- T1 ---------------------------------------------------------------
    $display("== T1: fill to full; reads do not free space ==");
    fill();
    chk($sformatf("T1: full asserted after %0d writes", pushed), full === 1'b1);
    chk("T1: occupancy == beats stored", occupancy == pushed);
    read_pass(4);
    chk("T1: still full after reading 4 beats -- reads are not destructive",
        full === 1'b1 && occupancy == pushed);

    // ---- T2 ---------------------------------------------------------------
    $display("\n== T2: read the whole packet in order, no bubbles ==");
    rewind_i = 1'b1; @(posedge clk); #1; rewind_i = 1'b0; @(posedge clk); #1;
    read_pass(pushed, 1);
    chk($sformatf("T2: read all %0d beats", pushed), got.size() == pushed);
    chk("T2: in order, no drops or duplicates", compare(pushed) == 0);
    chk($sformatf("T2: ZERO bubbles once streaming (%0d), startup %0d", bubbles, startup),
        bubbles == 0 && startup <= 2);

    // ---- T3 ---------------------------------------------------------------
    $display("\n== T3: rewind and read again -- identical beats ==");
    chk("T3: buffer is dry at the end of a pass", rd_valid === 1'b0);
    @(negedge clk); rewind_i = 1'b1; @(posedge clk); #1; rewind_i = 1'b0;
    read_pass(pushed, 1);
    chk($sformatf("T3: second pass produced all %0d beats again", pushed), got.size() == pushed);
    chk("T3: byte-identical to the first pass", compare(pushed) == 0);
    // A rewind flushes the skid and the RAM read is registered, so the first
    // beat of a new pass costs exactly one cycle. Every beat after it is
    // back-to-back, which is what matters for line rate.
    chk($sformatf("T3: re-read streams with no bubbles (%0d), startup %0d", bubbles, startup),
        bubbles == 0 && startup <= 2);

    // ---- T4 ---------------------------------------------------------------
    $display("\n== T4: rewind part-way through a pass ==");
    @(negedge clk); rewind_i = 1'b1; @(posedge clk); #1; rewind_i = 1'b0;
    read_pass(5);
    chk("T4: partial pass read 5 beats", got.size() == 5 && compare(5) == 0);
    @(negedge clk); rewind_i = 1'b1; @(posedge clk); #1; rewind_i = 1'b0;
    read_pass(pushed);
    chk("T4: rewinding mid-pass restarts at beat 0", got.size() == pushed && compare(pushed) == 0);

    // ---- T5 ---------------------------------------------------------------
    $display("\n== T5: clear empties it and it is reusable ==");
    @(negedge clk); clear_i = 1'b1; @(posedge clk); #1; clear_i = 1'b0; @(posedge clk); #1;
    chk("T5: empty after clear", rd_valid === 1'b0 && occupancy == 0 && full === 1'b0);
    fill();
    chk($sformatf("T5: a new packet fills it again (%0d beats)", pushed), full === 1'b1);
    read_pass(pushed, 1);
    chk("T5: the new packet reads back correctly", compare(pushed) == 0);
    chk($sformatf("T5: no bubbles after clear+refill (%0d), startup %0d", bubbles, startup),
        bubbles == 0 && startup <= 2);

    // ---- T6 ---------------------------------------------------------------
    $display("\n== T6: random read stalls over a filled buffer ==");
    @(negedge clk); rewind_i = 1'b1; @(posedge clk); #1; rewind_i = 1'b0;
    got.delete(); mismatches = 0; i = 0; n = 0;
    while (i < pushed && n < 2000) begin
      @(negedge clk);
      rd_en = ($urandom_range(0, 99) < 55);
      @(posedge clk); #1;
      if (rd_en && rd_valid) begin
        if (rd_data !== stored[i]) mismatches++;
        i++;
      end
      n++;
    end
    @(negedge clk); rd_en = 1'b0;
    chk($sformatf("T6: every beat came out exactly once under stalls (%0d)", i), i == pushed);
    chk("T6: no mismatches", mismatches == 0);

    // ---- T7 ---------------------------------------------------------------
    $display("\n== T7: write and read in the same cycle at empty ==");
    @(negedge clk); clear_i = 1'b1; @(posedge clk); #1; clear_i = 1'b0;
    @(negedge clk); wr_en = 1'b1; wr_data = 16'h5A5A; rd_en = 1'b1;
    @(posedge clk); #1; wr_en = 1'b0;
    n = 0;
    while (!rd_valid && n < 6) begin @(posedge clk); #1; n++; end
    chk($sformatf("T7: the beat appeared within %0d cycles", n), rd_valid === 1'b1);
    chk("T7: it is the beat that was written", rd_data === 16'h5A5A);
    @(posedge clk); #1; @(negedge clk); rd_en = 1'b0;
    chk("T7: nothing left afterwards", rd_valid === 1'b0);

    $display("\n================================================================");
    $display("  Results: %0d passed, %0d failed  (total %0d)", pass_cnt, fail_cnt, pass_cnt+fail_cnt);
    $display("================================================================");
    if (fail_cnt == 0) $display("  ALL TESTS PASSED");
    else                $display("  SOME TESTS FAILED");
    $finish;
  end

endmodule
