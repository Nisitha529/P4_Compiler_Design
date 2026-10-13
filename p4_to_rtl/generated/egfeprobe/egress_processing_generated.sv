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
  input  logic [15:0] meta_qd,

  // Standard metadata inputs (table key sources)
  input  logic [18:0] std_meta_deq_qdepth,

  // Header valid flag outputs (may be modified by setValid/setInvalid)
  output logic        out_eth_valid,

  // Header field outputs (pass-through, optionally modified)
  output logic [47:0] out_eth_dst,
  output logic [47:0] out_eth_src,
  output logic [15:0] out_eth_etype,

  // Metadata outputs (final value after the last stage)
  output logic [15:0] out_meta_qd,

  // FeatureExport pushes. The staging FIFO and the AXI4-Stream
  // master port live in the shell; this module just produces records.
  // tdata is padded up to a byte multiple, pad bits in the LOW bits.
  output logic        qos_feed_push,
  output logic [31:0] qos_feed_data,

  output logic        out_valid,   // aligned with out_*/drop -- see note
  output logic        valid_out,
  output logic        drop
);

  // Metadata shadow locals (writable copies of metadata inputs)
  logic [15:0] meta_qd_w;

  // ── FeatureExport push outputs ───────────────────────────────────────
  // qos_feed: 32-bit record padded to 32, pushed in stage 0
  // record layout, high bits first:
  //   [31:16] deq_qdepth (16b)
  //   [15:0] eth_dst_15_0 (16b)
  logic        qos_feed_push_c;
  logic [31:0] qos_feed_data_c;
  always_ff @(posedge clk) begin
    if (!rst_n) qos_feed_push <= 1'b0;
    else begin
      qos_feed_push <= qos_feed_push_c && valid_in;
      if (qos_feed_push_c && valid_in) qos_feed_data <= qos_feed_data_c;
    end
  end

  // Metadata outputs (final value after the last stage)
  assign out_meta_qd = meta_qd_w;

  // ---- Pipeline stage 0 ----
  always_comb begin
    drop = drop_in;

    // Metadata shadow defaults (init from inputs)
    meta_qd_w = meta_qd;
    qos_feed_push_c = 1'b0;
    qos_feed_data_c = '0;

    // Header valid flag pass-through defaults
    out_eth_valid = eth_valid;

    // Header field pass-through defaults
    out_eth_dst = eth_dst;
    out_eth_src = eth_src;
    out_eth_etype = eth_etype;

    // apply block
    meta_qd_w = 16'(std_meta_deq_qdepth);
    qos_feed_push_c = 1'b1;
    qos_feed_data_c = {16'(std_meta_deq_qdepth), eth_dst[15:0]};
  end

  always_ff @(posedge clk) begin
    if (!rst_n) valid_out <= 0;
    else        valid_out <= valid_in;
  end
  assign out_valid = valid_in;

endmodule
