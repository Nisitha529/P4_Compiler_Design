# de2115_host.sdc -- the board oscillator, plus whatever clock the JTAG debug
# fabric brings with it.

create_clock -name CLOCK_50 -period 20.000 [get_ports {CLOCK_50}]

# The JTAG-to-Avalon-Master IP carries its own TCK-derived clock, created by
# Quartus itself from the JTAG hub. derive_clock_uncertainty after the base
# clock covers both; without it Quartus reports critical warning 332168 for the
# debug fabric's clock, which this project has seen before on this board.
derive_clock_uncertainty

# JTAG debug access is not synchronous to the design clock, and it is driven by
# a human typing into System Console at kilohertz rates.
set_clock_groups -asynchronous -group [get_clocks {CLOCK_50}] -group [get_clocks {altera_reserved_tck}]

set_false_path -from [get_ports {KEY[*]}] -to *
set_false_path -from [get_ports {SW[*]}]  -to *
set_false_path -from * -to [get_ports {LEDR[*]}]
set_false_path -from * -to [get_ports {LEDG[*]}]
set_false_path -from * -to [get_ports {HEX0[*]}]
set_false_path -from * -to [get_ports {HEX1[*]}]
set_false_path -from * -to [get_ports {HEX2[*]}]
set_false_path -from * -to [get_ports {HEX3[*]}]
set_false_path -from * -to [get_ports {HEX4[*]}]
set_false_path -from * -to [get_ports {HEX5[*]}]
set_false_path -from * -to [get_ports {HEX6[*]}]
set_false_path -from * -to [get_ports {HEX7[*]}]

# Expected: three ports report as unconstrained -- altera_reserved_tdi,
# altera_reserved_tms and altera_reserved_tdo. Those are the device's dedicated
# JTAG pins, owned by Quartus's own debug fabric rather than by this design, and
# there is nothing meaningful for a user constraint to say about them. Noted
# here so the count is understood rather than investigated: every port this
# design actually owns IS constrained.
