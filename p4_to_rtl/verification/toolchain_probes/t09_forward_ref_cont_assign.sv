// A continuous assign referencing a wire declared LATER in the module.
module top;
  logic [7:0] seed;
  wire  [7:0] y = x + 8'd1;
  wire  [7:0] x = seed;
  initial begin
    seed = 8'h30; #1;
    if (y !== 8'h31) begin
      $display("RESULT FAIL y=%02h expected 31", y); $finish; end
    $display("RESULT PASS"); $finish;
  end
endmodule
