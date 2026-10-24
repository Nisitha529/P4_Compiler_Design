// seg7.sv -- one hex digit on one DE2-115 7-segment display.
//
// ACTIVE LOW. The DE2-115's displays are common anode (user manual 4.4,
// "the seven segments (common anode) are connected to pins on Cyclone IV E"),
// so a segment lights when the FPGA drives its pin LOW. Getting this backwards
// gives a display that is lit everywhere except the digit, which is a
// recognisable symptom worth knowing.
//
// Segment index follows the manual's Figure 4-9: 0=a (top), 1=b (upper right),
// 2=c (lower right), 3=d (bottom), 4=e (lower left), 5=f (upper left), 6=g
// (middle).
`default_nettype none

module seg7 (
    input  wire [3:0] nibble,
    input  wire       blank,     // 1 = display nothing (all segments off)
    output wire [6:0] seg        // active low, straight to a HEXn port
);
  logic [6:0] on;               // active HIGH here, inverted on the way out
  always_comb begin
    unique case (nibble)
      4'h0: on = 7'b0111111;
      4'h1: on = 7'b0000110;
      4'h2: on = 7'b1011011;
      4'h3: on = 7'b1001111;
      4'h4: on = 7'b1100110;
      4'h5: on = 7'b1101101;
      4'h6: on = 7'b1111101;
      4'h7: on = 7'b0000111;
      4'h8: on = 7'b1111111;
      4'h9: on = 7'b1101111;
      4'hA: on = 7'b1110111;
      4'hB: on = 7'b1111100;
      4'hC: on = 7'b0111001;
      4'hD: on = 7'b1011110;
      4'hE: on = 7'b1111001;
      4'hF: on = 7'b1110001;
      default: on = 7'b0000000;
    endcase
  end
  assign seg = blank ? 7'h7F : ~on;
endmodule

`default_nettype wire
