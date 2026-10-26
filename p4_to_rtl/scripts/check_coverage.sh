#!/bin/bash
# Line coverage of the generated RTL, per app, against a recorded baseline.
#
# Why a baseline rather than a target: a fixed percentage is a number somebody
# invented, and it either sits so low it never fires or so high it is always
# failing. A baseline is a RATCHET -- it answers the question that actually
# matters, "did a change make the suite test less than it used to", and it goes
# up when you improve the stimulus.
#
# Baseline: verification/vectors/coverage_baseline.json. Regenerate with
#   scripts/check_coverage.sh --update
# and commit the result, with the reason in the commit message.
#
# Measured by Verilator, replaying each app's committed pcap through the same
# generated testbench the pcap framework verifies with -- so what is measured
# is exactly what is verified. The testbench's own lines are excluded: it is
# the stimulus, and counting it would flatter the number.
set -u
R="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="${P4C_BIN:-/home/nisitha/p4c/build}:$PATH"
V="$R/verification/vectors"
BASE="$V/coverage_baseline.json"
UPDATE=0
[ "${1:-}" = "--update" ] && UPDATE=1
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
rc=0

command -v verilator >/dev/null 2>&1 || {
  echo "verilator not found -- skipping coverage"; exit 0; }

echo '{' > "$W/new.json"
first=1
for d in "$V"/*/; do
  app=$(basename "$d")
  [ -f "$d/traffic.pcap" ] || continue
  flags=""
  [ -f "$d/flags.txt" ] && flags=$(cat "$d/flags.txt")
  out=$(cd "$R" && timeout 1800 python3 verification/framework/coverage.py "$app" \
          --pcap "$d/traffic.pcap" --testcase "$d/entries.txt" \
          ${flags:+--gen-flags "$flags"} --work "$W/$app" \
          --json "$W/$app.json" 2>&1 | tail -1)
  pct=$(python3 -c "
import json,sys
try:  print(json.load(open('$W/$app.json'))['pct'])
except Exception: print(-1)")
  if [ "$pct" = "-1" ]; then
    echo "FAIL $app: $out"; rc=1; continue
  fi
  [ $first -eq 0 ] && echo ',' >> "$W/new.json"
  first=0
  printf '  "%s": %s' "$app" "$pct" >> "$W/new.json"
  if [ -f "$BASE" ] && [ $UPDATE -eq 0 ]; then
    want=$(python3 -c "
import json
b=json.load(open('$BASE'))
print(b.get('$app', -1))")
    drop=$(python3 -c "print(1 if $want > 0 and $pct < $want - 1.0 else 0)")
    if [ "$drop" = "1" ]; then
      echo "FAIL $app: coverage $pct% is below its baseline $want% (more than 1 point)"
      rc=1
    else
      echo "ok   $app: $pct% line coverage (baseline $want%)"
    fi
  else
    echo "ok   $app: $pct% line coverage"
  fi
done
echo '' >> "$W/new.json"; echo '}' >> "$W/new.json"

if [ $UPDATE -eq 1 ]; then
  python3 -c "
import json
d=json.load(open('$W/new.json'))
json.dump(d, open('$BASE','w'), indent=1, sort_keys=True)
open('$BASE','a').write('\n')
print('baseline written:', '$BASE', len(d), 'app(s)')"
fi
exit $rc
