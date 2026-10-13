// ============================================================================
// tb_rawprobe.sv -- the reported Register READ-AFTER-WRITE DISTANCE, measured.
//
// rawprobe.p4 reads last_ts at stage 0, applies a table, then writes back at
// stage 2, so the compiler reports:
//
//   [INFO] Register 'last_ts': RAW distance 3 packet(s)
//          (read stage 0, write-back stage 2)
//
// The claim that number makes is specific: a packet sees an earlier packet's
// write only if it entered the pipeline at least 3 cycles later. Anything
// closer reads the PRE-update value. Nothing tested that -- the number was
// printed and believed -- so this drives two packets at the SAME register
// index exactly d cycles apart, for d = 1..4, and checks which ones see the
// update.
//
// The write is `last_ts.write(idx, prev + 1)`, so a packet that sees the
// update reads 1 and one that does not reads 0.
//
//   d = 1, 2  -> stale (reads 0): closer than the distance
//   d = 3, 4  -> fresh (reads 1): at or beyond it
//
// Driven at the MODULE level, not through the shell: the point is exact packet
// spacing, and the shell's slot ring and cut-through issue decide that for
// itself. --register-ram adds a cycle to the read, which moves the boundary,
// so the expected values are parameterised by RAW_D rather than hardcoded.
//
//   iverilog -g2012 -o sim tb_rawprobe.sv ../rawprobe_pkg.sv \
//     $(ls ../*.sv | grep -v _pkg) && vvp sim
// ============================================================================
`timescale 1ns/1ps

module tb_rawprobe;

  // The distance the compiler reported for this build:
  //   default (asynchronous read)      -> 3   [read stage 0, write-back 2]
  //   --register-ram (synchronous read) -> 4   [read stage 1, write-back 3]
  // The synchronous case is one MORE than the write-minus-read span suggests,
  // because the read address is presented a stage early and the memory is
  // sampled at that earlier edge. This testbench is what established that:
  // the compiler used to report 3 for both modes, and RAW_D=3 fails here in
  // --register-ram mode while RAW_D=4 passes. Re-check with:
  //   python3 compiler/main.py rawprobe --register-ram
  //   iverilog -g2012 -Ptb_rawprobe.RAW_D=4 ...
  parameter int RAW_D = 3;

  localparam CLK_T = 10;
  logic clk = 0;
  always #(CLK_T/2) clk = ~clk;
  logic rst_n;

  logic        valid_in = 0;
  logic        eth_valid = 1;
  logic [47:0] eth_dst = 48'hAABBCCDDEEFF, eth_src = 48'h112233445566;
  logic [15:0] eth_etype = 16'd7;        // the register index
  logic [31:0] meta_prev = 0;
  logic [15:0] meta_idx  = 0;

  logic        out_eth_valid, out_valid, valid_out, drop;
  logic [47:0] out_eth_dst, out_eth_src;
  logic [15:0] out_eth_etype, out_meta_idx;
  logic [31:0] out_meta_prev;
  logic  [8:0] out_std_meta_egress_port;

  logic        fwd_cp_wr_en = 0;
  logic  [3:0] fwd_cp_wr_idx = 0;
  logic [15:0] fwd_cp_wr_key_etype = 0;
  logic  [0:0] fwd_cp_wr_action = 0;
  logic  [8:0] fwd_cp_wr_p_p = 0;
  logic        fwd_hit_out;

  processing_generated dut (
    .clk(clk), .rst_n(rst_n), .valid_in(valid_in),
    .eth_valid(eth_valid), .eth_dst(eth_dst), .eth_src(eth_src),
    .eth_etype(eth_etype),
    .meta_prev(meta_prev), .meta_idx(meta_idx),
    .out_eth_valid(out_eth_valid), .out_eth_dst(out_eth_dst),
    .out_eth_src(out_eth_src), .out_eth_etype(out_eth_etype),
    .out_std_meta_egress_port(out_std_meta_egress_port),
    .out_meta_prev(out_meta_prev), .out_meta_idx(out_meta_idx),
    .fwd_cp_wr_en(fwd_cp_wr_en), .fwd_cp_wr_idx(fwd_cp_wr_idx),
    .fwd_cp_wr_key_etype(fwd_cp_wr_key_etype),
    .fwd_cp_wr_action(fwd_cp_wr_action), .fwd_cp_wr_p_p(fwd_cp_wr_p_p),
    .fwd_hit_out(fwd_hit_out),
    .out_valid(out_valid), .valid_out(valid_out), .drop(drop)
  );

  int pass_cnt = 0, fail_cnt = 0;
  task automatic chk(input string name, input logic cond);
    if (cond) begin $display("    [PASS] %s", name); pass_cnt++; end
    else      begin $display("    [FAIL] %s", name); fail_cnt++; end
  endtask

  // Capture out_meta_prev for each packet as it leaves.
  logic [31:0] seen [$];
  always @(posedge clk) if (rst_n && out_valid) seen.push_back(out_meta_prev);

  task do_reset;
    rst_n = 0; valid_in = 0;
    repeat (5) @(posedge clk); @(negedge clk);
    rst_n = 1; @(posedge clk); #1;
  endtask

  // Two packets at the same register index, exactly `d` cycles apart.
  task automatic two_at(input int d);
    seen.delete();
    @(negedge clk);
    valid_in = 1'b1; @(posedge clk); #1;        // packet A
    valid_in = 1'b0;
    repeat (d - 1) begin @(posedge clk); #1; end
    @(negedge clk);
    valid_in = 1'b1; @(posedge clk); #1;        // packet B, d cycles after A
    valid_in = 1'b0;
    repeat (20) @(posedge clk);
  endtask

  int d;

  initial begin
    $display("\n================================================================");
    $display("  rawprobe -- Register read-after-write distance (reported: %0d)", RAW_D);
    $display("================================================================");

    for (d = 1; d <= 4; d++) begin
      do_reset();                      // each case starts from a zeroed register
      two_at(d);
      $display("\n  spacing %0d cycle(s): %0d packet(s) out, B read %0d",
               d, seen.size(), (seen.size() > 1 ? seen[1] : 32'hDEAD));
      if (seen.size() > 1) $display("      A read %0d, B read %0d", seen[0], seen[1]);
      chk($sformatf("d=%0d: both packets came out", d), seen.size() == 2);
      if (seen.size() > 1) begin
        // Compared to A's own read, not to a constant. The register memory is
        // only zeroed by the simulation-time-0 initial block, NOT by reset, so
        // its absolute value carries across these cases -- expecting literal
        // 0 and 1 measured the accumulated history instead of the hazard.
        if (seen[1] == seen[0])
          $display("      B read the same value as A -> STALE");
        else if (seen[1] == seen[0] + 32'd1)
          $display("      B read A's value + 1       -> FRESH (saw A's write)");
        else
          $display("      B read %0d vs A %0d        -> UNEXPECTED",
                   seen[1], seen[0]);
        if (d < RAW_D)
          chk($sformatf("d=%0d (< %0d): B is STALE", d, RAW_D),
              seen[1] == seen[0]);
        else
          chk($sformatf("d=%0d (>= %0d): B is FRESH", d, RAW_D),
              seen[1] == seen[0] + 32'd1);
      end
    end

    $display("\n================================================================");
    $display("  Results: %0d passed, %0d failed  (total %0d)", pass_cnt, fail_cnt, pass_cnt+fail_cnt);
    $display("================================================================");
    if (fail_cnt == 0) $display("  ALL TESTS PASSED");
    else                $display("  SOME TESTS FAILED");
    $finish;
  end

  initial begin #200000; $display("[TIMEOUT]"); $finish; end

endmodule
