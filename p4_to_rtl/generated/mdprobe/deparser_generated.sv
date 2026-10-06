module deparser_generated (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        valid_in,

  // Header valid flags
  input  logic        eth_valid,

  // Header field inputs
  input  logic [47:0] eth_dst,
  input  logic [47:0] eth_src,
  input  logic [15:0] eth_etype,

  // Packed output [111:0]  layout (MSB first): eth(112b)
  output logic [111:0] pkt_hdr_out,
  output logic [15:0]  pkt_hdr_len,
  output logic         valid_out
);

  always_comb begin
    pkt_hdr_out = '0;

    if (eth_valid) begin
      pkt_hdr_out[111:0] = {eth_dst, eth_src, eth_etype};
    end

    pkt_hdr_len = (eth_valid ? 16'd112 : 16'd0);
  end

  always_ff @(posedge clk) begin
    if (!rst_n) valid_out <= 0;
    else        valid_out <= valid_in;
  end

endmodule
