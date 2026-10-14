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
  input  logic [7:0] meta_enqd,
  input  logic [7:0] meta_deqd,

  // Standard metadata inputs (table key sources)
  input  logic [18:0] std_meta_deq_qdepth,
  input  logic [18:0] std_meta_enq_qdepth,

  // Header valid flag outputs (may be modified by setValid/setInvalid)
  output logic        out_eth_valid,

  // Header field outputs (pass-through, optionally modified)
  output logic [47:0] out_eth_dst,
  output logic [47:0] out_eth_src,
  output logic [15:0] out_eth_etype,

  // Metadata outputs (final value after the last stage)
  output logic [7:0] out_meta_enqd,
  output logic [7:0] out_meta_deqd,

  // FeatureExport pushes. The staging FIFO and the AXI4-Stream
  // master port live in the shell; this module just produces records.
  // tdata is padded up to a byte multiple, pad bits in the LOW bits.
  output logic        qd_feed_push,
  output logic [31:0] qd_feed_data,

  output logic        out_valid,   // aligned with out_*/drop -- see note
  output logic        valid_out,
  output logic        drop
);

  // Metadata shadow locals (writable copies of metadata inputs)
  logic [7:0] meta_enqd_w;
  logic [7:0] meta_deqd_w;

  // ── FeatureExport push outputs ───────────────────────────────────────
  // qd_feed: 32-bit record padded to 32, pushed in stage 0
  // record layout, high bits first:
  //   [31:24] enq_qdepth (8b)
  //   [23:16] deq_qdepth (8b)
  //   [15:0] eth_dst_15_0 (16b)
  logic        qd_feed_push_c;
  logic [31:0] qd_feed_data_c;
  always_ff @(posedge clk) begin
    if (!rst_n) qd_feed_push <= 1'b0;
    else begin
      qd_feed_push <= qd_feed_push_c && valid_in;
      if (qd_feed_push_c && valid_in) qd_feed_data <= qd_feed_data_c;
    end
  end

  // Metadata outputs (final value after the last stage)
  assign out_meta_enqd = meta_enqd_w;
  assign out_meta_deqd = meta_deqd_w;

  // ---- Pipeline stage 0 ----
  always_comb begin
    drop = drop_in;

    // Metadata shadow defaults (init from inputs)
    meta_enqd_w = meta_enqd;
    meta_deqd_w = meta_deqd;
    qd_feed_push_c = 1'b0;
    qd_feed_data_c = '0;

    // Header valid flag pass-through defaults
    out_eth_valid = eth_valid;

    // Header field pass-through defaults
    out_eth_dst = eth_dst;
    out_eth_src = eth_src;
    out_eth_etype = eth_etype;

    // apply block
    meta_enqd_w = 8'(std_meta_enq_qdepth);
    meta_deqd_w = 8'(std_meta_deq_qdepth);
    qd_feed_push_c = 1'b1;
    qd_feed_data_c = {8'(std_meta_enq_qdepth), 8'(std_meta_deq_qdepth), eth_dst[15:0]};
  end

  always_ff @(posedge clk) begin
    if (!rst_n) valid_out <= 0;
    else        valid_out <= valid_in;
  end
  assign out_valid = valid_in;

endmodule
