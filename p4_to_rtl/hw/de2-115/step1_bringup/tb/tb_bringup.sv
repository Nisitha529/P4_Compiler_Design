// tb_bringup.sv -- checks step 1 in simulation, so the first time it runs on
// the board you are testing the BOARD and not the design.
//
// CLK_HZ is overridden to 1000 so a "second" is 1000 cycles: the heartbeat
// divider is the one thing that cannot be checked at full scale in a
// reasonable simulation, and it is also the thing whose value you will judge
// by eye against a watch.
`timescale 1ns/1ps

module tb_bringup;

  localparam int CLK_HZ = 1000;      // pretend 1 kHz
  localparam int HB_HZ  = 1;         // -> 500-cycle half period
  localparam int WK_HZ  = 100;       // -> walk step every 10 cycles

  logic clk = 0;
  always #5 clk = ~clk;              // 100 MHz in sim time; the RATIO is what matters

  logic [3:0]  KEY = 4'hF;           // all released (active low)
  logic [17:0] SW  = '0;
  wire  [17:0] LEDR;
  wire  [8:0]  LEDG;
  wire  [6:0]  HEX0, HEX1, HEX2, HEX3, HEX4, HEX5, HEX6, HEX7;

  de2115_bringup_top #(.CLK_HZ(CLK_HZ), .HEARTBEAT_HZ(HB_HZ), .WALK_HZ(WK_HZ)) dut (
    .CLOCK_50(clk), .KEY(KEY), .SW(SW), .LEDR(LEDR), .LEDG(LEDG),
    .HEX0(HEX0), .HEX1(HEX1), .HEX2(HEX2), .HEX3(HEX3),
    .HEX4(HEX4), .HEX5(HEX5), .HEX6(HEX6), .HEX7(HEX7)
  );

  int pass_cnt = 0, fail_cnt = 0;
  task automatic chk(input string name, input logic cond);
    if (cond) begin $display("    [PASS] %s", name); pass_cnt++; end
    else      begin $display("    [FAIL] %s", name); fail_cnt++; end
  endtask

  // The seven-segment patterns the design must produce, derived here
  // INDEPENDENTLY of seg7.sv -- a testbench that imported the same table
  // would agree with a wrong table.
  function automatic [6:0] expect_seg(input [3:0] n);
    case (n)
      4'h0: expect_seg = ~7'b0111111;
      4'h1: expect_seg = ~7'b0000110;
      4'h2: expect_seg = ~7'b1011011;
      4'h5: expect_seg = ~7'b1101101;
      4'h8: expect_seg = ~7'b1111111;
      4'hD: expect_seg = ~7'b1011110;
      4'hE: expect_seg = ~7'b1111001;
      default: expect_seg = 7'h7F;
    endcase
  endfunction

  int    hb_edges;
  time   t0, t1;
  logic  hb_prev;
  int    lit;
  int    seen_mask;
  int    multi_lit;

  task automatic press(input int k, input int cycles);
    KEY[k] = 1'b0; repeat (cycles) @(posedge clk); KEY[k] = 1'b1;
    repeat (2) @(posedge clk);
  endtask

  initial begin
    $display("\n================================================================");
    $display("  tb_bringup: DE2-115 step 1 (board alive)");
    $display("================================================================");
    press(0, 10);                    // reset

    // ── the display reads DE2115 ────────────────────────────────────────────
    $display("\n== the fixed digits spell the board name ==");
    repeat (5) @(posedge clk);
    chk("HEX7 = D", HEX7 === expect_seg(4'hD));
    chk("HEX6 = E", HEX6 === expect_seg(4'hE));
    chk("HEX5 = 2", HEX5 === expect_seg(4'h2));
    chk("HEX4 = 1", HEX4 === expect_seg(4'h1));
    chk("HEX3 = 1", HEX3 === expect_seg(4'h1));
    chk("HEX2 = 5", HEX2 === expect_seg(4'h5));
    chk("every segment is driven (no X)", ^{HEX7,HEX6,HEX5,HEX4,HEX3,HEX2,HEX1,HEX0} !== 1'bx);

    // ── the heartbeat period is what the parameters say ─────────────────────
    // This is the check that matters most: if the divider is wrong, the board
    // will blink at the wrong rate and every conclusion drawn from "the clock
    // looks right" is wrong too.
    $display("\n== the heartbeat period matches CLK_HZ/HEARTBEAT_HZ ==");
    hb_prev = LEDG[8];
    while (LEDG[8] === hb_prev) @(posedge clk);
    t0 = $time; hb_prev = LEDG[8];
    while (LEDG[8] === hb_prev) @(posedge clk);
    t1 = $time;
    $display("      half period measured = %0t, expected %0d cycles",
             t1 - t0, CLK_HZ / (2 * HB_HZ));
    chk("half period is CLK_HZ/(2*HEARTBEAT_HZ) cycles",
        (t1 - t0) == (CLK_HZ / (2 * HB_HZ)) * 10);   // 10ns per cycle

    // ── the walk visits all 18 LEDs, one at a time ──────────────────────────
    $display("\n== the walking light reaches all 18 LEDR pins, one at a time ==");
    // A flag, not a `break`: iverilog 11 does not support break statements
    // (the same limitation the generated testbenches work around).
    seen_mask = 0;
    multi_lit = 0;
    for (int i = 0; i < 18 * (CLK_HZ / WK_HZ) + 40; i++) begin
      @(posedge clk);
      lit = 0;
      for (int b = 0; b < 18; b++) if (LEDR[b]) lit++;
      if (lit != 1) multi_lit = multi_lit + 1;
      seen_mask = seen_mask | int'(LEDR);
    end
    chk("exactly one LEDR lit at every step of the walk", multi_lit == 0);
    $display("      LEDR pins exercised = %05h (want 3ffff)", seen_mask);
    chk("all 18 LEDR pins were lit at some point", seen_mask == 18'h3ffff);

    // ── the switches reach the fabric ───────────────────────────────────────
    $display("\n== KEY[1] mirrors all 18 switches onto LEDR ==");
    SW = 18'h25A5A;
    KEY[1] = 1'b0;
    repeat (6) @(posedge clk);
    chk("LEDR follows SW while KEY[1] is held", LEDR === 18'h25A5A);
    SW = 18'h1FFFF;
    repeat (4) @(posedge clk);
    chk("...and follows a change", LEDR === 18'h1FFFF);
    KEY[1] = 1'b1;

    // ── the lamp test drives every output ───────────────────────────────────
    $display("\n== KEY[2] is a lamp test: every LED on, every segment lit ==");
    KEY[2] = 1'b0;
    repeat (4) @(posedge clk);
    chk("all 18 red LEDs on",   LEDR === 18'h3FFFF);
    chk("all 9 green LEDs on",  LEDG === 9'h1FF);
    chk("HEX0 shows 8 (all seven segments)", HEX0 === expect_seg(4'h8));
    chk("HEX7 shows 8 (all seven segments)", HEX7 === expect_seg(4'h8));
    KEY[2] = 1'b1;
    repeat (4) @(posedge clk);

    // ── freeze ──────────────────────────────────────────────────────────────
    $display("\n== KEY[3] freezes the counters ==");
    KEY[3] = 1'b0;
    repeat (4) @(posedge clk);
    begin
      logic [17:0] before_ledr;
      logic        before_hb;
      before_ledr = LEDR; before_hb = LEDG[8];
      repeat (CLK_HZ) @(posedge clk);          // a whole "second"
      chk("the walk stopped",      LEDR === before_ledr);
      chk("the heartbeat stopped", LEDG[8] === before_hb);
    end
    KEY[3] = 1'b1;

    $display("\n================================================================");
    $display("  Results: %0d passed, %0d failed  (total %0d)", pass_cnt, fail_cnt, pass_cnt+fail_cnt);
    $display("================================================================");
    if (fail_cnt == 0) $display("  ALL TESTS PASSED");
    else                $display("  SOME TESTS FAILED");
    $finish;
  end

  initial begin #5000000; $display("[TIMEOUT]"); $finish; end

endmodule
