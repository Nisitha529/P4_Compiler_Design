#!/usr/bin/env python3
"""p4v -- verify a generated design against a reference model, over a pcap.

    p4v.py <app> --pcap traffic.pcap [--testcase entries.txt] [--sim iverilog]

What it does, end to end, for ANY program the compiler accepts:

    1. compile the app (with --cp-map, into a scratch directory)
    2. build the reference model from the same IR the emitters used
    3. read the testcase file: table entries, in the same `table_add` shape
       Vitis Networking P4's behavioural model uses
    4. run every packet in the pcap through the model          -> expected
    5. translate the table entries into control-plane word writes USING THE
       CP MAP, generate the file-driven testbench, run the simulator -> actual
    6. compare, and write both sides back out as pcap files

Three outcomes, and the third one is the point:

    PASS          every packet matched
    FAIL          they differ -- first differing packet and byte are reported
    NOT VERIFIED  the model cannot represent some construct in this program.
                  It says which. It does NOT fall back to a guess, because an
                  oracle that approximates and reports PASS is worse than none.

The table-entry file is the user's, the pcap is the user's, and nothing in
either is specific to this project's own applications.
"""
import argparse
import os
import re
import subprocess
import sys
import tempfile

_HERE = os.path.dirname(os.path.abspath(__file__))
_ROOT = os.path.normpath(os.path.join(_HERE, '..', '..'))
sys.path.insert(0, _HERE)
sys.path.insert(0, os.path.join(_ROOT, 'compiler'))

import pcap as pcapmod                                  # noqa: E402
from build_ir import build_ir                           # noqa: E402
from refmodel import Model, Entry                       # noqa: E402
from expr import Unsupported                            # noqa: E402
from emit_vector_tb import emit_vector_tb, PortError    # noqa: E402

import json                                             # noqa: E402


class TestcaseError(Exception):
    pass


def parse_testcase(path):
    """`table_add <table> <action> <k0> <k1> => <p0> <p1>` lines, plus
    `run_traffic <name>` (accepted and ignored: the pcap is given on the
    command line). Keys may be <value>, <value>/<prefix_len> for lpm, or
    <value>&<mask> for ternary; `priority=<n>` sets a ternary priority."""
    entries, traffic = {}, []
    if not path:
        return entries, traffic
    with open(path) as f:
        for lineno, raw in enumerate(f, 1):
            line = raw.split('#')[0].strip()
            if not line:
                continue
            if line.startswith('run_traffic'):
                traffic.append(line.split()[1] if len(line.split()) > 1 else '')
                continue
            if not line.startswith('table_add'):
                raise TestcaseError(f'{path}:{lineno}: unknown directive {line.split()[0]!r} '
                                    f'(expected table_add or run_traffic)')
            body = line[len('table_add'):].strip()
            keypart, _, parampart = body.partition('=>')
            toks = keypart.split()
            if len(toks) < 2:
                raise TestcaseError(f'{path}:{lineno}: need "table_add <table> <action> ..."')
            table, action, keytoks = toks[0], toks[1], toks[2:]
            prio = 0
            keys, masks, plen = [], [], None
            for kt in keytoks:
                if kt.startswith('priority='):
                    prio = int(kt.split('=')[1], 0)
                    continue
                if '/' in kt:
                    v, p = kt.split('/')
                    keys.append(int(v, 0)); plen = int(p, 0); masks.append(None)
                elif '&' in kt:
                    v, mk = kt.split('&')
                    keys.append(int(v, 0)); masks.append(int(mk, 0))
                else:
                    keys.append(int(kt, 0)); masks.append(None)
            params = [int(x, 0) for x in parampart.split()] if parampart.strip() else []
            entries.setdefault(table, []).append(
                dict(action=action, keys=keys, masks=masks, prefix_len=plen,
                     priority=prio, params=params, line=lineno))
    return entries, traffic


def model_entries(raw, cpmap):
    """Testcase rows -> refmodel Entry objects (action params by NAME)."""
    out = {}
    tmap = {t['name']: t for t in cpmap['tables']}
    for table, rows in raw.items():
        if table not in tmap:
            raise TestcaseError(
                f'table {table!r} is not in this program (have: '
                f'{", ".join(sorted(tmap)) or "none"})')
        amap = {a['name']: a for a in tmap[table]['actions']}
        for r in rows:
            if r['action'] not in amap:
                raise TestcaseError(
                    f'table {table!r} has no action {r["action"]!r} '
                    f'(have: {", ".join(sorted(amap))})')
            pdefs = amap[r['action']]['params']
            if len(pdefs) != len(r['params']):
                raise TestcaseError(
                    f'line {r["line"]}: action {r["action"]!r} takes {len(pdefs)} '
                    f'parameter(s), {len(r["params"])} given')
            out.setdefault(table, []).append(Entry(
                action=r['action'], keys=r['keys'],
                params={d['name']: v for d, v in zip(pdefs, r['params'])},
                priority=r['priority'], masks=r['masks'], prefix_len=r['prefix_len']))
    return out


