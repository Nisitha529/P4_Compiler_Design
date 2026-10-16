// ============================================================================
// tb_feprobe_top.sv -- FeatureExport<T>: the AXI4-Stream record feed for an
// on-chip consumer (the TCN accelerator). See p4src/apps/feprobe.p4.
//
//   F1  N packets in => N records out when the consumer is always ready
//   F2  every record FIELD is at its declared bit position (each field is fed
//       a distinguishable value, so a swap or a shift is unmistakable)
//   F3  THE IMPORTANT ONE: tready held low forever must NOT stall the packet
//       path. Every packet still comes out, records are dropped newest-first
//       and counted, and tvalid obeys the stream protocol once raised.
//   F4  tready toggling: no duplicated records (the idle-cycle re-push bug)
//       and no all-zero records (the late-sampling bug)
//   F5  a packet the ingress DROPS still produces a record -- and gated_feed,
//       which pushes only `if (smeta.drop == 0)`, produces NONE for it, while
//       still producing one for a forwarded packet (checked in F1)
//   F6  the host's enable switch stops the feed
//
// Record layout (from processing_generated.sv, high bits first):
//   [63:48] eth.etype   [47:32] packet_length   [31:16] eth.dst[15:0]
//   [15:8]  0xA5        [7:0]   parsed_bytes[7:0]
// gated_feed record: [15:0] eth.dst[15:0]
//
// Register map: fwd 0 idx / 1 action / 2 key_etype / 3 p_port / 4 commit
//               tcn_feed 64 enable / 65 clear_stats / 66 pushed / 67 dropped
//                        68 status {hiwater, occupancy}
//               gated_feed 128..132, same layout
// ============================================================================
`timescale 1ns/1ps

module tb_feprobe_top;

  localparam CLK_T = 10;
  logic clk = 0;
  always #(CLK_T/2) clk = ~clk;
  logic rst_n;

  parameter  int TB_BEAT_BYTES = 32;
  localparam int TB_AXI_DATA_W = TB_BEAT_BYTES * 8;
  // Beats a frame of `nbytes` occupies at THIS beat width. Beat counts used to
  // be written as literals (a 64 B frame was "2 beats"), which silently encoded
  // --axi-data-width 256 into every such assertion; at 512 they all failed and
  // said nothing about the design. See scripts/check_axi_width.sh.
  function automatic int nbeats_of(input int nbytes);
    return (nbytes + TB_BEAT_BYTES - 1) / TB_BEAT_BYTES;
  endfunction

  localparam int FE_DEPTH      = 8;        // --fe-stage-depth default

  logic [TB_AXI_DATA_W-1:0] s_axis_tdata;
  logic [TB_BEAT_BYTES-1:0] s_axis_tkeep;
  logic s_axis_tvalid = 0, s_axis_tready, s_axis_tlast = 0;
  logic [TB_AXI_DATA_W-1:0] m_axis_tdata;
  logic [TB_BEAT_BYTES-1:0] m_axis_tkeep;
  logic m_axis_tvalid, m_axis_tready = 1'b1, m_axis_tlast;

  logic [15:0] s_axil_awaddr = 0; logic s_axil_awvalid = 0, s_axil_awready;
  logic [31:0] s_axil_wdata = 0;  logic [3:0] s_axil_wstrb = 0;
  logic s_axil_wvalid = 0, s_axil_wready; logic [1:0] s_axil_bresp;
  logic s_axil_bvalid, s_axil_bready = 1'b1;
  logic [15:0] s_axil_araddr = 0; logic s_axil_arvalid = 0, s_axil_arready;
  logic [31:0] s_axil_rdata;  logic [1:0] s_axil_rresp;
  logic s_axil_rvalid, s_axil_rready = 1'b1;

  logic [63:0] tcn_feed_tdata;
  logic        tcn_feed_tvalid;
  logic        tcn_feed_tready = 1'b1;

  logic [15:0] gated_feed_tdata;
  logic        gated_feed_tvalid;
  logic        gated_feed_tready = 1'b1;   // always ready: only WHETHER it pushes matters

  logic [15:0] out_meta_flow_id, out_meta_seen;
  logic  [7:0] out_meta_dir;
  logic  [8:0] out_std_meta_egress_port;

  feprobe_top dut (
    .clk(clk), .rst_n(rst_n),
    .s_axis_tdata(s_axis_tdata), .s_axis_tkeep(s_axis_tkeep),
    .s_axis_tvalid(s_axis_tvalid), .s_axis_tready(s_axis_tready), .s_axis_tlast(s_axis_tlast),
    .m_axis_tdata(m_axis_tdata), .m_axis_tkeep(m_axis_tkeep),
    .m_axis_tvalid(m_axis_tvalid), .m_axis_tready(m_axis_tready), .m_axis_tlast(m_axis_tlast),
    .s_axil_awaddr(s_axil_awaddr), .s_axil_awvalid(s_axil_awvalid), .s_axil_awready(s_axil_awready),
    .s_axil_wdata(s_axil_wdata), .s_axil_wstrb(s_axil_wstrb),
    .s_axil_wvalid(s_axil_wvalid), .s_axil_wready(s_axil_wready),
    .s_axil_bresp(s_axil_bresp), .s_axil_bvalid(s_axil_bvalid), .s_axil_bready(s_axil_bready),
    .s_axil_araddr(s_axil_araddr), .s_axil_arvalid(s_axil_arvalid), .s_axil_arready(s_axil_arready),
    .s_axil_rdata(s_axil_rdata), .s_axil_rresp(s_axil_rresp),
    .s_axil_rvalid(s_axil_rvalid), .s_axil_rready(s_axil_rready),
    .tcn_feed_tdata(tcn_feed_tdata), .tcn_feed_tvalid(tcn_feed_tvalid),
    .tcn_feed_tready(tcn_feed_tready),
    .gated_feed_tdata(gated_feed_tdata), .gated_feed_tvalid(gated_feed_tvalid),
    .gated_feed_tready(gated_feed_tready),
    .out_meta_flow_id(out_meta_flow_id), .out_meta_seen(out_meta_seen),
    .out_meta_dir(out_meta_dir),
    .out_std_meta_egress_port(out_std_meta_egress_port)
  );

  int pass_cnt = 0, fail_cnt = 0;
  task automatic chk(input string name, input logic cond);
    if (cond) begin $display("    [PASS] %s", name); pass_cnt++; end
    else      begin $display("    [FAIL] %s", name); fail_cnt++; end
  endtask

  // ── Record collector + stream-protocol monitor ───────────────────────────
  logic [63:0] recs [$];
  int          n_zero_recs = 0;
  logic        proto_violation = 0;
  logic        tv_d = 0, trdy_d = 0;
  logic [63:0] td_d = 0;
  always @(posedge clk) begin
    if (!rst_n) begin
      tv_d <= 0; trdy_d <= 0;
    end else begin
      // Protocol: tvalid may not be withdrawn, and tdata may not change, until
      // the beat has been ACCEPTED. The accept is (tvalid && tready) in the
      // PREVIOUS cycle, so this has to test trdy_d, not the current tready --
      // testing the current one flags the perfectly legal case of a beat taken
      // last cycle after which the ring went empty and tvalid dropped.
      if (tv_d && !trdy_d && (!tcn_feed_tvalid || tcn_feed_tdata !== td_d))
        proto_violation <= 1'b1;
      if (tcn_feed_tvalid && tcn_feed_tready) begin
        recs.push_back(tcn_feed_tdata);
        if (tcn_feed_tdata == 64'd0) n_zero_recs++;
      end
      tv_d   <= tcn_feed_tvalid;
      trdy_d <= tcn_feed_tready;
      td_d   <= tcn_feed_tdata;
    end
  end

  logic [15:0] grecs [$];
  always @(posedge clk) if (rst_n && gated_feed_tvalid && gated_feed_tready)
    grecs.push_back(gated_feed_tdata);

  task do_reset;
    rst_n = 0; s_axis_tvalid = 0; s_axis_tlast = 0;
    repeat(5) @(posedge clk); @(negedge clk);
    rst_n = 1; @(posedge clk); #1;
  endtask

  task automatic axil_write(input int word_addr, input logic [31:0] data);
    bit aw_done, w_done;
    @(negedge clk);
    s_axil_awaddr = word_addr * 4; s_axil_awvalid = 1'b1;
    s_axil_wdata = data; s_axil_wstrb = 4'hF; s_axil_wvalid = 1'b1;
    aw_done = 1'b0; w_done = 1'b0;
    while (!aw_done || !w_done) begin
      @(posedge clk); #1;
      if (!aw_done && s_axil_awready) aw_done = 1'b1;
      if (!w_done && s_axil_wready)   w_done  = 1'b1;
    end
    @(negedge clk);
    s_axil_awvalid = 1'b0; s_axil_wvalid = 1'b0;
  endtask

  task automatic axil_read(input int word_addr, output logic [31:0] data);
    bit accepted;
    @(negedge clk);
    s_axil_araddr = word_addr * 4; s_axil_arvalid = 1'b1;
    accepted = 1'b0;
    while (!accepted) begin @(posedge clk); if (s_axil_arready) accepted = 1'b1; end
    @(negedge clk); s_axil_arvalid = 1'b0;
    @(posedge clk);
    data = s_axil_rdata;
  endtask

  // 64-byte frame: dst MAC low 16 bits and etherType chosen by the caller.
  task automatic send_frame(input [15:0] dst_lo, input [15:0] etype);
    logic [TB_AXI_DATA_W-1:0] beat;
    logic [TB_BEAT_BYTES-1:0] keep;
    byte pkt[$];
    int nbeats, nbytes;
    nbytes = 64;
    pkt.delete();
    for (int i = 0; i < nbytes; i++) pkt.push_back(8'(i));
    pkt[0]=8'hAA; pkt[1]=8'hBB; pkt[2]=8'hCC; pkt[3]=8'hDD;
    pkt[4]=dst_lo[15:8]; pkt[5]=dst_lo[7:0];
    pkt[12] = etype[15:8]; pkt[13] = etype[7:0];
    nbeats = (nbytes + TB_BEAT_BYTES - 1) / TB_BEAT_BYTES;
    for (int b = 0; b < nbeats; b++) begin
      beat = '0; keep = '0;
      for (int i = 0; i < TB_BEAT_BYTES; i++)
        if (b*TB_BEAT_BYTES + i < nbytes) begin
          beat[i*8 +: 8] = pkt[b*TB_BEAT_BYTES + i];
          keep[i] = 1'b1;
        end
      @(negedge clk);
      s_axis_tdata = beat; s_axis_tkeep = keep;
      s_axis_tvalid = 1'b1; s_axis_tlast = (b == nbeats - 1);
      @(posedge clk);
      while (!s_axis_tready) @(posedge clk);
      #1;
    end
    @(negedge clk);
    s_axis_tvalid = 1'b0; s_axis_tlast = 1'b0;
  endtask

  int out_pkts; logic saw_last;
  always @(posedge clk) if (rst_n && m_axis_tvalid && m_axis_tready && m_axis_tlast)
    out_pkts <= out_pkts + 1;

  logic [31:0] rd;
  logic [63:0] r0;

  initial begin
    $display("\n================================================================");
    $display("  feprobe -- FeatureExport record stream");
    $display("================================================================");
    do_reset();
    out_pkts = 0;

    // forward etype 0x0801 to port 5; etype 0x0802 is dropped by the table
    axil_write(0, 0); axil_write(1, 1); axil_write(2, 16'h0801); axil_write(3, 5); axil_write(4, 1);
    axil_write(0, 1); axil_write(1, 2); axil_write(2, 16'h0802); axil_write(3, 0); axil_write(4, 1);
    axil_write(64, 1);                            // enable the feed
    repeat (6) @(posedge clk);

    // ── F1/F2: records appear, fields are where they should be ──────────────
    $display("\n== F1/F2: one record per packet, fields in position ==");
    recs.delete(); grecs.delete();
    send_frame(16'h1234, 16'h0801);
    repeat (40) @(posedge clk);
    chk("F1: exactly one record for one packet", recs.size() == 1);
    chk("F1: gated_feed also records a FORWARDED packet",
        grecs.size() == 1 && grecs[0] == 16'h1234);
    if (recs.size() > 0) begin
      r0 = recs[0];
      chk("F2: [63:48] = eth.etype",        r0[63:48] == 16'h0801);
      chk("F2: [47:32] = packet_length 64", r0[47:32] == 16'd64);
      chk("F2: [31:16] = eth.dst[15:0]",    r0[31:16] == 16'h1234);
      chk("F2: [15:8]  = the 0xA5 constant",r0[15:8]  == 8'hA5);
      chk("F2: [7:0]   = parsed_bytes 14",  r0[7:0]   == 8'd14);
    end

    // ── F5: a DROPPED packet still feeds the TCN ────────────────────────────
    $display("\n== F5: a dropped packet still produces a record ==");
    recs.delete(); grecs.delete(); out_pkts = 0;
    send_frame(16'hBEEF, 16'h0802);               // table action = drop_it
    repeat (40) @(posedge clk);
    chk("F5: the packet really was dropped", out_pkts == 0);
    chk("F5: but a record was still produced", recs.size() == 1);
    // The P4 opt-out. Two failures look the same from here and both have
    // happened: the read of smeta.drop seeing the value at issue (0) instead
    // of the drop decided by fwd, and the conditional push inferring a latch
    // that re-pushes the previous record.
    chk("F5: gated_feed (if smeta.drop == 0) produced NO record", grecs.size() == 0);
    if (recs.size() > 0) begin
      // A queue index plus a bit-select in one expression is two indices on a
      // one-dimensional queue, which iverilog rejects -- go through a temp.
      r0 = recs[0];
      chk("F5: and it carries that packet's dst", r0[31:16] == 16'hBEEF);
    end

    // ── F3: tready low forever must not touch the packet path ───────────────
    $display("\n== F3: consumer stalled -- packets must still flow, records drop ==");
    axil_write(65, 1);                            // clear stats
    repeat (4) @(posedge clk);
    recs.delete(); out_pkts = 0;
    tcn_feed_tready = 1'b0;
    for (int i = 0; i < 20; i++) send_frame(16'(i), 16'h0801);
    repeat (300) @(posedge clk);
    chk("F3: ALL 20 packets forwarded despite the stalled consumer", out_pkts == 20);
    chk("F3: no record was accepted while stalled", recs.size() == 0);
    chk("F3: tvalid stayed asserted (protocol held)", tcn_feed_tvalid === 1'b1);
    chk("F3: no stream-protocol violation", proto_violation === 1'b0);
    axil_read(66, rd);
    chk("F3: pushed == staging depth", rd == FE_DEPTH);
    axil_read(67, rd);
    chk("F3: dropped == the rest", rd == 20 - FE_DEPTH);
    axil_read(68, rd);
    chk("F3: status reports a full ring", rd[15:0] == FE_DEPTH);

    // ── F4: drain with tready toggling -- no dupes, no zero records ─────────
    $display("\n== F4: toggling consumer -- no duplicates, no zero records ==");
    recs.delete(); n_zero_recs = 0;
    fork
      begin : toggler
        for (int i = 0; i < 200; i++) begin
          @(negedge clk); tcn_feed_tready = ~tcn_feed_tready;
        end
        tcn_feed_tready = 1'b1;
      end
      begin
        for (int i = 0; i < 6; i++) send_frame(16'hA000 + 16'(i), 16'h0801);
        repeat (200) @(posedge clk);
      end
    join
    repeat (60) @(posedge clk);
    chk("F4: no all-zero record",            n_zero_recs == 0);
    chk("F4: no stream-protocol violation",  proto_violation === 1'b0);
    begin
      bit dupe; dupe = 0;
      for (int i = 1; i < recs.size(); i++)
        if (recs[i] == recs[i-1]) dupe = 1;
      chk("F4: no duplicated consecutive record", !dupe);
    end

    // ── F6: the host's enable switch ────────────────────────────────────────
    $display("\n== F6: enable=0 stops the feed ==");
    tcn_feed_tready = 1'b1;
    repeat (40) @(posedge clk);
    axil_write(64, 0); axil_write(65, 1);          // disable + clear stats
    repeat (6) @(posedge clk);
    recs.delete(); out_pkts = 0;
    for (int i = 0; i < 4; i++) send_frame(16'(i), 16'h0801);
    repeat (120) @(posedge clk);
    chk("F6: packets still forwarded with the feed off", out_pkts == 4);
    chk("F6: no records produced",                        recs.size() == 0);
    axil_read(66, rd);
    chk("F6: pushed stayed 0",                            rd == 32'd0);
    axil_read(67, rd);
    chk("F6: and nothing counted as dropped either",      rd == 32'd0);

    $display("\n================================================================");
    $display("  Results: %0d passed, %0d failed  (total %0d)", pass_cnt, fail_cnt, pass_cnt+fail_cnt);
    $display("================================================================");
    if (fail_cnt == 0) $display("  ALL TESTS PASSED");
    else                $display("  SOME TESTS FAILED");
    $finish;
  end

  initial begin #900000; $display("[TIMEOUT]"); $finish; end

endmodule
