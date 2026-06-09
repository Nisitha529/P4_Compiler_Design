package echo_pkg;

  // Typedefs
  typedef logic [31:0] IPv4Addr;
  typedef logic [47:0] MacAddr;
  typedef logic [15:0] UdpPort;

  // Constants
  localparam bit [15:0] IPV4_TYPE = 16'h0800;
  localparam bit [7:0] UDP_PROT = 8'h11;
  localparam bit [15:0] VLAN_TYPE = 16'h8100;

endpackage : echo_pkg
