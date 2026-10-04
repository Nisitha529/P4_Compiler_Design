// Reading an unpacked array element in a CONTINUOUS ASSIGN.
module top;
  logic [7:0] seed;
  logic [7:0] arr [0:3];
  always_comb for (int i = 0; i < 4; i++) arr[i] = seed + i;
  wire [7:0] w = arr[2];
  initial begin
    seed = 8'h70; #1;
    if (w !== 8'h72) begin
      $display("RESULT FAIL w=%02h expected 72", w); $finish; end
    $display("RESULT PASS"); $finish;
  end
endmodule
