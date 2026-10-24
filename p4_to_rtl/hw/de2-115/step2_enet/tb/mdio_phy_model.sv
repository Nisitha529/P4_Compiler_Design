// mdio_phy_model.sv -- a clause 22 MDIO slave, for testing the master against
// something that decodes the frame INDEPENDENTLY.
//
// Not a model of the 88E1111: a model of the PROTOCOL, with a register file the
// testbench fills. If the master's bit order, turnaround or sampling edge are
// wrong, this disagrees -- which a model derived from the master's own code
// could not.
//
// Decoded positionally from the first bit after the preamble, which is how the
// clause 22 frame is actually specified:
//
//   idx  0      ST[1] = 0   (the first 0 after >= 32 ones)
//   idx  1      ST[0] = 1
//   idx  2..3   OP          10 = read, 01 = write
//   idx  4..8   PHYAD       MSB first
//   idx  9..13  REGAD       MSB first
//   idx 14..15  TA          read: master releases, PHY drives 0 then data
//   idx 16..31  DATA        MSB first
//
// Only answers at its own address, so a testbench can check that a scan finds
// it at one address and nothing at the others.
`default_nettype none

module mdio_phy_model #(
    parameter logic [4:0] PHY_ADDR = 5'h10
) (
    input  wire       mdc,
    input  wire       mdio_i,       // the wire's current value
    input  wire       mdio_oe_m,    // whether the master is driving it
    output logic      mdio_o,
    output logic      mdio_oe
);
  logic [15:0] regs [0:31];
  initial for (int i = 0; i < 32; i++) regs[i] = 16'h0000;

  task automatic set_reg(input int idx, input logic [15:0] v);
    regs[idx] = v;
  endtask

  int          ones = 0;
  int          idx  = -1;        // -1 = hunting for the preamble
  logic [1:0]  op   = 2'b00;
  // PHYAD and REGAD captured as ONE 10-bit field and split only when the
  // whole field has arrived. Shifting them into two separate 5-bit registers
  // and comparing part-way through makes neighbouring addresses alias onto
  // each other -- which showed up as a scan that "found" a PHY at 0x08, 0x10
  // and 0x18 when only 0x10 existed.
  logic [9:0]  ad   = 10'h000;
  logic [9:0]  ad_full;   // temp, see the bit-select note below
  logic [4:0]  ra   = 5'h00;
  logic [15:0] wsh  = 16'h0000;
  logic [15:0] osr  = 16'h0000;
  logic        mine = 1'b0;
  logic        rd   = 1'b0;

  initial begin
    mdio_o = 1'b0; mdio_oe = 1'b0;
  end

  always @(posedge mdc) begin
    if (idx < 0) begin
      // preamble hunt: >= 32 ones, then the ST field's leading zero
      if (mdio_oe_m && mdio_i === 1'b1) ones <= ones + 1;
      else if (mdio_oe_m && mdio_i === 1'b0 && ones >= 32) begin
        idx  <= 1;              // this bit was idx 0 (ST[1])
        ones <= 0;
      end else ones <= 0;
    end else begin
      case (idx)
        1: if (mdio_i !== 1'b1) idx <= -1;                 // ST[0] must be 1
        2, 3: op <= {op[0], mdio_i};
        4,5,6,7,8,9,10,11,12,13: begin
          ad <= {ad[8:0], mdio_i};
          if (idx == 13) begin
            // The full 10-bit field is complete only WITH this bit, so the
            // comparison uses it rather than the register's current value.
            // Via a temp, blocking: a bit-select of a concatenation
            // (`{a,b}[9:5]`) is not legal Verilog -- the same rule that bit
            // the Digest status field in the compiler.
            ad_full = {ad[8:0], mdio_i};
            mine <= (ad_full[9:5] == PHY_ADDR);
            ra   <= ad_full[4:0];
            rd   <= (op == 2'b10);
          end
        end
        14, 15: ;                                           // turnaround
        default: begin                                      // 16..31 data
          if (!rd) wsh <= {wsh[14:0], mdio_i};
          if (idx == 31) begin
            if (!rd && mine) regs[ra] = {wsh[14:0], mdio_i};
            idx <= -1;
          end
        end
      endcase
      if (idx >= 1 && idx < 31) idx <= idx + 1;
    end
  end

  // The PHY drives on the FALLING edge, so its data is stable at the master's
  // rising-edge sample -- the discipline a real PHY follows.
  always @(negedge mdc) begin
    if (idx == 15 && rd && mine) begin
      mdio_oe <= 1'b1;             // turnaround: the PHY asserts 0
      mdio_o  <= 1'b0;
      osr     <= regs[ra];
    end else if (idx >= 16 && idx <= 31 && rd && mine) begin
      mdio_oe <= 1'b1;
      mdio_o  <= osr[15];
      osr     <= {osr[14:0], 1'b0};
    end else begin
      mdio_oe <= 1'b0;
      mdio_o  <= 1'b0;
    end
  end
endmodule

`default_nettype wire
