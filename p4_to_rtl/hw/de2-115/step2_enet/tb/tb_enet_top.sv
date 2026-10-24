// tb_enet_top.sv -- step 2 against a PHY model sitting at the address the
// DE2-115 user manual says ENET0 is strapped to.
//
// The point of these checks is that the design must FIND the PHY and report
// what it found, so the real board run tells you something you can act on.
// Timing parameters are scaled down so the 10 ms reset sequence does not take
// 10 ms of simulation.
`timescale 1ns/1ps

module tb_enet_top;

  // 50 kHz "CLK_HZ" => 1 ms is 50 cycles, so the reset sequence is short.
  localparam int CLK_HZ = 50_000;

  logic clk = 0;
  always #10 clk = ~clk;
  logic [3:0]  KEY = 4'hF;
  logic [17:0] SW  = '0;
  wire  [17:0] LEDR;
  wire  [8:0]  LEDG;
  wire  [6:0]  HEX0, HEX1, HEX2, HEX3, HEX4, HEX5, HEX6, HEX7;

  wire        ENET0_RST_N, ENET0_MDC, ENET1_RST_N;
  wire        ENET0_GTX_CLK, ENET0_TX_EN, ENET0_TX_ER;
  wire [3:0]  ENET0_TX_DATA;
  logic       rx_clk = 0;
  logic       rx_dv = 0;
  logic [3:0] rx_data = 0;

  // The MDIO wire, with the master and the PHY both able to drive it.
  wire mdio_net;
  wire phy_o, phy_oe;
  wire m_oe = dut.md_oe;
  wire m_o  = dut.md_o;
  assign mdio_net = m_oe ? m_o : (phy_oe ? phy_o : 1'b1);

  de2115_enet_top #(.CLK_HZ(CLK_HZ)) dut (
    .CLOCK_50(clk), .KEY(KEY), .SW(SW), .LEDR(LEDR), .LEDG(LEDG),
    .HEX0(HEX0), .HEX1(HEX1), .HEX2(HEX2), .HEX3(HEX3),
    .HEX4(HEX4), .HEX5(HEX5), .HEX6(HEX6), .HEX7(HEX7),
    .ENET0_RST_N(ENET0_RST_N), .ENET0_MDC(ENET0_MDC), .ENET0_MDIO(mdio_net),
    .ENET0_RX_CLK(rx_clk), .ENET0_RX_DV(rx_dv), .ENET0_RX_DATA(rx_data),
    .ENET0_RX_ER(1'b0), .ENET0_LINK100(1'b1), .ENET0_INT_N(1'b1),
    .ENET0_GTX_CLK(ENET0_GTX_CLK), .ENET0_TX_EN(ENET0_TX_EN),
    .ENET0_TX_DATA(ENET0_TX_DATA), .ENET0_TX_ER(ENET0_TX_ER),
    .ENET1_RST_N(ENET1_RST_N)
  );

  // The PHY answers only at 0x10, which is what the manual says ENET0's
  // straps select. Nothing else on the bus.
  mdio_phy_model #(.PHY_ADDR(5'h10)) phy (
    .mdc(ENET0_MDC), .mdio_i(mdio_net), .mdio_oe_m(m_oe),
    .mdio_o(phy_o), .mdio_oe(phy_oe)
  );

  int pass_cnt = 0, fail_cnt = 0;
  task automatic chk(input string name, input logic cond);
    if (cond) begin $display("    [PASS] %s", name); pass_cnt++; end
    else      begin $display("    [FAIL] %s", name); fail_cnt++; end
  endtask

  initial begin
    $display("\n================================================================");
    $display("  tb_enet_top: DE2-115 step 2 (Ethernet PHY bring-up)");
    $display("================================================================");
    phy.set_reg(2,  16'h0141);     // 88E1111 identifier, high
    phy.set_reg(3,  16'h0CC2);     // ...low, revision 2
    // BMSR built from NAMED bits rather than a plausible-looking hex literal:
    // the first version of this testbench used 0x7949 and called it "link up,
    // autoneg complete" when neither bit was actually set, so it accused the
    // design of a fault that was in the testbench.
    phy.set_reg(1,  16'h7800                 // 10/100 capability bits
                    | (16'd1 << 5)           // BMSR.5  auto-negotiation complete
                    | (16'd1 << 3)           // BMSR.3  auto-negotiation ability
                    | (16'd1 << 2)           // BMSR.2  link status: UP
                    | (16'd1 << 0));         // BMSR.0  extended capability
    phy.set_reg(17, 16'hBC08);     // PHY specific status

    // ── the PHY reset sequence ──────────────────────────────────────────────
    $display("\n== the PHY reset is asserted first, then released ==");
    KEY[0] = 1'b0; repeat (10) @(posedge clk); KEY[0] = 1'b1;
    repeat (4) @(posedge clk);
    chk("ENET0_RST_N is LOW right after reset", ENET0_RST_N === 1'b0);
    chk("ENET1_RST_N is held low (that PHY is inert)", ENET1_RST_N === 1'b0);
    chk("nothing is transmitted: TX_EN low", ENET0_TX_EN === 1'b0);
    repeat (CLK_HZ / 1000 * 11) @(posedge clk);
    chk("ENET0_RST_N is released after the hold time", ENET0_RST_N === 1'b1);

    // ── the scan ────────────────────────────────────────────────────────────
    // 32 addresses x 64 MDC periods x 20 clk -- give it room.
    $display("\n== the address scan finds the PHY, and only where it is ==");
    repeat (32 * 64 * 20 + 2000) @(posedge clk);
    $display("      found_map = %08h, phy_ad_found = %0d (0x%02h)",
             dut.found_map, dut.phy_ad_found, dut.phy_ad_found);
    chk("a PHY was found",                      dut.phy_found === 1'b1);
    chk("at address 0x10, where the straps put it", dut.phy_ad_found === 5'h10);
    chk("and at no other address",              dut.found_map === 32'h0001_0000);
    chk("LEDG[0] reports the PHY was found",    LEDG[0] === 1'b1);

    // ── identity and status ─────────────────────────────────────────────────
    $display("\n== the identity and link status are read and reported ==");
    repeat (4 * 64 * 20 + 2000) @(posedge clk);
    $display("      reg2=%04h reg3=%04h BMSR=%04h", dut.reg_id1, dut.reg_id2, dut.reg_bmsr);
    chk("register 2 read as 0x0141",            dut.reg_id1 === 16'h0141);
    chk("register 3 read as 0x0CC2",            dut.reg_id2 === 16'h0CC2);
    chk("the ID is recognised as an 88E1111",   LEDG[1] === 1'b1);
    chk("link up is reported on LEDG[2]",       LEDG[2] === 1'b1);
    chk("autoneg complete on LEDG[3]",          LEDG[3] === 1'b1);

    // ── the switch-selected register ────────────────────────────────────────
    $display("\n== SW[4:0] selects which register the displays show ==");
    SW[4:0] = 5'd17;
    repeat (8 * 64 * 20 + 4000) @(posedge clk);
    $display("      selected reg 17 -> %04h", dut.reg_sel);
    chk("register 17's value reached the display latch", dut.reg_sel === 16'hBC08);

    // ── the RX clock detector ───────────────────────────────────────────────
    // It must say "no clock" when the PHY is not clocking, and "clock" once it
    // is -- that distinction is the whole point of the indicator.
    $display("\n== the RX clock detector tracks the PHY's clock ==");
    chk("no RX clock reported while it is stopped", LEDG[4] === 1'b0);
    fork
      begin : rxclk_run
        repeat (200000) begin #40 rx_clk = ~rx_clk; end
      end
      begin : watch
        repeat (70000) @(posedge clk);
      end
    join_any
    $display("      LEDG[4] (RX clock live) = %0b", LEDG[4]);
    chk("the running RX clock is detected", LEDG[4] === 1'b1);

    $display("\n================================================================");
    $display("  Results: %0d passed, %0d failed  (total %0d)", pass_cnt, fail_cnt, pass_cnt+fail_cnt);
    $display("================================================================");
    if (fail_cnt == 0) $display("  ALL TESTS PASSED");
    else                $display("  SOME TESTS FAILED");
    $finish;
  end

  initial begin #200000000; $display("[TIMEOUT]"); $finish; end

endmodule
