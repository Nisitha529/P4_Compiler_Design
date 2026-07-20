module deparser_generated (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        valid_in,

  // Header valid flags
  input  logic        ethernet_valid,
  input  logic        ipv4_valid,
  input  logic        ipv4_option_valid,
  input  logic        mri_valid,
  input  logic        swtraces_0_valid,
  input  logic        swtraces_1_valid,
  input  logic        swtraces_2_valid,
  input  logic        swtraces_3_valid,
  input  logic        swtraces_4_valid,
  input  logic        swtraces_5_valid,
  input  logic        swtraces_6_valid,
  input  logic        swtraces_7_valid,
  input  logic        swtraces_8_valid,

  // Header field inputs
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
  input  logic [0:0] ipv4_option_copyFlag,
  input  logic [1:0] ipv4_option_optClass,
  input  logic [4:0] ipv4_option_option,
  input  logic [7:0] ipv4_option_optionLength,
  input  logic [15:0] mri_count,
  input  logic [31:0] swtraces_0_swid,
  input  logic [31:0] swtraces_0_qdepth,
  input  logic [31:0] swtraces_1_swid,
  input  logic [31:0] swtraces_1_qdepth,
  input  logic [31:0] swtraces_2_swid,
  input  logic [31:0] swtraces_2_qdepth,
  input  logic [31:0] swtraces_3_swid,
  input  logic [31:0] swtraces_3_qdepth,
  input  logic [31:0] swtraces_4_swid,
  input  logic [31:0] swtraces_4_qdepth,
  input  logic [31:0] swtraces_5_swid,
  input  logic [31:0] swtraces_5_qdepth,
  input  logic [31:0] swtraces_6_swid,
  input  logic [31:0] swtraces_6_qdepth,
  input  logic [31:0] swtraces_7_swid,
  input  logic [31:0] swtraces_7_qdepth,
  input  logic [31:0] swtraces_8_swid,
  input  logic [31:0] swtraces_8_qdepth,

  // Packed output [879:0]  layout (MSB first): ethernet(112b) | ipv4(160b) | ipv4_option(16b) | mri(16b) | swtraces_0(64b) | swtraces_1(64b) | swtraces_2(64b) | swtraces_3(64b) | swtraces_4(64b) | swtraces_5(64b) | swtraces_6(64b) | swtraces_7(64b) | swtraces_8(64b)
  output logic [879:0] pkt_hdr_out,
  output logic [15:0]  pkt_hdr_len,
  output logic         valid_out
);

  always_comb begin
    pkt_hdr_out = '0;
    pkt_hdr_len = 0;

    if (ethernet_valid) begin
      pkt_hdr_out[879:768] = {ethernet_dstAddr, ethernet_srcAddr, ethernet_etherType};
      pkt_hdr_len = pkt_hdr_len + 16'd112;
    end

    if (ipv4_valid) begin
      pkt_hdr_out[767:608] = {ipv4_version, ipv4_ihl, ipv4_diffserv, ipv4_totalLen, ipv4_identification, ipv4_flags, ipv4_fragOffset, ipv4_ttl, ipv4_protocol, ipv4_hdrChecksum, ipv4_srcAddr, ipv4_dstAddr};
      pkt_hdr_len = pkt_hdr_len + 16'd160;
    end

    if (ipv4_option_valid) begin
      pkt_hdr_out[607:592] = {ipv4_option_copyFlag, ipv4_option_optClass, ipv4_option_option, ipv4_option_optionLength};
      pkt_hdr_len = pkt_hdr_len + 16'd16;
    end

    if (mri_valid) begin
      pkt_hdr_out[591:576] = {mri_count};
      pkt_hdr_len = pkt_hdr_len + 16'd16;
    end

    if (swtraces_0_valid) begin
      pkt_hdr_out[575:512] = {swtraces_0_swid, swtraces_0_qdepth};
      pkt_hdr_len = pkt_hdr_len + 16'd64;
    end

    if (swtraces_1_valid) begin
      pkt_hdr_out[511:448] = {swtraces_1_swid, swtraces_1_qdepth};
      pkt_hdr_len = pkt_hdr_len + 16'd64;
    end

    if (swtraces_2_valid) begin
      pkt_hdr_out[447:384] = {swtraces_2_swid, swtraces_2_qdepth};
      pkt_hdr_len = pkt_hdr_len + 16'd64;
    end

    if (swtraces_3_valid) begin
      pkt_hdr_out[383:320] = {swtraces_3_swid, swtraces_3_qdepth};
      pkt_hdr_len = pkt_hdr_len + 16'd64;
    end

    if (swtraces_4_valid) begin
      pkt_hdr_out[319:256] = {swtraces_4_swid, swtraces_4_qdepth};
      pkt_hdr_len = pkt_hdr_len + 16'd64;
    end

    if (swtraces_5_valid) begin
      pkt_hdr_out[255:192] = {swtraces_5_swid, swtraces_5_qdepth};
      pkt_hdr_len = pkt_hdr_len + 16'd64;
    end

    if (swtraces_6_valid) begin
      pkt_hdr_out[191:128] = {swtraces_6_swid, swtraces_6_qdepth};
      pkt_hdr_len = pkt_hdr_len + 16'd64;
    end

    if (swtraces_7_valid) begin
      pkt_hdr_out[127:64] = {swtraces_7_swid, swtraces_7_qdepth};
      pkt_hdr_len = pkt_hdr_len + 16'd64;
    end

    if (swtraces_8_valid) begin
      pkt_hdr_out[63:0] = {swtraces_8_swid, swtraces_8_qdepth};
      pkt_hdr_len = pkt_hdr_len + 16'd64;
    end

  end

  always_ff @(posedge clk) begin
    if (!rst_n) valid_out <= 0;
    else        valid_out <= valid_in;
  end

endmodule
