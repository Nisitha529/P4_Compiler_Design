module ecmp_group_table #(
  parameter int DEPTH = 256
) (
  input  logic clk,
  input  logic rst_n,

  // Lookup key (combinational)
  input  logic [31:0] lkp_dstAddr,

  // Lookup result
  output logic        hit,
  output logic [1:0] action_id,
  output logic [15:0] p_ecmp_base,
  output logic [31:0] p_ecmp_count,

  // Control-plane write port (synchronous)
  input  logic        cp_wr_en,
  input  logic [7:0] cp_wr_idx,
  input  logic [31:0] cp_wr_key_dstAddr,
  input  logic [5:0] cp_wr_pfx_len,
  input  logic [1:0] cp_wr_action,
  input  logic [15:0] cp_wr_p_ecmp_base,
  input  logic [31:0] cp_wr_p_ecmp_count
);

  // Entry storage
  logic        mem_valid  [0:DEPTH-1];
  logic [31:0] mem_key_dstAddr[0:DEPTH-1];
  logic [31:0] mem_pfx_mask_dstAddr[0:DEPTH-1];
  logic [1:0] mem_action[0:DEPTH-1];
  logic [15:0] mem_p_ecmp_base[0:DEPTH-1];
  logic [31:0] mem_p_ecmp_count[0:DEPTH-1];

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
      mem_key_dstAddr[cp_wr_idx] <= cp_wr_key_dstAddr;
      mem_pfx_mask_dstAddr[cp_wr_idx] <= (cp_wr_pfx_len == 6'd0) ? 32'd0 : ({32{1'b1}} << (32 - cp_wr_pfx_len));
      mem_action[cp_wr_idx] <= cp_wr_action;
      mem_p_ecmp_base[cp_wr_idx] <= cp_wr_p_ecmp_base;
      mem_p_ecmp_count[cp_wr_idx] <= cp_wr_p_ecmp_count;
    end
  end

  // Priority-match reduction: balanced binary tree (log2(DEPTH) levels)
  // instead of a serial DEPTH-deep priority chain. Lowest index still wins.
  logic        hit_l0_c[0:255];
  logic [1:0] act_l0_c[0:255];
  logic [15:0] p_ecmp_base_l0_c[0:255];
  logic [31:0] p_ecmp_count_l0_c[0:255];

  integer _cj;
  always_comb begin
    for (_cj = 0; _cj < DEPTH; _cj = _cj + 1) begin
      hit_l0_c[_cj] = mem_valid[_cj] && ((lkp_dstAddr & mem_pfx_mask_dstAddr[_cj]) == (mem_key_dstAddr[_cj] & mem_pfx_mask_dstAddr[_cj]));
      act_l0_c[_cj] = mem_action[_cj];
      p_ecmp_base_l0_c[_cj] = mem_p_ecmp_base[_cj];
      p_ecmp_count_l0_c[_cj] = mem_p_ecmp_count[_cj];
    end
  end

  logic        hit_l0[0:255];
  logic [1:0] act_l0[0:255];
  logic [15:0] p_ecmp_base_l0[0:255];
  logic [31:0] p_ecmp_count_l0[0:255];
  integer _rj;
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      for (_rj = 0; _rj < DEPTH; _rj = _rj + 1)
        hit_l0[_rj] <= 1'b0;
    end else begin
      for (_rj = 0; _rj < DEPTH; _rj = _rj + 1) begin
        hit_l0[_rj] <= hit_l0_c[_rj];
        act_l0[_rj] <= act_l0_c[_rj];
        p_ecmp_base_l0[_rj] <= p_ecmp_base_l0_c[_rj];
        p_ecmp_count_l0[_rj] <= p_ecmp_count_l0_c[_rj];
      end
    end
  end

  logic        hit_l1[0:127];
  logic [1:0] act_l1[0:127];
  logic [15:0] p_ecmp_base_l1[0:127];
  logic [31:0] p_ecmp_count_l1[0:127];
  integer _tj_l1;
  always_comb begin
    for (_tj_l1 = 0; _tj_l1 < 128; _tj_l1 = _tj_l1 + 1) begin
      if (2*_tj_l1+1 < 256) begin
        hit_l1[_tj_l1] = hit_l0[2*_tj_l1] || hit_l0[2*_tj_l1+1];
        act_l1[_tj_l1] = hit_l0[2*_tj_l1] ? act_l0[2*_tj_l1] : act_l0[2*_tj_l1+1];
        p_ecmp_base_l1[_tj_l1] = hit_l0[2*_tj_l1] ? p_ecmp_base_l0[2*_tj_l1] : p_ecmp_base_l0[2*_tj_l1+1];
        p_ecmp_count_l1[_tj_l1] = hit_l0[2*_tj_l1] ? p_ecmp_count_l0[2*_tj_l1] : p_ecmp_count_l0[2*_tj_l1+1];
      end else begin
        hit_l1[_tj_l1] = hit_l0[2*_tj_l1];
        act_l1[_tj_l1] = act_l0[2*_tj_l1];
        p_ecmp_base_l1[_tj_l1] = p_ecmp_base_l0[2*_tj_l1];
        p_ecmp_count_l1[_tj_l1] = p_ecmp_count_l0[2*_tj_l1];
      end
    end
  end

  logic        hit_l2[0:63];
  logic [1:0] act_l2[0:63];
  logic [15:0] p_ecmp_base_l2[0:63];
  logic [31:0] p_ecmp_count_l2[0:63];
  integer _tj_l2;
  always_comb begin
    for (_tj_l2 = 0; _tj_l2 < 64; _tj_l2 = _tj_l2 + 1) begin
      if (2*_tj_l2+1 < 128) begin
        hit_l2[_tj_l2] = hit_l1[2*_tj_l2] || hit_l1[2*_tj_l2+1];
        act_l2[_tj_l2] = hit_l1[2*_tj_l2] ? act_l1[2*_tj_l2] : act_l1[2*_tj_l2+1];
        p_ecmp_base_l2[_tj_l2] = hit_l1[2*_tj_l2] ? p_ecmp_base_l1[2*_tj_l2] : p_ecmp_base_l1[2*_tj_l2+1];
        p_ecmp_count_l2[_tj_l2] = hit_l1[2*_tj_l2] ? p_ecmp_count_l1[2*_tj_l2] : p_ecmp_count_l1[2*_tj_l2+1];
      end else begin
        hit_l2[_tj_l2] = hit_l1[2*_tj_l2];
        act_l2[_tj_l2] = act_l1[2*_tj_l2];
        p_ecmp_base_l2[_tj_l2] = p_ecmp_base_l1[2*_tj_l2];
        p_ecmp_count_l2[_tj_l2] = p_ecmp_count_l1[2*_tj_l2];
      end
    end
  end

  logic        hit_l3[0:31];
  logic [1:0] act_l3[0:31];
  logic [15:0] p_ecmp_base_l3[0:31];
  logic [31:0] p_ecmp_count_l3[0:31];
  integer _tj_l3;
  always_comb begin
    for (_tj_l3 = 0; _tj_l3 < 32; _tj_l3 = _tj_l3 + 1) begin
      if (2*_tj_l3+1 < 64) begin
        hit_l3[_tj_l3] = hit_l2[2*_tj_l3] || hit_l2[2*_tj_l3+1];
        act_l3[_tj_l3] = hit_l2[2*_tj_l3] ? act_l2[2*_tj_l3] : act_l2[2*_tj_l3+1];
        p_ecmp_base_l3[_tj_l3] = hit_l2[2*_tj_l3] ? p_ecmp_base_l2[2*_tj_l3] : p_ecmp_base_l2[2*_tj_l3+1];
        p_ecmp_count_l3[_tj_l3] = hit_l2[2*_tj_l3] ? p_ecmp_count_l2[2*_tj_l3] : p_ecmp_count_l2[2*_tj_l3+1];
      end else begin
        hit_l3[_tj_l3] = hit_l2[2*_tj_l3];
        act_l3[_tj_l3] = act_l2[2*_tj_l3];
        p_ecmp_base_l3[_tj_l3] = p_ecmp_base_l2[2*_tj_l3];
        p_ecmp_count_l3[_tj_l3] = p_ecmp_count_l2[2*_tj_l3];
      end
    end
  end

  logic        hit_l4[0:15];
  logic [1:0] act_l4[0:15];
  logic [15:0] p_ecmp_base_l4[0:15];
  logic [31:0] p_ecmp_count_l4[0:15];
  integer _tj_l4;
  always_comb begin
    for (_tj_l4 = 0; _tj_l4 < 16; _tj_l4 = _tj_l4 + 1) begin
      if (2*_tj_l4+1 < 32) begin
        hit_l4[_tj_l4] = hit_l3[2*_tj_l4] || hit_l3[2*_tj_l4+1];
        act_l4[_tj_l4] = hit_l3[2*_tj_l4] ? act_l3[2*_tj_l4] : act_l3[2*_tj_l4+1];
        p_ecmp_base_l4[_tj_l4] = hit_l3[2*_tj_l4] ? p_ecmp_base_l3[2*_tj_l4] : p_ecmp_base_l3[2*_tj_l4+1];
        p_ecmp_count_l4[_tj_l4] = hit_l3[2*_tj_l4] ? p_ecmp_count_l3[2*_tj_l4] : p_ecmp_count_l3[2*_tj_l4+1];
      end else begin
        hit_l4[_tj_l4] = hit_l3[2*_tj_l4];
        act_l4[_tj_l4] = act_l3[2*_tj_l4];
        p_ecmp_base_l4[_tj_l4] = p_ecmp_base_l3[2*_tj_l4];
        p_ecmp_count_l4[_tj_l4] = p_ecmp_count_l3[2*_tj_l4];
      end
    end
  end

  logic        hit_l5[0:7];
  logic [1:0] act_l5[0:7];
  logic [15:0] p_ecmp_base_l5[0:7];
  logic [31:0] p_ecmp_count_l5[0:7];
  integer _tj_l5;
  always_comb begin
    for (_tj_l5 = 0; _tj_l5 < 8; _tj_l5 = _tj_l5 + 1) begin
      if (2*_tj_l5+1 < 16) begin
        hit_l5[_tj_l5] = hit_l4[2*_tj_l5] || hit_l4[2*_tj_l5+1];
        act_l5[_tj_l5] = hit_l4[2*_tj_l5] ? act_l4[2*_tj_l5] : act_l4[2*_tj_l5+1];
        p_ecmp_base_l5[_tj_l5] = hit_l4[2*_tj_l5] ? p_ecmp_base_l4[2*_tj_l5] : p_ecmp_base_l4[2*_tj_l5+1];
        p_ecmp_count_l5[_tj_l5] = hit_l4[2*_tj_l5] ? p_ecmp_count_l4[2*_tj_l5] : p_ecmp_count_l4[2*_tj_l5+1];
      end else begin
        hit_l5[_tj_l5] = hit_l4[2*_tj_l5];
        act_l5[_tj_l5] = act_l4[2*_tj_l5];
        p_ecmp_base_l5[_tj_l5] = p_ecmp_base_l4[2*_tj_l5];
        p_ecmp_count_l5[_tj_l5] = p_ecmp_count_l4[2*_tj_l5];
      end
    end
  end

  logic        hit_l6[0:3];
  logic [1:0] act_l6[0:3];
  logic [15:0] p_ecmp_base_l6[0:3];
  logic [31:0] p_ecmp_count_l6[0:3];
  integer _tj_l6;
  always_comb begin
    for (_tj_l6 = 0; _tj_l6 < 4; _tj_l6 = _tj_l6 + 1) begin
      if (2*_tj_l6+1 < 8) begin
        hit_l6[_tj_l6] = hit_l5[2*_tj_l6] || hit_l5[2*_tj_l6+1];
        act_l6[_tj_l6] = hit_l5[2*_tj_l6] ? act_l5[2*_tj_l6] : act_l5[2*_tj_l6+1];
        p_ecmp_base_l6[_tj_l6] = hit_l5[2*_tj_l6] ? p_ecmp_base_l5[2*_tj_l6] : p_ecmp_base_l5[2*_tj_l6+1];
        p_ecmp_count_l6[_tj_l6] = hit_l5[2*_tj_l6] ? p_ecmp_count_l5[2*_tj_l6] : p_ecmp_count_l5[2*_tj_l6+1];
      end else begin
        hit_l6[_tj_l6] = hit_l5[2*_tj_l6];
        act_l6[_tj_l6] = act_l5[2*_tj_l6];
        p_ecmp_base_l6[_tj_l6] = p_ecmp_base_l5[2*_tj_l6];
        p_ecmp_count_l6[_tj_l6] = p_ecmp_count_l5[2*_tj_l6];
      end
    end
  end

  logic        hit_l7[0:1];
  logic [1:0] act_l7[0:1];
  logic [15:0] p_ecmp_base_l7[0:1];
  logic [31:0] p_ecmp_count_l7[0:1];
  integer _tj_l7;
  always_comb begin
    for (_tj_l7 = 0; _tj_l7 < 2; _tj_l7 = _tj_l7 + 1) begin
      if (2*_tj_l7+1 < 4) begin
        hit_l7[_tj_l7] = hit_l6[2*_tj_l7] || hit_l6[2*_tj_l7+1];
        act_l7[_tj_l7] = hit_l6[2*_tj_l7] ? act_l6[2*_tj_l7] : act_l6[2*_tj_l7+1];
        p_ecmp_base_l7[_tj_l7] = hit_l6[2*_tj_l7] ? p_ecmp_base_l6[2*_tj_l7] : p_ecmp_base_l6[2*_tj_l7+1];
        p_ecmp_count_l7[_tj_l7] = hit_l6[2*_tj_l7] ? p_ecmp_count_l6[2*_tj_l7] : p_ecmp_count_l6[2*_tj_l7+1];
      end else begin
        hit_l7[_tj_l7] = hit_l6[2*_tj_l7];
        act_l7[_tj_l7] = act_l6[2*_tj_l7];
        p_ecmp_base_l7[_tj_l7] = p_ecmp_base_l6[2*_tj_l7];
        p_ecmp_count_l7[_tj_l7] = p_ecmp_count_l6[2*_tj_l7];
      end
    end
  end

  logic        hit_l8[0:0];
  logic [1:0] act_l8[0:0];
  logic [15:0] p_ecmp_base_l8[0:0];
  logic [31:0] p_ecmp_count_l8[0:0];
  integer _tj_l8;
  always_comb begin
    for (_tj_l8 = 0; _tj_l8 < 1; _tj_l8 = _tj_l8 + 1) begin
      if (2*_tj_l8+1 < 2) begin
        hit_l8[_tj_l8] = hit_l7[2*_tj_l8] || hit_l7[2*_tj_l8+1];
        act_l8[_tj_l8] = hit_l7[2*_tj_l8] ? act_l7[2*_tj_l8] : act_l7[2*_tj_l8+1];
        p_ecmp_base_l8[_tj_l8] = hit_l7[2*_tj_l8] ? p_ecmp_base_l7[2*_tj_l8] : p_ecmp_base_l7[2*_tj_l8+1];
        p_ecmp_count_l8[_tj_l8] = hit_l7[2*_tj_l8] ? p_ecmp_count_l7[2*_tj_l8] : p_ecmp_count_l7[2*_tj_l8+1];
      end else begin
        hit_l8[_tj_l8] = hit_l7[2*_tj_l8];
        act_l8[_tj_l8] = act_l7[2*_tj_l8];
        p_ecmp_base_l8[_tj_l8] = p_ecmp_base_l7[2*_tj_l8];
        p_ecmp_count_l8[_tj_l8] = p_ecmp_count_l7[2*_tj_l8];
      end
    end
  end

  logic hit_c;
  logic [1:0] action_id_c;
  logic [15:0] p_ecmp_base_c;
  logic [31:0] p_ecmp_count_c;
  always_comb begin
    hit_c = hit_l8[0];
    action_id_c = hit_l8[0] ? act_l8[0] : 2'd0;
    p_ecmp_base_c = hit_l8[0] ? p_ecmp_base_l8[0] : 16'b0;
    p_ecmp_count_c = hit_l8[0] ? p_ecmp_count_l8[0] : 32'b0;
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      hit <= 1'b0;
    end else begin
      hit <= hit_c;
      action_id <= action_id_c;
      p_ecmp_base <= p_ecmp_base_c;
      p_ecmp_count <= p_ecmp_count_c;
    end
  end

  // Action ID encoding:
  //   0 = NoAction
  //   1 = drop
  //   2 = set_ecmp_select

endmodule
