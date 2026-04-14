import p4_defs_pkg::*;
import p4_types_pkg::*;

module top_default (
	input  logic       clk,
	input  logic       rst_n,

  input  axis_word_t s_axis,
	input  logic       s_valid,
	output logic       s_ready,

  output axis_word_t m_axis,
	output logic       m_valid,
	input  logic       m_ready
);

  parser_bus_t bus_parser_to_proc;
	parser_bus_t bus_proc_to_deparser;

	logic        valid_p2p;
	logic        valid_p2d;

	axis_word_t  pkt_mid;
	logic        pkt_valid_mid;
	logic        pkt_ready_mid;

	parser_default u_parser (
    .clk       (clk),
		.rst_n     (rst_n),

		.s_axis    (s_axis),
		.s_valid   (s_valid),
		.s_ready   (s_ready),

    .bus_out   (bus_parser_to_proc),
    .valid_out (valid_p2p),

    .pkt_out   (pkt_mid),
		.pkt_valid (pkt_valid_mid),
    .pkt_ready (pkt_ready_mid)
	);

	processing_default u_proc (
		.clk       (clk),
		.rst_n     (rst_n),

    .bus_in    (bus_parser_to_proc),
		.valid_in  (valid_p2p),

		.bus_out   (bus_proc_to_deparser),
		.valid_out (valid_p2d)
	);

	deparser_default u_deparser (
    .clk       (clk),
		.rst_n     (rst_n),

		.bus_in    (bus_proc_to_deparser),
		.valid_in  (valid_p2d),

		.pkt_in    (pkt_mid),
		.pkt_valid (pkt_valid_mid),
		.pkt_ready (pkt_ready_mid),

		.m_axis    (m_axis),
		.m_valid   (m_valid),
		.m_ready   (m_ready)
	);
    
endmodule