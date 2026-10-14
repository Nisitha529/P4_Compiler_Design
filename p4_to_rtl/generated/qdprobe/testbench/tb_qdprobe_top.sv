// ============================================================================
// tb_qdprobe_top.sv -- the traffic manager's queue depth ABOVE ONE PACKET.
//
// Why this exists: egfeprobe's G3 could only show that deq_qdepth reaches a
// record, never that the number was right. With the default slot ring (NSLOT=4)
// at most two packets can be waiting at once, so every depth it ever saw was 1,
// and the arithmetic above 1 was an untested gap in the traffic manager.
//
// The gap is closed by making the queue genuinely deep: generate with
//   python3 compiler/main.py qdprobe --nslot 8 --cp-map
// hold m_axis_tready low so TX never retires a slot, and push a full ring of
// packets. TM_INFLIGHT=2 of them get past the scheduler; the rest WAIT, and a
// record per packet reports both ends of the wait.
//
//   G1  a lone packet: enqueued into an empty queue, dequeued as the only one
//   G2  a full ring into ONE queue: the deepest the queue gets is
//       NSLOT - TM_INFLIGHT, not 1 -- and no packet or record is lost
//   G3  the drain has the right SHAPE: one dequeue per packet, depth falling
//       by exactly one each time while the enqueue depth rose by exactly one
//   G4  the depth is PER QUEUE, not a global occupancy: the same burst split
//       over two queues halves it
//
// The expected numbers are derived from the DUT's own NSLOT / TM_INFLIGHT
// (read hierarchically), not hardcoded, so this testbench stays correct if the
// app is regenerated with a different --nslot. At --nslot 4 it still passes,
// but only G2's depth of 2 is above 1, so the deeper ring is the point.
//
// Record: [31:24] enq_qdepth  [23:16] deq_qdepth  [15:0] eth.dst[15:0] = seq
// Map: fwd 0 idx / 1 action / 2 key_etype / 3 p_port / 4 commit
//      qd_feed 64 enable / 65 commit / 66 pushed / 67 dropped / 68 status
// ============================================================================
`timescale 1ns/1ps

module tb_qdprobe_top;

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

  // dst[15:0] carries the sequence number, so a record says which packet the
  // two depths belong to; etype selects the queue through the fwd table.
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
  int nslot, inflight, exp_deep, max_qd, max_enq, min_deq;
  // A plain counter array, not an associative one: iverilog 11 has no
  // associative arrays, and a testbench that only builds under one simulator
  // is not a check on anything.
  int seen [0:63];
  int uniq;
  int run_start, run_len, bad_step;

  initial begin
    $display("\n================================================================");
    $display("  qdprobe -- traffic-manager queue depth above one packet");
    $display("================================================================");
    do_reset(); out_pkts = 0;

    // What the shell was built with decides what the right answers are.
    nslot    = dut.NSLOT;
    inflight = dut.TM_INFLIGHT;
    exp_deep = nslot - inflight;   // packets left WAITING when the ring is full
    $display("  built with NSLOT=%0d, TM_INFLIGHT=%0d  ->  deepest queue = %0d",
             nslot, inflight, exp_deep);

    // etype 0x0801 -> port 5 (queue 5 & 3 = 1);  0x0802 -> port 6 (queue 2)
    axil_write(0, 0); axil_write(1, 1); axil_write(2, 16'h0801); axil_write(3, 5); axil_write(4, 1);
    axil_write(0, 1); axil_write(1, 1); axil_write(2, 16'h0802); axil_write(3, 6); axil_write(4, 1);
    repeat (8) @(posedge clk);

    // ── G1: a lone packet ───────────────────────────────────────────────────
    $display("\n== G1: a lone packet queues behind nothing ==");
    recs.delete();
    send_frame(16'h0001, 16'h0801);
    repeat (60) @(posedge clk);
    chk("G1: exactly one record", recs.size() == 1);
    if (recs.size() > 0) begin
      r0 = recs[0];
      chk("G1: it is that packet's record",       r0[15:0]  == 16'h0001);
      chk("G1: enq_qdepth = 0 (queue was empty)", r0[31:24] == 8'd0);
      chk("G1: deq_qdepth = 1 (itself)",          r0[23:16] == 8'd1);
    end

    // ── G2: a full ring into ONE queue ──────────────────────────────────────
    // Stall TX so no slot is ever retired, then fill the ring. The releaser is
    // FORKED on purpose: once the ring is full s_axis_tready drops and
    // send_frame would wait on it forever -- a deadlock in the testbench, not
    // in the design, and it is how the first attempt at this test timed out.
    $display("\n== G2: a full ring into one queue reaches depth %0d ==", exp_deep);
    recs.delete(); out_pkts = 0;
    for (int i = 0; i < 64; i++) seen[i] = 0;
    max_qd = 0; max_enq = 0; min_deq = 255; uniq = 0;
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
    for (int i = 0; i < recs.size(); i++) begin
      r0 = recs[i];
      $display("      rec %0d: seq=%0d enq_qdepth=%0d deq_qdepth=%0d",
               i, r0[15:0], r0[31:24], r0[23:16]);
      if (int'(r0[31:24]) > max_enq) max_enq = int'(r0[31:24]);
      if (int'(r0[23:16]) > max_qd)  max_qd  = int'(r0[23:16]);
      if (int'(r0[23:16]) < min_deq) min_deq = int'(r0[23:16]);
      seen[int'(r0[15:0]) & 63] = seen[int'(r0[15:0]) & 63] + 1;
    end
    for (int i = 0; i < 64; i++) if (seen[i] == 1) uniq++;
    chk("G2: every packet was forwarded",              out_pkts == nslot);
    chk("G2: one record per packet",                   recs.size() == nslot);
    chk("G2: no sequence number lost or duplicated",   uniq == nslot);
    chk("G2: the queue really got deep",               max_qd == exp_deep);
    chk("G2: ... which is above one",                  max_qd > 1);
    chk("G2: a dequeued packet always counts itself",  min_deq >= 1);
    chk("G2: the last arrival saw the others waiting",  max_enq == exp_deep - 1);

    // ── G3: the shape of the drain ──────────────────────────────────────────
    // Records arrive in dequeue order. The first few packets go straight
    // through (depth 1, the inflight allowance), then one record per waiting
    // packet: depth must fall by exactly one each time, down to 1, while the
    // depth those same packets saw at ENQUEUE rose by exactly one -- that pair
    // of slopes is the queue arithmetic, and a counter that drifted or an
    // enqueue counted twice would break one of them.
    $display("\n== G3: one dequeue per packet, depth falling by exactly one ==");
    run_start = -1;
    for (int i = 0; i < recs.size(); i++) begin
      r0 = recs[i];
      if (run_start < 0 && int'(r0[23:16]) == exp_deep) run_start = i;
    end
    chk("G3: the deep run starts where the stall ended", run_start == inflight);
    bad_step = 0; run_len = 0;
    if (run_start >= 0) begin
      for (int i = run_start; i < recs.size(); i++) begin
        r0 = recs[i];
        if (int'(r0[23:16]) != exp_deep - (i - run_start)) bad_step++;
        if (int'(r0[31:24]) != (i - run_start))            bad_step++;
        run_len++;
      end
    end
    $display("      %0d record(s) in the run, %0d step(s) off", run_len, bad_step);
    chk("G3: the run covers every waiting packet", run_len == exp_deep);
    chk("G3: deq_qdepth falls exactly one per dequeue, enq_qdepth rose exactly one per arrival",
        bad_step == 0);

    // ── G4: the depth is per queue ──────────────────────────────────────────
    // The same burst, alternating between two egress ports. If deq_qdepth were
    // a global occupancy it would read the same as G2; being per queue, each
    // queue holds half as many and the depth halves with it.
    $display("\n== G4: splitting the burst over two queues halves the depth ==");
    recs.delete(); out_pkts = 0; max_qd = 0;
    @(negedge clk); m_axis_tready = 1'b0;
    fork
      begin : releaser2
        repeat (400) @(posedge clk);
        @(negedge clk); m_axis_tready = 1'b1;
      end
      begin : sender2
        for (int i = 0; i < nslot; i++)
          send_frame(16'h0020 + 16'(i), (i % 2) ? 16'h0802 : 16'h0801);
      end
    join
    repeat (800) @(posedge clk);
    for (int i = 0; i < recs.size(); i++) begin
      r0 = recs[i];
      $display("      rec %0d: seq=%0d enq_qdepth=%0d deq_qdepth=%0d",
               i, r0[15:0], r0[31:24], r0[23:16]);
      if (int'(r0[23:16]) > max_qd) max_qd = int'(r0[23:16]);
    end
    chk("G4: every packet was still forwarded", out_pkts == nslot);
    chk("G4: half the depth, because half the packets are in the other queue",
        max_qd == exp_deep / 2);

    $display("\n================================================================");
    $display("  Results: %0d passed, %0d failed  (total %0d)", pass_cnt, fail_cnt, pass_cnt+fail_cnt);
    $display("================================================================");
    if (fail_cnt == 0) $display("  ALL TESTS PASSED");
    else                $display("  SOME TESTS FAILED");
    $finish;
  end

  initial begin #2000000; $display("[TIMEOUT]"); $finish; end

endmodule
