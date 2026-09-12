module parser_generated(
  input  logic clk,
  input  logic rst_n,
  input  logic valid_in,
  input  logic [15:0] eth_etype,
  output logic extract_eth,
  output logic [3:0] parser_error,
  output logic done
);

  typedef enum logic [1:0] {
    START,
    ACCEPT,
    REJECT
  } state_t;

  (* fsm_encoding = "one_hot" *)
  state_t state, next_state;
  logic [3:0] err_next;

  always_comb begin
    extract_eth = 0;
    done = 0;
    next_state = state;
    err_next = parser_error;

    case (state)

      START: begin
        extract_eth = 1;
        next_state = ACCEPT;
        // verify(hdr.eth.etype != 16'hFFFF, 4'd8)
        if (!(eth_etype != 16'hFFFF)) begin
          next_state = REJECT;
          err_next   = 4'd8;
        end
      end

      ACCEPT: begin
        done = 1;
        next_state = START;
      end

      REJECT: begin
        done = 1;
        err_next = 4'd0;
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

  // standard_metadata.parser_error. Advances with the FSM so it is
  // valid in the same cycle `done` asserts for its packet.
  always_ff @(posedge clk) begin
    if (!rst_n)
      parser_error <= 4'd0;
    else if (valid_in)
      parser_error <= err_next;
  end

endmodule
