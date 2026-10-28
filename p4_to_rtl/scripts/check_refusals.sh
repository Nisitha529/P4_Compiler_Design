#!/bin/bash
# Programs the compiler MUST refuse, and the message it must refuse them with.
#
# Every entry here is a construct that was once accepted and silently
# miscompiled. A compiler that emits RTL missing behaviour the program asked
# for, and reports success, is worse than one that stops -- so these are tested
# the same way the positive cases are.
#
# Add a case by dropping a .p4 in verification/refusals/ and a line below.
set -u
R="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="${P4C_BIN:-/home/nisitha/p4c/build}:$PATH"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
rc=0

# <file>:<expected exit status>:<substring the message must contain>
CASES=(
  "arprobe.p4:2:switch (t.apply().action_run) is not supported"
)

for case in "${CASES[@]}"; do
  f="${case%%:*}"; rest="${case#*:}"
  want_rc="${rest%%:*}"; want_msg="${rest#*:}"
  src="$R/verification/refusals/$f"
  [ -f "$src" ] || { echo "FAIL $f: no such file"; rc=1; continue; }
  # The compiler takes an app NAME from p4src/apps, so the refusal fixture is
  # copied in for the duration of the check and removed afterwards -- it must
  # not sit there permanently, or the ordinary sweep would try to build it.
  app="${f%.p4}"
  cp "$src" "$R/p4src/apps/$app.p4"
  out=$(cd "$R" && python3 compiler/main.py "$app" --out-dir "$W/$app" 2>&1)
  got_rc=$?
  rm -f "$R/p4src/apps/$app.p4"
  if [ "$got_rc" != "$want_rc" ]; then
    echo "FAIL $f: exited $got_rc, expected $want_rc (a refusal)"
    echo "$out" | tail -3 | sed 's/^/     /'
    rc=1
  elif ! echo "$out" | grep -qF "$want_msg"; then
    echo "FAIL $f: refused, but the message did not mention: $want_msg"
    echo "$out" | tail -3 | sed 's/^/     /'
    rc=1
  else
    echo "ok   $f: refused with exit $got_rc and the expected message"
  fi
done
exit $rc
