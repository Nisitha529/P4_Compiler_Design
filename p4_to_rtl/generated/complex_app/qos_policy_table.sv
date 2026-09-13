module qos_policy_table #(
  parameter int DEPTH = 256
) (
  input  logic clk,
  input  logic rst_n,

  // Lookup key (combinational)
  input  logic [7:0] lkp_diffserv,
  input  logic [7:0] lkp_flags,

  // Lookup result
  output logic        hit,
  output logic [0:0] action_id,
  output logic [2:0] p_prio,

  // Control-plane write port (synchronous)
  input  logic        cp_wr_en,
  input  logic [7:0] cp_wr_idx,
  input  logic [7:0] cp_wr_key_diffserv,
  input  logic [7:0] cp_wr_key_flags,
  input  logic [7:0] cp_wr_mask_diffserv,
  input  logic [7:0] cp_wr_mask_flags,
  input  logic [0:0] cp_wr_action,
  input  logic [2:0] cp_wr_p_prio
);

  // Entry storage
  logic        mem_valid  [0:DEPTH-1];
  logic [7:0] mem_key_diffserv[0:DEPTH-1];
  logic [7:0] mem_key_flags[0:DEPTH-1];
  logic [7:0] mem_mask_diffserv[0:DEPTH-1];
  logic [7:0] mem_mask_flags[0:DEPTH-1];
  logic [0:0] mem_action[0:DEPTH-1];
  logic [2:0] mem_p_prio[0:DEPTH-1];

  integer _i;
  `ifndef SYNTHESIS
  // synthesis translate_off
  initial begin
    for (_i = 0; _i < DEPTH; _i = _i + 1)
      mem_valid[_i] = 1'b0;
  end
  // synthesis translate_on
  `endif

  always_ff @(posedge clk) begin
    if (cp_wr_en) begin
      mem_valid[cp_wr_idx]  <= 1'b1;
      mem_key_diffserv[cp_wr_idx] <= cp_wr_key_diffserv;
      mem_key_flags[cp_wr_idx] <= cp_wr_key_flags;
      mem_mask_diffserv[cp_wr_idx] <= cp_wr_mask_diffserv;
      mem_mask_flags[cp_wr_idx] <= cp_wr_mask_flags;
      mem_action[cp_wr_idx] <= cp_wr_action;
      mem_p_prio[cp_wr_idx] <= cp_wr_p_prio;
    end
  end

  // Priority-match reduction: balanced binary tree (log2(DEPTH) levels)
  // instead of a serial DEPTH-deep priority chain. Lowest index still wins.
  logic        hit_l0_c[0:255];
  logic [0:0] act_l0_c[0:255];
  logic [2:0] p_prio_l0_c[0:255];

  integer _cj;
  always_comb begin
    for (_cj = 0; _cj < DEPTH; _cj = _cj + 1) begin
      hit_l0_c[_cj] = mem_valid[_cj] && ((lkp_diffserv & mem_mask_diffserv[_cj]) == (mem_key_diffserv[_cj] & mem_mask_diffserv[_cj])) && ((lkp_flags & mem_mask_flags[_cj]) == (mem_key_flags[_cj] & mem_mask_flags[_cj]));
      act_l0_c[_cj] = mem_action[_cj];
      p_prio_l0_c[_cj] = mem_p_prio[_cj];
    end
  end

  logic        hit_l0[0:255];
  logic [0:0] act_l0[0:255];
  logic [2:0] p_prio_l0[0:255];
  integer _rj;
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      for (_rj = 0; _rj < DEPTH; _rj = _rj + 1)
        hit_l0[_rj] <= 1'b0;
    end else begin
      for (_rj = 0; _rj < DEPTH; _rj = _rj + 1) begin
        hit_l0[_rj] <= hit_l0_c[_rj];
        act_l0[_rj] <= act_l0_c[_rj];
        p_prio_l0[_rj] <= p_prio_l0_c[_rj];
      end
    end
  end

  logic        hit_l1[0:127];
  logic [0:0] act_l1[0:127];
  logic [2:0] p_prio_l1[0:127];
  integer _tj_l1;
  always_comb begin
    for (_tj_l1 = 0; _tj_l1 < 128; _tj_l1 = _tj_l1 + 1) begin
      if (2*_tj_l1+1 < 256) begin
        hit_l1[_tj_l1] = hit_l0[2*_tj_l1] || hit_l0[2*_tj_l1+1];
        act_l1[_tj_l1] = hit_l0[2*_tj_l1] ? act_l0[2*_tj_l1] : act_l0[2*_tj_l1+1];
        p_prio_l1[_tj_l1] = hit_l0[2*_tj_l1] ? p_prio_l0[2*_tj_l1] : p_prio_l0[2*_tj_l1+1];
      end else begin
        hit_l1[_tj_l1] = hit_l0[2*_tj_l1];
        act_l1[_tj_l1] = act_l0[2*_tj_l1];
        p_prio_l1[_tj_l1] = p_prio_l0[2*_tj_l1];
      end
    end
  end

  logic        hit_l2[0:63];
  logic [0:0] act_l2[0:63];
  logic [2:0] p_prio_l2[0:63];
  integer _tj_l2;
  always_comb begin
    for (_tj_l2 = 0; _tj_l2 < 64; _tj_l2 = _tj_l2 + 1) begin
      if (2*_tj_l2+1 < 128) begin
        hit_l2[_tj_l2] = hit_l1[2*_tj_l2] || hit_l1[2*_tj_l2+1];
        act_l2[_tj_l2] = hit_l1[2*_tj_l2] ? act_l1[2*_tj_l2] : act_l1[2*_tj_l2+1];
        p_prio_l2[_tj_l2] = hit_l1[2*_tj_l2] ? p_prio_l1[2*_tj_l2] : p_prio_l1[2*_tj_l2+1];
      end else begin
        hit_l2[_tj_l2] = hit_l1[2*_tj_l2];
        act_l2[_tj_l2] = act_l1[2*_tj_l2];
        p_prio_l2[_tj_l2] = p_prio_l1[2*_tj_l2];
      end
    end
  end

  logic        hit_l3[0:31];
  logic [0:0] act_l3[0:31];
  logic [2:0] p_prio_l3[0:31];
  integer _tj_l3;
  always_comb begin
    for (_tj_l3 = 0; _tj_l3 < 32; _tj_l3 = _tj_l3 + 1) begin
      if (2*_tj_l3+1 < 64) begin
        hit_l3[_tj_l3] = hit_l2[2*_tj_l3] || hit_l2[2*_tj_l3+1];
        act_l3[_tj_l3] = hit_l2[2*_tj_l3] ? act_l2[2*_tj_l3] : act_l2[2*_tj_l3+1];
        p_prio_l3[_tj_l3] = hit_l2[2*_tj_l3] ? p_prio_l2[2*_tj_l3] : p_prio_l2[2*_tj_l3+1];
      end else begin
        hit_l3[_tj_l3] = hit_l2[2*_tj_l3];
        act_l3[_tj_l3] = act_l2[2*_tj_l3];
        p_prio_l3[_tj_l3] = p_prio_l2[2*_tj_l3];
      end
    end
  end

  logic        hit_l4[0:15];
  logic [0:0] act_l4[0:15];
  logic [2:0] p_prio_l4[0:15];
  integer _tj_l4;
  always_comb begin
    for (_tj_l4 = 0; _tj_l4 < 16; _tj_l4 = _tj_l4 + 1) begin
      if (2*_tj_l4+1 < 32) begin
        hit_l4[_tj_l4] = hit_l3[2*_tj_l4] || hit_l3[2*_tj_l4+1];
        act_l4[_tj_l4] = hit_l3[2*_tj_l4] ? act_l3[2*_tj_l4] : act_l3[2*_tj_l4+1];
        p_prio_l4[_tj_l4] = hit_l3[2*_tj_l4] ? p_prio_l3[2*_tj_l4] : p_prio_l3[2*_tj_l4+1];
      end else begin
        hit_l4[_tj_l4] = hit_l3[2*_tj_l4];
        act_l4[_tj_l4] = act_l3[2*_tj_l4];
        p_prio_l4[_tj_l4] = p_prio_l3[2*_tj_l4];
      end
    end
  end

  logic        hit_l5[0:7];
  logic [0:0] act_l5[0:7];
  logic [2:0] p_prio_l5[0:7];
  integer _tj_l5;
  always_comb begin
    for (_tj_l5 = 0; _tj_l5 < 8; _tj_l5 = _tj_l5 + 1) begin
      if (2*_tj_l5+1 < 16) begin
        hit_l5[_tj_l5] = hit_l4[2*_tj_l5] || hit_l4[2*_tj_l5+1];
        act_l5[_tj_l5] = hit_l4[2*_tj_l5] ? act_l4[2*_tj_l5] : act_l4[2*_tj_l5+1];
        p_prio_l5[_tj_l5] = hit_l4[2*_tj_l5] ? p_prio_l4[2*_tj_l5] : p_prio_l4[2*_tj_l5+1];
      end else begin
        hit_l5[_tj_l5] = hit_l4[2*_tj_l5];
        act_l5[_tj_l5] = act_l4[2*_tj_l5];
        p_prio_l5[_tj_l5] = p_prio_l4[2*_tj_l5];
      end
    end
  end

  logic        hit_l6[0:3];
  logic [0:0] act_l6[0:3];
  logic [2:0] p_prio_l6[0:3];
  integer _tj_l6;
  always_comb begin
    for (_tj_l6 = 0; _tj_l6 < 4; _tj_l6 = _tj_l6 + 1) begin
      if (2*_tj_l6+1 < 8) begin
        hit_l6[_tj_l6] = hit_l5[2*_tj_l6] || hit_l5[2*_tj_l6+1];
        act_l6[_tj_l6] = hit_l5[2*_tj_l6] ? act_l5[2*_tj_l6] : act_l5[2*_tj_l6+1];
        p_prio_l6[_tj_l6] = hit_l5[2*_tj_l6] ? p_prio_l5[2*_tj_l6] : p_prio_l5[2*_tj_l6+1];
      end else begin
        hit_l6[_tj_l6] = hit_l5[2*_tj_l6];
        act_l6[_tj_l6] = act_l5[2*_tj_l6];
        p_prio_l6[_tj_l6] = p_prio_l5[2*_tj_l6];
      end
    end
  end

  logic        hit_l7[0:1];
  logic [0:0] act_l7[0:1];
  logic [2:0] p_prio_l7[0:1];
  integer _tj_l7;
  always_comb begin
    for (_tj_l7 = 0; _tj_l7 < 2; _tj_l7 = _tj_l7 + 1) begin
      if (2*_tj_l7+1 < 4) begin
        hit_l7[_tj_l7] = hit_l6[2*_tj_l7] || hit_l6[2*_tj_l7+1];
        act_l7[_tj_l7] = hit_l6[2*_tj_l7] ? act_l6[2*_tj_l7] : act_l6[2*_tj_l7+1];
        p_prio_l7[_tj_l7] = hit_l6[2*_tj_l7] ? p_prio_l6[2*_tj_l7] : p_prio_l6[2*_tj_l7+1];
      end else begin
        hit_l7[_tj_l7] = hit_l6[2*_tj_l7];
        act_l7[_tj_l7] = act_l6[2*_tj_l7];
        p_prio_l7[_tj_l7] = p_prio_l6[2*_tj_l7];
      end
    end
  end

  logic        hit_l8[0:0];
  logic [0:0] act_l8[0:0];
  logic [2:0] p_prio_l8[0:0];
  integer _tj_l8;
  always_comb begin
    for (_tj_l8 = 0; _tj_l8 < 1; _tj_l8 = _tj_l8 + 1) begin
      if (2*_tj_l8+1 < 2) begin
        hit_l8[_tj_l8] = hit_l7[2*_tj_l8] || hit_l7[2*_tj_l8+1];
        act_l8[_tj_l8] = hit_l7[2*_tj_l8] ? act_l7[2*_tj_l8] : act_l7[2*_tj_l8+1];
        p_prio_l8[_tj_l8] = hit_l7[2*_tj_l8] ? p_prio_l7[2*_tj_l8] : p_prio_l7[2*_tj_l8+1];
      end else begin
        hit_l8[_tj_l8] = hit_l7[2*_tj_l8];
        act_l8[_tj_l8] = act_l7[2*_tj_l8];
        p_prio_l8[_tj_l8] = p_prio_l7[2*_tj_l8];
      end
    end
  end

  logic hit_c;
  logic [0:0] action_id_c;
  logic [2:0] p_prio_c;
  always_comb begin
    hit_c = hit_l8[0];
    action_id_c = hit_l8[0] ? act_l8[0] : 1'd0;
    p_prio_c = hit_l8[0] ? p_prio_l8[0] : 3'b0;
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      hit <= 1'b0;
    end else begin
      hit <= hit_c;
      action_id <= action_id_c;
      p_prio <= p_prio_c;
    end
  end

  // Action ID encoding:
  //   0 = NoAction
  //   1 = set_priority

endmodule
