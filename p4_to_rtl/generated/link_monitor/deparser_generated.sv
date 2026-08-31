module deparser_generated (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        valid_in,

  // Header valid flags
  input  logic        ethernet_valid,
  input  logic        ipv4_valid,
  input  logic        probe_valid,
  input  logic        probe_data_0_valid,
  input  logic        probe_data_1_valid,
  input  logic        probe_data_2_valid,
  input  logic        probe_data_3_valid,
  input  logic        probe_data_4_valid,
  input  logic        probe_data_5_valid,
  input  logic        probe_data_6_valid,
  input  logic        probe_data_7_valid,
  input  logic        probe_data_8_valid,
  input  logic        probe_data_9_valid,
  input  logic        probe_fwd_0_valid,
  input  logic        probe_fwd_1_valid,
  input  logic        probe_fwd_2_valid,
  input  logic        probe_fwd_3_valid,
  input  logic        probe_fwd_4_valid,
  input  logic        probe_fwd_5_valid,
  input  logic        probe_fwd_6_valid,
  input  logic        probe_fwd_7_valid,
  input  logic        probe_fwd_8_valid,
  input  logic        probe_fwd_9_valid,

  // Header field inputs
  input  logic [47:0] ethernet_dstAddr,
  input  logic [47:0] ethernet_srcAddr,
  input  logic [15:0] ethernet_etherType,
  input  logic [3:0] ipv4_version,
  input  logic [3:0] ipv4_ihl,
  input  logic [7:0] ipv4_diffserv,
  input  logic [15:0] ipv4_totalLen,
  input  logic [15:0] ipv4_identification,
  input  logic [2:0] ipv4_flags,
  input  logic [12:0] ipv4_fragOffset,
  input  logic [7:0] ipv4_ttl,
  input  logic [7:0] ipv4_protocol,
  input  logic [15:0] ipv4_hdrChecksum,
  input  logic [31:0] ipv4_srcAddr,
  input  logic [31:0] ipv4_dstAddr,
  input  logic [7:0] probe_hop_cnt,
  input  logic [0:0] probe_data_0_bos,
  input  logic [6:0] probe_data_0_swid,
  input  logic [7:0] probe_data_0_port,
  input  logic [31:0] probe_data_0_byte_cnt,
  input  logic [47:0] probe_data_0_last_time,
  input  logic [47:0] probe_data_0_cur_time,
  input  logic [0:0] probe_data_1_bos,
  input  logic [6:0] probe_data_1_swid,
  input  logic [7:0] probe_data_1_port,
  input  logic [31:0] probe_data_1_byte_cnt,
  input  logic [47:0] probe_data_1_last_time,
  input  logic [47:0] probe_data_1_cur_time,
  input  logic [0:0] probe_data_2_bos,
  input  logic [6:0] probe_data_2_swid,
  input  logic [7:0] probe_data_2_port,
  input  logic [31:0] probe_data_2_byte_cnt,
  input  logic [47:0] probe_data_2_last_time,
  input  logic [47:0] probe_data_2_cur_time,
  input  logic [0:0] probe_data_3_bos,
  input  logic [6:0] probe_data_3_swid,
  input  logic [7:0] probe_data_3_port,
  input  logic [31:0] probe_data_3_byte_cnt,
  input  logic [47:0] probe_data_3_last_time,
  input  logic [47:0] probe_data_3_cur_time,
  input  logic [0:0] probe_data_4_bos,
  input  logic [6:0] probe_data_4_swid,
  input  logic [7:0] probe_data_4_port,
  input  logic [31:0] probe_data_4_byte_cnt,
  input  logic [47:0] probe_data_4_last_time,
  input  logic [47:0] probe_data_4_cur_time,
  input  logic [0:0] probe_data_5_bos,
  input  logic [6:0] probe_data_5_swid,
  input  logic [7:0] probe_data_5_port,
  input  logic [31:0] probe_data_5_byte_cnt,
  input  logic [47:0] probe_data_5_last_time,
  input  logic [47:0] probe_data_5_cur_time,
  input  logic [0:0] probe_data_6_bos,
  input  logic [6:0] probe_data_6_swid,
  input  logic [7:0] probe_data_6_port,
  input  logic [31:0] probe_data_6_byte_cnt,
  input  logic [47:0] probe_data_6_last_time,
  input  logic [47:0] probe_data_6_cur_time,
  input  logic [0:0] probe_data_7_bos,
  input  logic [6:0] probe_data_7_swid,
  input  logic [7:0] probe_data_7_port,
  input  logic [31:0] probe_data_7_byte_cnt,
  input  logic [47:0] probe_data_7_last_time,
  input  logic [47:0] probe_data_7_cur_time,
  input  logic [0:0] probe_data_8_bos,
  input  logic [6:0] probe_data_8_swid,
  input  logic [7:0] probe_data_8_port,
  input  logic [31:0] probe_data_8_byte_cnt,
  input  logic [47:0] probe_data_8_last_time,
  input  logic [47:0] probe_data_8_cur_time,
  input  logic [0:0] probe_data_9_bos,
  input  logic [6:0] probe_data_9_swid,
  input  logic [7:0] probe_data_9_port,
  input  logic [31:0] probe_data_9_byte_cnt,
  input  logic [47:0] probe_data_9_last_time,
  input  logic [47:0] probe_data_9_cur_time,
  input  logic [7:0] probe_fwd_0_egress_spec,
  input  logic [7:0] probe_fwd_1_egress_spec,
  input  logic [7:0] probe_fwd_2_egress_spec,
  input  logic [7:0] probe_fwd_3_egress_spec,
  input  logic [7:0] probe_fwd_4_egress_spec,
  input  logic [7:0] probe_fwd_5_egress_spec,
  input  logic [7:0] probe_fwd_6_egress_spec,
  input  logic [7:0] probe_fwd_7_egress_spec,
  input  logic [7:0] probe_fwd_8_egress_spec,
  input  logic [7:0] probe_fwd_9_egress_spec,

  // Packed output [1799:0]  layout (MSB first): ethernet(112b) | ipv4(160b) | probe(8b) | probe_data_0(144b) | probe_data_1(144b) | probe_data_2(144b) | probe_data_3(144b) | probe_data_4(144b) | probe_data_5(144b) | probe_data_6(144b) | probe_data_7(144b) | probe_data_8(144b) | probe_data_9(144b) | probe_fwd_0(8b) | probe_fwd_1(8b) | probe_fwd_2(8b) | probe_fwd_3(8b) | probe_fwd_4(8b) | probe_fwd_5(8b) | probe_fwd_6(8b) | probe_fwd_7(8b) | probe_fwd_8(8b) | probe_fwd_9(8b)
  output logic [1799:0] pkt_hdr_out,
  output logic [15:0]  pkt_hdr_len,
  output logic         valid_out
);

  always_comb begin
    pkt_hdr_out = '0;

    if (ethernet_valid) begin
      pkt_hdr_out[1799:1688] = {ethernet_dstAddr, ethernet_srcAddr, ethernet_etherType};
    end

    if (ipv4_valid) begin
      pkt_hdr_out[1687:1528] = {ipv4_version, ipv4_ihl, ipv4_diffserv, ipv4_totalLen, ipv4_identification, ipv4_flags, ipv4_fragOffset, ipv4_ttl, ipv4_protocol, ipv4_hdrChecksum, ipv4_srcAddr, ipv4_dstAddr};
    end

    if (probe_valid) begin
      pkt_hdr_out[1527:1520] = {probe_hop_cnt};
    end

    if (probe_data_0_valid) begin
      pkt_hdr_out[1519:1376] = {probe_data_0_bos, probe_data_0_swid, probe_data_0_port, probe_data_0_byte_cnt, probe_data_0_last_time, probe_data_0_cur_time};
    end

    if (probe_data_1_valid) begin
      pkt_hdr_out[1375:1232] = {probe_data_1_bos, probe_data_1_swid, probe_data_1_port, probe_data_1_byte_cnt, probe_data_1_last_time, probe_data_1_cur_time};
    end

    if (probe_data_2_valid) begin
      pkt_hdr_out[1231:1088] = {probe_data_2_bos, probe_data_2_swid, probe_data_2_port, probe_data_2_byte_cnt, probe_data_2_last_time, probe_data_2_cur_time};
    end

    if (probe_data_3_valid) begin
      pkt_hdr_out[1087:944] = {probe_data_3_bos, probe_data_3_swid, probe_data_3_port, probe_data_3_byte_cnt, probe_data_3_last_time, probe_data_3_cur_time};
    end

    if (probe_data_4_valid) begin
      pkt_hdr_out[943:800] = {probe_data_4_bos, probe_data_4_swid, probe_data_4_port, probe_data_4_byte_cnt, probe_data_4_last_time, probe_data_4_cur_time};
    end

    if (probe_data_5_valid) begin
      pkt_hdr_out[799:656] = {probe_data_5_bos, probe_data_5_swid, probe_data_5_port, probe_data_5_byte_cnt, probe_data_5_last_time, probe_data_5_cur_time};
    end

    if (probe_data_6_valid) begin
      pkt_hdr_out[655:512] = {probe_data_6_bos, probe_data_6_swid, probe_data_6_port, probe_data_6_byte_cnt, probe_data_6_last_time, probe_data_6_cur_time};
    end

    if (probe_data_7_valid) begin
      pkt_hdr_out[511:368] = {probe_data_7_bos, probe_data_7_swid, probe_data_7_port, probe_data_7_byte_cnt, probe_data_7_last_time, probe_data_7_cur_time};
    end

    if (probe_data_8_valid) begin
      pkt_hdr_out[367:224] = {probe_data_8_bos, probe_data_8_swid, probe_data_8_port, probe_data_8_byte_cnt, probe_data_8_last_time, probe_data_8_cur_time};
    end

    if (probe_data_9_valid) begin
      pkt_hdr_out[223:80] = {probe_data_9_bos, probe_data_9_swid, probe_data_9_port, probe_data_9_byte_cnt, probe_data_9_last_time, probe_data_9_cur_time};
    end

    if (probe_fwd_0_valid) begin
      pkt_hdr_out[79:72] = {probe_fwd_0_egress_spec};
    end

    if (probe_fwd_1_valid) begin
      pkt_hdr_out[71:64] = {probe_fwd_1_egress_spec};
    end

    if (probe_fwd_2_valid) begin
      pkt_hdr_out[63:56] = {probe_fwd_2_egress_spec};
    end

    if (probe_fwd_3_valid) begin
      pkt_hdr_out[55:48] = {probe_fwd_3_egress_spec};
    end

    if (probe_fwd_4_valid) begin
      pkt_hdr_out[47:40] = {probe_fwd_4_egress_spec};
    end

    if (probe_fwd_5_valid) begin
      pkt_hdr_out[39:32] = {probe_fwd_5_egress_spec};
    end

    if (probe_fwd_6_valid) begin
      pkt_hdr_out[31:24] = {probe_fwd_6_egress_spec};
    end

    if (probe_fwd_7_valid) begin
      pkt_hdr_out[23:16] = {probe_fwd_7_egress_spec};
    end

    if (probe_fwd_8_valid) begin
      pkt_hdr_out[15:8] = {probe_fwd_8_egress_spec};
    end

    if (probe_fwd_9_valid) begin
      pkt_hdr_out[7:0] = {probe_fwd_9_egress_spec};
    end

    pkt_hdr_len = (ethernet_valid ? 16'd112 : 16'd0) + (ipv4_valid ? 16'd160 : 16'd0) + (probe_valid ? 16'd8 : 16'd0) + (probe_data_0_valid ? 16'd144 : 16'd0) + (probe_data_1_valid ? 16'd144 : 16'd0) + (probe_data_2_valid ? 16'd144 : 16'd0) + (probe_data_3_valid ? 16'd144 : 16'd0) + (probe_data_4_valid ? 16'd144 : 16'd0) + (probe_data_5_valid ? 16'd144 : 16'd0) + (probe_data_6_valid ? 16'd144 : 16'd0) + (probe_data_7_valid ? 16'd144 : 16'd0) + (probe_data_8_valid ? 16'd144 : 16'd0) + (probe_data_9_valid ? 16'd144 : 16'd0) + (probe_fwd_0_valid ? 16'd8 : 16'd0) + (probe_fwd_1_valid ? 16'd8 : 16'd0) + (probe_fwd_2_valid ? 16'd8 : 16'd0) + (probe_fwd_3_valid ? 16'd8 : 16'd0) + (probe_fwd_4_valid ? 16'd8 : 16'd0) + (probe_fwd_5_valid ? 16'd8 : 16'd0) + (probe_fwd_6_valid ? 16'd8 : 16'd0) + (probe_fwd_7_valid ? 16'd8 : 16'd0) + (probe_fwd_8_valid ? 16'd8 : 16'd0) + (probe_fwd_9_valid ? 16'd8 : 16'd0);
  end

  always_ff @(posedge clk) begin
    if (!rst_n) valid_out <= 0;
    else        valid_out <= valid_in;
  end

endmodule
