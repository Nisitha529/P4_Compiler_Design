module parser_generated(
  input  logic clk,
  input  logic rst_n,
  input  logic valid_in,
  input logic dummy_select,
  output logic extract_eth,
  output logic done
);

  typedef enum logic [0:0] {
    START,
    ACCEPT
  } state_t;

  // fsm_encoding: board 'de2-115' (altera) has no reliable inline attribute for this -- set state-machine encoding via your toolchain's Assignment/Settings UI instead
  state_t state, next_state;

  always_comb begin
    extract_eth = 0;
    done = 0;
    next_state = state;

    case (state)

      START: begin
        extract_eth = 1;
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
