#!/bin/bash
# A short randomised campaign per app, against the reference model.
#
# FIXED SEED on purpose. A regression that generates fresh random cases every
# run is flaky by construction: it fails on someone else's machine, for a case
# nobody can reproduce, and the response becomes "run it again". With a fixed
# seed this is a deterministic test that happens to have been written by a
# generator, and a change in its result means a change in the design.
#
# The exploratory campaigns are a separate activity, run by hand with a random
# seed and many more iterations:
#
#   python3 verification/framework/fuzz.py <app> --iterations 2000
#
# When one of those finds something, it prints a minimal reproducer and the
# seed; add the reproducer to verification/vectors/ and it becomes a permanent
# directed test.
set -u
R="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="${P4C_BIN:-/home/nisitha/p4c/build}:$PATH"
V="$R/verification/vectors"
SEED=${FUZZ_SEED:-777}
ITER=${FUZZ_ITER:-6}
rc=0

for d in "$V"/*/; do
  app=$(basename "$d")
  [ -f "$d/traffic.pcap" ] || continue
  flags=""
  [ -f "$d/flags.txt" ] && flags=$(cat "$d/flags.txt")
  out=$(cd "$R" && timeout 1800 python3 verification/framework/fuzz.py "$app" \
          --iterations "$ITER" --seed "$SEED" ${flags:+--gen-flags "$flags"} \
          --quiet 2>&1)
  line=$(echo "$out" | grep -E "PASS=|FAIL|NOT VERIFIED|MINIMAL|cannot" | head -1)
  if echo "$line" | grep -q "PASS="; then
    echo "ok   $app: $line"
  else
    echo "FAIL $app: ${line:-no verdict}"
    echo "$out" | grep -E "MINIMAL|reproduce|seed" | head -3 | sed 's/^/     /'
    rc=1
  fi
done
exit $rc
