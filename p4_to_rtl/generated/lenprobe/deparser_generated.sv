module deparser_generated (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        valid_in,

  // Header valid flags
  input  logic        eth_valid,
  input  logic        tag_valid,
  input  logic        tag2_valid,
  input  logic        vlan_valid,

  // Header field inputs
  input  logic [47:0] eth_dst,
  input  logic [47:0] eth_src,
  input  logic [15:0] eth_etype,
  input  logic [15:0] tag_magic,
  input  logic [15:0] tag_seq,
  input  logic [15:0] tag2_magic2,
  input  logic [15:0] tag2_seq2,
  input  logic [15:0] vlan_tci,
  input  logic [15:0] vlan_inner_etype,

  // Packed output [207:0]  layout (MSB first): eth(112b) | tag(32b) | tag2(32b) | vlan(32b)
  output logic [207:0] pkt_hdr_out,
  output logic [15:0]  pkt_hdr_len,
  output logic         valid_out
);

  always_comb begin
    pkt_hdr_out = '0;

    if (eth_valid) begin
      pkt_hdr_out[207:96] = {eth_dst, eth_src, eth_etype};
    end

    if (tag_valid) begin
      pkt_hdr_out[95:64] = {tag_magic, tag_seq};
    end

    if (tag2_valid) begin
      pkt_hdr_out[63:32] = {tag2_magic2, tag2_seq2};
    end

    if (vlan_valid) begin
      pkt_hdr_out[31:0] = {vlan_tci, vlan_inner_etype};
    end

    pkt_hdr_len = (eth_valid ? 16'd112 : 16'd0) + (tag_valid ? 16'd32 : 16'd0) + (tag2_valid ? 16'd32 : 16'd0) + (vlan_valid ? 16'd32 : 16'd0);
  end

  always_ff @(posedge clk) begin
    if (!rst_n) valid_out <= 0;
    else        valid_out <= valid_in;
  end

endmodule
