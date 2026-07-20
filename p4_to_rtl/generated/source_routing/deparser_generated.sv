module deparser_generated (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        valid_in,

  // Header valid flags
  input  logic        ethernet_valid,
  input  logic        srcRoutes_0_valid,
  input  logic        srcRoutes_1_valid,
  input  logic        srcRoutes_2_valid,
  input  logic        srcRoutes_3_valid,
  input  logic        srcRoutes_4_valid,
  input  logic        srcRoutes_5_valid,
  input  logic        srcRoutes_6_valid,
  input  logic        srcRoutes_7_valid,
  input  logic        srcRoutes_8_valid,
  input  logic        ipv4_valid,

  // Header field inputs
  input  logic [47:0] ethernet_dstAddr,
  input  logic [47:0] ethernet_srcAddr,
  input  logic [15:0] ethernet_etherType,
  input  logic [0:0] srcRoutes_0_bos,
  input  logic [14:0] srcRoutes_0_port,
  input  logic [0:0] srcRoutes_1_bos,
  input  logic [14:0] srcRoutes_1_port,
  input  logic [0:0] srcRoutes_2_bos,
  input  logic [14:0] srcRoutes_2_port,
  input  logic [0:0] srcRoutes_3_bos,
  input  logic [14:0] srcRoutes_3_port,
  input  logic [0:0] srcRoutes_4_bos,
  input  logic [14:0] srcRoutes_4_port,
  input  logic [0:0] srcRoutes_5_bos,
  input  logic [14:0] srcRoutes_5_port,
  input  logic [0:0] srcRoutes_6_bos,
  input  logic [14:0] srcRoutes_6_port,
  input  logic [0:0] srcRoutes_7_bos,
  input  logic [14:0] srcRoutes_7_port,
  input  logic [0:0] srcRoutes_8_bos,
  input  logic [14:0] srcRoutes_8_port,
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

  // Packed output [415:0]  layout (MSB first): ethernet(112b) | srcRoutes_0(16b) | srcRoutes_1(16b) | srcRoutes_2(16b) | srcRoutes_3(16b) | srcRoutes_4(16b) | srcRoutes_5(16b) | srcRoutes_6(16b) | srcRoutes_7(16b) | srcRoutes_8(16b) | ipv4(160b)
  output logic [415:0] pkt_hdr_out,
  output logic [15:0]  pkt_hdr_len,
  output logic         valid_out
);

  always_comb begin
    pkt_hdr_out = '0;
    pkt_hdr_len = 0;

    if (ethernet_valid) begin
      pkt_hdr_out[415:304] = {ethernet_dstAddr, ethernet_srcAddr, ethernet_etherType};
      pkt_hdr_len = pkt_hdr_len + 16'd112;
    end

    if (srcRoutes_0_valid) begin
      pkt_hdr_out[303:288] = {srcRoutes_0_bos, srcRoutes_0_port};
      pkt_hdr_len = pkt_hdr_len + 16'd16;
    end

    if (srcRoutes_1_valid) begin
      pkt_hdr_out[287:272] = {srcRoutes_1_bos, srcRoutes_1_port};
      pkt_hdr_len = pkt_hdr_len + 16'd16;
    end

    if (srcRoutes_2_valid) begin
      pkt_hdr_out[271:256] = {srcRoutes_2_bos, srcRoutes_2_port};
      pkt_hdr_len = pkt_hdr_len + 16'd16;
    end

    if (srcRoutes_3_valid) begin
      pkt_hdr_out[255:240] = {srcRoutes_3_bos, srcRoutes_3_port};
      pkt_hdr_len = pkt_hdr_len + 16'd16;
    end

    if (srcRoutes_4_valid) begin
      pkt_hdr_out[239:224] = {srcRoutes_4_bos, srcRoutes_4_port};
      pkt_hdr_len = pkt_hdr_len + 16'd16;
    end

    if (srcRoutes_5_valid) begin
      pkt_hdr_out[223:208] = {srcRoutes_5_bos, srcRoutes_5_port};
      pkt_hdr_len = pkt_hdr_len + 16'd16;
    end

    if (srcRoutes_6_valid) begin
      pkt_hdr_out[207:192] = {srcRoutes_6_bos, srcRoutes_6_port};
      pkt_hdr_len = pkt_hdr_len + 16'd16;
    end

    if (srcRoutes_7_valid) begin
      pkt_hdr_out[191:176] = {srcRoutes_7_bos, srcRoutes_7_port};
      pkt_hdr_len = pkt_hdr_len + 16'd16;
    end

    if (srcRoutes_8_valid) begin
      pkt_hdr_out[175:160] = {srcRoutes_8_bos, srcRoutes_8_port};
      pkt_hdr_len = pkt_hdr_len + 16'd16;
    end

    if (ipv4_valid) begin
      pkt_hdr_out[159:0] = {ipv4_version, ipv4_ihl, ipv4_diffserv, ipv4_totalLen, ipv4_identification, ipv4_flags, ipv4_fragOffset, ipv4_ttl, ipv4_protocol, ipv4_hdrChecksum, ipv4_srcAddr, ipv4_dstAddr};
      pkt_hdr_len = pkt_hdr_len + 16'd160;
    end

  end

  always_ff @(posedge clk) begin
    if (!rst_n) valid_out <= 0;
    else        valid_out <= valid_in;
  end

endmodule
