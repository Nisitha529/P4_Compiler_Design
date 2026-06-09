package firewall_pkg;

  // Typedefs
  typedef logic [8:0] egressSpec_t;
  typedef logic [31:0] ip4Addr_t;
  typedef logic [47:0] macAddr_t;

  // Constants
  localparam bit [15:0] TYPE_IPV4 = 16'h0800;
  localparam bit [7:0] TYPE_TCP = 8'd6;

endpackage : firewall_pkg
