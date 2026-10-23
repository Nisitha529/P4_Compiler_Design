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
# The Register RAW distance, in BOTH register modes. The loop above runs each
# app once, in whatever mode it was last generated in, so --register-ram was
# never covered -- and that is exactly where the reported number was wrong.
# Both checks run through `bash` and are tested with -f, not -x: git records
# these scripts as 100644, so on a fresh clone a -x test skipped them silently.
if [ -f "$R/scripts/check_raw_distance.sh" ]; then
  if ! bash "$R/scripts/check_raw_distance.sh" > "$O/raw_distance.log" 2>&1; then
    echo "-----"; echo "RAW-DISTANCE MISMATCH:"; sed 's/^/  /' "$O/raw_distance.log"
    bad="$bad raw_distance"
  else
    echo "-----"; sed 's/^/raw_distance: /' "$O/raw_distance.log"
  fi
fi

# The traffic manager's queue depth, which only means something when a queue
# is deeper than one packet -- and that depends on how the app was GENERATED
# (--nslot), not on which testbench runs. Same reason as above: the loop runs
# each app in one mode. Also covers --tm-qlimit, whose testbench cannot live in
# generated/ because tm_tail_drops does not exist without the flag.
if [ -f "$R/scripts/check_tm_qdepth.sh" ]; then
  if ! bash "$R/scripts/check_tm_qdepth.sh" > "$O/tm_qdepth.log" 2>&1; then
    echo "-----"; echo "TRAFFIC-MANAGER QUEUE DEPTH:"; sed 's/^/  /' "$O/tm_qdepth.log"
    bad="$bad tm_qdepth"
  else
    echo "-----"; sed 's/^/tm_qdepth: /' "$O/tm_qdepth.log"
  fi
fi

# The ORACLE test: every committed pcap through both the design and a
# reference model built from the same IR, compared byte for byte. The rest of
# this suite checks the RTL against expectations a human wrote down; this
# checks it against an executable reading of the P4, over real traffic.
if [ -x "$R/scripts/check_vectors.sh" ]; then
  if ! "$R/scripts/check_vectors.sh" > "$O/vectors.log" 2>&1; then
    echo "-----"; echo "PCAP / REFERENCE-MODEL COMPARISON:"; sed 's/^/  /' "$O/vectors.log"
    bad="$bad vectors"
  else
    echo "-----"
    echo "vectors: $(grep -c '^ok ' "$O/vectors.log") app(s) agree with the reference model over their pcap"
  fi
fi

# Every --self-test wrapper must DRIVE every input of the core it wraps. An
# omitted port in an instantiation is legal SystemVerilog and silent, and two
# real inputs were found undriven that way (FeatureExport's tready, and
# ingress_port) -- both invisible in simulation until something read X.
if [ -f "$R/scripts/check_selftest_ports.py" ]; then
  if ! python3 "$R/scripts/check_selftest_ports.py" > "$O/selftest_ports.log" 2>&1; then
    echo "-----"; echo "SELF-TEST WRAPPER PORTS:"; sed 's/^/  /' "$O/selftest_ports.log"
    bad="$bad selftest_ports"
  elif ! grep -q "nothing to check" "$O/selftest_ports.log"; then
    echo "-----"
    echo "selftest_ports: $(grep -c '^ok ' "$O/selftest_ports.log") wrapper(s) drive every core input"
  fi
fi

# The 512-bit datapath. Same reason as the two above: --axi-data-width is a
# GENERATOR flag, every committed build is 256-bit, and the per-app loop can
# only run what was generated. This is the width boards/vcu118.json exists for.
if [ -x "$R/scripts/check_axi_width.sh" ]; then
  if ! "$R/scripts/check_axi_width.sh" > "$O/axi_width.log" 2>&1; then
    echo "-----"; echo "512-BIT DATAPATH:"; sed 's/^/  /' "$O/axi_width.log"
    bad="$bad axi_width"
  else
    echo "-----"
    echo "axi_width: $(grep -c '^ok ' "$O/axi_width.log") testbench(es) pass at --axi-data-width 512"
  fi
fi

# Any <app>_cp_map.json in the tree is checked against its decoder. The map's
# whole value is that host software can trust it, so a drift between the two has
# to fail here rather than on hardware. Silent when no map has been generated.
if ! python3 "$R/scripts/check_cp_map.py" > "$O/cp_map.log" 2>&1; then
  echo "-----"; echo "CONTROL-PLANE MAP MISMATCH:"; sed 's/^/  /' "$O/cp_map.log"
  bad="$bad cp_map"
elif ! grep -q "no <app>_cp_map.json found" "$O/cp_map.log"; then
  echo "-----"; grep -c '^ok ' "$O/cp_map.log" | xargs -I{} echo "cp_map: {} map(s) match their decoder"
fi

echo "-----"
echo "TOTAL (${sims[0]}): $tot_p passed, $tot_f failed"
if [ -n "$bad" ]; then echo "PROBLEMS:$bad"; echo "logs: $O"; exit 1; fi
echo "logs: $O"
