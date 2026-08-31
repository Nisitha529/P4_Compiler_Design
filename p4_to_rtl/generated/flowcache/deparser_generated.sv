module deparser_generated (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        valid_in,

  // Header valid flags
  input  logic        packet_in_valid,
  input  logic        ethernet_valid,
  input  logic        ipv4_valid,

  // Header field inputs
  input  logic [15:0] packet_in_input_port,
  input  logic [7:0] packet_in_punt_reason,
  input  logic [7:0] packet_in_opcode,
  input  logic [47:0] ethernet_dstAddr,
  input  logic [47:0] ethernet_srcAddr,
  input  logic [15:0] ethernet_etherType,
  input  logic [3:0] ipv4_version,
  input  logic [3:0] ipv4_ihl,
  input  logic [7:0] ipv4_diffserv,
  input  logic [15:0] ipv4_totalLen,
  input  logic [15:0] ipv4_identification,
  input  logic [2:0] ipv4_flags,
  input  logic [12:0] ipv4_fragOffset,
  input  logic [7:0] ipv4_ttl,
  input  logic [7:0] ipv4_protocol,
  input  logic [15:0] ipv4_hdrChecksum,
  input  logic [31:0] ipv4_srcAddr,
  input  logic [31:0] ipv4_dstAddr,

  // Packed output [303:0]  layout (MSB first): packet_in(32b) | ethernet(112b) | ipv4(160b)
  output logic [303:0] pkt_hdr_out,
  output logic [15:0]  pkt_hdr_len,
  output logic         valid_out
);

  always_comb begin
    pkt_hdr_out = '0;

    if (packet_in_valid) begin
      pkt_hdr_out[303:272] = {packet_in_input_port, packet_in_punt_reason, packet_in_opcode};
    end

    if (ethernet_valid) begin
      pkt_hdr_out[271:160] = {ethernet_dstAddr, ethernet_srcAddr, ethernet_etherType};
    end

    if (ipv4_valid) begin
      pkt_hdr_out[159:0] = {ipv4_version, ipv4_ihl, ipv4_diffserv, ipv4_totalLen, ipv4_identification, ipv4_flags, ipv4_fragOffset, ipv4_ttl, ipv4_protocol, ipv4_hdrChecksum, ipv4_srcAddr, ipv4_dstAddr};
    end

    pkt_hdr_len = (packet_in_valid ? 16'd32 : 16'd0) + (ethernet_valid ? 16'd112 : 16'd0) + (ipv4_valid ? 16'd160 : 16'd0);
  end

  always_ff @(posedge clk) begin
    if (!rst_n) valid_out <= 0;
    else        valid_out <= valid_in;
  end

endmodule
