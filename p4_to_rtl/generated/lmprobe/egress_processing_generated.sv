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
  input  logic [31:0] meta_byte_total,
  input  logic [8:0] meta_port_seen,

  // Standard metadata inputs (table key sources)
  input  logic [8:0] std_meta_egress_port,
  input  logic [15:0] std_meta_packet_length,

  // Header valid flag outputs (may be modified by setValid/setInvalid)
  output logic        out_eth_valid,

  // Header field outputs (pass-through, optionally modified)
  output logic [47:0] out_eth_dst,
  output logic [47:0] out_eth_src,
  output logic [15:0] out_eth_etype,

  // Metadata outputs (final value after the last stage)
  output logic [31:0] out_meta_byte_total,
  output logic [8:0] out_meta_port_seen,

  output logic        out_valid,   // aligned with out_*/drop -- see note
  output logic        valid_out,
  output logic        drop
);

  logic [31:0] byte_cnt;
  logic [31:0] tmp;

  // Metadata shadow locals (writable copies of metadata inputs)
  logic [31:0] meta_byte_total_w;
  logic [8:0] meta_port_seen_w;

  // byte_cnt_reg: register<bit<32>>(16)
  logic [31:0] byte_cnt_reg_mem [0:15];
  logic        byte_cnt_reg_wr_en;
  logic [3:0] byte_cnt_reg_wr_addr;
  logic [31:0] byte_cnt_reg_wr_data;

  // Zero all register memories at simulation start
  // synthesis translate_off
  initial begin
    for (int _si = 0; _si < 16; _si++)
      byte_cnt_reg_mem[_si] = 32'b0;
  end
  // synthesis translate_on

  // Register read wires (isolated via assign)
  logic [31:0] byte_cnt_reg_rd_byte_cnt;
  assign byte_cnt_reg_rd_byte_cnt = byte_cnt_reg_mem[4'(std_meta_egress_port)];

  // Metadata outputs (final value after the last stage)
  assign out_meta_byte_total = meta_byte_total_w;
  assign out_meta_port_seen = meta_port_seen_w;

  // ---- Pipeline stage 0 ----
  always_comb begin
    drop = drop_in;
    byte_cnt = 32'b0;
    tmp = 32'b0;

    // Metadata shadow defaults (init from inputs)
    meta_byte_total_w = meta_byte_total;
    meta_port_seen_w = meta_port_seen;
    byte_cnt_reg_wr_en   = 1'b0;
    byte_cnt_reg_wr_addr = '0;
    byte_cnt_reg_wr_data = '0;

    // Header valid flag pass-through defaults
    out_eth_valid = eth_valid;

    // Header field pass-through defaults
    out_eth_dst = eth_dst;
    out_eth_src = eth_src;
    out_eth_etype = eth_etype;

    // apply block
    byte_cnt = byte_cnt_reg_rd_byte_cnt;
    byte_cnt = byte_cnt + 32'(std_meta_packet_length);
    if (eth_etype == 16'h0801) begin
      tmp = 32'd0;
    end
    else begin
      tmp = byte_cnt;
    end
    byte_cnt_reg_wr_en   = 1'b1;
    byte_cnt_reg_wr_addr = 4'(std_meta_egress_port);
    byte_cnt_reg_wr_data = tmp;
    meta_byte_total_w = byte_cnt;
    meta_port_seen_w = std_meta_egress_port;
  end

  // Register write-back (initialized via initial block above)
  // The write is qualified with the pipeline valid of the stage the
  // write statement lives in. `<reg>_wr_en` alone only says "the
  // program reaches a .write() here": it is combinational from that
  // stage's registers, which HOLD after a packet drains, so without
  // the valid it stays asserted and rewrites the same address every
  // idle cycle. Invisible for a write of a constant (a Bloom filter
  // setting a bit to 1 is idempotent), corrupting for any
  // read-modify-write: the value is re-accumulated once per cycle.
  always_ff @(posedge clk) begin
    if (byte_cnt_reg_wr_en && valid_in)
      byte_cnt_reg_mem[byte_cnt_reg_wr_addr] <= byte_cnt_reg_wr_data;
  end

  always_ff @(posedge clk) begin
    if (!rst_n) valid_out <= 0;
    else        valid_out <= valid_in;
  end
  assign out_valid = valid_in;

endmodule
