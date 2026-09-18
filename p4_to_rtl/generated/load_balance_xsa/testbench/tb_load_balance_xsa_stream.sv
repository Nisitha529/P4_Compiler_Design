// ============================================================================
// tb_load_balance_xsa_stream.sv -- STREAMING harness for the shell.
//
// Step 0 of the streaming-shell work (docs/streaming_shell_plan.md). This is
// the regression target every later step must keep green, and the yardstick
// that shows whether a step actually improved throughput.
//
// It does three things the existing top-level tests deliberately do not:
//   * offers packets BACK-TO-BACK: the next packet's first beat is presented
//     the cycle after the previous packet's tlast, with tvalid never dropped
//     -- the way a real link behaves. The DUT decides how many it accepts.
//   * checks every output packet independently, in order, against what the
//     ECMP tables say it should be -- so a stale-PHV / wrong-order /
//     dropped-payload bug under concurrency cannot hide.
//   * MEASURES: cycles from first input beat to last output tlast, input
//     cycles where tready was low against a valid beat (= backpressure the
//     shell imposed), and derives packets-per-cycle.
// T3 does the same under random m_axis_tready stalls.
//
// On the CURRENT single-packet shell this passes functionally (packets are
// simply serialised) and records the baseline. Later steps must not change
// what comes out -- only how fast.
//
// Compile:
//   iverilog -g2012 -o sim tb_load_balance_xsa_stream.sv ../*.sv && vvp sim
// ============================================================================
`timescale 1ns/1ps

module tb_load_balance_xsa_stream;

  localparam CLK_T = 10;
  logic clk = 0;
  always #(CLK_T/2) clk = ~clk;
  logic rst_n;
  int cyc = 0;
  always @(posedge clk) cyc++;

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
  logic [13:0] out_meta_ecmp_select;
  logic  [8:0] out_meta_egress_port;

  load_balance_xsa_top dut (
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
    .out_meta_ecmp_select(out_meta_ecmp_select), .out_meta_egress_port(out_meta_egress_port)
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

  // ── AXI4-Lite + table programming (as tb_load_balance_xsa_top) ────────────
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
  task automatic program_tables;
    axil_write(0,0); axil_write(1,1); axil_write(2,32'h0A000000); axil_write(3,8);
    axil_write(4,0); axil_write(5,7); axil_write(6,1); repeat(4) @(posedge clk);
    axil_write(64,0); axil_write(65,1); axil_write(66,4); axil_write(67,32'h00000004);
    axil_write(68,32'hAAAA); axil_write(69,32'h0A000001); axil_write(70,3); axil_write(71,1); repeat(4) @(posedge clk);
    axil_write(64,1); axil_write(65,1); axil_write(66,6); axil_write(67,32'h00000006);
    axil_write(68,32'hBBBB); axil_write(69,32'h0A000002); axil_write(70,5); axil_write(71,1); repeat(4) @(posedge clk);
    axil_write(128,0); axil_write(129,1); axil_write(130,3); axil_write(131,32'hDEAD0003); axil_write(132,0); axil_write(133,1); repeat(4) @(posedge clk);
    axil_write(128,1); axil_write(129,1); axil_write(130,5); axil_write(131,32'hDEAD0005); axil_write(132,0); axil_write(133,1); repeat(4) @(posedge clk);
  endtask

  // ── Frame builder: flow A (sport 0x1234 -> bucket 4/port 3) or B (0x9999 -> 6/5) ──
  byte pb[$];
  task automatic a16(input [15:0] v); pb.push_back(v[15:8]); pb.push_back(v[7:0]); endtask
  task automatic a32(input [31:0] v); a16(v[31:16]); a16(v[15:0]); endtask
  task automatic a48(input [47:0] v); a16(v[47:32]); a32(v[31:0]); endtask
  task automatic build_frame(input bit flowB, input int total_bytes, input [15:0] tag);
    pb.delete();
    a48(48'hAABBCCDDEEFF); a48(48'h112233445566); a16(16'h0800);
    pb.push_back(8'h45); pb.push_back(8'h00); a16(16'd40); a16(tag);      // id = tag
    a16(16'h4000); pb.push_back(8'd64); pb.push_back(8'd6);
    a16(16'h0000); a32(32'hC0A80101); a32(32'h0A000005);
    a16(flowB ? 16'h9999 : 16'h1234); a16(16'h0050); a32(32'd1); a32(32'd0);
    pb.push_back(8'h50); pb.push_back(8'h02); a16(16'd1024); a16(16'd0); a16(16'd0);
    while (pb.size() < total_bytes) pb.push_back(8'(pb.size()));
  endtask

  // ── Back-to-back driver: never drops tvalid between packets ──────────────
  int in_stall_cycles = 0;   // valid beat offered, tready low
  int first_in_cycle = -1;
  bit accepted;
  bit in_stall_en = 0;      // when set, the driver randomly drops tvalid between beats
  task automatic send_pb_b2b;
    int nbeats = (pb.size() + TB_BEAT_BYTES - 1) / TB_BEAT_BYTES;
    for (int b = 0; b < nbeats; b++) begin
      logic [TB_AXI_DATA_W-1:0] beat = '0;
      logic [TB_BEAT_BYTES-1:0] keep = '0;
      if (in_stall_en) begin
        // idle 0-3 cycles with tvalid low (a real link's gaps / a slow sender)
        s_axis_tvalid = 1'b0;
        repeat ($urandom % 4) begin @(posedge clk); #1; end
      end
      for (int i = 0; i < TB_BEAT_BYTES; i++)
        if (b*TB_BEAT_BYTES + i < pb.size()) begin beat[i*8 +: 8] = pb[b*TB_BEAT_BYTES + i]; keep[i] = 1'b1; end
      s_axis_tdata = beat; s_axis_tkeep = keep; s_axis_tvalid = 1'b1; s_axis_tlast = (b == nbeats-1);
      if (first_in_cycle < 0) first_in_cycle = cyc;
      // hold until accepted, counting every stalled cycle
      accepted = 1'b0;
      while (!accepted) begin
        @(posedge clk);
        if (s_axis_tready) accepted = 1'b1;
        else in_stall_cycles++;
      end
      #1;
    end
    // next packet's first beat is presented immediately by the caller
  endtask

  // ── Collector: reassembles output packets, in order ──────────────────────
  byte out_bytes[$];      // all output bytes, packets concatenated in order
  int  out_len[$];        // length of each output packet, in order
  int  out_off[$];        // byte offset of each output packet in out_bytes
  byte cur[$];
  int last_out_cycle = -1;
  always @(posedge clk) begin
    if (m_axis_tvalid && m_axis_tready) begin
      for (int i = 0; i < TB_BEAT_BYTES; i++) if (m_axis_tkeep[i]) cur.push_back(m_axis_tdata[i*8 +: 8]);
      if (m_axis_tlast) begin
        out_off.push_back(out_bytes.size());
        out_len.push_back(cur.size());
        foreach (cur[i]) out_bytes.push_back(cur[i]);
        cur.delete();
        last_out_cycle = cyc;
      end
    end
  end

  // Expected rewrite for a frame of flow A/B: dst MAC, src MAC, dst IP, TTL,
  // and the IPv4 id we tagged it with (proves ORDER, not just content).
  function automatic byte ob(input int k, input int i); return out_bytes[out_off[k] + i]; endfunction
  int trunc_to = 0;   // when nonzero, packets longer than this are expected TRUNCATED to it
  function automatic bit check_pkt(input int k, input bit flowB, input [15:0] tag, input int n);
    bit ok = 1;
    if (trunc_to > 0 && n > trunc_to) n = trunc_to;
    if (out_len[k] != n) begin $display("      pkt tag %0d: size %0d != %0d", tag, out_len[k], n); ok = 0; end
    if ({ob(k,0),ob(k,1),ob(k,2),ob(k,3),ob(k,4),ob(k,5)} !== (flowB ? 48'hBBBB00000006 : 48'hAAAA00000004)) ok = 0;
    if ({ob(k,6),ob(k,7),ob(k,8),ob(k,9),ob(k,10),ob(k,11)} !== (flowB ? 48'h0000DEAD0005 : 48'h0000DEAD0003)) ok = 0;
    if ({ob(k,30),ob(k,31),ob(k,32),ob(k,33)} !== (flowB ? 32'h0A000002 : 32'h0A000001)) ok = 0;
    if (ob(k,22) !== 8'd63) ok = 0;
    if ({ob(k,18),ob(k,19)} !== tag) begin $display("      ORDER: expected tag %0d, got %0d", tag, {ob(k,18),ob(k,19)}); ok = 0; end
    return ok;
  endfunction

  // ── Run one stream of N packets, check all, report the numbers ───────────
  int bad, span, beats, guard;
  bit rand_ready_en = 0;
  bit out_hold = 0;
  int out_release_cyc = 0;
  always @(negedge clk) begin
    if (rand_ready_en) m_axis_tready = ($urandom % 4 != 0);
    // T7: hold the output off until a fixed time, then release. The release
    // must NOT wait for the input to finish -- the input cannot finish while
    // the FIFO is full and the output is held (that is the point of the test).
    if (out_hold && cyc >= out_release_cyc) begin m_axis_tready = 1'b1; out_hold = 0; end
  end
  real cyc_per_pkt, stall_pct;
  // sizes: if nonempty, packet k uses sizes[k % sizes.size()] instead of nbytes
  int sizes[$];
  task automatic run_stream(input string name, input int npkts, input int nbytes, input bit rand_ready,
                            input bit in_stall = 0, input int max_wait = 400);
    out_bytes.delete(); out_len.delete(); out_off.delete(); cur.delete(); in_stall_cycles = 0; first_in_cycle = -1; last_out_cycle = -1;
    rand_ready_en = rand_ready; in_stall_en = in_stall;
    // driver runs inline; the output collector is an always block so it
    // keeps running concurrently. No fork/join -- iverilog's join_any +
    // disable fork crashes vvp (JOIN_DETACH assertion).
    for (int k = 0; k < npkts; k++) begin
      build_frame((k % 2) == 1, (sizes.size() > 0) ? sizes[k % sizes.size()] : nbytes, 16'(k+1));
      send_pb_b2b();
    end
    @(negedge clk); s_axis_tvalid = 1'b0; s_axis_tlast = 1'b0; in_stall_en = 0;
    guard = 0;
    while (out_len.size() < npkts && guard < npkts * max_wait) begin @(posedge clk); guard++; end
    repeat (4) @(posedge clk);
    rand_ready_en = 1'b0;
    @(negedge clk); m_axis_tready = 1'b1;
    bad = 0;
    for (int k = 0; k < npkts; k++) begin
      if (k >= out_len.size()) bad++;
      else if (!check_pkt(k, (k % 2) == 1, 16'(k+1), (sizes.size() > 0) ? sizes[k % sizes.size()] : nbytes)) bad++;
    end
    chk($sformatf("%s: all %0d packets out, correct, in order (%0d bad)", name, npkts, bad),
        bad == 0 && out_len.size() == npkts);
    span  = last_out_cycle - first_in_cycle;
    beats = 0;
    for (int k = 0; k < npkts; k++)
      beats += (((sizes.size() > 0) ? sizes[k % sizes.size()] : nbytes) + TB_BEAT_BYTES - 1) / TB_BEAT_BYTES;
    cyc_per_pkt = span; cyc_per_pkt = cyc_per_pkt / npkts;
    stall_pct = in_stall_cycles; stall_pct = 100.0 * stall_pct / (beats + in_stall_cycles);
    $display("    [MEASURE] %s: %0d pkts x %0dB = %0d beats | span %0d cycles | %0.2f cycles/pkt | input stalled %0d cycles (%0.0f%% of beats) | ideal %0d cycles",
             name, npkts, nbytes, beats, span, cyc_per_pkt, in_stall_cycles, stall_pct, beats);
  endtask

  initial begin
    $display("\n== tb_load_balance_xsa_stream: back-to-back throughput + concurrency ==\n");
    do_reset();
    repeat (40) @(posedge clk);
    program_tables();

    $display("== T1: 16 x 64B packets, back-to-back, output always ready ==");
    run_stream("T1 64B", 16, 64, 0);

    $display("\n== T2: 16 x 256B packets, back-to-back ==");
    run_stream("T2 256B", 16, 256, 0);

    $display("\n== T3: 16 x 64B packets, random output stalls (tready ~75%%) ==");
    run_stream("T3 64B+stall", 16, 64, 1);

    $display("\n== T4: 64 x 64B back-to-back -- steady-state rate (latency amortised) ==");
    run_stream("T4 64x64B", 64, 64, 0);

    $display("\n== T5: random INPUT stalls + random output stalls together ==");
    run_stream("T5 in+out stalls", 32, 128, 1, 1);

    $display("\n== T6: mixed sizes 64/256/96/1024 B interleaved (header-only and payload paths back-to-back) ==");
    sizes.delete(); sizes.push_back(64); sizes.push_back(256); sizes.push_back(96); sizes.push_back(1024);
    run_stream("T6 mixed", 24, 0, 0);
    sizes.delete();

    $display("\n== T7: FIFO-full backpressure: 8 x 2048B (64 beats each) with the output HELD OFF ==");
    // 8 x 61 payload beats = 488 > FIFO depth 256: tready MUST drop, nothing may be lost
    @(negedge clk); m_axis_tready = 1'b0; out_hold = 1; out_release_cyc = cyc + 400;   // ~6 packets' worth: FIFO (256) fills first
    run_stream("T7 fifo-full", 8, 2048, 0, 0, 2000);
    chk("T7: input was actually back-pressured (FIFO filled)", in_stall_cycles > 100);

    $display("\n== T8: oversize 9000B packet (> MAX_PKT_BYTES 8192) then a 64B one: truncate cleanly, next intact ==");
    sizes.delete(); sizes.push_back(9000); sizes.push_back(64); sizes.push_back(256); sizes.push_back(64);
    trunc_to = 8192;
    run_stream("T8 oversize", 4, 0, 0, 0, 2000);
    trunc_to = 0; sizes.delete();

    $display("\n================================================================");
    $display("  Results: %0d passed, %0d failed  (total %0d)", pass_cnt, fail_cnt, pass_cnt + fail_cnt);
    $display("================================================================");
    if (fail_cnt == 0) $display("  ALL TESTS PASSED"); else $display("  SOME TESTS FAILED");
    $finish;
  end
endmodule
