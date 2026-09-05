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
  input  logic [0:0] meta_v1,
  input  logic [31:0] meta_pos,

  // Header valid flag outputs (may be modified by setValid/setInvalid)
  output logic        out_eth_valid,

  // Header field outputs (pass-through, optionally modified)
  output logic [47:0] out_eth_dst,
  output logic [47:0] out_eth_src,
  output logic [15:0] out_eth_etype,

  output logic        valid_out,
  output logic        drop
);

  // Metadata shadow locals (writable copies of metadata inputs)
  logic [0:0] meta_v1_w;
  logic [31:0] meta_pos_w;

  // bloom_1: register<bit<1>>(4096)
  logic [0:0] bloom_1_mem [0:4095];
  logic        bloom_1_wr_en;
  logic [11:0] bloom_1_wr_addr;
  logic [0:0] bloom_1_wr_data;

  // Zero all register memories at simulation start
  // synthesis translate_off
  initial begin
    for (int _si = 0; _si < 4096; _si++)
      bloom_1_mem[_si] = 1'b0;
  end
  // synthesis translate_on

  // Register read wires (isolated via assign)
  logic [0:0] bloom_1_rd_meta_v1;
  assign bloom_1_rd_meta_v1 = bloom_1_mem[eth_dst[31:0]];

  // ---- Pipeline stage 0 ----
  always_comb begin
    drop = 0;

    // Metadata shadow defaults (init from inputs)
    meta_v1_w = meta_v1;
    meta_pos_w = meta_pos;
    bloom_1_wr_en   = 1'b0;
    bloom_1_wr_addr = '0;
    bloom_1_wr_data = '0;

    // Header valid flag pass-through defaults
    out_eth_valid = eth_valid;

    // Header field pass-through defaults
    out_eth_dst = eth_dst;
    out_eth_src = eth_src;
    out_eth_etype = eth_etype;

    // apply block
    if (eth_etype == 16'h0800) begin
      bloom_1_wr_en   = 1'b1;
      bloom_1_wr_addr = eth_src[31:0];
      bloom_1_wr_data = eth_dst[0:0];
    end
    meta_v1_w = bloom_1_rd_meta_v1;
    out_eth_etype = 16'(meta_v1_w);
  end

  // Register write-back (initialized via initial block above)
  always_ff @(posedge clk) begin
    if (bloom_1_wr_en)
      bloom_1_mem[bloom_1_wr_addr] <= bloom_1_wr_data;
  end

  always_ff @(posedge clk) begin
    if (!rst_n) valid_out <= 0;
    else        valid_out <= valid_in;
  end

endmodule
