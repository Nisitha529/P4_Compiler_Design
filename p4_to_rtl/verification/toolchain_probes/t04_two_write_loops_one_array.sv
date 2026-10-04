// Clear-then-fill: two write loops over the SAME unpacked array in one
// always_comb. emit_top.py collapsed these into one unconditional loop.
module top;
  logic [7:0] seed;
  logic [7:0] src [0:3];
  logic [7:0] dst [0:7];
  always_comb for (int i = 0; i < 4; i++) src[i] = seed + i;
  always_comb begin
    for (int i = 0; i < 8; i++) dst[i] = 8'h00;
    for (int i = 0; i < 4; i++) dst[i + 2] = src[i];
  end
  initial begin
    seed = 8'h50; #1;
    if (dst[0] !== 8'h00 || dst[2] !== 8'h50 || dst[5] !== 8'h53 || dst[6] !== 8'h00) begin
      $display("RESULT FAIL d0=%02h d2=%02h d5=%02h d6=%02h exp 00 50 53 00",
               dst[0], dst[2], dst[5], dst[6]); $finish; end
    seed = 8'h60; #1;
    if (dst[2] !== 8'h60) begin
      $display("RESULT FAIL pass2 d2=%02h exp 60", dst[2]); $finish; end
    $display("RESULT PASS"); $finish;
  end
endmodule
