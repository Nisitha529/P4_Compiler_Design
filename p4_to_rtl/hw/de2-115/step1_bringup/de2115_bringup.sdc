# de2115_bringup.sdc -- the board's real 50 MHz oscillator, nothing else.
#
# CLOCK_50 is a 50 MHz on-board oscillator (user manual: "50 MHz clock input",
# PIN_Y2), so the period is 20.000 ns. The design runs straight off it with no
# PLL, on purpose: step 1 exists to remove variables, and a PLL is one more
# thing that can fail to lock.

create_clock -name CLOCK_50 -period 20.000 [get_ports {CLOCK_50}]
derive_clock_uncertainty

# KEY and SW are a human's fingers. They are registered twice inside the
# design before use (and the KEYs are Schmitt-debounced in hardware), so there
# is no timing relationship to analyse -- without this, every one of the 22
# input pins reports an unconstrained-path warning that buries the real ones.
set_false_path -from [get_ports {KEY[*]}] -to *
set_false_path -from [get_ports {SW[*]}]  -to *

# The LEDs and displays are looked at by a person, not sampled by a chip.
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
