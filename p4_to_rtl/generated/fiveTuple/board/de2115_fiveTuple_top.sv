// de2115_fiveTuple_top.sv -- DE2-115 hardware integration wrapper.
//
// Hand-written (not compiler-generated), specific to this one bring-up
// exercise, unlike rtl/common/avmm_axil_lite_bridge.sv which is generic.
// Instantiates the compiler-generated fiveTuple_selftest_top (on-chip
// packet generator + capture, no real MAC/PHY needed) behind an
// avmm_axil_lite_bridge, driven by an Intel "JTAG to Avalon Master Bridge"
// Platform Designer system so it can be exercised interactively from
// Quartus System Console over JTAG.
//
// This is the module that should become TOP_LEVEL_ENTITY in the .qsf for
// real synthesis -- NOT fiveTuple_selftest_top directly, and NOT
// fiveTuple_top (which has no on-chip traffic source at all without this
// wrapper's generator). compiler/emit_constraints.py's generated .qsf
// currently points TOP_LEVEL_ENTITY at fiveTuple_selftest_top when
// --self-test is used (see main.py) -- it has no way to know this
// hand-written wrapper exists, so change that one line by hand (or in your
// Quartus project's own Assignments) once you add this file:
//   set_global_assignment -name TOP_LEVEL_ENTITY de2115_fiveTuple_top
//
// JTAG-to-Avalon-Master instance assumptions (from the actual generated
// jtag_to_avalon_mst_brg_01_qsys system file, not guessed):
//   - Module name: jtag_to_avalon_mst_brg_01 -- confirm this matches your
//     project's actual generated file/module name if you named the IP
//     differently in IP Catalog.
//   - Port names (from the .qsys interfaces, autoexported 1:1, no prefix):
//     clk_clk, clk_reset_reset, master_address/read/write/writedata/
//     byteenable/readdata/waitrequest/readdatavalid, master_reset_reset.
//   - Reset polarity: Qsys convention names active-high resets "*_reset"
//     and active-low ones "*_reset_n" -- clk_reset_reset/master_reset_reset
//     have no _n, so they're treated as ACTIVE-HIGH below. If the design
//     never comes out of reset (or is permanently live with no reset
//     pulse at all) on real hardware, this polarity assumption is the
//     first thing to flip.
//   - master_address width is NOT shown in the .qsys (no override on the
//     exported/unconnected master interface) -- declared 32-bit below
//     (the common Platform Designer default for an exported master with no
//     internally-connected slave to size against) and truncated to the low
//     16 bits feeding the bridge (ST_AXIL_ADDR_W). If Quartus reports a
//     width mismatch on u_jtag_avmm's master_address port, check the
//     actual generated .v file's port declaration and adjust jm_address's
//     width here to match.
//   - master_reset_reset is an OUTPUT of the JTAG-Avalon-Master core (not
//     an input) -- it lets Quartus System Console reset the downstream
//     Avalon-MM/AXI4-Lite side independently of the board's own reset
//     button. Combined below with the board's KEY0 (either can reset the
//     pipeline), so both a physical button press and a System Console
//     reset command work.
//
// The table control-plane bus (fiveTuple_selftest_top's s_axil_*) is tied
// idle here -- out of scope for this bridge/wrapper. Bridging it too would
// need a second avmm_axil_lite_bridge instance at a different Avalon-MM
// base address (Platform Designer's interconnect can fan a single
// JTAG-to-Avalon-Master out to multiple slaves); not done here since the
// self-test bus alone is enough to prove the pipeline runs on real silicon.

