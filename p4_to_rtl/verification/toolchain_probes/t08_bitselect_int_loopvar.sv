// Bit-select of an `int` loop variable.
module top;
  logic [7:0] m;
  always_comb begin
    m = '0;
    for (int i = 0; i < 8; i++) if (i[0]) m[i] = 1'b1;
  end
  initial begin
    #1;
    if (m !== 8'b10101010) begin
      $display("RESULT FAIL m=%08b expected 10101010", m); $finish; end
    $display("RESULT PASS"); $finish;
  end
endmodule
