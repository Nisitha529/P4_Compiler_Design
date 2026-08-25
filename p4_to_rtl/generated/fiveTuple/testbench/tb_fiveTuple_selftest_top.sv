// ============================================================================
// tb_fiveTuple_selftest_top.sv -- correctness check for the opt-in on-chip
// packet generator + capture wrapper (--self-test), which lets the packet
// processor be exercised on real FPGA hardware without a real Ethernet
// MAC/PHY. NOT a replacement for tb_fiveTuple_top.sv's own regression suite
// (which covers the core AXI4-Stream/AXI4-Lite pipeline this wrapper
// instantiates unmodified) -- this isolates exactly the new code path
// emit_selftest.py adds: the template-buffer generator, the capture logic,
// and the new, independent self-test AXI4-Lite bus.
//
// Word offsets and default-width-specific constants below (TMPL_BASE_WORD,
// CAP_BASE_WORD) match emit_selftest.py's register map at the DEFAULT
// --axi-data-width (256 bits, MAX_PKT_BYTES=8192) -- same hardcoding
// precedent tb_fiveTuple_top.sv's own T9 already uses for width-derived
// constants (the committed testbench targets the default build it's
// actually compiled against).
//
// Run against the committed generated/fiveTuple/fiveTuple_selftest_top.sv
// (produced via `python3 main.py fiveTuple --self-test`, no special flags
// needed beyond that).
//
// Compile:
//   iverilog -g2012 -o sim tb_fiveTuple_selftest_top.sv \
//     ../fiveTuple_selftest_top.sv ../fiveTuple_top.sv \
//     ../processing_generated.sv ../FiveTuple_table.sv
//   vvp sim
// ============================================================================
`timescale 1ns/1ps

module tb_fiveTuple_selftest_top;

  localparam CLK_T = 10;
  logic clk = 0;
  always #(CLK_T/2) clk = ~clk;
  logic rst_n;

  // Register map (see compiler/emit_selftest.py's module docstring):
  //   0 gen_pkt_len  1 gen_pkt_count  2 gen_vary_offset  3 gen_vary_enable
  //   4 gen_ipg      5 gen_start(W)   6 gen_status(R)    7 gen_sent_count(R)
  //   8 cap_start(W) 9 cap_status(R)  10 cap_byte_count(R) 11 max_pkt_bytes(R)
  //   16.. tmpl_buf (RW)   TMPL+2048.. cap_buf (R)  -- default 256-bit width
  localparam int GEN_PKT_LEN      = 0;
  localparam int GEN_PKT_COUNT    = 1;
  localparam int GEN_VARY_OFFSET  = 2;
  localparam int GEN_VARY_ENABLE  = 3;
  localparam int GEN_IPG          = 4;
  localparam int GEN_START        = 5;
  localparam int GEN_STATUS       = 6;
  localparam int GEN_SENT_COUNT   = 7;
  localparam int CAP_START        = 8;
  localparam int CAP_STATUS       = 9;
  localparam int CAP_BYTE_COUNT   = 10;
  localparam int MAX_PKT_BYTES_REG = 11;
  localparam int TMPL_BASE_WORD   = 16;
  localparam int CAP_BASE_WORD    = 16 + 8192/4;  // 2064, default 256-bit width

  // ── Table-CP AXI4-Lite (unused by this testbench -- tie idle) ──────────────
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

  // ── Self-test AXI4-Lite ──────────────────────────────────────────────────
  logic [15:0] st_axil_awaddr = 0;
  logic        st_axil_awvalid = 0;
  logic        st_axil_awready;
  logic [31:0] st_axil_wdata = 0;
  logic [3:0]  st_axil_wstrb = 0;
  logic        st_axil_wvalid = 0;
  logic        st_axil_wready;
  logic [1:0]  st_axil_bresp;
  logic        st_axil_bvalid;
  logic        st_axil_bready = 1'b1;
  logic [15:0] st_axil_araddr = 0;
  logic        st_axil_arvalid = 0;
  logic        st_axil_arready;
  logic [31:0] st_axil_rdata;
  logic [1:0]  st_axil_rresp;
  logic        st_axil_rvalid;
  logic        st_axil_rready = 1'b1;

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

  int pass_cnt = 0, fail_cnt = 0;
  task automatic chk(input string name, input logic cond);
    if (cond) begin $display("    [PASS] %s", name); pass_cnt++; end
    else      begin $display("    [FAIL] %s", name); fail_cnt++; end
  endtask

  task automatic do_reset;
    rst_n = 0;
    st_axil_awvalid = 0; st_axil_wvalid = 0; st_axil_arvalid = 0;
    repeat(5) @(posedge clk); @(negedge clk);
    rst_n = 1; @(posedge clk); #1;
  endtask

  // ── AXI4-Lite write (word-addressed) -- same #1-after-edge discipline as
  // tb_fiveTuple_top.sv's axil_write (correct here: st_axil_wready stays
  // asserted for an observable window, no tied-high-rready-style hazard).
  task automatic st_write(input int word_addr, input logic [31:0] data);
    bit aw_done, w_done;
    @(negedge clk);
    st_axil_awaddr  = word_addr * 4;
    st_axil_awvalid = 1'b1;
    st_axil_wdata   = data;
    st_axil_wstrb   = 4'hF;
    st_axil_wvalid  = 1'b1;
    aw_done = 1'b0;
    w_done  = 1'b0;
    while (!aw_done || !w_done) begin
      @(posedge clk);
      #1;
      if (!aw_done && st_axil_awready) aw_done = 1'b1;
      if (!w_done && st_axil_wready)   w_done  = 1'b1;
    end
    @(negedge clk);
    st_axil_awvalid = 1'b0;
    st_axil_wvalid  = 1'b0;
  endtask

  // ── AXI4-Lite read (word-addressed) -- UNDELAYED same-edge sample of
  // rvalid/rdata, matching tb_fiveTuple_top.sv's axil_read and the reason
  // documented there: this read channel's rvalid is a registered output
  // that resolves within a single edge-to-edge window when rready is tied
  // high (as it is here), so a #1-delayed sample would always land one edge
  // too late and permanently miss the pulse.
  task automatic st_read(input int word_addr, output logic [31:0] data);
    bit accepted;
    @(negedge clk);
    st_axil_araddr  = word_addr * 4;
    st_axil_arvalid = 1'b1;
    accepted = 1'b0;
    while (!accepted) begin
      @(posedge clk);
      if (st_axil_arready) accepted = 1'b1;
    end
    @(negedge clk);
    st_axil_arvalid = 1'b0;
    @(posedge clk);
    data = st_axil_rdata;
  endtask

  // ── T3's known-good miss packet -- reused byte-for-byte from
  // tb_fiveTuple_top.sv's T3 (eth+ipv4+udp, src=C0A80003 dst=C0A80004
  // sport=3000 dport=4000, never CP-configured anywhere -- guaranteed
  // miss, so output==input exactly, no eth.type rewrite complications).
  // 42 bytes total, packed into 11 32-bit words (big-endian, matches
  // emit_selftest.py's documented tmpl_buf write convention).
  localparam int PKT_LEN = 42;
  logic [31:0] pkt_words[0:10];
  task automatic build_pkt_words(input logic [7:0] sport_lo);
    // Ethernet: dst=AA:BB:CC:DD:EE:FF src=11:22:33:44:55:66 type=0x0800
    pkt_words[0]  = 32'hAABBCCDD;
    pkt_words[1]  = 32'hEEFF1122;
    pkt_words[2]  = 32'h33445566;
    pkt_words[3]  = 32'h08004500;  // type=0800 | ipv4 ver/ihl=45 tos=00
    // IPv4: total_len=0000 id=1234 flags/frag=0000
    pkt_words[4]  = 32'h00001234;
    pkt_words[5]  = {8'h00, 8'h00, 8'd64, 8'd17};       // frag_lo=0000 ttl=64 proto=17(UDP)
    pkt_words[6]  = {16'h0000, 8'hC0, 8'hA8};           // checksum=0000 src[31:16]=C0A8
    pkt_words[7]  = {8'h00, 8'h03, 8'hC0, 8'hA8};        // src[15:0]=0003 dst[31:16]=C0A8
    // UDP: sport=(0x0B, sport_lo) dport=4000(0x0FA0) length=8 checksum=0
    pkt_words[8]  = {8'h00, 8'h04, 8'h0B, sport_lo};     // dst[15:0]=0004 sport=0B__
    pkt_words[9]  = {8'h0F, 8'hA0, 16'h0008};            // dport=0FA0 length=0008
    pkt_words[10] = 32'h00000000;                        // checksum=0000 + 2 don't-care pad bytes
  endtask

  task automatic write_template(input logic [7:0] sport_lo);
    build_pkt_words(sport_lo);
    for (int i = 0; i < 11; i++)
      st_write(TMPL_BASE_WORD + i, pkt_words[i]);
  endtask

  task automatic gen_configure(input int pkt_len, input int pkt_count,
                                input int vary_offset, input bit vary_enable,
                                input int ipg);
    st_write(GEN_PKT_LEN, pkt_len);
    st_write(GEN_PKT_COUNT, pkt_count);
    st_write(GEN_VARY_OFFSET, vary_offset);
    st_write(GEN_VARY_ENABLE, {31'd0, vary_enable});
    st_write(GEN_IPG, ipg);
  endtask

  task automatic poll_gen_done;
    logic [31:0] status;
    status = 32'd0;
    while (!status[1]) st_read(GEN_STATUS, status);
  endtask

  task automatic poll_cap_done;
    logic [31:0] status;
    status = 32'd0;
    while (!status[1]) st_read(CAP_STATUS, status);
  endtask

  initial begin
    $display("== tb_fiveTuple_selftest_top: on-chip generator/capture regression ==\n");

    // ────────────────────────────────────────────────────────────────────
    $display("══ T1: reset/idle sanity ══════════════════════════════════════════");
    do_reset();
    begin
      logic [31:0] v;
      st_read(GEN_STATUS, v);      chk("T1: gen_status==0 after reset", v == 32'd0);
      st_read(CAP_STATUS, v);      chk("T1: cap_status==0 after reset", v == 32'd0);
      st_read(GEN_SENT_COUNT, v);  chk("T1: gen_sent_count==0 after reset", v == 32'd0);
      st_read(MAX_PKT_BYTES_REG, v);
      chk("T1: max_pkt_bytes capability register == 8192 (default width)", v == 32'd8192);
    end

    // ────────────────────────────────────────────────────────────────────
    $display("\n══ T2: single-packet round-trip / byte-packing proof ═════════════");
    do_reset();
    write_template(8'hB8);  // sport low byte = 0xB8 -> sport=3000
    gen_configure(PKT_LEN, 1, 0, 1'b0, 0);
    st_write(CAP_START, 32'd0);   // arm BEFORE starting -- required (see T4)
    st_write(GEN_START, 32'd0);
    poll_gen_done();
    poll_cap_done();
    begin
      logic [31:0] sent, byte_count, rd;
      bit mismatch;
      st_read(GEN_SENT_COUNT, sent);
      chk("T2: gen_sent_count==1", sent == 32'd1);
      st_read(CAP_BYTE_COUNT, byte_count);
      chk("T2: cap_byte_count==42", byte_count == PKT_LEN);
      mismatch = 1'b0;
      for (int i = 0; i < 11; i++) begin
        st_read(CAP_BASE_WORD + i, rd);
        if (rd !== pkt_words[i]) mismatch = 1'b1;
      end
      chk("T2: captured bytes match the template word-for-word", !mismatch);
    end

    // ────────────────────────────────────────────────────────────────────
    $display("\n══ T3: multi-packet burst + vary sweep ════════════════════════════");
    do_reset();
    write_template(8'hB8);  // base sport low byte = 0xB8 (184)
    // vary_offset=35 is the UDP sport low byte's position in the 42-byte
    // packet (word 8's LSB, byte index 4*8+3=35 -- matches build_pkt_words'
    // pkt_words[8] = {..., sport_lo} placing sport_lo at that byte).
    gen_configure(PKT_LEN, 5, 35, 1'b1, 0);
    st_write(CAP_START, 32'd0);
    st_write(GEN_START, 32'd0);
    poll_gen_done();
    poll_cap_done();
    begin
      logic [31:0] sent, byte_count, last_word;
      st_read(GEN_SENT_COUNT, sent);
      chk("T3: gen_sent_count==5", sent == 32'd5);
      st_read(CAP_BYTE_COUNT, byte_count);
      chk("T3: cap_byte_count==42 (last packet, same length)", byte_count == PKT_LEN);
      // word 8 of the captured packet: {dst[15:0]=0004, sport_hi=0B, sport_lo}
      // sport_lo should be 0xB8+4=0xBC for the 5th (index-4) packet.
      st_read(CAP_BASE_WORD + 8, last_word);
      chk("T3: vary sweep applied to the LAST packet (sport_lo == base+4)",
          last_word[7:0] == 8'hBC);
      chk("T3: vary sweep did not disturb the adjacent byte (sport_hi == 0x0B)",
          last_word[15:8] == 8'h0B);
    end

    // ────────────────────────────────────────────────────────────────────
    $display("\n══ T4: cut-through-aware capture ordering (positive + negative) ═══");
    do_reset();
    begin
      // Large payload (well beyond one beat) so cut-through genuinely
      // triggers, mirroring tb_fiveTuple_top.sv's own T2 cut-through proof:
      // reuse the same 42-byte header, but request a bigger gen_pkt_len than
      // the template holds -- the tail (all zero, tkeep-covered) bytes are
      // still real AXI4-Stream payload from the generator's point of view,
      // sufficient to force the core's cut-through/multi-beat path.
      localparam int BIG_LEN = 4096;
      logic [31:0] byte_count;

      // Positive: arm BEFORE starting -> full length captured.
      write_template(8'hB8);
      gen_configure(BIG_LEN, 1, 0, 1'b0, 0);
      st_write(CAP_START, 32'd0);
      st_write(GEN_START, 32'd0);
      poll_gen_done();
      poll_cap_done();
      st_read(CAP_BYTE_COUNT, byte_count);
      chk("T4: cap_start before gen_start -> full packet captured",
          byte_count == BIG_LEN);

      // Negative: start GENERATING first, THEN arm capture -- must miss the
      // early (cut-through) bytes and end up short. Poll gen_status.busy
      // briefly so cap_start genuinely lands mid-transmission, not before
      // the DUT has even begun producing output.
      do_reset();
      write_template(8'hB8);
      gen_configure(BIG_LEN, 1, 0, 1'b0, 0);
      st_write(GEN_START, 32'd0);
      // Deliberately wait a handful of cycles (long enough for the DUT's
      // own cut-through output to have started, proven elsewhere in this
      // project for this same fiveTuple pipeline) before arming capture.
      repeat (30) @(posedge clk);
      st_write(CAP_START, 32'd0);
      poll_gen_done();
      poll_cap_done();
      st_read(CAP_BYTE_COUNT, byte_count);
      chk("T4: gen_start before cap_start -> capture demonstrably SHORT (misordering hazard is real)",
          byte_count < BIG_LEN);
    end

    // ────────────────────────────────────────────────────────────────────
    $display("\n══ T5: inter-packet gap (IPG) timing ═══════════════════════════════");
    do_reset();
    begin
      logic [31:0] sent;
      longint t0, t1, gap_cycles;
      write_template(8'hB8);
      // Single-beat packets (well under one beat's byte width) keep this
      // test's timing simple to reason about.
      gen_configure(16, 3, 0, 1'b0, 20);
      st_write(CAP_START, 32'd0);
      // Hierarchical probe on the internal gen_axis_tvalid net -- first use
      // of DUT-internal probing in this project's testbenches (no external
      // signal exposes generator beat timing) -- watch for the first two
      // tvalid pulses (packet 0 then packet 1) and measure the gap.
      fork
        begin
          @(posedge dut.gen_axis_tvalid);
          t0 = $time;
          @(negedge dut.gen_axis_tvalid);
          @(posedge dut.gen_axis_tvalid);
          t1 = $time;
        end
        st_write(GEN_START, 32'd0);
      join
      gap_cycles = (t1 - t0) / CLK_T;
      chk("T5: measured inter-packet gap >= gen_ipg", gap_cycles >= 20);
      poll_gen_done();
      st_read(GEN_SENT_COUNT, sent);
      chk("T5: burst still completes correctly with IPG active", sent == 32'd3);
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