def cp_writes(raw, cpmap):
    """Testcase rows -> [(word_address, data)] for the control plane.

    Uses the cp_map, which is the artifact that already describes every table's
    words, action ids and key widths -- so this knows nothing about any
    particular program's register layout.
    """
    writes = []
    tmap = {t['name']: t for t in cpmap['tables']}
    for table, rows in raw.items():
        t = tmap[table]
        # The cp_map's word numbers are ABSOLUTE word addresses on the one
        # AXI4-Lite bus -- the table's own `base` (a byte address) is already
        # folded into them: port_smac has base 0x0100 and wr_idx 64, and
        # 0x100/4 == 64. Adding the base again sends every write one window too
        # far, where it lands in another table's window and is quietly accepted.
        words = t['words']
        base = 0
        amap = {a['name']: a for a in t['actions']}
        for idx, r in enumerate(rows):
            a = amap[r['action']]
            writes.append((base + words['wr_idx'], idx))
            writes.append((base + words['wr_action'], a['id']))
            for kdef, kval in zip(t['keys'], r['keys']):
                for wi, w in enumerate(kdef['words']):
                    writes.append((base + w, (kval >> (32 * wi)) & 0xFFFFFFFF))
                if kdef['match'] == 'lpm' and r['prefix_len'] is not None:
                    for wi, w in enumerate(kdef.get('pfx_len_words', [])):
                        writes.append((base + w, r['prefix_len']))
                if kdef['match'] == 'ternary':
                    mval = None
                    for m in (r['masks'] or []):
                        if m is not None:
                            mval = m
                            break
                    if mval is None:
                        mval = (1 << kdef['width']) - 1
                    for wi, w in enumerate(kdef.get('mask_words', [])):
                        writes.append((base + w, (mval >> (32 * wi)) & 0xFFFFFFFF))
            for pdef, pval in zip(a['params'], r['params']):
                for wi, w in enumerate(pdef['words']):
                    writes.append((base + w, (pval >> (32 * wi)) & 0xFFFFFFFF))
            writes.append((base + words['commit'], 1))
    return writes


def run_sim(app, gen_dir, tb_path, files, work, plusargs, sim='iverilog', beat_bytes=32):
    """Build and run the generated vector testbench. Returns its stdout."""
    if sim == 'iverilog':
        vvp = os.path.join(work, 'vec.vvp')
        cmd = ['iverilog', '-g2012', f'-Ptb_{app}_vectors.TB_BEAT_BYTES={beat_bytes}',
               '-o', vvp] + files + [tb_path]
        p = subprocess.run(cmd, capture_output=True, text=True)
        if p.returncode != 0:
            real = [l for l in p.stderr.splitlines()
                    if 'sorry' not in l and 'warning' not in l.lower()]
            raise RuntimeError('testbench build failed:\n  ' + '\n  '.join(real[:6]))
        r = subprocess.run(['vvp', vvp] + [f'+{k}={v}' for k, v in plusargs.items()],
                           capture_output=True, text=True, timeout=1800)
        return r.stdout
    if sim == 'xsim':
        env = dict(os.environ)
        viv = env.get('VIVADO_BIN', '/tools/Xilinx/Vivado/2020.2/bin')
        env['PATH'] = viv + os.pathsep + env['PATH']
        top = f'tb_{app}_vectors'
        p = subprocess.run(['xvlog', '-sv'] + files + [tb_path],
                           cwd=work, capture_output=True, text=True, env=env)
        if p.returncode != 0:
            raise RuntimeError('xvlog failed:\n' + p.stdout[-1500:])
        args = ['xelab', '-R', top, '-s', 's', '--timescale', '1ns/1ps',
                '--generic_top', f'TB_BEAT_BYTES={beat_bytes}']
        for k, v in plusargs.items():
            args += ['-testplusarg', f'{k}={v}']
        r = subprocess.run(args, cwd=work, capture_output=True, text=True,
                           timeout=3600, env=env)
        return r.stdout
    raise ValueError(f'unknown simulator {sim!r}')


