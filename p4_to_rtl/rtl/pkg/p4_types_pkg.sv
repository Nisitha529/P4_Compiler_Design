package p4_types_pkg;

  // Basic configuration
  localparam int DATA_W = 128;
  localparam int KEEP_W = DATA_W / 8;

  // Parser error encoding according xsa.p4
  typedef enum logic [7 : 0] {
    P4_ERR_NoError                  = 8'd0,
    P4_ERR_PacketTooShort           = 8'd1,
    P4_ERR_NoMatch                  = 8'd2,
    P4_ERR_StackOutOfBounds         = 8'd3,
    P4_ERR_HeaderTooShort           = 8'd4,
    P4_ERR_ParserTimeout            = 8'd5,
    P4_ERR_HeaderDepthLimitExceeded = 8'd6
  } p4_error_t;

  // Standard metadata according to xsa.p4
  typedef struct packed {
    logic               drop;
    logic      [63 : 0] ingress_timestamp;
    logic      [15 : 0] parsed_bytes;
    // p4_error_t          parser_error;
    logic      [7 : 0]  parser_error;
  } standard_metadata_t;

  // User metadata
  typedef struct packed {
    logic dummy;
  } metadata_t;

  typedef struct packed {
    logic [47 : 0] dst_mac;
    logic [47 : 0] src_mac;
    logic [15 : 0] eth_type;
  } ethernet_t;

  // Parsed headers
  typedef struct packed {
    ethernet_t ethernet;
  } headers_t;

  // Parser -> Processing sideband bundle
  typedef struct packed {
    headers_t           hdr;
    metadata_t          meta;
    standard_metadata_t smeta;
    logic               valid;
  } parser_bus_t;

  // AXI Stream packet word
  typedef struct packed {
    logic [DATA_W - 1 : 0] tdata;
    logic [KEEP_W - 1 : 0] tkeep;
    logic                  tlast;
  } axis_word_t;
    
endpackage