# DE2-115 bring-up, in stages

Three designs, meant to be run in order. Each one answers a question that the
next one depends on, so that when something fails you know which layer it is
in. None of them contains any P4 logic: that is step 3, and it is only worth
starting once these pass.

| step | design | question it answers |
|---|---|---|
| 1 | `step1_bringup/` | Is the board alive? Clock, LEDs, displays, buttons, switches. |
| 2a | `step2_enet/` | Is the Ethernet PHY there, what is it, and what is the link doing? |
| 2b | `step2_host/` | Can the PC reach the FPGA fabric over the USB cable? |

All three are verified in simulation and compiled for `EP4CE115F29C7` with
Quartus Prime Lite 25.1std. Each directory holds a programmable `.sof`.

| | logic elements | registers | pins | worst setup slack | testbench |
|---|---|---|---|---|---|
| step 1 | 187 (<1%) | 106 | 106 (20%) | 12.96 ns | 18/18 |
| step 2a | 389 (<1%) | 233 | 126 (24%) | 14.05 ns (CLOCK_50), 7.15 ns (RX_CLK) | 16/16 + 9/9 |
| step 2b | 1,435 (1%) | 841 | 106 (20%) | 14.18 ns | 10/10 |

## Step 1 — is the board alive?

```bash
cd step1_bringup
quartus_sh --flow compile de2115_bringup
quartus_pgm -m jtag -o "p;de2115_bringup.sof"
```

What you should see, and what each thing tells you:

* **LEDG[8] blinks once a second.** Time it against a watch. A wrong rate means
  CLOCK_50 is not 50 MHz, and every timing number from here on would be built
  on a false premise.
* **HEX7..HEX2 read `DE2115`.** The word is known, so a dead segment, a swapped
  digit or an inverted drive is obvious instead of plausible.
* **One red LED walks across all 18.** A position that never lights is a pin
  assignment that is wrong, not an LED that is broken.
* **HEX1..HEX0 count seconds in hex.**

Then exercise the inputs:

| press | expect |
|---|---|
| `KEY[0]` | everything restarts: the walk returns to LEDR[0], the counter to 0 |
| `KEY[1]` held | LEDR mirrors SW[17:0] — flip each switch and watch its own LED follow |
| `KEY[2]` held | lamp test: all 27 LEDs on, all 8 digits showing `8` |
| `KEY[3]` held | everything freezes mid-blink |

If step 1 fails, nothing after it is worth debugging.

## Step 2a — the Ethernet PHY

```bash
cd step2_enet
quartus_sh --flow compile de2115_enet
quartus_pgm -m jtag -o "p;de2115_enet.sof"
```

This design **measures** rather than assumes. It scans all 32 MDIO addresses,
reports which answered, reads the IEEE identity registers and the link status,
and detects whether the PHY's receive clock is running — without decoding any
data, so the result is valid whatever interface mode the PHY is in.

* **LEDG[0]** a PHY answered on MDIO
* **LEDG[1]** its identity matches a Marvell 88E1111
* **LEDG[2]** link up, **LEDG[3]** auto-negotiation complete
* **LEDG[4]** the PHY's RX clock is running, **LEDG[5]** frames are arriving
* **LEDG[8]** heartbeat — so a frozen design and a quiet link do not look alike
* **HEX7 HEX6** the MDIO address that answered — expect `10`
* **HEX5 HEX4** the register being displayed, **HEX3..HEX0** its value
* **SW[4:0]** picks the register; **SW[17]** shows the scan map on LEDR

Plug a cable into **ENET0** (the socket nearer the power connector — confirm
against the silkscreen) and expect LEDG[2] to light within a few seconds.

Worth knowing before step 3: the DE2-115's PHYs come up strapped to
**RGMII- or GMII-to-copper, not MII** (user manual Table 4-20, `HWCFG[3:0]` =
`1011`/`1111`), with auto-negotiation advertising everything. So read what this
design reports from register 17 before committing to a data-path design — and
note that `de2115_enet.sdc` currently declares the RX data pins as false paths
because this step never samples them. **A step-3 design that samples
`ENET0_RX_DATA` must replace that with a real `set_input_delay`** derived from
the 88E1111's output timing, or its data path will never have been
timing-checked.

ENET1 is held in reset throughout, so it cannot interfere.

## Step 2b — the host link over the USB cable