def compare(expected, actual):
    """(verdict, detail). Reordering is reported as its own outcome: across
    queues the traffic manager is ALLOWED to reorder, so same-packets-wrong-
    order is a different fact from wrong-packets."""
    # Nothing on either side is NOT a pass. Two packets that both vanish
    # agree about nothing, and a run where the model expected no output and
    # the design produced no output tells you only that the stimulus never
    # reached the part under test -- which is exactly how a framework quietly
    # reports green while verifying nothing.
    if not expected and not actual:
        return 'VACUOUS', ('no packets on either side: the model expected none and '
                           'none came out, so this run proves nothing. Program table '
                           'entries, or send traffic the program forwards.')
    if expected == actual:
        return 'PASS', f'{len(actual)} packet(s) matched'
    if len(expected) != len(actual):
        return 'FAIL', (f'{len(expected)} packet(s) expected, {len(actual)} came out')
    if sorted(expected) == sorted(actual):
        return 'REORDERED', ('the same packets came out in a different order -- '
                             'legal across queues, a bug within one')
    for i, (e, a) in enumerate(zip(expected, actual)):
        if e != a:
            if len(e) != len(a):
                return 'FAIL', (f'packet {i}: expected {len(e)} bytes, got {len(a)}')
            for b, (eb, ab) in enumerate(zip(e, a)):
                if eb != ab:
                    return 'FAIL', (f'packet {i} byte {b}: expected {eb:02x}, got {ab:02x}\n'
                                    f'         expected {e.hex()}\n'
                                    f'         actual   {a.hex()}')
    return 'FAIL', 'differ'


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('app')
    ap.add_argument('--pcap', required=True, help='input traffic (libpcap, Ethernet)')
    ap.add_argument('--testcase', help='table_add lines (VNP4-style testcase file)')
    ap.add_argument('--sim', default='iverilog', choices=['iverilog', 'xsim'])
    ap.add_argument('--axi-data-width', type=int, default=256)
    ap.add_argument('--gen-flags', default='', help='extra flags for the compiler run')
    ap.add_argument('--in-port', type=int, default=0, help='ingress_port for every packet')
    ap.add_argument('--keep', metavar='DIR', help='keep artifacts (pcaps, vectors) here')
    ap.add_argument('--quiet', action='store_true')
    a = ap.parse_args(argv)

    work = a.keep or tempfile.mkdtemp(prefix='p4v_')
    os.makedirs(work, exist_ok=True)
    gen = os.path.join(work, 'gen')

    def say(*x):
        if not a.quiet:
            print(*x)

    # 1. the design
    cmd = [sys.executable, os.path.join(_ROOT, 'compiler', 'main.py'), a.app,
           '--cp-map', '--axi-data-width', str(a.axi_data_width),
           '--out-dir', gen] + (a.gen_flags.split() if a.gen_flags else [])
    p = subprocess.run(cmd, capture_output=True, text=True, cwd=_ROOT)
    if p.returncode != 0:
        print(f'{a.app}: compiler failed\n' + p.stdout[-1200:] + p.stderr[-800:])
        return 2
    with open(os.path.join(gen, f'{a.app}_cp_map.json')) as f:
        cpmap = json.load(f)

    # 2. the oracle
    try:
        ir = build_ir(a.app)
        model = Model(ir)
    except Unsupported as u:
        print(f'{a.app}: NOT VERIFIED -- {u}')
        return 3

    # 3. stimulus and entries
    raw, _ = parse_testcase(a.testcase)
    try:
        ments = model_entries(raw, cpmap)
        writes = cp_writes(raw, cpmap)
    except TestcaseError as e:
        print(f'{a.app}: testcase error -- {e}')
        return 2
    packets = [d for _, _, d in pcapmod.read_pcap(a.pcap)]
    say(f'{a.app}: {len(packets)} packet(s) from {os.path.basename(a.pcap)}, '
        f'{sum(len(v) for v in raw.values())} table entry/entries')

    # 4. the model's answer
    expected, records = [], []
    try:
        for pkt in packets:
            r = model.run(pkt, ments, ingress_port=a.in_port)
            if r.out_packet is not None:
                expected.append(r.out_packet)
            records += r.records
    except Unsupported as u:
        print(f'{a.app}: NOT VERIFIED -- {u}')
        return 3

    # 5. the design's answer
    vec_in = os.path.join(work, 'in.vec')
    vec_out = os.path.join(work, 'out.vec')
    tbl = os.path.join(work, 'entries.cp')
    pcapmod.write_vector(vec_in, packets)
    with open(tbl, 'w') as f:
        for addr, data in writes:
            f.write(f'{addr} {data:08x}\n')
    try:
        tb = emit_vector_tb(a.app, gen, output_path=os.path.join(work, f'tb_{a.app}_vectors.sv'))
    except PortError as e:
        print(f'{a.app}: NOT VERIFIED -- {e}')
        return 3
    files = [os.path.join(gen, f'{a.app}_pkg.sv')] + sorted(
        p for p in (os.path.join(gen, x) for x in os.listdir(gen))
        if p.endswith('.sv') and '_pkg' not in p and 'selftest' not in p)
    plus = {'vec_in': vec_in, 'vec_out': vec_out, 'tbl': tbl,
            'rec_out': os.path.join(work, 'records.txt'),
            'meta_out': os.path.join(work, 'meta.txt'),
            'in_port': a.in_port}
    try:
        out = run_sim(a.app, gen, tb, files, work, plus, a.sim, a.axi_data_width // 8)
    except RuntimeError as e:
        print(f'{a.app}: NOT VERIFIED -- {e}')
        return 3
    for line in out.splitlines():
        if 'VECTB' in line:
            say('  ' + line.strip())
    actual = pcapmod.read_vector(vec_out)

    # 6. the verdict, and both sides as pcaps for a human to open
    pcapmod.write_pcap(os.path.join(work, 'expected.pcap'), expected)
    pcapmod.write_pcap(os.path.join(work, 'actual.pcap'), actual)
    verdict, detail = compare(expected, actual)
    print(f'{a.app}: {verdict} -- {detail}')
    if a.keep or verdict not in ('PASS',):
        print(f'  artifacts: {work}  (expected.pcap, actual.pcap, in.vec, entries.cp)')
    return 0 if verdict == 'PASS' else 1


if __name__ == '__main__':
    sys.exit(main())
