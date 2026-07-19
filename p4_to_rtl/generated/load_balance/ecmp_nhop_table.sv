module ecmp_nhop_table #(
  parameter int DEPTH = 2
) (
  input  logic clk,
  input  logic rst_n,

  // Lookup key (combinational)
  input  logic [31:0] lkp_ecmp_select,

  // Lookup result (registered — 1 cycle after lkp_* is presented)
  output logic        hit,
  output logic [1:0] action_id,
  output logic [47:0] p_nhop_dmac,
  output logic [31:0] p_nhop_ipv4,
  output logic [8:0] p_port,

  // Control-plane write port (synchronous)
  input  logic        cp_wr_en,
  input  logic [0:0] cp_wr_idx,  // unused: exact-match tables self-address via hash(key)
  input  logic [31:0] cp_wr_key_ecmp_select,
  input  logic [1:0] cp_wr_action,
  input  logic [47:0] cp_wr_p_nhop_dmac,
  input  logic [31:0] cp_wr_p_nhop_ipv4,
  input  logic [8:0] cp_wr_p_port
);

  // Entry storage (synthesizes to block RAM)
  logic        mem_valid  [0:DEPTH-1];
  logic [31:0] mem_key_ecmp_select[0:DEPTH-1];
  logic [1:0] mem_action[0:DEPTH-1];
  logic [47:0] mem_p_nhop_dmac[0:DEPTH-1];
  logic [31:0] mem_p_nhop_ipv4[0:DEPTH-1];
  logic [8:0] mem_p_port[0:DEPTH-1];

  integer _i;
  initial begin
    for (_i = 0; _i < DEPTH; _i = _i + 1)
      mem_valid[_i] = 1'b0;
  end

  // XOR-fold hash: 32-bit key -> 1-bit BRAM address
  function automatic logic [0:0] hash_key(input logic [31:0] k);
    logic [0:0] h;
    integer c;
    begin
      h = '0;
      for (c = 0; c < 32; c = c + 1)
        h = h ^ k[c*1 +: 1];
      hash_key = h;
    end
  endfunction

  logic [31:0] wr_key_concat;
  assign wr_key_concat = {cp_wr_key_ecmp_select};
  logic [0:0] wr_addr;
  assign wr_addr = hash_key(wr_key_concat);

  logic [31:0] lkp_key_concat;
  assign lkp_key_concat = {lkp_ecmp_select};
  logic [0:0] lkp_addr;
  assign lkp_addr = hash_key(lkp_key_concat);

  // Synchronous write (control plane)
  always_ff @(posedge clk) begin
    if (cp_wr_en) begin
      mem_valid[wr_addr]  <= 1'b1;
      mem_key_ecmp_select[wr_addr] <= cp_wr_key_ecmp_select;
      mem_action[wr_addr] <= cp_wr_action;
      mem_p_nhop_dmac[wr_addr] <= cp_wr_p_nhop_dmac;
      mem_p_nhop_ipv4[wr_addr] <= cp_wr_p_nhop_ipv4;
      mem_p_port[wr_addr] <= cp_wr_p_port;
    end
  end

  // Registered BRAM read + tag-compare stage (1-cycle lookup latency)
  logic        valid_r;
  logic [31:0] key_r_ecmp_select;
  logic [31:0] mem_key_r_ecmp_select;
  logic [1:0] action_id_r;
  logic [47:0] p_r_nhop_dmac;
  logic [31:0] p_r_nhop_ipv4;
  logic [8:0] p_r_port;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      valid_r <= 1'b0;
    end else begin
      valid_r     <= mem_valid[lkp_addr];
      key_r_ecmp_select     <= lkp_ecmp_select;
      mem_key_r_ecmp_select <= mem_key_ecmp_select[lkp_addr];
      action_id_r <= mem_action[lkp_addr];
      p_r_nhop_dmac <= mem_p_nhop_dmac[lkp_addr];
      p_r_nhop_ipv4 <= mem_p_nhop_ipv4[lkp_addr];
      p_r_port <= mem_p_port[lkp_addr];
    end
  end

  assign hit       = valid_r && (mem_key_r_ecmp_select == key_r_ecmp_select);
  assign action_id = hit ? action_id_r : 2'd0;
  assign p_nhop_dmac = hit ? p_r_nhop_dmac : 48'b0;
  assign p_nhop_ipv4 = hit ? p_r_nhop_ipv4 : 32'b0;
  assign p_port = hit ? p_r_port : 9'b0;

  // Action ID encoding:
  //   0 = NoAction
  //   1 = drop
  //   2 = set_nhop

endmodule
