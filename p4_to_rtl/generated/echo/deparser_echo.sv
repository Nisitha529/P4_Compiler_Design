import p4_defs_pkg::*;
import p4_types_pkg::*;

module deparser_echo (
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

  logic       valid_reg;
  axis_word_t data_reg;

//   assign pkt_ready = m_ready;
//   assign m_axis    = pkt_in;
//   assign m_valid   = pkt_valid;
  assign m_axis    = data_reg;
  assign m_valid   = valid_reg;
  assign pkt_ready = !valid_reg || m_ready;

  always @ (posedge clk) begin
    if (!rst_n) begin
      valid_reg    <= 0;
	end else begin
      if (pkt_valid && pkt_ready) begin
        valid_reg  <= 1;
		data_reg   <= pkt_in;
	  end else if (m_valid && m_ready) begin
        valid_reg  <= 0;
	  end
	end
  end
    
endmodule