#!/usr/bin/env python3
"""Line coverage of the GENERATED RTL, measured by replaying a pcap.

    python3 verification/framework/coverage.py <app> --pcap t.pcap --testcase e.txt

Why: before this, nothing in the project measured what the testbenches touch.
985 assertions and 58 packets of traffic passed, and the fraction of the
generated shell they actually executed was unknown -- so "green" meant "nothing
we thought to check is broken", with no way to see what nobody thought to check.

Verilator does the measuring (it compiles the generated RTL cleanly), driven by
the same file-driven testbench the pcap framework already generates, so the
stimulus being measured is exactly the stimulus being verified.

One wrinkle, handled by verification/framework/verilator_main.cpp: Verilator
5.006's own --main does not write the coverage database, so a --coverage build
would run and discard the measurement. That file is Verilator's own event loop
plus the write.
"""
import argparse
import collections
import json
import os
import subprocess
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
_ROOT = os.path.normpath(os.path.join(_HERE, '..', '..'))
sys.path.insert(0, _HERE)
sys.path.insert(0, os.path.join(_ROOT, 'compiler'))

import pcap as pcapmod                                   # noqa: E402
from p4v import cp_writes, parse_testcase                # noqa: E402
from emit_vector_tb import emit_vector_tb                # noqa: E402


def build_and_run(app, work, pcap_path, testcase, axi_w=256, gen_flags=''):
    """Compile the app, build it under Verilator with coverage, replay the
    pcap, and return the path of the coverage database."""
    gen = os.path.join(work, 'gen')
    cmd = [sys.executable, os.path.join(_ROOT, 'compiler', 'main.py'), app,
           '--cp-map', '--axi-data-width', str(axi_w), '--out-dir', gen]
    cmd += gen_flags.split() if gen_flags else []
    p = subprocess.run(cmd, capture_output=True, text=True, cwd=_ROOT)
    if p.returncode != 0:
        raise RuntimeError(f'{app}: compile failed\n{p.stdout[-600:]}')
    with open(os.path.join(gen, f'{app}_cp_map.json')) as f:
        cpmap = json.load(f)
    tb = emit_vector_tb(app, gen, output_path=os.path.join(work, f'tb_{app}_vectors.sv'))

    packets = [d for _, _, d in pcapmod.read_pcap(pcap_path)]
    vec_in = os.path.join(work, 'in.vec')
    pcapmod.write_vector(vec_in, packets)
    tbl = os.path.join(work, 'entries.cp')
    raw, _ = parse_testcase(testcase) if testcase else ({}, [])
    with open(tbl, 'w') as f:
        for addr, data in cp_writes(raw, cpmap):
            f.write(f'{addr} {data:08x}\n')

    files = [os.path.join(gen, f'{app}_pkg.sv')] + sorted(
        os.path.join(gen, x) for x in os.listdir(gen)
        if x.endswith('.sv') and '_pkg' not in x and 'selftest' not in x)
    # --prefix Vdut keeps one C++ harness usable for every app.
    vcmd = ['verilator', '--binary', '--timing', '--coverage', '-Wno-fatal',
            '-j', '4', '--prefix', 'Vdut', '-o', 'vsim',
            '--top-module', f'tb_{app}_vectors'] + files + [
            tb, os.path.join(_HERE, 'verilator_main.cpp')]
    p = subprocess.run(vcmd, capture_output=True, text=True, cwd=work)
    if p.returncode != 0:
        raise RuntimeError(f'{app}: verilator build failed\n'
                           + '\n'.join(l for l in p.stderr.splitlines()
                                       if l.startswith('%Error'))[:800])
    dat = os.path.join(work, f'{app}.dat')
    r = subprocess.run([os.path.join(work, 'obj_dir', 'vsim'),
                        f'+vec_in={vec_in}', f'+vec_out={os.path.join(work, "out.vec")}',
                        f'+tbl={tbl}', f'+cov_out={dat}'],
                       capture_output=True, text=True, cwd=work, timeout=1800)
    if not os.path.exists(dat):
        raise RuntimeError(f'{app}: no coverage database written\n{r.stdout[-400:]}')
    return dat


def summarise(dat, work, only_generated=True):
    """{file: (covered, total)} from a coverage database."""
    info = dat + '.info'
    subprocess.run(['verilator_coverage', '--write-info', info, dat],
                   capture_output=True, text=True, check=True)
    tot, hit = collections.Counter(), collections.Counter()
    cur = None
    for line in open(info):
        line = line.strip()
        if line.startswith('SF:'):
            cur = os.path.basename(line[3:])
        elif line.startswith('DA:') and cur:
            # The testbench's own coverage is not the subject: it is the
            # stimulus, and counting it would flatter the number.
            if only_generated and cur.startswith('tb_'):
                continue
            n, h = line[3:].split(',')[:2]
            tot[cur] += 1
            if int(h) > 0:
                hit[cur] += 1
    return {f: (hit[f], tot[f]) for f in tot}


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('app')
    ap.add_argument('--pcap', required=True)
    ap.add_argument('--testcase')
    ap.add_argument('--axi-data-width', type=int, default=256)
    ap.add_argument('--gen-flags', default='')
    ap.add_argument('--work', default=None)
    ap.add_argument('--per-file', action='store_true')
    ap.add_argument('--json', metavar='PATH', help='also write the summary as JSON')
    a = ap.parse_args(argv)

    work = a.work or os.path.join('/tmp', f'cov_{a.app}')
    os.makedirs(work, exist_ok=True)
    try:
        dat = build_and_run(a.app, work, a.pcap, a.testcase,
                            a.axi_data_width, a.gen_flags)
    except Exception as e:
        print(f'{a.app}: coverage FAILED -- {e}')
        return 2
    per = summarise(dat, work)
    H = sum(h for h, _ in per.values())
    T = sum(t for _, t in per.values())
    if a.per_file:
        for f in sorted(per, key=lambda x: -per[x][1]):
            h, t = per[f]
            print(f'  {f:38s} {h:6d}/{t:<6d} {100.0*h/t:5.1f}%')
    print(f'{a.app}: {100.0*H/T:5.1f}% line coverage of the generated RTL '
          f'({H}/{T} lines)')
    if a.json:
        with open(a.json, 'w') as f:
            json.dump({'app': a.app, 'covered': H, 'total': T,
                       'pct': round(100.0*H/T, 2),
                       'per_file': {k: list(v) for k, v in per.items()}}, f, indent=1)
    return 0


if __name__ == '__main__':
    sys.exit(main())
