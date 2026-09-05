module processing_generated (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        valid_in,

  // Header valid flags
  input  logic        ethernet_valid,
  input  logic        ipv4_valid,
  input  logic        srcRoutes_0_valid,
  input  logic        srcRoutes_1_valid,
  input  logic        srcRoutes_2_valid,
  input  logic        srcRoutes_3_valid,
  input  logic        srcRoutes_4_valid,
  input  logic        srcRoutes_5_valid,
  input  logic        srcRoutes_6_valid,
  input  logic        srcRoutes_7_valid,
  input  logic        srcRoutes_8_valid,

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

  // Header valid flag outputs (may be modified by setValid/setInvalid)
  output logic        out_ethernet_valid,
  output logic        out_ipv4_valid,
  output logic        out_srcRoutes_0_valid,
  output logic        out_srcRoutes_1_valid,
  output logic        out_srcRoutes_2_valid,
  output logic        out_srcRoutes_3_valid,
  output logic        out_srcRoutes_4_valid,
  output logic        out_srcRoutes_5_valid,
  output logic        out_srcRoutes_6_valid,
  output logic        out_srcRoutes_7_valid,
  output logic        out_srcRoutes_8_valid,

  // Header field outputs (pass-through, optionally modified)
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
  output logic [0:0] out_srcRoutes_0_bos,
  output logic [14:0] out_srcRoutes_0_port,
  output logic [0:0] out_srcRoutes_1_bos,
  output logic [14:0] out_srcRoutes_1_port,
  output logic [0:0] out_srcRoutes_2_bos,
  output logic [14:0] out_srcRoutes_2_port,
  output logic [0:0] out_srcRoutes_3_bos,
  output logic [14:0] out_srcRoutes_3_port,
  output logic [0:0] out_srcRoutes_4_bos,
  output logic [14:0] out_srcRoutes_4_port,
  output logic [0:0] out_srcRoutes_5_bos,
  output logic [14:0] out_srcRoutes_5_port,
  output logic [0:0] out_srcRoutes_6_bos,
  output logic [14:0] out_srcRoutes_6_port,
  output logic [0:0] out_srcRoutes_7_bos,
  output logic [14:0] out_srcRoutes_7_port,
  output logic [0:0] out_srcRoutes_8_bos,
  output logic [14:0] out_srcRoutes_8_port,

  output logic        valid_out,
  output logic        drop
);

  // ---- Pipeline stage 0 ----
  always_comb begin
    drop = 0;

    // Header valid flag pass-through defaults
    out_ethernet_valid = ethernet_valid;
    out_ipv4_valid = ipv4_valid;
    out_srcRoutes_0_valid = srcRoutes_0_valid;
    out_srcRoutes_1_valid = srcRoutes_1_valid;
    out_srcRoutes_2_valid = srcRoutes_2_valid;
    out_srcRoutes_3_valid = srcRoutes_3_valid;
    out_srcRoutes_4_valid = srcRoutes_4_valid;
    out_srcRoutes_5_valid = srcRoutes_5_valid;
    out_srcRoutes_6_valid = srcRoutes_6_valid;
    out_srcRoutes_7_valid = srcRoutes_7_valid;
    out_srcRoutes_8_valid = srcRoutes_8_valid;

    // Header field pass-through defaults
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
    out_srcRoutes_0_bos = srcRoutes_0_bos;
    out_srcRoutes_0_port = srcRoutes_0_port;
    out_srcRoutes_1_bos = srcRoutes_1_bos;
    out_srcRoutes_1_port = srcRoutes_1_port;
    out_srcRoutes_2_bos = srcRoutes_2_bos;
    out_srcRoutes_2_port = srcRoutes_2_port;
    out_srcRoutes_3_bos = srcRoutes_3_bos;
    out_srcRoutes_3_port = srcRoutes_3_port;
    out_srcRoutes_4_bos = srcRoutes_4_bos;
    out_srcRoutes_4_port = srcRoutes_4_port;
    out_srcRoutes_5_bos = srcRoutes_5_bos;
    out_srcRoutes_5_port = srcRoutes_5_port;
    out_srcRoutes_6_bos = srcRoutes_6_bos;
    out_srcRoutes_6_port = srcRoutes_6_port;
    out_srcRoutes_7_bos = srcRoutes_7_bos;
    out_srcRoutes_7_port = srcRoutes_7_port;
    out_srcRoutes_8_bos = srcRoutes_8_bos;
    out_srcRoutes_8_port = srcRoutes_8_port;

    // apply block
    if (srcRoutes_0_valid) begin
      if ((srcRoutes_0_bos == 'h01)) begin
        out_ethernet_etherType = 'h0800;
      end
      out_std_meta_egress_spec = ((srcRoutes_0_port & 'h01FF) & 'h01FF);
      /* UNIMPLEMENTED EXTERN: _bmv2_pop(0, 'h1) */
      if (ipv4_valid) begin
        out_ipv4_ttl = ((ipv4_ttl + 'hFF) & 'hFF);
      end
    end
    else begin
      drop = 1;
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) valid_out <= 0;
    else        valid_out <= valid_in;
  end

endmodule
