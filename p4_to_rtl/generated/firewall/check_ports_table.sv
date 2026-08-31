module check_ports_table #(
  parameter int DEPTH = 1024
) (
  input  logic clk,
  input  logic rst_n,

  // Lookup key (combinational)
  input  logic [8:0] lkp_ingress_port,
  input  logic [8:0] lkp_egress_spec,

  // Lookup result (registered — 1 cycle after lkp_* is presented)
  output logic        hit,
  output logic [0:0] action_id,
  output logic [0:0] p_dir,

  // Control-plane write port (synchronous)
  input  logic        cp_wr_en,
  input  logic [9:0] cp_wr_idx,  // unused: exact-match tables self-address via hash(key)
  input  logic [8:0] cp_wr_key_ingress_port,
  input  logic [8:0] cp_wr_key_egress_spec,
  input  logic [0:0] cp_wr_action,
  input  logic [0:0] cp_wr_p_dir
);

  // Entry storage (synthesizes to block RAM)
  logic        mem_valid  [0:DEPTH-1];
  logic [8:0] mem_key_ingress_port[0:DEPTH-1];
  logic [8:0] mem_key_egress_spec[0:DEPTH-1];
  logic [0:0] mem_action[0:DEPTH-1];
  logic [0:0] mem_p_dir[0:DEPTH-1];

  integer _i;
  `ifndef SYNTHESIS
  // synthesis translate_off
  initial begin
    for (_i = 0; _i < DEPTH; _i = _i + 1)
      mem_valid[_i] = 1'b0;
  end
  // synthesis translate_on
  `endif

  // XOR-fold hash: 18-bit key -> 10-bit BRAM address
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
  assign wr_key_concat = {2'd0, cp_wr_key_egress_spec, cp_wr_key_ingress_port};
  logic [9:0] wr_addr;
  assign wr_addr = hash_key(wr_key_concat);

  logic [19:0] lkp_key_concat;
  assign lkp_key_concat = {2'd0, lkp_egress_spec, lkp_ingress_port};
  logic [9:0] lkp_addr;
  assign lkp_addr = hash_key(lkp_key_concat);

  // Synchronous write (control plane)
  always_ff @(posedge clk) begin
    if (cp_wr_en) begin
      mem_valid[wr_addr]  <= 1'b1;
      mem_key_ingress_port[wr_addr] <= cp_wr_key_ingress_port;
      mem_key_egress_spec[wr_addr] <= cp_wr_key_egress_spec;
      mem_action[wr_addr] <= cp_wr_action;
      mem_p_dir[wr_addr] <= cp_wr_p_dir;
    end
  end

  // Registered BRAM read + tag-compare stage (1-cycle lookup latency)
  logic        valid_r;
  logic [8:0] key_r_ingress_port;
  logic [8:0] mem_key_r_ingress_port;
  logic [8:0] key_r_egress_spec;
  logic [8:0] mem_key_r_egress_spec;
  logic [0:0] action_id_r;
  logic [0:0] p_r_dir;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      valid_r <= 1'b0;
    end else begin
      valid_r     <= mem_valid[lkp_addr];
      key_r_ingress_port     <= lkp_ingress_port;
      mem_key_r_ingress_port <= mem_key_ingress_port[lkp_addr];
      key_r_egress_spec     <= lkp_egress_spec;
      mem_key_r_egress_spec <= mem_key_egress_spec[lkp_addr];
      action_id_r <= mem_action[lkp_addr];
      p_r_dir <= mem_p_dir[lkp_addr];
    end
  end

  logic hit_c; assign hit_c = valid_r && (mem_key_r_ingress_port == key_r_ingress_port) && (mem_key_r_egress_spec == key_r_egress_spec);
  logic [0:0] action_id_c;
  assign action_id_c = hit_c ? action_id_r : 1'd0;
  logic [0:0] p_dir_c;
  assign p_dir_c = hit_c ? p_r_dir : 1'b0;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      hit <= 1'b0;
    end else begin
      hit <= hit_c;
      action_id <= action_id_c;
      p_dir <= p_dir_c;
    end
  end

  // Action ID encoding:
  //   0 = NoAction
  //   1 = set_direction

endmodule
