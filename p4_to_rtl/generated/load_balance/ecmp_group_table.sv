module ecmp_group_table #(
  parameter int DEPTH = 1024
) (
  input  logic clk,
  input  logic rst_n,

  // Lookup key (combinational)
  input  logic [31:0] lkp_dstAddr,

  // Lookup result
  output logic        hit,
  output logic [1:0] action_id,
  output logic [15:0] p_ecmp_base,
  output logic [31:0] p_ecmp_count,

  // Control-plane write port (synchronous)
  input  logic        cp_wr_en,
  input  logic [9:0] cp_wr_idx,
  input  logic [31:0] cp_wr_key_dstAddr,
  input  logic [5:0] cp_wr_pfx_len,
  input  logic [1:0] cp_wr_action,
  input  logic [15:0] cp_wr_p_ecmp_base,
  input  logic [31:0] cp_wr_p_ecmp_count
);

  // Entry storage
  logic        mem_valid  [0:DEPTH-1];
  logic [31:0] mem_key_dstAddr[0:DEPTH-1];
  logic [5:0] mem_pfx_len[0:DEPTH-1];
  logic [1:0] mem_action[0:DEPTH-1];
  logic [15:0] mem_p_ecmp_base[0:DEPTH-1];
  logic [31:0] mem_p_ecmp_count[0:DEPTH-1];

  integer _i;
  initial begin
    for (_i = 0; _i < DEPTH; _i = _i + 1)
      mem_valid[_i] = 1'b0;
  end

  always_ff @(posedge clk) begin
    if (cp_wr_en) begin
      mem_valid[cp_wr_idx]  <= 1'b1;
      mem_key_dstAddr[cp_wr_idx] <= cp_wr_key_dstAddr;
      mem_pfx_len[cp_wr_idx] <= cp_wr_pfx_len;
      mem_action[cp_wr_idx] <= cp_wr_action;
      mem_p_ecmp_base[cp_wr_idx] <= cp_wr_p_ecmp_base;
      mem_p_ecmp_count[cp_wr_idx] <= cp_wr_p_ecmp_count;
    end
  end

  // Combinational lookup
  // LPM: first-match wins; CP software should insert longest-prefix-first.
  always @(*) begin
    hit       = 1'b0;
    action_id = 2'd0;
    p_ecmp_base = 16'b0;
    p_ecmp_count = 32'b0;
    for (int _j = 0; _j < DEPTH; _j++) begin
      if (!hit && mem_valid[_j]) begin
        if (mem_pfx_len[_j] == 6'd0 ||
            (lkp_dstAddr >> (32 - mem_pfx_len[_j])) ==
            (mem_key_dstAddr[_j] >> (32 - mem_pfx_len[_j]))) begin
          hit       = 1'b1;
          action_id = mem_action[_j];
          p_ecmp_base = mem_p_ecmp_base[_j];
          p_ecmp_count = mem_p_ecmp_count[_j];
        end
      end
    end
  end

  // Action ID encoding:
  //   0 = NoAction
  //   1 = drop
  //   2 = set_ecmp_select

endmodule
