module egress_processing_generated (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        valid_in,

  // Header valid flags
  input  logic        packet_in_valid,
  input  logic        packet_out_valid,
  input  logic        ethernet_valid,
  input  logic        ipv4_valid,

  // Header field inputs
  input  logic [15:0] packet_in_input_port,
  input  logic [7:0] packet_in_punt_reason,
  input  logic [7:0] packet_in_opcode,
  input  logic [7:0] packet_out_opcode,
  input  logic [7:0] packet_out_reserved1,
  input  logic [31:0] packet_out_operand0,
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

  // Metadata inputs
  input  logic [8:0] meta_ingress_port,
  input  logic [7:0] meta_punt_reason,
  input  logic [7:0] meta_opcode,

  // Standard metadata inputs (table key sources)
  input  logic [8:0] std_meta_egress_port,

  // Header valid flag outputs (may be modified by setValid/setInvalid)
  output logic        out_packet_in_valid,
  output logic        out_packet_out_valid,
  output logic        out_ethernet_valid,
  output logic        out_ipv4_valid,

  // Header field outputs (pass-through, optionally modified)
  output logic [15:0] out_packet_in_input_port,
  output logic [7:0] out_packet_in_punt_reason,
  output logic [7:0] out_packet_in_opcode,
  output logic [7:0] out_packet_out_opcode,
  output logic [7:0] out_packet_out_reserved1,
  output logic [31:0] out_packet_out_operand0,
  output logic [47:0] out_ethernet_dstAddr,
  output logic [47:0] out_ethernet_srcAddr,
  output logic [15:0] out_ethernet_etherType,
  output logic [3:0] out_ipv4_version,
  output logic [3:0] out_ipv4_ihl,
  output logic [7:0] out_ipv4_diffserv,
  output logic [15:0] out_ipv4_totalLen,
  output logic [15:0] out_ipv4_identification,
  output logic [2:0] out_ipv4_flags,
  output logic [12:0] out_ipv4_fragOffset,
  output logic [7:0] out_ipv4_ttl,
  output logic [7:0] out_ipv4_protocol,
  output logic [15:0] out_ipv4_hdrChecksum,
  output logic [31:0] out_ipv4_srcAddr,
  output logic [31:0] out_ipv4_dstAddr,

  // Metadata outputs (final value after the last stage)
  output logic [8:0] out_meta_ingress_port,
  output logic [7:0] out_meta_punt_reason,
  output logic [7:0] out_meta_opcode,

  output logic        valid_out,
  output logic        drop
);

  logic [15:0] tmp_1;

  // Metadata shadow locals (writable copies of metadata inputs)
  logic [8:0] meta_ingress_port_w;
  logic [7:0] meta_punt_reason_w;
  logic [7:0] meta_opcode_w;

  // update_checksum -> ipv4.hdrChecksum
  wire [143:0] chk0_concat = {out_ipv4_version, out_ipv4_ihl, out_ipv4_diffserv, out_ipv4_totalLen, out_ipv4_identification, out_ipv4_flags, out_ipv4_fragOffset, out_ipv4_ttl, out_ipv4_protocol, out_ipv4_srcAddr, out_ipv4_dstAddr};
  wire [31:0] chk0_sum   = {16'd0, chk0_concat[143:128]} + {16'd0, chk0_concat[127:112]} + {16'd0, chk0_concat[111:96]} + {16'd0, chk0_concat[95:80]} + {16'd0, chk0_concat[79:64]} + {16'd0, chk0_concat[63:48]} + {16'd0, chk0_concat[47:32]} + {16'd0, chk0_concat[31:16]} + {16'd0, chk0_concat[15:0]};
  wire [16:0] chk0_fold1 = chk0_sum[15:0] + chk0_sum[31:16];
  wire [16:0] chk0_fold2 = {15'd0, chk0_fold1[16]} + {1'b0, chk0_fold1[15:0]};
  wire [15:0] chk0_value = ~chk0_fold2[15:0];

  // Metadata outputs (final value after the last stage)
  assign out_meta_ingress_port = meta_ingress_port_w;
  assign out_meta_punt_reason = meta_punt_reason_w;
  assign out_meta_opcode = meta_opcode_w;

  // ---- Pipeline stage 0 ----
  always_comb begin
    drop = 0;
    tmp_1 = 16'b0;

    // Metadata shadow defaults (init from inputs)
    meta_ingress_port_w = meta_ingress_port;
    meta_punt_reason_w = meta_punt_reason;
    meta_opcode_w = meta_opcode;

    // Header valid flag pass-through defaults
    out_packet_in_valid = packet_in_valid;
    out_packet_out_valid = packet_out_valid;
    out_ethernet_valid = ethernet_valid;
    out_ipv4_valid = ipv4_valid;

    // Header field pass-through defaults
    out_packet_in_input_port = packet_in_input_port;
    out_packet_in_punt_reason = packet_in_punt_reason;
    out_packet_in_opcode = packet_in_opcode;
    out_packet_out_opcode = packet_out_opcode;
    out_packet_out_reserved1 = packet_out_reserved1;
    out_packet_out_operand0 = packet_out_operand0;
    out_ethernet_dstAddr = ethernet_dstAddr;
    out_ethernet_srcAddr = ethernet_srcAddr;
    out_ethernet_etherType = ethernet_etherType;
    out_ipv4_version = ipv4_version;
    out_ipv4_ihl = ipv4_ihl;
    out_ipv4_diffserv = ipv4_diffserv;
    out_ipv4_totalLen = ipv4_totalLen;
    out_ipv4_identification = ipv4_identification;
    out_ipv4_flags = ipv4_flags;
    out_ipv4_fragOffset = ipv4_fragOffset;
    out_ipv4_ttl = ipv4_ttl;
    out_ipv4_protocol = ipv4_protocol;
    out_ipv4_hdrChecksum = ipv4_hdrChecksum;
    out_ipv4_srcAddr = ipv4_srcAddr;
    out_ipv4_dstAddr = ipv4_dstAddr;

    // apply block
    if ((std_meta_egress_port == 'h01FE)) begin
      out_packet_in_valid = 1'b1;
      out_packet_in_input_port = (meta_ingress_port_w & 'hFFFF);
      out_packet_in_punt_reason = meta_punt_reason_w;
      out_packet_in_opcode = 'h00;
      tmp_1 = ((ipv4_dstAddr & 'h3F) & 'hFFFFFFFF);
      /* UNIMPLEMENTED EXTERN: _bmv2_count(0, tmp_1) */
    end

    // update_checksum() writes -- final stage only,
    // needs the packet's fully-resolved header state
    if (ipv4_valid) out_ipv4_hdrChecksum = chk0_value;
  end

  always_ff @(posedge clk) begin
    if (!rst_n) valid_out <= 0;
    else        valid_out <= valid_in;
  end

endmodule
