"""
Emit <app>_cp_map.json: the control-plane register map as DATA.

docs/compiler_design.md used to say the authoritative register map is "the
14'dN: case labels in <app>_top.sv". That is fine for a testbench written by
whoever read the file, and useless to host software -- or to anything generating
proposals that must be checked against what the hardware actually supports.

Two rules this file follows, because the whole value is in not drifting:

  1. Word offsets come from emit_top's own `_reg_words` / `_n_words`, the
     SAME functions that write the SystemVerilog decoder. There is no second
     implementation of the address arithmetic to disagree with the first.
  2. Anything that cannot be derived is omitted rather than guessed. A field
     that is absent is honest; a field that is wrong is a trap.
"""
import json
import os
import subprocess

from emit_top import _reg_words, _n_words, AXIL_ADDR_W, AXIL_DATA_W, TABLE_AXIL_SZ
from emit_table import _action_ids, _key_width, _field_basename


def _git_rev(repo_root):
    """Short commit of the compiler that produced this map, or None.

    Recorded so a map found next to an old bitstream can be matched against the
    compiler that made it. None (not a guess) when this is not a git checkout.
    """
    try:
        out = subprocess.run(['git', '-C', repo_root, 'rev-parse', '--short', 'HEAD'],
                             capture_output=True, text=True, timeout=5)
        return out.stdout.strip() or None
    except (OSError, subprocess.SubprocessError):
        return None


def _words_for(ti):
    """{word_name: absolute_word_address} for one regmap window.

    Write words first, then read words, exactly as the two decoder case
    statements in emit_top number them.
    """
    words = {}
    base = ti['base']
    for idx, rname, _sig, _lo, _take in _reg_words(ti['regs']):
        words[rname] = (base + idx * 4) >> 2
    nw = _n_words(ti['regs'])
    for idx, rname, _sig, _lo, _take in _reg_words(ti['read_regs']):
        words[rname] = (base + (nw + idx) * 4) >> 2
    return words


def _field_words(words, prefix, width):
    """Bus words carrying one key or parameter, least-significant word first.

    A field wider than the bus does NOT get one word: `_reg_words` splits it
    into <name>_w0, <name>_w1, ... So a 48-bit MAC lives in two words, and a map
    that reported a single `word` reported null for it -- leaving a host unable
    to write a MAC at all. Always a list, so a caller writes the same loop for
    every field regardless of width.
    """
    if prefix in words:
        return [words[prefix]]
    out, i = [], 0
    while f'{prefix}_w{i}' in words:
        out.append(words[f'{prefix}_w{i}'])
        i += 1
    return out


def _table_entry(ti, tbl, amap, fwmap):
    """The P4-level view of a table, next to its register words.

    `keys` and `actions` come from the IR, because the regmap only keeps the
    flattened bus registers -- it has lost which P4 field and which match kind
    each one came from, and that is exactly what a caller needs in order to
    build a legal entry.
    """
    out = {
        'name':  ti['tname'],
        'stage': ti['stage'],
        'base':  f"0x{ti['base']:04X}",
        'supports_query': bool(ti['supports_query']),
        'words': _words_for(ti),
    }
    if tbl is not None:
        # The ACTION ID the hardware uses, not the list position. They differ:
        # _action_ids pins NoAction to 0 and numbers the rest from 1 in declared
        # order, so for `actions = { set_port; drop_it; NoAction; }` the ids are
        # 1, 2, 0 while the list positions are 0, 1, 2. A host that wrote the
        # position would select NoAction when it meant set_port -- exactly the
        # class of mistake this file exists to prevent.
        ids = _action_ids(tbl)
        words = out['words']
        out['size'] = tbl.size
        keys = []
        for k in tbl.keys:
            kb = _field_basename(k.field)
            entry = {
                'field': k.field,
                'match': k.match_type,
                'width': _key_width(k.field, fwmap),
                # Lists, least-significant word first -- see _field_words.
                'words':       _field_words(words, f'key_{kb}', 0),
                'query_words': _field_words(words, f'query_key_{kb}', 0),
            }
            # An LPM key is written with a prefix length, a ternary key with a
            # mask. Without the link a caller can see the word exists but not
            # which key it belongs to, and with several keys that is a guess.
            if k.match_type == 'lpm':
                entry['pfx_len_words'] = _field_words(words, 'wr_pfx_len', 0)
            elif k.match_type == 'ternary':
                entry['mask_words'] = _field_words(words, f'wr_mask_{kb}', 0)
            keys.append(entry)
        out['keys'] = keys
        acts = []
        for araw in tbl.actions:
            aname = araw.strip().rstrip('()')
            action = amap.get(aname)
            acts.append({
                'name': aname,
                'id':   ids.get(aname),
                'params': ([{'name': p.name, 'width': p.width,
                             'words': _field_words(words, f'p_{p.name}', p.width)}
                            for p in action.params] if action else []),
            })
        out['actions'] = acts
        # How an entry's slot is chosen. For an exact-match table the hardware
        # HASHES the key and wr_idx is ignored, so two keys that collide
        # silently overwrite each other -- a caller has to model that before it
        # writes, which it cannot do unless the map says so.
        if out['supports_query'] or ti.get('is_exact'):
            out['addressing'] = {
                'scheme':    'hash',
                'hash':      'xor-fold',
                'ways':      ti.get('ways', 1),
                'index_bits': ti.get('idx_w'),
                'key_bits':  sum((k['width'] or 0) for k in out['keys']),
                'note': 'the slot is chosen by XOR-folding the concatenated key '
                        'down to index_bits; wr_idx is NOT used. With ways=1 two '
                        'keys that fold to the same index overwrite each other, '
                        'so a writer must check for collisions itself.',
            }
        elif any(k['match'] in ('lpm', 'ternary') for k in out['keys']):
            # A priority table, NOT simply "direct". Every entry is compared and
            # the LOWEST INDEX WINS (emit_table.py's priority-match tree), so
            # where an entry is placed decides which of two matching entries
            # takes effect. Software therefore has to order its own inserts;
            # nothing in the hardware sorts them. Writing a /16 into a slot
            # below an existing /24 silently breaks forwarding for that prefix,
            # which is exactly the kind of mistake a generated entry makes.
            out['addressing'] = {
                'scheme':      'priority',
                'priority':    'lowest_index_wins',
                'index_word':  words.get('wr_idx'),
                'index_bits':  ti.get('idx_w'),
                'size':        tbl.size,
                'ordering': 'caller-ordered: insert MOST SPECIFIC first (longest '
                            'prefix / most mask bits set at the lowest index). The '
                            'hardware does not sort and does not compare prefix '
                            'lengths -- it returns the lowest matching index.',
            }
        else:
            out['addressing'] = {'scheme': 'direct', 'index_word': words.get('wr_idx'),
                                 'index_bits': ti.get('idx_w')}
    return out


