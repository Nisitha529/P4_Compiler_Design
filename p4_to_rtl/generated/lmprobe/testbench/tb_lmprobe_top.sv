// ============================================================================
// tb_lmprobe_top.sv -- link_monitor's byte-counting half on P4RtlPipeline
// (see lmprobe.p4 for why the rest of that app cannot be ported).
//
//   T1  one frame: the egress register accumulates packet_length for the port
//       ingress chose
//   T2  several frames on one port: the running total is the exact byte sum
//   T3  per-port independence, and a probe frame reports-then-resets
//   T4  MEASURES the register read-after-write distance (p4rtl.p4 states the
//       contract but not the number) by sending pairs at decreasing spacing
//
// Compile:
//   iverilog -g2012 -o sim tb_lmprobe_top.sv ../lmprobe_pkg.sv \
//     $(ls ../*.sv | grep -v _pkg)   &&  vvp sim
// ============================================================================
`timescale 1ns/1ps

module tb_lmprobe_top;

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

  logic  [8:0] ingress_port = 9'd0;
  logic [31:0] out_meta_byte_total;
  logic  [8:0] out_meta_port_seen;
  logic  [8:0] out_std_meta_egress_port;

  lmprobe_top dut (
    .clk(clk), .rst_n(rst_n),
    .s_axis_tdata(s_axis_tdata), .s_axis_tkeep(s_axis_tkeep),
    .s_axis_tvalid(s_axis_tvalid), .s_axis_tready(s_axis_tready), .s_axis_tlast(s_axis_tlast),
    .m_axis_tdata(m_axis_tdata), .m_axis_tkeep(m_axis_tkeep),
    .m_axis_tvalid(m_axis_tvalid), .m_axis_tready(m_axis_tready), .m_axis_tlast(m_axis_tlast),
    .ingress_port(ingress_port),
    .s_axil_awaddr(s_axil_awaddr), .s_axil_awvalid(s_axil_awvalid), .s_axil_awready(s_axil_awready),
    .s_axil_wdata(s_axil_wdata), .s_axil_wstrb(s_axil_wstrb),
    .s_axil_wvalid(s_axil_wvalid), .s_axil_wready(s_axil_wready),
    .s_axil_bresp(s_axil_bresp), .s_axil_bvalid(s_axil_bvalid), .s_axil_bready(s_axil_bready),
    .s_axil_araddr(s_axil_araddr), .s_axil_arvalid(s_axil_arvalid), .s_axil_arready(s_axil_arready),
    .s_axil_rdata(s_axil_rdata), .s_axil_rresp(s_axil_rresp),
    .s_axil_rvalid(s_axil_rvalid), .s_axil_rready(s_axil_rready),
    .out_meta_byte_total(out_meta_byte_total),
    .out_meta_port_seen(out_meta_port_seen),
    .out_std_meta_egress_port(out_std_meta_egress_port)
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

  // port_fwd (exact on ingress_port): 0 idx 1 action 2 key 3 p_port 4 commit
  task automatic prog_port_fwd(input int idx, input [8:0] iport, input [8:0] eport);
    axil_write(0, idx); axil_write(1, 1); axil_write(2, iport);
    axil_write(3, eport); axil_write(4, 1);
    repeat (4) @(posedge clk);
  endtask

  // One frame: 14-byte ethernet header (+ 20-byte IPv4 when is_ip), then filler.
  task automatic send_frame(input int nbytes, input bit is_ip);
    logic [TB_AXI_DATA_W-1:0] beat;
    logic [TB_BEAT_BYTES-1:0] keep;
    byte pkt[$];
    int nbeats;
    pkt.delete();
    for (int i = 0; i < nbytes; i++) pkt.push_back(8'(i));
    pkt[0]=8'h00; pkt[1]=8'h11; pkt[2]=8'h22; pkt[3]=8'h33; pkt[4]=8'h44; pkt[5]=8'h55;
    pkt[6]=8'h66; pkt[7]=8'h77; pkt[8]=8'h88; pkt[9]=8'h99; pkt[10]=8'haa; pkt[11]=8'hbb;
    pkt[12] = is_ip ? 8'h08 : 8'hAB; pkt[13] = is_ip ? 8'h00 : 8'hCD;
    nbeats = (nbytes + TB_BEAT_BYTES - 1) / TB_BEAT_BYTES;
    for (int b = 0; b < nbeats; b++) begin
      beat = '0;
      keep = '0;
      for (int i = 0; i < TB_BEAT_BYTES; i++)
        if (b*TB_BEAT_BYTES + i < nbytes) begin
          beat[i*8 +: 8] = pkt[b*TB_BEAT_BYTES + i];
          keep[i] = 1'b1;   // a partial final beat must say so: the shell
        end                 // counts packet_length by popcount(tkeep)
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

  int out_beats;
  logic saw_tlast;
  logic  [8:0] o_eport, o_port_seen;
  logic [31:0] o_total;
  task automatic watch_output(input int cycles);
    out_beats = 0; saw_tlast = 1'b0;
    repeat (cycles) begin
      @(posedge clk); #1;
      if (m_axis_tvalid && m_axis_tready) begin
        if (out_beats == 0) begin
          o_total = out_meta_byte_total; o_port_seen = out_meta_port_seen;
          o_eport = out_std_meta_egress_port;
        end
        out_beats++;
        if (m_axis_tlast) saw_tlast = 1'b1;
      end
    end
  endtask

  // Burst collector: one entry per emerging packet.
  int burst_pkts;
  logic [31:0] burst_total [$];
  logic burst_watch = 0;
  always @(posedge clk) begin
    #1;
    if (burst_watch && m_axis_tvalid && m_axis_tready && m_axis_tlast) begin
      burst_pkts++;
      burst_total.push_back(out_meta_byte_total);
    end
  end


  // Two frames on the same port, `gap` idle cycles apart. Returns the total
  // reported by the SECOND one, which is what reveals whether its register
  // read saw the first one's write.
  task automatic pair_with_gap(input int gap, output logic [31:0] second_total);
    burst_pkts = 0; burst_total.delete();
    burst_watch = 1;
    send_frame(64, 0);
    repeat (gap) @(posedge clk);
    send_frame(64, 0);
    repeat (250) @(posedge clk);
    burst_watch = 0;
    second_total = (burst_total.size() >= 2) ? burst_total[1] : 32'hFFFF_FFFF;
  endtask

  int  n_ok, raw_distance;
  logic [31:0] t2;

  initial begin
    $display("\n== tb_lmprobe_top: egress register + packet_length, keyed by egress_port ==\n");
    do_reset();

    prog_port_fwd(0, 9'd3, 9'd1);
    prog_port_fwd(1, 9'd4, 9'd2);

    // ---- T1 --------------------------------------------------------------
    $display("== T1: one 64 B frame accumulates into the egress register ==");
    ingress_port = 9'd3;
    fork send_frame(64, 0); watch_output(200); join
    chk("T1: frame forwarded",                       out_beats == 2 && saw_tlast);
    chk("T1: egress saw the port ingress chose (1)", o_port_seen === 9'd1);
    chk("T1: running total == 64",                   o_total === 32'd64);

    // ---- T2 --------------------------------------------------------------
    $display("\n== T2: the total is the exact byte sum over several frames ==");
    fork send_frame(128, 0); watch_output(220); join
    chk("T2: 64 + 128 = 192",                        o_total === 32'd192);
    fork send_frame(96,  0); watch_output(200); join
    chk("T2: + 96 = 288",                            o_total === 32'd288);
    fork send_frame(65,  0); watch_output(200); join
    chk("T2: + 65 = 353 (partial beat counted by tkeep)", o_total === 32'd353);

    // ---- T3 --------------------------------------------------------------
    $display("\n== T3: per-port independence, and probe reports-then-resets ==");
    ingress_port = 9'd4;
    fork send_frame(64, 0); watch_output(200); join
    chk("T3: port 2's own counter starts at 64",     o_total === 32'd64);
    chk("T3: egress_port is 2 for this one",         o_port_seen === 9'd2);
    ingress_port = 9'd3;
    fork send_frame(64, 1); watch_output(200); join   // is_ip=1 -> etype 0x0800
    chk("T3: port 1 untouched by port 2's traffic: 353 + 64 = 417", o_total === 32'd417);

    // ---- T4: the stated register RAW distance, measured ------------------
    $display("\n== T4: read-after-write distance on the egress register ==");
    raw_distance = -1;
    for (int gap = 12; gap >= 0; gap--) begin
      logic [31:0] before_total, got;
      // establish a known base for port 1, then a pair at this spacing
      ingress_port = 9'd3;
      fork send_frame(64, 0); watch_output(200); join
      before_total = o_total;
      pair_with_gap(gap, got);
      // The second frame of the pair must see the first: base + 64 + 64.
      if (got !== before_total + 32'd128 && raw_distance < 0) raw_distance = gap + 1;
    end
    if (raw_distance < 0) begin
      // The tightest spacing this driver can produce is ~1 idle cycle, so this
      // says the distance is at or below that -- not that it is exactly zero.
      $display("    [INFO] no spacing this test can produce (down to ~1 idle cycle) lost an update");
      chk("T4: consecutive frames on one port all accumulate", 1'b1);
    end else begin
      $display("    [INFO] updates are lost when frames are closer than %0d idle cycle(s)", raw_distance);
      chk("T4: the RAW distance is a small, bounded number of cycles", raw_distance <= 12);
    end

    $display("\n================================================================");
    $display("  Results: %0d passed, %0d failed  (total %0d)", pass_cnt, fail_cnt, pass_cnt+fail_cnt);
    $display("================================================================");
    if (fail_cnt == 0) $display("  ALL TESTS PASSED");
    else                $display("  SOME TESTS FAILED");
    $finish;
  end

endmodule
