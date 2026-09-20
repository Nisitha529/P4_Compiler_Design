// ============================================================================
// tb_egprobe_top.sv -- END-TO-END test of the P4RtlPipeline EGRESS stage with
// PHV pass-through, through the AXI shell (docs/egress_stage_plan.md).
//
// egprobe.p4: ingress l2 table on eth.etype decides {egress_port | drop |
// retag(etype:=0x0002, port 2)}; egress copies ingress_timestamp to meta,
// drops etype 0xBEEF, rewrites eth.src per egress_port (port_smac table) and
// counts per port (tx_pkts). Each test pins one boundary contract:
//
//   T1  etype 0x0001 -> port 1, egress src MAC rewrite, sideband port 1
//   T2  etype 0x00F0 -> ingress retags to 0x0002/port 2; egress must see
//                       0x0002 (PHV pass-through) and rewrite with port 2's MAC
//   T3  etype 0xBAD1 -> ingress drop; NO output; egress counter for port 0
//       (0xBAD1, not 0xDEAD: l2 is a 16-way direct-mapped exact table and
//        0xDEAD collides with 0xBEEF under its nibble-XOR hash)
//                       must NOT move (sticky drop gates egress side effects)
//   T4  etype 0xBEEF -> ingress port 1, egress drops; NO output; egress ran,
//                       so tx_pkts[1] DOES move (egress dropped it itself)
//   T5  unknown etype -> no match anywhere; frame passes untouched, port 0
//   T6  back-to-back mixed burst; counters sum exactly (drops excluded)
//   T7  meta.ts (ingress_timestamp read in EGRESS) is per-packet, sampled at
//       issue: two back-to-back packets get distinct, increasing stamps, and
//       a burst never sees a later packet's live counter value
//
// Compile:
//   iverilog -g2012 -o sim tb_egprobe_top.sv ../egprobe_pkg.sv \
//     $(ls ../*.sv | grep -v _pkg)   &&  vvp sim
// ============================================================================
`timescale 1ns/1ps

module tb_egprobe_top;

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


  logic [63:0] c0, c1, c2, c3;
  int n_ok;

  initial begin
    $display("\n== tb_egprobe_top: egress stage with PHV pass-through, through the AXI shell ==\n");
    do_reset();

    // ---- Program both stages' tables over the one AXI4-Lite bus ----------
    prog_l2(0, 16'h0001, ACT_FWD,   9'd1);
    prog_l2(1, 16'h0002, ACT_FWD,   9'd2);
    prog_l2(2, 16'h0003, ACT_FWD,   9'd3);
    prog_l2(3, 16'h00F0, ACT_RETAG, 9'd0);
    prog_l2(4, 16'hBAD1, ACT_DROP,  9'd0);
    prog_l2(5, 16'hBEEF, ACT_FWD,   9'd1);
    prog_port_smac(0, 9'd1, 48'h0000AA000001);
    prog_port_smac(1, 9'd2, 48'h0000AA000002);
    prog_port_smac(2, 9'd3, 48'h0000AA000003);

    // ---- T1: plain forward through both stages ---------------------------
    $display("== T1: etype 0x0001 -> port 1; egress rewrites src MAC ==");
    fork send_frame(16'h0001); watch_output(80); join
    chk("T1: packet forwarded (2 beats)",            out_beats == 2 && saw_tlast);
    chk("T1: sideband egress_port == 1 (ingress std meta)", out_port === 9'd1);
    chk("T1: src MAC rewritten by EGRESS port_smac(1)", beat_smac(out_first_beat) === 48'h0000AA000001);
    chk("T1: etype untouched",                       beat_etype(out_first_beat) === 16'h0001);
    query_tx_pkts(4'd1, c1);
    chk("T1: egress counter tx_pkts[1] == 1",       c1 == 64'd1);

    // ---- T2: PHV pass-through -------------------------------------------
    $display("\n== T2: etype 0x00F0 -> ingress retags to 0x0002/port 2; egress keys on the NEW etype ==");
    fork send_frame(16'h00F0); watch_output(80); join
    chk("T2: packet forwarded",                      out_beats == 2 && saw_tlast);
    chk("T2: etype on the wire is the ingress-rewritten 0x0002", beat_etype(out_first_beat) === 16'h0002);
    chk("T2: sideband egress_port == 2",             out_port === 9'd2);
    chk("T2: src MAC = port_smac(2): egress saw ingress's PHV, not the packet", beat_smac(out_first_beat) === 48'h0000AA000002);
    query_tx_pkts(4'd2, c2);
    chk("T2: tx_pkts[2] == 1",                       c2 == 64'd1);

    // ---- T3: ingress drop is sticky and gates egress side effects --------
    $display("\n== T3: etype 0xBAD1 -> ingress drop; egress must not run ==");
    query_tx_pkts(4'd0, c0);
    fork send_frame(16'hBAD1); watch_output(80); join
    chk("T3: nothing came out",                      out_beats == 0);
    query_tx_pkts(4'd0, c3);
    chk("T3: tx_pkts[0] unchanged -- egress did not count the dropped packet", c3 == c0);

    // ---- T4: egress's own drop ------------------------------------------
    $display("\n== T4: etype 0xBEEF -> ingress port 1, EGRESS drops ==");
    fork send_frame(16'hBEEF); watch_output(80); join
    chk("T4: nothing came out",                      out_beats == 0);
    query_tx_pkts(4'd1, c1);
    chk("T4: tx_pkts[1] == 2 -- egress ran (its own drop, counted after)", c1 == 64'd2);

    // ---- T5: no match anywhere -------------------------------------------
    $display("\n== T5: unknown etype -> passes untouched, port 0 ==");
    fork send_frame(16'h0800); watch_output(80); join
    chk("T5: packet forwarded",                      out_beats == 2 && saw_tlast);
    chk("T5: src MAC untouched (no port_smac entry for port 0)", beat_smac(out_first_beat) === 48'h66778899aabb);
    chk("T5: sideband egress_port == 0",             out_port === 9'd0);
    query_tx_pkts(4'd0, c0);
    chk("T5: tx_pkts[0] counts the unmatched packet (egress ran)", c0 == 64'd1);

    // ---- T6: back-to-back burst, drops interleaved -----------------------
    $display("\n== T6: 12-frame back-to-back burst with ingress and egress drops interleaved ==");
    burst.delete(); burst_port.delete(); burst_ts.delete(); burst_pkts = 0;
    // 3x port1, 3x port2, 2x port3, 2x ingress-drop, 2x egress-drop(port1)
    burst.push_back(16'h0001); burst.push_back(16'hBAD1); burst.push_back(16'h0002);
    burst.push_back(16'hBEEF); burst.push_back(16'h0003); burst.push_back(16'h0001);
    burst.push_back(16'h0002); burst.push_back(16'hBAD1); burst.push_back(16'h0003);
    burst.push_back(16'hBEEF); burst.push_back(16'h0001); burst.push_back(16'h0002);
    burst_watch = 1;
    send_frames_b2b();
    repeat (120) @(posedge clk);
    burst_watch = 0;
    chk("T6: 8 of 12 frames emerged (4 dropped)",    burst_pkts == 8);
    query_tx_pkts(4'd1, c1); query_tx_pkts(4'd2, c2); query_tx_pkts(4'd3, c3); query_tx_pkts(4'd0, c0);
    chk("T6: tx_pkts[1] == 2+3+2 (egress-dropped BEEF frames counted, ingress drops not)", c1 == 64'd7);
    chk("T6: tx_pkts[2] == 1+3",                     c2 == 64'd4);
    chk("T6: tx_pkts[3] == 2",                       c3 == 64'd2);
    chk("T6: tx_pkts[0] still 1 -- ingress drops never reached egress", c0 == 64'd1);
    n_ok = 0;
    foreach (burst_port[k]) begin
      // emerged order: 1,2,3,1,2,3,1,2 (drops removed)
      case (k) 0,3,6: if (burst_port[k] == 9'd1) n_ok++;
               1,4,7: if (burst_port[k] == 9'd2) n_ok++;
               2,5:   if (burst_port[k] == 9'd3) n_ok++;
      endcase
    end
    chk("T6: sideband ports in order for every survivor", n_ok == 8);

    // ---- T7: shell-sourced std meta read in EGRESS is per-packet ---------
    $display("\n== T7: meta.ts = ingress_timestamp read in egress: per-packet, issue-time sample ==");
    n_ok = 0;
    for (int k = 1; k < burst_ts.size(); k++)
      if (burst_ts[k] > burst_ts[k-1] && burst_ts[k] - burst_ts[k-1] < 64'd40) n_ok++;
    chk("T7: burst timestamps strictly increase, packet by packet", n_ok == burst_ts.size() - 1);
    chk("T7: consecutive survivors 2..6 cycles apart (issue cadence, not a shared sample)",
        burst_ts.size() == 8 && (burst_ts[1] - burst_ts[0]) >= 64'd2 && (burst_ts[1] - burst_ts[0]) <= 64'd6);

    $display("\n================================================================");
    $display("  Results: %0d passed, %0d failed  (total %0d)", pass_cnt, fail_cnt, pass_cnt+fail_cnt);
    $display("================================================================");
    if (fail_cnt == 0) $display("  ALL TESTS PASSED");
    else                $display("  SOME TESTS FAILED");
    $finish;
  end

endmodule
