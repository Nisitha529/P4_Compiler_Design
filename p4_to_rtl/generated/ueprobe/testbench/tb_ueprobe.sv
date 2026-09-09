// ============================================================================
// tb_ueprobe.sv -- UserExtern support: does the compiler honour the declared
// fixed_latency_in_cycles, and does it hold the REST of the packet context in
// step across it?
//
// ueprobe.p4 declares two chained UserExterns with DIFFERENT latencies:
//     UserExtern<bit<48>, bit<16>>(3) my_lookup;    // eth.dst  -> meta.res
//     UserExtern<bit<16>, bit<8>>(1)  my_classify;  // eth.etype-> meta.res2
// so the pipeline must absorb 3 cycles, then 1 more.
//
// The generated placeholder bodies are the identity delayed by the declared
// latency, which is what makes this testable end-to-end WITHOUT knowing
// anything about the block: if the staging is correct then, for every packet,
//     out_meta_res  == out_eth_dst[15:0]
//     out_meta_res2 == out_eth_etype[7:0]
// Those two equalities are the whole contract. They pair a value that travelled
// THROUGH the extern against a value that travelled AROUND it through the
// normal pipeline registers, so they hold only if both took exactly the same
// number of cycles. An off-by-one in either direction breaks them.
//
// T3 is the test that matters most: a continuous back-to-back stream with a
// different payload every cycle. Latency being right on an isolated packet is
// easy; staying in step under full-rate traffic is what proves the context is
// actually being carried, not just delayed.
//
// Compile:
//   iverilog -g2012 -o sim tb_ueprobe.sv ../processing_generated.sv \
//     ../my_lookup_user_extern.sv ../my_classify_user_extern.sv
//   vvp sim
// ============================================================================
`timescale 1ns/1ps

module tb_ueprobe;

  localparam CLK_T = 10;
  logic clk = 0;
  always #(CLK_T/2) clk = ~clk;
  logic rst_n;

  logic        valid_in = 0;
  logic        eth_valid = 1;
  logic [47:0] eth_dst = 0, eth_src = 0;
  logic [15:0] eth_etype = 0;
  logic [15:0] meta_res_in = 0;
  logic  [7:0] meta_res2_in = 0;

  logic        o_eth_valid, valid_out, drop;
  logic [47:0] o_eth_dst, o_eth_src;
  logic [15:0] o_eth_etype, o_meta_res;
  logic  [7:0] o_meta_res2;

  processing_generated dut (
    .clk(clk), .rst_n(rst_n), .valid_in(valid_in),
    .eth_valid(eth_valid),
    .eth_dst(eth_dst), .eth_src(eth_src), .eth_etype(eth_etype),
    .meta_res(meta_res_in), .meta_res2(meta_res2_in),
    .out_eth_valid(o_eth_valid),
    .out_eth_dst(o_eth_dst), .out_eth_src(o_eth_src),
    .out_eth_etype(o_eth_etype),
    .out_meta_res(o_meta_res), .out_meta_res2(o_meta_res2),
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

  int latency_measured;
  int seen, bad;

  initial begin
    $display("\n== tb_ueprobe: UserExtern latency + context lockstep ==\n");
    do_reset();

    // ---- T1: measure the pipeline depth -----------------------------------
    // my_lookup(3) then my_classify(1) -> 4 register hops before valid_out.
    $display("== T1: declared latency is actually inserted ==");
    eth_dst = 48'hAABBCCDD1234; eth_etype = 16'h0899;
    valid_in = 1; @(posedge clk); #1; valid_in = 0;
    latency_measured = 0;
    while (!valid_out && latency_measured < 20) begin
      @(posedge clk); #1;
      latency_measured = latency_measured + 1;
    end
    chk("T1: valid_out arrives after 4 cycles (3 + 1)", latency_measured == 4);
    chk("T1: valid_out asserted", valid_out === 1'b1);

    // ---- T2: the extern result is what the block actually produced --------
    // Placeholder body = identity delayed; so meta.res must be eth.dst[15:0]
    // of THIS packet, and meta.res2 must be eth.etype[7:0] of THIS packet.
    $display("\n== T2: extern results pair with their own packet ==");
    chk("T2: out_meta_res  == eth_dst[15:0]",   o_meta_res  === 16'h1234);
    chk("T2: out_meta_res2 == eth_etype[7:0]",  o_meta_res2 === 8'h99);
    chk("T2: header travelled with it",         o_eth_dst   === 48'hAABBCCDD1234);
    @(posedge clk); #1;
    chk("T2: valid_out deasserts",              valid_out === 1'b0);

    // ---- T3: full-rate back-to-back stream --------------------------------
    // A different payload every cycle. If the compiler were not holding the
    // packet context in step across the two externs, a packet's metadata would
    // pair with a NEIGHBOUR's header and these invariants would break.
    $display("\n== T3: back-to-back stream stays in lockstep ==");
    do_reset();
    seen = 0;
    bad  = 0;
    // One loop: drive a new payload every cycle, and check the far end on the
    // same cycle. 8 extra idle iterations let the pipeline drain.
    for (int i = 1; i <= 40; i++) begin
      if (i <= 32) begin
        eth_dst   = {32'hAABBCCDD, 16'd0 + i[15:0]};
        eth_etype = 16'h0800 + i[15:0];
        valid_in  = 1;
      end else begin
        valid_in  = 0;
      end
      @(posedge clk); #1;
      if (valid_out) begin
        seen = seen + 1;
        if (o_meta_res  !== o_eth_dst[15:0])  bad = bad + 1;
        if (o_meta_res2 !== o_eth_etype[7:0]) bad = bad + 1;
      end
    end
    chk($sformatf("T3: all packets in lockstep (%0d mismatches)", bad), bad == 0);
    chk($sformatf("T3: every packet came out (%0d/32)", seen), seen == 32);

    $display("\n================================================================");
    $display("  Results: %0d passed, %0d failed  (total %0d)",
             pass_cnt, fail_cnt, pass_cnt + fail_cnt);
    $display("================================================================");
    if (fail_cnt == 0) $display("  ALL TESTS PASSED");
    else                $display("  SOME TESTS FAILED");
    $finish;
  end

endmodule
