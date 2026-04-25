import p4_defs_pkg::*;
import p4_types_pkg::*;

module processing_echo (
  input  logic        clk,
  input  logic        rst_n,

  input  parser_bus_t bus_in,
  input  logic        valid_in,

  output parser_bus_t bus_out,
  output logic        valid_out
);

  assign bus_out   = bus_in;
  assign valid_out = valid_in;
    
endmodule