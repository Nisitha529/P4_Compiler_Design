"""Where an entry lands in a generated exact-match table, and which entries
therefore cannot coexist.

The reference model is an IDEAL table: any set of distinct keys can be held and
the longest/highest-priority match wins. The generated hardware is not. An
exact-match table is a BRAM addressed by an XOR-fold of the key, direct-mapped
unless the design was generated with `--exact-match-ways N`, so two keys that
fold to the same index overwrite one another and the earlier entry simply
stops existing.

That difference is real and documented, but without this module it surfaces as
a byte-level packet diff that looks like a datapath bug. The first randomised
run hit it immediately: keys 0x2c38 and 0xf965 both fold to index 5 in a
16-entry table, the second write displaced the first, and the packet that
should have matched missed. Thirty minutes of staring at a hex diff to
rediscover a known limitation.

So the framework computes the index itself, from the cp_map (which carries
`addressing.index_bits`, `key_bits`, `ways` and the hash name) and reports a
collision as its own outcome. The fold below mirrors emit_table.py's
`hash_key`: XOR the key in index_bits-wide chunks over the key width rounded
up to a whole number of chunks.
"""


def table_index(table, key_values):
    """Which BRAM index `key_values` addresses in `table`, or None if the
    table is not hash-addressed (LPM and ternary tables scan, so they have no
    collision of this kind)."""
    a = table.get('addressing') or {}
    if a.get('scheme') != 'hash':
        return None
    idx_w = int(a['index_bits'])
    key_w = int(a['key_bits'])
    if idx_w <= 0:
        return None
    # The key is the concatenation of the key fields, first field most
    # significant -- the same order emit_table.py concatenates cp_wr_key_*.
    k = 0
    for kdef, v in zip(table['keys'], key_values):
        w = int(kdef['width'])
        k = (k << w) | (int(v) & ((1 << w) - 1))
    padded = ((key_w + idx_w - 1) // idx_w) * idx_w
    h = 0
    for c in range(padded // idx_w):
        h ^= (k >> (c * idx_w)) & ((1 << idx_w) - 1)
    return h


def collisions(cpmap, raw):
    """Entry groups that cannot coexist in the hardware, as
    [(table, index, [row, ...])] -- only groups larger than the table's ways."""
    out = []
    tmap = {t['name']: t for t in cpmap['tables']}
    for tname, rows in raw.items():
        t = tmap.get(tname)
        if t is None:
            continue
        ways = int((t.get('addressing') or {}).get('ways', 1) or 1)
        buckets = {}
        for r in rows:
            idx = table_index(t, r['keys'])
            if idx is None:
                continue
            buckets.setdefault(idx, []).append(r)
        for idx, group in sorted(buckets.items()):
            # Entries with the SAME key are a rewrite, not a collision: the
            # second simply replaces the first, which the model does too.
            distinct = {tuple(r['keys']): r for r in group}
            if len(distinct) > ways:
                out.append((tname, idx, list(distinct.values())))
    return out


def describe(cpmap, coll):
    """A human-readable account of one collision group."""
    tmap = {t['name']: t for t in cpmap['tables']}
    tname, idx, rows = coll
    t = tmap[tname]
    ways = int((t.get('addressing') or {}).get('ways', 1) or 1)
    keys = ', '.join('(' + ' '.join(hex(k) for k in r['keys']) + ')' for r in rows)
    return (f'table {tname!r}: {len(rows)} distinct keys fold to index {idx} '
            f'but the table holds {ways} per index -- {keys}. '
            f'The last one written is the only one the hardware keeps. '
            f'Regenerate with --exact-match-ways {len(rows)} (or more) to hold '
            f'them all, or choose keys that do not collide.')
