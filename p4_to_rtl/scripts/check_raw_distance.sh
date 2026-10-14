#!/bin/bash
# Check the reported Register RAW distance in BOTH register modes.
#
# The regression's per-testbench loop runs each app once, in whatever mode it
# was last generated in -- so it only ever covered the default asynchronous
# read. The synchronous (--register-ram) read is one packet FURTHER apart,
# because the address is presented a stage early and the memory is sampled at
# that earlier edge. Reporting the async number for both modes understated the
# hazard by one packet, which is the direction that bites: a program trusting
# it would space packets too closely. That bug is why this script exists.
#
# Regenerates rawprobe in each mode, reads the distance the compiler printed,
# and runs tb_rawprobe with RAW_D set to it -- so the test checks the compiler's
# own claim rather than a number hardcoded here.
set -u
R="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="${P4C_BIN:-/home/nisitha/p4c/build}:$PATH"
W=$(mktemp -d); rc=0

for mode in "" "--register-ram"; do
  label=${mode:-default}
  out=$(cd "$R" && python3 compiler/main.py rawprobe $mode 2>&1)
  d=$(echo "$out" | grep -oE "RAW distance [0-9]+" | head -1 | awk '{print $3}')
  if [ -z "$d" ]; then
    echo "FAIL $label: the compiler printed no RAW distance"; rc=1; continue
  fi
  G="$R/generated/rawprobe"
  files=$(ls "$G"/*.sv | grep -v _pkg | grep -v selftest)
  if ! iverilog -g2012 -Ptb_rawprobe.RAW_D="$d" -o "$W/rp.vvp" \
        "$G"/rawprobe_pkg.sv $files "$G"/testbench/tb_rawprobe.sv 2> "$W/b.log"; then
    echo "FAIL $label: build error"; grep -vE "sorry|empty port|warning" "$W/b.log" | head -3; rc=1; continue
  fi
  res=$(timeout 120 vvp "$W/rp.vvp" 2>&1 | grep -oE "Results: [0-9]+ passed, [0-9]+ failed" | tail -1)
  fails=$(echo "$res" | awk '{print $4}')
  if [ "${fails:-1}" = "0" ]; then
    echo "ok   $label: reported distance $d, measured behaviour agrees ($res)"
  else
    echo "FAIL $label: reported distance $d but $res"; rc=1
  fi
done

# leave rawprobe in the default mode the rest of the regression expects
(cd "$R" && python3 compiler/main.py rawprobe > /dev/null 2>&1)
exit $rc
