#!/usr/bin/env python3
"""Check that a --self-test wrapper drives every INPUT of the core it wraps.

Why this exists: the wrapper instantiates <app>_top by name, and SystemVerilog
is perfectly happy with an instantiation that leaves ports out. An omitted
OUTPUT is merely unobserved; an omitted INPUT is undriven -- X in simulation,
tied low by synthesis -- and nothing warns. Two real cases were found that way:

  * FeatureExport's <name>_tready, so the shell's staging FIFO filled and every
    record after it was counted as dropped. On a board whose only master is
    JTAG-to-AXI that made the feature stream, which is the entire product of a
    TCN/IDS-style program, unobservable.
  * ingress_port, for any program that reads standard_metadata.ingress_port, so
    every packet looked like it arrived on port 0.

Both are fixed, but the point of this script is that the NEXT new core input
cannot repeat it quietly: a port added to emit_top.py's top-level that
emit_selftest.py does not know about fails here instead of on hardware.

Parses the generated SystemVerilog textually (no simulator needed) -- enough
for this one structural question, and it runs in milliseconds in regress.sh.
Silent when no app was generated with --self-test.
"""
import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def module_inputs(path, module):
    """The INPUT port names of `module` as declared in `path`."""
    src = open(path).read()
    m = re.search(r'^module\s+' + re.escape(module) + r'\b(.*?)\n\);',
                  src, re.S | re.M)
    if not m:
        return None
    names = []
    for line in m.group(1).splitlines():
        line = line.split('//')[0].strip()
        if not line.startswith('input'):
            continue
        # input logic [W-1:0] name,   /  input logic name,
        mm = re.match(r'input\s+(?:wire|logic|reg)?\s*(?:\[[^\]]*\]\s*)?'
                      r'([A-Za-z_]\w*)\s*,?$', line)
        if mm:
            names.append(mm.group(1))
    return names


def instance_connections(path, module):
    """Port names connected on the first instantiation of `module` in `path`."""
    src = open(path).read()
    m = re.search(re.escape(module) + r'\s+\w+\s*\((.*?)\n\s*\);', src, re.S)
    if not m:
        return None
    body = re.sub(r'//[^\n]*', '', m.group(1))
    return set(re.findall(r'\.\s*([A-Za-z_]\w*)\s*\(', body))


def main():
    wrappers = sorted(glob.glob(os.path.join(ROOT, 'generated', '*', '*_selftest_top.sv')))
    if not wrappers:
        print('no <app>_selftest_top.sv found -- nothing to check')
        return 0
    rc = 0
    for wrapper in wrappers:
        app = os.path.basename(wrapper)[:-len('_selftest_top.sv')]
        core = os.path.join(os.path.dirname(wrapper), f'{app}_top.sv')
        rel = os.path.relpath(wrapper, ROOT)
        if not os.path.exists(core):
            print(f'FAIL {rel}: no {app}_top.sv beside it to check against')
            rc = 1
            continue
        ins = module_inputs(core, f'{app}_top')
        conns = instance_connections(wrapper, f'{app}_top')
        if ins is None:
            print(f'FAIL {rel}: could not parse module {app}_top in the core')
            rc = 1
            continue
        if conns is None:
            print(f'FAIL {rel}: no {app}_top instantiation found in the wrapper')
            rc = 1
            continue
        missing = [n for n in ins if n not in conns]
        if missing:
            print(f'FAIL {rel}: {app}_top input(s) left UNDRIVEN by the wrapper: '
                  + ', '.join(missing))
            rc = 1
        else:
            print(f'ok   {app}: all {len(ins)} input(s) of {app}_top are driven')
    return rc


if __name__ == '__main__':
    sys.exit(main())
