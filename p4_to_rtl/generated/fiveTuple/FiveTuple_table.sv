module FiveTuple_table #(
  parameter int DEPTH = 8192
) (
  input  logic clk,
  input  logic rst_n,

  // Lookup key (combinational)
  input  logic [31:0] lkp_src,
  input  logic [31:0] lkp_dst,
  input  logic [7:0] lkp_protocol,
  input  logic [15:0] lkp_table_key_sport,
  input  logic [15:0] lkp_table_key_dport,

  // Lookup result (registered — 1 cycle after lkp_* is presented)
  output logic        hit,
  output logic [0:0] action_id,
  output logic [12:0] p_counter_index,
  output logic [2:0] p_pcp,
  output logic [0:0] p_cfi,
  output logic [11:0] p_vid,

  // Control-plane write port (synchronous)
  input  logic        cp_wr_en,
  input  logic [12:0] cp_wr_idx,  // unused: exact-match tables self-address via hash(key)
  input  logic [31:0] cp_wr_key_src,
  input  logic [31:0] cp_wr_key_dst,
  input  logic [7:0] cp_wr_key_protocol,
  input  logic [15:0] cp_wr_key_table_key_sport,
  input  logic [15:0] cp_wr_key_table_key_dport,
  input  logic [0:0] cp_wr_action,
  input  logic [12:0] cp_wr_p_counter_index,
  input  logic [2:0] cp_wr_p_pcp,
  input  logic [0:0] cp_wr_p_cfi,
  input  logic [11:0] cp_wr_p_vid
);

  // Entry storage (synthesizes to block RAM)
  logic        mem_valid  [0:DEPTH-1];
  logic [31:0] mem_key_src[0:DEPTH-1];
  logic [31:0] mem_key_dst[0:DEPTH-1];
  logic [7:0] mem_key_protocol[0:DEPTH-1];
  logic [15:0] mem_key_table_key_sport[0:DEPTH-1];
  logic [15:0] mem_key_table_key_dport[0:DEPTH-1];
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

  // XOR-fold hash: 104-bit key -> 13-bit BRAM address
  function automatic logic [12:0] hash_key(input logic [103:0] k);
    logic [12:0] h;
    integer c;
    begin
      h = '0;
      for (c = 0; c < 8; c = c + 1)
        h = h ^ k[c*13 +: 13];
      hash_key = h;
    end
  endfunction

  logic [103:0] wr_key_concat;
  assign wr_key_concat = {cp_wr_key_table_key_dport, cp_wr_key_table_key_sport, cp_wr_key_protocol, cp_wr_key_dst, cp_wr_key_src};
  logic [12:0] wr_addr;
  assign wr_addr = hash_key(wr_key_concat);

  logic [103:0] lkp_key_concat;
  assign lkp_key_concat = {lkp_table_key_dport, lkp_table_key_sport, lkp_protocol, lkp_dst, lkp_src};
  logic [12:0] lkp_addr;
  assign lkp_addr = hash_key(lkp_key_concat);

  // Synchronous write (control plane)
  always_ff @(posedge clk) begin
    if (cp_wr_en) begin
      mem_valid[wr_addr]  <= 1'b1;
      mem_key_src[wr_addr] <= cp_wr_key_src;
      mem_key_dst[wr_addr] <= cp_wr_key_dst;
      mem_key_protocol[wr_addr] <= cp_wr_key_protocol;
      mem_key_table_key_sport[wr_addr] <= cp_wr_key_table_key_sport;
      mem_key_table_key_dport[wr_addr] <= cp_wr_key_table_key_dport;
      mem_action[wr_addr] <= cp_wr_action;
      mem_p_counter_index[wr_addr] <= cp_wr_p_counter_index;
      mem_p_pcp[wr_addr] <= cp_wr_p_pcp;
      mem_p_cfi[wr_addr] <= cp_wr_p_cfi;
      mem_p_vid[wr_addr] <= cp_wr_p_vid;
    end
  end

  // Registered BRAM read + tag-compare stage (1-cycle lookup latency)
  logic        valid_r;
  logic [31:0] key_r_src;
  logic [31:0] mem_key_r_src;
  logic [31:0] key_r_dst;
  logic [31:0] mem_key_r_dst;
  logic [7:0] key_r_protocol;
  logic [7:0] mem_key_r_protocol;
  logic [15:0] key_r_table_key_sport;
  logic [15:0] mem_key_r_table_key_sport;
  logic [15:0] key_r_table_key_dport;
  logic [15:0] mem_key_r_table_key_dport;
  logic [0:0] action_id_r;
  logic [12:0] p_r_counter_index;
  logic [2:0] p_r_pcp;
  logic [0:0] p_r_cfi;
  logic [11:0] p_r_vid;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      valid_r <= 1'b0;
    end else begin
      valid_r     <= mem_valid[lkp_addr];
      key_r_src     <= lkp_src;
      mem_key_r_src <= mem_key_src[lkp_addr];
      key_r_dst     <= lkp_dst;
      mem_key_r_dst <= mem_key_dst[lkp_addr];
      key_r_protocol     <= lkp_protocol;
      mem_key_r_protocol <= mem_key_protocol[lkp_addr];
      key_r_table_key_sport     <= lkp_table_key_sport;
      mem_key_r_table_key_sport <= mem_key_table_key_sport[lkp_addr];
      key_r_table_key_dport     <= lkp_table_key_dport;
      mem_key_r_table_key_dport <= mem_key_table_key_dport[lkp_addr];
      action_id_r <= mem_action[lkp_addr];
      p_r_counter_index <= mem_p_counter_index[lkp_addr];
      p_r_pcp <= mem_p_pcp[lkp_addr];
      p_r_cfi <= mem_p_cfi[lkp_addr];
      p_r_vid <= mem_p_vid[lkp_addr];
    end
  end

  logic hit_c; assign hit_c = valid_r && (mem_key_r_src == key_r_src) && (mem_key_r_dst == key_r_dst) && (mem_key_r_protocol == key_r_protocol) && (mem_key_r_table_key_sport == key_r_table_key_sport) && (mem_key_r_table_key_dport == key_r_table_key_dport);
  logic [0:0] action_id_c;
  assign action_id_c = hit_c ? action_id_r : 1'd0;
  logic [12:0] p_counter_index_c;
  assign p_counter_index_c = hit_c ? p_r_counter_index : 13'b0;
  logic [2:0] p_pcp_c;
  assign p_pcp_c = hit_c ? p_r_pcp : 3'b0;
  logic [0:0] p_cfi_c;
  assign p_cfi_c = hit_c ? p_r_cfi : 1'b0;
  logic [11:0] p_vid_c;
  assign p_vid_c = hit_c ? p_r_vid : 12'b0;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      hit <= 1'b0;
    end else begin
      hit <= hit_c;
      action_id <= action_id_c;
      p_counter_index <= p_counter_index_c;
      p_pcp <= p_pcp_c;
      p_cfi <= p_cfi_c;
      p_vid <= p_vid_c;
    end
  end

  // Action ID encoding:
  //   0 = NoAction
  //   1 = InsertVLAN

endmodule
