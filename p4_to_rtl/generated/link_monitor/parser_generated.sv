module parser_generated(
  input  logic clk,
  input  logic rst_n,
  input  logic valid_in,
  input  logic [15:0] 0,
  input  logic [15:0] ethernet_etherType,
  input  logic [15:0] meta__parser_metadata_remaining1,
  input  logic [7:0] probe_hop_cnt,
  output logic extract_ethernet,
  output logic extract_ipv4,
  output logic extract_probe,
  output logic extract_probe_data,
  output logic extract_probe_fwd,
  output logic done
);

  typedef enum logic [2:0] {
    START,
    PARSE_IPV4,
    PARSE_PROBE,
    PARSE_PROBE_DATA,
    PARSE_PROBE_FWD,
    ACCEPT
  } state_t;

  (* fsm_encoding = "one_hot" *)
  state_t state, next_state;

  always_comb begin
    extract_probe = 0;
    extract_probe_data = 0;
    extract_ethernet = 0;
    extract_probe_fwd = 0;
    extract_ipv4 = 0;
    done = 0;
    next_state = state;

    case (state)

      START: begin
        extract_ethernet = 1;
        case (ethernet_etherType)
          16'h0800: next_state = PARSE_IPV4;
          16'h0812: next_state = PARSE_PROBE;
          default: next_state = ACCEPT;
        endcase
      end

      PARSE_IPV4: begin
        extract_ipv4 = 1;
        next_state = ACCEPT;
      end

      PARSE_PROBE: begin
        extract_probe = 1;
        case (probe_hop_cnt)
          8'h00: next_state = PARSE_PROBE_FWD;
          default: next_state = PARSE_PROBE_DATA;
        endcase
      end

      PARSE_PROBE_DATA: begin
        extract_probe_data = 1;
        case (0)
          16'h0001: next_state = PARSE_PROBE_FWD;
          default: next_state = PARSE_PROBE_DATA;
        endcase
      end

      PARSE_PROBE_FWD: begin
        extract_probe_fwd = 1;
        case (meta__parser_metadata_remaining1)
          16'h0000: next_state = ACCEPT;
          default: next_state = PARSE_PROBE_FWD;
        endcase
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
