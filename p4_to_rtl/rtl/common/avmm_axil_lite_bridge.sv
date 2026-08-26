// avmm_axil_lite_bridge.sv -- Avalon-MM slave to AXI4-Lite master bridge.
//
// Hand-written (not compiler-generated), generic, reusable board-integration
// glue: translates one Avalon-MM variable-latency transaction into one full
// AXI4-Lite AW+W+B (write) or AR+R (read) handshake sequence. Built for the
// p4_to_rtl project's DE2-115 bring-up path -- Intel's "JTAG to Avalon
// Master Bridge" IP (driven interactively from Quartus System Console over
// JTAG) speaks Avalon-MM, but the compiler's self-test control bus
// (emit_selftest.py's st_axil_*) is AXI4-Lite. This module is the missing
// link between the two; it is otherwise unaware of anything P4-specific.
//
// Byte-addressed on the Avalon-MM side (avs_address maps directly onto the
// AXI4-Lite word_addr*4 convention -- no address-unit conversion needed).
//
// Design note, verified against the actual generated AXI4-Lite decoder
// (compiler/emit_selftest.py's _write_axil_decoder), not assumed: awready/
// wready decode MUTUALLY EXCLUSIVE states of a single 2-bit register, so
// they provably can never assert on the same cycle -- a bridge that waits
// for awvalid&&awready&&wvalid&&wready together (a common shortcut valid
// against many real AXI-Lite slaves) would deadlock forever against this
// specific bus. The two independent sticky accept-flags below (aw_done_r/
// w_done_r) are load-bearing, not a style choice -- they match the same
// technique this project's own testbenches already use successfully
// against this exact decoder (see tb_fiveTuple_selftest_top.sv's st_write
// task).
//
// Critical correctness rule: m_axil_awvalid/wvalid/arvalid are pure
// combinational functions of (avst, aw_done_r, w_done_r) below, never a
// register that could stay asserted one cycle too long -- the far-side
// decoder trusts *valid unconditionally whenever it is idle, with no
// defense of its own against a stale re-latch, so this guard has to live
// entirely here.
//
// avs_byteenable is included (real Avalon-MM interface-spec form) and
// wired straight through to m_axil_wstrb, but it is currently a no-op on
// the far side: emit_selftest.py's decoder never reads wstrb at all --
// every register/template-buffer write is unconditionally full-32-bit.
// Passed through rather than hardware-tied, so this bridge needs no
// changes if that decoder is ever extended to honor per-byte strobes.

module avmm_axil_lite_bridge #(
    parameter int ADDR_W = 16
) (
    input  logic clk,
    input  logic rst_n,

    // Avalon-MM slave (from e.g. Intel's JTAG to Avalon Master Bridge IP)
    input  logic [ADDR_W-1:0] avs_address,
    input  logic              avs_read,
    input  logic              avs_write,
    input  logic [31:0]       avs_writedata,
    input  logic [3:0]        avs_byteenable,
    output logic [31:0]       avs_readdata,
    output logic              avs_waitrequest,
    output logic              avs_readdatavalid,

    // AXI4-Lite master (to e.g. {app}_selftest_top's st_axil_* slave port)
    output logic [ADDR_W-1:0] m_axil_awaddr,
    output logic              m_axil_awvalid,
    input  logic              m_axil_awready,
    output logic [31:0]       m_axil_wdata,
    output logic [3:0]        m_axil_wstrb,
    output logic              m_axil_wvalid,
    input  logic              m_axil_wready,
    input  logic [1:0]        m_axil_bresp,
    input  logic              m_axil_bvalid,
    output logic              m_axil_bready,
    output logic [ADDR_W-1:0] m_axil_araddr,
    output logic              m_axil_arvalid,
    input  logic              m_axil_arready,
    input  logic [31:0]       m_axil_rdata,
    input  logic [1:0]        m_axil_rresp,
    input  logic              m_axil_rvalid,
    output logic              m_axil_rready
);

  typedef enum logic [2:0] {
    AV_IDLE = 3'd0,
    AV_AW_W = 3'd1,
    AV_B    = 3'd2,
    AV_AR   = 3'd3,
    AV_R    = 3'd4
  } avst_t;

  avst_t avst;
  logic aw_done_r, w_done_r;

  logic [ADDR_W-1:0] addr_r;
  logic [31:0]       wdata_r;
  logic [3:0]         wstrb_r;

  assign avs_waitrequest = (avst != AV_IDLE);

  // Pure combinational -- see the module-header note on why this must
  // never be a register.
  assign m_axil_awvalid = (avst == AV_AW_W) && !aw_done_r;
  assign m_axil_wvalid  = (avst == AV_AW_W) && !w_done_r;
  assign m_axil_arvalid = (avst == AV_AR);

  assign m_axil_awaddr = addr_r;
  assign m_axil_wdata  = wdata_r;
  assign m_axil_wstrb  = wstrb_r;
  // Direct combinational passthrough throughout AV_AR -- the far-side
  // decoder decodes araddr live at the AR-handshake edge (no araddr_r on
  // that side), not a registered/delayed copy. Avalon-MM's own protocol
  // already guarantees avs_address stays stable while avs_waitrequest is
  // asserted, so this is safe.
  assign m_axil_araddr = avs_address;

  assign m_axil_bready = 1'b1;
  assign m_axil_rready = 1'b1;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      avst              <= AV_IDLE;
      aw_done_r         <= 1'b0;
      w_done_r          <= 1'b0;
      avs_readdata      <= 32'd0;
      avs_readdatavalid <= 1'b0;
    end else begin
      avs_readdatavalid <= 1'b0;  // default deassert; pulses explicitly below

      case (avst)
        AV_IDLE: begin
          // Prioritize write if both asserted simultaneously (defensive --
          // real JTAG-to-Avalon-Master Tcl procs never do this).
          if (avs_write) begin
            addr_r    <= avs_address;
            wdata_r   <= avs_writedata;
            wstrb_r   <= avs_byteenable;
            aw_done_r <= 1'b0;
            w_done_r  <= 1'b0;
            avst      <= AV_AW_W;
          end else if (avs_read) begin
            avst <= AV_AR;
          end
        end

        AV_AW_W: begin
          if (m_axil_awvalid && m_axil_awready) aw_done_r <= 1'b1;
          if (m_axil_wvalid  && m_axil_wready)  w_done_r  <= 1'b1;
          if ((aw_done_r || (m_axil_awvalid && m_axil_awready)) &&
              (w_done_r  || (m_axil_wvalid  && m_axil_wready))) begin
            avst <= AV_B;
          end
        end

        AV_B: begin
          if (m_axil_bvalid) avst <= AV_IDLE;
        end

        AV_AR: begin
          if (m_axil_arvalid && m_axil_arready) avst <= AV_R;
        end

        AV_R: begin
          if (m_axil_rvalid) begin
            avs_readdata      <= m_axil_rdata;
            avs_readdatavalid <= 1'b1;
            avst              <= AV_IDLE;
          end
        end

        default: avst <= AV_IDLE;
      endcase
    end
  end

endmodule
