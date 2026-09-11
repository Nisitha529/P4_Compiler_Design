// ============================================================================
// tb_smprobe.sv -- the architecture's own standard_metadata must survive at
// full declared width, and `error.*` constants must be real numbers.
//
// The load-bearing check is T1: a bit<64> timestamp whose value has bits set
// ABOVE bit 8. Under the compiler's old hardcoded v1model width table every
// unrecognised standard_metadata field defaulted to 9 bits, so this value
// could not round-trip -- the test fails by construction if that regresses.
//
// Compile:
//   iverilog -g2012 -o sim tb_smprobe.sv ../processing_generated.sv
//   vvp sim
// ============================================================================
`timescale 1ns/1ps

module tb_smprobe;

  localparam CLK_T = 10;
  logic clk = 0;
  always #(CLK_T/2) clk = ~clk;
  logic rst_n;

  logic        valid_in = 0, eth_valid = 1;
  logic [47:0] eth_dst = 48'h001122334455, eth_src = 48'h665544332211;
  logic [15:0] eth_etype = 16'h0800;
  logic [63:0] meta_ts_in = 0;
  logic [15:0] meta_nbytes_in = 0;
  logic [63:0] sm_ts = 0;
  logic [15:0] sm_bytes = 0;
  logic  [2:0] sm_err = 0;

  logic        o_eth_valid, valid_out, drop;
  logic [47:0] o_eth_dst, o_eth_src;
  logic [15:0] o_eth_etype, o_nbytes;
  logic [63:0] o_ts;

  processing_generated dut (
    .clk(clk), .rst_n(rst_n), .valid_in(valid_in),
    .eth_valid(eth_valid),
    .eth_dst(eth_dst), .eth_src(eth_src), .eth_etype(eth_etype),
    .meta_ts(meta_ts_in), .meta_nbytes(meta_nbytes_in),
    .std_meta_ingress_timestamp(sm_ts),
    .std_meta_parsed_bytes(sm_bytes),
    .std_meta_parser_error(sm_err),
    .out_eth_valid(o_eth_valid),
    .out_eth_dst(o_eth_dst), .out_eth_src(o_eth_src), .out_eth_etype(o_eth_etype),
    .out_meta_ts(o_ts), .out_meta_nbytes(o_nbytes),
    .valid_out(valid_out), .drop(drop)
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

  initial begin
    $display("\n== tb_smprobe: architecture-driven standard metadata ==\n");
    do_reset();

    // ---- T1: bit<64> survives at full width ------------------------------
    $display("== T1: ingress_timestamp is bit<64>, not the old 9-bit default ==");
    sm_ts = 64'hDEAD_BEEF_CAFE_BABE;
    valid_in = 1; @(posedge clk); #1;
    chk("T1: all 64 bits round-trip", o_ts === 64'hDEAD_BEEF_CAFE_BABE);
    chk("T1: high word intact (would be 0 if truncated to 9 bits)",
        o_ts[63:32] === 32'hDEAD_BEEF);

    // ---- T2: bit<16> field -------------------------------------------------
    $display("\n== T2: parsed_bytes is bit<16> ==");
    sm_bytes = 16'hBEEF; @(posedge clk); #1;
    chk("T2: all 16 bits round-trip", o_nbytes === 16'hBEEF);

    // ---- T3: the `error` enum is a real number ----------------------------
    // `if (smeta.parser_error != error.NoError) smeta.drop = 1;`
    // error.NoError must have become a numeric literal; if it reached the RTL
    // verbatim this design would not have elaborated at all.
    $display("\n== T3: error.* constants resolve to numbers ==");
    sm_err = 3'd0; @(posedge clk); #1;
    chk("T3: parser_error == NoError -> no drop", drop === 1'b0);
    sm_err = 3'd1; @(posedge clk); #1;
    chk("T3: parser_error == PacketTooShort -> drop", drop === 1'b1);
    sm_err = 3'd7; @(posedge clk); #1;
    chk("T3: parser_error == 7 -> drop", drop === 1'b1);
    sm_err = 3'd0; @(posedge clk); #1;
    chk("T3: back to NoError -> no drop", drop === 1'b0);

    valid_in = 0;
    $display("\n================================================================");
    $display("  Results: %0d passed, %0d failed  (total %0d)",
             pass_cnt, fail_cnt, pass_cnt + fail_cnt);
    $display("================================================================");
    if (fail_cnt == 0) $display("  ALL TESTS PASSED");
    else                $display("  SOME TESTS FAILED");
    $finish;
  end

endmodule
