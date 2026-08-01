module parser_generated(
  input  logic clk,
  input  logic rst_n,
  input  logic valid_in,
  input  logic [15:0] ethernet_etherType,
  input  logic [7:0] ipv4_protocol,
  output logic extract_ethernet,
  output logic extract_ipv4,
  output logic extract_tcp,
  output logic done
);

  typedef enum logic [1:0] {
    START,
    PARSE_IPV4,
    TCP,
    ACCEPT
  } state_t;

  (* fsm_encoding = "one_hot" *)
  state_t state, next_state;

  always_comb begin
    extract_ethernet = 0;
    extract_ipv4 = 0;
    extract_tcp = 0;
    done = 0;
    next_state = state;

    case (state)

      START: begin
        extract_ethernet = 1;
        case (ethernet_etherType)
          16'h0800: next_state = PARSE_IPV4;
          default: next_state = ACCEPT;
        endcase
      end

      PARSE_IPV4: begin
        extract_ipv4 = 1;
        case (ipv4_protocol)
          8'h06: next_state = TCP;
          default: next_state = ACCEPT;
        endcase
      end

      TCP: begin
        extract_tcp = 1;
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
