// host_regs.sv -- a tiny AXI4-Lite slave whose only job is to prove the host
// link works, end to end, before anything depends on it.
//
// Step 3 programs match-action tables from the PC over this exact path
// (USB-Blaster cable -> JTAG -> Intel's JTAG-to-Avalon-Master bridge ->
// avmm_axil_lite_bridge -> an AXI4-Lite control plane). If that path is not
// known-good first, a table that does not match looks identical to a link
// that silently dropped the write.
//
// Register map (word addresses, as System Console sees them x4 for bytes):
//   0  ID        R   0xDE2115_01 -- a constant. Reading it proves you are
//                    talking to THIS design on THIS board, not to a stale
//                    bitstream or a bridge that returns zeros.
//   1  SCRATCH   RW  any value, stored and returned. Proves writes land.
//   2  LEDS      RW  low 18 bits drive LEDR -- a write you can SEE, which
//                    distinguishes "the write reached the fabric" from "the
//                    readback path happens to echo".
//   3  HEXVAL    RW  low 32 bits drive the eight 7-segment digits.
//   4  TICKS     R   a free-running counter. Two reads returning the same
//                    value means the design is not running, even though the
//                    link is answering.
//   5  BUILD     R   0x<major><minor><patch> of this bring-up design.
`default_nettype none

module host_regs #(
    parameter int ADDR_W = 16
) (
    input  wire               clk,
    input  wire               rst_n,

    input  wire [ADDR_W-1:0]  s_axil_awaddr,
    input  wire               s_axil_awvalid,
    output logic              s_axil_awready,
    input  wire [31:0]        s_axil_wdata,
    input  wire [3:0]         s_axil_wstrb,
    input  wire               s_axil_wvalid,
    output logic              s_axil_wready,
    output logic [1:0]        s_axil_bresp,
    output logic              s_axil_bvalid,
    input  wire               s_axil_bready,
    input  wire [ADDR_W-1:0]  s_axil_araddr,
    input  wire               s_axil_arvalid,
    output logic              s_axil_arready,
    output logic [31:0]       s_axil_rdata,
    output logic [1:0]        s_axil_rresp,
    output logic              s_axil_rvalid,
    input  wire               s_axil_rready,

    output logic [17:0]       leds,
    output logic [31:0]       hexval,
    output logic              wr_seen,     // pulses on any write: LED activity
    output logic              rd_seen
);
  localparam logic [31:0] ID_VALUE    = 32'hDE21_1501;
  localparam logic [31:0] BUILD_VALUE = 32'h0001_0000;

  logic [31:0] scratch, ticks;
  logic [ADDR_W-1:0] awaddr_q;

  // Write channel. AW and W are accepted independently and the write commits
  // when both have arrived -- the same shape the compiler's own decoder uses,
  // because a master is allowed to present them in either order.
  typedef enum logic [1:0] {W_IDLE, W_DATA, W_RESP} wst_t;
  wst_t wst;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      wst            <= W_IDLE;
      s_axil_awready <= 1'b0;
      s_axil_wready  <= 1'b0;
      s_axil_bvalid  <= 1'b0;
      scratch        <= 32'h0;
      leds           <= 18'h0;
      hexval         <= 32'h0;
      awaddr_q       <= '0;
      wr_seen        <= 1'b0;
    end else begin
      wr_seen <= 1'b0;
      case (wst)
        W_IDLE: begin
          s_axil_awready <= 1'b1;
          s_axil_bvalid  <= 1'b0;
          if (s_axil_awvalid) begin
            awaddr_q       <= s_axil_awaddr;
            s_axil_awready <= 1'b0;
            s_axil_wready  <= 1'b1;
            wst            <= W_DATA;
          end
        end
        W_DATA: if (s_axil_wvalid) begin
          s_axil_wready <= 1'b0;
          case (awaddr_q[ADDR_W-1:2])
            'd1: scratch <= s_axil_wdata;
            'd2: leds    <= s_axil_wdata[17:0];
            'd3: hexval  <= s_axil_wdata;
            default: ;            // read-only or unmapped: accepted, ignored
          endcase
          wr_seen       <= 1'b1;
          s_axil_bvalid <= 1'b1;
          wst           <= W_RESP;
        end
        W_RESP: if (s_axil_bready) begin
          s_axil_bvalid <= 1'b0;
          wst           <= W_IDLE;
        end
        default: wst <= W_IDLE;
      endcase
    end
  end
  assign s_axil_bresp = 2'b00;

  // Read channel.
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      s_axil_arready <= 1'b1;
      s_axil_rvalid  <= 1'b0;
      s_axil_rdata   <= 32'h0;
      ticks          <= 32'h0;
      rd_seen        <= 1'b0;
    end else begin
      ticks   <= ticks + 32'd1;
      rd_seen <= 1'b0;
      if (s_axil_arready && s_axil_arvalid) begin
        case (s_axil_araddr[ADDR_W-1:2])
          'd0: s_axil_rdata <= ID_VALUE;
          'd1: s_axil_rdata <= scratch;
          'd2: s_axil_rdata <= {14'd0, leds};
          'd3: s_axil_rdata <= hexval;
          'd4: s_axil_rdata <= ticks;
          'd5: s_axil_rdata <= BUILD_VALUE;
          default: s_axil_rdata <= 32'hDEAD_BEEF;   // unmapped, and says so
        endcase
        s_axil_arready <= 1'b0;
        s_axil_rvalid  <= 1'b1;
        rd_seen        <= 1'b1;
      end else if (s_axil_rvalid && s_axil_rready) begin
        s_axil_rvalid  <= 1'b0;
        s_axil_arready <= 1'b1;
      end
    end
  end
  assign s_axil_rresp = 2'b00;
endmodule

`default_nettype wire
