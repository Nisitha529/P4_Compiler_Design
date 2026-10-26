#!/usr/bin/env python3
"""Randomised stimulus for the pcap framework: random traffic, random table
entries, compared against the reference model, with a seed and a shrinker.

    python3 verification/framework/fuzz.py <app> --iterations 200
    python3 verification/framework/fuzz.py <app> --seed 12345     # reproduce

Why this exists. The framework's oracle was fed 3 to 6 hand-chosen packets per
application -- 58 in total across thirteen programs. Every datapath bug this
project has actually found came from changing a parameter or a packet shape
(the 512-bit beat width, a frame short enough to fit in the header region, a
queue deep enough to matter), not from adding another assertion to a directed
test. So the useful thing to automate is the varying, not the asserting.

How the stimulus is made, and why it is this way round. Generating random KEYS
and hoping they match a table is hopeless: one 16-bit exact key hits one time
in 65536, so such a fuzzer spends all its time on the miss path and never
executes an action. This inverts it -- generate random PACKETS, ask the model
what key values those packets present (Model.key_values), and program entries
for a subset of them. Hits, misses and several actions all follow, with no
per-program knowledge, because the model is already evaluating each table's own
key expressions.

A failing case is SHRUNK before it is reported: packets are bisected and
entries dropped one at a time for as long as the failure survives, so what you
get is a minimal reproducer and a pcap you can open, not a 40-packet haystack.
"""
import argparse
import json
import os
import random
import subprocess
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
_ROOT = os.path.normpath(os.path.join(_HERE, '..', '..'))
sys.path.insert(0, _HERE)
sys.path.insert(0, os.path.join(_ROOT, 'compiler'))

import pcap as pcapmod                                   # noqa: E402
from build_ir import build_ir                            # noqa: E402
from refmodel import Model, Entry                        # noqa: E402
from expr import Unsupported                             # noqa: E402
from emit_vector_tb import emit_vector_tb, PortError     # noqa: E402
from p4v import cp_writes, model_entries, run_sim, compare   # noqa: E402
from tablemap import collisions                              # noqa: E402


# ── traffic ──────────────────────────────────────────────────────────────────
def random_frame(rng, min_len=32, max_len=256):
    """An Ethernet frame with plausible structure and random content.

    Structure matters: a parser that selects on etherType and then extracts
    IPv4 will reject uniform noise at the first state, so noise alone would
    only ever test the reject path. A quarter of the frames are deliberately
    malformed for the same reason in reverse.
    """
    n = rng.randint(min_len, max_len)
    kind = rng.random()
    dst = bytes(rng.randrange(256) for _ in range(6))
    src = bytes(rng.randrange(256) for _ in range(6))
    if kind < 0.25:                                  # arbitrary etherType
        etype = rng.randrange(0x10000)
        body = bytes(rng.randrange(256) for _ in range(max(0, n - 14)))
        return bytes(dst + src + bytes([etype >> 8, etype & 0xFF]) + body)
    if kind < 0.45:                                  # a low etherType, as the probes use
        etype = rng.randrange(0x0010)
        body = bytes(rng.randrange(256) for _ in range(max(0, n - 14)))
        return bytes(dst + src + bytes([etype >> 8, etype & 0xFF]) + body)
    # IPv4, sometimes with a transport header
    proto = rng.choice([6, 17, 1, rng.randrange(256)])
    ttl = rng.choice([0, 1, 64, 255, rng.randrange(256)])
    ihl = 5
    payload_len = max(0, n - 14 - 20)
    body = bytes(rng.randrange(256) for _ in range(payload_len))
    ip = bytes([0x40 | ihl, rng.randrange(256), (n - 14) >> 8, (n - 14) & 0xFF,
                rng.randrange(256), rng.randrange(256), 0, 0, ttl, proto, 0, 0])
    ip += bytes(rng.randrange(256) for _ in range(4))     # src
    # Destination drawn from a small pool so LPM prefixes have something to
    # match: fully random addresses almost never share a prefix.
    ip += rng.choice([bytes([10, 0, 0, rng.randrange(8)]),
                      bytes([10, 0, rng.randrange(4), rng.randrange(256)]),
                      bytes([192, 168, 0, rng.randrange(4)]),
                      bytes(rng.randrange(256) for _ in range(4))])
    return bytes(dst + src + bytes([0x08, 0x00]) + ip + body)


