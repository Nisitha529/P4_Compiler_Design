module parser_generated(
  input  logic clk,
  input  logic rst_n,
  input  logic valid_in,
  input  logic [15:0] ethernet_etherType,
  input  logic [15:0] standard_metadata_ingress_port,
  output logic extract_ethernet,
  output logic extract_ipv4,
  output logic extract_packet_out,
  output logic done
);

  typedef enum logic [2:0] {
    START,
    PARSE_CONTROLLER_PACKET_OUT_HEADER,
    PARSE_ETHERNET,
    PARSE_IPV4,
    ACCEPT
  } state_t;

  (* fsm_encoding = "one_hot" *)
  state_t state, next_state;

  always_comb begin
    extract_ethernet = 0;
    extract_packet_out = 0;
    extract_ipv4 = 0;
    done = 0;
    next_state = state;

    case (state)

      START: begin
        case (standard_metadata_ingress_port)
          16'h01FE: next_state = PARSE_CONTROLLER_PACKET_OUT_HEADER;
          default: next_state = PARSE_ETHERNET;
        endcase
      end

      PARSE_CONTROLLER_PACKET_OUT_HEADER: begin
        extract_packet_out = 1;
        next_state = ACCEPT;
      end

      PARSE_ETHERNET: begin
        extract_ethernet = 1;
        case (ethernet_etherType)
          16'h0800: next_state = PARSE_IPV4;
          default: next_state = ACCEPT;
        endcase
      end

      PARSE_IPV4: begin
        extract_ipv4 = 1;
        next_state = ACCEPT;
      end

      ACCEPT: begin
        done = 1;
        next_state = START;
      end

    endcase
  end

  always_ff @(posedge clk) begin
    if (!rst_n)
      state <= ACCEPT;
    else if (valid_in)
      state <= next_state;
  end

endmodule
