// An always_comb that writes a variable and then reads it back (accumulator).
module top;
  logic [7:0] seed;
  logic [7:0] src [0:3];
  logic [7:0] sum;
  always_comb for (int i = 0; i < 4; i++) src[i] = seed + i;
  always_comb begin
    logic [7:0] acc;
    acc = 8'h00;
    for (int i = 0; i < 4; i++) acc = acc + src[i];
    sum = acc;
  end
  initial begin
    seed = 8'h01; #1;                       // 1+2+3+4 = 10
    if (sum !== 8'h0A) begin
      $display("RESULT FAIL sum=%02h expected 0A", sum); $finish; end
    seed = 8'h10; #1;                       // 16+17+18+19 = 70 = 0x46
    if (sum !== 8'h46) begin
      $display("RESULT FAIL pass2 sum=%02h expected 46", sum); $finish; end
    $display("RESULT PASS"); $finish;
  end
endmodule
