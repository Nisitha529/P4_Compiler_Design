module ecmp_nhop_table #(
  parameter int DEPTH = 2
) (
  input  logic clk,
  input  logic rst_n,

  // Lookup key (combinational)
  input  logic [13:0] lkp_ecmp_select,

  // Lookup result
  output logic        hit,
  output logic [1:0] action_id,
  output logic [47:0] p_nhop_dmac,
  output logic [31:0] p_nhop_ipv4,
  output logic [8:0] p_port,

  // Control-plane write port (synchronous)
  input  logic        cp_wr_en,
  input  logic [0:0] cp_wr_idx,
  input  logic [13:0] cp_wr_key_ecmp_select,
  input  logic [1:0] cp_wr_action,
  input  logic [47:0] cp_wr_p_nhop_dmac,
  input  logic [31:0] cp_wr_p_nhop_ipv4,
  input  logic [8:0] cp_wr_p_port
);

  // Entry storage
  logic        mem_valid  [0:DEPTH-1];
  logic [13:0] mem_key_ecmp_select[0:DEPTH-1];
  logic [1:0] mem_action[0:DEPTH-1];
  logic [47:0] mem_p_nhop_dmac[0:DEPTH-1];
  logic [31:0] mem_p_nhop_ipv4[0:DEPTH-1];
  logic [8:0] mem_p_port[0:DEPTH-1];

  integer _i;
  initial begin
    for (_i = 0; _i < DEPTH; _i = _i + 1)
      mem_valid[_i] = 1'b0;
  end

  always_ff @(posedge clk) begin
    if (cp_wr_en) begin
      mem_valid[cp_wr_idx]  <= 1'b1;
      mem_key_ecmp_select[cp_wr_idx] <= cp_wr_key_ecmp_select;
      mem_action[cp_wr_idx] <= cp_wr_action;
      mem_p_nhop_dmac[cp_wr_idx] <= cp_wr_p_nhop_dmac;
      mem_p_nhop_ipv4[cp_wr_idx] <= cp_wr_p_nhop_ipv4;
      mem_p_port[cp_wr_idx] <= cp_wr_p_port;
    end
  end

  // Combinational lookup
  // LPM: first-match wins; CP software should insert longest-prefix-first.
  always @(*) begin
    hit       = 1'b0;
    action_id = 2'd0;
    p_nhop_dmac = 48'b0;
    p_nhop_ipv4 = 32'b0;
    p_port = 9'b0;
    for (int _j = 0; _j < DEPTH; _j++) begin
      if (!hit && mem_valid[_j]) begin
        if (lkp_ecmp_select == mem_key_ecmp_select[_j]) begin
          hit       = 1'b1;
          action_id = mem_action[_j];
          p_nhop_dmac = mem_p_nhop_dmac[_j];
          p_nhop_ipv4 = mem_p_nhop_ipv4[_j];
          p_port = mem_p_port[_j];
        end
      end
    end
  end

  // Action ID encoding:
  //   0 = NoAction
  //   1 = drop
  //   2 = set_nhop

endmodule
