module parser_generated(
  input  logic clk,
  input  logic rst_n
);

  typedef enum logic [0:0] {
    START,
    ACCEPT
  } state_t;

  state_t state;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      state <= START;
    end else begin
      case (state)
        START: begin
          state <= ACCEPT;
        end
        default: begin
          state <= START;
        end
      endcase
    end
  end

endmodule
