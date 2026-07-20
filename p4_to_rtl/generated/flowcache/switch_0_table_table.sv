module switch_0_table_table #(
  parameter int DEPTH = 1
) (
  input  logic clk,
  input  logic rst_n,

  // Lookup key (combinational)
  input  logic [7:0] lkp_switch_0_key,

  // Lookup result (registered — 1 cycle after lkp_* is presented)
  output logic        hit,
  output logic [1:0] action_id,

  // Control-plane write port (synchronous)
  input  logic        cp_wr_en,
  input  logic [0:0] cp_wr_idx,  // unused: exact-match tables self-address via hash(key)
  input  logic [7:0] cp_wr_key_switch_0_key,
  input  logic [1:0] cp_wr_action
);

  // Entry storage (synthesizes to block RAM)
  logic        mem_valid  [0:DEPTH-1];
  logic [7:0] mem_key_switch_0_key[0:DEPTH-1];
  logic [1:0] mem_action[0:DEPTH-1];

  integer _i;
  initial begin
    for (_i = 0; _i < DEPTH; _i = _i + 1)
      mem_valid[_i] = 1'b0;
  end

  // XOR-fold hash: 8-bit key -> 1-bit BRAM address
  function automatic logic [0:0] hash_key(input logic [7:0] k);
    logic [0:0] h;
    integer c;
    begin
      h = '0;
      for (c = 0; c < 8; c = c + 1)
        h = h ^ k[c*1 +: 1];
      hash_key = h;
    end
  endfunction

  logic [7:0] wr_key_concat;
  assign wr_key_concat = {cp_wr_key_switch_0_key};
  logic [0:0] wr_addr;
  assign wr_addr = hash_key(wr_key_concat);

  logic [7:0] lkp_key_concat;
  assign lkp_key_concat = {lkp_switch_0_key};
  logic [0:0] lkp_addr;
  assign lkp_addr = hash_key(lkp_key_concat);

  // Synchronous write (control plane)
  always_ff @(posedge clk) begin
    if (cp_wr_en) begin
      mem_valid[wr_addr]  <= 1'b1;
      mem_key_switch_0_key[wr_addr] <= cp_wr_key_switch_0_key;
      mem_action[wr_addr] <= cp_wr_action;
    end
  end

  // Registered BRAM read + tag-compare stage (1-cycle lookup latency)
  logic        valid_r;
  logic [7:0] key_r_switch_0_key;
  logic [7:0] mem_key_r_switch_0_key;
  logic [1:0] action_id_r;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      valid_r <= 1'b0;
    end else begin
      valid_r     <= mem_valid[lkp_addr];
      key_r_switch_0_key     <= lkp_switch_0_key;
      mem_key_r_switch_0_key <= mem_key_switch_0_key[lkp_addr];
      action_id_r <= mem_action[lkp_addr];
    end
  end

  assign hit       = valid_r && (mem_key_r_switch_0_key == key_r_switch_0_key);
  assign action_id = hit ? action_id_r : 2'd2;

  // Action ID encoding:
  //   0 = NoAction
  //   1 = switch_0_case
  //   2 = switch_0_case_0

endmodule
