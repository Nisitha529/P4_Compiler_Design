// de2115_bringup_top.sv -- STEP 1 of the DE2-115 bring-up: is the board alive?
//
// Nothing about the P4 pipeline is in here on purpose. This design answers the
// questions that have to be answered BEFORE any of it means anything:
//
//   is the 50 MHz oscillator real and running?   -> LEDG[8] blinks at 1 Hz.
//                                                   Time it against a watch: a
//                                                   wrong blink rate means the
//                                                   clock is not what the .sdc
//                                                   claims, which would make
//                                                   every later timing result
//                                                   meaningless.
//   does the FPGA drive every LED pin?           -> LEDR walks one lit LED
//                                                   across all 18, LEDG[7:0]
//                                                   counts in binary. A pin
//                                                   that never lights is a
//                                                   dead assignment, not a
//                                                   dead LED.
//   do the 7-segment displays work?              -> HEX7..HEX2 read "DE2115"
//                                                   and HEX1..HEX0 count
//                                                   seconds in hex. A wrong
//                                                   digit, a missing segment
//                                                   or a swapped display is
//                                                   immediately visible
//                                                   because the word is known.
//   do the inputs reach the fabric?              -> KEY and SW each change the
//                                                   display; see the table.
//
// Controls (KEYs are ACTIVE LOW and already hardware-debounced by a Schmitt
// trigger, per user manual 4.2, so they are used directly):
//
//   KEY[0] pressed : synchronous reset -- counters and the walk restart
//   KEY[1] pressed : LEDR mirrors SW[17:0] instead of walking  (tests all 18
//                    switches: flip one, its LED follows)
//   KEY[2] pressed : every LED on, every segment lit  (tests that each output
//                    CAN drive -- a lamp test)
//   KEY[3] pressed : freeze the counters (the heartbeat stops mid-blink)
//
// The design runs straight off CLOCK_50 with no PLL, deliberately: a PLL is
// one more thing that can fail to lock, and step 1 exists to remove variables.
`default_nettype none

module de2115_bringup_top #(
    // Overridden by the testbench so a simulation does not have to run for a
    // real second. Nothing else in the design depends on the value.
    parameter int CLK_HZ       = 50_000_000,
    parameter int HEARTBEAT_HZ = 1,
    parameter int WALK_HZ      = 8
) (
    input  wire        CLOCK_50,
    input  wire [3:0]  KEY,
    input  wire [17:0] SW,
    output wire [17:0] LEDR,
    output wire [8:0]  LEDG,
    output wire [6:0]  HEX0,
    output wire [6:0]  HEX1,
    output wire [6:0]  HEX2,
    output wire [6:0]  HEX3,
    output wire [6:0]  HEX4,
    output wire [6:0]  HEX5,
    output wire [6:0]  HEX6,
    output wire [6:0]  HEX7
);

  // ── Inputs ───────────────────────────────────────────────────────────────
  // KEYs are active low. Named so the polarity is stated once, here, instead
  // of being re-reasoned at every use.
  wire rst      = ~KEY[0];
  wire show_sw  = ~KEY[1];
  wire lamp_test = ~KEY[2];
  wire freeze   = ~KEY[3];

  // Slide switches are NOT debounced in hardware (only the KEYs are), and they
  // cross into this clock domain asynchronously, so they are registered twice
  // before use. Harmless for a human-operated switch; correct anyway.
  logic [17:0] sw_q, sw_qq;
  always_ff @(posedge CLOCK_50) begin
    sw_q  <= SW;
    sw_qq <= sw_q;
  end

  // ── Tick generators ──────────────────────────────────────────────────────
  localparam int HB_DIV   = CLK_HZ / (2 * HEARTBEAT_HZ);   // half period
  localparam int WALK_DIV = CLK_HZ / WALK_HZ;
  localparam int HB_W     = (HB_DIV   <= 1) ? 1 : $clog2(HB_DIV);
  localparam int WALK_W   = (WALK_DIV <= 1) ? 1 : $clog2(WALK_DIV);

  logic [HB_W-1:0]   hb_cnt;
  logic              hb;          // the heartbeat itself
  logic [WALK_W-1:0] walk_cnt;
  logic [4:0]        walk_pos;    // 0..17
  logic [7:0]        sec_cnt;     // seconds, shown on HEX1..HEX0
  logic [7:0]        green_cnt;

  always_ff @(posedge CLOCK_50) begin
    if (rst) begin
      hb_cnt    <= '0;
      hb        <= 1'b0;
      walk_cnt  <= '0;
      walk_pos  <= '0;
      sec_cnt   <= '0;
      green_cnt <= '0;
    end else if (!freeze) begin
      // heartbeat: toggle every half period, and count seconds on the way up
      if (hb_cnt == HB_DIV[HB_W-1:0] - 1) begin
        hb_cnt <= '0;
        hb     <= ~hb;
        if (!hb) begin
          sec_cnt   <= sec_cnt + 8'd1;     // one full period = one second
          green_cnt <= green_cnt + 8'd1;
        end
      end else begin
        hb_cnt <= hb_cnt + 1'b1;
      end
      // the walking light
      if (walk_cnt == WALK_DIV[WALK_W-1:0] - 1) begin
        walk_cnt <= '0;
        walk_pos <= (walk_pos == 5'd17) ? 5'd0 : walk_pos + 5'd1;
      end else begin
        walk_cnt <= walk_cnt + 1'b1;
      end
    end
  end

  // ── LEDs (active HIGH: user manual 4.3, "driving its associated pin to a
  //    high logic level turns the LED on") ──────────────────────────────────
  logic [17:0] ledr_v;
  always_comb begin
    if (lamp_test)     ledr_v = '1;
    else if (show_sw)  ledr_v = sw_qq;
    else               ledr_v = 18'd1 << walk_pos;
  end
  assign LEDR = ledr_v;
  assign LEDG = lamp_test ? '1 : {hb, green_cnt};

  // ── 7-segment: "DE2115" then a seconds counter ───────────────────────────
  // 0xD 0xE 0x2 0x1 0x1 0x5 reads as the board's name on HEX7..HEX2, which is
  // what makes a wrong segment or a swapped digit obvious at a glance.
  wire [3:0] d7 = 4'hD, d6 = 4'hE, d5 = 4'h2;
  wire [3:0] d4 = 4'h1, d3 = 4'h1, d2 = 4'h5;
  wire       blank = 1'b0;

  seg7 u7 (.nibble(lamp_test ? 4'h8 : d7),            .blank(blank), .seg(HEX7));
  seg7 u6 (.nibble(lamp_test ? 4'h8 : d6),            .blank(blank), .seg(HEX6));
  seg7 u5 (.nibble(lamp_test ? 4'h8 : d5),            .blank(blank), .seg(HEX5));
  seg7 u4 (.nibble(lamp_test ? 4'h8 : d4),            .blank(blank), .seg(HEX4));
  seg7 u3 (.nibble(lamp_test ? 4'h8 : d3),            .blank(blank), .seg(HEX3));
  seg7 u2 (.nibble(lamp_test ? 4'h8 : d2),            .blank(blank), .seg(HEX2));
  seg7 u1 (.nibble(lamp_test ? 4'h8 : sec_cnt[7:4]),  .blank(blank), .seg(HEX1));
  seg7 u0 (.nibble(lamp_test ? 4'h8 : sec_cnt[3:0]),  .blank(blank), .seg(HEX0));

  // lamp_test also lights the g segment on every digit via nibble 8, which is
  // the only digit that uses all seven.
endmodule

`default_nettype wire
