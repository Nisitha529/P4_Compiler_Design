// ============================================================================
// tb_mdprobe_top.sv -- the two p4rtl.p4 externs that used to be declared and
// not implemented: Meter<S> and Digest<T>. See p4src/apps/mdprobe.p4.
//
//   M1  a GREEN packet is forwarded and reports colour 0
//   M2  draining the bucket turns the colour RED and the packet is dropped
//   M3  buckets are PER INDEX: a different etherType is still GREEN while the
//       first bucket is empty
//   M4  the bucket REFILLS over time -- after waiting, the drained index is
//       GREEN again (this is what makes it a rate limiter and not a counter)
//   D1  pack() pushes one entry per packet; the FIFO occupancy tracks it
//   D2  the entry's data is the source MAC that was packed
//   D3  pop advances by exactly one entry
//   D4  pack() never changes the packet (a digest is a notification)
//
// Register map (from mdprobe_top.sv's decoder):
//   fwd        0 idx  1 action  2 key_dst_w0  3 key_dst_w1  4 p_port  5 commit
//   rate_limit 64 rate_shift   65 burst
//   seen_src   128 pop(pulse)  129 status[overflow|occupancy]  130/131 data
// ============================================================================
`timescale 1ns/1ps

module tb_mdprobe_top;

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

  logic  [7:0] out_meta_colour;
  logic [15:0] out_meta_midx;

  mdprobe_top dut (
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
    .out_meta_colour(out_meta_colour), .out_meta_midx(out_meta_midx)
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

  // 64-byte frame; dst MAC fixed, src MAC and etherType chosen by the caller.
  task automatic send_frame(input [47:0] src, input [15:0] etype);
    logic [TB_AXI_DATA_W-1:0] beat;
    logic [TB_BEAT_BYTES-1:0] keep;
    byte pkt[$];
    int nbeats, nbytes;
    nbytes = 64;
    pkt.delete();
    for (int i = 0; i < nbytes; i++) pkt.push_back(8'(i));
    pkt[0]=8'hAA; pkt[1]=8'hBB; pkt[2]=8'hCC; pkt[3]=8'hDD; pkt[4]=8'hEE; pkt[5]=8'hFF;
    for (int i = 0; i < 6; i++) pkt[6+i] = src[47-8*i -: 8];
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

  int out_beats; logic saw_tlast; logic [7:0] o_colour;
  logic [TB_AXI_DATA_W-1:0] first_beat;
  task automatic watch_output(input int cycles);
    out_beats = 0; saw_tlast = 1'b0; first_beat = '0;
    repeat (cycles) begin
      @(posedge clk); #1;
      if (m_axis_tvalid && m_axis_tready) begin
        if (out_beats == 0) first_beat = m_axis_tdata;   // tdata is stale once
        out_beats++;                                      // the burst has ended
        o_colour = out_meta_colour;
        if (m_axis_tlast) saw_tlast = 1'b1;
      end
    end
  endtask

  task automatic one_packet(input [47:0] src, input [15:0] etype, input int cycles);
    fork send_frame(src, etype); watch_output(cycles); join
  endtask

  logic [31:0] rd;
  int occ;

  initial begin
    $display("\n================================================================");
    $display("  mdprobe -- Meter and Digest");
    $display("================================================================");
    do_reset();

    // fwd: forward everything with this dst MAC to port 5
    axil_write(0, 0); axil_write(1, 1);
    axil_write(2, 32'hCCDDEEFF); axil_write(3, 16'hAABB);
    axil_write(4, 5); axil_write(5, 1);
    repeat (4) @(posedge clk);

    // ── Meter ────────────────────────────────────────────────────────────────
    // burst = 2 tokens, refill one token per 2^20 cycles: effectively no refill
    // on this timescale, so the bucket is a 2-packet allowance.
    $display("\n== Meter ==");
    axil_write(64, 20); axil_write(65, 2);
    repeat (4) @(posedge clk);

    one_packet(48'h001122334455, 16'h0001, 200);
    chk("M1: first packet forwarded", out_beats > 0 && saw_tlast);
    chk("M1: colour is GREEN (0)",    o_colour == 8'd0);

    one_packet(48'h001122334455, 16'h0001, 200);   // 2nd token
    one_packet(48'h001122334455, 16'h0001, 200);   // bucket now empty
    chk("M2: bucket drained -> dropped", out_beats == 0);

    one_packet(48'h001122334455, 16'h0002, 200);   // a DIFFERENT bucket
    chk("M3: a different index is still GREEN", out_beats > 0 && saw_tlast);
    chk("M3: and reports colour 0",             o_colour == 8'd0);

    // M4: the debit decays, so after enough cycles the drained index passes
    // again. shift=4 makes one unit decay every 16 cycles, which is reachable
    // inside a testbench; the earlier tests used shift=20 to freeze it.
    axil_write(64, 4);
    repeat (4) @(posedge clk);
    repeat (200) @(posedge clk);          // plenty of decay for a debit of 2
    one_packet(48'h001122334455, 16'h0001, 200);
    chk("M4: the drained index is GREEN again after decay",
        out_beats > 0 && saw_tlast && o_colour == 8'd0);

    // ── Digest ───────────────────────────────────────────────────────────────
    $display("\n== Digest ==");
    axil_read(129, rd);
    occ = rd[4:0];
    chk("D1: entries were pushed (one per packet so far)", occ > 0);
    chk("D1: nothing overflowed",                          rd[31:16] == 16'd0);

    axil_read(130, rd);
    chk("D2: data word 0 = low 32 bits of the first src MAC", rd == 32'h22334455);
    axil_read(131, rd);
    chk("D2: data word 1 = high 16 bits",                     rd[15:0] == 16'h0011);

    axil_read(129, rd); occ = rd[4:0];
    axil_write(128, 1);                 // pop one
    repeat (3) @(posedge clk);
    axil_read(129, rd);
    chk("D3: pop removed exactly one entry", rd[4:0] == occ - 1);

    // D4: the packet itself is untouched by pack(). The frame we sent had
    // dst MAC AA:BB:CC:DD:EE:FF; the deparser emits ethernet unchanged.
    one_packet(48'h665544332211, 16'h0002, 200);
    chk("D4: pack() did not stop the packet", out_beats > 0 && saw_tlast);
    chk("D4: eth.dst still AA:BB:CC:DD:EE:FF",
        first_beat[7:0]   == 8'hAA && first_beat[15:8]  == 8'hBB &&
        first_beat[23:16] == 8'hCC && first_beat[31:24] == 8'hDD);

    $display("\n================================================================");
    $display("  Results: %0d passed, %0d failed  (total %0d)", pass_cnt, fail_cnt, pass_cnt+fail_cnt);
    $display("================================================================");
    if (fail_cnt == 0) $display("  ALL TESTS PASSED");
    else                $display("  SOME TESTS FAILED");
    $finish;
  end

  initial begin #400000; $display("[TIMEOUT]"); $finish; end

endmodule
