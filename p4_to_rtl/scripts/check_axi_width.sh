#!/bin/bash
# Run every top-level testbench against a 512-BIT datapath.
#
# Why this exists: --axi-data-width is the one generator flag that changes the
# whole shell, and nothing ever ran at anything but the 256-bit default. Every
# committed build is 256-bit, so the regression's per-app loop can only ever
# cover that. boards/vcu118.json exists for a target where 512-bit at 100G is
# the point, and the first time the width was actually exercised it found:
#
#   * a REAL defect: TX asked the payload buffer for a beat when the packet
#     fitted entirely inside the header region (no payload at all) and waited
#     for it forever, wedging the slot ring and stalling the link behind one
#     short packet. HDR_MAX_BYTES is beat-rounded, so a 64-byte frame triggers
#     it at 512 and a <=32-byte frame triggers it at 256 -- it was a
#     short-packet bug all along, which is why no 512-bit-only fix was right.
#     Pinned by tb_lenprobe_top T6/T7/T8, which derive the frame size from the
#     DUT's own HDR_MAX_BYTES.
#   * testbenches that had the beat width baked in: literal beat counts
#     ("a 64 B frame is 2 beats"), a send loop hardcoded to two beats over a
#     64-entry array, an 8192-byte truncation point that was really
#     MAX_PKT_BEATS * BEAT_BYTES, and two collectors that sampled m_axis just
#     after the clock edge, where the beat sampled depends on when tready rose.
#     Each one failed at 512 while saying nothing about the design.
#
# Testbenches take the width as `parameter int TB_BEAT_BYTES`, overridden here
# with -P. A localparam cannot be overridden, which is why they were converted:
# `-P` on one silently does nothing, so the sweep LOOKED green while still
# driving 32-byte beats into a 512-bit port.
#
# iverilog only, for speed. The two testbenches this work actually changed the
# behaviour of -- lenprobe (the TX fix) and qdprobe (the depth ceiling) -- were
# also run at 512 under Vivado xsim by hand (xelab --generic_top
# TB_BEAT_BYTES=64), and the whole set passes under xsim at 256 via
# scripts/regress.sh --sim all. The rest of this set has not been run under
# xsim AT 512.
# Generated builds go to a scratch directory (--out-dir), never generated/.
set -u
R="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="${P4C_BIN:-/home/nisitha/p4c/build}:$PATH"
W=$(mktemp -d); rc=0
trap 'rm -rf "$W"' EXIT

# app:extra-generator-flags  (the flags each committed build uses, where they
# matter to the datapath; --self-test/--board only add files the TB never reads)
APPS=(
  "egprobe:"  "ioprobe:"  "lmprobe:"  "regprobe:"  "ueprobe:"  "smprobe:"
  "mdprobe:"  "mcprobe:"  "ecn_p4rtl:"  "lenprobe:"  "feprobe:"  "egfeprobe:"
  "qdprobe:--nslot 8"  "load_balance_p4rtl:"  "load_balance_xsa:"  "fiveTuple:"
)

for entry in "${APPS[@]}"; do
  app="${entry%%:*}"; flags="${entry#*:}"
  tb="$R/generated/$app/testbench/tb_${app}_top.sv"
  [ -f "$tb" ] || { echo "SKIP $app: no tb_${app}_top.sv"; continue; }
  top=$(grep -oE '^[[:space:]]*module[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' "$tb" \
        | head -1 | awk '{print $2}')
  if ! grep -q "parameter  *int TB_BEAT_BYTES" "$tb"; then
    echo "FAIL $app: TB_BEAT_BYTES is not a parameter, so -P cannot set it"
    rc=1; continue
  fi
  G="$W/$app"
  if ! (cd "$R" && python3 compiler/main.py "$app" $flags \
        --axi-data-width 512 --out-dir "$G") > "$W/gen.log" 2>&1; then
    echo "FAIL $app: generation failed"; tail -3 "$W/gen.log" | sed 's/^/     /'
    rc=1; continue
  fi
  files=$(ls "$G"/*.sv | grep -v _pkg | grep -v selftest)
  if ! iverilog -g2012 -P"$top".TB_BEAT_BYTES=64 -o "$W/tb.vvp" \
        "$G"/${app}_pkg.sv $files "$tb" 2> "$W/b.log"; then
    echo "FAIL $app: build error"
    grep -vE "sorry|empty port|warning" "$W/b.log" | head -3 | sed 's/^/     /'
    rc=1; continue
  fi
  timeout 300 vvp "$W/tb.vvp" > "$W/run.log" 2>&1
  res=$(grep -oE "Results: [0-9]+ passed, [0-9]+ failed" "$W/run.log" | tail -1)
  fails=$(echo "$res" | awk '{print $4}')
  if [ "${fails:-1}" = "0" ] && [ -n "$res" ]; then
    echo "ok   $app @512: $res"
  else
    echo "FAIL $app @512: ${res:-no result}"
    grep -E "\[FAIL\]|TIMEOUT" "$W/run.log" | head -4 | sed 's/^/     /'
    rc=1
  fi
done
exit $rc
