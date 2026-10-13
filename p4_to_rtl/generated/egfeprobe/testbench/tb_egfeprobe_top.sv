// ============================================================================
// tb_egfeprobe_top.sv -- FeatureExport pushed from the EGRESS stage.
// See p4src/apps/egfeprobe.p4 for why egress needs its own probe.
//
//   G1  a forwarded packet produces one record, fields in position
//   G2  THE OPEN QUESTION: egress runs for a packet INGRESS ALREADY DROPPED
//       (the shell drives it on deq_fire with the sticky drop in drop_in), and
//       the egress Counter gates itself on !drop_in while a push() does not.
//       This measures what actually happens and pins it.
//   G3  deq_qdepth in the record is non-zero when the traffic manager is
//       holding packets -- the reason to export from egress at all
//   G4  the consumer stalling still does not stall the packet path
//
// Record: [31:16] deq_qdepth   [15:0] eth.dst[15:0]
// Map: fwd 0 idx / 1 action / 2 key_etype / 3 p_port / 4 commit
//      qos_feed 64 enable / 65 clear_stats / 66 pushed / 67 dropped / 68 status
// ============================================================================
`timescale 1ns/1ps

module tb_egfeprobe_top;

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

  logic [31:0] qos_feed_tdata;
  logic        qos_feed_tvalid;
  logic        qos_feed_tready = 1'b1;
  logic [15:0] out_meta_qd;
  logic  [8:0] out_std_meta_egress_port;

  egfeprobe_top dut (
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
    .qos_feed_tdata(qos_feed_tdata), .qos_feed_tvalid(qos_feed_tvalid),
    .qos_feed_tready(qos_feed_tready),
    .out_meta_qd(out_meta_qd),
    .out_std_meta_egress_port(out_std_meta_egress_port)
  );

  int pass_cnt = 0, fail_cnt = 0;
  task automatic chk(input string name, input logic cond);
    if (cond) begin $display("    [PASS] %s", name); pass_cnt++; end
    else      begin $display("    [FAIL] %s", name); fail_cnt++; end
  endtask

  logic [31:0] recs [$];
  always @(posedge clk) if (rst_n && qos_feed_tvalid && qos_feed_tready)
    recs.push_back(qos_feed_tdata);

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

  task automatic axil_read(input int word_addr, output logic [31:0] data);
    bit accepted;
    @(negedge clk);
    s_axil_araddr = word_addr * 4; s_axil_arvalid = 1'b1;
    accepted = 1'b0;
    while (!accepted) begin @(posedge clk); if (s_axil_arready) accepted = 1'b1; end
    @(negedge clk); s_axil_arvalid = 1'b0;
    @(posedge clk); data = s_axil_rdata;
  endtask

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
    @(negedge clk); s_axis_tvalid = 1'b0; s_axis_tlast = 1'b0;
  endtask

  logic [31:0] rd, r0;
  int max_qd;

  initial begin
    $display("\n================================================================");
    $display("  egfeprobe -- FeatureExport from the EGRESS stage");
    $display("================================================================");
    do_reset(); out_pkts = 0;

    axil_write(0, 0); axil_write(1, 1); axil_write(2, 16'h0801); axil_write(3, 5); axil_write(4, 1);
    axil_write(0, 1); axil_write(1, 2); axil_write(2, 16'h0802); axil_write(3, 0); axil_write(4, 1);
    repeat (6) @(posedge clk);

    // ── G1: a forwarded packet ───────────────────────────────────────────────
    $display("\n== G1: a forwarded packet produces one egress record ==");
    recs.delete();
    send_frame(16'h1234, 16'h0801);
    repeat (60) @(posedge clk);
    chk("G1: exactly one record", recs.size() == 1);
    if (recs.size() > 0) begin
      r0 = recs[0];
      chk("G1: [15:0] = eth.dst[15:0]", r0[15:0] == 16'h1234);
      $display("      record = %08h  (deq_qdepth=%0d)", r0, r0[31:16]);
    end

    // ── G2: an ingress-DROPPED packet ───────────────────────────────────────
    // Measured, then pinned. Egress runs for it, and push() has no !drop_in
    // gate (the egress Counter does), so a record IS produced. That is the
    // right default for an IDS -- a dropped attack packet is still evidence --
    // and a program that wants the opposite writes it in P4:
    //     if (standard_metadata.drop == 0) { qos_feed.push(...); }
    // Pinned here so the behaviour cannot change unnoticed.
    $display("\n== G2: an ingress-dropped packet still reaches the egress push ==");
    recs.delete(); out_pkts = 0;
    send_frame(16'hBEEF, 16'h0802);
    repeat (60) @(posedge clk);
    chk("G2: the packet really was dropped", out_pkts == 0);
    chk("G2: a record was still produced",   recs.size() == 1);
    if (recs.size() > 0) begin
      r0 = recs[0];
      chk("G2: and it carries that packet's dst", r0[15:0] == 16'hBEEF);
    end

    // ── G3: deq_qdepth is real ──────────────────────────────────────────────
    // Hold the output off so the traffic manager accumulates packets, then
    // release: the records must show a non-zero queue depth. This is the whole
    // reason to export from egress rather than ingress.
    // What this checks is that deq_qdepth REACHES THE RECORD with a plausible
    // value -- that is the FeatureExport question. It does NOT check the depth
    // semantics themselves.
    //
    // Holding m_axis_tready low backs up the TX path, not the TM queue, so the
    // depth stays at 1 however many packets are in flight; congesting the TM
    // itself needs the dequeue to run slower than the enqueue. Worth stating
    // plainly: NO testbench in the tree currently forces a queue depth above 1
    // and asserts on it (ecn_p4rtl only mentions qdepth in a comment), so the
    // depth arithmetic above 1 is an open gap in the traffic manager's
    // coverage, not something this probe quietly dropped.
    $display("\n== G3: deq_qdepth reaches the record with a plausible value ==");
    recs.delete(); out_pkts = 0; max_qd = 0;
    // Only as many packets as the slot ring holds (NSLOT=4), and the release is
    // forked: with the output held off the ring fills, s_axis_tready drops, and
    // send_frame would otherwise wait for it forever -- a deadlock in the
    // TESTBENCH, which is how the first version of this test timed out.
    @(negedge clk); m_axis_tready = 1'b0;
    fork
      begin : releaser
        repeat (120) @(posedge clk);
        @(negedge clk); m_axis_tready = 1'b1;
      end
      begin : sender
        for (int i = 0; i < 3; i++) send_frame(16'hC000 + 16'(i), 16'h0801);
      end
    join
    repeat (300) @(posedge clk);
    for (int i = 0; i < recs.size(); i++) begin
      r0 = recs[i];
      if (int'(r0[31:16]) > max_qd) max_qd = int'(r0[31:16]);
    end
    $display("      %0d record(s), highest deq_qdepth seen = %0d", recs.size(), max_qd);
    chk("G3: records were produced for the burst", recs.size() >= 3);
    chk("G3: deq_qdepth arrives in the record (>= 1)", max_qd >= 1);

    // ── G4: a stalled consumer must not stall packets ───────────────────────
    $display("\n== G4: stalled consumer does not stall the packet path ==");
    axil_write(65, 1); repeat (4) @(posedge clk);
    recs.delete(); out_pkts = 0;
    @(negedge clk); qos_feed_tready = 1'b0;
    for (int i = 0; i < 16; i++) send_frame(16'(i), 16'h0801);
    repeat (400) @(posedge clk);
    chk("G4: all 16 packets forwarded", out_pkts == 16);
    axil_read(67, rd);
    $display("      dropped records = %0d", rd);
    chk("G4: records were dropped rather than stalling", rd > 0);
    qos_feed_tready = 1'b1;

    $display("\n================================================================");
    $display("  Results: %0d passed, %0d failed  (total %0d)", pass_cnt, fail_cnt, pass_cnt+fail_cnt);
    $display("================================================================");
    if (fail_cnt == 0) $display("  ALL TESTS PASSED");
    else                $display("  SOME TESTS FAILED");
    $finish;
  end

  initial begin #900000; $display("[TIMEOUT]"); $finish; end

endmodule
