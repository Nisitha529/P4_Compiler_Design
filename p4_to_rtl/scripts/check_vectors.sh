#!/bin/bash
# Run every committed pcap through the design AND the reference model, and
# require them to agree byte for byte.
#
# This is the project's only ORACLE-based test. Everything else in the suite
# states expectations a human worked out by reading the P4 -- which checks the
# RTL against someone's reading of the program. This checks it against an
# executable reading, over real traffic, and the traffic is a pcap so a
# designer can point it at their own program with their own capture:
#
#   python3 verification/framework/p4v.py <app> --pcap mine.pcap \
#           --testcase entries.txt
#
# Every app directory under verification/vectors/ MUST pass. Programs whose
# constructs the model cannot represent (a UserExtern's RTL is unknowable, a
# Meter's bucket is implementation-defined, multicast replicates, a varbit
# header has no fixed layout) have no directory here, and p4v reports them as
# NOT VERIFIED rather than passing them -- see docs/compiler_design.md.
set -u
R="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="${P4C_BIN:-/home/nisitha/p4c/build}:$PATH"
V="$R/verification/vectors"
rc=0

for d in "$V"/*/; do
  app=$(basename "$d")
  [ -f "$d/traffic.pcap" ] || continue
  flags=""
  [ -f "$d/flags.txt" ] && flags=$(cat "$d/flags.txt")
  out=$(cd "$R" && timeout 1800 python3 verification/framework/p4v.py "$app" \
          --pcap "$d/traffic.pcap" --testcase "$d/entries.txt" \
          ${flags:+--gen-flags "$flags"} --quiet 2>&1)
  line=$(echo "$out" | grep -E "PASS|FAIL|NOT VERIFIED|VACUOUS|REORDERED" | head -1)
  case "$line" in
    *PASS*) echo "ok   $line" ;;
    '')     echo "FAIL $app: no verdict"; echo "$out" | tail -3 | sed 's/^/     /'; rc=1 ;;
    *)      echo "FAIL $line"; rc=1 ;;
  esac
done
exit $rc
