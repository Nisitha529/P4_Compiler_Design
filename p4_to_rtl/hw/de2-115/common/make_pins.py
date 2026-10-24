#!/usr/bin/env python3
"""Generate the DE2-115 pin constraint files, from two independent sources that
must agree.

Why this is a script and not a hand-written .qsf: a bring-up design is only as
good as its pin assignments, and there are over a hundred of them. Typing them
out is the step where a design that looks right drives the wrong ball on a real
board -- and on a shared bus (the Ethernet PHY's MDIO, the USB controller's
data bus) a wrong direction means two drivers fighting, which is the one class
of mistake that can do damage rather than just not work.

So every pin here is taken from BOTH of these and emitted only if they match:

  1. the official Terasic DE2-115 user manual's pin tables (authoritative)
  2. a DE2-115 project that has actually been FITTED by Quartus and runs
     Ethernet on this board: Alex Forencich's verilog-ethernet DE2-115 example

A disagreement is a hard error. Anything present in only one source is listed
as unconfirmed and left OUT of the emitted files, rather than taken on faith.

    python3 hw/de2-115/common/make_pins.py \
        --manual /path/to/DE2_115_User_manual.pdf \
        --reference /path/to/verilog-ethernet/example/DE2-115/fpga/fpga.qsf

Both paths are LOCAL files on this machine; nothing is downloaded. The outputs
(pins_core.qsf, pins_enet.qsf, pins_otg.qsf) are committed, so the designs
build without re-running this -- but the script is how you check them.
"""
import argparse
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))

# What goes in which file, as regexes over signal names.
GROUPS = {
    'pins_core.qsf': (
        r'^(CLOCK_50|CLOCK2_50|CLOCK3_50|KEY\[\d+\]|SW\[\d+\]|LEDR\[\d+\]'
        r'|LEDG\[\d+\]|HEX[0-7]\[\d+\])$',
        'clocks, push-buttons, slide switches, all 27 LEDs, all 8 7-segment digits'),
    'pins_enet.qsf': (
        r'^(ENETCLK_25|ENET[01]_[A-Z0-9_]+(\[\d+\])?)$',
        'both Marvell 88E1111 Ethernet PHYs (GMII/MII + MDIO + reset)'),
    'pins_otg.qsf': (
        r'^(OTG_[A-Z0-9_]+(\[\d+\])?)$',
        'the Cypress CY7C67200 USB host/device controller bus'),
}


def from_manual(pdf):
    """{signal: (pin, voltage_text)} from the manual's pin tables."""
    txt = subprocess.run(['pdftotext', '-layout', pdf, '-'],
                         capture_output=True, text=True, check=True).stdout
    out = {}
    pat = re.compile(r'^\s*([A-Z][A-Z0-9_]*(?:\[\d+\])?)\s+(PIN_[A-Z]+\d+)\s+(.*)$')
    for line in txt.splitlines():
        m = pat.match(line)
        if m:
            sig, pin, rest = m.group(1), m.group(2), m.group(3).strip()
            volt = '2.5V' if rest.endswith('2.5V') else (
                   '3.3V' if rest.endswith('3.3V') else 'JP')
            # The manual lists some signals more than once (per-PHY tables);
            # a repeat with a DIFFERENT pin is a parse problem, not a fact.
            if sig in out and out[sig][0] != pin:
                raise SystemExit(f'manual lists {sig} twice with different pins: '
                                 f'{out[sig][0]} and {pin}')
            out[sig] = (pin, volt)
    return out


def from_reference(qsf):
    """{signal: (pin, io_standard)} from a fitted DE2-115 project's .qsf."""
    loc, std = {}, {}
    for line in open(qsf):
        m = re.match(r'\s*set_location_assignment\s+(PIN_\w+)\s+-to\s+(\S+)', line)
        if m:
            loc[m.group(2)] = m.group(1)
        m = re.match(r'\s*set_instance_assignment\s+-name\s+IO_STANDARD\s+'
                     r'"([^"]+)"\s+-to\s+(\S+)', line)
        if m:
            std[m.group(2)] = m.group(1)
    return {s: (p, std.get(s)) for s, p in loc.items()}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--manual', required=True)
    ap.add_argument('--reference', required=True)
    ap.add_argument('--out-dir', default=HERE)
    a = ap.parse_args()

    man = from_manual(a.manual)
    ref = from_reference(a.reference)

    conflicts, only_manual, only_ref, agreed = [], [], [], {}
    wanted = re.compile('|'.join(f'({p})' for p, _ in GROUPS.values()))
    for sig in sorted(set(man) | set(ref)):
        if not wanted.match(sig):
            continue
        if sig in man and sig in ref:
            if man[sig][0] != ref[sig][0]:
                conflicts.append((sig, man[sig][0], ref[sig][0]))
            else:
                # Location from both (they agree); I/O standard from the
                # fitted project, which had to satisfy Quartus for real.
                io = ref[sig][1] or ('2.5 V' if man[sig][1] == '2.5V' else '3.3-V LVTTL')
                agreed[sig] = (man[sig][0], io)
        elif sig in man:
            only_manual.append((sig, man[sig][0]))
        else:
            only_ref.append((sig, ref[sig][0]))

    if conflicts:
        print('PIN CONFLICT -- the two sources disagree, nothing emitted:')
        for sig, a_, b_ in conflicts:
            print(f'  {sig}: manual says {a_}, fitted reference says {b_}')
        return 1

    for fname, (pat, note) in GROUPS.items():
        rx = re.compile(pat)
        sigs = [s for s in agreed if rx.match(s)]
        sigs.sort(key=lambda s: (re.sub(r'\[\d+\]', '', s),
                                 int(re.search(r'\[(\d+)\]', s).group(1)) if '[' in s else -1))
        path = os.path.join(a.out_dir, fname)
        with open(path, 'w') as f:
            f.write(f'# {fname} -- DE2-115 pin assignments: {note}\n')
            f.write('#\n')
            f.write('# GENERATED by hw/de2-115/common/make_pins.py. Every pin below appears\n')
            f.write('# in BOTH the Terasic DE2-115 user manual and a DE2-115 project that\n')
            f.write('# Quartus has fitted and that runs Ethernet on this board, with the same\n')
            f.write('# value. Signals the two sources did not agree on are not here at all.\n')
            f.write('#\n')
            f.write('# Include from a project .qsf with:\n')
            f.write(f'#     set_global_assignment -name SOURCE_TCL_SCRIPT_FILE {fname}\n')
            f.write('# ...or paste the contents in. Verify against YOUR board revision\n')
            f.write('# before programming: Terasic has shipped more than one DE2-115 rev.\n\n')
            for s in sigs:
                pin, io = agreed[s]
                f.write(f'set_location_assignment {pin} -to {s}\n')
                f.write(f'set_instance_assignment -name IO_STANDARD "{io}" -to {s}\n')
        print(f'{fname:16s} {len(sigs):4d} pin(s)  -- {note}')

    if only_manual or only_ref:
        print('\nnot emitted (only one source has them, so unconfirmed):')
        for sig, pin in only_manual[:12]:
            print(f'  {sig:22s} {pin:9s} manual only')
        for sig, pin in only_ref[:12]:
            print(f'  {sig:22s} {pin:9s} fitted reference only')
        extra = len(only_manual) + len(only_ref) - 24
        if extra > 0:
            print(f'  ... and {extra} more')
    return 0


if __name__ == '__main__':
    sys.exit(main())
