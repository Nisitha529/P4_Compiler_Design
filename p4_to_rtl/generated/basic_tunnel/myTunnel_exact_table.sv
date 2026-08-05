module myTunnel_exact_table #(
  parameter int DEPTH = 1024
) (
  input  logic clk,
  input  logic rst_n,

  // Lookup key (combinational)
  input  logic [15:0] lkp_dst_id,

  // Lookup result (registered — 1 cycle after lkp_* is presented)
  output logic        hit,
  output logic [1:0] action_id,
  output logic [8:0] p_port,

  // Control-plane write port (synchronous)
  input  logic        cp_wr_en,
  input  logic [9:0] cp_wr_idx,  // unused: exact-match tables self-address via hash(key)
  input  logic [15:0] cp_wr_key_dst_id,
  input  logic [1:0] cp_wr_action,
  input  logic [8:0] cp_wr_p_port
);

  // Entry storage (synthesizes to block RAM)
  logic        mem_valid  [0:DEPTH-1];
  logic [15:0] mem_key_dst_id[0:DEPTH-1];
  logic [1:0] mem_action[0:DEPTH-1];
  logic [8:0] mem_p_port[0:DEPTH-1];

  integer _i;
  initial begin
    for (_i = 0; _i < DEPTH; _i = _i + 1)
      mem_valid[_i] = 1'b0;
  end

  // XOR-fold hash: 16-bit key -> 10-bit BRAM address
  function automatic logic [9:0] hash_key(input logic [19:0] k);
    logic [9:0] h;
    integer c;
    begin
      h = '0;
      for (c = 0; c < 2; c = c + 1)
        h = h ^ k[c*10 +: 10];
      hash_key = h;
    end
  endfunction

  logic [19:0] wr_key_concat;
  assign wr_key_concat = {4'd0, cp_wr_key_dst_id};
  logic [9:0] wr_addr;
  assign wr_addr = hash_key(wr_key_concat);

  logic [19:0] lkp_key_concat;
  assign lkp_key_concat = {4'd0, lkp_dst_id};
  logic [9:0] lkp_addr;
  assign lkp_addr = hash_key(lkp_key_concat);

  // Synchronous write (control plane)
  always_ff @(posedge clk) begin
    if (cp_wr_en) begin
      mem_valid[wr_addr]  <= 1'b1;
      mem_key_dst_id[wr_addr] <= cp_wr_key_dst_id;
      mem_action[wr_addr] <= cp_wr_action;
      mem_p_port[wr_addr] <= cp_wr_p_port;
    end
  end

  // Registered BRAM read + tag-compare stage (1-cycle lookup latency)
  logic        valid_r;
  logic [15:0] key_r_dst_id;
  logic [15:0] mem_key_r_dst_id;
  logic [1:0] action_id_r;
  logic [8:0] p_r_port;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      valid_r <= 1'b0;
    end else begin
      valid_r     <= mem_valid[lkp_addr];
      key_r_dst_id     <= lkp_dst_id;
      mem_key_r_dst_id <= mem_key_dst_id[lkp_addr];
      action_id_r <= mem_action[lkp_addr];
      p_r_port <= mem_p_port[lkp_addr];
    end
  end

  logic hit_c; assign hit_c = valid_r && (mem_key_r_dst_id == key_r_dst_id);
  logic [1:0] action_id_c;
  assign action_id_c = hit_c ? action_id_r : 2'd2;
  logic [8:0] p_port_c;
  assign p_port_c = hit_c ? p_r_port : 9'b0;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      hit <= 1'b0;
    end else begin
      hit <= hit_c;
      action_id <= action_id_c;
      p_port <= p_port_c;
    end
  end

  // Action ID encoding:
  //   0 = NoAction
  //   1 = myTunnel_forward
  //   2 = drop

endmodule
