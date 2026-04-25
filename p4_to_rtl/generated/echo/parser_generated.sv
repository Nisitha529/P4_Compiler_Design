module parser_generated(
  input  logic                 clk,
  input  logic                 rst_n,
  input  logic                 valid_in,
  input  logic [127       : 0] data_in,
  output logic [0 : 0] state_out
);

  typedef enum logic [0:0] {
    START,
    ACCEPT
  } state_t;

  state_t state;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      state <= START;
    end else if (valid_in) begin
      case (state)
        START: begin
          state <= ACCEPT;
        end
 
        ACCEPT : begin
          state <= ACCEPT;
        end

        default: begin
          state <= START;
        end
      endcase
    end
  end

  assign state_out = state;

endmodule
