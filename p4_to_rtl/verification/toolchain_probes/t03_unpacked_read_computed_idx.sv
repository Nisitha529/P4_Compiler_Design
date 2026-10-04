// Reading an UNPACKED array at a computed (non-loop-variable) index inside
// always_comb. emit_top.py replaced this with a case over constant offsets.
module top;
  logic [7:0] seed;
  logic [7:0] src [0:7];
  logic [7:0] dst [0:7];
  logic [3:0] off;
  always_comb for (int i = 0; i < 8; i++) src[i] = seed + i;
  always_comb begin
    int q;
    for (int p = 0; p < 8; p++) begin
      q = p - off;
      dst[p] = (q >= 0 && q < 8) ? src[q] : 8'h00;
    end
  end
  initial begin
    seed = 8'h40; off = 4'd2; #1;
    if (dst[0] !== 8'h00 || dst[1] !== 8'h00 || dst[2] !== 8'h40 || dst[7] !== 8'h45) begin
      $display("RESULT FAIL d0=%02h d1=%02h d2=%02h d7=%02h exp 00 00 40 45",
               dst[0], dst[1], dst[2], dst[7]); $finish; end
    seed = 8'h80; #1;
    if (dst[2] !== 8'h80 || dst[7] !== 8'h85) begin
      $display("RESULT FAIL pass2 d2=%02h d7=%02h exp 80 85", dst[2], dst[7]); $finish; end
    $display("RESULT PASS"); $finish;
  end
endmodule
