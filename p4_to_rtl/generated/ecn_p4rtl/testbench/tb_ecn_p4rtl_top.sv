// ============================================================================
// tb_ecn_p4rtl_top.sv -- ECN marking driven by REAL queue depth.
//
// ecn_p4rtl.p4 is the app the traffic manager was built for: it marks
// congestion in egress from standard_metadata.enq_qdepth, which did not exist
// until the shell had queues (docs/traffic_manager_plan.md step 4).
// Congestion is created by holding m_axis_tready low so packets pile into the
// output queue, exactly as a slow output port would.
// ============================================================================
`timescale 1ns/1ps

module tb_ecn_p4rtl_top;

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

  logic  [8:0] out_std_meta_egress_port;

  ecn_p4rtl_top dut (
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

  // ipv4_lpm (lpm on ipv4.dstAddr): 0 idx 1 action 2 key 3 pfx_len
  //   4 p_dstAddr[31:0] 5 p_dstAddr[47:32] 6 p_port 7 commit
  localparam int ACT_FWD = 1;
  task automatic prog_lpm(input int idx, input [31:0] dst, input int pfx,
                          input [47:0] dmac, input [8:0] port);
    axil_write(0, idx); axil_write(1, ACT_FWD); axil_write(2, dst);
    axil_write(3, pfx); axil_write(4, dmac[31:0]); axil_write(5, dmac[47:32]);
    axil_write(6, port); axil_write(7, 1);
    repeat (4) @(posedge clk);
  endtask

  // One IPv4 frame with a chosen ECN codepoint and destination address.
  task automatic send_ip(input [1:0] ecn_bits, input [31:0] dst, input int nbytes = 64);
    logic [TB_AXI_DATA_W-1:0] beat;
    logic [TB_BEAT_BYTES-1:0] keep;
    byte pkt[$];
    int nbeats;
    pkt.delete();
    for (int i = 0; i < nbytes; i++) pkt.push_back(8'(i));
    pkt[0]=8'h00; pkt[1]=8'h11; pkt[2]=8'h22; pkt[3]=8'h33; pkt[4]=8'h44; pkt[5]=8'h55;
    pkt[6]=8'h66; pkt[7]=8'h77; pkt[8]=8'h88; pkt[9]=8'h99; pkt[10]=8'haa; pkt[11]=8'hbb;
    pkt[12] = 8'h08; pkt[13] = 8'h00;              // etherType IPv4
    pkt[14] = 8'h45;                                // version 4, ihl 5
    pkt[15] = {6'd0, ecn_bits};                     // diffserv[5:0], ecn[1:0]
    pkt[22] = 8'd64;                                // ttl
    pkt[23] = 8'd6;                                 // protocol
    pkt[30] = dst[31:24]; pkt[31] = dst[23:16];     // ipv4.dstAddr
    pkt[32] = dst[15:8];  pkt[33] = dst[7:0];
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
  logic  [8:0] o_eport;
  task automatic watch_output(input int cycles);
    out_beats = 0; saw_tlast = 1'b0;
    repeat (cycles) begin
      @(posedge clk); #1;
      if (m_axis_tvalid && m_axis_tready) begin
        if (out_beats == 0) begin
          o_eport = out_std_meta_egress_port;
        end
        out_beats++;
        if (m_axis_tlast) saw_tlast = 1'b1;
      end
    end
  endtask

  // Collector: record every output packet's ECN codepoint, in order.
  int          got_n;
  logic [1:0]  got_ecn [$];
  logic        collecting = 0;
  logic        cur_seen;
  logic [1:0]  cur_ecn;
  always @(posedge clk) begin
    #1;
    if (collecting && m_axis_tvalid && m_axis_tready) begin
      if (!cur_seen) begin cur_ecn = m_axis_tdata[15*8 +: 2]; cur_seen = 1'b1; end
      if (m_axis_tlast) begin got_ecn.push_back(cur_ecn); got_n++; cur_seen = 1'b0; end
    end
  end

  int n_marked, n_ok;

  initial begin
    $display("\n== tb_ecn_p4rtl_top: ECN marking from real queue depth ==\n");
    do_reset();
    prog_lpm(0, 32'h0A000001, 8, 48'h0000BB000001, 9'd1);

    $display("== T1: an uncongested ECT(0) packet is not marked ==");
    got_n = 0; got_ecn.delete(); cur_seen = 0; collecting = 1;
    send_ip(2'd2, 32'h0A000001);
    repeat (250) @(posedge clk);
    collecting = 0;
    chk("T1: packet emerged",               got_n == 1);
    chk("T1: ECN still ECT(0), not marked",  got_n == 1 && got_ecn[0] === 2'd2);

    $display("\n== T2: packets queued behind another are marked CE ==");
    got_n = 0; got_ecn.delete(); cur_seen = 0;
    m_axis_tready = 1'b0;
    collecting = 1;
    send_ip(2'd2, 32'h0A000001);
    send_ip(2'd2, 32'h0A000001);
    send_ip(2'd1, 32'h0A000001);
    send_ip(2'd2, 32'h0A000001);
    repeat (40) @(posedge clk);
    m_axis_tready = 1'b1;
    repeat (400) @(posedge clk);
    collecting = 0;
    chk("T2: all 4 packets emerged", got_n == 4);
    n_marked = 0;
    foreach (got_ecn[k]) if (got_ecn[k] === 2'd3) n_marked++;
    $display("    [INFO] ECN codepoints out: %0d %0d %0d %0d (3 = CE)",
             got_ecn[0], got_ecn[1], got_ecn[2], got_ecn[3]);
    chk("T2: at least one packet was marked CE", n_marked >= 1);
    chk("T2: the FIRST packet is unmarked -- it found an empty queue",
        got_ecn[0] === 2'd2);

    $display("\n== T3: non-ECT traffic is never marked, however congested ==");
    got_n = 0; got_ecn.delete(); cur_seen = 0;
    m_axis_tready = 1'b0;
    collecting = 1;
    send_ip(2'd0, 32'h0A000001);
    send_ip(2'd0, 32'h0A000001);
    send_ip(2'd0, 32'h0A000001);
    repeat (40) @(posedge clk);
    m_axis_tready = 1'b1;
    repeat (400) @(posedge clk);
    collecting = 0;
    chk("T3: all 3 packets emerged", got_n == 3);
    n_ok = 1;
    foreach (got_ecn[k]) if (got_ecn[k] !== 2'd0) n_ok = 0;
    chk("T3: none of them was marked", n_ok == 1);

    $display("\n== T4: once congestion clears, packets are unmarked again ==");
    got_n = 0; got_ecn.delete(); cur_seen = 0; collecting = 1;
    send_ip(2'd2, 32'h0A000001);
    repeat (250) @(posedge clk);
    send_ip(2'd2, 32'h0A000001);
    repeat (250) @(posedge clk);
    collecting = 0;
    chk("T4: both packets emerged", got_n == 2);
    chk("T4: neither is marked -- the queue was empty each time",
        got_n == 2 && got_ecn[0] === 2'd2 && got_ecn[1] === 2'd2);

    $display("\n================================================================");
    $display("  Results: %0d passed, %0d failed  (total %0d)", pass_cnt, fail_cnt, pass_cnt+fail_cnt);
    $display("================================================================");
    if (fail_cnt == 0) $display("  ALL TESTS PASSED");
    else                $display("  SOME TESTS FAILED");
    $finish;
  end

endmodule
