// ============================================================================
// tb_fiveTuple_parser_verify.sv -- P4 `verify()` in the generated parser FSM.
//
// fiveTuple.p4 declares two verifies:
//     state parse_ipv4 { verify(hdr.ipv4.version == 4 && hdr.ipv4.hdr_len >= 5,
//                              error.InvalidIPpacket); }   // -> 4'd8
//     state parse_tcp  { verify(hdr.tcp.dataOffset >= 5,
//                              error.InvalidTCPpacket); }  // -> 4'd9
// The error codes are the values p4c assigns in the flattened error enum
// (core.p4's 8 standard errors first, so the program's own start at 8).
//
// What this checks:
//   * a well-formed packet parses to ACCEPT with parser_error == NoError
//   * a malformed IPv4 header diverts to REJECT with InvalidIPpacket
//   * a malformed TCP header diverts to REJECT with InvalidTCPpacket
//   * REJECT still asserts `done`, so a bad packet DRAINS rather than
//     stalling the pipeline -- this is the property most likely to be got
//     wrong, and a stall would hang a real design
//   * the error latches and then clears for the next packet
//
// SCOPE NOTE: parser_generated is a standalone module. No generated top
// instantiates it -- the XSA top extracts header fields itself at fixed
// offsets from the packet buffer -- so this verifies the parser FSM, not an
// end-to-end path from packet to standard_metadata.parser_error.
//
// Compile:
//   iverilog -g2012 -o sim tb_fiveTuple_parser_verify.sv ../parser_generated.sv
//   vvp sim
// ============================================================================
`timescale 1ns/1ps

module tb_fiveTuple_parser_verify;

  localparam CLK_T = 10;
  logic clk = 0;
  always #(CLK_T/2) clk = ~clk;
  logic rst_n;

  localparam [3:0] ERR_NONE        = 4'd0;
  localparam [3:0] ERR_INVALID_IP  = 4'd8;
  localparam [3:0] ERR_INVALID_TCP = 4'd9;

  logic        valid_in = 0;
  logic [15:0] eth_type = 16'h0800;
  logic  [3:0] ipv4_hdr_len = 4'd5;
  logic  [7:0] ipv4_protocol = 8'd6;
  logic  [3:0] ipv4_version = 4'd4;
  logic  [3:0] tcp_dataOffset = 4'd5;
  logic [15:0] vlan_tpid = 16'h0800;

  logic extract_eth, extract_ipv4, extract_ipv4opt, extract_tcp;
  logic extract_tcpopt, extract_udp, extract_vlan, done;
  logic [3:0] parser_error;

  parser_generated dut (
    .clk(clk), .rst_n(rst_n), .valid_in(valid_in),
    .eth_type(eth_type), .ipv4_hdr_len(ipv4_hdr_len),
    .ipv4_protocol(ipv4_protocol), .ipv4_version(ipv4_version),
    .tcp_dataOffset(tcp_dataOffset), .vlan_tpid(vlan_tpid),
    .extract_eth(extract_eth), .extract_ipv4(extract_ipv4),
    .extract_ipv4opt(extract_ipv4opt), .extract_tcp(extract_tcp),
    .extract_tcpopt(extract_tcpopt), .extract_udp(extract_udp),
    .extract_vlan(extract_vlan),
    .parser_error(parser_error), .done(done)
  );

  int pass_cnt = 0, fail_cnt = 0;
  task automatic chk(input string name, input logic cond);
    if (cond) begin $display("    [PASS] %s", name); pass_cnt++; end
    else      begin $display("    [FAIL] %s", name); fail_cnt++; end
  endtask

  task do_reset;
    rst_n = 0; valid_in = 0;
    repeat(5) @(posedge clk); @(negedge clk);
    rst_n = 1; @(posedge clk); #1;
  endtask

  // Run the FSM until `done`, up to a generous bound. Returns cycles taken in
  // `cycles`; `timed_out` is the property a stall would violate.
  int cycles;
  logic timed_out;
  task automatic run_packet;
    valid_in = 1;
    cycles = 0;
    timed_out = 1'b0;
    @(posedge clk); #1;          // leave the idle/ACCEPT sentinel
    while (!done && cycles < 12) begin
      @(posedge clk); #1;
      cycles = cycles + 1;
    end
    if (!done) timed_out = 1'b1;
    valid_in = 0;
  endtask

  initial begin
    $display("\n== tb_fiveTuple_parser_verify: P4 verify() in the parser FSM ==\n");

    // ---- T1: well-formed IPv4/TCP ----------------------------------------
    $display("== T1: well-formed packet parses cleanly ==");
    do_reset();
    ipv4_version = 4'd4; ipv4_hdr_len = 4'd5; tcp_dataOffset = 4'd5;
    run_packet();
    chk("T1: reached done",                 !timed_out);
    chk("T1: parser_error == NoError",      parser_error === ERR_NONE);

    // ---- T2: bad IP version -> InvalidIPpacket ---------------------------
    $display("\n== T2: ipv4.version != 4 -> REJECT, InvalidIPpacket ==");
    do_reset();
    ipv4_version = 4'd6;          // verify fails
    run_packet();
    chk("T2: still reached done (REJECT drains, no stall)", !timed_out);
    chk("T2: parser_error == InvalidIPpacket",
        parser_error === ERR_INVALID_IP);

    // ---- T3: bad IHL -> same error (second half of the && ) ---------------
    $display("\n== T3: ipv4.hdr_len < 5 -> REJECT, InvalidIPpacket ==");
    do_reset();
    ipv4_version = 4'd4; ipv4_hdr_len = 4'd3;
    run_packet();
    chk("T3: reached done",                 !timed_out);
    chk("T3: parser_error == InvalidIPpacket",
        parser_error === ERR_INVALID_IP);

    // ---- T4: bad TCP dataOffset -> InvalidTCPpacket -----------------------
    // IPv4 must be VALID here, so the FSM actually reaches parse_tcp -- this
    // also proves the first verify did not fire.
    $display("\n== T4: tcp.dataOffset < 5 -> REJECT, InvalidTCPpacket ==");
    do_reset();
    ipv4_version = 4'd4; ipv4_hdr_len = 4'd5; ipv4_protocol = 8'd6;
    tcp_dataOffset = 4'd2;
    run_packet();
    chk("T4: reached done",                 !timed_out);
    chk("T4: parser_error == InvalidTCPpacket",
        parser_error === ERR_INVALID_TCP);

    // ---- T5: the error does not leak into the next packet -----------------
    $display("\n== T5: error clears for the following packet ==");
    ipv4_version = 4'd4; ipv4_hdr_len = 4'd5; tcp_dataOffset = 4'd5;
    run_packet();
    chk("T5: reached done",                 !timed_out);
    chk("T5: back to NoError",              parser_error === ERR_NONE);

    $display("\n================================================================");
    $display("  Results: %0d passed, %0d failed  (total %0d)",
             pass_cnt, fail_cnt, pass_cnt + fail_cnt);
    $display("================================================================");
    if (fail_cnt == 0) $display("  ALL TESTS PASSED");
    else                $display("  SOME TESTS FAILED");
    $finish;
  end

endmodule
