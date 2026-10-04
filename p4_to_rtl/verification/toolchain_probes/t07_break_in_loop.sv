// `break` inside a for loop in always_comb.
module top;
  logic [7:0] seed, cnt;
  always_comb begin
    cnt = 8'h00;
    for (int i = 0; i < 8; i++) begin
      if (i == 4) break;
      cnt = cnt + 8'd1;
    end
  end
  initial begin
    seed = 8'h00; #1;
    if (cnt !== 8'd4) begin
      $display("RESULT FAIL cnt=%0d expected 4", cnt); $finish; end
    $display("RESULT PASS"); $finish;
  end
endmodule
