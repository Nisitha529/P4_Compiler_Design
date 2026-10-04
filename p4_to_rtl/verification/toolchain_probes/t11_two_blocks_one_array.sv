// Two procedural blocks writing DIFFERENT elements of one unpacked array.
// Simulators resolve this; Quartus calls it a multi-driver (checked separately).
module top;
  logic [7:0] seed;
  logic [7:0] arr [0:1];
  always_comb arr[0] = seed;
  always_comb arr[1] = seed + 8'd1;
  initial begin
    seed = 8'h90; #1;
    if (arr[0] !== 8'h90 || arr[1] !== 8'h91) begin
      $display("RESULT FAIL a0=%02h a1=%02h expected 90 91", arr[0], arr[1]); $finish; end
    $display("RESULT PASS"); $finish;
  end
endmodule