def make_entries(rng, model, cpmap, packets, hit_fraction=0.7):
    """Table entries derived from what the packets actually present."""
    raw = {}
    for t in cpmap['tables']:
        name = t['name']
        acts = [a for a in t['actions'] if a['name'] != 'NoAction']
        if not acts:
            continue
        # the key tuples this traffic presents to this table
        seen = []
        for p in packets:
            try:
                kv = model.key_values(p, name)
            except Unsupported:
                kv = None
            if kv is not None:
                seen.append(tuple(v for v, _w in kv))
        seen = list(dict.fromkeys(seen))             # unique, order preserved
        rng.shuffle(seen)
        n_hit = int(len(seen) * hit_fraction)
        chosen = seen[:max(1, n_hit)] if seen else []
        # plus a couple of keys nothing presents, so the miss path is real
        for _ in range(rng.randint(0, 2)):
            chosen.append(tuple(rng.randrange(1 << min(k['width'], 24))
                                for k in t['keys']))
        rows = []
        for keys in chosen[:12]:                    # the table has a size limit
            a = rng.choice(acts)
            params = [rng.randrange(1 << min(p['width'], 24)) for p in a['params']]
            kt = [k['match'] for k in t['keys']]
            plen = None
            masks = [None] * len(keys)
            if 'lpm' in kt:
                plen = rng.choice([8, 16, 24, 32][:max(1, len(bin(max(keys))) // 4)])
                plen = min(plen, t['keys'][kt.index('lpm')]['width'])
            rows.append(dict(action=a['name'], keys=list(keys), masks=masks,
                             prefix_len=plen, priority=rng.randrange(4),
                             params=params, line=0))
        if rows:
            raw[name] = rows
    # Drop entries that cannot coexist in the hardware. Without this the
    # fuzzer spends its whole life rediscovering the direct-mapped table's
    # collision behaviour -- with twelve random keys in a sixteen-entry table a
    # collision is near-certain by the birthday bound, and it was indeed the
    # very first thing the first run found. The limitation is real and is
    # reported by p4v as its own COLLISION verdict; a bug hunt should not keep
    # tripping over it.
    while True:
        coll = collisions(cpmap, raw)
        if not coll:
            break
        tname, _idx, group = coll[0]
        drop = group[-1]
        raw[tname] = [r for r in raw[tname] if r is not drop]
        if not raw[tname]:
            del raw[tname]
    return raw


# ── one case ─────────────────────────────────────────────────────────────────
class Harness:
    """Everything that does not change between iterations, set up once."""

    def __init__(self, app, work, sim='iverilog', axi_w=256, gen_flags=''):
        self.app, self.work, self.sim, self.axi_w = app, work, sim, axi_w
        self.gen = os.path.join(work, 'gen')
        cmd = [sys.executable, os.path.join(_ROOT, 'compiler', 'main.py'), app,
               '--cp-map', '--axi-data-width', str(axi_w), '--out-dir', self.gen]
        cmd += gen_flags.split() if gen_flags else []
        p = subprocess.run(cmd, capture_output=True, text=True, cwd=_ROOT)
        if p.returncode != 0:
            raise RuntimeError(f'{app}: compile failed\n{p.stdout[-800:]}')
        with open(os.path.join(self.gen, f'{app}_cp_map.json')) as f:
            self.cpmap = json.load(f)
        self.model = Model(build_ir(app))
        self.tb = emit_vector_tb(app, self.gen,
                                 output_path=os.path.join(work, f'tb_{app}_vectors.sv'))
        self.files = [os.path.join(self.gen, f'{app}_pkg.sv')] + sorted(
            os.path.join(self.gen, x) for x in os.listdir(self.gen)
            if x.endswith('.sv') and '_pkg' not in x and 'selftest' not in x)

    def run(self, packets, raw):
        """(verdict, detail) for one packet set and entry set."""
        ments = model_entries(raw, self.cpmap)
        expected = []
        for p in packets:
            r = self.model.run(p, ments)
            if r.out_packet is not None:
                expected.append(r.out_packet)
        vec_in = os.path.join(self.work, 'in.vec')
        vec_out = os.path.join(self.work, 'out.vec')
        tbl = os.path.join(self.work, 'entries.cp')
        pcapmod.write_vector(vec_in, packets)
        with open(tbl, 'w') as f:
            for addr, data in cp_writes(raw, self.cpmap):
                f.write(f'{addr} {data:08x}\n')
        if os.path.exists(vec_out):
            os.remove(vec_out)
        run_sim(self.app, self.gen, self.tb, self.files, self.work,
                {'vec_in': vec_in, 'vec_out': vec_out, 'tbl': tbl},
                self.sim, self.axi_w // 8)
        actual = pcapmod.read_vector(vec_out) if os.path.exists(vec_out) else []
        return compare(expected, actual)


def shrink(h, packets, raw):
    """A minimal case that still fails: bisect the packets, then drop entries."""
    def fails(ps, rw):
        try:
            v, _ = h.run(ps, rw)
        except Exception:
            return False
        return v not in ('PASS', 'VACUOUS')

    # packets: halve while the failure survives, then drop one at a time
    changed = True
    while changed and len(packets) > 1:
        changed = False
        half = len(packets) // 2
        for cand in (packets[:half], packets[half:]):
            if cand and fails(cand, raw):
                packets, changed = cand, True
                break
    i = 0
    while i < len(packets) and len(packets) > 1:
        cand = packets[:i] + packets[i+1:]
        if fails(cand, raw):
            packets = cand
        else:
            i += 1
    # entries: drop any whose absence keeps the failure
    for t in list(raw):
        i = 0
        while i < len(raw[t]):
            cand = {k: (v[:i] + v[i+1:] if k == t else v) for k, v in raw.items()}
            cand = {k: v for k, v in cand.items() if v}
            if fails(packets, cand):
                raw = cand
                if t not in raw:
                    break
            else:
                i += 1
    return packets, raw


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('app')
    ap.add_argument('--iterations', type=int, default=50)
    ap.add_argument('--seed', type=int, default=None)
    ap.add_argument('--packets', type=int, default=12, help='packets per case')
    ap.add_argument('--sim', default='iverilog', choices=['iverilog', 'xsim'])
    ap.add_argument('--axi-data-width', type=int, default=256)
    ap.add_argument('--gen-flags', default='')
    ap.add_argument('--work', default=None)
    ap.add_argument('--truncated', action='store_true',
                    help='also generate frames that run the parser past the '
                         'end (a known divergence: the design has no '
                         'PacketTooShort check)')
    ap.add_argument('--quiet', action='store_true')
    a = ap.parse_args(argv)

    seed = a.seed if a.seed is not None else random.randrange(1 << 30)
    rng = random.Random(seed)
    work = a.work or os.path.join('/tmp', f'fuzz_{a.app}_{seed}')
    os.makedirs(work, exist_ok=True)

    try:
        h = Harness(a.app, work, a.sim, a.axi_data_width, a.gen_flags)
    except Unsupported as u:
        print(f'{a.app}: NOT VERIFIED -- {u}')
        return 3
    except (RuntimeError, PortError) as e:
        print(f'{a.app}: cannot set up -- {e}')
        return 2

    print(f'{a.app}: seed {seed}, {a.iterations} iteration(s) '
          f'x {a.packets} packet(s), {a.sim}')
    stats = {}
    for it in range(a.iterations):
        packets = []
        tries = 0
        while len(packets) < a.packets and tries < a.packets * 40:
            tries += 1
            p = random_frame(rng)
            if not a.truncated:
                # Ask the MODEL whether this frame runs the parser past its
                # end, rather than reasoning about which protocols this
                # particular program parses -- that keeps the filter
                # app-agnostic. Such frames are a known divergence (the design
                # implements no PacketTooShort check, see p4v's SHORT-PACKET
                # verdict), so including them by default would make every
                # iteration fail for the same already-known reason and hide
                # everything else.
                try:
                    if h.model.run(p, {}).truncated:
                        continue
                except Unsupported:
                    continue
            packets.append(p)
        if len(packets) < a.packets:
            print(f'  iteration {it}: could not generate {a.packets} '
                  f'non-truncated frame(s); use --truncated to allow them')
            break
        raw = make_entries(rng, h.model, h.cpmap, packets)
        try:
            verdict, detail = h.run(packets, raw)
        except Unsupported as u:
            print(f'  iteration {it}: NOT VERIFIED -- {u}')
            return 3
        stats[verdict] = stats.get(verdict, 0) + 1
        if verdict in ('PASS', 'VACUOUS'):
            if not a.quiet and it % 10 == 0:
                print(f'  {it:4d}/{a.iterations}  {verdict}')
            continue
        print(f'\n  iteration {it}: {verdict} -- {detail}')
        print('  shrinking...')
        packets, raw = shrink(h, packets, raw)
        v2, d2 = h.run(packets, raw)
        bad_pcap = os.path.join(work, 'failing.pcap')
        pcapmod.write_pcap(bad_pcap, packets)
        with open(os.path.join(work, 'failing.txt'), 'w') as f:
            f.write(f'# minimal reproducer, seed {seed}, iteration {it}\n')
            # The key forms MUST be written back exactly as generated. An
            # earlier version wrote bare key values and dropped the LPM prefix
            # lengths and ternary masks, so the "minimal reproducer" did not
            # reproduce -- which is worse than no reproducer, because it sends
            # you looking for the difference in the wrong place.
            for t, rows in raw.items():
                for r in rows:
                    parts = []
                    for i, k in enumerate(r['keys']):
                        if r.get('prefix_len') is not None:
                            parts.append(f'{hex(k)}/{r["prefix_len"]}')
                        elif r.get('masks') and i < len(r['masks']) and r['masks'][i] is not None:
                            parts.append(f'{hex(k)}&{hex(r["masks"][i])}')
                        else:
                            parts.append(hex(k))
                    if r.get('priority'):
                        parts.append(f'priority={r["priority"]}')
                    ps = ' '.join(hex(p) for p in r['params'])
                    f.write(f'table_add {t} {r["action"]} ' + ' '.join(parts)
                            + (f' => {ps}' if ps else '') + '\n')
            f.write('run_traffic failing\n')
        print(f'  MINIMAL CASE: {len(packets)} packet(s), '
              f'{sum(len(v) for v in raw.values())} entry/entries -> {v2}: {d2}')
        print(f'  reproduce: python3 verification/framework/p4v.py {a.app} '
              f'--pcap {bad_pcap} --testcase {os.path.join(work, "failing.txt")}')
        print(f'  or the whole run: --seed {seed}')
        return 1

    print(f'{a.app}: ' + ', '.join(f'{v}={n}' for v, n in sorted(stats.items()))
          + f'  (seed {seed})')
    return 0 if not (set(stats) - {'PASS', 'VACUOUS'}) else 1


if __name__ == '__main__':
    sys.exit(main())
