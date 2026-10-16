// ============================================================================
// tb_feprobe_selftest_top.sv -- FeatureExport records through the --self-test
// wrapper: the on-chip path by which a board with no MAC and no DMA can see
// the record stream at all.
//
// The gap this closes: the wrapper instantiates feprobe_top, and before this it
// left the record ports out of that instantiation entirely. SystemVerilog
// allows it silently, so <name>_tready was an UNDRIVEN INPUT of the core --
// tied low by synthesis -- the shell's staging FIFO filled, and every record
// after it was counted as dropped. For a program whose whole product is the
// feature stream, the self-test build could not observe its own output.
// scripts/check_selftest_ports.py now fails on any core input the wrapper
// leaves undriven, which is the structural guard; this testbench checks the
// records that now come back are the RIGHT ones.
//
//   R1  the record window describes itself: rec_info (instances, words per
//       entry, depth) and the three window bases, all read from the DUT
//   R2  a generated burst produces one record per packet per instance, and
//       each record's FIELDS land where the cp_map says
//   R3  the vary sweep walks a dst byte, so record i belongs to packet i --
//       ordering and per-packet capture, not one record repeated
//   R4  more packets than the window holds: rec_count saturates at the depth,
//       rec_total keeps counting, and (total - count) is what was not kept
//   R5  rec_arm clears counts and totals for every instance
//   R6  the second instance is the GATED one: with the table dropping the
//       packet, tcn_feed still records and gated_feed stays silent -- the
//       drop-gate behaviour, now observable on-chip
//
// tcn_feed record (cp_map): [63:48] eth.etype  [47:32] packet_length
//                           [31:16] eth.dst[15:0]  [15:8] 0xA5  [7:0] parsed_bytes
// gated_feed record:        [15:0]  eth.dst[15:0]
// ============================================================================
`timescale 1ns/1ps

module tb_feprobe_selftest_top;

  localparam CLK_T = 10;
  logic clk = 0;
  always #(CLK_T/2) clk = ~clk;
  logic rst_n;

  // Self-test bus register map (compiler/emit_selftest.py's docstring)
  localparam int GEN_PKT_LEN       = 0;
  localparam int GEN_PKT_COUNT     = 1;
  localparam int GEN_VARY_OFFSET   = 2;
  localparam int GEN_VARY_ENABLE   = 3;
  localparam int GEN_IPG           = 4;
  localparam int GEN_START         = 5;
  localparam int GEN_STATUS        = 6;
  localparam int CAP_START         = 8;
  localparam int MAX_PKT_BYTES_REG = 11;
  localparam int REC_ARM           = 12;   // W: clear; R: rec_info
  localparam int REC_SEL           = 13;
  localparam int REC_COUNT         = 14;
  localparam int REC_TOTAL         = 15;
  localparam int TMPL_BASE_REG     = 17;
  localparam int CAP_BASE_REG      = 18;
  localparam int REC_BASE_REG      = 19;

  // All read from the DUT in R1 -- never hardcoded.
  int TMPL_BASE_WORD, CAP_BASE_WORD, REC_BASE_WORD;
  int REC_NINST, REC_WORDS, REC_DEPTH;

  logic [15:0] s_axil_awaddr = 0; logic s_axil_awvalid = 0, s_axil_awready;
  logic [31:0] s_axil_wdata = 0;  logic [3:0] s_axil_wstrb = 0;
  logic s_axil_wvalid = 0, s_axil_wready; logic [1:0] s_axil_bresp;
  logic s_axil_bvalid, s_axil_bready = 1'b1;
  logic [15:0] s_axil_araddr = 0; logic s_axil_arvalid = 0, s_axil_arready;
  logic [31:0] s_axil_rdata;  logic [1:0] s_axil_rresp;
  logic s_axil_rvalid, s_axil_rready = 1'b1;

  logic [15:0] st_axil_awaddr = 0; logic st_axil_awvalid = 0, st_axil_awready;
  logic [31:0] st_axil_wdata = 0;  logic [3:0] st_axil_wstrb = 0;
  logic st_axil_wvalid = 0, st_axil_wready; logic [1:0] st_axil_bresp;
  logic st_axil_bvalid, st_axil_bready = 1'b1;
  logic [15:0] st_axil_araddr = 0; logic st_axil_arvalid = 0, st_axil_arready;
  logic [31:0] st_axil_rdata;  logic [1:0] st_axil_rresp;
  logic st_axil_rvalid, st_axil_rready = 1'b1;

  logic [63:0] tcn_feed_tdata;   logic tcn_feed_tvalid;
  logic [15:0] gated_feed_tdata; logic gated_feed_tvalid;

  feprobe_selftest_top dut (
    .clk(clk), .rst_n(rst_n),
    .s_axil_awaddr(s_axil_awaddr), .s_axil_awvalid(s_axil_awvalid), .s_axil_awready(s_axil_awready),
    .s_axil_wdata(s_axil_wdata), .s_axil_wstrb(s_axil_wstrb),
    .s_axil_wvalid(s_axil_wvalid), .s_axil_wready(s_axil_wready),
    .s_axil_bresp(s_axil_bresp), .s_axil_bvalid(s_axil_bvalid), .s_axil_bready(s_axil_bready),
    .s_axil_araddr(s_axil_araddr), .s_axil_arvalid(s_axil_arvalid), .s_axil_arready(s_axil_arready),
    .s_axil_rdata(s_axil_rdata), .s_axil_rresp(s_axil_rresp),
    .s_axil_rvalid(s_axil_rvalid), .s_axil_rready(s_axil_rready),
    .st_axil_awaddr(st_axil_awaddr), .st_axil_awvalid(st_axil_awvalid), .st_axil_awready(st_axil_awready),
    .st_axil_wdata(st_axil_wdata), .st_axil_wstrb(st_axil_wstrb),
    .st_axil_wvalid(st_axil_wvalid), .st_axil_wready(st_axil_wready),
    .st_axil_bresp(st_axil_bresp), .st_axil_bvalid(st_axil_bvalid), .st_axil_bready(st_axil_bready),
    .st_axil_araddr(st_axil_araddr), .st_axil_arvalid(st_axil_arvalid), .st_axil_arready(st_axil_arready),
    .st_axil_rdata(st_axil_rdata), .st_axil_rresp(st_axil_rresp),
    .st_axil_rvalid(st_axil_rvalid), .st_axil_rready(st_axil_rready),
    .tcn_feed_tdata(tcn_feed_tdata), .tcn_feed_tvalid(tcn_feed_tvalid),
    .gated_feed_tdata(gated_feed_tdata), .gated_feed_tvalid(gated_feed_tvalid)
  );

  int pass_cnt = 0, fail_cnt = 0;
  task automatic chk(input string name, input logic cond);
    if (cond) begin $display("    [PASS] %s", name); pass_cnt++; end
    else      begin $display("    [FAIL] %s", name); fail_cnt++; end
  endtask

  task automatic do_reset;
    rst_n = 0;
    st_axil_awvalid = 0; st_axil_wvalid = 0; st_axil_arvalid = 0;
    s_axil_awvalid = 0; s_axil_wvalid = 0; s_axil_arvalid = 0;
    repeat(5) @(posedge clk); @(negedge clk);
    rst_n = 1; @(posedge clk); #1;
  endtask

  task automatic st_write(input int word_addr, input logic [31:0] data);
    bit aw_done, w_done;
    @(negedge clk);
    st_axil_awaddr = word_addr * 4; st_axil_awvalid = 1'b1;
    st_axil_wdata = data; st_axil_wstrb = 4'hF; st_axil_wvalid = 1'b1;
    aw_done = 1'b0; w_done = 1'b0;
    while (!aw_done || !w_done) begin
      @(posedge clk); #1;
      if (!aw_done && st_axil_awready) aw_done = 1'b1;
      if (!w_done && st_axil_wready)   w_done  = 1'b1;
    end
    @(negedge clk); st_axil_awvalid = 1'b0; st_axil_wvalid = 1'b0;
  endtask

  // Undelayed rvalid/rdata sample, then poll: control words answer in one
  // cycle, buffer-backed ones take three (R_IDLE->R_WAIT->R_EXTRACT->R_DATA).
  task automatic st_read(input int word_addr, output logic [31:0] data);
    bit accepted;
    @(negedge clk);
    st_axil_araddr = word_addr * 4; st_axil_arvalid = 1'b1;
    accepted = 1'b0;
    while (!accepted) begin @(posedge clk); if (st_axil_arready) accepted = 1'b1; end
    @(negedge clk); st_axil_arvalid = 1'b0;
    while (!st_axil_rvalid) @(posedge clk);
    data = st_axil_rdata;
  endtask

  // The table CP bus, for programming fwd (passed straight through by the
  // wrapper -- programming a table on the self-test build must still work).
  task automatic cp_write(input int word_addr, input logic [31:0] data);
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
    @(negedge clk); s_axil_awvalid = 1'b0; s_axil_wvalid = 1'b0;
  endtask

  // fwd: 0 wr_idx, 1 wr_action, 2 key_etype, 3 p_p, 4 commit (cp_map)
  task automatic prog_fwd(input int idx, input logic [15:0] etype,
                          input int act, input logic [8:0] port);
    cp_write(0, idx); cp_write(1, act); cp_write(2, {16'd0, etype});
    cp_write(3, {23'd0, port}); cp_write(4, 32'd1);
  endtask

  // A 64-byte frame: dst = 00:11:22:33:44:<dst_lo>, etype at bytes 12-13.
  // Big-endian word packing, per the tmpl_buf convention.
  localparam int PKT_LEN = 64;
  task automatic write_template(input logic [7:0] dst_lo, input logic [15:0] etype);
    logic [31:0] w;
    for (int i = 0; i < PKT_LEN/4; i++) begin
      case (i)
        0: w = {8'h00, 8'h11, 8'h22, 8'h33};
        1: w = {8'h44, dst_lo, 8'h66, 8'h77};       // dst[15:0] = {44, dst_lo}
        2: w = 32'h88995566;
        3: w = {etype, 16'hDEAD};                    // etype at bytes 12-13
        default: w = {8'(i*4), 8'(i*4+1), 8'(i*4+2), 8'(i*4+3)};
      endcase
      st_write(TMPL_BASE_WORD + i, w);
    end
  endtask

  task automatic poll_gen_done;
    logic [31:0] status;
    status = 32'd0;
    while (!status[1]) st_read(GEN_STATUS, status);
  endtask

  // One record, as two 32-bit words out of the window for the selected instance
  task automatic read_record(input int inst, input int idx, output logic [63:0] rec);
    logic [31:0] lo, hi;
    st_write(REC_SEL, inst);
    st_read(REC_BASE_WORD + idx*REC_WORDS + 0, lo);
    if (REC_WORDS > 1) st_read(REC_BASE_WORD + idx*REC_WORDS + 1, hi);
    else               hi = 32'd0;
    rec = {hi, lo};
  endtask

  logic [31:0] v;
  logic [63:0] rec;
  int n_ok, cnt0, cnt1, tot0, tot1;

  initial begin
    $display("\n================================================================");
    $display("  feprobe --self-test: FeatureExport records read back on-chip");
    $display("================================================================");
    do_reset();

    // ── R1: the window describes itself ─────────────────────────────────────
    $display("\n== R1: the record window describes itself ==");
    st_read(REC_ARM, v);
    REC_DEPTH = int'(v[31:16]); REC_WORDS = int'(v[15:8]); REC_NINST = int'(v[7:0]);
    $display("      rec_info: %0d instance(s), %0d word(s)/entry, depth %0d",
             REC_NINST, REC_WORDS, REC_DEPTH);
    chk("R1: two FeatureExport instances reported", REC_NINST == 2);
    chk("R1: 2 words per entry (the widest record is 64-bit)", REC_WORDS == 2);
    chk("R1: a non-zero depth", REC_DEPTH > 0);
    st_read(TMPL_BASE_REG, v); TMPL_BASE_WORD = int'(v);
    st_read(CAP_BASE_REG,  v); CAP_BASE_WORD  = int'(v);
    st_read(REC_BASE_REG,  v); REC_BASE_WORD  = int'(v);
    $display("      bases: tmpl=%0d cap=%0d rec=%0d",
             TMPL_BASE_WORD, CAP_BASE_WORD, REC_BASE_WORD);
    chk("R1: the record window sits above the capture buffer",
        REC_BASE_WORD > CAP_BASE_WORD && CAP_BASE_WORD > TMPL_BASE_WORD);

    // ── R2: one record per packet, fields in position ───────────────────────
    $display("\n== R2: a 4-packet burst, fields where the cp_map says ==");
    prog_fwd(0, 16'h0801, 1, 9'd5);        // action 1 = set_port
    write_template(8'h10, 16'h0801);
    st_write(REC_ARM, 32'd0);
    st_write(CAP_START, 32'd0);
    st_write(GEN_PKT_LEN, PKT_LEN); st_write(GEN_PKT_COUNT, 4);
    st_write(GEN_VARY_ENABLE, 32'd0); st_write(GEN_IPG, 32'd8);
    st_write(GEN_START, 32'd0);
    poll_gen_done();
    repeat (200) @(posedge clk);
    st_write(REC_SEL, 0); st_read(REC_COUNT, v); cnt0 = int'(v);
    st_write(REC_SEL, 1); st_read(REC_COUNT, v); cnt1 = int'(v);
    $display("      records stored: tcn_feed=%0d gated_feed=%0d", cnt0, cnt1);
    chk("R2: tcn_feed recorded all 4 packets",   cnt0 == 4);
    chk("R2: gated_feed recorded all 4 as well (none dropped)", cnt1 == 4);
    read_record(0, 0, rec);
    $display("      tcn_feed[0] = %016h", rec);
    chk("R2: [63:48] = eth.etype",            rec[63:48] === 16'h0801);
    chk("R2: [47:32] = packet_length (64)",   rec[47:32] === 16'd64);
    chk("R2: [31:16] = eth.dst[15:0]",        rec[31:16] === 16'h4410);
    chk("R2: [15:8]  = the 0xA5 constant",    rec[15:8]  === 8'hA5);
    chk("R2: [7:0]   = parsed_bytes (14)",    rec[7:0]   === 8'd14);
    read_record(1, 0, rec);
    chk("R2: gated_feed[0] carries the same dst", rec[15:0] === 16'h4410);

    // ── R3: the sweep proves record i belongs to packet i ───────────────────
    // The vary sweep increments template byte 5, which is eth.dst[7:0], so
    // the records must walk with it. Without this, one record repeated four
    // times would pass R2 unnoticed.
    $display("\n== R3: the vary sweep walks dst, and the records walk with it ==");
    do_reset();
    prog_fwd(0, 16'h0801, 1, 9'd5);
    write_template(8'h20, 16'h0801);
    st_write(REC_ARM, 32'd0);
    st_write(GEN_PKT_LEN, PKT_LEN); st_write(GEN_PKT_COUNT, 5);
    st_write(GEN_VARY_OFFSET, 5); st_write(GEN_VARY_ENABLE, 32'd1);
    st_write(GEN_IPG, 32'd8);
    st_write(GEN_START, 32'd0);
    poll_gen_done();
    repeat (250) @(posedge clk);
    n_ok = 1;
    for (int i = 0; i < 5; i++) begin
      read_record(0, i, rec);
      $display("      tcn_feed[%0d] dst[15:0]=%04h", i, rec[31:16]);
      // !== , not != : an X compares as X, which an `if` treats as false, so
      // != would let an unread record pass this check silently.
      if (rec[31:16] !== {8'h44, 8'(8'h20 + i)}) n_ok = 0;
    end
    chk("R3: record i carries packet i's swept dst byte", n_ok == 1);

    // ── R4: more packets than the window holds ──────────────────────────────
    $display("\n== R4: overflowing the window keeps the first N and says so ==");
    do_reset();
    prog_fwd(0, 16'h0801, 1, 9'd5);
    write_template(8'h30, 16'h0801);
    st_write(REC_ARM, 32'd0);
    st_write(GEN_PKT_LEN, PKT_LEN); st_write(GEN_PKT_COUNT, REC_DEPTH + 6);
    st_write(GEN_VARY_ENABLE, 32'd0); st_write(GEN_IPG, 32'd4);
    st_write(GEN_START, 32'd0);
    poll_gen_done();
    repeat (400) @(posedge clk);
    st_write(REC_SEL, 0);
    st_read(REC_COUNT, v); cnt0 = int'(v);
    st_read(REC_TOTAL, v); tot0 = int'(v);
    $display("      tcn_feed: stored=%0d seen=%0d", cnt0, tot0);
    chk("R4: stored saturates at the window depth", cnt0 == REC_DEPTH);
    chk("R4: seen counts every record pushed",      tot0 == REC_DEPTH + 6);
    chk("R4: the difference is what was not kept",  tot0 - cnt0 == 6);

    // ── R5: rec_arm clears every instance ───────────────────────────────────
    $display("\n== R5: rec_arm clears both instances ==");
    st_write(REC_ARM, 32'd0);
    repeat (4) @(posedge clk);
    st_write(REC_SEL, 0); st_read(REC_COUNT, v); cnt0 = int'(v);
                          st_read(REC_TOTAL, v); tot0 = int'(v);
    st_write(REC_SEL, 1); st_read(REC_COUNT, v); cnt1 = int'(v);
                          st_read(REC_TOTAL, v); tot1 = int'(v);
    chk("R5: instance 0 cleared", cnt0 == 0 && tot0 == 0);
    chk("R5: instance 1 cleared", cnt1 == 0 && tot1 == 0);

    // ── R6: the drop gate, observable on-chip ───────────────────────────────
    // action 2 = drop_it. tcn_feed pushes unconditionally; gated_feed pushes
    // only `if (smeta.drop == 0)`. Both of those were verified on the core's
    // own stream ports by tb_feprobe_top; the point here is that the self-test
    // build can now see the same thing with no external consumer at all.
    $display("\n== R6: an ingress-dropped packet: tcn_feed records, gated_feed does not ==");
    do_reset();
    prog_fwd(0, 16'h0802, 2, 9'd0);        // action 2 = drop_it
    write_template(8'h40, 16'h0802);
    st_write(REC_ARM, 32'd0);
    st_write(GEN_PKT_LEN, PKT_LEN); st_write(GEN_PKT_COUNT, 3);
    st_write(GEN_VARY_ENABLE, 32'd0); st_write(GEN_IPG, 32'd8);
    st_write(GEN_START, 32'd0);
    poll_gen_done();
    repeat (250) @(posedge clk);
    st_write(REC_SEL, 0); st_read(REC_TOTAL, v); tot0 = int'(v);
    st_write(REC_SEL, 1); st_read(REC_TOTAL, v); tot1 = int'(v);
    $display("      pushed: tcn_feed=%0d gated_feed=%0d", tot0, tot1);
    chk("R6: tcn_feed recorded the dropped packets", tot0 == 3);
    chk("R6: gated_feed stayed silent",              tot1 == 0);
    read_record(0, 0, rec);
    chk("R6: and the record is that packet's",       rec[31:16] === 16'h4440);

    $display("\n================================================================");
    $display("  Results: %0d passed, %0d failed  (total %0d)", pass_cnt, fail_cnt, pass_cnt+fail_cnt);
    $display("================================================================");
    if (fail_cnt == 0) $display("  ALL TESTS PASSED");
    else                $display("  SOME TESTS FAILED");
    $finish;
  end

  initial begin #4000000; $display("[TIMEOUT]"); $finish; end

endmodule
