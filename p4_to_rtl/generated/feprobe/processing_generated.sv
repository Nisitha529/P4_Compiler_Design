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
  input  logic [15:0] meta_flow_id,
  input  logic [15:0] meta_seen,
  input  logic [7:0] meta_dir,

  // Standard metadata inputs (table key sources)
  input  logic [0:0] std_meta_drop,
  input  logic [15:0] std_meta_packet_length,
  input  logic [15:0] std_meta_parsed_bytes,

  // Header valid flag outputs (may be modified by setValid/setInvalid)
  output logic        out_eth_valid,

  // Header field outputs (pass-through, optionally modified)
  output logic [47:0] out_eth_dst,
  output logic [47:0] out_eth_src,
  output logic [15:0] out_eth_etype,

  // Standard metadata outputs
  output logic [8:0] out_std_meta_egress_port,

  // Metadata outputs (final value after the last stage)
  output logic [15:0] out_meta_flow_id,
  output logic [15:0] out_meta_seen,
  output logic [7:0] out_meta_dir,

  // Control-plane write ports for table instances
  input  logic        fwd_cp_wr_en,
  input  logic [3:0] fwd_cp_wr_idx,
  input  logic [15:0] fwd_cp_wr_key_etype,
  input  logic [1:0] fwd_cp_wr_action,
  input  logic [8:0] fwd_cp_wr_p_p,

  // Table hit outputs
  output logic        fwd_hit_out,

  // Control-plane query/delete ports (plain exact-match tables)
  input  logic        fwd_cp_query_en,
  input  logic        fwd_cp_query_del,
  input  logic [15:0] fwd_cp_query_key_etype,
  output logic        fwd_cp_query_busy,
  output logic        fwd_cp_query_hit,
  output logic [1:0] fwd_cp_query_action_id,
  output logic [8:0] fwd_cp_query_p_p,

  // FeatureExport pushes. The staging FIFO and the AXI4-Stream
  // master port live in the shell; this module just produces records.
  // tdata is padded up to a byte multiple, pad bits in the LOW bits.
  output logic        tcn_feed_push,
  output logic [63:0] tcn_feed_data,
  output logic        gated_feed_push,
  output logic [15:0] gated_feed_data,

  output logic        out_valid,   // aligned with out_*/drop -- see note
  output logic        valid_out,
  output logic        drop
);

  // Metadata shadow locals (writable copies of metadata inputs)
  logic [15:0] meta_flow_id_w;
  logic [15:0] meta_seen_w;
  logic [7:0] meta_dir_w;

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
  logic [15:0] meta_flow_id_w_s1;
  logic [15:0] meta_seen_w_s1;
  logic [7:0] meta_dir_w_s1;
  logic [8:0] out_std_meta_egress_port_s1;
  logic [0:0] std_meta_drop_s1;
  logic [15:0] std_meta_packet_length_s1;
  logic [15:0] std_meta_parsed_bytes_s1;
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
  logic [15:0] meta_flow_id_w_s2;
  logic [15:0] meta_seen_w_s2;
  logic [7:0] meta_dir_w_s2;
  logic [8:0] out_std_meta_egress_port_s2;
  logic [0:0] std_meta_drop_s2;
  logic [15:0] std_meta_packet_length_s2;
  logic [15:0] std_meta_parsed_bytes_s2;
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
  logic [15:0] meta_flow_id_w__st1;
  logic [15:0] meta_seen_w__st1;
  logic [7:0] meta_dir_w__st1;
  logic eth_valid__st1;
  logic [47:0] eth_dst__st1;
  logic [47:0] eth_src__st1;
  logic [15:0] eth_etype__st1;
  logic [0:0] std_meta_drop__st1;
  logic [15:0] std_meta_packet_length__st1;
  logic [15:0] std_meta_parsed_bytes__st1;
  logic [15:0] meta_flow_id_w__st2;
  logic [15:0] meta_seen_w__st2;
  logic [7:0] meta_dir_w__st2;
  logic eth_valid__st2;
  logic [47:0] eth_dst__st2;
  logic [47:0] eth_src__st2;
  logic [15:0] eth_etype__st2;
  logic [0:0] std_meta_drop__st2;
  logic [15:0] std_meta_packet_length__st2;
  logic [15:0] std_meta_parsed_bytes__st2;

  // ── FeatureExport push outputs ───────────────────────────────────────
  // tcn_feed: 64-bit record padded to 64, pushed in stage 2
  // record layout, high bits first:
  //   [63:48] eth_etype (16b)
  //   [47:32] packet_length (16b)
  //   [31:16] eth_dst_15_0 (16b)
  //   [15:8] const (8b)
  //   [7:0] parsed_bytes_7_0 (8b)
  logic        tcn_feed_push_c;
  logic [63:0] tcn_feed_data_c;
  always_ff @(posedge clk) begin
    if (!rst_n) tcn_feed_push <= 1'b0;
    else begin
      tcn_feed_push <= tcn_feed_push_c && valid_s2;
      if (tcn_feed_push_c && valid_s2) tcn_feed_data <= tcn_feed_data_c;
    end
  end
  // gated_feed: 16-bit record padded to 16, pushed in stage 2
  // record layout, high bits first:
  //   [15:0] eth_dst_15_0 (16b)
  logic        gated_feed_push_c;
  logic [15:0] gated_feed_data_c;
  always_ff @(posedge clk) begin
    if (!rst_n) gated_feed_push <= 1'b0;
    else begin
      gated_feed_push <= gated_feed_push_c && valid_s2;
      if (gated_feed_push_c && valid_s2) gated_feed_data <= gated_feed_data_c;
    end
  end

  // Table lookup result wires
  logic        fwd_hit;
  logic [1:0] fwd_act_id;
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
  assign out_meta_flow_id = meta_flow_id_w__st2;
  assign out_meta_seen = meta_seen_w__st2;
  assign out_meta_dir = meta_dir_w__st2;

  // ---- Pipeline stage 0 (combinational, feeds the first exact-match table boundary) ----
  always_comb begin
    drop__st0 = 0;

    // Metadata shadow defaults (init from inputs)
    meta_flow_id_w = meta_flow_id;
    meta_seen_w = meta_seen;
    meta_dir_w = meta_dir;

    // Standard metadata defaults
    out_std_meta_egress_port__st0 = 9'b0;

    // Header valid flag pass-through defaults
    out_eth_valid__st0 = eth_valid;

    // Header field pass-through defaults
    out_eth_dst__st0 = eth_dst;
    out_eth_src__st0 = eth_src;
    out_eth_etype__st0 = eth_etype;

    // apply block (stage 0 of 2)
    meta_dir_w = 8'hA5;
  end

  // Forward stage-0 state into stage-1 registers (1-cycle
  // boundary — matches the exact-match table's registered latency)
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      valid_s1 <= 1'b0;
    end else begin
      valid_s1 <= valid_in;
      drop_s1 <= drop__st0;
      meta_flow_id_w_s1 <= meta_flow_id_w;
      meta_seen_w_s1 <= meta_seen_w;
      meta_dir_w_s1 <= meta_dir_w;
      out_eth_valid_s1 <= out_eth_valid__st0;
      eth_valid_s1 <= eth_valid;
      out_eth_dst_s1 <= out_eth_dst__st0;
      eth_dst_s1 <= eth_dst;
      out_eth_src_s1 <= out_eth_src__st0;
      eth_src_s1 <= eth_src;
      out_eth_etype_s1 <= out_eth_etype__st0;
      eth_etype_s1 <= eth_etype;
      out_std_meta_egress_port_s1 <= out_std_meta_egress_port__st0;
      std_meta_drop_s1 <= std_meta_drop;
      std_meta_packet_length_s1 <= std_meta_packet_length;
      std_meta_parsed_bytes_s1 <= std_meta_parsed_bytes;
    end
  end

  // ---- Pipeline stage 1 (registered 1 cycle(s) after stage 0) ----
  always_comb begin
    drop__st1 = drop_s1;
    meta_flow_id_w__st1 = meta_flow_id_w_s1;
    meta_seen_w__st1 = meta_seen_w_s1;
    meta_dir_w__st1 = meta_dir_w_s1;
    out_eth_valid__st1 = out_eth_valid_s1;
    eth_valid__st1 = eth_valid_s1;
    out_eth_dst__st1 = out_eth_dst_s1;
    eth_dst__st1 = eth_dst_s1;
    out_eth_src__st1 = out_eth_src_s1;
    eth_src__st1 = eth_src_s1;
    out_eth_etype__st1 = out_eth_etype_s1;
    eth_etype__st1 = eth_etype_s1;
    out_std_meta_egress_port__st1 = out_std_meta_egress_port_s1;
    std_meta_drop__st1 = std_meta_drop_s1;
    std_meta_packet_length__st1 = std_meta_packet_length_s1;
    std_meta_parsed_bytes__st1 = std_meta_parsed_bytes_s1;
  end

  // Forward stage-1 state into stage-2 registers (1-cycle
  // boundary — matches the exact-match table's registered latency)
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      valid_s2 <= 1'b0;
    end else begin
      valid_s2 <= valid_s1;
      drop_s2 <= drop__st1;
      meta_flow_id_w_s2 <= meta_flow_id_w__st1;
      meta_seen_w_s2 <= meta_seen_w__st1;
      meta_dir_w_s2 <= meta_dir_w__st1;
      out_eth_valid_s2 <= out_eth_valid__st1;
      eth_valid_s2 <= eth_valid__st1;
      out_eth_dst_s2 <= out_eth_dst__st1;
      eth_dst_s2 <= eth_dst__st1;
      out_eth_src_s2 <= out_eth_src__st1;
      eth_src_s2 <= eth_src__st1;
      out_eth_etype_s2 <= out_eth_etype__st1;
      eth_etype_s2 <= eth_etype__st1;
      out_std_meta_egress_port_s2 <= out_std_meta_egress_port__st1;
      std_meta_drop_s2 <= std_meta_drop__st1;
      std_meta_packet_length_s2 <= std_meta_packet_length__st1;
      std_meta_parsed_bytes_s2 <= std_meta_parsed_bytes__st1;
    end
  end

  // ---- Pipeline stage 2 (registered 2 cycle(s) after stage 0) ----
  always_comb begin
    drop = drop_s2;
    meta_flow_id_w__st2 = meta_flow_id_w_s2;
    meta_seen_w__st2 = meta_seen_w_s2;
    meta_dir_w__st2 = meta_dir_w_s2;
    tcn_feed_push_c = 1'b0;
    tcn_feed_data_c = '0;
    gated_feed_push_c = 1'b0;
    gated_feed_data_c = '0;
    out_eth_valid = out_eth_valid_s2;
    eth_valid__st2 = eth_valid_s2;
    out_eth_dst = out_eth_dst_s2;
    eth_dst__st2 = eth_dst_s2;
    out_eth_src = out_eth_src_s2;
    eth_src__st2 = eth_src_s2;
    out_eth_etype = out_eth_etype_s2;
    eth_etype__st2 = eth_etype_s2;
    out_std_meta_egress_port = out_std_meta_egress_port_s2;
    std_meta_drop__st2 = std_meta_drop_s2;
    std_meta_packet_length__st2 = std_meta_packet_length_s2;
    std_meta_parsed_bytes__st2 = std_meta_parsed_bytes_s2;

    // apply block (stage 2 of 2)
    // fwd.apply()
    if (fwd_hit) begin
      unique case (fwd_act_id)
        2'd0: ; // NoAction
        2'd1: begin // set_port
          out_std_meta_egress_port = fwd_p_p;
        end
        2'd2: begin // drop_it
          drop = 1'd1;
        end
        default: ; // default = NoAction
      endcase
    end
    tcn_feed_push_c = 1'b1;
    tcn_feed_data_c = {eth_etype__st2, std_meta_packet_length__st2, eth_dst__st2[15:0], 8'hA5, std_meta_parsed_bytes__st2[7:0]};
    if (drop == 1'd0) begin
      gated_feed_push_c = 1'b1;
      gated_feed_data_c = eth_dst__st2[15:0];
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) valid_out <= 0;
    else        valid_out <= valid_s2;
  end
  assign out_valid = valid_s2;

endmodule
