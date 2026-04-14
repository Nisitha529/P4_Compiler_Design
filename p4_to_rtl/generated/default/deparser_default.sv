import p4_defs_pkg::*;
import p4_types_pkg::*;

module deparser_default (
  input  logic        clk,
  input  logic        rst_n,

  input  parser_bus_t bus_in,
  input  logic        valid_in,

  input  axis_word_t  pkt_in,
  input  logic        pkt_valid,
  output logic        pkt_ready,

  output axis_word_t  m_axis,
  output logic        m_valid,
  input  logic        m_ready
);

  assign pkt_ready = m_ready;
  assign m_axis    = pkt_in;
  assign m_valid   = pkt_valid;
    
endmodule