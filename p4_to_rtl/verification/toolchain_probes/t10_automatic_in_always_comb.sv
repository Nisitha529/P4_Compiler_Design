// An `automatic` variable declared inside always_comb.
module top;
  logic [7:0] seed;
  logic [7:0] src [0:3];
  logic [7:0] sum;
  always_comb for (int i = 0; i < 4; i++) src[i] = seed + i;
  always_comb begin
    automatic logic [7:0] t = 8'h00;
    for (int i = 0; i < 4; i++) t = t + src[i];
    sum = t;
  end
  initial begin
    seed = 8'h01; #1;
    if (sum !== 8'h0A) begin
      $display("RESULT FAIL sum=%02h expected 0A", sum); $finish; end
    $display("RESULT PASS"); $finish;
  end
endmodule
