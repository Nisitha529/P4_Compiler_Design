#!/bin/bash
# Build and run every generated testbench, under one or both simulators.
#
#   scripts/regress.sh                  # iverilog only (the default, fast)
#   scripts/regress.sh --sim all        # iverilog + Vivado xsim
#   scripts/regress.sh --sim xsim fiveTuple lenprobe
#
# Why this exists rather than "compile everything in the directory": the file
# set per testbench is NOT uniform, and getting it wrong looks exactly like a
# regression. Three rules, each learned from a false alarm:
#   * files whose basename carries a control prefix (MyIngress.foo.sv) are
#     STALE output from an older generator -- they declare `module MyIngress.foo`,
#     which is not legal SystemVerilog, so including them fails the whole
#     directory at line 1. The current generator writes foo.sv alongside them.
#   * a *_selftest_top testbench needs the selftest module, which every other
#     testbench must NOT see (it has its own top).
#   * the AVMM selftest testbench additionally needs rtl/common's bridge.
#
# Exit status is non-zero if any testbench fails, times out, or will not build.
set -u
R="$(cd "$(dirname "$0")/.." && pwd)"
SIM=iverilog
case "${1:-}" in --sim) SIM="$2"; shift 2;; esac
VIV="${VIVADO_BIN:-/tools/Xilinx/Vivado/2020.2/bin}"
[ -x "$VIV/xvlog" ] && export PATH="$VIV:$PATH"
have_xsim=0; command -v xvlog >/dev/null 2>&1 && have_xsim=1
if [ "$SIM" != iverilog ] && [ $have_xsim -eq 0 ]; then
  echo "xsim requested but xvlog not found (set VIVADO_BIN); continuing with iverilog only"
  SIM=iverilog
fi
O=$(mktemp -d); tot_p=0; tot_f=0; bad=""
apps=("$@"); [ ${#apps[@]} -eq 0 ] && apps=($(ls "$R/generated"))

fileset() { # $1=app dir  $2=testbench basename  -> prints the .sv list
  local d="$1" tb="$2" f
  ls "$d"/*_pkg.sv 2>/dev/null
  for f in "$d"/*.sv; do
    local b; b=$(basename "$f")
    case "$b" in
      *_pkg.sv)            continue ;;   # already emitted above
      *.*.sv)              continue ;;   # stale control-prefixed leftover
      *_selftest_top.sv)   case "$tb" in *selftest*) ;; *) continue ;; esac ;;
    esac
    echo "$f"
  done
  case "$tb" in *avmm*) echo "$R/rtl/common/avmm_axil_lite_bridge.sv" ;; esac
}

run_one() { # $1=sim $2=app $3=tb-path -> echoes "pass fail status"
  local sim="$1" app="$2" tb="$3" n d rc line pp ff
  n=$(basename "$tb" .sv); d="$O/$sim.$app.$n"; mkdir -p "$d"
  # The top module is read from the file, NOT assumed from the filename:
  # tb_firewall_regram.sv declares `module tb_firewall`, so xelab -s by
  # filename fails with "Cannot find design unit". iverilog does not care,
  # which is why the mismatch went unnoticed.
  local top; top=$(grep -oE '^[[:space:]]*module[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' "$tb" \
                   | head -1 | awk '{print $2}')
  [ -z "$top" ] && top="$n"
  local files; files=$(fileset "$R/generated/$app" "$n")
  if [ "$sim" = iverilog ]; then
    if ! iverilog -g2012 -o "$d/a.vvp" $files "$tb" > "$d/build.log" 2>&1; then
      echo "0 0 BUILD-FAIL"; return; fi
    timeout 300 vvp "$d/a.vvp" > "$d/run.log" 2>&1; rc=$?
  else
    ( cd "$d" && xvlog -sv $files "$tb" > build.log 2>&1 ) || { echo "0 0 BUILD-FAIL"; return; }
    ( cd "$d" && timeout 600 xelab -R "$top" -s s --timescale 1ns/1ps > run.log 2>&1 ); rc=$?
  fi
  line=$(grep -oE "Results: [0-9]+ passed, [0-9]+ failed" "$d/run.log" 2>/dev/null | tail -1)
  if [ -z "$line" ]; then
    pp=$(grep -c "\[PASS\]" "$d/run.log" 2>/dev/null || echo 0)
    ff=$(grep -c "\[FAIL\]" "$d/run.log" 2>/dev/null || echo 0)
  else
    pp=$(echo "$line" | awk '{print $2}'); ff=$(echo "$line" | awk '{print $4}')
  fi
  local st=ok
  [ "$rc" = 124 ] && st=TIMEOUT
  [ "$ff" != 0 ] && st=FAIL
  [ "$pp" = 0 ] && [ "$ff" = 0 ] && st=NO-RESULT
  echo "$pp $ff $st"
}

sims=(iverilog); [ "$SIM" = xsim ] && sims=(xsim); [ "$SIM" = all ] && sims=(iverilog xsim)
printf "%-22s %-34s" APP TESTBENCH; for s in "${sims[@]}"; do printf " %-18s" "$s"; done; echo
for app in "${apps[@]}"; do
  [ -d "$R/generated/$app/testbench" ] || continue
  for tb in "$R/generated/$app"/testbench/*.sv; do
    [ -e "$tb" ] || continue
    printf "%-22s %-34s" "$app" "$(basename "$tb" .sv)"
    for s in "${sims[@]}"; do
      read -r pp ff st <<< "$(run_one "$s" "$app" "$tb")"
      printf " %-18s" "$pp/$ff $st"
      if [ "$s" = "${sims[0]}" ]; then tot_p=$((tot_p+pp)); tot_f=$((tot_f+ff)); fi
      [ "$st" != ok ] && bad="$bad $s:$app/$(basename "$tb" .sv)($st)"
    done
    echo
  done
done
echo "-----"
echo "TOTAL (${sims[0]}): $tot_p passed, $tot_f failed"
if [ -n "$bad" ]; then echo "PROBLEMS:$bad"; echo "logs: $O"; exit 1; fi
echo "logs: $O"
