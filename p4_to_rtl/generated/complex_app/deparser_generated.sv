module deparser_generated (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        valid_in,

  // Header valid flags
  input  logic        ethernet_valid,
  input  logic        mpls_0_valid,
  input  logic        mpls_1_valid,
  input  logic        mpls_2_valid,
  input  logic        ipv4_valid,
  input  logic        tcp_valid,
  input  logic        udp_valid,

  // Header field inputs
  input  logic [47:0] ethernet_dstAddr,
  input  logic [47:0] ethernet_srcAddr,
  input  logic [15:0] ethernet_etherType,
  input  logic [19:0] mpls_0_label,
  input  logic [2:0] mpls_0_tc,
  input  logic [0:0] mpls_0_bos,
  input  logic [7:0] mpls_0_ttl,
  input  logic [19:0] mpls_1_label,
  input  logic [2:0] mpls_1_tc,
  input  logic [0:0] mpls_1_bos,
  input  logic [7:0] mpls_1_ttl,
  input  logic [19:0] mpls_2_label,
  input  logic [2:0] mpls_2_tc,
  input  logic [0:0] mpls_2_bos,
  input  logic [7:0] mpls_2_ttl,
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
  input  logic [15:0] tcp_srcPort,
  input  logic [15:0] tcp_dstPort,
  input  logic [31:0] tcp_seqNo,
  input  logic [31:0] tcp_ackNo,
  input  logic [3:0] tcp_dataOffset,
  input  logic [3:0] tcp_reserved,
  input  logic [7:0] tcp_flags,
  input  logic [15:0] tcp_window,
  input  logic [15:0] tcp_checksum,
  input  logic [15:0] tcp_urgentPtr,
  input  logic [15:0] udp_srcPort,
  input  logic [15:0] udp_dstPort,
  input  logic [15:0] udp_length,
  input  logic [15:0] udp_checksum,

  // Packed output [591:0]  layout (MSB first): ethernet(112b) | mpls_0(32b) | mpls_1(32b) | mpls_2(32b) | ipv4(160b) | tcp(160b) | udp(64b)
  output logic [591:0] pkt_hdr_out,
  output logic [15:0]  pkt_hdr_len,
  output logic         valid_out
);

  always_comb begin
    pkt_hdr_out = '0;

    if (ethernet_valid) begin
      pkt_hdr_out[591:480] = {ethernet_dstAddr, ethernet_srcAddr, ethernet_etherType};
    end

    if (mpls_0_valid) begin
      pkt_hdr_out[479:448] = {mpls_0_label, mpls_0_tc, mpls_0_bos, mpls_0_ttl};
    end

    if (mpls_1_valid) begin
      pkt_hdr_out[447:416] = {mpls_1_label, mpls_1_tc, mpls_1_bos, mpls_1_ttl};
    end

    if (mpls_2_valid) begin
      pkt_hdr_out[415:384] = {mpls_2_label, mpls_2_tc, mpls_2_bos, mpls_2_ttl};
    end

    if (ipv4_valid) begin
      pkt_hdr_out[383:224] = {ipv4_version, ipv4_ihl, ipv4_diffserv, ipv4_totalLen, ipv4_identification, ipv4_flags, ipv4_fragOffset, ipv4_ttl, ipv4_protocol, ipv4_hdrChecksum, ipv4_srcAddr, ipv4_dstAddr};
    end

    if (tcp_valid) begin
      pkt_hdr_out[223:64] = {tcp_srcPort, tcp_dstPort, tcp_seqNo, tcp_ackNo, tcp_dataOffset, tcp_reserved, tcp_flags, tcp_window, tcp_checksum, tcp_urgentPtr};
    end

    if (udp_valid) begin
      pkt_hdr_out[63:0] = {udp_srcPort, udp_dstPort, udp_length, udp_checksum};
    end

    pkt_hdr_len = (ethernet_valid ? 16'd112 : 16'd0) + (mpls_0_valid ? 16'd32 : 16'd0) + (mpls_1_valid ? 16'd32 : 16'd0) + (mpls_2_valid ? 16'd32 : 16'd0) + (ipv4_valid ? 16'd160 : 16'd0) + (tcp_valid ? 16'd160 : 16'd0) + (udp_valid ? 16'd64 : 16'd0);
  end

  always_ff @(posedge clk) begin
    if (!rst_n) valid_out <= 0;
    else        valid_out <= valid_in;
  end

endmodule