def emit_cp_map(ir, app_name, output_path, regmap, ctrl, amap, fwmap=None,
                ectrl=None, eamap=None, axi_data_width=None, clock_hz=None,
                repo_root=None):
    """Write <app>_cp_map.json. Returns the dict it wrote."""
    tables_by_name = {}
    for c, am in ((ctrl, amap), (ectrl, eamap)):
        if c is None:
            continue
        for t in c.tables:
            tables_by_name[t.name] = (t, am or {})

    doc = {
        'app': app_name,
        'compiler_git': _git_rev(repo_root or os.getcwd()),
        'axi_data_width': axi_data_width,
        # The timestamp unit. ingress_timestamp counts PIPELINE CLOCK CYCLES, so
        # anything comparing hardware inter-arrival times against times computed
        # off-line has to agree on this number. None when it was not supplied --
        # a wrong clock is worse than an absent one, because it makes a
        # bit-exact comparison silently meaningless.
        'clock_hz': clock_hz,
        'axil': {
            'addr_w':       AXIL_ADDR_W,
            'data_w':       AXIL_DATA_W,
            'window_bytes': TABLE_AXIL_SZ,
        },
        'tables': [], 'counters': [], 'meters': [], 'digests': [],
        'feature_exports': [], 'registers': [],
    }

    for ti in regmap:
        if ti.get('is_mcast'):
            doc.setdefault('mcast', []).append(
                {'name': ti['tname'], 'base': f"0x{ti['base']:04X}",
                 'words': _words_for(ti)})
        elif ti.get('is_counter'):
            doc['counters'].append(
                {'name': ti['tname'], 'stage': ti['stage'],
                 'base': f"0x{ti['base']:04X}",
                 'has_packets': bool(ti.get('has_pkt')),
                 'has_bytes':   bool(ti.get('has_byte')),
                 'words': _words_for(ti)})
        elif ti.get('is_meter'):
            doc['meters'].append(
                {'name': ti['tname'], 'stage': ti['stage'],
                 'base': f"0x{ti['base']:04X}", 'words': _words_for(ti),
                 'note': 'rate_shift and burst are per INSTANCE, not per index; '
                         'one allowance unit returns every 2^rate_shift cycles, '
                         'charged one unit per packet'})
        elif ti.get('is_digest'):
            doc['digests'].append(
                {'name': ti['tname'], 'stage': ti['stage'],
                 'base': f"0x{ti['base']:04X}", 'width': ti.get('digest_width'),
                 'words': _words_for(ti)})
        elif ti.get('is_feature_export'):
            fe = next((x for c in (ctrl, ectrl) if c is not None
                       for x in getattr(c, 'feature_exports', [])
                       if x.name == ti['tname']), None)
            fields, lsb = [], (fe.total_width if fe else 0)
            for fname, fwidth in (fe.fields if fe else []):
                lsb -= fwidth
                fields.append({'name': fname, 'lsb': lsb, 'width': fwidth})
            doc['feature_exports'].append(
                {'name': ti['tname'], 'stage': ti['stage'],
                 'base': f"0x{ti['base']:04X}",
                 'width':        fe.total_width if fe else None,
                 'tdata_width':  ti.get('fe_width'),
                 'stage_depth':  ti.get('fe_depth'),
                 # The feed comes up ENABLED out of reset. Recorded because the
                 # consumer side would otherwise have to guess, and "no records
                 # and nothing says why" is the hardest bring-up failure to
                 # diagnose.
                 'enable_reset': 1,
                 'fields': fields,
                 'words': _words_for(ti),
                 'note': 'records leave by the AXI4-Stream port <name>_t*, not '
                         'over AXI4-Lite; these words are statistics only'})
        else:
            tbl, am = tables_by_name.get(ti['tname'], (None, {}))
            doc['tables'].append(_table_entry(ti, tbl, am, fwmap))

    for c in (ctrl, ectrl):
        if c is None:
            continue
        for r in getattr(c, 'registers', []):
            doc['registers'].append({
                'name': r.name, 'size': r.size, 'width': r.data_width,
                # Computed by emit_processing from the assigned stages. 0 means
                # read-only (no hazard); N means two packets must be at least N
                # apart for the second to see the first's write.
                'raw_distance': getattr(r, 'raw_distance', None),
            })

    with open(output_path, 'w') as f:
        json.dump(doc, f, indent=2, sort_keys=False)
        f.write('\n')
    return doc
