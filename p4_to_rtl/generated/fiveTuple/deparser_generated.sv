module deparser_generated (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        valid_in,

  // Header valid flags
  input  logic        eth_valid,
  input  logic        new_vlan_valid,
  input  logic        vlan_valid,
  input  logic        ipv4_valid,
  input  logic        ipv4opt_valid,
  input  logic        tcp_valid,
  input  logic        tcpopt_valid,
  input  logic        udp_valid,

  // Header field inputs
  input  logic [47:0] eth_dmac,
  input  logic [47:0] eth_smac,
  input  logic [15:0] eth_type,
  input  logic [2:0] new_vlan_pcp,
  input  logic [0:0] new_vlan_cfi,
  input  logic [11:0] new_vlan_vid,
  input  logic [15:0] new_vlan_tpid,
  input  logic [2:0] vlan_pcp,
  input  logic [0:0] vlan_cfi,
  input  logic [11:0] vlan_vid,
  input  logic [15:0] vlan_tpid,
  input  logic [3:0] ipv4_version,
  input  logic [3:0] ipv4_hdr_len,
  input  logic [7:0] ipv4_tos,
  input  logic [15:0] ipv4_length,
  input  logic [15:0] ipv4_id,
  input  logic [2:0] ipv4_flags,
  input  logic [12:0] ipv4_offset,
  input  logic [7:0] ipv4_ttl,
  input  logic [7:0] ipv4_protocol,
  input  logic [15:0] ipv4_hdr_chk,
  input  logic [31:0] ipv4_src,
  input  logic [31:0] ipv4_dst,
  input  logic [319:0] ipv4opt_options,
  input  logic [15:0] tcp_src_port,
  input  logic [15:0] tcp_dst_port,
  input  logic [31:0] tcp_seqNum,
  input  logic [31:0] tcp_ackNum,
  input  logic [3:0] tcp_dataOffset,
  input  logic [5:0] tcp_resv,
  input  logic [5:0] tcp_flags,
  input  logic [15:0] tcp_window,
  input  logic [15:0] tcp_checksum,
  input  logic [15:0] tcp_urgPtr,
  input  logic [319:0] tcpopt_options,
  input  logic [15:0] udp_src_port,
  input  logic [15:0] udp_dst_port,
  input  logic [15:0] udp_length,
  input  logic [15:0] udp_checksum,

  // Packed output [1199:0]  layout (MSB first): eth(112b) | new_vlan(32b) | vlan(32b) | ipv4(160b) | ipv4opt(320b) | tcp(160b) | tcpopt(320b) | udp(64b)
  output logic [1199:0] pkt_hdr_out,
  output logic [15:0]  pkt_hdr_len,
  output logic         valid_out
);

  always_comb begin
    pkt_hdr_out = '0;

    if (eth_valid) begin
      pkt_hdr_out[1199:1088] = {eth_dmac, eth_smac, eth_type};
    end

    if (new_vlan_valid) begin
      pkt_hdr_out[1087:1056] = {new_vlan_pcp, new_vlan_cfi, new_vlan_vid, new_vlan_tpid};
    end

    if (vlan_valid) begin
      pkt_hdr_out[1055:1024] = {vlan_pcp, vlan_cfi, vlan_vid, vlan_tpid};
    end

    if (ipv4_valid) begin
      pkt_hdr_out[1023:864] = {ipv4_version, ipv4_hdr_len, ipv4_tos, ipv4_length, ipv4_id, ipv4_flags, ipv4_offset, ipv4_ttl, ipv4_protocol, ipv4_hdr_chk, ipv4_src, ipv4_dst};
    end

    if (ipv4opt_valid) begin
      pkt_hdr_out[863:544] = {ipv4opt_options};
    end

    if (tcp_valid) begin
      pkt_hdr_out[543:384] = {tcp_src_port, tcp_dst_port, tcp_seqNum, tcp_ackNum, tcp_dataOffset, tcp_resv, tcp_flags, tcp_window, tcp_checksum, tcp_urgPtr};
    end

    if (tcpopt_valid) begin
      pkt_hdr_out[383:64] = {tcpopt_options};
    end

    if (udp_valid) begin
      pkt_hdr_out[63:0] = {udp_src_port, udp_dst_port, udp_length, udp_checksum};
    end

    pkt_hdr_len = (eth_valid ? 16'd112 : 16'd0) + (new_vlan_valid ? 16'd32 : 16'd0) + (vlan_valid ? 16'd32 : 16'd0) + (ipv4_valid ? 16'd160 : 16'd0) + (ipv4opt_valid ? 16'd320 : 16'd0) + (tcp_valid ? 16'd160 : 16'd0) + (tcpopt_valid ? 16'd320 : 16'd0) + (udp_valid ? 16'd64 : 16'd0);
  end

  always_ff @(posedge clk) begin
    if (!rst_n) valid_out <= 0;
    else        valid_out <= valid_in;
  end

endmodule
