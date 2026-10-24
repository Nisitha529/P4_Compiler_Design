// tb_mdio_master.sv -- the MDIO master against an independent clause 22 slave.
//
// Checks the things that make a bring-up design fail silently on hardware:
// bit order, the read turnaround, that a write actually lands, and that an
// address with no PHY is reported as "no reply" rather than as data.
`timescale 1ns/1ps

module tb_mdio_master;

  localparam int CLK_HZ = 50_000_000;
  localparam int MDC_HZ = 2_500_000;        // 20 clk per MDC period

  logic clk = 0;
  always #10 clk = ~clk;                    // 50 MHz
  logic rst = 1;

  logic        start = 0, we = 0;
  logic [4:0]  phy_ad = 5'h10, reg_ad = 0;
  logic [15:0] wdata = 0, rdata;
  logic        done, busy, no_reply;
  logic        mdc, mdio_o, mdio_oe;
  logic        phy_o, phy_oe;

  // The wire: whoever drives wins, pulled up when nobody does. This models
  // the real open-drain net, so a master that forgets to release during
  // turnaround would corrupt the PHY's data here too.
  wire mdio_net = mdio_oe ? mdio_o : (phy_oe ? phy_o : 1'b1);

  mdio_master #(.CLK_HZ(CLK_HZ), .MDC_HZ(MDC_HZ)) dut (
    .clk(clk), .rst(rst), .start(start), .we(we),
    .phy_ad(phy_ad), .reg_ad(reg_ad), .wdata(wdata),
    .rdata(rdata), .done(done), .busy(busy), .no_reply(no_reply),
    .mdc(mdc), .mdio_o(mdio_o), .mdio_oe(mdio_oe), .mdio_i(mdio_net)
  );

  mdio_phy_model #(.PHY_ADDR(5'h10)) phy (
    .mdc(mdc), .mdio_i(mdio_net), .mdio_oe_m(mdio_oe),
    .mdio_o(phy_o), .mdio_oe(phy_oe)
  );

  int pass_cnt = 0, fail_cnt = 0;
  task automatic chk(input string name, input logic cond);
    if (cond) begin $display("    [PASS] %s", name); pass_cnt++; end
    else      begin $display("    [FAIL] %s", name); fail_cnt++; end
  endtask

  task automatic xact(input logic is_we, input logic [4:0] pa,
                      input logic [4:0] ra, input logic [15:0] wd);
    @(negedge clk);
    we = is_we; phy_ad = pa; reg_ad = ra; wdata = wd; start = 1'b1;
    @(negedge clk); start = 1'b0;
    @(posedge done);
    @(negedge clk);
  endtask

  initial begin
    $display("\n================================================================");
    $display("  tb_mdio_master: clause 22 MDIO against an independent slave");
    $display("================================================================");
    // The 88E1111's identity registers, as the DE2-115 manual's PHY would
    // report them. The VALUES are the testbench's choice: what is under test
    // is that the master transports them intact.
    phy.set_reg(2, 16'h0141);
    phy.set_reg(3, 16'h0CC2);
    phy.set_reg(1, 16'h7949);     // BMSR: link up, autoneg complete
    phy.set_reg(17, 16'hB40C);    // 88E1111 PHY specific status

    repeat (5) @(posedge clk); rst = 0; repeat (5) @(posedge clk);

    $display("\n== reads return the register contents, MSB first ==");
    xact(1'b0, 5'h10, 5'd2, 16'h0000);
    $display("      reg 2 -> %04h (want 0141)", rdata);
    chk("read reg 2 = 0x0141", rdata === 16'h0141);
    chk("a PHY answered (turnaround driven low)", no_reply === 1'b0);

    xact(1'b0, 5'h10, 5'd3, 16'h0000);
    $display("      reg 3 -> %04h (want 0CC2)", rdata);
    chk("read reg 3 = 0x0CC2", rdata === 16'h0CC2);

    xact(1'b0, 5'h10, 5'd1, 16'h0000);
    chk("read reg 1 = 0x7949", rdata === 16'h7949);

    $display("\n== a write lands in the addressed register ==");
    xact(1'b1, 5'h10, 5'd20, 16'hBEEF);
    xact(1'b0, 5'h10, 5'd20, 16'h0000);
    $display("      wrote BEEF to reg 20, read back %04h", rdata);
    chk("write then read returns the written value", rdata === 16'hBEEF);

    $display("\n== an address with no PHY is reported, not guessed ==");
    xact(1'b0, 5'h07, 5'd2, 16'h0000);
    $display("      addr 7 -> rdata %04h, no_reply=%0b", rdata, no_reply);
    chk("no_reply is set when nothing answers", no_reply === 1'b1);

    $display("\n== and the real PHY is still found afterwards ==");
    xact(1'b0, 5'h10, 5'd2, 16'h0000);
    chk("addr 0x10 still reads 0x0141", rdata === 16'h0141 && no_reply === 1'b0);

    // No wait on mdc here: MDC is parked low between transactions, so a
    // @(posedge mdc) in an idle period never returns -- a deadlock in the
    // testbench, which is how the first version of this hung.
    $display("\n== the master leaves the wire released when idle ==");
    chk("MDIO is not driven by the master in idle", mdio_oe === 1'b0);
    chk("MDC is parked low in idle",                mdc === 1'b0);

    $display("\n================================================================");
    $display("  Results: %0d passed, %0d failed  (total %0d)", pass_cnt, fail_cnt, pass_cnt+fail_cnt);
    $display("================================================================");
    if (fail_cnt == 0) $display("  ALL TESTS PASSED");
    else                $display("  SOME TESTS FAILED");
    $finish;
  end

  initial begin #2000000; $display("[TIMEOUT]"); $finish; end

endmodule
