package p4_defs_pkg;

  // Global configuration
  localparam int   P4_DATA_W             = 128;
  localparam int   P4_KEEP_W             = P4_DATA_W / 8;

  // Generic booleans and flags
  localparam logic P4_FALSE              = 1'b0;
  localparam logic P4_TRUE               = 1'b1;

  localparam logic P4_DROP_KEEP_METADATA = 1'b0;
  localparam logic P4_DROP_PACKET        = 1'b1;

  // Parser state machine
  // Needed to be expanded in the future
  typedef enum logic [1 : 0] { 
    PARSER_STATE_START    = 2'd0,
    PARSER_STATE_ACCEPT   = 2'd1,
    PARSER_STATE_REJECT   = 2'd2
  } parser_state_t;

  // Processing state machine
  typedef enum logic [1 : 0] {
    PROC_STATE_IDLE       = 2'd0,
    PROC_STATE_APPLY      = 2'd1,
    PROC_STATE_DONE       = 2'd2
  } processing_state_t;

  // Deparser state machine
  typedef enum logic [1 : 0] {
    DEPARSER_STATE_IDLE   = 2'd0,
    DEPARSER_STATE_EMIT   = 2'd1,
    DEPARSER_STATE_FINISH = 2'd2
  } deparser_state_t;

  // Table and action identifiers
  typedef enum logic [7 : 0] {
    P4_TABLE_ID_NONE      = 8'd0,
    P4_TABLE_ID_DEFAULT_0 = 8'd1
  } p4_table_id_t;

  typedef enum logic [7 : 0] {
    P4_ACTION_ID_NOACTION = 8'd0,
    P4_ACTION_ID_DROP     = 8'd1,
    P4_ACTION_ID_FORWARD  = 8'd2,
    P4_ACTION_ID_USER_0   = 8'd3
  } p4_action_id_t;

  // Match results
  typedef struct packed {
    logic                   hit;
    // p4_action_id_t          action_id;
    logic          [7 : 0]  action_id;
    logic          [63 : 0] action_data;
  } table_result_t;

  // Parser and deparser control defaults
  localparam logic [15 : 0]            P4_PARSED_BYTES_RESET = 16'd0;

  localparam logic [P4_DATA_W - 1 : 0] P4_ZERO_DATA          = '0;
  localparam logic [P4_KEEP_W - 1 : 0] P4_ZERO_KEEP          = '0;

  // Generic packet keeping
  localparam int                       P4_ETH_HDR_BYTES      = 14;
  localparam int                       P4_IPV4_HDR_BYTES     = 20;
  localparam int                       P4_IPV6_HDR_BYTES     = 40;

  // AXI defaults
  localparam logic                     P4_AXIS_VALID_RESET   = 1'b0;
  localparam logic                     P4_AXIS_LAST_RESET    = 1'b0;
  localparam logic                     P4_AXIS_READY_DFLT    = 1'b1;

  // Null and default pipeline helper values
  // localparam p4_action_id_t            P4_DEFAULT_ACTION     = P4_ACTION_ID_NOACTION;
  // localparam p4_table_id_t             P4_DEFAULT_TABLE      = P4_TABLE_ID_NONE;
  localparam logic [7 : 0]             P4_DEFAULT_ACTION     = 8'd0;
  localparam logic [7 : 0]             P4_DEFAULT_TABLE      = 8'd0;

  // Helper functions
  function automatic logic [P4_KEEP_W - 1 : 0] keep_from_nbytes (input int nbytes);
    logic [P4_KEEP_W - 1 : 0] tmp;
    int                       i;

    begin
      tmp = '0;

      for (i =0; i < P4_KEEP_W; i ++ ) begin
        if ( i < nbytes) begin
            tmp [i] = 1'b1;
        end
      end

      return tmp;

    end

  endfunction
    
endpackage