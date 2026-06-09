package qos_pkg;

  // Typedefs
  typedef logic [8:0] egressSpec_t;
  typedef logic [31:0] ip4Addr_t;
  typedef logic [47:0] macAddr_t;

  // Constants
  localparam bit [7:0] IP_PROTOCOLS_EIGRP = 8'd88;
  localparam bit [7:0] IP_PROTOCOLS_GRE = 8'd47;
  localparam bit [7:0] IP_PROTOCOLS_ICMP = 8'd1;
  localparam bit [7:0] IP_PROTOCOLS_ICMPV6 = 8'd58;
  localparam bit [7:0] IP_PROTOCOLS_IGMP = 8'd2;
  localparam bit [7:0] IP_PROTOCOLS_IPSEC_AH = 8'd51;
  localparam bit [7:0] IP_PROTOCOLS_IPSEC_ESP = 8'd50;
  localparam bit [7:0] IP_PROTOCOLS_IPV4 = 8'd4;
  localparam bit [7:0] IP_PROTOCOLS_IPV6 = 8'd41;
  localparam bit [7:0] IP_PROTOCOLS_OSPF = 8'd89;
  localparam bit [7:0] IP_PROTOCOLS_PIM = 8'd103;
  localparam bit [7:0] IP_PROTOCOLS_TCP = 8'd6;
  localparam bit [7:0] IP_PROTOCOLS_UDP = 8'd17;
  localparam bit [7:0] IP_PROTOCOLS_VRRP = 8'd112;
  localparam bit [15:0] TYPE_IPV4 = 16'h0800;

endpackage : qos_pkg
