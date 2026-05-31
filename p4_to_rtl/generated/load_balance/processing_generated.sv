module processing_generated (
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

  // Metadata
  input  logic [13:0] meta_ecmp_select,

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
  output logic [15:0] out_tcp_srcPort,
  output logic [15:0] out_tcp_dstPort,
  output logic [31:0] out_tcp_seqNo,
  output logic [31:0] out_tcp_ackNo,
  output logic [3:0] out_tcp_dataOffset,
  output logic [2:0] out_tcp_res,
  output logic [2:0] out_tcp_ecn,
  output logic [5:0] out_tcp_ctrl,
  output logic [15:0] out_tcp_window,
  output logic [15:0] out_tcp_checksum,
  output logic [15:0] out_tcp_urgentPtr,
  output logic        ecmp_group_hit_out,

  output logic        valid_out,
  output logic        drop
);

  logic [0:0] ecmp_group_hit;
  logic [31:0] standard_metadata_egress_spec;

  always_comb begin
    drop = 0;
    ecmp_group_hit = 1'b0;
    standard_metadata_egress_spec = 32'b0;

    // pass-through defaults
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
    out_tcp_srcPort = tcp_srcPort;
    out_tcp_dstPort = tcp_dstPort;
    out_tcp_seqNo = tcp_seqNo;
    out_tcp_ackNo = tcp_ackNo;
    out_tcp_dataOffset = tcp_dataOffset;
    out_tcp_res = tcp_res;
    out_tcp_ecn = tcp_ecn;
    out_tcp_ctrl = tcp_ctrl;
    out_tcp_window = tcp_window;
    out_tcp_checksum = tcp_checksum;
    out_tcp_urgentPtr = tcp_urgentPtr;

    // apply block
    if (ipv4_valid && ipv4_ttl > 0) begin
      // ecmp_group.apply()
      //   key: ipv4_dstAddr [lpm]
      //   default: None
      // TODO: drive ecmp_group_hit from lookup module
      if (ecmp_group_hit) begin
        // ecmp_nhop.apply()
        //   key: meta_ecmp_select [exact]
        //   default_action: None
      end
    end
  end

  assign ecmp_group_hit_out = ecmp_group_hit;

  always_ff @(posedge clk) begin
    if (!rst_n) valid_out <= 0;
    else        valid_out <= valid_in;
  end

endmodule
