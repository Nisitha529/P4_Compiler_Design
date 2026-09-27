module processing_generated (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        valid_in,

  // Header valid flags
  input  logic        eth_valid,
  input  logic        tag_valid,
  input  logic        tag2_valid,
  input  logic        vlan_valid,

  // Header field inputs
  input  logic [47:0] eth_dst,
  input  logic [47:0] eth_src,
  input  logic [15:0] eth_etype,
  input  logic [15:0] tag_magic,
  input  logic [15:0] tag_seq,
  input  logic [15:0] tag2_magic2,
  input  logic [15:0] tag2_seq2,
  input  logic [15:0] vlan_tci,
  input  logic [15:0] vlan_inner_etype,

  // Metadata inputs
  input  logic [15:0] meta_unused,

  // Header valid flag outputs (may be modified by setValid/setInvalid)
  output logic        out_eth_valid,
  output logic        out_tag_valid,
  output logic        out_tag2_valid,
  output logic        out_vlan_valid,

  // Header field outputs (pass-through, optionally modified)
  output logic [47:0] out_eth_dst,
  output logic [47:0] out_eth_src,
  output logic [15:0] out_eth_etype,
  output logic [15:0] out_tag_magic,
  output logic [15:0] out_tag_seq,
  output logic [15:0] out_tag2_magic2,
  output logic [15:0] out_tag2_seq2,
  output logic [15:0] out_vlan_tci,
  output logic [15:0] out_vlan_inner_etype,

  // Standard metadata outputs
  output logic [8:0] out_std_meta_egress_port,

  // Metadata outputs (final value after the last stage)
  output logic [15:0] out_meta_unused,

  // Control-plane write ports for table instances
  input  logic        cls_cp_wr_en,
  input  logic [3:0] cls_cp_wr_idx,
  input  logic [15:0] cls_cp_wr_key_etype,
  input  logic [2:0] cls_cp_wr_action,
  input  logic [8:0] cls_cp_wr_p_port,

  // Table hit outputs
  output logic        cls_hit_out,

  // Control-plane query/delete ports (plain exact-match tables)
  input  logic        cls_cp_query_en,
  input  logic        cls_cp_query_del,
  input  logic [15:0] cls_cp_query_key_etype,
  output logic        cls_cp_query_busy,
  output logic        cls_cp_query_hit,
  output logic [2:0] cls_cp_query_action_id,
  output logic [8:0] cls_cp_query_p_port,

  output logic        out_valid,   // aligned with out_*/drop -- see note
  output logic        valid_out,
  output logic        drop
);

  // Metadata shadow locals (writable copies of metadata inputs)
  logic [15:0] meta_unused_w;

  // Pipeline-stage forwarding registers (one set per exact-match
  // table boundary in the chain)
  logic valid_s1;
  logic out_eth_valid_s1;
  logic eth_valid_s1;
  logic out_tag_valid_s1;
  logic tag_valid_s1;
  logic out_tag2_valid_s1;
  logic tag2_valid_s1;
  logic out_vlan_valid_s1;
  logic vlan_valid_s1;
  logic [47:0] out_eth_dst_s1;
  logic [47:0] eth_dst_s1;
  logic [47:0] out_eth_src_s1;
  logic [47:0] eth_src_s1;
  logic [15:0] out_eth_etype_s1;
  logic [15:0] eth_etype_s1;
  logic [15:0] out_tag_magic_s1;
  logic [15:0] tag_magic_s1;
  logic [15:0] out_tag_seq_s1;
  logic [15:0] tag_seq_s1;
  logic [15:0] out_tag2_magic2_s1;
  logic [15:0] tag2_magic2_s1;
  logic [15:0] out_tag2_seq2_s1;
  logic [15:0] tag2_seq2_s1;
  logic [15:0] out_vlan_tci_s1;
  logic [15:0] vlan_tci_s1;
  logic [15:0] out_vlan_inner_etype_s1;
  logic [15:0] vlan_inner_etype_s1;
  logic [15:0] meta_unused_w_s1;
  logic [8:0] out_std_meta_egress_port_s1;
  logic drop_s1;
  logic valid_s2;
  logic out_eth_valid_s2;
  logic eth_valid_s2;
  logic out_tag_valid_s2;
  logic tag_valid_s2;
  logic out_tag2_valid_s2;
  logic tag2_valid_s2;
  logic out_vlan_valid_s2;
  logic vlan_valid_s2;
  logic [47:0] out_eth_dst_s2;
  logic [47:0] eth_dst_s2;
  logic [47:0] out_eth_src_s2;
  logic [47:0] eth_src_s2;
  logic [15:0] out_eth_etype_s2;
  logic [15:0] eth_etype_s2;
  logic [15:0] out_tag_magic_s2;
  logic [15:0] tag_magic_s2;
  logic [15:0] out_tag_seq_s2;
  logic [15:0] tag_seq_s2;
  logic [15:0] out_tag2_magic2_s2;
  logic [15:0] tag2_magic2_s2;
  logic [15:0] out_tag2_seq2_s2;
  logic [15:0] tag2_seq2_s2;
  logic [15:0] out_vlan_tci_s2;
  logic [15:0] vlan_tci_s2;
  logic [15:0] out_vlan_inner_etype_s2;
  logic [15:0] vlan_inner_etype_s2;
  logic [15:0] meta_unused_w_s2;
  logic [8:0] out_std_meta_egress_port_s2;
  logic drop_s2;

  // Pool-A (out_*/drop) working copies -- every stage except the
  // last, which drives the real output ports directly
  logic out_eth_valid__st0;
  logic out_tag_valid__st0;
  logic out_tag2_valid__st0;
  logic out_vlan_valid__st0;
  logic [47:0] out_eth_dst__st0;
  logic [47:0] out_eth_src__st0;
  logic [15:0] out_eth_etype__st0;
  logic [15:0] out_tag_magic__st0;
  logic [15:0] out_tag_seq__st0;
  logic [15:0] out_tag2_magic2__st0;
  logic [15:0] out_tag2_seq2__st0;
  logic [15:0] out_vlan_tci__st0;
  logic [15:0] out_vlan_inner_etype__st0;
  logic [8:0] out_std_meta_egress_port__st0;
  logic drop__st0;
  logic out_eth_valid__st1;
  logic out_tag_valid__st1;
  logic out_tag2_valid__st1;
  logic out_vlan_valid__st1;
  logic [47:0] out_eth_dst__st1;
  logic [47:0] out_eth_src__st1;
  logic [15:0] out_eth_etype__st1;
  logic [15:0] out_tag_magic__st1;
  logic [15:0] out_tag_seq__st1;
  logic [15:0] out_tag2_magic2__st1;
  logic [15:0] out_tag2_seq2__st1;
  logic [15:0] out_vlan_tci__st1;
  logic [15:0] out_vlan_inner_etype__st1;
  logic [8:0] out_std_meta_egress_port__st1;
  logic drop__st1;

  // Pool-B (locals/meta shadow/raw hdr+std_meta reads) working
  // copies -- every stage except the first, which reads live inputs
  logic [15:0] meta_unused_w__st1;
  logic eth_valid__st1;
  logic tag_valid__st1;
  logic tag2_valid__st1;
  logic vlan_valid__st1;
  logic [47:0] eth_dst__st1;
  logic [47:0] eth_src__st1;
  logic [15:0] eth_etype__st1;
  logic [15:0] tag_magic__st1;
  logic [15:0] tag_seq__st1;
  logic [15:0] tag2_magic2__st1;
  logic [15:0] tag2_seq2__st1;
  logic [15:0] vlan_tci__st1;
  logic [15:0] vlan_inner_etype__st1;
  logic [15:0] meta_unused_w__st2;
  logic eth_valid__st2;
  logic tag_valid__st2;
  logic tag2_valid__st2;
  logic vlan_valid__st2;
  logic [47:0] eth_dst__st2;
  logic [47:0] eth_src__st2;
  logic [15:0] eth_etype__st2;
  logic [15:0] tag_magic__st2;
  logic [15:0] tag_seq__st2;
  logic [15:0] tag2_magic2__st2;
  logic [15:0] tag2_seq2__st2;
  logic [15:0] vlan_tci__st2;
  logic [15:0] vlan_inner_etype__st2;

  // Table lookup result wires
  logic        cls_hit;
  logic [2:0] cls_act_id;
  logic [8:0] cls_p_port;

  // Table module instantiations
  cls_table #(.DEPTH(16)) u_cls (
    .clk    (clk),
    .rst_n  (rst_n),
    .lkp_etype    (eth_etype),
    .hit       (cls_hit),
    .action_id (cls_act_id),
    .p_port  (cls_p_port),
    .cp_wr_en  (cls_cp_wr_en),
    .cp_wr_idx (cls_cp_wr_idx),
    .cp_wr_key_etype (cls_cp_wr_key_etype),
    .cp_wr_action (cls_cp_wr_action),
    .cp_wr_p_port (cls_cp_wr_p_port),
    .cp_query_en  (cls_cp_query_en),
    .cp_query_del (cls_cp_query_del),
    .cp_query_key_etype (cls_cp_query_key_etype),
    .cp_query_busy (cls_cp_query_busy),
    .cp_query_hit  (cls_cp_query_hit),
    .cp_query_action_id (cls_cp_query_action_id),
    .cp_query_p_port (cls_cp_query_p_port)
  );

  // Table hit outputs
  assign cls_hit_out = cls_hit;

  // Metadata outputs (final value after the last stage)
  assign out_meta_unused = meta_unused_w__st2;

  // ---- Pipeline stage 0 (combinational, feeds the first exact-match table boundary) ----
  always_comb begin
    drop__st0 = 0;

    // Metadata shadow defaults (init from inputs)
    meta_unused_w = meta_unused;

    // Standard metadata defaults
    out_std_meta_egress_port__st0 = 9'b0;

    // Header valid flag pass-through defaults
    out_eth_valid__st0 = eth_valid;
    out_tag_valid__st0 = tag_valid;
    out_tag2_valid__st0 = tag2_valid;
    out_vlan_valid__st0 = vlan_valid;

    // Header field pass-through defaults
    out_eth_dst__st0 = eth_dst;
    out_eth_src__st0 = eth_src;
    out_eth_etype__st0 = eth_etype;
    out_tag_magic__st0 = tag_magic;
    out_tag_seq__st0 = tag_seq;
    out_tag2_magic2__st0 = tag2_magic2;
    out_tag2_seq2__st0 = tag2_seq2;
    out_vlan_tci__st0 = vlan_tci;
    out_vlan_inner_etype__st0 = vlan_inner_etype;
  end

  // Forward stage-0 state into stage-1 registers (1-cycle
  // boundary — matches the exact-match table's registered latency)
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      valid_s1 <= 1'b0;
    end else begin
      valid_s1 <= valid_in;
      drop_s1 <= drop__st0;
      meta_unused_w_s1 <= meta_unused_w;
      out_eth_valid_s1 <= out_eth_valid__st0;
      eth_valid_s1 <= eth_valid;
      out_tag_valid_s1 <= out_tag_valid__st0;
      tag_valid_s1 <= tag_valid;
      out_tag2_valid_s1 <= out_tag2_valid__st0;
      tag2_valid_s1 <= tag2_valid;
      out_vlan_valid_s1 <= out_vlan_valid__st0;
      vlan_valid_s1 <= vlan_valid;
      out_eth_dst_s1 <= out_eth_dst__st0;
      eth_dst_s1 <= eth_dst;
      out_eth_src_s1 <= out_eth_src__st0;
      eth_src_s1 <= eth_src;
      out_eth_etype_s1 <= out_eth_etype__st0;
      eth_etype_s1 <= eth_etype;
      out_tag_magic_s1 <= out_tag_magic__st0;
      tag_magic_s1 <= tag_magic;
      out_tag_seq_s1 <= out_tag_seq__st0;
      tag_seq_s1 <= tag_seq;
      out_tag2_magic2_s1 <= out_tag2_magic2__st0;
      tag2_magic2_s1 <= tag2_magic2;
      out_tag2_seq2_s1 <= out_tag2_seq2__st0;
      tag2_seq2_s1 <= tag2_seq2;
      out_vlan_tci_s1 <= out_vlan_tci__st0;
      vlan_tci_s1 <= vlan_tci;
      out_vlan_inner_etype_s1 <= out_vlan_inner_etype__st0;
      vlan_inner_etype_s1 <= vlan_inner_etype;
      out_std_meta_egress_port_s1 <= out_std_meta_egress_port__st0;
    end
  end

  // ---- Pipeline stage 1 (registered 1 cycle(s) after stage 0) ----
  always_comb begin
    drop__st1 = drop_s1;
    meta_unused_w__st1 = meta_unused_w_s1;
    out_eth_valid__st1 = out_eth_valid_s1;
    eth_valid__st1 = eth_valid_s1;
    out_tag_valid__st1 = out_tag_valid_s1;
    tag_valid__st1 = tag_valid_s1;
    out_tag2_valid__st1 = out_tag2_valid_s1;
    tag2_valid__st1 = tag2_valid_s1;
    out_vlan_valid__st1 = out_vlan_valid_s1;
    vlan_valid__st1 = vlan_valid_s1;
    out_eth_dst__st1 = out_eth_dst_s1;
    eth_dst__st1 = eth_dst_s1;
    out_eth_src__st1 = out_eth_src_s1;
    eth_src__st1 = eth_src_s1;
    out_eth_etype__st1 = out_eth_etype_s1;
    eth_etype__st1 = eth_etype_s1;
    out_tag_magic__st1 = out_tag_magic_s1;
    tag_magic__st1 = tag_magic_s1;
    out_tag_seq__st1 = out_tag_seq_s1;
    tag_seq__st1 = tag_seq_s1;
    out_tag2_magic2__st1 = out_tag2_magic2_s1;
    tag2_magic2__st1 = tag2_magic2_s1;
    out_tag2_seq2__st1 = out_tag2_seq2_s1;
    tag2_seq2__st1 = tag2_seq2_s1;
    out_vlan_tci__st1 = out_vlan_tci_s1;
    vlan_tci__st1 = vlan_tci_s1;
    out_vlan_inner_etype__st1 = out_vlan_inner_etype_s1;
    vlan_inner_etype__st1 = vlan_inner_etype_s1;
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
      meta_unused_w_s2 <= meta_unused_w__st1;
      out_eth_valid_s2 <= out_eth_valid__st1;
      eth_valid_s2 <= eth_valid__st1;
      out_tag_valid_s2 <= out_tag_valid__st1;
      tag_valid_s2 <= tag_valid__st1;
      out_tag2_valid_s2 <= out_tag2_valid__st1;
      tag2_valid_s2 <= tag2_valid__st1;
      out_vlan_valid_s2 <= out_vlan_valid__st1;
      vlan_valid_s2 <= vlan_valid__st1;
      out_eth_dst_s2 <= out_eth_dst__st1;
      eth_dst_s2 <= eth_dst__st1;
      out_eth_src_s2 <= out_eth_src__st1;
      eth_src_s2 <= eth_src__st1;
      out_eth_etype_s2 <= out_eth_etype__st1;
      eth_etype_s2 <= eth_etype__st1;
      out_tag_magic_s2 <= out_tag_magic__st1;
      tag_magic_s2 <= tag_magic__st1;
      out_tag_seq_s2 <= out_tag_seq__st1;
      tag_seq_s2 <= tag_seq__st1;
      out_tag2_magic2_s2 <= out_tag2_magic2__st1;
      tag2_magic2_s2 <= tag2_magic2__st1;
      out_tag2_seq2_s2 <= out_tag2_seq2__st1;
      tag2_seq2_s2 <= tag2_seq2__st1;
      out_vlan_tci_s2 <= out_vlan_tci__st1;
      vlan_tci_s2 <= vlan_tci__st1;
      out_vlan_inner_etype_s2 <= out_vlan_inner_etype__st1;
      vlan_inner_etype_s2 <= vlan_inner_etype__st1;
      out_std_meta_egress_port_s2 <= out_std_meta_egress_port__st1;
    end
  end

  // ---- Pipeline stage 2 (registered 2 cycle(s) after stage 0) ----
  always_comb begin
    drop = drop_s2;
    meta_unused_w__st2 = meta_unused_w_s2;
    out_eth_valid = out_eth_valid_s2;
    eth_valid__st2 = eth_valid_s2;
    out_tag_valid = out_tag_valid_s2;
    tag_valid__st2 = tag_valid_s2;
    out_tag2_valid = out_tag2_valid_s2;
    tag2_valid__st2 = tag2_valid_s2;
    out_vlan_valid = out_vlan_valid_s2;
    vlan_valid__st2 = vlan_valid_s2;
    out_eth_dst = out_eth_dst_s2;
    eth_dst__st2 = eth_dst_s2;
    out_eth_src = out_eth_src_s2;
    eth_src__st2 = eth_src_s2;
    out_eth_etype = out_eth_etype_s2;
    eth_etype__st2 = eth_etype_s2;
    out_tag_magic = out_tag_magic_s2;
    tag_magic__st2 = tag_magic_s2;
    out_tag_seq = out_tag_seq_s2;
    tag_seq__st2 = tag_seq_s2;
    out_tag2_magic2 = out_tag2_magic2_s2;
    tag2_magic2__st2 = tag2_magic2_s2;
    out_tag2_seq2 = out_tag2_seq2_s2;
    tag2_seq2__st2 = tag2_seq2_s2;
    out_vlan_tci = out_vlan_tci_s2;
    vlan_tci__st2 = vlan_tci_s2;
    out_vlan_inner_etype = out_vlan_inner_etype_s2;
    vlan_inner_etype__st2 = vlan_inner_etype_s2;
    out_std_meta_egress_port = out_std_meta_egress_port_s2;

    // apply block (stage 2 of 2)
    // cls.apply()
    if (cls_hit) begin
      unique case (cls_act_id)
        3'd0: ; // NoAction
        3'd1: begin // fwd
          out_std_meta_egress_port = cls_p_port;
        end
        3'd2: begin // insert_one
          out_std_meta_egress_port = cls_p_port;
          out_tag_valid = 1'b1;
          out_tag_magic = 16'hAA01;
          out_tag_seq = 16'h1111;
        end
        3'd3: begin // insert_two
          out_std_meta_egress_port = cls_p_port;
          out_tag_valid = 1'b1;
          out_tag_magic = 16'hAA01;
          out_tag_seq = 16'h1111;
          out_tag2_valid = 1'b1;
          out_tag2_magic2 = 16'hBB02;
          out_tag2_seq2 = 16'h2222;
        end
        3'd4: begin // strip_vlan
          out_std_meta_egress_port = cls_p_port;
          out_vlan_valid = 1'b0;
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
