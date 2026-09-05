module parser_generated(
  input  logic clk,
  input  logic rst_n,
  input  logic valid_in,
  input logic dummy_select,
  output logic done
);

  typedef enum logic [0:0] {
    START,
    ACCEPT
  } state_t;

  (* fsm_encoding = "one_hot" *)
  state_t state, next_state;

  always_comb begin
    done = 0;
    next_state = state;

    case (state)

      START: begin
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
