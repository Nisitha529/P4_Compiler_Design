#!/bin/bash
# Check the traffic manager's queue depth where it actually means something:
# with a queue DEEPER THAN ONE PACKET, and with a depth limit set.
#
# Why a script rather than two more testbenches in the regression's loop:
# both answers depend on how the app was GENERATED, and the loop runs each app
# in whatever mode it was last built in.
#   * the depth a queue can reach is NSLOT - TM_INFLIGHT. At the default
#     --nslot 4 that is 2, so a regression that never passes --nslot could only
#     ever observe a depth of 2 -- barely above the 1 that was the original gap.
#     Here it is generated at --nslot 8, where the depth reaches 6 and the
#     drain has a shape worth checking.
#   * --tm-qlimit emits tm_tail_drops, which does not exist without the flag,
#     so its testbench cannot live in generated/ at all (the loop would build
#     it against the no-limit design and fail at elaboration). It lives in
#     verification/tm_qlimit/ and is built from here.
#
# Both testbenches are iverilog-only here, for speed; both were also confirmed
# under Vivado xsim by hand, including the hierarchical reads of the DUT's
# NSLOT / TM_INFLIGHT / TM_QLIMIT and tm_tail_drops that they depend on.
#
# Both builds go into a scratch directory (--out-dir), never generated/: the
# committed qdprobe (--nslot 8 --cp-map) is what the regression loop runs, and
# rebuilding it in place used to leave the tree modified after every run.
set -u
R="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="${P4C_BIN:-/home/nisitha/p4c/build}:$PATH"
W=$(mktemp -d); rc=0
trap 'rm -rf "$W"' EXIT

run_tb() { # $1=label  $2=testbench path  $3=generated-RTL directory
  local label="$1" tb="$2" G="$3" files res fails
  files=$(ls "$G"/*.sv | grep -v _pkg | grep -v selftest)
  if ! iverilog -g2012 -o "$W/tb.vvp" "$G"/qdprobe_pkg.sv $files "$tb" 2> "$W/b.log"; then
    echo "FAIL $label: build error"
    grep -vE "sorry|empty port|warning" "$W/b.log" | head -3; rc=1; return
  fi
  timeout 180 vvp "$W/tb.vvp" > "$W/run.log" 2>&1
  res=$(grep -oE "Results: [0-9]+ passed, [0-9]+ failed" "$W/run.log" | tail -1)
  fails=$(echo "$res" | awk '{print $4}')
  if [ "${fails:-1}" = "0" ] && [ -n "$res" ]; then
    echo "ok   $label: $res"
  else
    echo "FAIL $label: ${res:-no result}"
    grep -E "\[FAIL\]|TIMEOUT" "$W/run.log" | head -5 | sed 's/^/     /'; rc=1
  fi
}

# 1. A deep ring: the depth, the drain shape, and that it is per queue.
if ! (cd "$R" && python3 compiler/main.py qdprobe --nslot 8 --cp-map \
        --out-dir "$W/depth") > "$W/gen1.log" 2>&1; then
  echo "FAIL depth: generation failed"; sed 's/^/     /' "$W/gen1.log" | tail -5; rc=1
else
  run_tb "depth  (--nslot 8)" "$R/generated/qdprobe/testbench/tb_qdprobe_top.sv" "$W/depth"
fi

# 2. The same ring with a limit: tail drop at the limit, and what it does not do.
if ! (cd "$R" && python3 compiler/main.py qdprobe --nslot 8 --tm-qlimit 3 \
        --out-dir "$W/qlimit") > "$W/gen2.log" 2>&1; then
  echo "FAIL qlimit: generation failed"; sed 's/^/     /' "$W/gen2.log" | tail -5; rc=1
else
  run_tb "qlimit (--tm-qlimit 3)" "$R/verification/tm_qlimit/tb_qdprobe_limit.sv" "$W/qlimit"
fi
exit $rc
