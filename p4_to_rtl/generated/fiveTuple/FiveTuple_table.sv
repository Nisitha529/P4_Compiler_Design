module FiveTuple_table #(
  parameter int DEPTH = 32
) (
  input  logic clk,
  input  logic rst_n,

  // Lookup key (combinational)
  input  logic [31:0] lkp_src,
  input  logic [31:0] lkp_dst,
  input  logic [7:0] lkp_protocol,
  input  logic [31:0] lkp_table_key_sport,
  input  logic [31:0] lkp_table_key_dport,

  // Lookup result
  output logic        hit,
  output logic [0:0] action_id,
  output logic [12:0] p_counter_index,
  output logic [2:0] p_pcp,
  output logic [0:0] p_cfi,
  output logic [11:0] p_vid,

  // Control-plane write port (synchronous)
  input  logic        cp_wr_en,
  input  logic [4:0] cp_wr_idx,
  input  logic [31:0] cp_wr_key_src,
  input  logic [31:0] cp_wr_key_dst,
  input  logic [7:0] cp_wr_key_protocol,
  input  logic [31:0] cp_wr_key_table_key_sport,
  input  logic [31:0] cp_wr_key_table_key_dport,
  input  logic [0:0] cp_wr_action,
  input  logic [12:0] cp_wr_p_counter_index,
  input  logic [2:0] cp_wr_p_pcp,
  input  logic [0:0] cp_wr_p_cfi,
  input  logic [11:0] cp_wr_p_vid
);

  // Entry storage
  logic        mem_valid  [0:DEPTH-1];
  logic [31:0] mem_key_src[0:DEPTH-1];
  logic [31:0] mem_key_dst[0:DEPTH-1];
  logic [7:0] mem_key_protocol[0:DEPTH-1];
  logic [31:0] mem_key_table_key_sport[0:DEPTH-1];
  logic [31:0] mem_key_table_key_dport[0:DEPTH-1];
  logic [0:0] mem_action[0:DEPTH-1];
  logic [12:0] mem_p_counter_index[0:DEPTH-1];
  logic [2:0] mem_p_pcp[0:DEPTH-1];
  logic [0:0] mem_p_cfi[0:DEPTH-1];
  logic [11:0] mem_p_vid[0:DEPTH-1];

  integer _i;
  initial begin
    for (_i = 0; _i < DEPTH; _i = _i + 1)
      mem_valid[_i] = 1'b0;
  end

  always_ff @(posedge clk) begin
    if (cp_wr_en) begin
      mem_valid[cp_wr_idx]  <= 1'b1;
      mem_key_src[cp_wr_idx] <= cp_wr_key_src;
      mem_key_dst[cp_wr_idx] <= cp_wr_key_dst;
      mem_key_protocol[cp_wr_idx] <= cp_wr_key_protocol;
      mem_key_table_key_sport[cp_wr_idx] <= cp_wr_key_table_key_sport;
      mem_key_table_key_dport[cp_wr_idx] <= cp_wr_key_table_key_dport;
      mem_action[cp_wr_idx] <= cp_wr_action;
      mem_p_counter_index[cp_wr_idx] <= cp_wr_p_counter_index;
      mem_p_pcp[cp_wr_idx] <= cp_wr_p_pcp;
      mem_p_cfi[cp_wr_idx] <= cp_wr_p_cfi;
      mem_p_vid[cp_wr_idx] <= cp_wr_p_vid;
    end
  end

  // Combinational lookup
  // LPM: first-match wins; CP software should insert longest-prefix-first.
  always @(*) begin
    hit       = 1'b0;
    action_id = 1'd0;
    p_counter_index = 13'b0;
    p_pcp = 3'b0;
    p_cfi = 1'b0;
    p_vid = 12'b0;
    for (int _j = 0; _j < DEPTH; _j++) begin
      if (!hit && mem_valid[_j]) begin
        if (lkp_src == mem_key_src[_j] && lkp_dst == mem_key_dst[_j] && lkp_protocol == mem_key_protocol[_j] && lkp_table_key_sport == mem_key_table_key_sport[_j] && lkp_table_key_dport == mem_key_table_key_dport[_j]) begin
          hit       = 1'b1;
          action_id = mem_action[_j];
          p_counter_index = mem_p_counter_index[_j];
          p_pcp = mem_p_pcp[_j];
          p_cfi = mem_p_cfi[_j];
          p_vid = mem_p_vid[_j];
        end
      end
    end
  end

  // Action ID encoding:
  //   0 = NoAction
  //   1 = InsertVLAN

endmodule
