module parser_generated(
  input  logic clk,
  input  logic rst_n,
  input  logic valid_in,
  input  logic [15:0] eth_etype,
  output logic extract_eth,
  output logic extract_vlan,
  output logic done
);

  typedef enum logic [1:0] {
    START,
    PARSE_VLAN,
    ACCEPT
  } state_t;

  (* fsm_encoding = "one_hot" *)
  state_t state, next_state;

  always_comb begin
    extract_eth = 0;
    extract_vlan = 0;
    done = 0;
    next_state = state;

    case (state)

      START: begin
        extract_eth = 1;
        case (eth_etype)
          16'h0003: next_state = PARSE_VLAN;
          default: next_state = ACCEPT;
        endcase
      end

      PARSE_VLAN: begin
        extract_vlan = 1;
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
