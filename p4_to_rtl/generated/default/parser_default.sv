import p4_defs_pkg::*;
import p4_types_pkg::*;

module parser_default (
  input  logic        clk,
  input  logic        rst_n,

  input  axis_word_t  s_axis,
  input  logic        s_valid,
  output logic        s_ready,

  output parser_bus_t bus_out,
  output logic        valid_out,

  output axis_word_t  pkt_out,
  output logic        pkt_valid,
  input  logic        pkt_ready
);

  assign s_ready   = pkt_ready;
  assign pkt_out   = s_axis;
  assign pkt_valid = s_valid;

  always @ (posedge clk) begin
    if (!rst_n) begin
      valid_out    <= 0;
    end else begin
      valid_out    <= s_valid;
    end
  end
    
endmodule