module de2115_fiveTuple_top (
    input  logic CLOCK_50,   // DE2-115's 50MHz oscillator -- TODO: confirm
                              // this exact port/pin name against Terasic's
                              // official DE2_115_pin_assignments.csv before
                              // using this file as-is; not independently
                              // verified in this session.
    input  logic KEY0        // active-low pushbutton reset -- TODO: same
                              // caveat, confirm the exact port/pin name.
);

  logic clk;
  logic rst_n;
  assign clk   = CLOCK_50;
  assign rst_n = KEY0;

  // ── JTAG to Avalon Master Bridge (Platform Designer system) ──────────────
  logic [31:0] jm_address;
  logic        jm_read;
  logic        jm_write;
  logic [31:0] jm_writedata;
  logic [3:0]  jm_byteenable;
  logic [31:0] jm_readdata;
  logic        jm_waitrequest;
  logic        jm_readdatavalid;
  logic        jtag_master_reset;   // active-high, OUTPUT of the JTAG-Avalon-Master

  jtag_to_avalon_mst_brg_01 u_jtag_avmm (
    .clk_clk             (clk),
    .clk_reset_reset     (~rst_n),           // active-high, see header note
    .master_address      (jm_address),
    .master_read         (jm_read),
    .master_write        (jm_write),
    .master_writedata    (jm_writedata),
    .master_byteenable   (jm_byteenable),
    .master_readdata     (jm_readdata),
    .master_waitrequest  (jm_waitrequest),
    .master_readdatavalid(jm_readdatavalid),
    .master_reset_reset  (jtag_master_reset)
  );

  // Pipeline/bridge come out of reset only once BOTH the board's KEY0 is
  // released AND the JTAG-Avalon-Master isn't asserting its own reset --
  // either a physical button press or a System Console reset command works.
  logic pipeline_rst_n;
  assign pipeline_rst_n = rst_n && !jtag_master_reset;

  // ── Table control-plane AXI4-Lite -- tied idle, out of scope here ────────
  logic [15:0] s_axil_awaddr   = 16'd0;
  logic        s_axil_awvalid  = 1'b0;
  logic        s_axil_awready;
  logic [31:0] s_axil_wdata    = 32'd0;
  logic [3:0]  s_axil_wstrb    = 4'd0;
  logic        s_axil_wvalid   = 1'b0;
  logic        s_axil_wready;
  logic [1:0]  s_axil_bresp;
  logic        s_axil_bvalid;
  logic        s_axil_bready   = 1'b1;
  logic [15:0] s_axil_araddr   = 16'd0;
  logic        s_axil_arvalid  = 1'b0;
  logic        s_axil_arready;
  logic [31:0] s_axil_rdata;
  logic [1:0]  s_axil_rresp;
  logic        s_axil_rvalid;
  logic        s_axil_rready   = 1'b1;

  // ── Self-test AXI4-Lite -- driven by the bridge below ────────────────────
  logic [15:0] st_axil_awaddr;
  logic        st_axil_awvalid;
  logic        st_axil_awready;
  logic [31:0] st_axil_wdata;
  logic [3:0]  st_axil_wstrb;
  logic        st_axil_wvalid;
  logic        st_axil_wready;
  logic [1:0]  st_axil_bresp;
  logic        st_axil_bvalid;
  logic        st_axil_bready;
  logic [15:0] st_axil_araddr;
  logic        st_axil_arvalid;
  logic        st_axil_arready;
  logic [31:0] st_axil_rdata;
  logic [1:0]  st_axil_rresp;
  logic        st_axil_rvalid;
  logic        st_axil_rready;

  fiveTuple_selftest_top u_pipeline (
    .clk(clk), .rst_n(pipeline_rst_n),
    .s_axil_awaddr(s_axil_awaddr), .s_axil_awvalid(s_axil_awvalid), .s_axil_awready(s_axil_awready),
    .s_axil_wdata(s_axil_wdata), .s_axil_wstrb(s_axil_wstrb), .s_axil_wvalid(s_axil_wvalid), .s_axil_wready(s_axil_wready),
    .s_axil_bresp(s_axil_bresp), .s_axil_bvalid(s_axil_bvalid), .s_axil_bready(s_axil_bready),
    .s_axil_araddr(s_axil_araddr), .s_axil_arvalid(s_axil_arvalid), .s_axil_arready(s_axil_arready),
    .s_axil_rdata(s_axil_rdata), .s_axil_rresp(s_axil_rresp), .s_axil_rvalid(s_axil_rvalid), .s_axil_rready(s_axil_rready),
    .st_axil_awaddr(st_axil_awaddr), .st_axil_awvalid(st_axil_awvalid), .st_axil_awready(st_axil_awready),
    .st_axil_wdata(st_axil_wdata), .st_axil_wstrb(st_axil_wstrb), .st_axil_wvalid(st_axil_wvalid), .st_axil_wready(st_axil_wready),
    .st_axil_bresp(st_axil_bresp), .st_axil_bvalid(st_axil_bvalid), .st_axil_bready(st_axil_bready),
    .st_axil_araddr(st_axil_araddr), .st_axil_arvalid(st_axil_arvalid), .st_axil_arready(st_axil_arready),
    .st_axil_rdata(st_axil_rdata), .st_axil_rresp(st_axil_rresp), .st_axil_rvalid(st_axil_rvalid), .st_axil_rready(st_axil_rready)
  );

  avmm_axil_lite_bridge #(.ADDR_W(16)) u_bridge (
    .clk(clk), .rst_n(pipeline_rst_n),
    .avs_address(jm_address[15:0]),
    .avs_read(jm_read),
    .avs_write(jm_write),
    .avs_writedata(jm_writedata),
    .avs_byteenable(jm_byteenable),
    .avs_readdata(jm_readdata),
    .avs_waitrequest(jm_waitrequest),
    .avs_readdatavalid(jm_readdatavalid),
    .m_axil_awaddr(st_axil_awaddr), .m_axil_awvalid(st_axil_awvalid), .m_axil_awready(st_axil_awready),
    .m_axil_wdata(st_axil_wdata), .m_axil_wstrb(st_axil_wstrb), .m_axil_wvalid(st_axil_wvalid), .m_axil_wready(st_axil_wready),
    .m_axil_bresp(st_axil_bresp), .m_axil_bvalid(st_axil_bvalid), .m_axil_bready(st_axil_bready),
    .m_axil_araddr(st_axil_araddr), .m_axil_arvalid(st_axil_arvalid), .m_axil_arready(st_axil_arready),
    .m_axil_rdata(st_axil_rdata), .m_axil_rresp(st_axil_rresp), .m_axil_rvalid(st_axil_rvalid), .m_axil_rready(st_axil_rready)
  );

endmodule
