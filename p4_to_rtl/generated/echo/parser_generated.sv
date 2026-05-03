module parser_generated(
  input  logic clk,
  input  logic rst_n,
  input  logic valid_in,
  input  logic [15:0] eth_type,
  input  logic [7:0] ipv4_protocol,
  input  logic [15:0] vlan_last_tpid,
  output logic done
);

  typedef enum logic [2:0] {
    START,
    PARSE_ETH,
    PARSE_VLAN,
    PARSE_IPV4,
    PARSE_UDP,
    ACCEPT
  } state_t;

  state_t state, next_state;

  always_comb begin
    done = 0;
    next_state = state;

    case (state)

      START: begin
        next_state = PARSE_ETH;
      end

      PARSE_ETH: begin
        case (eth_type)
          16'h8100: next_state = PARSE_VLAN;
          16'h0800: next_state = PARSE_IPV4;
          default: next_state = ACCEPT;
        endcase
      end

      PARSE_VLAN: begin
        case (vlan_last_tpid)
          16'h8100: next_state = PARSE_VLAN;
          16'h0800: next_state = PARSE_IPV4;
          default: next_state = ACCEPT;
        endcase
      end

      PARSE_IPV4: begin
        case (ipv4_protocol)
          8'h11: next_state = PARSE_UDP;
          default: next_state = ACCEPT;
        endcase
      end

      PARSE_UDP: begin
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
      state <= START;
    else if (valid_in)
      state <= next_state;
  end

endmodule
