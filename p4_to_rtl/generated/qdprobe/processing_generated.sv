module processing_generated (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        valid_in,

  // Header valid flags
  input  logic        eth_valid,

  // Header field inputs
  input  logic [47:0] eth_dst,
  input  logic [47:0] eth_src,
  input  logic [15:0] eth_etype,

  // Metadata inputs
  input  logic [7:0] meta_enqd,
  input  logic [7:0] meta_deqd,

  // Header valid flag outputs (may be modified by setValid/setInvalid)
  output logic        out_eth_valid,

  // Header field outputs (pass-through, optionally modified)
  output logic [47:0] out_eth_dst,
  output logic [47:0] out_eth_src,
  output logic [15:0] out_eth_etype,

  // Standard metadata outputs
  output logic [8:0] out_std_meta_egress_port,

  // Metadata outputs (final value after the last stage)
  output logic [7:0] out_meta_enqd,
  output logic [7:0] out_meta_deqd,

  // Control-plane write ports for table instances
  input  logic        fwd_cp_wr_en,
  input  logic [3:0] fwd_cp_wr_idx,
  input  logic [15:0] fwd_cp_wr_key_etype,
  input  logic [0:0] fwd_cp_wr_action,
  input  logic [8:0] fwd_cp_wr_p_p,

  // Table hit outputs
  output logic        fwd_hit_out,

  // Control-plane query/delete ports (plain exact-match tables)
  input  logic        fwd_cp_query_en,
  input  logic        fwd_cp_query_del,
  input  logic [15:0] fwd_cp_query_key_etype,
  output logic        fwd_cp_query_busy,
  output logic        fwd_cp_query_hit,
  output logic [0:0] fwd_cp_query_action_id,
  output logic [8:0] fwd_cp_query_p_p,

  output logic        out_valid,   // aligned with out_*/drop -- see note
  output logic        valid_out,
  output logic        drop
);

  // Metadata shadow locals (writable copies of metadata inputs)
  logic [7:0] meta_enqd_w;
  logic [7:0] meta_deqd_w;

  // Pipeline-stage forwarding registers (one set per exact-match
  // table boundary in the chain)
  logic valid_s1;
  logic out_eth_valid_s1;
  logic eth_valid_s1;
  logic [47:0] out_eth_dst_s1;
  logic [47:0] eth_dst_s1;
  logic [47:0] out_eth_src_s1;
  logic [47:0] eth_src_s1;
  logic [15:0] out_eth_etype_s1;
  logic [15:0] eth_etype_s1;
  logic [7:0] meta_enqd_w_s1;
  logic [7:0] meta_deqd_w_s1;
  logic [8:0] out_std_meta_egress_port_s1;
  logic drop_s1;
  logic valid_s2;
  logic out_eth_valid_s2;
  logic eth_valid_s2;
  logic [47:0] out_eth_dst_s2;
  logic [47:0] eth_dst_s2;
  logic [47:0] out_eth_src_s2;
  logic [47:0] eth_src_s2;
  logic [15:0] out_eth_etype_s2;
  logic [15:0] eth_etype_s2;
  logic [7:0] meta_enqd_w_s2;
  logic [7:0] meta_deqd_w_s2;
  logic [8:0] out_std_meta_egress_port_s2;
  logic drop_s2;

  // Pool-A (out_*/drop) working copies -- every stage except the
  // last, which drives the real output ports directly
  logic out_eth_valid__st0;
  logic [47:0] out_eth_dst__st0;
  logic [47:0] out_eth_src__st0;
  logic [15:0] out_eth_etype__st0;
  logic [8:0] out_std_meta_egress_port__st0;
  logic drop__st0;
  logic out_eth_valid__st1;
  logic [47:0] out_eth_dst__st1;
  logic [47:0] out_eth_src__st1;
  logic [15:0] out_eth_etype__st1;
  logic [8:0] out_std_meta_egress_port__st1;
  logic drop__st1;

  // Pool-B (locals/meta shadow/raw hdr+std_meta reads) working
  // copies -- every stage except the first, which reads live inputs
  logic [7:0] meta_enqd_w__st1;
  logic [7:0] meta_deqd_w__st1;
  logic eth_valid__st1;
  logic [47:0] eth_dst__st1;
  logic [47:0] eth_src__st1;
  logic [15:0] eth_etype__st1;
  logic [7:0] meta_enqd_w__st2;
  logic [7:0] meta_deqd_w__st2;
  logic eth_valid__st2;
  logic [47:0] eth_dst__st2;
  logic [47:0] eth_src__st2;
  logic [15:0] eth_etype__st2;

  // Table lookup result wires
  logic        fwd_hit;
  logic [0:0] fwd_act_id;
  logic [8:0] fwd_p_p;

  // Table module instantiations
  fwd_table #(.DEPTH(16)) u_fwd (
    .clk    (clk),
    .rst_n  (rst_n),
    .lkp_etype    (eth_etype),
    .hit       (fwd_hit),
    .action_id (fwd_act_id),
    .p_p  (fwd_p_p),
    .cp_wr_en  (fwd_cp_wr_en),
    .cp_wr_idx (fwd_cp_wr_idx),
    .cp_wr_key_etype (fwd_cp_wr_key_etype),
    .cp_wr_action (fwd_cp_wr_action),
    .cp_wr_p_p (fwd_cp_wr_p_p),
    .cp_query_en  (fwd_cp_query_en),
    .cp_query_del (fwd_cp_query_del),
    .cp_query_key_etype (fwd_cp_query_key_etype),
    .cp_query_busy (fwd_cp_query_busy),
    .cp_query_hit  (fwd_cp_query_hit),
    .cp_query_action_id (fwd_cp_query_action_id),
    .cp_query_p_p (fwd_cp_query_p_p)
  );

  // Table hit outputs
  assign fwd_hit_out = fwd_hit;

  // Metadata outputs (final value after the last stage)
  assign out_meta_enqd = meta_enqd_w__st2;
  assign out_meta_deqd = meta_deqd_w__st2;

  // ---- Pipeline stage 0 (combinational, feeds the first exact-match table boundary) ----
  always_comb begin
    drop__st0 = 0;

    // Metadata shadow defaults (init from inputs)
    meta_enqd_w = meta_enqd;
    meta_deqd_w = meta_deqd;

    // Standard metadata defaults
    out_std_meta_egress_port__st0 = 9'b0;

    // Header valid flag pass-through defaults
    out_eth_valid__st0 = eth_valid;

    // Header field pass-through defaults
    out_eth_dst__st0 = eth_dst;
    out_eth_src__st0 = eth_src;
    out_eth_etype__st0 = eth_etype;
  end

  // Forward stage-0 state into stage-1 registers (1-cycle
  // boundary — matches the exact-match table's registered latency)
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      valid_s1 <= 1'b0;
    end else begin
      valid_s1 <= valid_in;
      drop_s1 <= drop__st0;
      meta_enqd_w_s1 <= meta_enqd_w;
      meta_deqd_w_s1 <= meta_deqd_w;
      out_eth_valid_s1 <= out_eth_valid__st0;
      eth_valid_s1 <= eth_valid;
      out_eth_dst_s1 <= out_eth_dst__st0;
      eth_dst_s1 <= eth_dst;
      out_eth_src_s1 <= out_eth_src__st0;
      eth_src_s1 <= eth_src;
      out_eth_etype_s1 <= out_eth_etype__st0;
      eth_etype_s1 <= eth_etype;
      out_std_meta_egress_port_s1 <= out_std_meta_egress_port__st0;
    end
  end

  // ---- Pipeline stage 1 (registered 1 cycle(s) after stage 0) ----
  always_comb begin
    drop__st1 = drop_s1;
    meta_enqd_w__st1 = meta_enqd_w_s1;
    meta_deqd_w__st1 = meta_deqd_w_s1;
    out_eth_valid__st1 = out_eth_valid_s1;
    eth_valid__st1 = eth_valid_s1;
    out_eth_dst__st1 = out_eth_dst_s1;
    eth_dst__st1 = eth_dst_s1;
    out_eth_src__st1 = out_eth_src_s1;
    eth_src__st1 = eth_src_s1;
    out_eth_etype__st1 = out_eth_etype_s1;
    eth_etype__st1 = eth_etype_s1;
    out_std_meta_egress_port__st1 = out_std_meta_egress_port_s1;
  end

  // Forward stage-1 state into stage-2 registers (1-cycle
  // boundary — matches the exact-match table's registered latency)
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      valid_s2 <= 1'b0;
    end else begin
      valid_s2 <= valid_s1;
      drop_s2 <= drop__st1;
      meta_enqd_w_s2 <= meta_enqd_w__st1;
      meta_deqd_w_s2 <= meta_deqd_w__st1;
      out_eth_valid_s2 <= out_eth_valid__st1;
      eth_valid_s2 <= eth_valid__st1;
      out_eth_dst_s2 <= out_eth_dst__st1;
      eth_dst_s2 <= eth_dst__st1;
      out_eth_src_s2 <= out_eth_src__st1;
      eth_src_s2 <= eth_src__st1;
      out_eth_etype_s2 <= out_eth_etype__st1;
      eth_etype_s2 <= eth_etype__st1;
      out_std_meta_egress_port_s2 <= out_std_meta_egress_port__st1;
    end
  end

  // ---- Pipeline stage 2 (registered 2 cycle(s) after stage 0) ----
  always_comb begin
    drop = drop_s2;
    meta_enqd_w__st2 = meta_enqd_w_s2;
    meta_deqd_w__st2 = meta_deqd_w_s2;
    out_eth_valid = out_eth_valid_s2;
    eth_valid__st2 = eth_valid_s2;
    out_eth_dst = out_eth_dst_s2;
    eth_dst__st2 = eth_dst_s2;
    out_eth_src = out_eth_src_s2;
    eth_src__st2 = eth_src_s2;
    out_eth_etype = out_eth_etype_s2;
    eth_etype__st2 = eth_etype_s2;
    out_std_meta_egress_port = out_std_meta_egress_port_s2;

    // apply block (stage 2 of 2)
    // fwd.apply()
    if (fwd_hit) begin
      unique case (fwd_act_id)
        1'd0: ; // NoAction
        1'd1: begin // set_port
          out_std_meta_egress_port = fwd_p_p;
        end
        default: ; // default = NoAction
      endcase
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) valid_out <= 0;
    else        valid_out <= valid_s2;
  end
  assign out_valid = valid_s2;

endmodule
