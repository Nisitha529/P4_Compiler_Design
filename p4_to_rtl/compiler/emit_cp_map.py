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


def _table_entry(ti, tbl, amap):
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
        out['size'] = tbl.size
        out['keys'] = [{'field': k.field, 'match': k.match_type} for k in tbl.keys]
        acts = []
        for araw in tbl.actions:
            aname = araw.strip().rstrip('()')
            action = amap.get(aname)
            acts.append({
                'name': aname,
                'params': ([{'name': p.name, 'width': p.width}
                            for p in action.params] if action else []),
            })
        out['actions'] = acts
    return out


def emit_cp_map(ir, app_name, output_path, regmap, ctrl, amap,
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
                 'fields': fields,
                 'words': _words_for(ti),
                 'note': 'records leave by the AXI4-Stream port <name>_t*, not '
                         'over AXI4-Lite; these words are statistics only'})
        else:
            tbl, am = tables_by_name.get(ti['tname'], (None, {}))
            doc['tables'].append(_table_entry(ti, tbl, am))

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
