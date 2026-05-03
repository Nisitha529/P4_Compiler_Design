// ============================================================
// parser_default.sv
// DATAPATH for P4 parser (FINAL CORRECTED VERSION)
// ============================================================

import p4_defs_pkg::*;
import p4_types_pkg::*;

module parser_default (
  input  logic        clk,
  input  logic        rst_n,

  // AXI input
  input  axis_word_t  s_axis,
  input  logic        s_valid,
  output logic        s_ready,

  // Parser → Processing
  output parser_bus_t bus_out,
  output logic        valid_out,

  // Packet passthrough
  output axis_word_t  pkt_out,
  output logic        pkt_valid,
  input  logic        pkt_ready
);

  // ============================================================
  // Internal registers
  // ============================================================
  logic               valid_reg;
  axis_word_t         data_reg;

  headers_t           hdr_reg;
  metadata_t          meta_reg;
  standard_metadata_t smeta_reg;

  // ============================================================
  // CONTROL SIGNALS (MATCH parser_generated)
  // ============================================================
  logic extract_eth;
  logic extract_ipv4;
  logic extract_udp;
  logic done;

  // ============================================================
  // FEEDBACK SIGNALS (ZERO LATENCY)
  // ============================================================
  logic [15:0] eth_type_wire;
  logic [7:0]  ipv4_protocol_wire;

  assign eth_type_wire      = data_reg.tdata[31:16];
  assign ipv4_protocol_wire = data_reg.tdata[23:16]; // future-safe

  // ============================================================
  // CONTROL FSM (GENERATED)
  // ============================================================
  parser_generated u_parser_ctrl (
    .clk(clk),
    .rst_n(rst_n),
    .valid_in(valid_reg),

    .eth_type(eth_type_wire),
    .ipv4_protocol(ipv4_protocol_wire),

    .extract_eth(extract_eth),
    .extract_ipv4(extract_ipv4),
    .extract_udp(extract_udp),

    .done(done)
  );

  // ============================================================
  // AXI HANDSHAKE
  // ============================================================
  assign s_ready   = !valid_reg || pkt_ready;
  assign pkt_valid = valid_reg;
  assign pkt_out   = data_reg;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      valid_reg <= 1'b0;
    end else begin

      if (s_valid && s_ready) begin
        valid_reg <= 1'b1;
        data_reg  <= s_axis;
      end

      if (pkt_valid && pkt_ready) begin
        valid_reg <= 1'b0;
      end
    end
  end

  // ============================================================
  // PARSER DATAPATH
  // ============================================================
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      hdr_reg   <= '0;
      meta_reg  <= '0;
      smeta_reg <= '0;

    end else if (valid_reg) begin

      // --------------------------------------------------------
      // Ethernet extraction
      // --------------------------------------------------------
      if (extract_eth) begin
        hdr_reg.ethernet.dst_mac  <= data_reg.tdata[127:80];
        hdr_reg.ethernet.src_mac  <= data_reg.tdata[79:32];
        hdr_reg.ethernet.eth_type <= data_reg.tdata[31:16];

        smeta_reg.parsed_bytes <= 16'd14;
      end

      // --------------------------------------------------------
      // IPv4 extraction (placeholder)
      // --------------------------------------------------------
      if (extract_ipv4) begin
        // TODO: correct offset using cursor later
        // hdr_reg.ipv4 <= ...
      end

      // --------------------------------------------------------
      // UDP extraction (placeholder)
      // --------------------------------------------------------
      if (extract_udp) begin
        // TODO
      end
    end
  end

  // ============================================================
  // OUTPUT BUS
  // ============================================================
  assign bus_out.hdr   = hdr_reg;
  assign bus_out.meta  = meta_reg;
  assign bus_out.smeta = smeta_reg;
  assign bus_out.valid = valid_reg;

  assign valid_out = valid_reg; // or (valid_reg & done)

endmodule