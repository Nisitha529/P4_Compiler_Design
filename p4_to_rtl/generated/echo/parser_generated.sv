module parser_generated(
  input  logic clk,
  input  logic rst_n,
  input  logic valid_in,
  input  logic [15:0] eth_type,
  input  logic [7:0] ipv4_protocol,
  input  logic [15:0] vlan_0_tpid,
  input  logic [15:0] vlan_1_tpid,
  output logic extract_eth,
  output logic extract_ipv4,
  output logic extract_ipv4opt,
  output logic extract_udp,
  output logic extract_vlan_0,
  output logic extract_vlan_1,
  output logic done
);

  typedef enum logic [2:0] {
    START,
    PARSE_VLAN_0,
    PARSE_VLAN_1,
    PARSE_IPV4,
    PARSE_UDP,
    ACCEPT
  } state_t;

  (* fsm_encoding = "one_hot" *)
  state_t state, next_state;

  always_comb begin
    extract_vlan_0 = 0;
    extract_vlan_1 = 0;
    extract_udp = 0;
    extract_ipv4 = 0;
    extract_eth = 0;
    extract_ipv4opt = 0;
    done = 0;
    next_state = state;

    case (state)

      START: begin
        extract_eth = 1;
        case (eth_type)
          16'h8100: next_state = PARSE_VLAN_0;
          16'h0800: next_state = PARSE_IPV4;
          default: next_state = ACCEPT;
        endcase
      end

      PARSE_VLAN_0: begin
        extract_vlan_0 = 1;
        case (vlan_0_tpid)
          16'h8100: next_state = PARSE_VLAN_1;
          16'h0800: next_state = PARSE_IPV4;
          default: next_state = ACCEPT;
        endcase
      end

      PARSE_VLAN_1: begin
        extract_vlan_1 = 1;
        case (vlan_1_tpid)
          16'h0800: next_state = PARSE_IPV4;
          default: next_state = ACCEPT;
        endcase
      end

      PARSE_IPV4: begin
        extract_ipv4 = 1;
        extract_ipv4opt = 1;
        case (ipv4_protocol)
          8'h11: next_state = PARSE_UDP;
          default: next_state = ACCEPT;
        endcase
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
