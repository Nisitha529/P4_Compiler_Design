module check_ports_table #(
  parameter int DEPTH = 1024
) (
  input  logic clk,
  input  logic rst_n,

  // Lookup key (combinational)
  input  logic [8:0] lkp_ingress_port,
  input  logic [8:0] lkp_egress_spec,

  // Lookup result
  output logic        hit,
  output logic [0:0] action_id,
  output logic [0:0] p_dir,

  // Control-plane write port (synchronous)
  input  logic        cp_wr_en,
  input  logic [9:0] cp_wr_idx,
  input  logic [8:0] cp_wr_key_ingress_port,
  input  logic [8:0] cp_wr_key_egress_spec,
  input  logic [0:0] cp_wr_action,
  input  logic [0:0] cp_wr_p_dir
);

  // Entry storage
  logic        mem_valid  [0:DEPTH-1];
  logic [8:0] mem_key_ingress_port[0:DEPTH-1];
  logic [8:0] mem_key_egress_spec[0:DEPTH-1];
  logic [0:0] mem_action[0:DEPTH-1];
  logic [0:0] mem_p_dir[0:DEPTH-1];

  integer _i;
  initial begin
    for (_i = 0; _i < DEPTH; _i = _i + 1)
      mem_valid[_i] = 1'b0;
  end

  always_ff @(posedge clk) begin
    if (cp_wr_en) begin
      mem_valid[cp_wr_idx]  <= 1'b1;
      mem_key_ingress_port[cp_wr_idx] <= cp_wr_key_ingress_port;
      mem_key_egress_spec[cp_wr_idx] <= cp_wr_key_egress_spec;
      mem_action[cp_wr_idx] <= cp_wr_action;
      mem_p_dir[cp_wr_idx] <= cp_wr_p_dir;
    end
  end

  always @(*) begin
    hit       = 1'b0;
    action_id = 1'd0;
    p_dir = 1'b0;
    for (int _j = 0; _j < DEPTH; _j++) begin
      if (mem_valid[_j]) begin
        if (lkp_ingress_port == mem_key_ingress_port[_j] && lkp_egress_spec == mem_key_egress_spec[_j]) begin
          hit       = 1'b1;
          action_id = mem_action[_j];
          p_dir = mem_p_dir[_j];
        end
      end
    end
  end

  // Action ID encoding:
  //   0 = NoAction
  //   1 = set_direction

endmodule
