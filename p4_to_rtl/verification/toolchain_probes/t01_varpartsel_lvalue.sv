// Variable part-select as an LVALUE inside always_comb, mixed sources per lane
// (the shape the beat assembly had). Expect: legal SV. out = {b1,a1,a0,b0}
module top;
  logic [31:0] out;
  logic [7:0]  a [0:3];
  logic [7:0]  b [0:3];
  logic [1:0]  rot;
  always_comb begin
    out = '0;
    for (int i = 0; i < 4; i++)
      if (i >= rot) out[i*8 +: 8] = a[i - rot];
      else          out[i*8 +: 8] = b[4 - rot + i];
  end
  initial begin
    a[0]=8'hA0; a[1]=8'hA1; a[2]=8'hA2; a[3]=8'hA3;
    b[0]=8'hB0; b[1]=8'hB1; b[2]=8'hB2; b[3]=8'hB3;
    rot = 2'd1;
    #1;
    if (out === 32'hA2A1A0B3) $display("RESULT PASS");
    else $display("RESULT FAIL out=%08h expected A2A1A0B3", out);
    $finish;
  end
endmodule
