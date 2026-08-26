module ecmp_group_table (
  input  logic clk,
  input  logic rst_n,

  // Result (no key -- always hits the configured default action)
  output logic        hit,
  output logic [0:0] action_id,

  // Control-plane write port (synchronous) -- sets the default action
  input  logic        cp_wr_en,
  input  logic [0:0] cp_wr_action
);

  logic [0:0] action_id_r;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      action_id_r <= 1'd1;
    end else if (cp_wr_en) begin
      action_id_r <= cp_wr_action;
    end
  end

  assign hit       = 1'b1;
  assign action_id = action_id_r;

  // Action ID encoding:
  //   0 = NoAction
  //   1 = set_ecmp_hash

endmodule
