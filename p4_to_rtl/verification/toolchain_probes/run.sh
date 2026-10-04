#!/bin/bash
# Ground truth for the RTL patterns the emitters avoid. Each tNN_*.sv is a
# self-contained module that prints exactly one "RESULT PASS" or "RESULT FAIL ..."
# and calls $finish. Classification:
#   PASS   accepted, and the semantics are right
#   WRONG  compiled and ran, produced the wrong value   (the dangerous outcome)
#   STALL  compiled and ran, never finished             (simulation time stopped)
#   REJECT refused to compile
# See docs/toolchain_constraints.md for the recorded results and what they mean.
set -u
P="$(cd "$(dirname "$0")" && pwd)"
VIV="${VIVADO_BIN:-/tools/Xilinx/Vivado/2020.2/bin}"
[ -x "$VIV/xvlog" ] && export PATH="$VIV:$PATH"
W=$(mktemp -d)
classify() { # $1=rc $2=log
  if   [ "$1" = 124 ];                          then echo STALL
  elif grep -q "RESULT PASS" "$2" 2>/dev/null;  then echo PASS
  elif grep -q "RESULT FAIL" "$2" 2>/dev/null;  then echo WRONG
  else echo REJECT; fi
}
printf "%-36s %-8s %-8s %-8s\n" PROBE iverilog xsim verilator
for f in "$P"/t*.sv; do
  n=$(basename "$f" .sv); d="$W/$n"; mkdir -p "$d"
  if iverilog -g2012 -o "$d/i.vvp" "$f" > "$d/i.log" 2>&1; then
    timeout 10 vvp "$d/i.vvp" >> "$d/i.log" 2>&1; ri=$(classify $? "$d/i.log")
  else ri=REJECT; fi
  if command -v xvlog >/dev/null 2>&1; then
    ( cd "$d" && xvlog -sv "$f" > x1.log 2>&1 && timeout 180 xelab -R top -s s > x2.log 2>&1 )
    rc=$?; cat "$d"/x1.log "$d"/x2.log > "$d/x.log" 2>/dev/null
    grep -q "^ERROR" "$d/x1.log" && rx=REJECT || rx=$(classify $rc "$d/x.log")
  else rx=skip; fi
  if command -v verilator >/dev/null 2>&1; then
    ( cd "$d" && timeout 240 verilator --binary -j 2 --timing -Wno-fatal \
        --top-module top -o vsim "$f" > v1.log 2>&1 && timeout 10 ./obj_dir/vsim > v2.log 2>&1 )
    rc=$?; cat "$d"/v1.log "$d"/v2.log > "$d/v.log" 2>/dev/null
    [ -x "$d/obj_dir/vsim" ] && rv=$(classify $rc "$d/v.log") || rv=REJECT
  else rv=skip; fi
  printf "%-36s %-8s %-8s %-8s\n" "$n" "$ri" "$rx" "$rv"
done
echo; echo "logs: $W"
