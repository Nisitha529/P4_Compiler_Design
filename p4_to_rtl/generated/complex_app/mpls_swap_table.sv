module mpls_swap_table #(
  parameter int DEPTH = 512
) (
  input  logic clk,
  input  logic rst_n,

  // Lookup key (combinational)
  input  logic [19:0] lkp_key_0,

  // Lookup result (registered — 1 cycle after lkp_* is presented)
  output logic        hit,
  output logic [1:0] action_id,
  output logic [19:0] p_new_label,
  output logic [19:0] p_label,

  // Control-plane write port (synchronous)
  input  logic        cp_wr_en,
  input  logic [8:0] cp_wr_idx,  // unused: exact-match tables self-address via hash(key)
  input  logic [19:0] cp_wr_key_key_0,
  input  logic [1:0] cp_wr_action,
  input  logic [19:0] cp_wr_p_new_label,
  input  logic [19:0] cp_wr_p_label
);

  // Entry storage (synthesizes to block RAM)
  logic        mem_valid  [0:DEPTH-1];
  logic [19:0] mem_key_key_0[0:DEPTH-1];
  logic [1:0] mem_action[0:DEPTH-1];
  logic [19:0] mem_p_new_label[0:DEPTH-1];
  logic [19:0] mem_p_label[0:DEPTH-1];

  integer _i;
  `ifndef SYNTHESIS
  // synthesis translate_off
  initial begin
    for (_i = 0; _i < DEPTH; _i = _i + 1)
      mem_valid[_i] = 1'b0;
  end
  // synthesis translate_on
  `endif

  // XOR-fold hash: 20-bit key -> 9-bit BRAM address
  function automatic logic [8:0] hash_key(input logic [26:0] k);
    logic [8:0] h;
    integer c;
    begin
      h = '0;
      for (c = 0; c < 3; c = c + 1)
        h = h ^ k[c*9 +: 9];
      hash_key = h;
    end
  endfunction

  logic [26:0] wr_key_concat;
  assign wr_key_concat = {7'd0, cp_wr_key_key_0};
  logic [8:0] wr_addr;
  assign wr_addr = hash_key(wr_key_concat);

  logic [26:0] lkp_key_concat;
  assign lkp_key_concat = {7'd0, lkp_key_0};
  logic [8:0] lkp_addr;
  assign lkp_addr = hash_key(lkp_key_concat);

  // Synchronous write (control plane)
  always_ff @(posedge clk) begin
    if (cp_wr_en) begin
      mem_valid[wr_addr]  <= 1'b1;
      mem_key_key_0[wr_addr] <= cp_wr_key_key_0;
      mem_action[wr_addr] <= cp_wr_action;
      mem_p_new_label[wr_addr] <= cp_wr_p_new_label;
      mem_p_label[wr_addr] <= cp_wr_p_label;
    end
  end

  // Registered BRAM read + tag-compare stage (1-cycle lookup latency)
  logic        valid_r;
  logic [19:0] key_r_key_0;
  logic [19:0] mem_key_r_key_0;
  logic [1:0] action_id_r;
  logic [19:0] p_r_new_label;
  logic [19:0] p_r_label;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      valid_r <= 1'b0;
    end else begin
      valid_r     <= mem_valid[lkp_addr];
      key_r_key_0     <= lkp_key_0;
      mem_key_r_key_0 <= mem_key_key_0[lkp_addr];
      action_id_r <= mem_action[lkp_addr];
      p_r_new_label <= mem_p_new_label[lkp_addr];
      p_r_label <= mem_p_label[lkp_addr];
    end
  end

  logic hit_c; assign hit_c = valid_r && (mem_key_r_key_0 == key_r_key_0);
  logic [1:0] action_id_c;
  assign action_id_c = hit_c ? action_id_r : 2'd0;
  logic [19:0] p_new_label_c;
  assign p_new_label_c = hit_c ? p_r_new_label : 20'b0;
  logic [19:0] p_label_c;
  assign p_label_c = hit_c ? p_r_label : 20'b0;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      hit <= 1'b0;
    end else begin
      hit <= hit_c;
      action_id <= action_id_c;
      p_new_label <= p_new_label_c;
      p_label <= p_label_c;
    end
  end

  // Action ID encoding:
  //   0 = NoAction
  //   1 = swap_label
  //   2 = push_mpls
  //   3 = pop_mpls

endmodule
