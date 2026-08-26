module parser_generated(
  input  logic clk,
  input  logic rst_n,
  input  logic valid_in,
  input  logic [15:0] ethernet_etherType,
  input  logic [7:0] ipv4_protocol,
  input  logic [0:0] mpls_0_bos,
  input  logic [0:0] mpls_1_bos,
  input  logic [0:0] mpls_2_bos,
  output logic extract_ethernet,
  output logic extract_ipv4,
  output logic extract_mpls_0,
  output logic extract_mpls_1,
  output logic extract_mpls_2,
  output logic extract_tcp,
  output logic extract_udp,
  output logic done
);

  typedef enum logic [2:0] {
    START,
    PARSE_MPLS_0,
    PARSE_MPLS_1,
    PARSE_MPLS_2,
    PARSE_IPV4,
    PARSE_TCP,
    PARSE_UDP,
    ACCEPT
  } state_t;

  (* fsm_encoding = "one_hot" *)
  state_t state, next_state;

  always_comb begin
    extract_mpls_0 = 0;
    extract_mpls_1 = 0;
    extract_tcp = 0;
    extract_mpls_2 = 0;
    extract_udp = 0;
    extract_ipv4 = 0;
    extract_ethernet = 0;
    done = 0;
    next_state = state;

    case (state)

      START: begin
        extract_ethernet = 1;
        case (ethernet_etherType)
          16'h8847: next_state = PARSE_MPLS_0;
          16'h0800: next_state = PARSE_IPV4;
          default: next_state = ACCEPT;
        endcase
      end

      PARSE_MPLS_0: begin
        extract_mpls_0 = 1;
        case (mpls_0_bos)
          1'h1: next_state = PARSE_IPV4;
          default: next_state = PARSE_MPLS_1;
        endcase
      end

      PARSE_MPLS_1: begin
        extract_mpls_1 = 1;
        case (mpls_1_bos)
          1'h1: next_state = PARSE_IPV4;
          default: next_state = PARSE_MPLS_2;
        endcase
      end

      PARSE_MPLS_2: begin
        extract_mpls_2 = 1;
        case (mpls_2_bos)
          1'h1: next_state = PARSE_IPV4;
          default: next_state = ACCEPT;
        endcase
      end

      PARSE_IPV4: begin
        extract_ipv4 = 1;
        case (ipv4_protocol)
          8'h06: next_state = PARSE_TCP;
          8'h11: next_state = PARSE_UDP;
          default: next_state = ACCEPT;
        endcase
      end

      PARSE_TCP: begin
        extract_tcp = 1;
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
