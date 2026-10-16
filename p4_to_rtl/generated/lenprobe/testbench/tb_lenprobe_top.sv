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
//   T6  insert_one on a frame that fits ENTIRELY in the header region, so the
//       payload buffer is empty -- TX used to wait for a payload beat that
//       never comes and wedge the slot ring behind it
//   T7  the same, shrinking
//   T8  a normal frame after those two, because the old failure stalled the
//       whole link rather than losing one packet
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

  parameter  int TB_BEAT_BYTES = 32;
  localparam int TB_AXI_DATA_W = TB_BEAT_BYTES * 8;
  // Beats a frame of `nbytes` occupies at THIS beat width. Beat counts used to
  // be written as literals (a 64 B frame was "2 beats"), which silently encoded
  // --axi-data-width 256 into every such assertion; at 512 they all failed and
  // said nothing about the design. See scripts/check_axi_width.sh.
  function automatic int nbeats_of(input int nbytes);
    return (nbytes + TB_BEAT_BYTES - 1) / TB_BEAT_BYTES;
  endfunction


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

  logic [15:0] out_meta_plen, out_meta_pbytes;
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
    .out_meta_plen(out_meta_plen), .out_meta_pbytes(out_meta_pbytes),
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
  localparam int ACT_FWD = 1, ACT_INS1 = 2, ACT_INS2 = 3, ACT_STAMP = 4, ACT_STRIP = 5;
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

  logic tb_wedged = 0;

  task automatic send_pkt;
    logic [TB_AXI_DATA_W-1:0] beat;
    logic [TB_BEAT_BYTES-1:0] keep;
    int nbeats, stall;
    nbeats = (tx_pkt.size() + TB_BEAT_BYTES - 1) / TB_BEAT_BYTES;
    // Guarded rather than an early `return`: iverilog 11 rejects `return`
    // from a task, so once the input is known wedged the remaining beats are
    // simply skipped.
    for (int b = 0; b < nbeats && !tb_wedged; b++) begin
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
      // BOUNDED. A wedged TX stops retiring slots, the ring fills, and
      // s_axis_tready stays low forever -- an unbounded wait here turns a
      // design failure into a testbench that never returns, which the
      // regression can only report as a timeout. Bounded, it reports the
      // failure and the remaining checks fail on an empty output, which says
      // what actually happened.
      stall = 0;
      while (!s_axis_tready && stall < 2000) begin
        @(posedge clk); stall = stall + 1;
      end
      if (stall >= 2000) begin
        // One string literal: iverilog does not join adjacent ones.
        $display("    [FAIL] input stalled %0d cycles on s_axis_tready -- TX is not retiring slots", stall);
        fail_cnt++;
        tb_wedged = 1'b1;
      end
      #1;
    end
    @(negedge clk);
    s_axis_tvalid = 1'b0; s_axis_tlast = 1'b0;
  endtask

  logic collecting = 0;
  logic        got_meta;
  logic [15:0] o_plen, o_pbytes;
  always @(posedge clk) begin
    #1;
    if (collecting && m_axis_tvalid && m_axis_tready && !got_meta) begin
      o_plen   = out_meta_plen;
      o_pbytes = out_meta_pbytes;
      got_meta = 1'b1;
    end
    if (collecting && m_axis_tvalid && m_axis_tready)
      for (int i = 0; i < TB_BEAT_BYTES; i++)
        if (m_axis_tkeep[i]) rx_pkt.push_back(m_axis_tdata[i*8 +: 8]);
  end

  // Step 1 observability: sample hdr_delta while TX is on the packet.
  int    seen_delta, seen_splice;
  logic  saw_delta = 0;
  // The DUT's header-region size, read hierarchically in T6/T7. It is
  // BEAT-ROUNDED, so it changes with --axi-data-width (32 bytes at 256,
  // 64 at 512) -- which is exactly why those two tests derive from it
  // rather than naming a frame size.
  int    hdr_region;
  // Declared ahead of the task below that clears them: xvlog rejects an
  // identifier used before its declaration, while iverilog accepts it.

  task automatic run_one(input [15:0] etype, input int nbytes, input bit with_vlan,
                         input int wait_cyc = 400);
    build_frame(etype, nbytes, with_vlan);
    rx_pkt.delete();
    got_meta = 1'b0; o_plen = 16'hFFFF; o_pbytes = 16'hFFFF;
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

  // Sampled when the beat is LOADED (dut.emit_beat), not when it is accepted
  // on m_axis. Both of these are per-slot views indexed by tx_slot, and the
  // slot is popped as the last beat is loaded -- so while that beat is still
  // being presented on m_axis, tx_slot already reads X and so do these. With a
  // 64-byte frame at --axi-data-width 256 the first beat was never the last
  // one, so sampling on the m_axis handshake happened to work; at 512 the whole
  // frame is one beat and it returned X (printed as 0), reporting hdr_delta 0
  // for a packet that shrank and splice 0 for a packet with a valid header.
  // The emitted bytes were correct throughout -- only the observation point was
  // wrong. emit_beat is the cycle these values are actually USED, which is the
  // only point where they are guaranteed to mean something.
  always @(negedge clk) begin
    if (collecting && dut.emit_beat && !saw_delta) begin
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
    prog_cls(4, 16'h0005, ACT_STAMP, 9'd1);

    // ---- T1: no length change (the control case) -------------------------
    $display("== T1: fwd -- nothing changes, out == in ==");
    run_one(16'h0004, 64, 0);
    expect_pkt = tx_pkt;
    report("T1");
    chk("T1: hdr_delta == 0 (step 1)", seen_delta == 0);
    chk("T1: tx_splice == 14 (step 2)", seen_splice == 14);
    chk("T1: 64 bytes out", rx_pkt.size() == 64);
    chk("T1: byte-for-byte identical to the input", first_diff() == -2);
    chk("T1: packet_length == 64 (received length)", o_plen == 16'd64);
    chk("T1: parsed_bytes == 14 (eth only)",         o_pbytes == 16'd14);

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
    chk("T2: packet_length still 64 -- the RECEIVED length, not the 68 sent",
        o_plen == 16'd64);
    chk("T2: parsed_bytes still 14 -- insert-only headers are never parsed",
        o_pbytes == 16'd14);

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
    chk("T3: packet_length still 64 (out is 72)", o_plen == 16'd64);

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
    chk("T4: packet_length == 64 (received), though only 60 went out", o_plen == 16'd64);
    chk("T4: parsed_bytes == 18 (eth + the VLAN that WAS parsed)", o_pbytes == 16'd18);

    // ---- T5: a program carrying a length across the change ---------------
    $display("\n== T5: insert_stamp -- the inserted header carries packet_length ==");
    run_one(16'h0005, 96, 0);
    expect_pkt.delete();
    for (i = 0; i < 14; i++) expect_pkt.push_back(tx_pkt[i]);
    expect_pkt.push_back(8'hAA); expect_pkt.push_back(8'h01);   // tag.magic
    expect_pkt.push_back(8'h00); expect_pkt.push_back(8'h60);   // tag.seq = 96
    for (i = 14; i < 96; i++) expect_pkt.push_back(tx_pkt[i]);
    report("T5");
    chk("T5: 100 bytes out (96 + 4)", rx_pkt.size() == 100);
    chk("T5: the stamped tag holds the received length, tail shifted",
        first_diff() == -2);
    chk("T5: packet_length == 96", o_plen == 16'd96);

    // ---- T6/T7: a frame that fits ENTIRELY inside the header region ------
    // The regression bug these exist for: the output is oimg[0..tx_pstart)
    // followed by the payload buffer, and that buffer only ever holds the
    // bytes PAST the header region. For a frame this short it is empty, but
    // TX still asked it for a beat and waited forever -- wedging the slot ring
    // behind it, so the whole link stalled on one short packet. Every earlier
    // case here is 64 bytes, which at the 256-bit default always leaves
    // payload; the same frame at 512 does not, which is how this surfaced.
    hdr_region = dut.HDR_MAX_BYTES;

    $display("\n== T6: insert_one on a %0d B frame -- no payload at all ==", hdr_region);
    run_one(16'h0001, hdr_region, 0);
    expect_pkt.delete();
    for (i = 0; i < 14; i++) expect_pkt.push_back(tx_pkt[i]);        // ethernet
    expect_pkt.push_back(8'hAA); expect_pkt.push_back(8'h01);        // tag.magic
    expect_pkt.push_back(8'h11); expect_pkt.push_back(8'h11);        // tag.seq
    for (i = 14; i < hdr_region; i++) expect_pkt.push_back(tx_pkt[i]);
    report("T6");
    chk("T6: hdr_delta == 4", seen_delta == 4);
    chk("T6: the frame came out at all (it used to wedge TX)", rx_pkt.size() > 0);
    chk("T6: grew by exactly 4", rx_pkt.size() == hdr_region + 4);
    chk("T6: byte-for-byte correct", first_diff() == -2);

    $display("\n== T7: strip_vlan on a %0d B frame -- no payload at all ==", hdr_region);
    run_one(16'h0003, hdr_region, 1);
    expect_pkt.delete();
    for (i = 0; i < 14; i++) expect_pkt.push_back(tx_pkt[i]);        // ethernet
    for (i = 18; i < hdr_region; i++) expect_pkt.push_back(tx_pkt[i]);
    report("T7");
    chk("T7: hdr_delta == -4", seen_delta == -4);
    chk("T7: shrank by exactly 4", rx_pkt.size() == hdr_region - 4);
    chk("T7: byte-for-byte correct", first_diff() == -2);

    // A following packet must still flow: the old failure did not just lose
    // the short packet, it stopped the link, so the NEXT one never came out.
    $display("\n== T8: a normal frame still flows afterwards ==");
    run_one(16'h0004, 64, 0);
    expect_pkt = tx_pkt;
    report("T8");
    chk("T8: 64 bytes out after the short frames", rx_pkt.size() == 64);
    chk("T8: byte-for-byte identical", first_diff() == -2);

    $display("\n================================================================");
    $display("  Results: %0d passed, %0d failed  (total %0d)", pass_cnt, fail_cnt, pass_cnt+fail_cnt);
    $display("================================================================");
    if (fail_cnt == 0) $display("  ALL TESTS PASSED");
    else                $display("  SOME TESTS FAILED");
    $finish;
  end

endmodule
