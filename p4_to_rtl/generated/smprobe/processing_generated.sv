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
  input  logic [63:0] meta_ts,
  input  logic [15:0] meta_nbytes,

  // Standard metadata inputs (table key sources)
  input  logic [63:0] std_meta_ingress_timestamp,
  input  logic [15:0] std_meta_parsed_bytes,
  input  logic [2:0] std_meta_parser_error,

  // Header valid flag outputs (may be modified by setValid/setInvalid)
  output logic        out_eth_valid,

  // Header field outputs (pass-through, optionally modified)
  output logic [47:0] out_eth_dst,
  output logic [47:0] out_eth_src,
  output logic [15:0] out_eth_etype,

  // Metadata outputs (final value after the last stage)
  output logic [63:0] out_meta_ts,
  output logic [15:0] out_meta_nbytes,

  output logic        valid_out,
  output logic        drop
);

  // Metadata shadow locals (writable copies of metadata inputs)
  logic [63:0] meta_ts_w;
  logic [15:0] meta_nbytes_w;

  // Metadata outputs (final value after the last stage)
  assign out_meta_ts = meta_ts_w;
  assign out_meta_nbytes = meta_nbytes_w;

  // ---- Pipeline stage 0 ----
  always_comb begin
    drop = 0;

    // Metadata shadow defaults (init from inputs)
    meta_ts_w = meta_ts;
    meta_nbytes_w = meta_nbytes;

    // Header valid flag pass-through defaults
    out_eth_valid = eth_valid;

    // Header field pass-through defaults
    out_eth_dst = eth_dst;
    out_eth_src = eth_src;
    out_eth_etype = eth_etype;

    // apply block
    meta_ts_w = std_meta_ingress_timestamp;
    meta_nbytes_w = std_meta_parsed_bytes;
    if (std_meta_parser_error != 3'd0) begin
      drop = 1'd1;
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) valid_out <= 0;
    else        valid_out <= valid_in;
  end

endmodule
