// ============================================================================
// tb_fiveTuple_counters_e2e.sv -- end-to-end proof that a REAL packet, hitting
// a REAL CP-configured table entry with action=InsertVLAN, actually reaches
// PacketCounter.count()/ByteCounter.count() and produces a control-plane-
// queryable result over the real AXI4-Lite bus -- the one link the standalone
// tests (tb_PacketCounter_standalone.sv / tb_ByteCounter_standalone.sv) and
// tb_fiveTuple_top.sv's own regression don't cover between them: the former
// drive the counter modules directly (bypassing processing_generated and
// fiveTuple_top entirely), and the latter's own scope note explicitly never
// configures action=InsertVLAN at all (InsertVLAN grows the packet via
// hdr.new_vlan.setValid(), and this cut-through TX design always replays
// exactly rx_beat_cnt beats -- a separate, pre-existing, out-of-scope
// limitation unrelated to counters). This test reuses that same
// action=InsertVLAN configuration but -- unlike tb_fiveTuple_top.sv --
// deliberately does NOT assert anything about the transmitted packet's
// content, only that PacketCounter/ByteCounter end up holding the right
// values afterward.
//
// Compile (from this directory):
//   iverilog -g2012 -o sim tb_fiveTuple_counters_e2e.sv \
//     ../fiveTuple_pkg.sv ../parser_generated.sv ../processing_generated.sv \
//     ../deparser_generated.sv ../FiveTuple_table.sv \
//     ../PacketCounter_counter.sv ../ByteCounter_counter.sv ../fiveTuple_top.sv
//   vvp sim
// ============================================================================
`timescale 1ns/1ps

module tb_fiveTuple_counters_e2e;

  localparam CLK_T = 10;
  logic clk = 0;
  always #(CLK_T/2) clk = ~clk;
  logic rst_n;

  localparam int TB_BEAT_BYTES = 32;
  localparam int TB_AXI_DATA_W = TB_BEAT_BYTES * 8;

  logic [TB_AXI_DATA_W-1:0]   s_axis_tdata;
  logic [TB_BEAT_BYTES-1:0]   s_axis_tkeep;
  logic        s_axis_tvalid = 0;
  logic        s_axis_tready;
  logic        s_axis_tlast = 0;

  logic [TB_AXI_DATA_W-1:0]   m_axis_tdata;
  logic [TB_BEAT_BYTES-1:0]   m_axis_tkeep;
  logic        m_axis_tvalid;
  logic        m_axis_tready = 1'b1;
  logic        m_axis_tlast;

  logic [15:0] s_axil_awaddr = 0;
  logic        s_axil_awvalid = 0;
  logic        s_axil_awready;
  logic [31:0] s_axil_wdata = 0;
  logic [3:0]  s_axil_wstrb = 0;
  logic        s_axil_wvalid = 0;
  logic        s_axil_wready;
  logic [1:0]  s_axil_bresp;
  logic        s_axil_bvalid;
  logic        s_axil_bready = 1'b1;
  logic [15:0] s_axil_araddr = 0;
  logic        s_axil_arvalid = 0;
  logic        s_axil_arready;
  logic [31:0] s_axil_rdata;
  logic [1:0]  s_axil_rresp;
  logic        s_axil_rvalid;
  logic        s_axil_rready = 1'b1;

  fiveTuple_top dut (
    .clk(clk), .rst_n(rst_n),
    .s_axis_tdata(s_axis_tdata), .s_axis_tkeep(s_axis_tkeep),
    .s_axis_tvalid(s_axis_tvalid), .s_axis_tready(s_axis_tready), .s_axis_tlast(s_axis_tlast),
    .m_axis_tdata(m_axis_tdata), .m_axis_tkeep(m_axis_tkeep),
    .m_axis_tvalid(m_axis_tvalid), .m_axis_tready(m_axis_tready), .m_axis_tlast(m_axis_tlast),
    .s_axil_awaddr(s_axil_awaddr), .s_axil_awvalid(s_axil_awvalid), .s_axil_awready(s_axil_awready),
    .s_axil_wdata(s_axil_wdata), .s_axil_wstrb(s_axil_wstrb), .s_axil_wvalid(s_axil_wvalid), .s_axil_wready(s_axil_wready),
    .s_axil_bresp(s_axil_bresp), .s_axil_bvalid(s_axil_bvalid), .s_axil_bready(s_axil_bready),
    .s_axil_araddr(s_axil_araddr), .s_axil_arvalid(s_axil_arvalid), .s_axil_arready(s_axil_arready),
    .s_axil_rdata(s_axil_rdata), .s_axil_rresp(s_axil_rresp), .s_axil_rvalid(s_axil_rvalid), .s_axil_rready(s_axil_rready)
  );

  int pass_cnt = 0, fail_cnt = 0;
  task automatic chk(input string name, input logic cond);
    if (cond) begin $display("    [PASS] %s", name); pass_cnt++; end
    else      begin $display("    [FAIL] %s", name); fail_cnt++; end
  endtask

  task do_reset;
    rst_n = 0; s_axis_tvalid = 0; s_axis_tlast = 0;
    repeat(5) @(posedge clk); @(negedge clk);
    rst_n = 1; @(posedge clk); #1;
  endtask

  // Identical addressing/sampling convention to tb_fiveTuple_top.sv's own
  // axil_write/axil_read (see that file for the detailed race-avoidance
  // rationale in each task's comments) -- word-addressed, matches
  // _build_axil_regmap.
  task automatic axil_write(input int word_addr, input logic [31:0] data);
    bit aw_done, w_done;
    @(negedge clk);
    s_axil_awaddr  = word_addr * 4;
    s_axil_awvalid = 1'b1;
    s_axil_wdata   = data;
    s_axil_wstrb   = 4'hF;
    s_axil_wvalid  = 1'b1;
    aw_done = 1'b0;
    w_done  = 1'b0;
    while (!aw_done || !w_done) begin
      @(posedge clk);
      #1;
      if (!aw_done && s_axil_awready) aw_done = 1'b1;
      if (!w_done && s_axil_wready)   w_done  = 1'b1;
    end
    @(negedge clk);
    s_axil_awvalid = 1'b0;
    s_axil_wvalid  = 1'b0;
  endtask

  task automatic axil_read(input int word_addr, output logic [31:0] data);
    bit accepted;
    @(negedge clk);
    s_axil_araddr  = word_addr * 4;
    s_axil_arvalid = 1'b1;
    accepted = 1'b0;
    while (!accepted) begin
      @(posedge clk);
      if (s_axil_arready) accepted = 1'b1;
    end
    @(negedge clk);
    s_axil_arvalid = 1'b0;
    @(posedge clk);
    data = s_axil_rdata;
  endtask

  // FiveTuple's own regmap window (words 0-24) -- see tb_fiveTuple_top.sv
  // for the full field-by-field map. Only what's needed here: wr_idx(0),
  // key fields(2-6), action(1), InsertVLAN's params(7-10), commit(11).
  task automatic cp_write_insertvlan_entry(
      input [12:0] idx, input [31:0] src, input [31:0] dst,
      input [7:0] proto, input [15:0] sport, input [15:0] dport,
      input [12:0] counter_index, input [2:0] pcp, input cfi, input [11:0] vid);
    axil_write(0, idx);
    axil_write(1, 32'd1);   // action = InsertVLAN (1; NoAction=0)
    axil_write(2, src);
    axil_write(3, dst);
    axil_write(4, {24'd0, proto});
    axil_write(5, {16'd0, sport});
    axil_write(6, {16'd0, dport});
    axil_write(7, {19'd0, counter_index});
    axil_write(8, {29'd0, pcp});
    axil_write(9, {31'd0, cfi});
    axil_write(10, {20'd0, vid});
    axil_write(11, 32'd0);  // commit
  endtask

  // PacketCounter's regmap window: base word 64 (TABLE_AXIL_SZ=0x100=64
  // words/table, PacketCounter is the 2nd regmap entry after FiveTuple).
  // words: 64=query_idx 65=query_commit 66=query_status(bit0=busy)
  //        67=value_pkt_lo 68=value_pkt_hi
  task automatic query_packet_counter(input [12:0] idx, output [63:0] value);
    logic [31:0] status, lo, hi;
    axil_write(64, {19'd0, idx});
    axil_write(65, 32'd0);  // query_commit
    status = 32'hFFFF_FFFF;
    while (status[0]) axil_read(66, status);  // poll busy
    axil_read(67, lo);
    axil_read(68, hi);
    value = {hi, lo};
  endtask

  // ByteCounter's regmap window: base word 128 (3rd regmap entry).
  // words: 128=query_idx 129=query_commit 130=query_status
  //        131=value_byte_lo 132=value_byte_hi
  task automatic query_byte_counter(input [12:0] idx, output [63:0] value);
    logic [31:0] status, lo, hi;
    axil_write(128, {19'd0, idx});
    axil_write(129, 32'd0);  // query_commit
    status = 32'hFFFF_FFFF;
    while (status[0]) axil_read(130, status);  // poll busy
    axil_read(131, lo);
    axil_read(132, hi);
    value = {hi, lo};
  endtask

  int send_tlast_cycle;
  task automatic send_packet(input byte data[]);
    int nbytes, nbeats;
    nbytes = data.size();
    nbeats = (nbytes + TB_BEAT_BYTES - 1) / TB_BEAT_BYTES;
    for (int b = 0; b < nbeats; b++) begin
      logic [TB_AXI_DATA_W-1:0] beat_data;
      logic [TB_BEAT_BYTES-1:0] beat_keep;
      int base, valid_bytes;
      base = b * TB_BEAT_BYTES;
      valid_bytes = ((base + TB_BEAT_BYTES) <= nbytes) ? TB_BEAT_BYTES : (nbytes - base);
      beat_data = '0;
      beat_keep = '0;
      for (int i = 0; i < valid_bytes; i++) begin
        beat_data[i*8 +: 8] = data[base + i];
        beat_keep[i] = 1'b1;
      end
      @(negedge clk);
      s_axis_tdata  = beat_data;
      s_axis_tkeep  = beat_keep;
      s_axis_tvalid = 1'b1;
      s_axis_tlast  = (b == nbeats - 1);
      @(posedge clk);
      while (!s_axis_tready) @(posedge clk);
      #1;
    end
    @(negedge clk);
    s_axis_tvalid = 1'b0;
    s_axis_tlast  = 1'b0;
  endtask

  byte pb[$];
  task automatic append16(input [15:0] v);
    pb.push_back(v[15:8]); pb.push_back(v[7:0]);
  endtask
  task automatic append32(input [31:0] v);
    pb.push_back(v[31:24]); pb.push_back(v[23:16]); pb.push_back(v[15:8]); pb.push_back(v[7:0]);
  endtask
  task automatic append48(input [47:0] v);
    pb.push_back(v[47:40]); pb.push_back(v[39:32]); pb.push_back(v[31:24]);
    pb.push_back(v[23:16]); pb.push_back(v[15:8]);  pb.push_back(v[7:0]);
  endtask
  task automatic append_eth(input [15:0] ethertype);
    append48(48'hAABBCCDDEEFF);
    append48(48'h112233445566);
    append16(ethertype);
  endtask
  task automatic append_ipv4(input [3:0] ihl, input [7:0] proto,
                              input [31:0] src, input [31:0] dst);
    pb.push_back({4'd4, ihl});
    pb.push_back(8'h00);
    append16(16'd0);
    append16(16'h1234);
    append16(16'd0);
    pb.push_back(8'd64);
    pb.push_back(proto);
    append16(16'd0);
    append32(src);
    append32(dst);
  endtask
  task automatic append_udp(input [15:0] sport, input [15:0] dport);
    append16(sport);
    append16(dport);
    append16(16'd8);
    append16(16'd0);
  endtask

  initial begin
    $display("== tb_fiveTuple_counters_e2e: real packet -> InsertVLAN -> counters -> AXI4-Lite query ==\n");
    do_reset();

    // PacketCounter/ByteCounter use the app's real NUM_COUNTERS=8192, so
    // their power-on clear FSM (see emit_counters.py) takes 8192 cycles --
    // unlike the standalone testbenches, which override DEPTH small, this
    // one drives the actual fiveTuple_top instance, so the real wait is
    // unavoidable. Both increments and CP queries are silently ignored
    // while clearing is in progress (documented, accepted behavior), so
    // this genuinely has to be waited out, not just a nice-to-have margin.
    repeat(8192 + 10) @(posedge clk);
    #1;

    $display("== T1: one packet hitting action=InsertVLAN increments both counters ==");
    cp_write_insertvlan_entry(13'd0, 32'hC0A80005, 32'hC0A80006, 8'd17, 16'd5000, 16'd6000,
                               13'd77, 3'd5, 1'b1, 12'd42);
    begin
      byte pkt_arr[];
      logic [63:0] pkt_val, byte_val;
      pb.delete();
      append_eth(16'h0800);
      append_ipv4(4'd5, 8'd17, 32'hC0A80005, 32'hC0A80006);
      append_udp(16'd5000, 16'd6000);
      pkt_arr = pb;  // 14 + 20 + 8 = 42 bytes
      send_packet(pkt_arr);
      // Drain time: single-packet-in-flight pipeline needs rx_done ->
      // proc_settle -> proc_committed -> tx_active clears -> pkt_done ->
      // counter's own 2-cycle RMW. A generous fixed margin (this packet is
      // tiny -- 2 beats at TB_BEAT_BYTES=32) rather than a tight bound.
      repeat(60) @(posedge clk);
      #1;

      query_packet_counter(13'd77, pkt_val);
      chk("T1: PacketCounter[77] == 1 after one hit", pkt_val == 64'd1);

      query_byte_counter(13'd77, byte_val);
      chk("T1: ByteCounter[77] == 42 (this packet's real byte length)", byte_val == 64'd42);

      query_packet_counter(13'd0, pkt_val);
      chk("T1: PacketCounter[0] (a different index) stays 0", pkt_val == 64'd0);
    end

    $display("\n== T2: a second packet to the same index accumulates ==");
    begin
      byte pkt_arr[];
      logic [63:0] pkt_val, byte_val;
      pb.delete();
      append_eth(16'h0800);
      append_ipv4(4'd5, 8'd17, 32'hC0A80005, 32'hC0A80006);
      append_udp(16'd5000, 16'd6000);
      pkt_arr = pb;
      send_packet(pkt_arr);
      repeat(60) @(posedge clk);
      #1;

      query_packet_counter(13'd77, pkt_val);
      chk("T2: PacketCounter[77] == 2 after a second hit", pkt_val == 64'd2);

      query_byte_counter(13'd77, byte_val);
      chk("T2: ByteCounter[77] == 84 (42+42)", byte_val == 64'd84);
    end

    $display("\n================================================================");
    $display("  Results: %0d passed, %0d failed  (total %0d)", pass_cnt, fail_cnt, pass_cnt+fail_cnt);
    $display("================================================================");
    if (fail_cnt == 0) $display("  ALL TESTS PASSED");
    else                $display("  SOME TESTS FAILED");
    $finish;
  end

endmodule
