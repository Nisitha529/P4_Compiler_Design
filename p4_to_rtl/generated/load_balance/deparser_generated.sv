module deparser_generated (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        valid_in,

  // Header valid flags
  input  logic        ethernet_valid,
  input  logic        ipv4_valid,
  input  logic        tcp_valid,

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
  input  logic [15:0] tcp_srcPort,
  input  logic [15:0] tcp_dstPort,
  input  logic [31:0] tcp_seqNo,
  input  logic [31:0] tcp_ackNo,
  input  logic [3:0] tcp_dataOffset,
  input  logic [2:0] tcp_res,
  input  logic [2:0] tcp_ecn,
  input  logic [5:0] tcp_ctrl,
  input  logic [15:0] tcp_window,
  input  logic [15:0] tcp_checksum,
  input  logic [15:0] tcp_urgentPtr,

  // Packed output [431:0]  layout (MSB first): ethernet(112b) | ipv4(160b) | tcp(160b)
  output logic [431:0] pkt_hdr_out,
  output logic [15:0]  pkt_hdr_len,
  output logic         valid_out
);

  always_comb begin
    pkt_hdr_out = '0;

    if (ethernet_valid) begin
      pkt_hdr_out[431:320] = {ethernet_dstAddr, ethernet_srcAddr, ethernet_etherType};
    end

    if (ipv4_valid) begin
      pkt_hdr_out[319:160] = {ipv4_version, ipv4_ihl, ipv4_diffserv, ipv4_totalLen, ipv4_identification, ipv4_flags, ipv4_fragOffset, ipv4_ttl, ipv4_protocol, ipv4_hdrChecksum, ipv4_srcAddr, ipv4_dstAddr};
    end

    if (tcp_valid) begin
      pkt_hdr_out[159:0] = {tcp_srcPort, tcp_dstPort, tcp_seqNo, tcp_ackNo, tcp_dataOffset, tcp_res, tcp_ecn, tcp_ctrl, tcp_window, tcp_checksum, tcp_urgentPtr};
    end

    pkt_hdr_len = (ethernet_valid ? 16'd112 : 16'd0) + (ipv4_valid ? 16'd160 : 16'd0) + (tcp_valid ? 16'd160 : 16'd0);
  end

  always_ff @(posedge clk) begin
    if (!rst_n) valid_out <= 0;
    else        valid_out <= valid_in;
  end

endmodule
