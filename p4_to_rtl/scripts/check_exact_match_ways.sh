#!/bin/bash
# The d-way set-associative exact-match table (--exact-match-ways).
#
# This test was sitting in the regression's per-app loop, where it could never
# pass: it needs the app generated with --exact-match-ways 4 and the committed
# build is ways=1, so it failed on every run for weeks and became part of the
# background noise that made the suite's exit status meaningless. Its own
# header said what it needed; nothing acted on it.
#
# It is worth recovering rather than deleting, and not only for tidiness:
# set-associativity is the fix for the collision limitation the randomised
# stimulus runs into (two keys that fold to the same index cannot both be held
# at ways=1 -- see verification/framework/tablemap.py). This is the only test
# of that path.
set -u
R="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="${P4C_BIN:-/home/nisitha/p4c/build}:$PATH"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
TB="$R/verification/exact_match_ways/tb_mac_lookup_table_assoc_standalone.sv"
rc=0

if ! (cd "$R" && python3 compiler/main.py multicast --exact-match-ways 4 \
        --out-dir "$W/gen") > "$W/gen.log" 2>&1; then
  echo "FAIL ways=4: generation failed"; tail -3 "$W/gen.log" | sed 's/^/     /'
  exit 1
fi
files=$(ls "$W"/gen/*.sv | grep -v _pkg | grep -v selftest)
if ! iverilog -g2012 -o "$W/a.vvp" "$W"/gen/*_pkg.sv $files "$TB" 2> "$W/b.log"; then
  echo "FAIL ways=4: build error"
  grep -vE "sorry|warning" "$W/b.log" | head -3 | sed 's/^/     /'
  exit 1
fi
res=$(timeout 300 vvp "$W/a.vvp" 2>&1 | grep -oE "Results: [0-9]+ passed, [0-9]+ failed" | tail -1)
fails=$(echo "$res" | awk '{print $4}')
if [ "${fails:-1}" = "0" ] && [ -n "$res" ]; then
  echo "ok   ways=4 set-associative table: $res"
else
  echo "FAIL ways=4 set-associative table: ${res:-no result}"; rc=1
fi
exit $rc
