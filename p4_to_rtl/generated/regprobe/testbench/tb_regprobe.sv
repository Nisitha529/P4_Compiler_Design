// ============================================================================
// tb_regprobe.sv -- FUNCTIONAL verification of `register` on the p4test/XSA
// front-end, in BOTH read modes.
//
// This closes a real hole. `--register-ram` (synchronous, BRAM-inferable
// reads) was verified functionally only on the firewall, which is a bmv2-path
// app; on the XSA path it had been checked structurally -- emitted RTL shape,
// and a real quartus_map showing altsyncram inference -- but never actually
// simulated. regprobe.p4 is the only XSA app with a register, so this is the
// only place that can cover it.
//
// regprobe.p4:
//     if (hdr.eth.etype == 0x0800)
//         bloom_1.write(hdr.eth.src[31:0], hdr.eth.dst[0:0]);
//     bloom_1.read(meta.v1, hdr.eth.dst[31:0]);
// Note the write ADDRESS comes from src and the read address from dst, and the
// write DATA is dst[0] -- so a test can write a chosen bit to a chosen slot and
// read any slot back independently.
//
// Build BOTH ways; both must pass. `PIPE_EXTRA` absorbs the extra stage the
// synchronous read costs (one boundary per register read):
//
//   # default (asynchronous read)
//   iverilog -g2012 -o sim tb_regprobe.sv ../processing_generated.sv
//   vvp sim
//
//   # --register-ram (synchronous read, +1 stage)
//   iverilog -g2012 -DPIPE_EXTRA=1 -o sim_ram tb_regprobe.sv <ram build>.sv
//   vvp sim_ram
// ============================================================================
`timescale 1ns/1ps
`ifndef PIPE_EXTRA
  `define PIPE_EXTRA 0
`endif

module tb_regprobe;

  localparam CLK_T = 10;
  logic clk = 0;
  always #(CLK_T/2) clk = ~clk;
  logic rst_n;

  logic        valid_in = 0, eth_valid = 1;
  logic [47:0] eth_dst = 0, eth_src = 0;
  logic [15:0] eth_etype = 16'h0800;
  logic  [0:0] meta_v1_in = 0;
  logic [31:0] meta_pos_in = 0;

  logic        o_eth_valid, valid_out, drop;
  logic [47:0] o_eth_dst, o_eth_src;
  logic [15:0] o_eth_etype;
  logic  [0:0] o_v1;
  logic [31:0] o_pos;

  processing_generated dut (
    .clk(clk), .rst_n(rst_n), .valid_in(valid_in),
    .eth_valid(eth_valid),
    .eth_dst(eth_dst), .eth_src(eth_src), .eth_etype(eth_etype),
    .meta_v1(meta_v1_in), .meta_pos(meta_pos_in),
    .out_eth_valid(o_eth_valid),
    .out_eth_dst(o_eth_dst), .out_eth_src(o_eth_src), .out_eth_etype(o_eth_etype),
    .out_meta_v1(o_v1), .out_meta_pos(o_pos),
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

  // Drive one packet and let it drain, including the extra stage the
  // synchronous read costs and one more edge for the write to commit.
  //
  // CAREFUL: in regprobe.p4 eth.dst is BOTH the read address and (in bit 0)
  // the write data, so those two are not independent. `raddr` and `wdata`
  // below are combined as {raddr[31:1], wdata} -- i.e. wdata REPLACES bit 0 of
  // the read address. To read an even slot you must pass wdata=0, and to write
  // a 1 you must be reading an odd slot that packet. Getting this wrong reads
  // a neighbouring slot and looks exactly like a compiler bug.
  task automatic send(input [31:0] waddr, input [31:0] raddr, input bit wdata,
                      input [15:0] etype);
    eth_src   = {16'h0000, waddr};
    eth_dst   = {16'h0000, raddr[31:1], wdata};
    eth_etype = etype;
    valid_in  = 1;
    repeat(4 + `PIPE_EXTRA) begin @(posedge clk); #1; end
    valid_in = 0;
    @(posedge clk); #1;
  endtask

  initial begin
    $display("\n== tb_regprobe: register on the XSA path (PIPE_EXTRA=%0d) ==\n",
             `PIPE_EXTRA);
    do_reset();

    // ---- T1: write a 1, read it back -------------------------------------
    // Note the read address must have bit0 = the data we wrote, because the
    // app derives write-data from dst[0]; use even/odd addresses accordingly.
    $display("== T1: write 1 at slot 0x101, read it back ==");
    send(32'h101, 32'h101, 1'b1, 16'h0800);   // writes mem[0x101] = 1
    send(32'h000, 32'h101, 1'b1, 16'h0800);   // read 0x101 (writes 0x000 too)
    chk("T1: read-back of a written 1", o_v1 === 1'b1);

    // ---- T2: an untouched slot still reads 0 ------------------------------
    $display("\n== T2: never-written slot reads 0 ==");
    send(32'h000, 32'h7FE, 1'b0, 16'h0800);
    chk("T2: untouched slot is 0", o_v1 === 1'b0);

    // ---- T3: the write is gated on etherType ------------------------------
    // Non-IPv4 must NOT write, so a slot written only under a non-IPv4 packet
    // must still read 0.
    $display("\n== T3: write is gated by `if (etype == 0x0800)` ==");
    send(32'h205, 32'h205, 1'b1, 16'h8100);   // NOT IPv4 -> must not write
    send(32'h000, 32'h205, 1'b1, 16'h0800);   // read it
    chk("T3: no write happened under non-IPv4", o_v1 === 1'b0);
    send(32'h205, 32'h205, 1'b1, 16'h0800);   // now DO write it
    send(32'h000, 32'h205, 1'b1, 16'h0800);
    chk("T3: same slot written once etype is IPv4", o_v1 === 1'b1);

    // ---- T4: write data is real, not a constant 1 -------------------------
    // Writing 0 over a slot that held 1 must clear it.
    $display("\n== T4: write data is data-dependent (dst[0]), not constant ==");
    // Write 1 into slot 0x300: the writing packet must itself carry an odd
    // dst so that dst[0] (the write data) is 1 -- 0x301 here.
    send(32'h300, 32'h301, 1'b1, 16'h0800);   // mem[0x300] <= 1
    // Read slot 0x300: dst must equal 0x300 exactly, which forces wdata=0;
    // the harmless write lands in slot 0x000.
    send(32'h000, 32'h300, 1'b0, 16'h0800);
    chk("T4: slot 0x300 holds 1", o_v1 === 1'b1);
    send(32'h300, 32'h300, 1'b0, 16'h0800);   // mem[0x300] <= 0 (dst[0]=0)
    send(32'h000, 32'h300, 1'b0, 16'h0800);
    chk("T4: slot 0x300 cleared to 0", o_v1 === 1'b0);

    // ---- T5: headers still pass through -----------------------------------
    $display("\n== T5: register access does not disturb the packet ==");
    chk("T5: eth_dst passed through", o_eth_dst === eth_dst);
    chk("T5: no spurious drop",       drop === 1'b0);

    $display("\n================================================================");
    $display("  Results: %0d passed, %0d failed  (total %0d)",
             pass_cnt, fail_cnt, pass_cnt + fail_cnt);
    $display("================================================================");
    if (fail_cnt == 0) $display("  ALL TESTS PASSED");
    else                $display("  SOME TESTS FAILED");
    $finish;
  end

endmodule
