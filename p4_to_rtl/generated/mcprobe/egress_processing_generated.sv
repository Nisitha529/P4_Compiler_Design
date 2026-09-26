module egress_processing_generated (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        valid_in,
  input  logic        drop_in,   // ingress drop (sticky; PHV pass-through)

  // Header valid flags
  input  logic        eth_valid,

  // Header field inputs
  input  logic [47:0] eth_dst,
  input  logic [47:0] eth_src,
  input  logic [15:0] eth_etype,

  // Metadata inputs
  input  logic [8:0] meta_in_port,

  // Standard metadata inputs (table key sources)
  input  logic [8:0] std_meta_egress_port,

  // Header valid flag outputs (may be modified by setValid/setInvalid)
  output logic        out_eth_valid,

  // Header field outputs (pass-through, optionally modified)
  output logic [47:0] out_eth_dst,
  output logic [47:0] out_eth_src,
  output logic [15:0] out_eth_etype,

  // Metadata outputs (final value after the last stage)
  output logic [8:0] out_meta_in_port,

  // Control-plane write ports for table instances
  input  logic        port_smac_cp_wr_en,
  input  logic [3:0] port_smac_cp_wr_idx,
  input  logic [8:0] port_smac_cp_wr_key_egress_port,
  input  logic [0:0] port_smac_cp_wr_action,
  input  logic [47:0] port_smac_cp_wr_p_smac,

  // Table hit outputs
  output logic        port_smac_hit_out,

  // Control-plane query/delete ports (plain exact-match tables)
  input  logic        port_smac_cp_query_en,
  input  logic        port_smac_cp_query_del,
  input  logic [8:0] port_smac_cp_query_key_egress_port,
  output logic        port_smac_cp_query_busy,
  output logic        port_smac_cp_query_hit,
  output logic [0:0] port_smac_cp_query_action_id,
  output logic [47:0] port_smac_cp_query_p_smac,

  output logic        out_valid,   // aligned with out_*/drop -- see note
  output logic        valid_out,
  output logic        drop
);

  // Metadata shadow locals (writable copies of metadata inputs)
  logic [8:0] meta_in_port_w;

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
  logic [8:0] meta_in_port_w_s1;
  logic [8:0] std_meta_egress_port_s1;
  logic drop_in_s1;
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
  logic [8:0] meta_in_port_w_s2;
  logic [8:0] std_meta_egress_port_s2;
  logic drop_in_s2;
  logic drop_s2;

  // Pool-A (out_*/drop) working copies -- every stage except the
  // last, which drives the real output ports directly
  logic out_eth_valid__st0;
  logic [47:0] out_eth_dst__st0;
  logic [47:0] out_eth_src__st0;
  logic [15:0] out_eth_etype__st0;
  logic drop__st0;
  logic out_eth_valid__st1;
  logic [47:0] out_eth_dst__st1;
  logic [47:0] out_eth_src__st1;
  logic [15:0] out_eth_etype__st1;
  logic drop__st1;

  // Pool-B (locals/meta shadow/raw hdr+std_meta reads) working
  // copies -- every stage except the first, which reads live inputs
  logic [8:0] meta_in_port_w__st1;
  logic eth_valid__st1;
  logic [47:0] eth_dst__st1;
  logic [47:0] eth_src__st1;
  logic [15:0] eth_etype__st1;
  logic [8:0] std_meta_egress_port__st1;
  logic drop_in__st1;
  logic [8:0] meta_in_port_w__st2;
  logic eth_valid__st2;
  logic [47:0] eth_dst__st2;
  logic [47:0] eth_src__st2;
  logic [15:0] eth_etype__st2;
  logic [8:0] std_meta_egress_port__st2;
  logic drop_in__st2;

  // Table lookup result wires
  logic        port_smac_hit;
  logic [0:0] port_smac_act_id;
  logic [47:0] port_smac_p_smac;

  // Table module instantiations
  port_smac_table #(.DEPTH(16)) u_port_smac (
    .clk    (clk),
    .rst_n  (rst_n),
    .lkp_egress_port    (std_meta_egress_port),
    .hit       (port_smac_hit),
    .action_id (port_smac_act_id),
    .p_smac  (port_smac_p_smac),
    .cp_wr_en  (port_smac_cp_wr_en),
    .cp_wr_idx (port_smac_cp_wr_idx),
    .cp_wr_key_egress_port (port_smac_cp_wr_key_egress_port),
    .cp_wr_action (port_smac_cp_wr_action),
    .cp_wr_p_smac (port_smac_cp_wr_p_smac),
    .cp_query_en  (port_smac_cp_query_en),
    .cp_query_del (port_smac_cp_query_del),
    .cp_query_key_egress_port (port_smac_cp_query_key_egress_port),
    .cp_query_busy (port_smac_cp_query_busy),
    .cp_query_hit  (port_smac_cp_query_hit),
    .cp_query_action_id (port_smac_cp_query_action_id),
    .cp_query_p_smac (port_smac_cp_query_p_smac)
  );

  // Table hit outputs
  assign port_smac_hit_out = port_smac_hit;

  // Metadata outputs (final value after the last stage)
  assign out_meta_in_port = meta_in_port_w__st2;

  // ---- Pipeline stage 0 (combinational, feeds the first exact-match table boundary) ----
  always_comb begin
    drop__st0 = drop_in;

    // Metadata shadow defaults (init from inputs)
    meta_in_port_w = meta_in_port;

    // Header valid flag pass-through defaults
    out_eth_valid__st0 = eth_valid;

    // Header field pass-through defaults
    out_eth_dst__st0 = eth_dst;
    out_eth_src__st0 = eth_src;
    out_eth_etype__st0 = eth_etype;

    // apply block (stage 0 of 2)
    if (std_meta_egress_port == meta_in_port_w) begin
      drop__st0 = 1'd1;
    end
  end

  // Forward stage-0 state into stage-1 registers (1-cycle
  // boundary — matches the exact-match table's registered latency)
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      valid_s1 <= 1'b0;
    end else begin
      valid_s1 <= valid_in;
      drop_s1 <= drop__st0;
      meta_in_port_w_s1 <= meta_in_port_w;
      out_eth_valid_s1 <= out_eth_valid__st0;
      eth_valid_s1 <= eth_valid;
      out_eth_dst_s1 <= out_eth_dst__st0;
      eth_dst_s1 <= eth_dst;
      out_eth_src_s1 <= out_eth_src__st0;
      eth_src_s1 <= eth_src;
      out_eth_etype_s1 <= out_eth_etype__st0;
      eth_etype_s1 <= eth_etype;
      std_meta_egress_port_s1 <= std_meta_egress_port;
      drop_in_s1 <= drop_in;
    end
  end

  // ---- Pipeline stage 1 (registered 1 cycle(s) after stage 0) ----
  always_comb begin
    drop__st1 = drop_s1;
    meta_in_port_w__st1 = meta_in_port_w_s1;
    out_eth_valid__st1 = out_eth_valid_s1;
    eth_valid__st1 = eth_valid_s1;
    out_eth_dst__st1 = out_eth_dst_s1;
    eth_dst__st1 = eth_dst_s1;
    out_eth_src__st1 = out_eth_src_s1;
    eth_src__st1 = eth_src_s1;
    out_eth_etype__st1 = out_eth_etype_s1;
    eth_etype__st1 = eth_etype_s1;
    std_meta_egress_port__st1 = std_meta_egress_port_s1;
    drop_in__st1 = drop_in_s1;
  end

  // Forward stage-1 state into stage-2 registers (1-cycle
  // boundary — matches the exact-match table's registered latency)
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      valid_s2 <= 1'b0;
    end else begin
      valid_s2 <= valid_s1;
      drop_s2 <= drop__st1;
      meta_in_port_w_s2 <= meta_in_port_w__st1;
      out_eth_valid_s2 <= out_eth_valid__st1;
      eth_valid_s2 <= eth_valid__st1;
      out_eth_dst_s2 <= out_eth_dst__st1;
      eth_dst_s2 <= eth_dst__st1;
      out_eth_src_s2 <= out_eth_src__st1;
      eth_src_s2 <= eth_src__st1;
      out_eth_etype_s2 <= out_eth_etype__st1;
      eth_etype_s2 <= eth_etype__st1;
      std_meta_egress_port_s2 <= std_meta_egress_port__st1;
      drop_in_s2 <= drop_in__st1;
    end
  end

  // ---- Pipeline stage 2 (registered 2 cycle(s) after stage 0) ----
  always_comb begin
    drop = drop_s2;
    meta_in_port_w__st2 = meta_in_port_w_s2;
    out_eth_valid = out_eth_valid_s2;
    eth_valid__st2 = eth_valid_s2;
    out_eth_dst = out_eth_dst_s2;
    eth_dst__st2 = eth_dst_s2;
    out_eth_src = out_eth_src_s2;
    eth_src__st2 = eth_src_s2;
    out_eth_etype = out_eth_etype_s2;
    eth_etype__st2 = eth_etype_s2;
    std_meta_egress_port__st2 = std_meta_egress_port_s2;
    drop_in__st2 = drop_in_s2;

    // apply block (stage 2 of 2)
    // port_smac.apply()
    if (port_smac_hit) begin
      unique case (port_smac_act_id)
        1'd0: ; // NoAction
        1'd1: begin // set_smac
          out_eth_src = port_smac_p_smac;
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
