// mdio_master.sv -- IEEE 802.3 clause 22 MDIO station management master.
//
// This is the whole of step 2a: two wires that tell you whether the Ethernet
// PHY is alive, what it is, and what the link is doing. It needs no knowledge
// of the data interface (MII/GMII/RGMII), which is exactly why it comes first
// -- the DE2-115's PHYs are strapped to RGMII/GMII by default (user manual
// Table 4-20, HWCFG[3:0] = 1011/1111), so a data path built on an assumption
// about the mode can fail for a reason you cannot see. MDIO lets you ASK.
//
// Frame format (clause 22.2.4.5): 32 bits of preamble (all ones), ST = 01,
// OP = 10 read / 01 write, PHYAD[4:0], REGAD[4:0], then a 2-bit turnaround and
// 16 data bits. On a read the master releases MDIO during turnaround and the
// PHY drives a 0 followed by the data.
//
// Clocking: MDC is derived by integer division from clk. 2.5 MHz is what the
// DE2-115 user manual itself specifies for this PHY ("the desired MDC clock
// frequency is 2.5MHz"), so from 50 MHz the divider is 20.
//
// MDIO is open-drain/bidirectional on the wire; this module exposes it as
// separate o/oe/i so the TRISTATE lives at the top level, where the pin is.
`default_nettype none

module mdio_master #(
    parameter int CLK_HZ = 50_000_000,
    parameter int MDC_HZ = 2_500_000
) (
    input  wire        clk,
    input  wire        rst,

    input  wire        start,        // pulse to begin a transaction
    input  wire        we,           // 1 = write, 0 = read
    input  wire [4:0]  phy_ad,
    input  wire [4:0]  reg_ad,
    input  wire [15:0] wdata,
    output logic [15:0] rdata,
    output logic       done,         // one-cycle pulse when rdata is valid
    output logic       busy,
    // a read whose turnaround bit was not driven low by any PHY: nothing
    // answered at that address. Reported rather than returned as 0xFFFF,
    // because "no PHY there" and "a PHY holding all ones" are different facts.
    output logic       no_reply,

    output logic       mdc,
    output logic       mdio_o,
    output logic       mdio_oe,      // 1 = master drives the wire
    input  wire        mdio_i
);
  localparam int DIV      = CLK_HZ / MDC_HZ;      // full MDC period in clk
  localparam int HALF     = DIV / 2;
  localparam int DIV_W    = (HALF <= 1) ? 1 : $clog2(HALF + 1);
  localparam int NBITS    = 32 + 2 + 2 + 5 + 5 + 2 + 16;   // 64

  typedef enum logic [1:0] {IDLE, RUN, FINISH} st_t;
  st_t st;

  logic [DIV_W-1:0] div_cnt;
  logic [6:0]       bit_idx;        // 0..63
  logic             mdc_q;
  logic [15:0]      shift_in;
  logic             ta_seen_low;

  // The bit the master drives at index i, and whether it drives at all.
  // Written as a function of the index rather than a shift register so the
  // frame layout is readable against the clause 22 field list above.
  logic        drive;
  logic        bit_out;
  always_comb begin
    drive   = 1'b1;
    bit_out = 1'b1;
    if (bit_idx < 32) begin                    // preamble: 32 ones
      bit_out = 1'b1;
    end else if (bit_idx < 34) begin           // ST = 01
      bit_out = (bit_idx == 33);
    end else if (bit_idx < 36) begin           // OP = 10 read / 01 write
      bit_out = we ? (bit_idx == 35) : (bit_idx == 34);
    end else if (bit_idx < 41) begin           // PHYAD, MSB first
      bit_out = phy_ad[4 - (bit_idx - 36)];
    end else if (bit_idx < 46) begin           // REGAD, MSB first
      bit_out = reg_ad[4 - (bit_idx - 41)];
    end else if (bit_idx < 48) begin           // turnaround
      // write: the master drives 10. read: the master lets go, and the PHY
      // drives 0 on the second bit.
      drive   = we;
      bit_out = (bit_idx == 46);
    end else begin                             // 16 data bits, MSB first
      drive   = we;
      bit_out = we ? wdata[15 - (bit_idx - 48)] : 1'b1;
    end
  end

  assign busy = (st != IDLE);

  always_ff @(posedge clk) begin
    if (rst) begin
      st        <= IDLE;
      mdc       <= 1'b0;
      mdc_q     <= 1'b0;
      div_cnt   <= '0;
      bit_idx   <= '0;
      rdata     <= '0;
      shift_in  <= '0;
      done      <= 1'b0;
      no_reply  <= 1'b0;
      mdio_o    <= 1'b1;
      mdio_oe   <= 1'b0;
      ta_seen_low <= 1'b0;
    end else begin
      done <= 1'b0;
      case (st)
        IDLE: begin
          mdc     <= 1'b0;
          mdio_oe <= 1'b0;
          if (start) begin
            st          <= RUN;
            bit_idx     <= '0;
            div_cnt     <= '0;
            mdc         <= 1'b0;
            shift_in    <= '0;
            ta_seen_low <= 1'b0;
            no_reply    <= 1'b0;
          end
        end

        RUN: begin
          // Drive the current bit while MDC is low; the PHY samples it on the
          // rising edge (clause 22.3.4), so it is set up a half period early.
          mdio_oe <= drive;
          mdio_o  <= bit_out;

          if (div_cnt == DIV_W'(HALF - 1)) begin
            div_cnt <= '0;
            mdc     <= ~mdc;
            mdc_q   <= mdc;
            if (!mdc) begin
              // about to go HIGH: this is the edge the PHY samples on, and
              // the edge on which the PHY's own read data is stable
              if (!we && bit_idx >= 47) begin
                if (bit_idx == 47) begin
                  // the PHY's turnaround bit: a 0 here is the only evidence
                  // that something is actually out there
                  if (!mdio_i) ta_seen_low <= 1'b1;
                end else begin
                  shift_in <= {shift_in[14:0], mdio_i};
                end
              end
            end else begin
              // about to go LOW: one full MDC period done, advance
              if (bit_idx == NBITS - 1) st <= FINISH;
              else                      bit_idx <= bit_idx + 1'b1;
            end
          end else begin
            div_cnt <= div_cnt + 1'b1;
          end
        end

        FINISH: begin
          mdio_oe  <= 1'b0;
          mdc      <= 1'b0;
          rdata    <= we ? wdata : shift_in;
          no_reply <= !we && !ta_seen_low;
          done     <= 1'b1;
          st       <= IDLE;
        end

        default: st <= IDLE;
      endcase
    end
  end
endmodule

`default_nettype wire
