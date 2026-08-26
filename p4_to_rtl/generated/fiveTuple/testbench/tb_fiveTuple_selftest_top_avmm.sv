// ============================================================================
// tb_fiveTuple_selftest_top_avmm.sv -- correctness check for
// rtl/common/avmm_axil_lite_bridge.sv, the Avalon-MM-to-AXI4-Lite bridge
// built for DE2-115 JTAG bring-up (Intel's JTAG to Avalon Master Bridge IP
// sits upstream of this bridge on real hardware, driven interactively from
// Quartus System Console). NOT a replacement for
// tb_fiveTuple_selftest_top.sv's own suite, which already proves the
// st_axil_* AXI4-Lite decoder directly -- this isolates exactly the new
// code path: does the bridge correctly translate an Avalon-MM transaction
// into that same, already-proven AXI4-Lite sequence? Reuses that suite's
// exact register-map constants and known-good 42-byte packet (not new test
// vectors), so a pass here is unambiguous evidence about the bridge, not
// about the decoder underneath it.
//
// Compile:
//   iverilog -g2012 -o sim tb_fiveTuple_selftest_top_avmm.sv \
//     ../../../rtl/common/avmm_axil_lite_bridge.sv \
//     ../fiveTuple_selftest_top.sv ../fiveTuple_top.sv \
//     ../processing_generated.sv ../FiveTuple_table.sv
//   vvp sim
// ============================================================================
`timescale 1ns/1ps

module tb_fiveTuple_selftest_top_avmm;

  localparam CLK_T = 10;
  logic clk = 0;
  always #(CLK_T/2) clk = ~clk;
  logic rst_n;

  // Register map -- identical to tb_fiveTuple_selftest_top.sv (see
  // compiler/emit_selftest.py's module docstring).
  localparam int GEN_PKT_LEN       = 0;
  localparam int GEN_PKT_COUNT     = 1;
  localparam int GEN_VARY_OFFSET   = 2;
  localparam int GEN_VARY_ENABLE   = 3;
  localparam int GEN_IPG           = 4;
  localparam int GEN_START         = 5;
  localparam int GEN_STATUS        = 6;
  localparam int GEN_SENT_COUNT    = 7;
  localparam int CAP_START         = 8;
  localparam int CAP_STATUS        = 9;
  localparam int CAP_BYTE_COUNT    = 10;
  localparam int MAX_PKT_BYTES_REG = 11;
  localparam int TMPL_BASE_WORD    = 16;
  localparam int CAP_BASE_WORD     = 16 + 8192/4;  // 2064, default 256-bit width

  // ── Table-CP AXI4-Lite (unused -- tie idle, same as tb_fiveTuple_selftest_top.sv) ──
  logic [15:0] s_axil_awaddr = 0;
  logic        s_axil_awvalid = 0;
  logic        s_axil_awready;
  logic [31:0] s_axil_wdata = 0;
  logic [3:0]  s_axil_wstrb = 0;
  logic        s_axil_wvalid = 0;
  logic        s_axil_wready;
  logic [1:0]  s_axil_bresp;
  logic        s_axil_bvalid;
  logic        s_axil_bready = 1'b1;
  logic [15:0] s_axil_araddr = 0;
  logic        s_axil_arvalid = 0;
  logic        s_axil_arready;
  logic [31:0] s_axil_rdata;
  logic [1:0]  s_axil_rresp;
  logic        s_axil_rvalid;
  logic        s_axil_rready = 1'b1;

  // ── Self-test AXI4-Lite -- now driven by the bridge, not directly ──────────
  logic [15:0] st_axil_awaddr;
  logic        st_axil_awvalid;
  logic        st_axil_awready;
  logic [31:0] st_axil_wdata;
  logic [3:0]  st_axil_wstrb;
  logic        st_axil_wvalid;
  logic        st_axil_wready;
  logic [1:0]  st_axil_bresp;
  logic        st_axil_bvalid;
  logic        st_axil_bready;
  logic [15:0] st_axil_araddr;
  logic        st_axil_arvalid;
  logic        st_axil_arready;
  logic [31:0] st_axil_rdata;
  logic [1:0]  st_axil_rresp;
  logic        st_axil_rvalid;
  logic        st_axil_rready;

  // ── Avalon-MM (the "JTAG to Avalon Master Bridge" side, mocked here) ───────
  logic [15:0] avs_address = 0;
  logic        avs_read = 0;
  logic        avs_write = 0;
  logic [31:0] avs_writedata = 0;
  logic [3:0]  avs_byteenable = 4'hF;
  logic [31:0] avs_readdata;
  logic        avs_waitrequest;
  logic        avs_readdatavalid;

  fiveTuple_selftest_top dut (
    .clk(clk), .rst_n(rst_n),
    .s_axil_awaddr(s_axil_awaddr), .s_axil_awvalid(s_axil_awvalid), .s_axil_awready(s_axil_awready),
    .s_axil_wdata(s_axil_wdata), .s_axil_wstrb(s_axil_wstrb), .s_axil_wvalid(s_axil_wvalid), .s_axil_wready(s_axil_wready),
    .s_axil_bresp(s_axil_bresp), .s_axil_bvalid(s_axil_bvalid), .s_axil_bready(s_axil_bready),
    .s_axil_araddr(s_axil_araddr), .s_axil_arvalid(s_axil_arvalid), .s_axil_arready(s_axil_arready),
    .s_axil_rdata(s_axil_rdata), .s_axil_rresp(s_axil_rresp), .s_axil_rvalid(s_axil_rvalid), .s_axil_rready(s_axil_rready),
    .st_axil_awaddr(st_axil_awaddr), .st_axil_awvalid(st_axil_awvalid), .st_axil_awready(st_axil_awready),
    .st_axil_wdata(st_axil_wdata), .st_axil_wstrb(st_axil_wstrb), .st_axil_wvalid(st_axil_wvalid), .st_axil_wready(st_axil_wready),
    .st_axil_bresp(st_axil_bresp), .st_axil_bvalid(st_axil_bvalid), .st_axil_bready(st_axil_bready),
    .st_axil_araddr(st_axil_araddr), .st_axil_arvalid(st_axil_arvalid), .st_axil_arready(st_axil_arready),
    .st_axil_rdata(st_axil_rdata), .st_axil_rresp(st_axil_rresp), .st_axil_rvalid(st_axil_rvalid), .st_axil_rready(st_axil_rready)
  );

  avmm_axil_lite_bridge #(.ADDR_W(16)) bridge (
    .clk(clk), .rst_n(rst_n),
    .avs_address(avs_address), .avs_read(avs_read), .avs_write(avs_write),
    .avs_writedata(avs_writedata), .avs_byteenable(avs_byteenable),
    .avs_readdata(avs_readdata), .avs_waitrequest(avs_waitrequest),
    .avs_readdatavalid(avs_readdatavalid),
    .m_axil_awaddr(st_axil_awaddr), .m_axil_awvalid(st_axil_awvalid), .m_axil_awready(st_axil_awready),
    .m_axil_wdata(st_axil_wdata), .m_axil_wstrb(st_axil_wstrb), .m_axil_wvalid(st_axil_wvalid), .m_axil_wready(st_axil_wready),
    .m_axil_bresp(st_axil_bresp), .m_axil_bvalid(st_axil_bvalid), .m_axil_bready(st_axil_bready),
    .m_axil_araddr(st_axil_araddr), .m_axil_arvalid(st_axil_arvalid), .m_axil_arready(st_axil_arready),
    .m_axil_rdata(st_axil_rdata), .m_axil_rresp(st_axil_rresp), .m_axil_rvalid(st_axil_rvalid), .m_axil_rready(st_axil_rready)
  );

  int pass_cnt = 0, fail_cnt = 0;
  task automatic chk(input string name, input logic cond);
    if (cond) begin $display("    [PASS] %s", name); pass_cnt++; end
    else      begin $display("    [FAIL] %s", name); fail_cnt++; end
  endtask

  task automatic do_reset;
    rst_n = 0;
    avs_read = 0; avs_write = 0;
    repeat(5) @(posedge clk); @(negedge clk);
    rst_n = 1; @(posedge clk); #1;
  endtask

  // ── Mock Avalon-MM master tasks, modeled on how JTAG-to-Avalon-Master's
  // Tcl master_write_32/master_read_32 behave.
  //
  // avs_waitrequest is purely `(avst != AV_IDLE)` in the bridge -- reading
  // it as 0 the SAME cycle a request first asserts (while avst is still
  // IDLE, before any clock edge has processed it) correctly means "accepted
  // immediately, zero wait states" per the real Avalon-MM contract, not "not
  // yet started." Since this testbench always waits for one full
  // avmm_write/avmm_read to fully complete before issuing the next (no
  // pipelining), the bus is *always* idle when a new command begins, so
  // every command is accepted in exactly one cycle: assert the request for
  // one clock, deassert, then separately poll avs_waitrequest back to 0 (for
  // writes) or avs_readdatavalid (for reads) to know the underlying
  // multi-cycle AXI4-Lite transaction has fully finished before the next
  // call. Sampling avs_waitrequest/avs_readdatavalid with #1 INSIDE the
  // poll loop (not once after it exits) avoids the same testbench
  // blocking-vs-NBA sampling hazard this project already hit once this
  // session (tb_fiveTuple_top.sv's axil_read) -- these are DUT-driven
  // signals updated via nonblocking assignment, so checking them
  // immediately after @(posedge clk) with no delay would race that update.
  task automatic avmm_write(input int word_addr, input logic [31:0] data);
    @(negedge clk);
    avs_address    = word_addr * 4;
    avs_writedata  = data;
    avs_byteenable = 4'hF;
    avs_write      = 1'b1;
    @(posedge clk); #1;   // accept edge (bus was idle -- zero wait states)
    @(negedge clk);
    avs_write = 1'b0;
    while (avs_waitrequest !== 1'b0) begin
      @(posedge clk);
      #1;
    end
  endtask

  task automatic avmm_read(input int word_addr, output logic [31:0] data);
    @(negedge clk);
    avs_address = word_addr * 4;
    avs_read    = 1'b1;
    @(posedge clk); #1;   // accept edge (bus was idle -- zero wait states)
    @(negedge clk);
    avs_read = 1'b0;
    while (!avs_readdatavalid) begin
      @(posedge clk);
      #1;
    end
    data = avs_readdata;
  endtask

  // ── T2's known-good 42-byte packet, byte-for-byte copy from
  // tb_fiveTuple_selftest_top.sv (reused, not re-derived).
  localparam int PKT_LEN = 42;
  logic [31:0] pkt_words[0:10];
  task automatic build_pkt_words(input logic [7:0] sport_lo);
    pkt_words[0]  = 32'hAABBCCDD;
    pkt_words[1]  = 32'hEEFF1122;
    pkt_words[2]  = 32'h33445566;
    pkt_words[3]  = 32'h08004500;
    pkt_words[4]  = 32'h00001234;
    pkt_words[5]  = {8'h00, 8'h00, 8'd64, 8'd17};
    pkt_words[6]  = {16'h0000, 8'hC0, 8'hA8};
    pkt_words[7]  = {8'h00, 8'h03, 8'hC0, 8'hA8};
    pkt_words[8]  = {8'h00, 8'h04, 8'h0B, sport_lo};
    pkt_words[9]  = {8'h0F, 8'hA0, 16'h0008};
    pkt_words[10] = 32'h00000000;
  endtask

  task automatic write_template(input logic [7:0] sport_lo);
    build_pkt_words(sport_lo);
    for (int i = 0; i < 11; i++)
      avmm_write(TMPL_BASE_WORD + i, pkt_words[i]);
  endtask

  task automatic gen_configure(input int pkt_len, input int pkt_count,
                                input int vary_offset, input bit vary_enable,
                                input int ipg);
    avmm_write(GEN_PKT_LEN, pkt_len);
    avmm_write(GEN_PKT_COUNT, pkt_count);
    avmm_write(GEN_VARY_OFFSET, vary_offset);
    avmm_write(GEN_VARY_ENABLE, {31'd0, vary_enable});
    avmm_write(GEN_IPG, ipg);
  endtask

  task automatic poll_gen_done;
    logic [31:0] status;
    status = 32'd0;
    while (!status[1]) avmm_read(GEN_STATUS, status);
  endtask

  task automatic poll_cap_done;
    logic [31:0] status;
    status = 32'd0;
    while (!status[1]) avmm_read(CAP_STATUS, status);
  endtask

  initial begin
    $display("== tb_fiveTuple_selftest_top_avmm: Avalon-MM bridge regression ==\n");

    // ────────────────────────────────────────────────────────────────────
    $display("══ T1: reset/idle sanity (through the bridge) ═════════════════════");
    do_reset();
    begin
      logic [31:0] v;
      avmm_read(GEN_STATUS, v);       chk("T1: gen_status==0 after reset", v == 32'd0);
      avmm_read(CAP_STATUS, v);       chk("T1: cap_status==0 after reset", v == 32'd0);
      avmm_read(MAX_PKT_BYTES_REG, v);
      chk("T1: max_pkt_bytes capability register == 8192 (default width)", v == 32'd8192);
    end

    // ────────────────────────────────────────────────────────────────────
    $display("\n══ T2: single-packet round-trip / byte-packing proof (through the bridge) ═");
    do_reset();
    write_template(8'hB8);
    gen_configure(PKT_LEN, 1, 0, 1'b0, 0);
    avmm_write(CAP_START, 32'd0);   // arm BEFORE starting -- required (see T4)
    avmm_write(GEN_START, 32'd0);
    poll_gen_done();
    poll_cap_done();
    begin
      logic [31:0] sent, byte_count, rd;
      bit mismatch;
      avmm_read(GEN_SENT_COUNT, sent);
      chk("T2: gen_sent_count==1", sent == 32'd1);
      avmm_read(CAP_BYTE_COUNT, byte_count);
      chk("T2: cap_byte_count==42", byte_count == PKT_LEN);
      mismatch = 1'b0;
      for (int i = 0; i < 11; i++) begin
        avmm_read(CAP_BASE_WORD + i, rd);
        if (rd !== pkt_words[i]) mismatch = 1'b1;
      end
      chk("T2: captured bytes match the template word-for-word", !mismatch);
    end

    // ────────────────────────────────────────────────────────────────────
    $display("\n══ T4 (positive only): capture-armed-before-start ordering (through the bridge) ═");
    do_reset();
    begin
      localparam int BIG_LEN = 4096;
      logic [31:0] byte_count;
      write_template(8'hB8);
      gen_configure(BIG_LEN, 1, 0, 1'b0, 0);
      avmm_write(CAP_START, 32'd0);
      avmm_write(GEN_START, 32'd0);
      poll_gen_done();
      poll_cap_done();
      avmm_read(CAP_BYTE_COUNT, byte_count);
      chk("T4: cap_start before gen_start -> full packet captured",
          byte_count == BIG_LEN);
    end

    // ────────────────────────────────────────────────────────────────────
    $display("");
    $display("════════════════════════════════════════════════════════════════");
    $display("  Results: %0d passed, %0d failed  (total %0d)", pass_cnt, fail_cnt, pass_cnt+fail_cnt);
    $display("════════════════════════════════════════════════════════════════");
    if (fail_cnt == 0) $display("  ALL TESTS PASSED");
    else                $display("  FAILURES DETECTED — see [FAIL] lines above");

    $finish;
  end

endmodule
