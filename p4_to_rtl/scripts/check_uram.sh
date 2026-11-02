#!/bin/bash
# The board-selected RAM-style pragma on Register storage.
#
# boards/*.json may name two memory primitives: ram_style_pragma for ordinary
# block RAM and uram_style_pragma for a larger one. vcu118.json carried the
# second for weeks with a note in its own `notes` field saying no emitter read
# it -- so on VU9P a large Register array silently went to block RAM, which is
# the difference between a design fitting and not.
#
# Three things are checked, because the pragma being present is only one of
# them and the other two are how it goes wrong:
#   1. an array at or above URAM_MIN_BITS gets the board's uram pragma
#   2. one below it gets the ordinary block-RAM pragma, not a wasted URAM
#   3. with the DEFAULT asynchronous register read, NEITHER is emitted -- the
#      array is not a RAM at that point (it is read combinationally at an
#      arbitrary address), and a style pragma on it drives the tool into the
#      fallback mux network, which is the trap pkt_buf_hdr documents
set -u
R="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="${P4C_BIN:-/home/nisitha/p4c/build}:$PATH"
W=$(mktemp -d); trap 'rm -rf "$W"; rm -f "$R/p4src/apps/uramprobe.p4"' EXIT
rc=0

# The compiler takes an app NAME from p4src/apps, so the fixture is copied in
# for the duration of the check -- it must not sit there permanently or the
# ordinary sweep would try to build it.
cp "$R/verification/uram/uramprobe.p4" "$R/p4src/apps/uramprobe.p4"

pragma_for() {   # <generated dir> <register name> -> the attribute line above it
  grep -B4 "  logic \[31:0\] $2_mem \[0:" "$1/processing_generated.sv" \
    | grep -oE '\(\* ram_style = "[a-z]+" \*\)' | tail -1
}

run() {          # <label> <out dir> <extra flags...>
  local label="$1" out="$2"; shift 2
  (cd "$R" && python3 compiler/main.py uramprobe --out-dir "$out" "$@" \
      >/dev/null 2>&1) || { echo "FAIL $label: the compiler failed"; rc=1; return 1; }
}

# 1 + 2: vcu118 with a synchronous read
if run "vcu118 --register-ram" "$W/a" --board vcu118 --register-ram; then
  big=$(pragma_for "$W/a" big)
  small=$(pragma_for "$W/a" small)
  if [ "$big" = '(* ram_style = "ultra" *)' ]; then
    echo "ok   big (512Kb) -> $big"
  else
    echo "FAIL big (512Kb) -> ${big:-no pragma}, expected (* ram_style = \"ultra\" *)"; rc=1
  fi
  if [ "$small" = '(* ram_style = "block" *)' ]; then
    echo "ok   small (32Kb) -> $small"
  else
    echo "FAIL small (32Kb) -> ${small:-no pragma}, expected (* ram_style = \"block\" *)"; rc=1
  fi
fi

# 3: the default asynchronous read is not a RAM, so no pragma at all
if run "vcu118 async" "$W/b" --board vcu118; then
  any=$(pragma_for "$W/b" big)
  if [ -z "$any" ]; then
    echo "ok   async read -> no RAM-style pragma, as intended"
  else
    echo "FAIL async read -> $any, but an async-read array is not a RAM"; rc=1
  fi
fi

# A board with no uram_style_pragma must fall back, not crash or emit Xilinx
# syntax into a Quartus file.
if run "de2-115 --register-ram" "$W/c" --board de2-115 --register-ram; then
  q=$(grep -B4 '  logic \[31:0\] big_mem \[0:' "$W/c/processing_generated.sv" \
      | grep -oE 'ramstyle = "[A-Za-z0-9]+"' | tail -1)
  if [ -n "$q" ]; then
    echo "ok   de2-115 (no uram pragma) -> falls back to $q"
  else
    echo "FAIL de2-115: expected the Quartus ramstyle attribute, got none"; rc=1
  fi
fi
exit $rc
