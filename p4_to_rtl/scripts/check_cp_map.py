#!/usr/bin/env python3
"""
Cross-check every <app>_cp_map.json against the decoder in <app>_top.sv.

The map's only value is that host software can trust it. So it is not enough to
generate it from the same data as the decoder -- that has to be CHECKED, or the
next refactor silently decouples them and nothing notices until a register write
lands in the wrong place on real hardware.

Reads the `N'dM: ... // <window> <word>` case labels straight out of the
generated SystemVerilog and asserts the JSON agrees on every one, in both
directions. Exits non-zero on any mismatch.

    scripts/check_cp_map.py [app ...]
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GEN = os.path.join(ROOT, 'generated')

# The generator tags every decoder case arm with a canonical marker:
#   14'd66: r_rdata <= tcn_feed_pushed; // tcn_feed pushed [cpmap:tcn_feed.pushed]
# Parsing that rather than the human comment is deliberate -- the prose uses
# several conventions (a bare word name, "<tbl> commit", "<tbl> query" for a
# word the map calls query_commit), and a checker that guesses between them
# reports differences that are not real.
LABEL = re.compile(r"\d+'d(\d+)\s*:.*?\[cpmap:([^.\]]+)\.([^\]]+)\]")


def words_from_rtl(top_path):
    """{(window, word): addr} as the SystemVerilog decoder actually numbers it."""
    found = {}
    with open(top_path) as f:
        for line in f:
            m = LABEL.search(line.rstrip())
            if m:
                addr, window, word = int(m.group(1)), m.group(2), m.group(3)
                found[(window, word)] = addr
    return found


def words_from_map(doc):
    out = {}
    for section in ('tables', 'counters', 'meters', 'digests',
                    'feature_exports', 'mcast'):
        for entry in doc.get(section, []) or []:
            for word, addr in (entry.get('words') or {}).items():
                out[(entry['name'], word)] = addr
    return out


def check(app):
    top = os.path.join(GEN, app, f'{app}_top.sv')
    mapf = os.path.join(GEN, app, f'{app}_cp_map.json')
    if not (os.path.isfile(top) and os.path.isfile(mapf)):
        return None
    rtl = words_from_rtl(top)
    doc = json.load(open(mapf))
    mp = words_from_map(doc)

    problems = []
    for key, addr in sorted(mp.items()):
        if key not in rtl:
            problems.append(f"map has {key[0]}.{key[1]} @ word {addr}, "
                            f"the decoder has no such case label")
        elif rtl[key] != addr:
            problems.append(f"{key[0]}.{key[1]}: map says word {addr}, "
                            f"decoder says {rtl[key]}")
    for key, addr in sorted(rtl.items()):
        # The decoder also carries labels the map does not model as words
        # (per-field key/param spellings differ); only flag a window the map
        # claims to describe at all.
        if key not in mp and any(k[0] == key[0] for k in mp):
            problems.append(f"decoder has {key[0]}.{key[1]} @ word {addr}, "
                            f"missing from the map")
    return problems


def main():
    apps = sys.argv[1:] or sorted(os.listdir(GEN))
    checked = failed = 0
    for app in apps:
        problems = check(app)
        if problems is None:
            continue
        checked += 1
        if problems:
            failed += 1
            print(f"FAIL {app}")
            for p in problems:
                print(f"       {p}")
        else:
            print(f"ok   {app}")
    if not checked:
        print("no <app>_cp_map.json found -- generate one with --cp-map")
        return 0
    print(f"-----\n{checked} map(s) checked, {failed} with mismatches")
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
