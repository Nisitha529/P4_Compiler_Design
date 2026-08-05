module send_frame_table #(
  parameter int DEPTH = 256
) (
  input  logic clk,
  input  logic rst_n,

  // Lookup key (combinational)
  input  logic [8:0] lkp_egress_port,

  // Lookup result (registered — 1 cycle after lkp_* is presented)
  output logic        hit,
  output logic [1:0] action_id,
  output logic [47:0] p_smac,

  // Control-plane write port (synchronous)
  input  logic        cp_wr_en,
  input  logic [7:0] cp_wr_idx,  // unused: exact-match tables self-address via hash(key)
  input  logic [8:0] cp_wr_key_egress_port,
  input  logic [1:0] cp_wr_action,
  input  logic [47:0] cp_wr_p_smac
);

  // Entry storage (synthesizes to block RAM)
  logic        mem_valid  [0:DEPTH-1];
  logic [8:0] mem_key_egress_port[0:DEPTH-1];
  logic [1:0] mem_action[0:DEPTH-1];
  logic [47:0] mem_p_smac[0:DEPTH-1];

  integer _i;
  initial begin
    for (_i = 0; _i < DEPTH; _i = _i + 1)
      mem_valid[_i] = 1'b0;
  end

  // XOR-fold hash: 9-bit key -> 8-bit BRAM address
  function automatic logic [7:0] hash_key(input logic [15:0] k);
    logic [7:0] h;
    integer c;
    begin
      h = '0;
      for (c = 0; c < 2; c = c + 1)
        h = h ^ k[c*8 +: 8];
      hash_key = h;
    end
  endfunction

  logic [15:0] wr_key_concat;
  assign wr_key_concat = {7'd0, cp_wr_key_egress_port};
  logic [7:0] wr_addr;
  assign wr_addr = hash_key(wr_key_concat);

  logic [15:0] lkp_key_concat;
  assign lkp_key_concat = {7'd0, lkp_egress_port};
  logic [7:0] lkp_addr;
  assign lkp_addr = hash_key(lkp_key_concat);

  // Synchronous write (control plane)
  always_ff @(posedge clk) begin
    if (cp_wr_en) begin
      mem_valid[wr_addr]  <= 1'b1;
      mem_key_egress_port[wr_addr] <= cp_wr_key_egress_port;
      mem_action[wr_addr] <= cp_wr_action;
      mem_p_smac[wr_addr] <= cp_wr_p_smac;
    end
  end

  // Registered BRAM read + tag-compare stage (1-cycle lookup latency)
  logic        valid_r;
  logic [8:0] key_r_egress_port;
  logic [8:0] mem_key_r_egress_port;
  logic [1:0] action_id_r;
  logic [47:0] p_r_smac;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      valid_r <= 1'b0;
    end else begin
      valid_r     <= mem_valid[lkp_addr];
      key_r_egress_port     <= lkp_egress_port;
      mem_key_r_egress_port <= mem_key_egress_port[lkp_addr];
      action_id_r <= mem_action[lkp_addr];
      p_r_smac <= mem_p_smac[lkp_addr];
    end
  end

  logic hit_c; assign hit_c = valid_r && (mem_key_r_egress_port == key_r_egress_port);
  logic [1:0] action_id_c;
  assign action_id_c = hit_c ? action_id_r : 2'd0;
  logic [47:0] p_smac_c;
  assign p_smac_c = hit_c ? p_r_smac : 48'b0;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      hit <= 1'b0;
    end else begin
      hit <= hit_c;
      action_id <= action_id_c;
      p_smac <= p_smac_c;
    end
  end

  // Action ID encoding:
  //   0 = NoAction
  //   1 = rewrite_mac
  //   2 = drop

endmodule
