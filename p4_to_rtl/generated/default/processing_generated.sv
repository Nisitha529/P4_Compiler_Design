module processing_generated (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        valid_in,

  // Header valid flags

  // Header field inputs

  // Header field outputs (pass-through, optionally modified)

  output logic        valid_out,
  output logic        drop
);

  always_comb begin
    drop = 0;

    // pass-through defaults

    // (no apply statements)
  end

  always_ff @(posedge clk) begin
    if (!rst_n) valid_out <= 0;
    else        valid_out <= valid_in;
  end

endmodule
