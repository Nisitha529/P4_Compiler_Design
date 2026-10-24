// tb_host_regs.sv -- the host path from the Avalon-MM side inwards.
//
// The JTAG master itself cannot be meaningfully simulated (it is a hard IP
// talking to a cable), so this testbench stands in its place and drives
// Avalon-MM exactly as that IP does, through the REAL avmm_axil_lite_bridge
// and the real register block. What is left untested in simulation is only the
// JTAG link itself, which is what the System Console commands in
// de2115_host_top.sv's header are for.
`timescale 1ns/1ps

module tb_host_regs;

  localparam int ADDR_W = 16;

  logic clk = 0;
  always #10 clk = ~clk;
  logic rst_n = 0;

  // Avalon-MM, driven here the way the JTAG bridge drives it
  logic [ADDR_W-1:0] avs_address = '0;
  logic              avs_read = 0, avs_write = 0;
  logic [31:0]       avs_writedata = '0;
  logic [3:0]        avs_byteenable = 4'hF;
  wire  [31:0]       avs_readdata;
  wire               avs_waitrequest, avs_readdatavalid;

  wire [ADDR_W-1:0] aw, ar;
  wire awv, awr, wv, wr, bv, br, arv, arr, rv, rr;
  wire [31:0] wd, rd;
  wire [3:0]  ws;
  wire [1:0]  bresp, rresp;
  wire [17:0] leds;
  wire [31:0] hexval;
  wire        wr_seen, rd_seen;

  avmm_axil_lite_bridge #(.ADDR_W(ADDR_W)) u_bridge (
    .clk(clk), .rst_n(rst_n),
    .avs_address(avs_address), .avs_read(avs_read), .avs_write(avs_write),
    .avs_writedata(avs_writedata), .avs_byteenable(avs_byteenable),
    .avs_readdata(avs_readdata), .avs_waitrequest(avs_waitrequest),
    .avs_readdatavalid(avs_readdatavalid),
    .m_axil_awaddr(aw), .m_axil_awvalid(awv), .m_axil_awready(awr),
    .m_axil_wdata(wd), .m_axil_wstrb(ws), .m_axil_wvalid(wv), .m_axil_wready(wr),
    .m_axil_bresp(bresp), .m_axil_bvalid(bv), .m_axil_bready(br),
    .m_axil_araddr(ar), .m_axil_arvalid(arv), .m_axil_arready(arr),
    .m_axil_rdata(rd), .m_axil_rresp(rresp), .m_axil_rvalid(rv), .m_axil_rready(rr)
  );

  host_regs #(.ADDR_W(ADDR_W)) u_regs (
    .clk(clk), .rst_n(rst_n),
    .s_axil_awaddr(aw), .s_axil_awvalid(awv), .s_axil_awready(awr),
    .s_axil_wdata(wd), .s_axil_wstrb(ws), .s_axil_wvalid(wv), .s_axil_wready(wr),
    .s_axil_bresp(bresp), .s_axil_bvalid(bv), .s_axil_bready(br),
    .s_axil_araddr(ar), .s_axil_arvalid(arv), .s_axil_arready(arr),
    .s_axil_rdata(rd), .s_axil_rresp(rresp), .s_axil_rvalid(rv), .s_axil_rready(rr),
    .leds(leds), .hexval(hexval), .wr_seen(wr_seen), .rd_seen(rd_seen)
  );

  int pass_cnt = 0, fail_cnt = 0;
  task automatic chk(input string name, input logic cond);
    if (cond) begin $display("    [PASS] %s", name); pass_cnt++; end
    else      begin $display("    [FAIL] %s", name); fail_cnt++; end
  endtask

  // One Avalon-MM write: hold until waitrequest drops, the IP's own protocol.
  task automatic av_write(input [ADDR_W-1:0] byte_addr, input [31:0] data);
    @(negedge clk);
    avs_address = byte_addr; avs_writedata = data; avs_write = 1'b1;
    @(posedge clk);
    while (avs_waitrequest) @(posedge clk);
    @(negedge clk); avs_write = 1'b0;
    repeat (2) @(posedge clk);
  endtask

  task automatic av_read(input [ADDR_W-1:0] byte_addr, output [31:0] data);
    int guard;
    @(negedge clk);
    avs_address = byte_addr; avs_read = 1'b1;
    @(posedge clk);
    while (avs_waitrequest) @(posedge clk);
    @(negedge clk); avs_read = 1'b0;
    // readdatavalid may be a cycle or two later; bounded so a broken bridge
    // fails rather than hangs.
    guard = 0;
    while (!avs_readdatavalid && guard < 100) begin
      @(posedge clk); guard = guard + 1;
    end
    data = avs_readdata;
    if (guard >= 100) $display("    [TB] readdatavalid never arrived");
    repeat (2) @(posedge clk);
  endtask

  logic [31:0] v, v2;
  // Sticky captures for the one-cycle activity pulses.
  logic saw_rd = 1'b0, saw_wr = 1'b0;
  always @(posedge clk) begin
    if (rd_seen) saw_rd <= 1'b1;
    if (wr_seen) saw_wr <= 1'b1;
  end

  initial begin
    $display("\n================================================================");
    $display("  tb_host_regs: DE2-115 step 2b (the PC-to-fabric path)");
    $display("================================================================");
    repeat (5) @(posedge clk); rst_n = 1; repeat (5) @(posedge clk);

    $display("\n== the ID register identifies this design ==");
    av_read(16'h0000, v);
    $display("      read 0x0 -> %08h (want de211501)", v);
    chk("ID reads 0xDE211501 through the bridge", v === 32'hDE21_1501);

    $display("\n== a write lands and reads back ==");
    av_write(16'h0004, 32'h1234_5678);
    av_read (16'h0004, v);
    $display("      scratch -> %08h", v);
    chk("scratch returns what was written", v === 32'h1234_5678);
    av_write(16'h0004, 32'hA5A5_5A5A);
    av_read (16'h0004, v);
    chk("...and again with a different value", v === 32'hA5A5_5A5A);

    $display("\n== a write the board can SHOW ==");
    av_write(16'h0008, 32'h0003_FFFF);
    repeat (4) @(posedge clk);
    $display("      LEDR drive = %05h", leds);
    chk("all 18 red LEDs driven by the host", leds === 18'h3FFFF);
    av_write(16'h000C, 32'hCAFE_1234);
    repeat (4) @(posedge clk);
    chk("the 7-segment value came from the host", hexval === 32'hCAFE_1234);

    $display("\n== the design is RUNNING, not just answering ==");
    av_read(16'h0010, v);
    av_read(16'h0010, v2);
    $display("      ticks: %0d then %0d", v, v2);
    chk("two reads of the tick counter differ", v !== v2);

    $display("\n== an unmapped address says so rather than returning 0 ==");
    av_read(16'h00F0, v);
    $display("      unmapped -> %08h", v);
    chk("unmapped reads as 0xDEADBEEF", v === 32'hDEAD_BEEF);

    // These are one-cycle pulses, so they have to be CAUGHT, not sampled --
    // the first version of this check was `chk(..., 1'b1)`, which is not a
    // check at all.
    $display("\n== reads and writes raise the activity pulses ==");
    saw_rd = 1'b0; saw_wr = 1'b0;
    av_read(16'h0000, v);
    chk("a read pulsed rd_seen",  saw_rd === 1'b1);
    chk("...and did not pulse wr_seen", saw_wr === 1'b0);
    saw_rd = 1'b0; saw_wr = 1'b0;
    av_write(16'h0004, 32'h1);
    // The Avalon side finishes before the AXI write does: waitrequest drops
    // when the bridge has taken the transaction, and the slave's B response
    // (and so the pulse) lands a few cycles later. Checking immediately after
    // av_write returns samples too early -- which is what the first version
    // of this check did, and it looked like a missing pulse in the design.
    repeat (8) @(posedge clk);
    chk("a write pulsed wr_seen", saw_wr === 1'b1);

    $display("\n================================================================");
    $display("  Results: %0d passed, %0d failed  (total %0d)", pass_cnt, fail_cnt, pass_cnt+fail_cnt);
    $display("================================================================");
    if (fail_cnt == 0) $display("  ALL TESTS PASSED");
    else                $display("  SOME TESTS FAILED");
    $finish;
  end

  initial begin #500000; $display("[TIMEOUT]"); $finish; end

endmodule
