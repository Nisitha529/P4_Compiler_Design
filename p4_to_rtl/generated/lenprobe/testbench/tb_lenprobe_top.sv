// ============================================================================
// tb_lenprobe_top.sv -- the LENGTH-CHANGING deparser
// (docs/length_changing_deparser_plan.md, step 0).
//
// Written as a FAILING baseline (step 0) and now passing (step 3). It pinned the
// gap before anything was changed, which is why the fix had a target.
//
// The shell used to reproduce the input packet's length exactly: TX replayed
// slot_beat_cnt beats and the deparser overlaid headers onto the received bytes
// at fixed offsets, so a header made valid that was never parsed was dropped
// entirely and one made invalid left its bytes behind. TX now emits a single
// byte stream -- the output header image, then the payload shifted by
// hdr_delta -- so both work.
//
// Four cases, each an exact byte-for-byte comparison against the packet the P4
// program says should come out:
//   T1  fwd         : nothing changes                  -> out == in        (64 B)
//   T2  insert_one  : 4 bytes appear after ethernet     -> out == in + 4   (68 B)
//   T3  insert_two  : 8 bytes appear after ethernet     -> out == in + 8   (72 B)
//   T4  strip_vlan  : a parsed 4-byte VLAN is removed   -> out == in - 4   (60 B)
//
// This is the same shape as fiveTuple.p4's InsertVLAN, the flagship app's whole
// purpose, which has never been exercisable end-to-end for exactly this reason.
// ============================================================================
`timescale 1ns/1ps

module tb_lenprobe_top;

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

  logic [15:0] out_meta_unused;
  logic  [8:0] out_std_meta_egress_port;

  lenprobe_top dut (
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
    .out_meta_unused(out_meta_unused),
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

  // cls (exact on eth.etype): 0 idx 1 action 2 key_etype 3 p_port 4 commit
  localparam int ACT_FWD = 1, ACT_INS1 = 2, ACT_INS2 = 3, ACT_STRIP = 4;
  task automatic prog_cls(input int idx, input [15:0] etype, input int act,
                          input [8:0] port);
    axil_write(0, idx); axil_write(1, act); axil_write(2, etype);
    axil_write(3, port); axil_write(4, 1);
    repeat (4) @(posedge clk);
  endtask

  // ── frames as byte arrays, so lengths and contents are both checkable ─────
  byte unsigned tx_pkt [$];
  byte unsigned rx_pkt [$];
  byte unsigned expect_pkt [$];

  // eth(14) [+ vlan(4)] + a counting payload, total `nbytes`.
  task automatic build_frame(input [15:0] etype, input int nbytes, input bit with_vlan);
    tx_pkt.delete();
    for (int i = 0; i < nbytes; i++) tx_pkt.push_back(8'(8'h80 + i));
    tx_pkt[0]=8'h00; tx_pkt[1]=8'h11; tx_pkt[2]=8'h22;
    tx_pkt[3]=8'h33; tx_pkt[4]=8'h44; tx_pkt[5]=8'h55;
    tx_pkt[6]=8'h66; tx_pkt[7]=8'h77; tx_pkt[8]=8'h88;
    tx_pkt[9]=8'h99; tx_pkt[10]=8'haa; tx_pkt[11]=8'hbb;
    tx_pkt[12]=etype[15:8]; tx_pkt[13]=etype[7:0];
    if (with_vlan) begin
      tx_pkt[14]=8'h0A; tx_pkt[15]=8'hBC;   // tci
      tx_pkt[16]=8'h08; tx_pkt[17]=8'h00;   // inner etherType
    end
  endtask

  task automatic send_pkt;
    logic [TB_AXI_DATA_W-1:0] beat;
    logic [TB_BEAT_BYTES-1:0] keep;
    int nbeats;
    nbeats = (tx_pkt.size() + TB_BEAT_BYTES - 1) / TB_BEAT_BYTES;
    for (int b = 0; b < nbeats; b++) begin
      beat = '0; keep = '0;
      for (int i = 0; i < TB_BEAT_BYTES; i++)
        if (b*TB_BEAT_BYTES + i < tx_pkt.size()) begin
          beat[i*8 +: 8] = tx_pkt[b*TB_BEAT_BYTES + i];
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

  logic collecting = 0;
  always @(posedge clk) begin
    #1;
    if (collecting && m_axis_tvalid && m_axis_tready)
      for (int i = 0; i < TB_BEAT_BYTES; i++)
        if (m_axis_tkeep[i]) rx_pkt.push_back(m_axis_tdata[i*8 +: 8]);
  end

  task automatic run_one(input [15:0] etype, input int nbytes, input bit with_vlan,
                         input int wait_cyc = 400);
    build_frame(etype, nbytes, with_vlan);
    rx_pkt.delete();
    saw_delta = 1'b0; seen_delta = 999; seen_splice = 999;
    collecting = 1;
    send_pkt();
    repeat (wait_cyc) @(posedge clk);
    collecting = 0;
  endtask

  function automatic int first_diff;
    if (rx_pkt.size() != expect_pkt.size()) return -1;
    for (int i = 0; i < expect_pkt.size(); i++)
      if (rx_pkt[i] !== expect_pkt[i]) return i;
    return -2;   // identical
  endfunction

  task automatic report(input string tag);
    int d;
    d = first_diff();
    if (d == -2)
      $display("    [INFO] %s: %0d bytes out, byte-for-byte correct", tag, rx_pkt.size());
    else if (d == -1)
      $display("    [INFO] %s: WRONG LENGTH -- got %0d bytes, expected %0d",
               tag, rx_pkt.size(), expect_pkt.size());
    else
      $display("    [INFO] %s: length ok (%0d) but first difference at byte %0d: got %02h expected %02h",
               tag, rx_pkt.size(), d, rx_pkt[d], expect_pkt[d]);
  endtask

  // Step 1 observability: sample hdr_delta while TX is on the packet.
  int    seen_delta, seen_splice;
  logic  saw_delta = 0;
  always @(posedge clk) begin
    #1;
    if (collecting && m_axis_tvalid && m_axis_tready && !saw_delta) begin
      seen_delta  = dut.hdr_delta;
      seen_splice = dut.tx_splice;
      saw_delta   = 1'b1;
    end
  end

  int i;

  initial begin
    $display("\n== tb_lenprobe_top: length-changing deparser ==\n");
    do_reset();

    prog_cls(0, 16'h0001, ACT_INS1,  9'd1);
    prog_cls(1, 16'h0002, ACT_INS2,  9'd1);
    prog_cls(2, 16'h0003, ACT_STRIP, 9'd1);
    prog_cls(3, 16'h0004, ACT_FWD,   9'd1);

    // ---- T1: no length change (the control case) -------------------------
    $display("== T1: fwd -- nothing changes, out == in ==");
    run_one(16'h0004, 64, 0);
    expect_pkt = tx_pkt;
    report("T1");
    chk("T1: hdr_delta == 0 (step 1)", seen_delta == 0);
    chk("T1: tx_splice == 14 (step 2)", seen_splice == 14);
    chk("T1: 64 bytes out", rx_pkt.size() == 64);
    chk("T1: byte-for-byte identical to the input", first_diff() == -2);

    // ---- T2: insert 4 bytes ---------------------------------------------
    $display("\n== T2: insert_one -- 4 bytes appear after ethernet ==");
    run_one(16'h0001, 64, 0);
    expect_pkt.delete();
    for (i = 0; i < 14; i++) expect_pkt.push_back(tx_pkt[i]);      // ethernet
    expect_pkt.push_back(8'hAA); expect_pkt.push_back(8'h01);      // tag.magic
    expect_pkt.push_back(8'h11); expect_pkt.push_back(8'h11);      // tag.seq
    for (i = 14; i < 64; i++) expect_pkt.push_back(tx_pkt[i]);     // the rest, shifted
    report("T2");
    chk("T2: hdr_delta == 4 (step 1)", seen_delta == 4);
    chk("T2: tx_splice == 18 (step 2)", seen_splice == 18);
    chk("T2: 68 bytes out (64 + 4)", rx_pkt.size() == 68);
    chk("T2: the inserted tag is present and the tail shifted", first_diff() == -2);

    // ---- T3: insert 8 bytes ---------------------------------------------
    $display("\n== T3: insert_two -- 8 bytes appear after ethernet ==");
    run_one(16'h0002, 64, 0);
    expect_pkt.delete();
    for (i = 0; i < 14; i++) expect_pkt.push_back(tx_pkt[i]);
    expect_pkt.push_back(8'hAA); expect_pkt.push_back(8'h01);
    expect_pkt.push_back(8'h11); expect_pkt.push_back(8'h11);
    expect_pkt.push_back(8'hBB); expect_pkt.push_back(8'h02);      // tag2.magic2
    expect_pkt.push_back(8'h22); expect_pkt.push_back(8'h22);      // tag2.seq2
    for (i = 14; i < 64; i++) expect_pkt.push_back(tx_pkt[i]);
    report("T3");
    chk("T3: hdr_delta == 8 (step 1)", seen_delta == 8);
    chk("T3: tx_splice == 22 (step 2)", seen_splice == 22);
    chk("T3: 72 bytes out (64 + 8)", rx_pkt.size() == 72);
    chk("T3: both tags present, tail shifted by 8", first_diff() == -2);

    // ---- T4: remove 4 bytes ---------------------------------------------
    $display("\n== T4: strip_vlan -- a parsed 4-byte VLAN is removed ==");
    run_one(16'h0003, 64, 1);
    expect_pkt.delete();
    for (i = 0; i < 14; i++) expect_pkt.push_back(tx_pkt[i]);      // ethernet
    for (i = 18; i < 64; i++) expect_pkt.push_back(tx_pkt[i]);     // skip the VLAN
    report("T4");
    chk("T4: hdr_delta == -4 (step 1)", seen_delta == -4);
    chk("T4: tx_splice == 14 (step 2)", seen_splice == 14);
    chk("T4: 60 bytes out (64 - 4)", rx_pkt.size() == 60);
    chk("T4: the VLAN is gone and the tail pulled back by 4", first_diff() == -2);

    $display("\n================================================================");
    $display("  Results: %0d passed, %0d failed  (total %0d)", pass_cnt, fail_cnt, pass_cnt+fail_cnt);
    $display("================================================================");
    if (fail_cnt == 0) $display("  ALL TESTS PASSED");
    else                $display("  SOME TESTS FAILED");
    $finish;
  end

endmodule
