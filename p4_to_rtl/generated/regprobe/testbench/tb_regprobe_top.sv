// ============================================================================
// tb_regprobe_top.sv -- `register` END-TO-END through the AXI shell.
//
// tb_regprobe.sv drives processing_generated directly. This drives real
// AXI-Stream frames through regprobe_top and observes the register read on
// the out_meta_v1 sideband -- the path that was silently broken for this app
// until the packet_in parameter-name bug was fixed (every header wire in the
// top was tied to '0, so the register was only ever addressed at slot 0).
//
// regprobe.p4:
//     if (hdr.eth.etype == 0x0800)
//         bloom_1.write(hdr.eth.src[31:0], hdr.eth.dst[0:0]);
//     bloom_1.read(meta.v1, hdr.eth.dst[31:0]);
//
// ADDRESS COUPLING (the same trap as tb_regprobe.sv): eth.dst is BOTH the
// read address AND, in bit 0, the write data. So:
//   * to WRITE a 1 into slot S: src = S, and dst must be ODD (dst[0] = 1)
//   * to READ slot S:           dst = S exactly, which forces the write data
//                                to S[0]; point src at slot 0 so that
//                                incidental write lands somewhere harmless
// Each read is a SEPARATE frame after the write has committed, so the default
// asynchronous read (which sees the pre-write value within one packet) is not
// what is being measured here.
//
// Compile:
//   iverilog -g2012 -o sim tb_regprobe_top.sv ../regprobe_top.sv \
//     ../processing_generated.sv ../regprobe_pkg.sv
//   vvp sim
// ============================================================================
`timescale 1ns/1ps

module tb_regprobe_top;

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

  logic  [0:0] out_meta_v1;
  logic [31:0] out_meta_pos;

  regprobe_top dut (
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
    .out_meta_v1(out_meta_v1), .out_meta_pos(out_meta_pos)
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

  task automatic send_frame(input [47:0] dst, input [47:0] src, input [15:0] etype);
    logic [TB_AXI_DATA_W-1:0] beat;
    byte pkt[64];
    for (int i = 0; i < 64; i++) pkt[i] = 8'(i);
    pkt[0]=dst[47:40]; pkt[1]=dst[39:32]; pkt[2]=dst[31:24]; pkt[3]=dst[23:16]; pkt[4]=dst[15:8]; pkt[5]=dst[7:0];
    pkt[6]=src[47:40]; pkt[7]=src[39:32]; pkt[8]=src[31:24]; pkt[9]=src[23:16]; pkt[10]=src[15:8]; pkt[11]=src[7:0];
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
    repeat (4) @(posedge clk); #1;
  endtask

  // WRITE value `v` into slot S. dst is only used for its bit 0 here; point
  // the read at an address we do not care about.
  task automatic wr(input [31:0] S, input bit v);
    fork
      send_frame({16'h0, 32'h7FFE | {31'b0, v}}, {16'h0, S}, 16'h0800);
      wait_output(120);
    join
  endtask
  // READ slot S (dst == S). The incidental write goes to slot 0.
  task automatic rd(input [31:0] S);
    fork
      send_frame({16'h0, S}, 48'h0, 16'h0800);
      wait_output(120);
    join
  endtask

  initial begin
    $display("\n== tb_regprobe_top: register end-to-end through the AXI shell ==\n");
    do_reset();

    $display("== T1: write 1 into slot 0x100, read it back on the sideband ==");
    wr(32'h100, 1'b1);
    rd(32'h100);
    chk("T1: frame emerged",              saw_tlast && out_beats == 2);
    chk("T1: out_meta_v1 == 1",           out_meta_v1 === 1'b1);

    $display("\n== T2: never-written slot reads 0 ==");
    rd(32'h7F0);
    chk("T2: out_meta_v1 == 0",           out_meta_v1 === 1'b0);

    $display("\n== T3: write is gated on etype == 0x0800 ==");
    fork  // non-IPv4 frame targeting slot 0x200 -- must NOT write
      send_frame({16'h0, 32'h7FFF}, {16'h0, 32'h200}, 16'h8100);
      wait_output(120);
    join
    rd(32'h200);
    chk("T3: non-IPv4 frame did not write",  out_meta_v1 === 1'b0);
    wr(32'h200, 1'b1);
    rd(32'h200);
    chk("T3: IPv4 frame did write",           out_meta_v1 === 1'b1);

    $display("\n== T4: write data is dst[0], not a constant -- writing 0 clears ==");
    wr(32'h300, 1'b1);
    rd(32'h300);
    chk("T4: slot 0x300 holds 1",         out_meta_v1 === 1'b1);
    wr(32'h300, 1'b0);
    rd(32'h300);
    chk("T4: slot 0x300 cleared to 0",    out_meta_v1 === 1'b0);

    $display("\n== T5: the header round-trips (register access is transparent) ==");
    chk("T5: last frame emerged intact (2 beats)", saw_tlast && out_beats == 2);

    $display("\n================================================================");
    $display("  Results: %0d passed, %0d failed  (total %0d)",
             pass_cnt, fail_cnt, pass_cnt + fail_cnt);
    $display("================================================================");
    if (fail_cnt == 0) $display("  ALL TESTS PASSED");
    else                $display("  SOME TESTS FAILED");
    $finish;
  end

endmodule
