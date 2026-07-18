module MyIngress.ipv4_lpm_table #(
  parameter int DEPTH = 1024
) (
  input  logic clk,
  input  logic rst_n,

  // Lookup key (combinational)
  input  logic [31:0] lkp_dstAddr,

  // Lookup result
  output logic        hit,
  output logic [1:0] action_id,
  output logic [47:0] p_dstAddr,
  output logic [8:0] p_port,

  // Control-plane write port (synchronous)
  input  logic        cp_wr_en,
  input  logic [9:0] cp_wr_idx,
  input  logic [31:0] cp_wr_key_dstAddr,
  input  logic [5:0] cp_wr_pfx_len,
  input  logic [1:0] cp_wr_action,
  input  logic [47:0] cp_wr_p_dstAddr,
  input  logic [8:0] cp_wr_p_port
);

  // Entry storage
  logic        mem_valid  [0:DEPTH-1];
  logic [31:0] mem_key_dstAddr[0:DEPTH-1];
  logic [5:0] mem_pfx_len[0:DEPTH-1];
  logic [1:0] mem_action[0:DEPTH-1];
  logic [47:0] mem_p_dstAddr[0:DEPTH-1];
  logic [8:0] mem_p_port[0:DEPTH-1];

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
      mem_p_dstAddr[cp_wr_idx] <= cp_wr_p_dstAddr;
      mem_p_port[cp_wr_idx] <= cp_wr_p_port;
    end
  end

  // Combinational lookup
  // LPM: first-match wins; CP software should insert longest-prefix-first.
  always @(*) begin
    hit       = 1'b0;
    action_id = 2'd2;
    p_dstAddr = 48'b0;
    p_port = 9'b0;
    for (int _j = 0; _j < DEPTH; _j++) begin
      if (!hit && mem_valid[_j]) begin
        if (mem_pfx_len[_j] == 6'd0 ||
            (lkp_dstAddr >> (32 - mem_pfx_len[_j])) ==
            (mem_key_dstAddr[_j] >> (32 - mem_pfx_len[_j]))) begin
          hit       = 1'b1;
          action_id = mem_action[_j];
          p_dstAddr = mem_p_dstAddr[_j];
          p_port = mem_p_port[_j];
        end
      end
    end
  end

  // Action ID encoding:
  //   0 = NoAction
  //   1 = MyIngress.ipv4_forward
  //   2 = MyIngress.drop

endmodule
