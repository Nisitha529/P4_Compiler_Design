// ============================================================================
// tb_qdprobe_limit.sv -- --tm-qlimit, the other half of queue depth.
//
// Lives OUTSIDE generated/ on purpose: it reads dut.tm_tail_drops, which only
// exists when the app was generated with --tm-qlimit, so the regression's
// "build every testbench in the app directory" loop must not pick it up. It is
// driven by scripts/check_tm_qdepth.sh, which generates that variant first.
//
// Built against: python3 compiler/main.py qdprobe --nslot 8 --tm-qlimit 3
//
//   L1  the limit bites at the right depth: with the transmitter stalled, the
//       packets that find the queue already at TM_QLIMIT are dropped and the
//       earlier ones are not
//   L2  the tail-drop counter agrees with the packets that went missing
//   L3  a tail-dropped packet still produces its FeatureExport record (the
//       same ungated-push behaviour egfeprobe pinned for an ingress drop) and
//       its depths show WHY it was dropped -- enq_qdepth >= TM_QLIMIT
//   L4  what the limit does NOT do, pinned so it cannot be mistaken: the
//       packet is still enqueued and still occupies the queue until TX
//       discards it, so the depth keeps climbing past the limit. The limit
//       marks packets for discard; it does not cap occupancy.
// ============================================================================
`timescale 1ns/1ps

module tb_qdprobe_limit;

  localparam CLK_T = 10;
  logic clk = 0;
  always #(CLK_T/2) clk = ~clk;
  logic rst_n;

  parameter  int TB_BEAT_BYTES = 32;
  localparam int TB_AXI_DATA_W = TB_BEAT_BYTES * 8;

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

  logic [31:0] qd_feed_tdata;
  logic        qd_feed_tvalid;
  logic        qd_feed_tready = 1'b1;
  logic  [7:0] out_meta_enqd, out_meta_deqd;
  logic  [8:0] out_std_meta_egress_port;

  qdprobe_top dut (
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
    .qd_feed_tdata(qd_feed_tdata), .qd_feed_tvalid(qd_feed_tvalid),
    .qd_feed_tready(qd_feed_tready),
    .out_meta_enqd(out_meta_enqd), .out_meta_deqd(out_meta_deqd),
    .out_std_meta_egress_port(out_std_meta_egress_port)
  );

  int pass_cnt = 0, fail_cnt = 0;
  task automatic chk(input string name, input logic cond);
    if (cond) begin $display("    [PASS] %s", name); pass_cnt++; end
    else      begin $display("    [FAIL] %s", name); fail_cnt++; end
  endtask

  logic [31:0] recs [$];
  always @(posedge clk) if (rst_n && qd_feed_tvalid && qd_feed_tready)
    recs.push_back(qd_feed_tdata);

  int out_pkts;
  always @(posedge clk) if (rst_n && m_axis_tvalid && m_axis_tready && m_axis_tlast)
    out_pkts <= out_pkts + 1;

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
    @(negedge clk); s_axil_awvalid = 1'b0; s_axil_wvalid = 1'b0;
  endtask

  task automatic send_frame(input [15:0] seq, input [15:0] etype);
    logic [TB_AXI_DATA_W-1:0] beat;
    logic [TB_BEAT_BYTES-1:0] keep;
    byte pkt[$];
    int nbeats, nbytes;
    nbytes = 64;
    pkt.delete();
    for (int i = 0; i < nbytes; i++) pkt.push_back(8'(i));
    pkt[4] = seq[15:8]; pkt[5] = seq[7:0];
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
    @(negedge clk); s_axis_tvalid = 1'b0; s_axis_tlast = 1'b0;
  endtask

  logic [31:0] r0;
  int nslot, inflight, qlimit, exp_kept, exp_dropped, drops, max_qd;
  int over_limit_recs, under_limit_recs;

  initial begin
    $display("\n================================================================");
    $display("  qdprobe -- traffic-manager tail drop (--tm-qlimit)");
    $display("================================================================");
    do_reset(); out_pkts = 0;

    nslot    = dut.NSLOT;
    inflight = dut.TM_INFLIGHT;
    qlimit   = dut.TM_QLIMIT;
    // The first `inflight` packets never wait, so they are never at the limit.
    // After that the queue fills one per packet, and the packet that arrives
    // when the depth has reached TM_QLIMIT is the first to be dropped.
    exp_kept    = inflight + qlimit;
    exp_dropped = nslot - exp_kept;
    $display("  NSLOT=%0d TM_INFLIGHT=%0d TM_QLIMIT=%0d  ->  expect %0d kept, %0d tail-dropped",
             nslot, inflight, qlimit, exp_kept, exp_dropped);

    axil_write(0, 0); axil_write(1, 1); axil_write(2, 16'h0801); axil_write(3, 5); axil_write(4, 1);
    repeat (8) @(posedge clk);

    recs.delete(); out_pkts = 0; max_qd = 0;
    over_limit_recs = 0; under_limit_recs = 0;
    @(negedge clk); m_axis_tready = 1'b0;
    fork
      begin : releaser
        repeat (400) @(posedge clk);
        @(negedge clk); m_axis_tready = 1'b1;
      end
      begin : sender
        for (int i = 0; i < nslot; i++) send_frame(16'h0010 + 16'(i), 16'h0801);
      end
    join
    repeat (800) @(posedge clk);
    drops = dut.tm_tail_drops;
    for (int i = 0; i < recs.size(); i++) begin
      r0 = recs[i];
      $display("      rec %0d: seq=%0d enq_qdepth=%0d deq_qdepth=%0d%s",
               i, r0[15:0], r0[31:24], r0[23:16],
               (int'(r0[31:24]) >= qlimit) ? "   <- was at the limit on arrival" : "");
      if (int'(r0[23:16]) > max_qd) max_qd = int'(r0[23:16]);
      if (int'(r0[31:24]) >= qlimit) over_limit_recs++; else under_limit_recs++;
    end
    $display("      forwarded=%0d  tail_drops=%0d  records=%0d",
             out_pkts, drops, recs.size());

    chk("L1: exactly the packets that found room were forwarded", out_pkts == exp_kept);
    chk("L2: the tail-drop counter matches what went missing",    drops == exp_dropped);
    chk("L2: ... and nothing was counted twice",                  drops == nslot - out_pkts);
    chk("L3: a tail-dropped packet still produced its record",    recs.size() == nslot);
    chk("L3: and its record says it arrived at the limit",        over_limit_recs == exp_dropped);
    chk("L3: the forwarded ones arrived below the limit",         under_limit_recs == exp_kept);
    // L4 is the honest part: the limit does not cap occupancy. A dropped packet
    // is still enqueued and still holds its place until TX discards it, so the
    // depth reaches the same NSLOT - TM_INFLIGHT it would with no limit at all.
    chk("L4: occupancy is NOT capped by the limit (depth still reaches NSLOT-TM_INFLIGHT)",
        max_qd == nslot - inflight);

    $display("\n================================================================");
    $display("  Results: %0d passed, %0d failed  (total %0d)", pass_cnt, fail_cnt, pass_cnt+fail_cnt);
    $display("================================================================");
    if (fail_cnt == 0) $display("  ALL TESTS PASSED");
    else                $display("  SOME TESTS FAILED");
    $finish;
  end

  initial begin #2000000; $display("[TIMEOUT]"); $finish; end

endmodule
