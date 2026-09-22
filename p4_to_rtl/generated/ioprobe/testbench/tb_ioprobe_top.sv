// ============================================================================
// tb_ioprobe_top.sv -- the packet-ARRIVAL standard metadata through the AXI
// shell: ingress_port, packet_length and parsed_bytes (see ioprobe.p4).
//
//   T1  ingress_port reaches the pipeline and keys a table
//   T2  packet_length == the real frame size, for four different sizes
//   T3  parsed_bytes == 14 (non-IP) / 34 (IPv4), independent of frame size --
//       the value the shell used to report as "whichever beats had arrived"
//   T4  ingress_port changes DURING a back-to-back burst: each packet must
//       carry the value that was present at ITS start of packet, not the one
//       live at issue (issue is cut-through and runs behind RX)
//   T5  packet_length drives a real decision (drop above 128 B)
//
// Compile:
//   iverilog -g2012 -o sim tb_ioprobe_top.sv ../ioprobe_pkg.sv \
//     $(ls ../*.sv | grep -v _pkg)   &&  vvp sim
// ============================================================================
`timescale 1ns/1ps

module tb_ioprobe_top;

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
  logic  [8:0] out_meta_iport;
  logic [15:0] out_meta_plen, out_meta_pbytes;
  logic  [8:0] out_std_meta_egress_port;

  ioprobe_top dut (
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
    .out_meta_iport(out_meta_iport), .out_meta_plen(out_meta_plen),
    .out_meta_pbytes(out_meta_pbytes),
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
  logic  [8:0] o_iport, o_eport;
  logic [15:0] o_plen, o_pbytes;
  task automatic watch_output(input int cycles);
    out_beats = 0; saw_tlast = 1'b0;
    repeat (cycles) begin
      @(posedge clk); #1;
      if (m_axis_tvalid && m_axis_tready) begin
        if (out_beats == 0) begin
          o_iport = out_meta_iport; o_plen = out_meta_plen;
          o_pbytes = out_meta_pbytes; o_eport = out_std_meta_egress_port;
        end
        out_beats++;
        if (m_axis_tlast) saw_tlast = 1'b1;
      end
    end
  endtask

  // Burst collector: one entry per emerging packet.
  int burst_pkts;
  logic [8:0] burst_iport [$];
  logic burst_watch = 0;
  always @(posedge clk) begin
    #1;
    if (burst_watch && m_axis_tvalid && m_axis_tready && m_axis_tlast) begin
      burst_pkts++;
      burst_iport.push_back(out_meta_iport);
    end
  end

  // Back-to-back 64 B frames, with ingress_port changed between frames so the
  // value live at issue differs from the value at each frame's SOP.
  task automatic send_burst_changing_port(input int nframes);
    logic [TB_AXI_DATA_W-1:0] beat;
    for (int k = 0; k < nframes; k++) begin
      for (int b = 0; b < 2; b++) begin
        beat = '0;
        for (int i = 0; i < TB_BEAT_BYTES; i++) beat[i*8 +: 8] = 8'(b*TB_BEAT_BYTES + i);
        if (b == 0) begin
          beat[0*8 +: 8]=8'h00; beat[1*8 +: 8]=8'h11; beat[2*8 +: 8]=8'h22;
          beat[3*8 +: 8]=8'h33; beat[4*8 +: 8]=8'h44; beat[5*8 +: 8]=8'h55;
          beat[6*8 +: 8]=8'h66; beat[7*8 +: 8]=8'h77; beat[8*8 +: 8]=8'h88;
          beat[9*8 +: 8]=8'h99; beat[10*8 +: 8]=8'haa; beat[11*8 +: 8]=8'hbb;
          beat[12*8 +: 8]=8'hAB; beat[13*8 +: 8]=8'hCD;
        end
        @(negedge clk);
        // Drive the port for THIS frame; it changes on every frame boundary.
        if (b == 0) ingress_port = 9'(k + 1);
        s_axis_tdata = beat; s_axis_tkeep = '1; s_axis_tvalid = 1'b1; s_axis_tlast = (b == 1);
        @(posedge clk);
        while (!s_axis_tready) @(posedge clk);
        #1;
      end
    end
    @(negedge clk);
    s_axis_tvalid = 1'b0; s_axis_tlast = 1'b0;
  endtask

  int n_ok;

  initial begin
    $display("\n== tb_ioprobe_top: ingress_port / packet_length / parsed_bytes ==\n");
    do_reset();

    prog_port_fwd(0, 9'd3, 9'd7);
    prog_port_fwd(1, 9'd4, 9'd8);

    // ---- T1: ingress_port reaches the pipeline and keys a table ----------
    $display("== T1: ingress_port delivered and used as a table key ==");
    ingress_port = 9'd3;
    fork send_frame(64, 0); watch_output(120); join
    chk("T1: packet forwarded",                       out_beats == 2 && saw_tlast);
    chk("T1: meta.iport == the driven ingress_port 3", o_iport === 9'd3);
    chk("T1: port_fwd(3) hit -> egress_port 7",        o_eport === 9'd7);
    ingress_port = 9'd4;
    fork send_frame(64, 0); watch_output(120); join
    chk("T1: a different port is seen too (4)",        o_iport === 9'd4);
    chk("T1: port_fwd(4) hit -> egress_port 8",        o_eport === 9'd8);

    // ---- T2: packet_length is the real frame size ------------------------
    $display("\n== T2: packet_length == frame size, four sizes ==");
    ingress_port = 9'd3;
    fork send_frame(64, 0);  watch_output(160); join
    chk("T2: 64 B frame  -> packet_length 64",   o_plen === 16'd64);
    fork send_frame(65, 0);  watch_output(160); join
    chk("T2: 65 B frame  -> packet_length 65 (partial last beat)", o_plen === 16'd65);
    fork send_frame(96, 0);  watch_output(160); join
    chk("T2: 96 B frame  -> packet_length 96",   o_plen === 16'd96);
    fork send_frame(128, 0); watch_output(200); join
    chk("T2: 128 B frame -> packet_length 128",  o_plen === 16'd128);

    // ---- T3: parsed_bytes is extract()'s byte count ----------------------
    $display("\n== T3: parsed_bytes == extracted header bytes, not bytes received ==");
    fork send_frame(64, 0);  watch_output(160); join
    chk("T3: non-IP 64 B  -> parsed_bytes 14 (eth only)",  o_pbytes === 16'd14);
    fork send_frame(128, 0); watch_output(200); join
    chk("T3: non-IP 128 B -> parsed_bytes STILL 14 (size-independent)", o_pbytes === 16'd14);
    fork send_frame(64, 1);  watch_output(160); join
    chk("T3: IPv4 64 B    -> parsed_bytes 34 (eth + ipv4)", o_pbytes === 16'd34);
    fork send_frame(128, 1); watch_output(200); join
    chk("T3: IPv4 128 B   -> parsed_bytes STILL 34",        o_pbytes === 16'd34);

    // ---- T4: SOP sampling under back-to-back traffic ---------------------
    $display("\n== T4: ingress_port changing mid-burst: each packet keeps ITS SOP value ==");
    burst_pkts = 0; burst_iport.delete();
    burst_watch = 1;
    send_burst_changing_port(8);
    repeat (200) @(posedge clk);
    burst_watch = 0;
    chk("T4: all 8 frames emerged",             burst_pkts == 8);
    n_ok = 0;
    foreach (burst_iport[k]) if (burst_iport[k] === 9'(k + 1)) n_ok++;
    chk("T4: every packet carries the port present at its own SOP", n_ok == 8);

    // ---- T5: packet_length drives a real decision ------------------------
    $display("\n== T5: drop when packet_length > 128 ==");
    ingress_port = 9'd3;
    fork send_frame(128, 0); watch_output(200); join
    chk("T5: 128 B is at the threshold -> forwarded", out_beats > 0 && saw_tlast);
    fork send_frame(160, 0); watch_output(200); join
    chk("T5: 160 B is over it -> dropped",            out_beats == 0);
    fork send_frame(64, 0);  watch_output(160); join
    chk("T5: a short frame after the drop still passes", out_beats == 2 && saw_tlast);

    $display("\n================================================================");
    $display("  Results: %0d passed, %0d failed  (total %0d)", pass_cnt, fail_cnt, pass_cnt+fail_cnt);
    $display("================================================================");
    if (fail_cnt == 0) $display("  ALL TESTS PASSED");
    else                $display("  SOME TESTS FAILED");
    $finish;
  end

endmodule
