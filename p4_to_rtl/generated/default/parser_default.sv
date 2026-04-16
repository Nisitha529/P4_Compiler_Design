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

  logic       valid_reg;
  axis_word_t data_reg;

//   assign s_ready   = pkt_ready;
//   assign pkt_out   = s_axis;
//   assign pkt_valid = s_valid;
  assign pkt_out   = data_reg;
  assign s_ready   = !valid_reg || pkt_ready;
  assign pkt_valid = valid_reg;

  always @(posedge clk) begin
    if (!rst_n) begin
      valid_reg    <= 0;
	end else begin
	  if (s_valid && s_ready) begin
        valid_reg  <= 1;
		data_reg   <= s_axis;
	  end 
	  
	  if (pkt_valid && pkt_ready) begin
        valid_reg  <= 0;
      end
	end
  end

//   always @ (posedge clk) begin
//     if (!rst_n) begin
//       valid_out    <= 0;
//     end else begin
//       valid_out    <= valid_reg;
//     end
//   end

  assign valid_out = valid_reg;
    
endmodule