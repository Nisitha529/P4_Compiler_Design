module egress_processing_generated (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        valid_in,

  // Header valid flags
  input  logic        ethernet_valid,
  input  logic        ipv4_valid,

  // Header field inputs
  input  logic [47:0] ethernet_dstAddr,
  input  logic [47:0] ethernet_srcAddr,
  input  logic [15:0] ethernet_etherType,
  input  logic [3:0] ipv4_version,
  input  logic [3:0] ipv4_ihl,
  input  logic [5:0] ipv4_diffserv,
  input  logic [1:0] ipv4_ecn,
  input  logic [15:0] ipv4_totalLen,
  input  logic [15:0] ipv4_identification,
  input  logic [2:0] ipv4_flags,
  input  logic [12:0] ipv4_fragOffset,
  input  logic [7:0] ipv4_ttl,
  input  logic [7:0] ipv4_protocol,
  input  logic [15:0] ipv4_hdrChecksum,
  input  logic [31:0] ipv4_srcAddr,
  input  logic [31:0] ipv4_dstAddr,

  // Standard metadata inputs (table key sources)
  input  logic [18:0] std_meta_enq_qdepth,

  // Header valid flag outputs (may be modified by setValid/setInvalid)
  output logic        out_ethernet_valid,
  output logic        out_ipv4_valid,

  // Header field outputs (pass-through, optionally modified)
  output logic [47:0] out_ethernet_dstAddr,
  output logic [47:0] out_ethernet_srcAddr,
  output logic [15:0] out_ethernet_etherType,
  output logic [3:0] out_ipv4_version,
  output logic [3:0] out_ipv4_ihl,
  output logic [5:0] out_ipv4_diffserv,
  output logic [1:0] out_ipv4_ecn,
  output logic [15:0] out_ipv4_totalLen,
  output logic [15:0] out_ipv4_identification,
  output logic [2:0] out_ipv4_flags,
  output logic [12:0] out_ipv4_fragOffset,
  output logic [7:0] out_ipv4_ttl,
  output logic [7:0] out_ipv4_protocol,
  output logic [15:0] out_ipv4_hdrChecksum,
  output logic [31:0] out_ipv4_srcAddr,
  output logic [31:0] out_ipv4_dstAddr,

  output logic        valid_out,
  output logic        drop
);

  // update_checksum -> ipv4.hdrChecksum
  wire [143:0] chk0_concat = {out_ipv4_version, out_ipv4_ihl, out_ipv4_diffserv, out_ipv4_ecn, out_ipv4_totalLen, out_ipv4_identification, out_ipv4_flags, out_ipv4_fragOffset, out_ipv4_ttl, out_ipv4_protocol, out_ipv4_srcAddr, out_ipv4_dstAddr};
  wire [31:0] chk0_sum   = {16'd0, chk0_concat[143:128]} + {16'd0, chk0_concat[127:112]} + {16'd0, chk0_concat[111:96]} + {16'd0, chk0_concat[95:80]} + {16'd0, chk0_concat[79:64]} + {16'd0, chk0_concat[63:48]} + {16'd0, chk0_concat[47:32]} + {16'd0, chk0_concat[31:16]} + {16'd0, chk0_concat[15:0]};
  wire [16:0] chk0_fold1 = chk0_sum[15:0] + chk0_sum[31:16];
  wire [16:0] chk0_fold2 = {15'd0, chk0_fold1[16]} + {1'b0, chk0_fold1[15:0]};
  wire [15:0] chk0_value = ~chk0_fold2[15:0];

  // ---- Pipeline stage 0 ----
  always_comb begin
    drop = 0;

    // Header valid flag pass-through defaults
    out_ethernet_valid = ethernet_valid;
    out_ipv4_valid = ipv4_valid;

    // Header field pass-through defaults
    out_ethernet_dstAddr = ethernet_dstAddr;
    out_ethernet_srcAddr = ethernet_srcAddr;
    out_ethernet_etherType = ethernet_etherType;
    out_ipv4_version = ipv4_version;
    out_ipv4_ihl = ipv4_ihl;
    out_ipv4_diffserv = ipv4_diffserv;
    out_ipv4_ecn = ipv4_ecn;
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
    if (((ipv4_ecn == 'h01) || (ipv4_ecn == 'h02))) begin
      if ((std_meta_enq_qdepth >= 'h00000A)) begin
        out_ipv4_ecn = 'h03;
      end
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
