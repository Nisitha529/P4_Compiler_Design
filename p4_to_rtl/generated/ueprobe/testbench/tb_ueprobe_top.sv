// ============================================================================
// tb_ueprobe_top.sv -- UserExtern END-TO-END through the AXI shell.
//
// tb_ueprobe.sv drives processing_generated directly and proves the latency
// staging. It does NOT prove that a real packet's header reaches the extern,
// or that the extern's result reaches the outside world. Both of those go
// through the top, and both were silently broken for this very app until the
// packet_in parameter-name bug was fixed (the top had every header wire tied
// to '0, so my_lookup always saw data_in = 0 and the processing-level test
// could never notice).
//
// Path under test:
//   AXI-Stream frame -> pkt_buf -> w_eth_dst / w_eth_etype extracted
//     -> processing_generated -> my_lookup(3 cycles) / my_classify(1 cycle)
//     -> meta.res / meta.res2 -> out_meta_* sideband latched at packet commit
//
// The generated placeholder bodies are the identity delayed by the declared
// latency, so through the shell the sideband must satisfy, per packet:
//     out_meta_res  == eth.dst[15:0]
//     out_meta_res2 == eth.etype[7:0]
//
// T3 sends several frames back-to-back through the store-and-forward shell
// with a different dst/etype each, checking each frame's sideband against
// ITS OWN header. A stale latch or a mis-staged extern would pair a frame's
// result with a neighbour's header.
//
// Compile:
//   iverilog -g2012 -o sim tb_ueprobe_top.sv ../ueprobe_top.sv \
//     ../processing_generated.sv ../ueprobe_pkg.sv \
//     ../my_lookup_user_extern.sv ../my_classify_user_extern.sv
//   vvp sim
// ============================================================================
`timescale 1ns/1ps

module tb_ueprobe_top;

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

  logic [15:0] out_meta_res;
  logic  [7:0] out_meta_res2;

  ueprobe_top dut (
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
    .out_meta_res(out_meta_res), .out_meta_res2(out_meta_res2)
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

  // One 64-byte frame with the given dst MAC and etherType.
  task automatic send_frame(input [47:0] dst, input [15:0] etype);
    logic [TB_AXI_DATA_W-1:0] beat;
    byte pkt[64];
    for (int i = 0; i < 64; i++) pkt[i] = 8'(i);
    pkt[0]=dst[47:40]; pkt[1]=dst[39:32]; pkt[2]=dst[31:24];
    pkt[3]=dst[23:16]; pkt[4]=dst[15:8];  pkt[5]=dst[7:0];
    pkt[6]=8'h66; pkt[7]=8'h77; pkt[8]=8'h88; pkt[9]=8'h99; pkt[10]=8'haa; pkt[11]=8'hbb;
    pkt[12] = etype[15:8]; pkt[13] = etype[7:0];
    for (int b = 0; b < 2; b++) begin
      beat = '0;
      for (int i = 0; i < TB_BEAT_BYTES; i++) beat[i*8 +: 8] = pkt[b*TB_BEAT_BYTES + i];
      @(negedge clk);
      s_axis_tdata = beat; s_axis_tkeep = '1;
      s_axis_tvalid = 1'b1; s_axis_tlast = (b == 1);
      @(posedge clk);
      while (!s_axis_tready) @(posedge clk);
      #1;
    end
    @(negedge clk);
    s_axis_tvalid = 1'b0; s_axis_tlast = 1'b0;
  endtask

  // Wait for the frame to emerge (bounded), then the sideband is stable.
  int out_beats; logic saw_tlast;
  task automatic wait_output(input int max_cycles);
    out_beats = 0; saw_tlast = 1'b0;
    for (int c = 0; c < max_cycles && !saw_tlast; c++) begin
      @(posedge clk); #1;
      if (m_axis_tvalid && m_axis_tready) begin
        out_beats++;
        if (m_axis_tlast) saw_tlast = 1'b1;
      end
    end
    // let the shell finish its clear-down before the next frame
    repeat (4) @(posedge clk); #1;
  endtask

  // send + wait as one step (store-and-forward: one frame in flight)
  task automatic run_frame(input [47:0] dst, input [15:0] etype);
    fork
      send_frame(dst, etype);
      wait_output(120);
    join
  endtask

  int bad;
  initial begin
    $display("\n== tb_ueprobe_top: UserExtern end-to-end through the AXI shell ==\n");
    do_reset();

    // ---- T1: single frame, both externs ----------------------------------
    $display("== T1: header reaches the externs, results reach the sideband ==");
    run_frame(48'hAABBCCDD1234, 16'h0899);
    chk("T1: frame emerged",                       saw_tlast && out_beats == 2);
    chk("T1: out_meta_res  == eth.dst[15:0]",      out_meta_res  === 16'h1234);
    chk("T1: out_meta_res2 == eth.etype[7:0]",     out_meta_res2 === 8'h99);

    // ---- T2: a different frame, no stale latch ---------------------------
    $display("\n== T2: second frame replaces the sideband, no stale value ==");
    run_frame(48'h0102030405AB, 16'h86DD);
    chk("T2: frame emerged",                       saw_tlast && out_beats == 2);
    chk("T2: out_meta_res  updated",               out_meta_res  === 16'h05AB);
    chk("T2: out_meta_res2 updated",               out_meta_res2 === 8'hDD);

    // ---- T3: sequence, each frame's result pairs with its own header ------
    $display("\n== T3: 12 frames in sequence, each result pairs with its own header ==");
    bad = 0;
    for (int i = 1; i <= 12; i++) begin
      run_frame({32'h00000000 + i, 16'(16'h1000 + i*17)}, 16'(16'h0800 + i));
      if (!(saw_tlast && out_beats == 2)) bad++;
      if (out_meta_res  !== 16'(16'h1000 + i*17)) bad++;
      if (out_meta_res2 !== 8'((16'h0800 + i) & 16'hFF)) bad++;
    end
    chk($sformatf("T3: all 12 frames consistent (%0d mismatches)", bad), bad == 0);

    $display("\n================================================================");
    $display("  Results: %0d passed, %0d failed  (total %0d)",
             pass_cnt, fail_cnt, pass_cnt + fail_cnt);
    $display("================================================================");
    if (fail_cnt == 0) $display("  ALL TESTS PASSED");
    else                $display("  SOME TESTS FAILED");
    $finish;
  end

endmodule
