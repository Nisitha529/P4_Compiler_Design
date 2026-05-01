// ============================================================
// parser_default.sv
// DATAPATH for P4 parser
// ============================================================

import p4_defs_pkg::*;
import p4_types_pkg::*;

module parser_default (
  input  logic        clk,
  input  logic        rst_n,

  // ============================================================
  // AXI Stream input
  // ============================================================
  input  axis_word_t  s_axis,
  input  logic        s_valid,
  output logic        s_ready,

  // ============================================================
  // Parser → Processing interface
  // ============================================================
  output parser_bus_t bus_out,
  output logic        valid_out,

  // ============================================================
  // Packet passthrough
  // ============================================================
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
  // CONTROL SIGNALS from parser_generated
  // ============================================================
  logic extract_ethernet;   // CHANGED: control-driven extraction
  logic done;               // CHANGED: parsing completion

  // ============================================================
  // Extracted fields (fed back to control)
  // ============================================================
  logic [15:0] eth_type_wire;

  // ============================================================
  // CONTROL MODULE (generated from P4)
  // ============================================================
  parser_generated u_parser_ctrl (
    .clk              (clk),
    .rst_n            (rst_n),

    .valid_in         (valid_reg),

    // CHANGED: feedback signal for select()
    .eth_type         (eth_type_wire),

    // CHANGED: control signals
    .extract_ethernet (extract_ethernet),
    .done             (done)
  );

  // ============================================================
  // AXI HANDSHAKE LOGIC (STABLE)
  // ============================================================
  assign s_ready   = !valid_reg || pkt_ready;
  assign pkt_valid = valid_reg;
  assign pkt_out   = data_reg;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      valid_reg <= 1'b0;
    end else begin

      // Capture incoming packet
      if (s_valid && s_ready) begin
        valid_reg <= 1'b1;
        data_reg  <= s_axis;
      end

      // Release after downstream accepts
      if (pkt_valid && pkt_ready) begin
        valid_reg <= 1'b0;
      end
    end
  end

  // ============================================================
  // PARSER DATAPATH (CONTROL-DRIVEN)
  // ============================================================
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      hdr_reg   <= '0;
      meta_reg  <= '0;
      smeta_reg <= '0;

    end else if (valid_reg) begin

      // --------------------------------------------------------
      // CHANGED: extraction controlled by FSM signals
      // --------------------------------------------------------
      if (extract_ethernet) begin

        // Ethernet header extraction
        hdr_reg.ethernet.dst_mac  <= data_reg.tdata[127:80];
        hdr_reg.ethernet.src_mac  <= data_reg.tdata[79:32];
        hdr_reg.ethernet.eth_type <= data_reg.tdata[31:16];

        // Update metadata
        smeta_reg.parsed_bytes    <= 16'd14;
        smeta_reg.parser_error    <= 8'd0;

      end

      // --------------------------------------------------------
      // FUTURE EXTENSIONS (NOT YET IMPLEMENTED)
      // --------------------------------------------------------
      // if (extract_ipv4) begin ...
      // if (extract_tcp)  begin ...
      // if (extract_udp)  begin ...

    end
  end

  // ============================================================
  // FEEDBACK TO CONTROL (FOR SELECT)
  // ============================================================
  assign eth_type_wire = hdr_reg.ethernet.eth_type;

  // ============================================================
  // OUTPUT BUS
  // ============================================================
  assign bus_out.hdr   = hdr_reg;
  assign bus_out.meta  = meta_reg;
  assign bus_out.smeta = smeta_reg;
  assign bus_out.valid = valid_reg;   // CHANGED: explicit valid in bus

  assign valid_out = valid_reg;

endmodule