```bash
cd step2_host
qsys-generate jtag_to_avalon_mst_brg_01.qsys --synthesis=VERILOG \
    --family="Cyclone IV E" --part=EP4CE115F29C7
quartus_sh --flow compile de2115_host
quartus_pgm -m jtag -o "p;de2115_host.sof"
```

**Which USB this is.** The DE2-115 has two unrelated USB things, and only one
of them is on the path between your PC and the FPGA:

* the **USB-Blaster** port — the JTAG programming and debug cable. Every host
  tool uses it, and the P4 control plane will run over it. This is what step 2b
  tests.
* a **Cypress CY7C67200** USB host/peripheral controller with its own type-A
  and type-B sockets (user manual 4.10, the `OTG_*` pins). That is a separate
  chip for attaching USB devices *to* the board. Nothing in a P4 pipeline needs
  it. Its pins are in `common/pins_otg.qsf` if you want it later; driving it
  means implementing its host-port interface and a USB stack, which is a
  project of its own.

The path under test is the one step 3 needs for programming tables:

```
PC (System Console) → USB-Blaster → JTAG
   → Intel JTAG-to-Avalon-Master bridge
   → avmm_axil_lite_bridge   (rtl/common, already in this repo)
   → an AXI4-Lite register block
```

From Quartus: **Tools → System Debugging Tools → System Console**, then

```tcl
set m [lindex [get_service_paths master] 0]
open_service master $m
master_read_32  $m 0x0  1          ;# 0xde211501 -- the design's ID
master_write_32 $m 0x4  0x12345678
master_read_32  $m 0x4  1          ;# 0x12345678 -- a write that landed
master_write_32 $m 0x8  0x3ffff    ;# all 18 red LEDs on -- VISIBLE
master_write_32 $m 0xc  0xcafe1234 ;# the 7-segment displays
master_read_32  $m 0x10 1          ;# ticks: read twice, must differ
```

Reading the ID proves you are talking to this design and not a stale
bitstream. Writing the LEDs proves the write reached the fabric rather than
being echoed by a readback path. Two different tick values prove the design is
running, not merely answering.

## Where the pin assignments come from

Every pin in `common/pins_*.qsf` is **generated**, by
`common/make_pins.py`, from two independent sources that have to agree:

1. the official Terasic DE2-115 user manual's pin tables, and
2. a DE2-115 project that Quartus has fitted and that runs Ethernet on this
   board (Alex Forencich's `verilog-ethernet` DE2-115 example).

A disagreement between them is a hard error and nothing is emitted; a signal
only one source has is listed as unconfirmed and left out. 176 pins agree, with
zero conflicts. Regenerate and re-check with:

```bash
python3 common/make_pins.py --manual /path/to/DE2_115_User_manual.pdf \
    --reference /path/to/verilog-ethernet/example/DE2-115/fpga/fpga.qsf
```

Terasic has shipped more than one DE2-115 revision. Verify against your own
board's System Builder output before programming anything that drives a shared
bus.

Two polarity facts these designs depend on, both from the manual rather than
assumed: the LEDs are **active high** ("driving its associated pin to a high
logic level turns the LED on"), the 7-segment displays are **common anode** so
a segment lights when its pin is driven **low**, and the push-buttons are
**active low** and already Schmitt-debounced in hardware.

## Simulating any of it

```bash
# step 1
iverilog -g2012 -o /tmp/s1.vvp common/seg7.sv step1_bringup/de2115_bringup_top.sv \
    step1_bringup/tb/tb_bringup.sv && vvp /tmp/s1.vvp

# step 2a: the MDIO master against an independent clause-22 slave model
iverilog -g2012 -o /tmp/md.vvp common/mdio_master.sv \
    step2_enet/tb/mdio_phy_model.sv step2_enet/tb/tb_mdio_master.sv && vvp /tmp/md.vvp

# step 2a: the whole design against a PHY at the strapped address
iverilog -g2012 -o /tmp/s2.vvp common/seg7.sv common/mdio_master.sv \
    step2_enet/de2115_enet_top.sv step2_enet/tb/mdio_phy_model.sv \
    step2_enet/tb/tb_enet_top.sv && vvp /tmp/s2.vvp

# step 2b: the host path through the real bridge
iverilog -g2012 -o /tmp/s3.vvp ../../rtl/common/avmm_axil_lite_bridge.sv \
    step2_host/host_regs.sv step2_host/tb/tb_host_regs.sv && vvp /tmp/s3.vvp
```
