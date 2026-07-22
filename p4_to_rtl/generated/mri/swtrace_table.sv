module swtrace_table (
  input  logic clk,
  input  logic rst_n,

  // Result (no key -- always hits the configured default action)
  output logic        hit,
  output logic [0:0] action_id,
  output logic [31:0] p_swid,

  // Control-plane write port (synchronous) -- sets the default action
  input  logic        cp_wr_en,
  input  logic [0:0] cp_wr_action,
  input  logic [31:0] cp_wr_p_swid
);

  logic [0:0] action_id_r;
  logic [31:0] p_swid_r;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      action_id_r <= 1'd0;
      p_swid_r <= 32'b0;
    end else if (cp_wr_en) begin
      action_id_r <= cp_wr_action;
      p_swid_r <= cp_wr_p_swid;
    end
  end

  assign hit       = 1'b1;
  assign action_id = action_id_r;
  assign p_swid = p_swid_r;

  // Action ID encoding:
  //   0 = NoAction
  //   1 = add_swtrace

endmodule
