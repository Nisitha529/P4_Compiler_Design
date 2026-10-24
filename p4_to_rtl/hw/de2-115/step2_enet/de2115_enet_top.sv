// de2115_enet_top.sv -- STEP 2 of the DE2-115 bring-up: is the Ethernet PHY
// there, and what is it doing?
//
// This design MEASURES rather than assumes, because the next step depends on
// facts this one can establish and nothing else can:
//
//   * which MDIO address the PHY answers at. The user manual says ENET0 is
//     strapped to 10000 (0x10) and ENET1 to 10001 -- but this scans all 32
//     addresses and shows which one replied, so a board whose straps differ
//     tells you so instead of looking dead.
//   * whether it IS an 88E1111: registers 2 and 3 are the IEEE PHY identifier
//     and are shown in full on the displays. A green LED lights when they
//     match the expected value, but the raw value is always visible, which
//     matters if your board has a different revision.
//   * what the link is doing: link up, auto-negotiation complete, and the
//     negotiated speed, read from the standard BMSR (register 1) and the
//     88E1111's own PHY-specific status (register 17).
//   * whether the RX clock from the PHY is running at all, and whether frames
//     are arriving -- both detected without decoding the data, so this works
//     no matter which data interface the PHY is strapped to.
//
// That last point is the reason this step exists in this form. The DE2-115's
// PHYs come up in RGMII- or GMII-to-copper mode (user manual Table 4-20,
// HWCFG[3:0] = 1011/1111), NOT MII, so a data path built on an assumption
// about the interface can fail for a reason that is invisible from outside.
// Step 3 should be built on what this design reports.
//
// Nothing is transmitted: TX_EN is held low and GTX_CLK is parked. ENET1 is
// held in reset so it cannot participate.
//
// Controls:
//   KEY[0] pressed : reset -- re-runs the PHY reset sequence and the scan
//   SW[4:0]        : which PHY register to show on HEX3..HEX0
//   SW[17]         : show the scan result map on LEDR instead of status
//
// Display:
//   HEX7 HEX6      : the MDIO address the PHY answered at
//   HEX5 HEX4      : the register number being shown
//   HEX3..HEX0     : that register's 16-bit value
`default_nettype none

module de2115_enet_top #(
    parameter int CLK_HZ = 50_000_000,
    // The IEEE identifier the Marvell 88E1111 is expected to report. Only the
    // model/OUI part of register 3 is compared: its low 4 bits are the silicon
    // revision and differ between parts that are otherwise the same chip.
    parameter logic [15:0] PHY_ID1 = 16'h0141,
    parameter logic [15:0] PHY_ID2 = 16'h0CC0,
    parameter logic [15:0] PHY_ID2_MASK = 16'hFFF0
) (
    input  wire        CLOCK_50,
    input  wire [3:0]  KEY,
    input  wire [17:0] SW,
    output wire [17:0] LEDR,
    output wire [8:0]  LEDG,
    output wire [6:0]  HEX0,
    output wire [6:0]  HEX1,
    output wire [6:0]  HEX2,
    output wire [6:0]  HEX3,
    output wire [6:0]  HEX4,
    output wire [6:0]  HEX5,
    output wire [6:0]  HEX6,
    output wire [6:0]  HEX7,

    // Ethernet PHY 0 -- management plus the receive side we only observe
    output wire        ENET0_RST_N,
    output wire        ENET0_MDC,
    inout  wire        ENET0_MDIO,
    input  wire        ENET0_RX_CLK,
    input  wire        ENET0_RX_DV,
    input  wire [3:0]  ENET0_RX_DATA,
    input  wire        ENET0_RX_ER,
    input  wire        ENET0_LINK100,
    input  wire        ENET0_INT_N,
    // Transmit side, parked: nothing is sent in this step
    output wire        ENET0_GTX_CLK,
    output wire        ENET0_TX_EN,
    output wire [3:0]  ENET0_TX_DATA,
    output wire        ENET0_TX_ER,
    // PHY 1 held in reset so it cannot drive anything
    output wire        ENET1_RST_N
);

  wire rst = ~KEY[0];

  // ── PHY reset sequencing ─────────────────────────────────────────────────
  // The 88E1111 needs its hardware reset held, then time before management
  // access. 10 ms each is far longer than the datasheet minimum and costs
  // nothing on a bring-up design -- being generous here removes a variable.
  localparam int MS_CYC   = CLK_HZ / 1000;
  localparam int RST_MS   = 10;
  localparam int WAIT_MS  = 10;
  localparam int PH_W     = $clog2(MS_CYC * (RST_MS + WAIT_MS) + 2);
  logic [PH_W-1:0] phase_cnt;
  logic            phy_rst_n, mgmt_ready;

  always_ff @(posedge CLOCK_50) begin
    if (rst) begin
      phase_cnt  <= '0;
      phy_rst_n  <= 1'b0;
      mgmt_ready <= 1'b0;
    end else begin
      if (phase_cnt < PH_W'(MS_CYC * (RST_MS + WAIT_MS))) phase_cnt <= phase_cnt + 1'b1;
      phy_rst_n  <= (phase_cnt >= PH_W'(MS_CYC * RST_MS));
      mgmt_ready <= (phase_cnt >= PH_W'(MS_CYC * (RST_MS + WAIT_MS)) - 1);
    end
  end
  assign ENET0_RST_N = phy_rst_n;
  assign ENET1_RST_N = 1'b0;          // deliberately held in reset

  // ── MDIO ─────────────────────────────────────────────────────────────────
  logic        md_start, md_we;
  logic [4:0]  md_phy, md_reg;
  logic [15:0] md_wdata, md_rdata;
  logic        md_done, md_busy, md_noreply;
  logic        md_o, md_oe;

  mdio_master #(.CLK_HZ(CLK_HZ), .MDC_HZ(2_500_000)) u_mdio (
    .clk(CLOCK_50), .rst(rst),
    .start(md_start), .we(md_we), .phy_ad(md_phy), .reg_ad(md_reg),
    .wdata(md_wdata), .rdata(md_rdata), .done(md_done), .busy(md_busy),
    .no_reply(md_noreply),
    .mdc(ENET0_MDC), .mdio_o(md_o), .mdio_oe(md_oe), .mdio_i(ENET0_MDIO)
  );
  // The only tri-state in the design, at the pin where it belongs.
  assign ENET0_MDIO = md_oe ? md_o : 1'bz;

  // ── Sequencer: scan for the PHY, then poll it forever ────────────────────
  typedef enum logic [2:0] {S_WAIT, S_SCAN, S_SCAN_W, S_POLL, S_POLL_W} seq_t;
  seq_t seq;

  logic [4:0]  scan_ad;
  logic [31:0] found_map;         // one bit per address that answered
  logic [4:0]  phy_ad_found;
  logic        phy_found;
  logic [1:0]  poll_i;            // which register of the poll set
  logic [15:0] reg_id1, reg_id2, reg_bmsr, reg_sel;
  logic [4:0]  sel_reg_q;

  wire [4:0] poll_reg = (poll_i == 2'd0) ? 5'd2 :
                        (poll_i == 2'd1) ? 5'd3 :
                        (poll_i == 2'd2) ? 5'd1 : sel_reg_q;

  always_ff @(posedge CLOCK_50) begin
    if (rst) begin
      seq          <= S_WAIT;
      scan_ad      <= '0;
      found_map    <= '0;
      phy_ad_found <= '0;
      phy_found    <= 1'b0;
      poll_i       <= '0;
      md_start     <= 1'b0;
      md_we        <= 1'b0;
      md_wdata     <= '0;
      md_phy       <= '0;
      md_reg       <= '0;
      reg_id1      <= '0;
      reg_id2      <= '0;
      reg_bmsr     <= '0;
      reg_sel      <= '0;
      sel_reg_q    <= '0;
    end else begin
      md_start  <= 1'b0;
      sel_reg_q <= SW[4:0];
      case (seq)
        S_WAIT:  if (mgmt_ready) seq <= S_SCAN;

        // Read register 2 at every address. An address that drives the
        // turnaround bit low has something on it; one that does not, does not.
        S_SCAN: if (!md_busy) begin
          md_we    <= 1'b0;
          md_phy   <= scan_ad;
          md_reg   <= 5'd2;
          md_start <= 1'b1;
          seq      <= S_SCAN_W;
        end
        S_SCAN_W: if (md_done) begin
          if (!md_noreply) begin
            found_map[scan_ad] <= 1'b1;
            if (!phy_found) begin
              phy_found    <= 1'b1;
              phy_ad_found <= scan_ad;
            end
          end
          if (scan_ad == 5'd31) seq <= S_POLL;
          else begin
            scan_ad <= scan_ad + 1'b1;
            seq     <= S_SCAN;
          end
        end

        // Poll the identity, the standard status and whichever register the
        // switches select, round and round, so the display is live.
        S_POLL: if (!md_busy) begin
          md_we    <= 1'b0;
          md_phy   <= phy_ad_found;
          md_reg   <= poll_reg;
          md_start <= 1'b1;
          seq      <= S_POLL_W;
        end
        S_POLL_W: if (md_done) begin
          unique case (poll_i)
            2'd0: reg_id1  <= md_rdata;
            2'd1: reg_id2  <= md_rdata;
            2'd2: reg_bmsr <= md_rdata;
            2'd3: reg_sel  <= md_rdata;
          endcase
          poll_i <= poll_i + 2'd1;
          seq    <= S_POLL;
        end

        default: seq <= S_WAIT;
      endcase
    end
  end

  wire id_ok = phy_found && (reg_id1 == PHY_ID1)
               && ((reg_id2 & PHY_ID2_MASK) == (PHY_ID2 & PHY_ID2_MASK));
  wire link_up   = reg_bmsr[2];      // BMSR.2  link status (latching low)
  wire aneg_done = reg_bmsr[5];      // BMSR.5  auto-negotiation complete

  // ── Is the PHY's receive clock running, and are frames arriving? ─────────
  // Deliberately mode-agnostic: it counts in the RX_CLK domain without
  // decoding anything, so it reports the same truth whether the PHY is in
  // MII, GMII or RGMII mode. A clock that is not running cannot advance a
  // counter, which is exactly the signal wanted here.
  // A TOGGLE per RX clock edge, not a counter.
  //
  // The first version of this compared a 4-bit counter's value at the start
  // and end of each window, and that is a trap: if the number of increments
  // per window happens to be a multiple of the counter's range, the two
  // samples are equal and a perfectly healthy clock reads as stopped. It is
  // not hypothetical -- it is what the testbench hit (2048 increments of a
  // 4-bit counter per window, 2048 mod 16 == 0), and on hardware it would
  // depend on the exact ratio between CLOCK_50 and the PHY's clock, which is
  // the kind of flakiness that costs a day at the bench.
  //
  // A toggle that the 50 MHz side watches on EVERY cycle, sticky until the
  // window ends, cannot alias: it asks "did this change at all", not "is it
  // different now than it was".
  //
  // Initial values rather than a reset, deliberately: this lives in the PHY's
  // clock domain and that clock may not be running, which is the very thing
  // being detected -- a reset in that domain could never be applied.
  logic rxclk_tog = 1'b0;
  logic rxdv_tog  = 1'b0;
  always_ff @(posedge ENET0_RX_CLK) begin
    rxclk_tog <= ~rxclk_tog;
    if (ENET0_RX_DV) rxdv_tog <= ~rxdv_tog;
  end

  // Cross back with two flops, then look for change over a window. Nothing
  // here is timing-critical: it drives LEDs for a human.
  localparam int WIN_W = $clog2(CLK_HZ / 8);   // ~8 windows per second
  logic rxclk_s1, rxclk_s2, rxclk_s3;
  logic rxdv_s1, rxdv_s2, rxdv_s3;
  logic [WIN_W-1:0] win;
  logic rxclk_seen, rxdv_seen;      // sticky within the window
  logic rxclk_live, rx_active;      // what the LEDs show
  always_ff @(posedge CLOCK_50) begin
    if (rst) begin
      // Off until a window has actually SEEN a change: "not proved running"
      // and "stopped" should both read off, never X and never a false yes.
      rxclk_s1 <= 1'b0; rxclk_s2 <= 1'b0; rxclk_s3 <= 1'b0;
      rxdv_s1  <= 1'b0; rxdv_s2  <= 1'b0; rxdv_s3  <= 1'b0;
      win        <= '0;
      rxclk_seen <= 1'b0;
      rxdv_seen  <= 1'b0;
      rxclk_live <= 1'b0;
      rx_active  <= 1'b0;
    end else begin
      // two flops to cross the domain, a third to edge-detect
      rxclk_s1 <= rxclk_tog; rxclk_s2 <= rxclk_s1; rxclk_s3 <= rxclk_s2;
      rxdv_s1  <= rxdv_tog;  rxdv_s2  <= rxdv_s1;  rxdv_s3  <= rxdv_s2;
      if (rxclk_s2 != rxclk_s3) rxclk_seen <= 1'b1;
      if (rxdv_s2  != rxdv_s3)  rxdv_seen  <= 1'b1;
      win <= win + 1'b1;
      if (win == '0) begin
        rxclk_live <= rxclk_seen;
        rx_active  <= rxdv_seen;
        rxclk_seen <= 1'b0;
        rxdv_seen  <= 1'b0;
      end
    end
  end

  // ── Heartbeat, so a frozen design is distinguishable from a quiet one ────
  localparam int HB_DIV = CLK_HZ / 2;
  logic [$clog2(HB_DIV)-1:0] hb_cnt;
  logic hb;
  always_ff @(posedge CLOCK_50) begin
    if (rst) begin hb_cnt <= '0; hb <= 1'b0; end
    else if (hb_cnt == HB_DIV[$clog2(HB_DIV)-1:0] - 1) begin
      hb_cnt <= '0; hb <= ~hb;
    end else hb_cnt <= hb_cnt + 1'b1;
  end

  // ── Outputs ──────────────────────────────────────────────────────────────
  // Transmit parked: this step never sends.
  assign ENET0_GTX_CLK = 1'b0;
  assign ENET0_TX_EN   = 1'b0;
  assign ENET0_TX_DATA = 4'h0;
  assign ENET0_TX_ER   = 1'b0;

  assign LEDG = {hb, 2'b00, rx_active, rxclk_live, aneg_done, link_up, id_ok, phy_found};
  assign LEDR = SW[17] ? found_map[17:0]
                       : {md_noreply, ~ENET0_INT_N, ENET0_LINK100, 3'b000,
                          reg_sel[7:0], phy_ad_found};

  seg7 h7 (.nibble({3'b000, phy_ad_found[4]}), .blank(1'b0), .seg(HEX7));
  seg7 h6 (.nibble(phy_ad_found[3:0]),         .blank(1'b0), .seg(HEX6));
  seg7 h5 (.nibble({3'b000, poll_reg[4]}),     .blank(1'b0), .seg(HEX5));
  seg7 h4 (.nibble(sel_reg_q[3:0]),            .blank(1'b0), .seg(HEX4));
  seg7 h3 (.nibble(reg_sel[15:12]),            .blank(1'b0), .seg(HEX3));
  seg7 h2 (.nibble(reg_sel[11:8]),             .blank(1'b0), .seg(HEX2));
  seg7 h1 (.nibble(reg_sel[7:4]),              .blank(1'b0), .seg(HEX1));
  seg7 h0 (.nibble(reg_sel[3:0]),              .blank(1'b0), .seg(HEX0));
endmodule

`default_nettype wire
