// de2115_host_top.sv -- STEP 2b: can the PC talk to the FPGA over the USB
// cable, and can what it writes be seen on the board?
//
// This is the "USB" half of step 2, and it is worth being precise about what
// that means on a DE2-115, because the board has two unrelated USB things:
//
//   * the USB-Blaster port, which is the JTAG programming/debug cable. This is
//     the one every host tool uses, the one the P4 control plane will run over,
//     and the one this design tests.
//   * a Cypress CY7C67200 USB host/peripheral controller with its own type-A
//     and type-B sockets (user manual 4.10, pins OTG_*). That is a separate
//     chip for attaching USB devices TO the board. It is NOT on the path
//     between the PC and the FPGA fabric, and nothing in a P4 pipeline needs
//     it. Its pins are in common/pins_otg.qsf if you do want it later.
//
// The path tested here is exactly the path step 3 needs:
//
//   PC (Quartus System Console)
//     -> USB-Blaster cable -> JTAG
//     -> Intel "JTAG to Avalon Master Bridge" IP   (jtag_to_avalon_mst_brg_01)
//     -> avmm_axil_lite_bridge                      (rtl/common, already in
//                                                    this repo and tested)
//     -> host_regs, an AXI4-Lite slave
//
// Check it from System Console (Tools -> System Debugging Tools in Quartus):
//
//     set m [lindex [get_service_paths master] 0]
//     open_service master $m
//     master_read_32  $m 0x0  1     ;# expect 0xde211501  -- the ID
//     master_write_32 $m 0x4  0x12345678
//     master_read_32  $m 0x4  1     ;# expect 0x12345678  -- the scratch
//     master_write_32 $m 0x8  0x3ffff   ;# all 18 red LEDs on -- VISIBLE
//     master_write_32 $m 0xc  0xcafe1234 ;# the 7-segment displays
//     master_read_32  $m 0x10 1     ;# ticks: read twice, must differ
//
// If the ID reads back and the LEDs change, the whole host path is proven and
// step 3's table writes have somewhere to land.
`default_nettype none

module de2115_host_top (
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
    output wire [6:0]  HEX7
);
  localparam int ADDR_W = 16;
  localparam int CLK_HZ = 50_000_000;

  wire rst_n = KEY[0];        // active-low button, active-low reset: direct

  // ── The JTAG master, from the PC ──────────────────────────────────────────
  wire [31:0] avm_address;
  wire        avm_read, avm_write;
  wire [31:0] avm_writedata, avm_readdata;
  wire [3:0]  avm_byteenable;
  wire        avm_waitrequest, avm_readdatavalid;
  wire        avm_reset;

  jtag_to_avalon_mst_brg_01 u_jtag (
    .clk_clk              (CLOCK_50),
    .clk_reset_reset      (~rst_n),
    .master_address       (avm_address),
    .master_readdata      (avm_readdata),
    .master_read          (avm_read),
    .master_write         (avm_write),
    .master_writedata     (avm_writedata),
    .master_waitrequest   (avm_waitrequest),
    .master_readdatavalid (avm_readdatavalid),
    .master_byteenable    (avm_byteenable),
    .master_reset_reset   (avm_reset)
  );

  // ── Avalon-MM to AXI4-Lite, the module this repo already had ─────────────
  wire [ADDR_W-1:0] axil_awaddr, axil_araddr;
  wire              axil_awvalid, axil_awready, axil_wvalid, axil_wready;
  wire              axil_bvalid, axil_bready, axil_arvalid, axil_arready;
  wire              axil_rvalid, axil_rready;
  wire [31:0]       axil_wdata, axil_rdata;
  wire [3:0]        axil_wstrb;
  wire [1:0]        axil_bresp, axil_rresp;

  avmm_axil_lite_bridge #(.ADDR_W(ADDR_W)) u_bridge (
    .clk(CLOCK_50), .rst_n(rst_n),
    .avs_address       (avm_address[ADDR_W-1:0]),
    .avs_read          (avm_read),
    .avs_write         (avm_write),
    .avs_writedata     (avm_writedata),
    .avs_byteenable    (avm_byteenable),
    .avs_readdata      (avm_readdata),
    .avs_waitrequest   (avm_waitrequest),
    .avs_readdatavalid (avm_readdatavalid),
    .m_axil_awaddr(axil_awaddr), .m_axil_awvalid(axil_awvalid), .m_axil_awready(axil_awready),
    .m_axil_wdata(axil_wdata),   .m_axil_wstrb(axil_wstrb),
    .m_axil_wvalid(axil_wvalid), .m_axil_wready(axil_wready),
    .m_axil_bresp(axil_bresp),   .m_axil_bvalid(axil_bvalid), .m_axil_bready(axil_bready),
    .m_axil_araddr(axil_araddr), .m_axil_arvalid(axil_arvalid), .m_axil_arready(axil_arready),
    .m_axil_rdata(axil_rdata),   .m_axil_rresp(axil_rresp),
    .m_axil_rvalid(axil_rvalid), .m_axil_rready(axil_rready)
  );

  // ── The registers the host pokes ─────────────────────────────────────────
  wire [17:0] host_leds;
  wire [31:0] host_hex;
  wire        wr_seen, rd_seen;

  host_regs #(.ADDR_W(ADDR_W)) u_regs (
    .clk(CLOCK_50), .rst_n(rst_n),
    .s_axil_awaddr(axil_awaddr), .s_axil_awvalid(axil_awvalid), .s_axil_awready(axil_awready),
    .s_axil_wdata(axil_wdata),   .s_axil_wstrb(axil_wstrb),
    .s_axil_wvalid(axil_wvalid), .s_axil_wready(axil_wready),
    .s_axil_bresp(axil_bresp),   .s_axil_bvalid(axil_bvalid), .s_axil_bready(axil_bready),
    .s_axil_araddr(axil_araddr), .s_axil_arvalid(axil_arvalid), .s_axil_arready(axil_arready),
    .s_axil_rdata(axil_rdata),   .s_axil_rresp(axil_rresp),
    .s_axil_rvalid(axil_rvalid), .s_axil_rready(axil_rready),
    .leds(host_leds), .hexval(host_hex), .wr_seen(wr_seen), .rd_seen(rd_seen)
  );

  // ── Activity indicators ──────────────────────────────────────────────────
  // A host transaction is a few cycles long: far too short to see. These
  // stretch each one to about 1/16 s so a single System Console command
  // produces a visible blink -- which is how you tell "the write arrived" from
  // "the readback path lied".
  localparam int STRETCH = CLK_HZ / 16;
  logic [$clog2(STRETCH)-1:0] wr_str, rd_str;
  always_ff @(posedge CLOCK_50) begin
    if (!rst_n) begin
      wr_str <= '0; rd_str <= '0;
    end else begin
      if (wr_seen)            wr_str <= STRETCH[$clog2(STRETCH)-1:0] - 1;
      else if (wr_str != '0)  wr_str <= wr_str - 1'b1;
      if (rd_seen)            rd_str <= STRETCH[$clog2(STRETCH)-1:0] - 1;
      else if (rd_str != '0)  rd_str <= rd_str - 1'b1;
    end
  end

  // Heartbeat, same as the other steps: a dark board and a frozen board should
  // not look alike.
  localparam int HB_DIV = CLK_HZ / 2;
  logic [$clog2(HB_DIV)-1:0] hb_cnt;
  logic hb;
  always_ff @(posedge CLOCK_50) begin
    if (!rst_n) begin hb_cnt <= '0; hb <= 1'b0; end
    else if (hb_cnt == HB_DIV[$clog2(HB_DIV)-1:0] - 1) begin hb_cnt <= '0; hb <= ~hb; end
    else hb_cnt <= hb_cnt + 1'b1;
  end

  // SW[17] shows the raw host LED register; otherwise LEDR is the host's to
  // drive. Either way the host's write is what you are looking at.
  assign LEDR = host_leds;
  assign LEDG = {hb, 4'b0000, avm_reset, rd_str != '0, wr_str != '0, 1'b1};

  seg7 h7 (.nibble(host_hex[31:28]), .blank(1'b0), .seg(HEX7));
  seg7 h6 (.nibble(host_hex[27:24]), .blank(1'b0), .seg(HEX6));
  seg7 h5 (.nibble(host_hex[23:20]), .blank(1'b0), .seg(HEX5));
  seg7 h4 (.nibble(host_hex[19:16]), .blank(1'b0), .seg(HEX4));
  seg7 h3 (.nibble(host_hex[15:12]), .blank(1'b0), .seg(HEX3));
  seg7 h2 (.nibble(host_hex[11:8]),  .blank(1'b0), .seg(HEX2));
  seg7 h1 (.nibble(host_hex[7:4]),   .blank(1'b0), .seg(HEX1));
  seg7 h0 (.nibble(host_hex[3:0]),   .blank(1'b0), .seg(HEX0));
endmodule

`default_nettype wire
