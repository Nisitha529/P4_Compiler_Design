module flow_cache_table #(
  parameter int DEPTH = 65536
) (
  input  logic clk,
  input  logic rst_n,

  // Lookup key (combinational)
  input  logic [7:0] lkp_protocol,
  input  logic [31:0] lkp_srcAddr,
  input  logic [31:0] lkp_dstAddr,

  // Lookup result (registered — 1 cycle after lkp_* is presented)
  output logic        hit,
  output logic [1:0] action_id,
  output logic [8:0] p_port,
  output logic [0:0] p_decrement_ttl,
  output logic [5:0] p_new_dscp,
  output logic [47:0] p_dst_eth_addr,

  // Control-plane write port (synchronous)
  input  logic        cp_wr_en,
  input  logic [15:0] cp_wr_idx,  // unused: exact-match tables self-address via hash(key)
  input  logic [7:0] cp_wr_key_protocol,
  input  logic [31:0] cp_wr_key_srcAddr,
  input  logic [31:0] cp_wr_key_dstAddr,
  input  logic [1:0] cp_wr_action,
  input  logic [8:0] cp_wr_p_port,
  input  logic [0:0] cp_wr_p_decrement_ttl,
  input  logic [5:0] cp_wr_p_new_dscp,
  input  logic [47:0] cp_wr_p_dst_eth_addr
);

  // Entry storage (synthesizes to block RAM)
  logic        mem_valid  [0:DEPTH-1];
  logic [7:0] mem_key_protocol[0:DEPTH-1];
  logic [31:0] mem_key_srcAddr[0:DEPTH-1];
  logic [31:0] mem_key_dstAddr[0:DEPTH-1];
  logic [1:0] mem_action[0:DEPTH-1];
  logic [8:0] mem_p_port[0:DEPTH-1];
  logic [0:0] mem_p_decrement_ttl[0:DEPTH-1];
  logic [5:0] mem_p_new_dscp[0:DEPTH-1];
  logic [47:0] mem_p_dst_eth_addr[0:DEPTH-1];

  integer _i;
  initial begin
    for (_i = 0; _i < DEPTH; _i = _i + 1)
      mem_valid[_i] = 1'b0;
  end

  // XOR-fold hash: 72-bit key -> 16-bit BRAM address
  function automatic logic [15:0] hash_key(input logic [79:0] k);
    logic [15:0] h;
    integer c;
    begin
      h = '0;
      for (c = 0; c < 5; c = c + 1)
        h = h ^ k[c*16 +: 16];
      hash_key = h;
    end
  endfunction

  logic [79:0] wr_key_concat;
  assign wr_key_concat = {8'd0, cp_wr_key_dstAddr, cp_wr_key_srcAddr, cp_wr_key_protocol};
  logic [15:0] wr_addr;
  assign wr_addr = hash_key(wr_key_concat);

  logic [79:0] lkp_key_concat;
  assign lkp_key_concat = {8'd0, lkp_dstAddr, lkp_srcAddr, lkp_protocol};
  logic [15:0] lkp_addr;
  assign lkp_addr = hash_key(lkp_key_concat);

  // Synchronous write (control plane)
  always_ff @(posedge clk) begin
    if (cp_wr_en) begin
      mem_valid[wr_addr]  <= 1'b1;
      mem_key_protocol[wr_addr] <= cp_wr_key_protocol;
      mem_key_srcAddr[wr_addr] <= cp_wr_key_srcAddr;
      mem_key_dstAddr[wr_addr] <= cp_wr_key_dstAddr;
      mem_action[wr_addr] <= cp_wr_action;
      mem_p_port[wr_addr] <= cp_wr_p_port;
      mem_p_decrement_ttl[wr_addr] <= cp_wr_p_decrement_ttl;
      mem_p_new_dscp[wr_addr] <= cp_wr_p_new_dscp;
      mem_p_dst_eth_addr[wr_addr] <= cp_wr_p_dst_eth_addr;
    end
  end

  // Registered BRAM read + tag-compare stage (1-cycle lookup latency)
  logic        valid_r;
  logic [7:0] key_r_protocol;
  logic [7:0] mem_key_r_protocol;
  logic [31:0] key_r_srcAddr;
  logic [31:0] mem_key_r_srcAddr;
  logic [31:0] key_r_dstAddr;
  logic [31:0] mem_key_r_dstAddr;
  logic [1:0] action_id_r;
  logic [8:0] p_r_port;
  logic [0:0] p_r_decrement_ttl;
  logic [5:0] p_r_new_dscp;
  logic [47:0] p_r_dst_eth_addr;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      valid_r <= 1'b0;
    end else begin
      valid_r     <= mem_valid[lkp_addr];
      key_r_protocol     <= lkp_protocol;
      mem_key_r_protocol <= mem_key_protocol[lkp_addr];
      key_r_srcAddr     <= lkp_srcAddr;
      mem_key_r_srcAddr <= mem_key_srcAddr[lkp_addr];
      key_r_dstAddr     <= lkp_dstAddr;
      mem_key_r_dstAddr <= mem_key_dstAddr[lkp_addr];
      action_id_r <= mem_action[lkp_addr];
      p_r_port <= mem_p_port[lkp_addr];
      p_r_decrement_ttl <= mem_p_decrement_ttl[lkp_addr];
      p_r_new_dscp <= mem_p_new_dscp[lkp_addr];
      p_r_dst_eth_addr <= mem_p_dst_eth_addr[lkp_addr];
    end
  end

  assign hit       = valid_r && (mem_key_r_protocol == key_r_protocol) && (mem_key_r_srcAddr == key_r_srcAddr) && (mem_key_r_dstAddr == key_r_dstAddr);
  assign action_id = hit ? action_id_r : 2'd3;
  assign p_port = hit ? p_r_port : 9'b0;
  assign p_decrement_ttl = hit ? p_r_decrement_ttl : 1'b0;
  assign p_new_dscp = hit ? p_r_new_dscp : 6'b0;
  assign p_dst_eth_addr = hit ? p_r_dst_eth_addr : 48'b0;

  // Action ID encoding:
  //   0 = NoAction
  //   1 = cached_action
  //   2 = drop_packet
  //   3 = flow_unknown

endmodule
