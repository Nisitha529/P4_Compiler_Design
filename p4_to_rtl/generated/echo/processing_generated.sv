module processing_generated (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        valid_in,

  // Header valid flags
  input  logic        eth_valid,
  input  logic        vlan_0_valid,
  input  logic        vlan_1_valid,
  input  logic        ipv4_valid,
  input  logic        ipv4opt_valid,
  input  logic        udp_valid,

  // Header field inputs
  input  logic [47:0] eth_dmac,
  input  logic [47:0] eth_smac,
  input  logic [15:0] eth_type,
  input  logic [2:0] vlan_0_pcp,
  input  logic [0:0] vlan_0_cfi,
  input  logic [11:0] vlan_0_vid,
  input  logic [15:0] vlan_0_tpid,
  input  logic [2:0] vlan_1_pcp,
  input  logic [0:0] vlan_1_cfi,
  input  logic [11:0] vlan_1_vid,
  input  logic [15:0] vlan_1_tpid,
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
  input  logic [15:0] udp_src_port,
  input  logic [15:0] udp_dst_port,
  input  logic [15:0] udp_length,
  input  logic [15:0] udp_checksum,

  // Metadata inputs
  input  logic [15:0] meta_echo_port,

  // Header valid flag outputs (may be modified by setValid/setInvalid)
  output logic        out_eth_valid,
  output logic        out_vlan_0_valid,
  output logic        out_vlan_1_valid,
  output logic        out_ipv4_valid,
  output logic        out_ipv4opt_valid,
  output logic        out_udp_valid,

  // Header field outputs (pass-through, optionally modified)
  output logic [47:0] out_eth_dmac,
  output logic [47:0] out_eth_smac,
  output logic [15:0] out_eth_type,
  output logic [2:0] out_vlan_0_pcp,
  output logic [0:0] out_vlan_0_cfi,
  output logic [11:0] out_vlan_0_vid,
  output logic [15:0] out_vlan_0_tpid,
  output logic [2:0] out_vlan_1_pcp,
  output logic [0:0] out_vlan_1_cfi,
  output logic [11:0] out_vlan_1_vid,
  output logic [15:0] out_vlan_1_tpid,
  output logic [3:0] out_ipv4_version,
  output logic [3:0] out_ipv4_hdr_len,
  output logic [7:0] out_ipv4_tos,
  output logic [15:0] out_ipv4_length,
  output logic [15:0] out_ipv4_id,
  output logic [2:0] out_ipv4_flags,
  output logic [12:0] out_ipv4_offset,
  output logic [7:0] out_ipv4_ttl,
  output logic [7:0] out_ipv4_protocol,
  output logic [15:0] out_ipv4_hdr_chk,
  output logic [31:0] out_ipv4_src,
  output logic [31:0] out_ipv4_dst,
  output logic [319:0] out_ipv4opt_options,
  output logic [15:0] out_udp_src_port,
  output logic [15:0] out_udp_dst_port,
  output logic [15:0] out_udp_length,
  output logic [15:0] out_udp_checksum,

  output logic        valid_out,
  output logic        drop
);

  logic [47:0] tmp_eth_addr;
  logic [31:0] tmp_ip_addr;
  logic [15:0] tmp_udp_port;

  // Metadata shadow locals (writable copies of metadata inputs)
  logic [15:0] meta_echo_port_w;

  // ---- Pipeline stage 0 ----
  always_comb begin
    drop = 0;
    tmp_eth_addr = 48'b0;
    tmp_ip_addr = 32'b0;
    tmp_udp_port = 16'b0;

    // Metadata shadow defaults (init from inputs)
    meta_echo_port_w = meta_echo_port;

    // Header valid flag pass-through defaults
    out_eth_valid = eth_valid;
    out_vlan_0_valid = vlan_0_valid;
    out_vlan_1_valid = vlan_1_valid;
    out_ipv4_valid = ipv4_valid;
    out_ipv4opt_valid = ipv4opt_valid;
    out_udp_valid = udp_valid;

    // Header field pass-through defaults
    out_eth_dmac = eth_dmac;
    out_eth_smac = eth_smac;
    out_eth_type = eth_type;
    out_vlan_0_pcp = vlan_0_pcp;
    out_vlan_0_cfi = vlan_0_cfi;
    out_vlan_0_vid = vlan_0_vid;
    out_vlan_0_tpid = vlan_0_tpid;
    out_vlan_1_pcp = vlan_1_pcp;
    out_vlan_1_cfi = vlan_1_cfi;
    out_vlan_1_vid = vlan_1_vid;
    out_vlan_1_tpid = vlan_1_tpid;
    out_ipv4_version = ipv4_version;
    out_ipv4_hdr_len = ipv4_hdr_len;
    out_ipv4_tos = ipv4_tos;
    out_ipv4_length = ipv4_length;
    out_ipv4_id = ipv4_id;
    out_ipv4_flags = ipv4_flags;
    out_ipv4_offset = ipv4_offset;
    out_ipv4_ttl = ipv4_ttl;
    out_ipv4_protocol = ipv4_protocol;
    out_ipv4_hdr_chk = ipv4_hdr_chk;
    out_ipv4_src = ipv4_src;
    out_ipv4_dst = ipv4_dst;
    out_ipv4opt_options = ipv4opt_options;
    out_udp_src_port = udp_src_port;
    out_udp_dst_port = udp_dst_port;
    out_udp_length = udp_length;
    out_udp_checksum = udp_checksum;

    // apply block
    if (udp_valid) begin
      if (udp_dst_port == meta_echo_port_w) begin
        tmp_eth_addr = eth_dmac;
        out_eth_dmac = eth_smac;
        out_eth_smac = tmp_eth_addr;
        tmp_ip_addr = ipv4_dst;
        out_ipv4_dst = ipv4_src;
        out_ipv4_src = tmp_ip_addr;
        tmp_udp_port = udp_dst_port;
        out_udp_dst_port = udp_src_port;
        out_udp_src_port = tmp_udp_port;
      end
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) valid_out <= 0;
    else        valid_out <= valid_in;
  end

endmodule
