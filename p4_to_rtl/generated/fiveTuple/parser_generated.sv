module parser_generated(
  input  logic clk,
  input  logic rst_n,
  input  logic valid_in,
  input  logic [15:0] eth_type,
  input  logic [7:0] ipv4_protocol,
  input  logic [15:0] vlan_tpid,
  output logic extract_eth,
  output logic extract_ipv4,
  output logic extract_ipv4opt,
  output logic extract_tcp,
  output logic extract_tcpopt,
  output logic extract_udp,
  output logic extract_vlan,
  output logic done
);

  typedef enum logic [2:0] {
    START,
    PARSE_VLAN,
    PARSE_IPV4,
    PARSE_TCP,
    PARSE_UDP,
    ACCEPT
  } state_t;

  (* fsm_encoding = "one_hot" *)
  state_t state, next_state;

  always_comb begin
    extract_vlan = 0;
    extract_udp = 0;
    extract_tcpopt = 0;
    extract_ipv4 = 0;
    extract_tcp = 0;
    extract_eth = 0;
    extract_ipv4opt = 0;
    done = 0;
    next_state = state;

    case (state)

      START: begin
        extract_eth = 1;
        case (eth_type)
          16'h8100: next_state = PARSE_VLAN;
          16'h0800: next_state = PARSE_IPV4;
          default: next_state = ACCEPT;
        endcase
      end

      PARSE_VLAN: begin
        extract_vlan = 1;
        case (vlan_tpid)
          16'h0800: next_state = PARSE_IPV4;
          default: next_state = ACCEPT;
        endcase
      end

      PARSE_IPV4: begin
        extract_ipv4 = 1;
        extract_ipv4opt = 1;
        case (ipv4_protocol)
          8'h06: next_state = PARSE_TCP;
          8'h11: next_state = PARSE_UDP;
          default: next_state = ACCEPT;
        endcase
      end

      PARSE_TCP: begin
        extract_tcp = 1;
        extract_tcpopt = 1;
        next_state = ACCEPT;
      end

      PARSE_UDP: begin
        extract_udp = 1;
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
