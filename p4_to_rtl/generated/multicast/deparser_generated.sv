module deparser_generated (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        valid_in,

  // Header valid flags
  input  logic        ethernet_valid,

  // Header field inputs
  input  logic [47:0] ethernet_dstAddr,
  input  logic [47:0] ethernet_srcAddr,
  input  logic [15:0] ethernet_etherType,

  // Packed output [111:0]  layout (MSB first): ethernet(112b)
  output logic [111:0] pkt_hdr_out,
  output logic [15:0]  pkt_hdr_len,
  output logic         valid_out
);

  always_comb begin
    pkt_hdr_out = '0;
    pkt_hdr_len = 0;

    if (ethernet_valid) begin
      pkt_hdr_out[111:0] = {ethernet_dstAddr, ethernet_srcAddr, ethernet_etherType};
      pkt_hdr_len = pkt_hdr_len + 16'd112;
    end

  end

  always_ff @(posedge clk) begin
    if (!rst_n) valid_out <= 0;
    else        valid_out <= valid_in;
  end

endmodule
