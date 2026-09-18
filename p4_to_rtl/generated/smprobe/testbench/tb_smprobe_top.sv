// ============================================================================
// tb_smprobe_top.sv -- END-TO-END parser_error: a real AXI-Stream packet in,
// verify() evaluated in the top's parallel extractor, standard_metadata.
// parser_error delivered to the control, and the control's drop decision
// observed as the ABSENCE of an output packet.
//
// This path did not exist before. verify() was only ever lowered into
// parser_generated's FSM, and no generated top instantiates that FSM -- the
// top extracts fields itself, straight from the packet buffer -- so in the
// synthesized design parser_error was hard-wired to NoError and this app's
//     if (smeta.parser_error != error.NoError) smeta.drop = 1;
// could never fire. Now verify() is lowered into the top's own reachability
// logic (emit_top._gen_valid_signals), and this test drives the whole chain.
//
//   smprobe.p4:  verify(hdr.eth.etype != 0xFFFF, error.BadEtherType);
//
//   T1  etype 0x0800  -> parser_error NoError      -> packet FORWARDED
//   T2  etype 0xFFFF  -> parser_error BadEtherType -> packet DROPPED
//   T3  etype 0x0800  -> forwarded again (the drop did not wedge the shell)
//
// Compile:
//   iverilog -g2012 -o sim tb_smprobe_top.sv ../smprobe_top.sv \
//     ../processing_generated.sv ../smprobe_pkg.sv
//   vvp sim
// ============================================================================
`timescale 1ns/1ps

module tb_smprobe_top;

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
  logic [15:0] out_meta_nbytes;

  smprobe_top dut (
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
    .out_meta_ts(out_meta_ts), .out_meta_nbytes(out_meta_nbytes)
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
  task automatic watch_output(input int cycles);
    out_beats = 0; saw_tlast = 1'b0;
    repeat (cycles) begin
      @(posedge clk); #1;
      if (m_axis_tvalid && m_axis_tready) begin
        out_beats++;
        if (m_axis_tlast) saw_tlast = 1'b1;
      end
    end
  endtask

  initial begin
    $display("\n== tb_smprobe_top: end-to-end parser_error through the AXI shell ==\n");
    do_reset();

    // ---- T1: good etherType -> forwarded ---------------------------------
    $display("== T1: etype 0x0800, verify passes -> packet forwarded ==");
    fork
      send_frame(16'h0800);
      watch_output(80);
    join
    chk("T1: output packet emerged",       out_beats > 0);
    chk("T1: output packet completed",     saw_tlast);
    chk("T1: whole frame came out (2 beats)", out_beats == 2);

    // ---- T2: bad etherType -> verify fails -> dropped ---------------------
    $display("\n== T2: etype 0xFFFF, verify FAILS -> parser_error=BadEtherType -> dropped ==");
    fork
      send_frame(16'hFFFF);
      watch_output(80);
    join
    chk("T2: NO output packet (dropped on parser_error)", out_beats == 0);

    // ---- T3: shell recovers -----------------------------------------------
    $display("\n== T3: next good packet is forwarded (drop did not wedge the shell) ==");
    fork
      send_frame(16'h0800);
      watch_output(80);
    join
    chk("T3: output packet emerged again",  out_beats == 2 && saw_tlast);

    // ---- T4: a DROPPED packet that has payload beats beyond the header region --
    // 224 B = 7 beats: 3 header rows + 4 payload beats in the FIFO. Those four
    // must be discarded, or they would come out in front of the next packet.
    $display("\n== T4: 224B packet dropped -> its FIFO payload must be discarded ==");
    fork
      send_frame(16'hFFFF, 224);
      watch_output(120);
    join
    chk("T4: NO output for the dropped 224B packet", out_beats == 0);

    // ---- T5: the next good packet is intact -- no leftover beats -------------
    $display("\n== T5: following 224B good packet comes out whole and first ==");
    fork
      send_frame(16'h0800, 224);
      watch_output(120);
    join
    chk("T5: exactly 7 beats, ending in tlast", out_beats == 7 && saw_tlast);

    $display("\n================================================================");
    $display("  Results: %0d passed, %0d failed  (total %0d)",
             pass_cnt, fail_cnt, pass_cnt + fail_cnt);
    $display("================================================================");
    if (fail_cnt == 0) $display("  ALL TESTS PASSED");
    else                $display("  SOME TESTS FAILED");
    $finish;
  end

endmodule
