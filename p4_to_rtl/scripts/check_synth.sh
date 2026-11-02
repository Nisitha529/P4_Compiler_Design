#!/bin/bash
# Does the generated RTL actually SYNTHESIZE, and has its size moved?
#
# Why this exists. Everything else in this suite runs the design in a
# SIMULATOR, and the two simulators here are permissive in the same direction
# Quartus is strict: an unpacked array driven from two always_ff blocks is
# accepted by both iverilog and Verilator and REJECTED outright by Quartus
# ("Can't resolve multiple constant drivers"). The PacketTooShort check added
# on 2026-10-28 did exactly that to slot_too_short[], so for four days NO app
# would synthesize while 985 assertions, the oracle, the fuzzer and the
# coverage ratchet were all green. The first Quartus run on a generated app
# found it in seven seconds.
#
# quartus_map (Analysis & Synthesis) only -- not a full fit. That is the
# deliberate trade: map catches elaboration and inference errors, which is the
# class above, and takes seconds rather than the minutes a fit and timing
# analysis take. Fmax needs quartus_fit + quartus_sta and belongs in a
# separate, slower job.
#
# Baseline: verification/synth_baseline.json, a RATCHET on size with a
# tolerance -- same reasoning as the coverage baseline. Logic that jumps is a
# fact worth a failing test; logic that shrinks updates the record.
#
#   scripts/check_synth.sh            # check
#   scripts/check_synth.sh --update   # re-record the baseline, and say why in
#                                     # the commit message
set -u
R="$(cd "$(dirname "$0")/.." && pwd)"
QBIN="${QUARTUS_BIN:-/data/intelFPGA_lite/25.1std/quartus/bin}"
BASE="$R/verification/synth_baseline.json"
# Tolerance in percent: below this a size change is noise (a different Quartus
# build, a different seed), above it somebody should know.
TOL=${SYNTH_TOL:-10}
UPDATE=0
[ "${1:-}" = "--update" ] && UPDATE=1
rc=0

[ -x "$QBIN/quartus_map" ] || {
  echo "quartus_map not found under $QBIN -- skipping synthesis check"; exit 0; }

W=$(mktemp -d); trap 'rm -rf "$W"' EXIT

# One app per distinct shell shape, not all eighteen: the point is to catch a
# construct the simulators accept and Quartus does not, and that is a property
# of the SHELL, so the shapes are what need covering.
#   lmprobe            egress control + Register, no traffic manager queueing
#   mcprobe            multicast replication (two writers into one TM queue)
#   fiveTuple          varbit parsing + length-changing deparser
#   load_balance_xsa   the xsa architecture, checksum, three tables
APPS="${SYNTH_APPS:-lmprobe mcprobe fiveTuple load_balance_xsa}"

echo '{' > "$W/new.json"
first=1
for app in $APPS; do
  gen="$R/generated/$app"
  [ -d "$gen" ] || { echo "FAIL $app: no generated/ directory"; rc=1; continue; }
  d="$W/$app"; mkdir -p "$d"
  cp "$gen"/*.sv "$d"/ 2>/dev/null
  {
    echo 'set_global_assignment -name FAMILY "Cyclone IV E"'
    echo 'set_global_assignment -name DEVICE EP4CE115F29C7'
    echo "set_global_assignment -name TOP_LEVEL_ENTITY ${app}_top"
    # SYNTHESIS=1 is what the generated RTL's translate_off blocks key on.
    echo 'set_global_assignment -name VERILOG_MACRO "SYNTHESIS=1"'
    for f in "$d"/*.sv; do
      echo "set_global_assignment -name SYSTEMVERILOG_FILE $(basename "$f")"
    done
  } > "$d/$app.qsf"
  if ! (cd "$d" && "$QBIN/quartus_map" "$app" > map.log 2>&1); then
    echo "FAIL $app: Analysis & Synthesis failed"
    grep -E "^Error" "$d/map.log" | head -4 | sed 's/^/     /'
    rc=1
    continue
  fi
  le=$(grep -E "^Total logic elements" "$d/$app.map.summary" \
       | sed 's/.*: *//; s/,//g')
  rg=$(grep -E "^Total registers" "$d/$app.map.summary" | sed 's/.*: *//; s/,//g')
  [ -n "$le" ] || { echo "FAIL $app: no logic-element count in the summary"; rc=1; continue; }
  [ $first -eq 1 ] || echo ',' >> "$W/new.json"
  first=0
  printf '  "%s": {"logic_elements": %s, "registers": %s}' "$app" "$le" "$rg" >> "$W/new.json"

  if [ -f "$BASE" ]; then
    want=$(python3 -c "
import json,sys
b=json.load(open('$BASE')).get('$app')
print(b['logic_elements'] if b else -1)")
  else
    want=-1
  fi
  if [ "$want" = "-1" ]; then
    echo "ok   $app: synthesizes, $le LE / $rg registers (no baseline yet)"
  else
    python3 - "$le" "$want" "$TOL" <<'PY'
import sys
got, want, tol = int(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3])
sys.exit(0 if abs(got - want) * 100 <= want * tol else 1)
PY
    if [ $? -eq 0 ]; then
      echo "ok   $app: synthesizes, $le LE / $rg registers (baseline $want)"
    else
      echo "FAIL $app: $le LE against a baseline of $want, more than $TOL% apart"
      rc=1
    fi
  fi
done
echo '' >> "$W/new.json"; echo '}' >> "$W/new.json"

if [ $UPDATE -eq 1 ]; then
  python3 -c "
import json
json.dump(json.load(open('$W/new.json')), open('$BASE','w'), indent=2, sort_keys=True)
open('$BASE','a').write('\n')"
  echo "baseline written: $BASE"
  exit 0
fi
exit $rc
