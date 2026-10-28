#!/usr/bin/env python3
"""Record the generator flags each committed build was made with, and check
that regenerating with them reproduces it.

    python3 scripts/make_build_flags.py            # check (default)
    python3 scripts/make_build_flags.py --write    # (re)write build.flags
    python3 scripts/make_build_flags.py --regen    # regenerate in place

Why this exists: the flags lived only as artifacts you had to infer from the
output directory -- a cp_map here, a selftest top there, an --nslot visible
only as a localparam in the generated RTL. Three times a regeneration has
silently lost one (a --clock-hz, an unintended --board, nearly an --nslot),
and each time the loss was caught by chance in a diff rather than by anything
checking. With the flags recorded, "regenerate this app" is a defined
operation and `--check` makes it a test.

Flags are INFERRED from the artifacts the first time (the rules below), then
committed as generated/<app>/build.flags and read from there afterwards.
"""
import argparse
import json
import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GEN = os.path.join(ROOT, 'generated')
APPS = os.path.join(ROOT, 'p4src', 'apps')


def infer(app, d):
    """Flags implied by what is sitting in the app's output directory."""
    flags = []
    cpmap = os.path.join(d, f'{app}_cp_map.json')
    if os.path.exists(cpmap):
        flags.append('--cp-map')
        try:
            with open(cpmap) as f:
                m = json.load(f)
            if m.get('clock_hz'):
                flags += ['--clock-hz', str(m['clock_hz'])]
            # A width other than the default is visible in the map.
            if m.get('axi_data_width') and int(m['axi_data_width']) != 256:
                flags += ['--axi-data-width', str(m['axi_data_width'])]
        except Exception:
            pass
    if os.path.exists(os.path.join(d, f'{app}_selftest_top.sv')):
        flags.append('--self-test')
    # A board shows up as its constraint files, and which vendor they are
    # tells you which board family.
    if any(os.path.exists(os.path.join(d, f'{app}{ext}')) for ext in ('.qsf', '.sdc')):
        flags += ['--board', 'de2-115']
    elif os.path.exists(os.path.join(d, f'{app}.xdc')):
        flags += ['--board', 'zybo']
    top = os.path.join(d, f'{app}_top.sv')
    if os.path.exists(top):
        src = open(top).read()
        m = re.search(r'localparam int NSLOT\s*=\s*(\d+)', src)
        if m and int(m.group(1)) != 4:
            flags += ['--nslot', m.group(1)]
        m = re.search(r'localparam int TM_QLIMIT\s*=\s*(\d+)', src)
        if m:
            flags += ['--tm-qlimit', m.group(1)]
        if 'ramstyle' in src and 'altsyncram' not in src:
            pass           # board-driven, already covered above
        # A synchronous-read register memory is what --register-ram produces.
        if re.search(r'// --register-ram', src):
            flags.append('--register-ram')
    return flags


def read_flags(app, d):
    p = os.path.join(d, 'build.flags')
    if not os.path.exists(p):
        return None
    out = []
    for line in open(p):
        line = line.split('#')[0].strip()
        if line:
            out += line.split()
    return out


def regen(app, flags, out_dir):
    cmd = [sys.executable, os.path.join(ROOT, 'compiler', 'main.py'), app]
    cmd += flags + ['--out-dir', out_dir]
    return subprocess.run(cmd, capture_output=True, text=True, cwd=ROOT)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--write', action='store_true', help='write build.flags from the inferred flags')
    ap.add_argument('--regen', action='store_true', help='regenerate each build in place')
    ap.add_argument('--check', action='store_true', help='regenerate to a scratch dir and diff (default)')
    ap.add_argument('apps', nargs='*')
    a = ap.parse_args()
    if not (a.write or a.regen):
        a.check = True

    apps = a.apps or sorted(
        x for x in os.listdir(GEN)
        if os.path.isdir(os.path.join(GEN, x))
        and os.path.exists(os.path.join(APPS, f'{x}.p4'))
        and os.path.exists(os.path.join(GEN, x, f'{x}_top.sv')))

    rc = 0
    for app in apps:
        d = os.path.join(GEN, app)
        flags = read_flags(app, d) or infer(app, d)
        shown = ' '.join(flags) if flags else '(none)'
        if a.write:
            with open(os.path.join(d, 'build.flags'), 'w') as f:
                f.write('# Generator flags this committed build was made with.\n')
                f.write(f'# Regenerate:  python3 compiler/main.py {app} '
                        f'{" ".join(flags)}\n')
                f.write('# Checked by scripts/make_build_flags.py --check.\n')
                f.write(' '.join(flags) + '\n')
            print(f'{app:22s} wrote build.flags: {shown}')
            continue
        if a.regen:
            p = regen(app, flags, d)
            print(f'{app:22s} {"regenerated" if p.returncode == 0 else "FAILED"}: {shown}')
            if p.returncode != 0:
                print(p.stdout[-400:]); rc = 1
            continue
        with tempfile.TemporaryDirectory() as w:
            p = regen(app, flags, w)
            if p.returncode != 0:
                print(f'{app:22s} REGEN FAILED with {shown}')
                rc = 1
                continue
            diff = []
            for f in sorted(os.listdir(w)):
                if not f.endswith(('.sv', '.json')):
                    continue
                b = os.path.join(d, f)
                if not os.path.exists(b):
                    diff.append(f'{f} (missing from the committed build)')
                elif open(os.path.join(w, f)).read() != open(b).read():
                    # the cp_map embeds the git revision, which moves on every
                    # commit and says nothing about the RTL
                    if f.endswith('_cp_map.json'):
                        x = json.load(open(os.path.join(w, f)))
                        y = json.load(open(b))
                        x.pop('compiler_git', None); y.pop('compiler_git', None)
                        if x == y:
                            continue
                    diff.append(f)
            if diff:
                print(f'{app:22s} DIFFERS from committed ({shown}): '
                      + ', '.join(diff[:4]) + ('...' if len(diff) > 4 else ''))
                rc = 1
            else:
                print(f'{app:22s} reproduces: {shown}')
    return rc


if __name__ == '__main__':
    sys.exit(main())
