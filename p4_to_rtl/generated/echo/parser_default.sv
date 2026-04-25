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

  logic                       valid_reg;
  axis_word_t                 data_reg;

  logic               [0 : 0] parser_state;

  headers_t                   hdr_reg;
  metadata_t                  meta_reg;
  standard_metadata_t         smeta_reg;

  parser_generated parser_generated_01 (
    .clk       (clk),
    .rst_n     (rst_n),

    .valid_in  (valid_reg),
    .data_in   (data_reg.tdata),

    .state_out (parser_state)
  );

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

  always @ (posedge clk) begin
    if (!rst_n) begin
      hdr_reg   <= '0;
      meta_reg  <= '0;
      smeta_reg <= '0;
    end else if (valid_reg) begin
      case (parser_state)
        1'b0 : begin
          // Ethernet Extraction
          hdr_reg.ethernet.dst_mac  <= data_reg.tdata[127 : 80];
          hdr_reg.ethernet.src_mac  <= data_reg.tdata[79 : 32];
          hdr_reg.ethernet.eth_type <= data_reg.tdata[31 : 16];

          smeta_reg.parsed_bytes    <= 14;
        end

        1'b1 : begin
            
        end

      endcase
    end
  end

  assign bus_out.hdr   = hdr_reg;
  assign bus_out.meta  = meta_reg;
  assign bus_out.smeta = smeta_reg;

  assign valid_out = valid_reg;
    
endmodule