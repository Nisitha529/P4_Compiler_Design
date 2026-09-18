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
  input  logic [15:0] meta_res,
  input  logic [7:0] meta_res2,

  // Header valid flag outputs (may be modified by setValid/setInvalid)
  output logic        out_eth_valid,

  // Header field outputs (pass-through, optionally modified)
  output logic [47:0] out_eth_dst,
  output logic [47:0] out_eth_src,
  output logic [15:0] out_eth_etype,

  // Metadata outputs (final value after the last stage)
  output logic [15:0] out_meta_res,
  output logic [7:0] out_meta_res2,

  output logic        out_valid,   // aligned with out_*/drop -- see note
  output logic        valid_out,
  output logic        drop
);

  // Metadata shadow locals (writable copies of metadata inputs)
  logic [15:0] meta_res_w;
  logic [7:0] meta_res2_w;

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
  logic [15:0] meta_res_w_s1;
  logic [7:0] meta_res2_w_s1;
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
  logic [15:0] meta_res_w_s2;
  logic [7:0] meta_res2_w_s2;
  logic drop_s2;
  logic valid_s3;
  logic out_eth_valid_s3;
  logic eth_valid_s3;
  logic [47:0] out_eth_dst_s3;
  logic [47:0] eth_dst_s3;
  logic [47:0] out_eth_src_s3;
  logic [47:0] eth_src_s3;
  logic [15:0] out_eth_etype_s3;
  logic [15:0] eth_etype_s3;
  logic [15:0] meta_res_w_s3;
  logic [7:0] meta_res2_w_s3;
  logic drop_s3;
  logic valid_s4;
  logic out_eth_valid_s4;
  logic eth_valid_s4;
  logic [47:0] out_eth_dst_s4;
  logic [47:0] eth_dst_s4;
  logic [47:0] out_eth_src_s4;
  logic [47:0] eth_src_s4;
  logic [15:0] out_eth_etype_s4;
  logic [15:0] eth_etype_s4;
  logic [15:0] meta_res_w_s4;
  logic [7:0] meta_res2_w_s4;
  logic drop_s4;

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
  logic out_eth_valid__st2;
  logic [47:0] out_eth_dst__st2;
  logic [47:0] out_eth_src__st2;
  logic [15:0] out_eth_etype__st2;
  logic drop__st2;
  logic out_eth_valid__st3;
  logic [47:0] out_eth_dst__st3;
  logic [47:0] out_eth_src__st3;
  logic [15:0] out_eth_etype__st3;
  logic drop__st3;

  // Pool-B (locals/meta shadow/raw hdr+std_meta reads) working
  // copies -- every stage except the first, which reads live inputs
  logic [15:0] meta_res_w__st1;
  logic [7:0] meta_res2_w__st1;
  logic eth_valid__st1;
  logic [47:0] eth_dst__st1;
  logic [47:0] eth_src__st1;
  logic [15:0] eth_etype__st1;
  logic [15:0] meta_res_w__st2;
  logic [7:0] meta_res2_w__st2;
  logic eth_valid__st2;
  logic [47:0] eth_dst__st2;
  logic [47:0] eth_src__st2;
  logic [15:0] eth_etype__st2;
  logic [15:0] meta_res_w__st3;
  logic [7:0] meta_res2_w__st3;
  logic eth_valid__st3;
  logic [47:0] eth_dst__st3;
  logic [47:0] eth_src__st3;
  logic [15:0] eth_etype__st3;
  logic [15:0] meta_res_w__st4;
  logic [7:0] meta_res2_w__st4;
  logic eth_valid__st4;
  logic [47:0] eth_dst__st4;
  logic [47:0] eth_src__st4;
  logic [15:0] eth_etype__st4;

  // UserExtern instances (xsa.p4 escape hatch --
  // module bodies are user-provided)
  logic [47:0] my_lookup_data_in;
  logic [15:0] my_lookup_result;
  logic [15:0] my_classify_data_in;
  logic [7:0] my_classify_result;

  assign my_lookup_data_in = eth_dst;
  my_lookup u_my_lookup (
    .clk      (clk),
    .rst_n    (rst_n),
    .valid_in (valid_in),
    .data_in  (my_lookup_data_in),
    .result   (my_lookup_result)
  );
  assign my_classify_data_in = eth_etype__st3;
  my_classify u_my_classify (
    .clk      (clk),
    .rst_n    (rst_n),
    .valid_in (valid_s3),
    .data_in  (my_classify_data_in),
    .result   (my_classify_result)
  );

  // Metadata outputs (final value after the last stage)
  assign out_meta_res = meta_res_w__st4;
  assign out_meta_res2 = meta_res2_w__st4;

  // ---- Pipeline stage 0 (combinational, feeds the first exact-match table boundary) ----
  always_comb begin
    drop__st0 = 0;

    // Metadata shadow defaults (init from inputs)
    meta_res_w = meta_res;
    meta_res2_w = meta_res2;

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
      meta_res_w_s1 <= meta_res_w;
      meta_res2_w_s1 <= meta_res2_w;
      out_eth_valid_s1 <= out_eth_valid__st0;
      eth_valid_s1 <= eth_valid;
      out_eth_dst_s1 <= out_eth_dst__st0;
      eth_dst_s1 <= eth_dst;
      out_eth_src_s1 <= out_eth_src__st0;
      eth_src_s1 <= eth_src;
      out_eth_etype_s1 <= out_eth_etype__st0;
      eth_etype_s1 <= eth_etype;
    end
  end

  // ---- Pipeline stage 1 (registered 1 cycle(s) after stage 0) ----
  always_comb begin
    drop__st1 = drop_s1;
    meta_res_w__st1 = meta_res_w_s1;
    meta_res2_w__st1 = meta_res2_w_s1;
    out_eth_valid__st1 = out_eth_valid_s1;
    eth_valid__st1 = eth_valid_s1;
    out_eth_dst__st1 = out_eth_dst_s1;
    eth_dst__st1 = eth_dst_s1;
    out_eth_src__st1 = out_eth_src_s1;
    eth_src__st1 = eth_src_s1;
    out_eth_etype__st1 = out_eth_etype_s1;
    eth_etype__st1 = eth_etype_s1;
  end

  // Forward stage-1 state into stage-2 registers (1-cycle
  // boundary — matches the exact-match table's registered latency)
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      valid_s2 <= 1'b0;
    end else begin
      valid_s2 <= valid_s1;
      drop_s2 <= drop__st1;
      meta_res_w_s2 <= meta_res_w__st1;
      meta_res2_w_s2 <= meta_res2_w__st1;
      out_eth_valid_s2 <= out_eth_valid__st1;
      eth_valid_s2 <= eth_valid__st1;
      out_eth_dst_s2 <= out_eth_dst__st1;
      eth_dst_s2 <= eth_dst__st1;
      out_eth_src_s2 <= out_eth_src__st1;
      eth_src_s2 <= eth_src__st1;
      out_eth_etype_s2 <= out_eth_etype__st1;
      eth_etype_s2 <= eth_etype__st1;
    end
  end

  // ---- Pipeline stage 2 (registered 2 cycle(s) after stage 0) ----
  always_comb begin
    drop__st2 = drop_s2;
    meta_res_w__st2 = meta_res_w_s2;
    meta_res2_w__st2 = meta_res2_w_s2;
    out_eth_valid__st2 = out_eth_valid_s2;
    eth_valid__st2 = eth_valid_s2;
    out_eth_dst__st2 = out_eth_dst_s2;
    eth_dst__st2 = eth_dst_s2;
    out_eth_src__st2 = out_eth_src_s2;
    eth_src__st2 = eth_src_s2;
    out_eth_etype__st2 = out_eth_etype_s2;
    eth_etype__st2 = eth_etype_s2;
  end

  // Forward stage-2 state into stage-3 registers (1-cycle
  // boundary — matches the exact-match table's registered latency)
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      valid_s3 <= 1'b0;
    end else begin
      valid_s3 <= valid_s2;
      drop_s3 <= drop__st2;
      meta_res_w_s3 <= meta_res_w__st2;
      meta_res2_w_s3 <= meta_res2_w__st2;
      out_eth_valid_s3 <= out_eth_valid__st2;
      eth_valid_s3 <= eth_valid__st2;
      out_eth_dst_s3 <= out_eth_dst__st2;
      eth_dst_s3 <= eth_dst__st2;
      out_eth_src_s3 <= out_eth_src__st2;
      eth_src_s3 <= eth_src__st2;
      out_eth_etype_s3 <= out_eth_etype__st2;
      eth_etype_s3 <= eth_etype__st2;
    end
  end

  // ---- Pipeline stage 3 (registered 3 cycle(s) after stage 0) ----
  always_comb begin
    drop__st3 = drop_s3;
    meta_res_w__st3 = meta_res_w_s3;
    meta_res2_w__st3 = meta_res2_w_s3;
    out_eth_valid__st3 = out_eth_valid_s3;
    eth_valid__st3 = eth_valid_s3;
    out_eth_dst__st3 = out_eth_dst_s3;
    eth_dst__st3 = eth_dst_s3;
    out_eth_src__st3 = out_eth_src_s3;
    eth_src__st3 = eth_src_s3;
    out_eth_etype__st3 = out_eth_etype_s3;
    eth_etype__st3 = eth_etype_s3;

    // apply block (stage 3 of 4)
    meta_res_w__st3 = my_lookup_result;
  end

  // Forward stage-3 state into stage-4 registers (1-cycle
  // boundary — matches the exact-match table's registered latency)
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      valid_s4 <= 1'b0;
    end else begin
      valid_s4 <= valid_s3;
      drop_s4 <= drop__st3;
      meta_res_w_s4 <= meta_res_w__st3;
      meta_res2_w_s4 <= meta_res2_w__st3;
      out_eth_valid_s4 <= out_eth_valid__st3;
      eth_valid_s4 <= eth_valid__st3;
      out_eth_dst_s4 <= out_eth_dst__st3;
      eth_dst_s4 <= eth_dst__st3;
      out_eth_src_s4 <= out_eth_src__st3;
      eth_src_s4 <= eth_src__st3;
      out_eth_etype_s4 <= out_eth_etype__st3;
      eth_etype_s4 <= eth_etype__st3;
    end
  end

  // ---- Pipeline stage 4 (registered 4 cycle(s) after stage 0) ----
  always_comb begin
    drop = drop_s4;
    meta_res_w__st4 = meta_res_w_s4;
    meta_res2_w__st4 = meta_res2_w_s4;
    out_eth_valid = out_eth_valid_s4;
    eth_valid__st4 = eth_valid_s4;
    out_eth_dst = out_eth_dst_s4;
    eth_dst__st4 = eth_dst_s4;
    out_eth_src = out_eth_src_s4;
    eth_src__st4 = eth_src_s4;
    out_eth_etype = out_eth_etype_s4;
    eth_etype__st4 = eth_etype_s4;

    // apply block (stage 4 of 4)
    meta_res2_w__st4 = my_classify_result;
  end

  always_ff @(posedge clk) begin
    if (!rst_n) valid_out <= 0;
    else        valid_out <= valid_s4;
  end
  assign out_valid = valid_s4;

endmodule
