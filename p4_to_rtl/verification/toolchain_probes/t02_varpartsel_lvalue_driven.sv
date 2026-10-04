// t01, but both source arrays are driven by always_comb -- the real beat
// assembly's situation. emit_top.py unrolls the lanes to avoid this.
module top;
  logic [7:0]  seed;
  logic [7:0]  a [0:3];
  logic [7:0]  b [0:3];
  logic [1:0]  rot;
  logic [31:0] out;
  always_comb for (int i = 0; i < 4; i++) a[i] = seed + i;
  always_comb for (int i = 0; i < 4; i++) b[i] = seed + 8'h10 + i;
  always_comb begin
    out = '0;
    for (int i = 0; i < 4; i++)
      if (i >= rot) out[i*8 +: 8] = a[i - rot];
      else          out[i*8 +: 8] = b[4 - rot + i];
  end
  initial begin
    seed = 8'h00; rot = 2'd1; #1;
    if (out !== 32'h02010013) begin
      $display("RESULT FAIL pass1 out=%08h expected 02010013", out); $finish; end
    seed = 8'h20; #1;
    if (out !== 32'h22212033) begin
      $display("RESULT FAIL pass2 out=%08h expected 22212033", out); $finish; end
    $display("RESULT PASS"); $finish;
  end
endmodule
