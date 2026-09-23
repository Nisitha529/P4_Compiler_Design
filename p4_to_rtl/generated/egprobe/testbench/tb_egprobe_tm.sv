// ============================================================================
// tb_egprobe_tm.sv -- the TRAFFIC MANAGER: per-queue FIFO order, and real
// cross-queue reordering (docs/traffic_manager_plan.md step 3).
//
// egprobe's l2 table maps eth.etype to an egress_port, and the shell puts a
// packet into the queue named by that port's low bits. This harness stalls the
// output so packets pile up in their queues, then releases it and watches the
// order they come back in. Each frame is tagged in eth.dst, which nothing in
// the program writes, so a tag survives the pipeline untouched.
//
//   T1  per-queue order: within one output port, order is exactly arrival
//       order -- a queue is a FIFO and the scheduler must not disturb it
//   T2  cross-queue REORDERING: with two queues backed up, a later-arriving
//       packet on the idle queue overtakes earlier packets on the busy one.
//       This is the whole point of the TM, and it is the first time this
//       shell has ever emitted packets in an order other than arrival order.
//   T3  no packet is lost or duplicated across the reordering
//   T4  round-robin fairness: one queue offered far more traffic than another
//       must not starve it
//
// Compile:
//   iverilog -g2012 -o sim tb_egprobe_tm.sv ../egprobe_pkg.sv \\
//     $(ls ../*.sv | grep -v _pkg)   &&  vvp sim
// ============================================================================
`timescale 1ns/1ps

module tb_egprobe_tm;

  localparam CLK_T = 10;
  logic clk = 0;
  always #(CLK_T/2) clk = ~clk;
  logic rst_n;

  localparam int TB_BEAT_BYTES = 32;
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

  logic [63:0] out_meta_ts;
  logic  [8:0] out_std_meta_egress_port;

  egprobe_top dut (
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
    .out_meta_ts(out_meta_ts), .out_std_meta_egress_port(out_std_meta_egress_port)
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

  // One frame of `nbytes` (default 64): 14-byte ethernet header + payload.
  task automatic send_frame(input [15:0] etype, input int nbytes = 64);
    logic [TB_AXI_DATA_W-1:0] beat;
    byte pkt[$];
    int nbeats;
    pkt.delete();
    for (int i = 0; i < nbytes; i++) pkt.push_back(8'(i));
    // dst 00:11:22:33:44:55, src 66:77:88:99:aa:bb, etype big-endian
    pkt[0]=8'h00; pkt[1]=8'h11; pkt[2]=8'h22; pkt[3]=8'h33; pkt[4]=8'h44; pkt[5]=8'h55;
    pkt[6]=8'h66; pkt[7]=8'h77; pkt[8]=8'h88; pkt[9]=8'h99; pkt[10]=8'haa; pkt[11]=8'hbb;
    pkt[12] = etype[15:8]; pkt[13] = etype[7:0];
    nbeats = (nbytes + TB_BEAT_BYTES - 1) / TB_BEAT_BYTES;
    for (int b = 0; b < nbeats; b++) begin
      beat = '0;
      for (int i = 0; i < TB_BEAT_BYTES; i++)
        if (b*TB_BEAT_BYTES + i < nbytes) beat[i*8 +: 8] = pkt[b*TB_BEAT_BYTES + i];
      @(negedge clk);
      s_axis_tdata = beat; s_axis_tkeep = '1;
      s_axis_tvalid = 1'b1; s_axis_tlast = (b == nbeats - 1);
      @(posedge clk);
      while (!s_axis_tready) @(posedge clk);
      #1;
    end
    @(negedge clk);
    s_axis_tvalid = 1'b0; s_axis_tlast = 1'b0;
  endtask

  // Watch the output for a bounded window and report whether a packet
  // emerged. A drop shows up as silence, so a bound is the only way to
  // test it.
  int out_beats;
  logic saw_tlast;
  logic [TB_AXI_DATA_W-1:0] out_first_beat;
  logic [8:0]  out_port;
  logic [63:0] out_ts;
  task automatic watch_output(input int cycles);
    out_beats = 0; saw_tlast = 1'b0;
    repeat (cycles) begin
      @(posedge clk); #1;
      if (m_axis_tvalid && m_axis_tready) begin
        if (out_beats == 0) begin
          out_first_beat = m_axis_tdata;
          out_port = out_std_meta_egress_port;
          out_ts   = out_meta_ts;
        end
        out_beats++;
        if (m_axis_tlast) saw_tlast = 1'b1;
      end
    end
  endtask
  function automatic logic [47:0] beat_smac(input logic [TB_AXI_DATA_W-1:0] b);
    return {b[6*8 +: 8], b[7*8 +: 8], b[8*8 +: 8], b[9*8 +: 8], b[10*8 +: 8], b[11*8 +: 8]};
  endfunction
  function automatic logic [15:0] beat_etype(input logic [TB_AXI_DATA_W-1:0] b);
    return {b[12*8 +: 8], b[13*8 +: 8]};
  endfunction

  // ── AXI4-Lite helpers ──────────────────────────────────────────────────────
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
    @(negedge clk);
    s_axil_arvalid = 1'b0;
    @(posedge clk);
    data = s_axil_rdata;
  endtask

  // Register map (from egprobe_top.sv):
  //   l2 (ingress, exact on etype):    0 idx 1 action 2 key_etype 3 p_port 4 commit
  //   port_smac (EGRESS, exact on egress_port): 64 idx 65 action 66 key_egress_port
  //                                    67 p_smac[31:0] 68 p_smac[47:32] 69 commit
  //   tx_pkts (EGRESS counter):        128 query_idx 129 query_commit 130 status
  //                                    131 value_lo 132 value_hi
  localparam int ACT_FWD = 1, ACT_DROP = 2, ACT_RETAG = 3;   // l2 action ids
  localparam int ACT_SET_SMAC = 1;
  task automatic prog_l2(input int idx, input [15:0] etype, input int act, input [8:0] port);
    axil_write(0, idx); axil_write(1, act); axil_write(2, etype); axil_write(3, port); axil_write(4, 1);
    repeat (4) @(posedge clk);
  endtask
  task automatic prog_port_smac(input int idx, input [8:0] port, input [47:0] smac);
    axil_write(64, idx); axil_write(65, ACT_SET_SMAC); axil_write(66, port);
    axil_write(67, smac[31:0]); axil_write(68, smac[47:32]); axil_write(69, 1);
    repeat (4) @(posedge clk);
  endtask
  task automatic query_tx_pkts(input [3:0] idx, output [63:0] value);
    logic [31:0] status, lo, hi;
    axil_write(128, {28'd0, idx});
    axil_write(129, 32'd0);
    status = 32'hFFFF_FFFF;
    while (status[0]) axil_read(130, status);
    axil_read(131, lo); axil_read(132, hi);
    value = {hi, lo};
  endtask

  // Back-to-back frame driver: tvalid never drops between frames.
  logic [15:0] burst[$];   // frames for send_frames_b2b (module-level: vvp
                           // cannot pass a queue into an automatic task)
  task automatic send_frames_b2b();
    logic [TB_AXI_DATA_W-1:0] beat;
    logic [15:0] et;
    for (int k = 0; k < burst.size(); k++) begin
      for (int b = 0; b < 2; b++) begin
        beat = '0;
        for (int i = 0; i < TB_BEAT_BYTES; i++) beat[i*8 +: 8] = 8'(b*TB_BEAT_BYTES + i);
        if (b == 0) begin
          beat[0*8 +: 8]=8'h00; beat[1*8 +: 8]=8'h11; beat[2*8 +: 8]=8'h22; beat[3*8 +: 8]=8'h33; beat[4*8 +: 8]=8'h44; beat[5*8 +: 8]=8'h55;
          beat[6*8 +: 8]=8'h66; beat[7*8 +: 8]=8'h77; beat[8*8 +: 8]=8'h88; beat[9*8 +: 8]=8'h99; beat[10*8 +: 8]=8'haa; beat[11*8 +: 8]=8'hbb;
          et = burst[k];
          beat[12*8 +: 8] = et[15:8]; beat[13*8 +: 8] = et[7:0];
        end
        @(negedge clk);
        s_axis_tdata = beat; s_axis_tkeep = '1; s_axis_tvalid = 1'b1; s_axis_tlast = (b == 1);
        @(posedge clk);
        while (!s_axis_tready) @(posedge clk);
        #1;
      end
    end
    @(negedge clk);
    s_axis_tvalid = 1'b0; s_axis_tlast = 1'b0;
  endtask
  // Collector for bursts: counts output packets and records each one's
  // sideband port and timestamp.
  int   burst_pkts;
  logic [8:0]  burst_port [$];
  logic [63:0] burst_ts   [$];
  logic burst_watch = 0;
  always @(posedge clk) begin
    #1;
    if (burst_watch && m_axis_tvalid && m_axis_tready && m_axis_tlast) begin
      burst_pkts++;
      burst_port.push_back(out_std_meta_egress_port);
      burst_ts.push_back(out_meta_ts);
    end
  end


  // ── Frame driver: tag goes in eth.dst, etype picks the output port ────────
  task automatic send_tagged(input [15:0] etype, input [15:0] tag);
    logic [TB_AXI_DATA_W-1:0] beat;
    for (int b = 0; b < 2; b++) begin
      beat = '0;
      for (int i = 0; i < TB_BEAT_BYTES; i++) beat[i*8 +: 8] = 8'(b*TB_BEAT_BYTES + i);
      if (b == 0) begin
        beat[0*8 +: 8]=8'h00; beat[1*8 +: 8]=8'h00; beat[2*8 +: 8]=8'h00;
        beat[3*8 +: 8]=8'h00; beat[4*8 +: 8]=tag[15:8]; beat[5*8 +: 8]=tag[7:0];
        beat[6*8 +: 8]=8'h66; beat[7*8 +: 8]=8'h77; beat[8*8 +: 8]=8'h88;
        beat[9*8 +: 8]=8'h99; beat[10*8 +: 8]=8'haa; beat[11*8 +: 8]=8'hbb;
        beat[12*8 +: 8] = etype[15:8]; beat[13*8 +: 8] = etype[7:0];
      end
      @(negedge clk);
      s_axis_tdata = beat; s_axis_tkeep = '1; s_axis_tvalid = 1'b1; s_axis_tlast = (b == 1);
      @(posedge clk);
      while (!s_axis_tready) @(posedge clk);
      #1;
    end
    @(negedge clk);
    s_axis_tvalid = 1'b0; s_axis_tlast = 1'b0;
  endtask

  // Collector: one entry per emerging packet, recording its tag and the
  // source MAC egress stamped on it (which identifies the output port).
  int          got_n;
  logic [15:0] got_tag  [$];
  logic [47:0] got_smac [$];
  logic        collecting = 0;
  logic [15:0] cur_tag;
  logic        cur_seen;
  always @(posedge clk) begin
    #1;
    if (collecting && m_axis_tvalid && m_axis_tready) begin
      if (!cur_seen) begin
        cur_tag = {m_axis_tdata[4*8 +: 8], m_axis_tdata[5*8 +: 8]};
        got_smac.push_back({m_axis_tdata[6*8 +: 8], m_axis_tdata[7*8 +: 8],
                            m_axis_tdata[8*8 +: 8], m_axis_tdata[9*8 +: 8],
                            m_axis_tdata[10*8 +: 8], m_axis_tdata[11*8 +: 8]});
        cur_seen = 1'b1;
      end
      if (m_axis_tlast) begin
        got_tag.push_back(cur_tag);
        got_n++;
        cur_seen = 1'b0;
      end
    end
  end

  int  n_ok, n_a, n_b, first_b_at, last_a_at, seen;
  logic [15:0] prev;

  initial begin
    $display("\n== tb_egprobe_tm: traffic-manager queues, order and reordering ==\n");
    do_reset();

    // etype 1 -> port 1 (queue 1), etype 2 -> port 2 (queue 2)
    prog_l2(0, 16'h0001, ACT_FWD, 9'd1);
    prog_l2(1, 16'h0002, ACT_FWD, 9'd2);
    prog_port_smac(0, 9'd1, 48'h0000AA000001);
    prog_port_smac(1, 9'd2, 48'h0000AA000002);

    // ---- T1: per-queue order is arrival order ---------------------------
    $display("== T1: within one output port, order is exactly arrival order ==");
    got_n = 0; got_tag.delete(); got_smac.delete(); cur_seen = 0;
    collecting = 1;
    for (int k = 0; k < 8; k++) send_tagged(16'h0001, 16'(k + 1));
    repeat (250) @(posedge clk);
    collecting = 0;
    chk("T1: all 8 frames emerged", got_n == 8);
    n_ok = 1; prev = 0;
    foreach (got_tag[k]) begin
      if (got_tag[k] <= prev) n_ok = 0;
      prev = got_tag[k];
    end
    chk("T1: tags strictly increasing -- one queue is a FIFO", n_ok == 1);

    // ---- T2: cross-queue reordering --------------------------------------
    // Stall the output, then send: two primers on port 1 (which drain into
    // the in-flight window), then A on port 1 and B on port 2. A arrives
    // BEFORE B. With both queues backed up the round-robin scheduler serves
    // the other queue next, so B must overtake A.
    $display("\n== T2: a later packet on an idle queue overtakes an earlier one ==");
    got_n = 0; got_tag.delete(); got_smac.delete(); cur_seen = 0;
    m_axis_tready = 1'b0;
    collecting = 1;
    send_tagged(16'h0001, 16'd101);   // primer, port 1
    send_tagged(16'h0001, 16'd102);   // primer, port 1
    send_tagged(16'h0001, 16'd103);   // A: port 1, arrives 3rd
    send_tagged(16'h0002, 16'd104);   // B: port 2, arrives 4th
    repeat (40) @(posedge clk);
    m_axis_tready = 1'b1;
    repeat (300) @(posedge clk);
    collecting = 0;
    chk("T2: all 4 frames emerged", got_n == 4);
    $display("    [INFO] arrival order 101 102 103 104 -> output order %0d %0d %0d %0d",
             got_tag[0], got_tag[1], got_tag[2], got_tag[3]);
    // find where the port-2 packet (104) landed
    first_b_at = -1; last_a_at = -1;
    foreach (got_tag[k]) begin
      if (got_tag[k] == 16'd104) first_b_at = k;
      if (got_tag[k] == 16'd103) last_a_at  = k;
    end
    chk("T2: the port-2 packet overtook the earlier port-1 packet (REORDERED)",
        first_b_at >= 0 && last_a_at >= 0 && first_b_at < last_a_at);
    chk("T2: the two primers still came out first, in order",
        got_tag[0] == 16'd101 && got_tag[1] == 16'd102);

    // ---- T3: nothing lost or duplicated ----------------------------------
    $display("\n== T3: reordering loses and duplicates nothing ==");
    n_ok = 0;
    // `seen` is declared at module scope on purpose: a variable declared
    // inside a loop body has STATIC lifetime here, so its initializer runs
    // once and the count carries over between iterations.
    for (int want = 101; want <= 104; want++) begin
      seen = 0;
      foreach (got_tag[k]) if (got_tag[k] == 16'(want)) seen++;
      if (seen == 1) n_ok++;
    end
    chk("T3: each of the 4 tags appears exactly once", n_ok == 4);
    n_ok = 1;
    foreach (got_smac[k])
      if (got_smac[k] !== 48'h0000AA000001 && got_smac[k] !== 48'h0000AA000002) n_ok = 0;
    chk("T3: every packet carries its own port's MAC (egress ran per packet)", n_ok == 1);

    // ---- T4: round-robin fairness ----------------------------------------
    // Offer port 1 three times as much traffic as port 2 with the output
    // stalled, then drain: port 2's packets must not be left until last.
    $display("\n== T4: a busy queue does not starve an idle one ==");
    got_n = 0; got_tag.delete(); got_smac.delete(); cur_seen = 0;
    m_axis_tready = 1'b0;
    collecting = 1;
    send_tagged(16'h0001, 16'd201);
    send_tagged(16'h0001, 16'd202);
    send_tagged(16'h0001, 16'd203);
    send_tagged(16'h0002, 16'd204);
    repeat (40) @(posedge clk);
    m_axis_tready = 1'b1;
    repeat (400) @(posedge clk);
    collecting = 0;
    chk("T4: all 4 frames emerged", got_n == 4);
    first_b_at = -1;
    foreach (got_tag[k]) if (got_tag[k] == 16'd204) first_b_at = k;
    chk("T4: the single port-2 packet was not left until last", first_b_at >= 0 && first_b_at < 3);
    n_a = 0; n_ok = 1; prev = 0;
    foreach (got_tag[k])
      if (got_tag[k] >= 16'd201 && got_tag[k] <= 16'd203) begin
        if (got_tag[k] <= prev) n_ok = 0;
        prev = got_tag[k];
        n_a++;
      end
    chk("T4: port 1's three packets kept their order among themselves", n_ok == 1 && n_a == 3);

    $display("\n================================================================");
    $display("  Results: %0d passed, %0d failed  (total %0d)", pass_cnt, fail_cnt, pass_cnt+fail_cnt);
    $display("================================================================");
    if (fail_cnt == 0) $display("  ALL TESTS PASSED");
    else                $display("  SOME TESTS FAILED");
    $finish;
  end

endmodule
