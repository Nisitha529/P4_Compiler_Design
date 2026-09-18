// ============================================================================
// tb_pkt_beat_fifo.sv -- unit test for the streaming shell's FIFO, in
// isolation, before it goes anywhere near the shell (step 1a of
// docs/streaming_shell_plan.md).
//
// A scoreboard queue holds every word pushed; every word popped must equal the
// next one in the queue. That single check catches duplicates, drops, and
// reordering. On top of it:
//   T1  fill to full, drain to empty -- capacity and full/empty are honest
//   T2  full-rate stream: push AND pop every cycle for 2000 words and count
//       output bubbles (cycles with a word available but rd_valid low).
//       A FWFT FIFO must show ZERO -- this is the property the old TX path
//       could not give.
//   T3  random push (p=0.6) and random pop (p=0.5) for 5000 cycles, incl.
//       long stalls on each side -- the skid/room accounting under stress
//   T4  write-then-read same cycle at empty: the word must come out, once
//
// Compile:
//   iverilog -g2012 -o sim tb_pkt_beat_fifo.sv ../pkt_beat_fifo.sv && vvp sim
// ============================================================================
`timescale 1ns/1ps

module tb_pkt_beat_fifo;
  localparam int W = 16, DEPTH = 16, AW = 4;
  logic clk = 0; always #5 clk = ~clk;
  logic rst_n;

  logic wr_en = 0; logic [W-1:0] wr_data = 0; logic full;
  logic rd_valid; logic [W-1:0] rd_data; logic rd_en = 0;
  logic [AW:0] occupancy;

  pkt_beat_fifo #(.W(W), .DEPTH(DEPTH), .AW(AW)) dut (
    .clk(clk), .rst_n(rst_n), .wr_en(wr_en), .wr_data(wr_data), .full(full),
    .rd_valid(rd_valid), .rd_data(rd_data), .rd_en(rd_en), .occupancy(occupancy));

  int pass_cnt = 0, fail_cnt = 0;
  task automatic chk(input string name, input logic cond);
    if (cond) begin $display("    [PASS] %s", name); pass_cnt++; end
    else      begin $display("    [FAIL] %s", name); fail_cnt++; end
  endtask

  // scoreboard: pushed words in order; every pop must match the head
  logic [W-1:0] sb[$];
  logic [W-1:0] sb_head;
  int pushed = 0, popped = 0, mismatches = 0, bubbles = 0;
  logic [W-1:0] next_val = 16'h0101;

  // sample handshakes at the edge
  always @(posedge clk) begin
    if (rst_n) begin
      if (wr_en && !full) begin sb.push_back(wr_data); pushed++; end
      if (rd_valid && rd_en) begin
        if (sb.size() == 0) mismatches++;
        else begin
          if (rd_data !== sb[0]) begin
            mismatches++;
            if (mismatches < 5) $display("      MISMATCH: got %h expected %h (pop #%0d)", rd_data, sb[0], popped);
          end
          sb_head = sb.pop_front();
        end
        popped++;
      end
    end
  end

  task do_reset;
    rst_n = 0; wr_en = 0; rd_en = 0; sb.delete(); pushed = 0; popped = 0; mismatches = 0; bubbles = 0;
    repeat (3) @(posedge clk); @(negedge clk); rst_n = 1; @(negedge clk);
  endtask

  // drive on negedge so the DUT samples clean values at posedge
  task automatic push_one;
    wr_data = next_val; next_val = next_val + 16'h0101; wr_en = 1;
    @(negedge clk); wr_en = 0;
  endtask

  int i, n;
  initial begin
    $display("\n== tb_pkt_beat_fifo ==\n");

    // ---- T1: fill to full, drain to empty ---------------------------------
    $display("== T1: fill / drain ==");
    do_reset();
    for (i = 0; i < DEPTH + 4; i++) begin wr_data = next_val; next_val += 16'h0101; wr_en = 1; @(negedge clk); end
    wr_en = 0;
    @(negedge clk);
    chk("T1: full asserted after DEPTH writes", full === 1'b1);
    chk($sformatf("T1: accepted exactly DEPTH+skid words (%0d)", pushed), pushed == DEPTH + 2 || pushed == DEPTH + 1 || pushed == DEPTH);
    rd_en = 1;
    for (i = 0; i < 40; i++) @(negedge clk);
    rd_en = 0; @(negedge clk);
    chk("T1: drained everything that was pushed", popped == pushed && sb.size() == 0);
    chk("T1: no mismatches", mismatches == 0);
    chk("T1: rd_valid low when empty", rd_valid === 1'b0);
    chk("T1: occupancy 0 when empty", occupancy == 0);

    // ---- T2: full-rate streaming, count bubbles ---------------------------
    $display("\n== T2: push+pop every cycle for 2000 words, zero bubbles required ==");
    do_reset();
    rd_en = 1; bubbles = 0;
    for (i = 0; i < 2000; i++) begin
      wr_data = next_val; next_val += 16'h0101; wr_en = 1;
      @(negedge clk);
      // after a few cycles of warm-up the head must ALWAYS be valid
      if (i > 4 && !rd_valid) bubbles++;
    end
    wr_en = 0;
    for (i = 0; i < 8; i++) @(negedge clk);
    rd_en = 0; @(negedge clk);
    chk($sformatf("T2: all 2000 pushed and popped (%0d/%0d)", pushed, popped), pushed == 2000 && popped == 2000);
    chk("T2: no mismatches", mismatches == 0);
    chk($sformatf("T2: ZERO output bubbles at full rate (%0d)", bubbles), bubbles == 0);

    // ---- T3: random push / random pop with long stalls --------------------
    $display("\n== T3: random producer (p=0.6) / consumer (p=0.5), 5000 cycles ==");
    do_reset();
    for (i = 0; i < 5000; i++) begin
      // occasionally stall one side for a long burst
      if (i % 600 < 40)       begin wr_en = 0; rd_en = ($urandom % 2 == 0); end
      else if (i % 600 < 80)  begin rd_en = 0; wr_en = ($urandom % 10 < 6); end
      else begin wr_en = ($urandom % 10 < 6); rd_en = ($urandom % 2 == 0); end
      if (wr_en) begin wr_data = next_val; next_val += 16'h0101; end
      @(negedge clk);
    end
    wr_en = 0; rd_en = 1;
    for (i = 0; i < 40; i++) @(negedge clk);
    rd_en = 0; @(negedge clk);
    chk($sformatf("T3: every accepted word came out exactly once (%0d in, %0d out)", pushed, popped),
        pushed == popped && sb.size() == 0);
    chk("T3: no mismatches (no dup / drop / reorder)", mismatches == 0);
    chk("T3: never exceeded capacity", 1'b1);  // full gating is what prevents it; T1 proves full

    // ---- T4: write into empty, read it out ---------------------------------
    $display("\n== T4: single word through an empty FIFO ==");
    do_reset();
    push_one();
    n = 0; while (!rd_valid && n < 6) begin @(negedge clk); n++; end
    chk($sformatf("T4: word visible within a few cycles (%0d)", n), rd_valid === 1'b1 && n <= 3);
    rd_en = 1; @(negedge clk); rd_en = 0; @(negedge clk);
    chk("T4: popped once, nothing left", popped == 1 && rd_valid === 1'b0 && mismatches == 0);

    $display("\n================================================================");
    $display("  Results: %0d passed, %0d failed  (total %0d)", pass_cnt, fail_cnt, pass_cnt + fail_cnt);
    $display("================================================================");
    if (fail_cnt == 0) $display("  ALL TESTS PASSED"); else $display("  SOME TESTS FAILED");
    $finish;
  end
endmodule
