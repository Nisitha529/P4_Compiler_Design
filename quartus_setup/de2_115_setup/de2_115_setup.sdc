# de2_115_setup.sdc -- real timing constraint for the DE2-115 fiveTuple bring-up.
# CLOCK_50 is the board's real 50MHz oscillator (period = 1/50MHz = 20.000ns).
# Replaces the compiler-generated skeleton's 100MHz placeholder, which was
# never a real target -- this design runs directly off CLOCK_50, no PLL.

create_clock -name CLOCK_50 -period 20.000 [get_ports {CLOCK_50}]

# Standard TimeQuest hygiene: without this, Quartus flags every clock
# transfer as missing an uncertainty assignment (Critical Warning 332168,
# already seen for the JTAG debug fabric's own internal TCK clock in past
# runs -- this covers the real design clock the same way).
derive_clock_uncertainty
