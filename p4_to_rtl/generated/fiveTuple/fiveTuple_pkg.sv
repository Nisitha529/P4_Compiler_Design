package fiveTuple_pkg;

  // Typedefs
  typedef logic [12:0] CounterIndex_t;
  typedef logic [31:0] IPv4Addr;
  typedef logic [47:0] MacAddr;

  // Constants
  localparam bit [15:0] IPV4_TYPE = 16'h0800;
  localparam bit [31:0] NUM_COUNTERS = 32'd8192;
  localparam bit [15:0] QINQ_TYPE = 16'h88A8;
  localparam bit [7:0] TCP_PROT = 8'h06;
  localparam bit [7:0] UDP_PROT = 8'h11;
  localparam bit [15:0] VLAN_TYPE = 16'h8100;

endpackage : fiveTuple_pkg
