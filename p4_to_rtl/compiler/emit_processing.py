import io
import math
import re

from ir import Assignment, ExternCall, IfStatement, TableApply, ActionParam

# ============================================================
# Standard-metadata field widths (v1model definitions)
# ============================================================
_STD_META_WIDTHS = {
    'egress_spec': 9, 'ingress_port': 9, 'egress_port': 9,
    'instance_type': 32, 'packet_length': 32, 'priority': 3,
    'mcast_grp': 16, 'egress_rid': 16, 'checksum_error': 1,
    'enq_timestamp': 32, 'enq_qdepth': 19, 'deq_timedelta': 32, 'deq_qdepth': 19,
    'ingress_global_timestamp': 48, 'egress_global_timestamp': 48,
}

# ============================================================
# Maps
# ============================================================

def _build_const_map(ir):
    cmap = {}
    for name, entry in ir.consts.items():
        if isinstance(entry, dict):
            val_str = entry['value'].strip()
            w       = entry.get('width', 32)
        else:
            val_str = str(entry).strip()
            w       = 32
        try:
            if val_str.startswith('0x') or val_str.startswith('0X'):
                iv     = int(val_str, 16)
                digits = max(1, (w + 3) // 4)
                cmap[name] = f"{w}'h{iv:0{digits}X}"
            else:
                iv = int(val_str)
                cmap[name] = f"{w}'d{iv}"
        except ValueError:
            cmap[name] = val_str
    return cmap


def _build_field_width_map(ir):
    fwmap = {}
    for inst in ir.header_instances:
        if inst.is_stack:
            continue
        for fld in inst.header_type.fields:
            if fld.width:
                fwmap[f'{inst.inst_name}_{fld.name}'] = fld.width
    if not fwmap:
        for h in ir.headers:
            for fld in h.fields:
                if fld.width:
                    fwmap[f'{h.name}_{fld.name}'] = fld.width
    # Include metadata fields so table key widths resolve correctly
    for mf in ir.metadata_fields:
        fwmap[f'meta_{mf.name}'] = mf.width
    # Include control-local variables used as table keys (e.g. bit<16> table_key_sport)
    for block in ir.controls.values():
        for lv in block.local_vars:
            if lv.name not in fwmap:
                fwmap[lv.name] = lv.width
    return fwmap


# ============================================================
# Signal helpers
# ============================================================

def _sig(field_expr):
    s = field_expr.strip()
    s = re.sub(r'^hdr\.', '', s)
    s = re.sub(r'^meta\.', 'meta_', s)
    return s.replace('.', '_')


def _out(field_expr):
    return 'out_' + _sig(field_expr)


def _is_hdr(expr):
    return expr.strip().startswith('hdr.')


def _is_std_meta(expr):
    return expr.strip().startswith('standard_metadata.')


def _is_meta(expr):
    return re.match(r'^meta\.', expr.strip()) is not None


def _std_meta_fname(expr):
    m = re.match(r'^standard_metadata\.(\w+)$', expr.strip())
    return m.group(1) if m else None


def _meta_fname(expr):
    m = re.match(r'^meta\.(\w+)$', expr.strip())
    return m.group(1) if m else None


def _lhs_sig(lhs):
    lhs = lhs.strip()
    if _is_hdr(lhs):
        return _out(lhs)
    fn = _std_meta_fname(lhs)
    if fn:
        return f'out_std_meta_{fn}'
    mfn = _meta_fname(lhs)
    if mfn:
        return f'meta_{mfn}_w'        # writable shadow of the metadata input
    return re.sub(r'[.\[\]]', '_', lhs)


def _map_cond(cond, cmap=None):
    cond = re.sub(r'(\w+)\.apply\(\)\.(\w+)', r'\1_\2', cond)
    cond = re.sub(r'hdr\.(\w+)\.isValid\(\)', r'\1_valid', cond)
    cond = re.sub(r'hdr\.(\w+)\.(\w+)', r'\1_\2', cond)
    cond = re.sub(r'\bmeta\.(\w+)', r'meta_\1_w', cond)  # reads use the shadow
    if cmap:
        for name, sv_lit in cmap.items():
            cond = re.sub(r'\b' + re.escape(name) + r'\b', sv_lit, cond)
    return cond


def _map_expr(e, cmap=None):
    e = re.sub(r'hdr\.(\w+)\.(\w+)', r'\1_\2', e)
    e = re.sub(r'\bmeta\.(\w+)', r'meta_\1_w', e)          # reads use the shadow
    e = re.sub(r'\bstandard_metadata\.(\w+)', r'std_meta_\1', e)
    if cmap:
        for name, sv_lit in cmap.items():
            e = re.sub(r'\b' + re.escape(name) + r'\b', sv_lit, e)
    return e


# ============================================================
# Control-block resolution
# ============================================================

def _find_processing_ctrl(ir):
    if ir.pipeline.ingress is not None:
        return ir.pipeline.ingress
    _SKIP = {'parser', 'deparser', 'verify', 'compute', 'checksum'}
    for name, block in ir.controls.items():
        if not any(k in name.lower() for k in _SKIP):
            return block
    return None


# ============================================================
# Port collection helpers
# ============================================================

def _collect_std_meta_outputs(ctrl):
    fields = {}
    for action in ctrl.actions:
        for stmt in action.body:
            if isinstance(stmt, Assignment):
                fn = _std_meta_fname(stmt.lhs)
                if fn:
                    fields[fn] = _STD_META_WIDTHS.get(fn, 32)
    return fields


def _collect_std_meta_inputs(tables):
    fields = {}
    for tbl in tables:
        for key in tbl.keys:
            fn = _std_meta_fname(key.field)
            if fn:
                fields[fn] = _STD_META_WIDTHS.get(fn, 9)
    return fields


# ============================================================
# Table metadata helpers
# ============================================================

def _table_action_ids(table):
    ids = {}
    next_id = 1
    for raw in table.actions:
        name = raw.strip().rstrip('()')
        if name == 'NoAction':
            ids[name] = 0
        else:
            if name not in ids:
                ids[name] = next_id
                next_id += 1
    if 'NoAction' not in ids:
        ids['NoAction'] = 0
    return ids


def _table_params(table, amap):
    seen = {}
    for raw in table.actions:
        aname = raw.strip().rstrip('()')
        if aname == 'NoAction':
            continue
        action = amap.get(aname)
        if action is None:
            continue
        for p in action.params:
            if isinstance(p, ActionParam):
                pname, w = p.name, (p.width or 32)
            else:
                pname, w = str(p), 32
            if pname not in seen:
                seen[pname] = w
    return list(seen.items())


def _field_basename(field_expr):
    return field_expr.strip().split('.')[-1]


def _table_key_sig(key_field):
    """Map a P4 key field to its SV signal name inside processing_generated."""
    fn = _std_meta_fname(key_field)
    if fn:
        return f'std_meta_{fn}'
    mfn = _meta_fname(key_field)
    if mfn:
        return f'meta_{mfn}_w'        # use the writable shadow
    return _sig(key_field)


# ============================================================
# Local signal detection
# ============================================================

def _collect_local_signals(ctrl, fwmap, table_wire_names=None, meta_shadow_names=None):
    locals_ = {}
    tbl_wires    = table_wire_names  or set()
    meta_shadows = meta_shadow_names or set()

    def _param_widths(action):
        pw = {}
        for p in action.params:
            if isinstance(p, ActionParam):
                pw[p.name] = p.width or 32
        return pw

    def _scan_cond(cond):
        for m in re.finditer(r'(\w+)\.apply\(\)\.(\w+)', cond):
            sig = f'{m.group(1)}_{m.group(2)}'
            if sig in tbl_wires or sig in meta_shadows:
                continue
            if sig not in locals_:
                locals_[sig] = 1

    def _scan_stmts(stmts):
        for s in stmts:
            if isinstance(s, Assignment):
                if not _is_hdr(s.lhs) and not _is_std_meta(s.lhs) and not _is_meta(s.lhs):
                    n = _lhs_sig(s.lhs)
                    if n not in locals_ and n not in tbl_wires and n not in meta_shadows:
                        rhs_sig = _map_expr(s.rhs)
                        locals_[n] = fwmap.get(rhs_sig, 16)
            elif isinstance(s, IfStatement):
                _scan_cond(s.condition)
                _scan_stmts(s.then_body)
                _scan_stmts(s.else_body)
            elif isinstance(s, TableApply) and s.result_var:
                if s.result_var not in locals_ and s.result_var not in tbl_wires:
                    locals_[s.result_var] = 1

    for a in ctrl.actions:
        pw = _param_widths(a)
        for stmt in a.body:
            if isinstance(stmt, Assignment):
                if not _is_hdr(stmt.lhs) and not _is_std_meta(stmt.lhs) and not _is_meta(stmt.lhs):
                    n = _lhs_sig(stmt.lhs)
                    if n not in locals_ and n not in tbl_wires and n not in meta_shadows:
                        rhs = stmt.rhs.strip()
                        if rhs in pw:
                            locals_[n] = pw[rhs]
                        else:
                            rhs_sig = _map_expr(rhs)
                            locals_[n] = fwmap.get(rhs_sig, 32)

    for lv in ctrl.local_vars:
        if lv.name not in tbl_wires and lv.name not in meta_shadows:
            locals_[lv.name] = lv.width

    _scan_stmts(ctrl.statements)
    return locals_


# ============================================================
# Inlining helpers
# ============================================================

def _inline(action_name, amap, depth=0):
    if depth > 16 or action_name not in amap:
        return []
    result = []
    for stmt in amap[action_name].body:
        if isinstance(stmt, Assignment):
            result.append(stmt)
        elif isinstance(stmt, ExternCall):
            sub = _inline(stmt.name, amap, depth + 1)
            if sub:
                result.extend(sub)
            else:
                result.append(stmt)
    return result


def _emit_inlined_body(f, body_stmts, pmap, cmap, ind):
    for stmt in body_stmts:
        if isinstance(stmt, Assignment):
            lhs = _lhs_sig(stmt.lhs)
            rhs = stmt.rhs
            for pname, psig in pmap.items():
                rhs = re.sub(r'(?<!\.)\b' + re.escape(pname) + r'\b', psig, rhs)
            f.write(f'{ind}{lhs} = {_map_expr(rhs, cmap)};\n')
        elif isinstance(stmt, ExternCall):
            _emit_extern_stub(f, stmt, ind, pmap, cmap)


def _subst(text, pmap, cmap):
    for pname, psig in pmap.items():
        text = re.sub(r'(?<!\.)\b' + re.escape(pname) + r'\b', psig, text)
    return _map_expr(text, cmap)


def _collect_reg_reads(ctrl):
    seen  = set()
    reads = []

    def _record(obj, dest, addr):
        key = (obj, dest)
        if key not in seen:
            seen.add(key)
            reads.append((obj, dest, addr))

    def _scan(stmts):
        for s in stmts:
            if isinstance(s, ExternCall) and '.' in s.name:
                obj, method = s.name.split('.', 1)
                if method == 'read' and len(s.args) >= 2:
                    _record(obj, s.args[0].strip(), s.args[1].strip())
            elif isinstance(s, IfStatement):
                _scan(s.then_body)
                _scan(s.else_body)

    _scan(ctrl.statements)
    for a in ctrl.actions:
        for s in a.body:
            if isinstance(s, ExternCall) and '.' in s.name:
                obj, method = s.name.split('.', 1)
                if method == 'read' and len(s.args) >= 2:
                    _record(obj, s.args[0].strip(), s.args[1].strip())
    return reads


def _emit_extern_stub(f, stmt, ind, pmap, cmap):
    """Emit RTL for extern calls: setValid/setInvalid, mark_to_drop, hash, register.read/write."""
    name = stmt.name

    if name == 'mark_to_drop':
        f.write(f'{ind}drop = 1;\n')
        return

    if name == 'hash':
        if len(stmt.args) >= 5:
            out_var   = _subst(stmt.args[0], pmap, cmap)
            field_arg = stmt.args[3].strip().lstrip('{').rstrip('}')
            fields    = [_subst(fi.strip(), pmap, cmap)
                         for fi in field_arg.split(',') if fi.strip()]
            max_val   = stmt.args[4].strip().lstrip('(').rstrip(')').split()[-1]
            try:
                max_int = int(max_val)
                bits    = max(1, math.ceil(math.log2(max_int)))
            except ValueError:
                bits = 12
            xor_expr = ' ^ '.join(fields) if fields else "32'd0"
            f.write(f'{ind}// hash() stub — XOR-based behavioral approximation\n')
            f.write(f'{ind}{out_var} = ({xor_expr}) & {bits}\'h{(2**bits - 1):X};\n')
        else:
            f.write(f'{ind}/* UNIMPLEMENTED: hash() — insufficient args */\n')
        return

    if '.' in name:
        parts = name.split('.')
        # hdr.HEADER.setValid() / hdr.HEADER.setInvalid()
        if len(parts) == 3 and parts[0] == 'hdr' and parts[2] in ('setValid', 'setInvalid'):
            hdr_name = parts[1]
            val = "1'b1" if parts[2] == 'setValid' else "1'b0"
            f.write(f'{ind}out_{hdr_name}_valid = {val};\n')
            return
        # HEADER.setValid() / HEADER.setInvalid()  (from action-body parser: obj=header_name)
        if len(parts) == 2 and parts[1] in ('setValid', 'setInvalid'):
            hdr_name = parts[0]
            val = "1'b1" if parts[1] == 'setValid' else "1'b0"
            f.write(f'{ind}out_{hdr_name}_valid = {val};\n')
            return
        obj, method = name.split('.', 1)
        if method == 'read' and len(stmt.args) >= 2:
            raw_out = stmt.args[0].strip()
            out_var = _subst(raw_out, pmap, cmap)
            f.write(f'{ind}{out_var} = {obj}_rd_{raw_out};\n')
            return
        if method == 'write' and len(stmt.args) >= 2:
            addr = _subst(stmt.args[0], pmap, cmap)
            data = _subst(stmt.args[1], pmap, cmap)
            f.write(f'{ind}{obj}_wr_en   = 1\'b1;\n')
            f.write(f'{ind}{obj}_wr_addr = {addr};\n')
            f.write(f'{ind}{obj}_wr_data = {data};\n')
            return
        f.write(f'{ind}/* UNIMPLEMENTED EXTERN: {name}({", ".join(stmt.args)}) */\n')
        return

    f.write(f'{ind}/* UNIMPLEMENTED EXTERN: {name}({", ".join(stmt.args)}) */\n')


# ============================================================
# Table case-statement emitter
# ============================================================

def _emit_table_case(f, table, amap, ind, cmap):
    act_ids      = _table_action_ids(table)
    params       = _table_params(table, amap)
    n_acts       = max(act_ids.values()) + 1 if act_ids else 1
    id_w         = max(1, math.ceil(math.log2(n_acts))) if n_acts > 1 else 1
    hit_sig      = f'{table.name}_hit'
    aid_sig      = f'{table.name}_act_id'
    default_name = (table.default_action or 'NoAction').rstrip('()')
    default_id   = act_ids.get(default_name, 0)

    f.write(f'{ind}// {table.name}.apply()\n')
    f.write(f'{ind}if ({hit_sig}) begin\n')
    f.write(f'{ind}  unique case ({aid_sig})\n')

    for aname, aid in sorted(act_ids.items(), key=lambda x: x[1]):
        if aname == 'NoAction':
            f.write(f'{ind}    {id_w}\'d{aid}: ; // NoAction\n')
            continue
        action = amap.get(aname)
        if action is None:
            continue
        pmap = {}
        for p in action.params:
            pname = p.name if isinstance(p, ActionParam) else str(p)
            pmap[pname] = f'{table.name}_p_{pname}'
        f.write(f'{ind}    {id_w}\'d{aid}: begin // {aname}\n')
        _emit_inlined_body(f, action.body, pmap, cmap, ind + '      ')
        f.write(f'{ind}    end\n')

    f.write(f'{ind}    default: ; // default = {default_name}\n')
    f.write(f'{ind}  endcase\n')
    f.write(f'{ind}end')

    if default_name not in ('NoAction',):
        action = amap.get(default_name)
        f.write(f' else begin // {default_name} on miss\n')
        if action:
            _emit_inlined_body(f, action.body, {}, cmap, ind + '  ')
        f.write(f'{ind}end\n')
    else:
        f.write('\n')


# ============================================================
# Pipeline-stage scheduler
# ============================================================
#
# Exact-match tables now have 1-cycle lookup latency (hash + BRAM read,
# see emit_table.py) instead of the old 0-cycle combinational scan. The
# apply block has to be split at each exact-match table's apply point so
# that everything depending on its hit/action_id executes one clock
# later than everything that produces its key inputs.
#
# `_split_stage` walks a statement list and divides it into a `before`
# half (runs this stage) and an `after` half (runs next stage, once the
# split table's result is registered). Two cases:
#   1. The split table is referenced directly (`tbl.apply()` statement,
#      or as an `if (tbl.apply().hit)` condition) -> that statement (and
#      everything textually after it) moves to `after` unchanged; its own
#      condition already reads the table's correctly-timed registered
#      output wire.
#   2. The split table sits inside an unrelated enclosing `if` (e.g. a
#      combinational LPM table's hit gating an exact-match table's
#      apply) -> that condition is unrelated to the split table's timing,
#      so it must be evaluated in this stage and its boolean result
#      forwarded to next stage via a register (`__stage_cond_N_r`).

def _tbl_refs_in_cond(cond):
    return {m.group(1) for m in re.finditer(r'(\w+)\.apply\(\)\.(\w+)', cond)}


def _split_stage(stmts, split_name, fwd_counter):
    before, after = [], []
    forwards = []
    found = False

    for s in stmts:
        if found:
            after.append(s)
            continue

        if isinstance(s, TableApply) and s.table_name == split_name:
            found = True
            after.append(s)
            continue

        if isinstance(s, IfStatement):
            if split_name in _tbl_refs_in_cond(s.condition):
                found = True
                after.append(s)
                continue

            sb_then, sa_then, sf_then, f_then = _split_stage(s.then_body, split_name, fwd_counter)
            sb_else, sa_else, sf_else, f_else = _split_stage(s.else_body, split_name, fwd_counter)

            if f_then or f_else:
                found = True
                reg_name = f'__stage_cond_{fwd_counter[0]}_r'
                fwd_counter[0] += 1
                forwards.append((reg_name, s.condition))

                before_if = IfStatement(s.condition)
                before_if.then_body, before_if.else_body = sb_then, sb_else
                before.append(before_if)

                after_if = IfStatement(reg_name)
                after_if.then_body, after_if.else_body = sa_then, sa_else
                after.append(after_if)

                forwards.extend(sf_then)
                forwards.extend(sf_else)
                continue
            else:
                before.append(s)
                continue

        before.append(s)

    return before, after, forwards, found


def _find_first_exact_table(stmts, exact_names):
    for s in stmts:
        if isinstance(s, TableApply) and s.table_name in exact_names:
            return s.table_name
        if isinstance(s, IfStatement):
            refs = _tbl_refs_in_cond(s.condition) & exact_names
            if refs:
                return next(iter(refs))
            r = _find_first_exact_table(s.then_body, exact_names)
            if r:
                return r
            r = _find_first_exact_table(s.else_body, exact_names)
            if r:
                return r
    return None


def _schedule_stages(ctrl_statements, exact_names):
    """Returns (stages, boundary_forwards): stages[0] runs this cycle,
    stages[i] runs i cycles later. boundary_forwards[i] is the list of
    (reg_name, raw_condition) pairs registered between stage i and i+1."""
    remaining = ctrl_statements
    names_left = set(exact_names)
    stages = []
    boundary_forwards = []
    fwd_counter = [0]

    while True:
        target = _find_first_exact_table(remaining, names_left)
        if target is None:
            stages.append(remaining)
            break
        before, after, fwd, _ = _split_stage(remaining, target, fwd_counter)
        stages.append(before)
        boundary_forwards.append(fwd)
        names_left.discard(target)
        remaining = after

    return stages, boundary_forwards


# ============================================================
# Apply-block statement emitter
# ============================================================

def _emit_stmts(f, stmts, amap, ind, cmap, ctrl_tables):
    for stmt in stmts:

        if isinstance(stmt, IfStatement):
            tbl_applies = list(re.finditer(r'(\w+)\.apply\(\)\.(\w+)', stmt.condition))

            f.write(f'{ind}if ({_map_cond(stmt.condition, cmap)}) begin\n')

            for tm in tbl_applies:
                tname = tm.group(1)
                tbl   = next((t for t in ctrl_tables if t.name == tname), None)
                if tbl:
                    _emit_table_case(f, tbl, amap, ind + '  ', cmap)

            _emit_stmts(f, stmt.then_body, amap, ind + '  ', cmap, ctrl_tables)
            f.write(f'{ind}end\n')
            if stmt.else_body:
                f.write(f'{ind}else begin\n')
                _emit_stmts(f, stmt.else_body, amap, ind + '  ', cmap, ctrl_tables)
                f.write(f'{ind}end\n')

        elif isinstance(stmt, TableApply):
            tbl = next((t for t in ctrl_tables if t.name == stmt.table_name), None)
            if tbl and tbl.keys:
                _emit_table_case(f, tbl, amap, ind, cmap)
            else:
                f.write(f'{ind}// {stmt.table_name}.apply()  [no keys — stub]\n')

        elif isinstance(stmt, ExternCall):
            action = amap.get(stmt.name)
            if stmt.name == 'mark_to_drop':
                f.write(f'{ind}drop = 1;\n')
            elif action and stmt.args and action.params:
                pmap = {}
                for i, p in enumerate(action.params):
                    pname = p.name if isinstance(p, ActionParam) else str(p)
                    if i < len(stmt.args):
                        pmap[pname] = _map_expr(stmt.args[i], cmap)
                f.write(f'{ind}// {stmt.name}({", ".join(stmt.args)})\n')
                _emit_inlined_body(f, action.body, pmap, cmap, ind)
            elif action:
                inlined = _inline(stmt.name, amap)
                if inlined:
                    f.write(f'{ind}// {stmt.name}()\n')
                    _emit_inlined_body(f, inlined, {}, cmap, ind)
                else:
                    f.write(f'{ind}/* UNIMPLEMENTED EXTERN: {stmt.name}() */\n')
            else:
                _emit_extern_stub(f, stmt, ind, {}, cmap)

        elif isinstance(stmt, Assignment):
            lhs = _lhs_sig(stmt.lhs)
            rhs = _map_expr(stmt.rhs, cmap)
            f.write(f'{ind}{lhs} = {rhs};\n')


# ============================================================
# Main emitter
# ============================================================

def emit_processing(ir, output_path):

    ctrl = _find_processing_ctrl(ir)
    if ctrl is None:
        raise RuntimeError(
            "emit_processing: no processing control block found in ir.controls."
        )

    cmap          = _build_const_map(ir)
    amap          = {a.name: a for a in ctrl.actions}
    fwmap         = _build_field_width_map(ir)
    std_meta_outs = _collect_std_meta_outputs(ctrl)
    std_meta_ins  = _collect_std_meta_inputs(ctrl.tables)

    # ── Port lists ─────────────────────────────────────────────────────────
    instances  = ir.header_instances
    hdr_ports  = []
    hdr_valids = []
    if instances:
        for inst in instances:
            if inst.is_stack:
                continue
            hdr_valids.append(inst.inst_name)
            for fld in inst.header_type.fields:
                if fld.width:
                    hdr_ports.append((inst.inst_name, fld.name, fld.width))
    else:
        for h in ir.headers:
            hdr_valids.append(h.name)
            for fld in h.fields:
                if fld.width:
                    hdr_ports.append((h.name, fld.name, fld.width))

    meta_fields = ir.metadata_fields

    # ── Metadata shadow names (writable copies of metadata input ports) ────
    meta_shadow_names = {f'meta_{mf.name}_w' for mf in meta_fields}

    # ── Table wiring info ──────────────────────────────────────────────────
    table_wires = []
    for tbl in ctrl.tables:
        if not tbl.keys:
            continue
        act_ids  = _table_action_ids(tbl)
        n_acts   = max(act_ids.values()) + 1 if act_ids else 1
        id_w     = max(1, math.ceil(math.log2(n_acts))) if n_acts > 1 else 1
        params   = _table_params(tbl, amap)
        key_sigs = [(_field_basename(k.field), _table_key_sig(k.field),
                     _STD_META_WIDTHS.get(_std_meta_fname(k.field) or '', None)
                     or fwmap.get(_sig(k.field), 32))
                    for k in tbl.keys]
        # Fix meta.* key widths via fwmap (already includes meta_ entries)
        fixed_key_sigs = []
        for fname, ksig, kw in key_sigs:
            mfn = _meta_fname(tbl.keys[len(fixed_key_sigs)].field)
            if mfn and f'meta_{mfn}' in fwmap:
                kw = fwmap[f'meta_{mfn}']
            fixed_key_sigs.append((fname, ksig, kw))
        mt = tbl.keys[0].match_type if tbl.keys else 'exact'
        table_wires.append({
            'table': tbl, 'hit_sig': f'{tbl.name}_hit',
            'aid_sig': f'{tbl.name}_act_id', 'id_w': id_w,
            'params': params, 'key_sigs': fixed_key_sigs,
            'depth': tbl.size if tbl.size else 1024,
            'is_exact': mt not in ('lpm', 'ternary'),
        })

    tbl_wire_names = set()
    for tw in table_wires:
        tbl_wire_names.add(tw['hit_sig'])
        tbl_wire_names.add(tw['aid_sig'])
        for pname, _ in tw['params']:
            tbl_wire_names.add(f"{tw['table'].name}_p_{pname}")

    locals_ = _collect_local_signals(ctrl, fwmap, tbl_wire_names, meta_shadow_names)

    registers = ctrl.registers

    with open(output_path, 'w') as f:

        # ── Module declaration ──────────────────────────────────────────
        f.write('module processing_generated (\n')
        f.write('  input  logic        clk,\n')
        f.write('  input  logic        rst_n,\n')
        f.write('  input  logic        valid_in,\n')

        f.write('\n  // Header valid flags\n')
        for hname in hdr_valids:
            f.write(f'  input  logic        {hname}_valid,\n')

        f.write('\n  // Header field inputs\n')
        for hname, fname, w in hdr_ports:
            f.write(f'  input  logic [{w-1}:0] {hname}_{fname},\n')

        if meta_fields:
            f.write('\n  // Metadata inputs\n')
            for mf in meta_fields:
                f.write(f'  input  logic [{mf.width-1}:0] meta_{mf.name},\n')

        if std_meta_ins:
            f.write('\n  // Standard metadata inputs (table key sources)\n')
            for fname in sorted(std_meta_ins):
                fw = std_meta_ins[fname]
                f.write(f'  input  logic [{fw-1}:0] std_meta_{fname},\n')

        f.write('\n  // Header valid flag outputs (may be modified by setValid/setInvalid)\n')
        for hname in hdr_valids:
            f.write(f'  output logic        out_{hname}_valid,\n')

        f.write('\n  // Header field outputs (pass-through, optionally modified)\n')
        for hname, fname, w in hdr_ports:
            f.write(f'  output logic [{w-1}:0] out_{hname}_{fname},\n')

        if std_meta_outs:
            f.write('\n  // Standard metadata outputs\n')
            for fname in sorted(std_meta_outs):
                fw = std_meta_outs[fname]
                f.write(f'  output logic [{fw-1}:0] out_std_meta_{fname},\n')

        # CP write ports for each table
        if table_wires:
            f.write('\n  // Control-plane write ports for table instances\n')
            for tw in table_wires:
                tbl   = tw['table']
                tname = tbl.name
                depth = tw['depth']
                idx_w = max(1, math.ceil(math.log2(depth))) if depth > 1 else 1
                mt    = tbl.keys[0].match_type if tbl.keys else 'exact'
                is_lpm     = (mt == 'lpm')
                is_ternary = (mt == 'ternary')
                f.write(f'  input  logic        {tname}_cp_wr_en,\n')
                f.write(f'  input  logic [{idx_w-1}:0] {tname}_cp_wr_idx,\n')
                for fname, _, kw in tw['key_sigs']:
                    f.write(f'  input  logic [{kw-1}:0] {tname}_cp_wr_key_{fname},\n')
                if is_lpm:
                    key_w = tw['key_sigs'][0][2] if tw['key_sigs'] else 32
                    pfx_w = max(1, math.ceil(math.log2(key_w + 1)))
                    f.write(f'  input  logic [{pfx_w-1}:0] {tname}_cp_wr_pfx_len,\n')
                elif is_ternary:
                    for fname, _, kw in tw['key_sigs']:
                        f.write(f'  input  logic [{kw-1}:0] {tname}_cp_wr_mask_{fname},\n')
                f.write(f'  input  logic [{tw["id_w"]-1}:0] {tname}_cp_wr_action,\n')
                for pname, pw in tw['params']:
                    f.write(f'  input  logic [{pw-1}:0] {tname}_cp_wr_p_{pname},\n')

        # Table hit outputs (for external observation / CAM integration)
        if table_wires:
            f.write('\n  // Table hit outputs\n')
            for tw in table_wires:
                f.write(f'  output logic        {tw["table"].name}_hit_out,\n')

        f.write('\n  output logic        valid_out,\n')
        f.write('  output logic        drop\n')
        f.write(');\n\n')

        # ── Pipeline-stage scheduling ────────────────────────────────────
        exact_names = {tw['table'].name for tw in table_wires if tw['is_exact']}
        stages, boundary_forwards = _schedule_stages(ctrl.statements, exact_names)
        n_bounds = len(boundary_forwards)
        if n_bounds > 1:
            raise NotImplementedError(
                'emit_processing: this control block has more than one '
                'exact-match table pipeline boundary in sequence; only a '
                'single boundary (0 or 1 exact-match tables gating further '
                'exact-match tables) is currently supported.'
            )

        def _stmts_contain_write(stmts, reg_name):
            for s in stmts:
                if isinstance(s, ExternCall) and s.name == f'{reg_name}.write':
                    return True
                if isinstance(s, IfStatement):
                    if _stmts_contain_write(s.then_body, reg_name) or \
                       _stmts_contain_write(s.else_body, reg_name):
                        return True
            return False

        def _reg_write_stage(reg_name):
            for i, stg in enumerate(stages):
                if _stmts_contain_write(stg, reg_name):
                    return i
            return 0

        reg_write_stage = {reg.name: _reg_write_stage(reg.name) for reg in registers}

        def _stmts_contain_call(stmts, call_name):
            for s in stmts:
                if isinstance(s, ExternCall) and s.name == call_name:
                    return True
                if isinstance(s, IfStatement):
                    if _stmts_contain_call(s.then_body, call_name) or \
                       _stmts_contain_call(s.else_body, call_name):
                        return True
            return False

        def _reg_read_stage(reg_name):
            for i, stg in enumerate(stages):
                if _stmts_contain_call(stg, f'{reg_name}.read'):
                    return i
            return 0

        # ── Stage-local renaming ─────────────────────────────────────────
        # Everything emitted by the existing (stage-unaware) statement
        # emitter is generated once per stage as plain text, then passed
        # through this rename so each stage gets its own working copy of
        # every header/metadata/local signal instead of two always_comb
        # blocks illegally driving the same variable.
        #
        # Two independent name pools, because they need opposite "which
        # stage stays unsuffixed" rules:
        #   Pool A (out_* pass-through copies, drop) must land on the
        #     real module output ports unsuffixed in the LAST stage —
        #     that's what's actually wired to the port list.
        #   Pool B (locals, meta_*_w, and raw hdr/std_meta field READS —
        #     `_map_expr`/`_map_cond` always map a `hdr.x.y` READ to the
        #     bare top-level input port name, so that name must stay
        #     unsuffixed only in stage 0, where it legitimately means
        #     "this cycle's live input"; every later stage needs its own
        #     forwarded copy, never the live input for a different packet)
        #     must stay unsuffixed only in stage 0.
        # With n_bounds in {0, 1} (enforced above) these two rules only
        # ever disagree on stage 0 vs stage 1, which is exactly the split
        # point, so there is no name collision between them.
        _pool_a = {'drop'}
        for hname, fname, _ in hdr_ports:
            _pool_a.add(f'out_{hname}_{fname}')
        for hname in hdr_valids:
            _pool_a.add(f'out_{hname}_valid')
        for fname in std_meta_outs:
            _pool_a.add(f'out_std_meta_{fname}')

        _pool_b = set(locals_.keys())
        for mf in meta_fields:
            _pool_b.add(f'meta_{mf.name}_w')
        for hname, fname, _ in hdr_ports:
            _pool_b.add(f'{hname}_{fname}')
        for hname in hdr_valids:
            _pool_b.add(f'{hname}_valid')
        for fname in std_meta_ins:
            _pool_b.add(f'std_meta_{fname}')

        def _mk_re(pool):
            names = sorted(pool, key=len, reverse=True)
            return re.compile(r'\b(' + '|'.join(re.escape(n) for n in names) + r')\b') if names else None

        _re_a, _re_b = _mk_re(_pool_a), _mk_re(_pool_b)

        def _stage_text(raw_text, stage_idx):
            text = raw_text
            suf_a = '' if stage_idx == n_bounds else f'__st{stage_idx}'
            if suf_a and _re_a is not None:
                text = _re_a.sub(lambda m: m.group(1) + suf_a, text)
            suf_b = '' if stage_idx == 0 else f'__st{stage_idx}'
            if suf_b and _re_b is not None:
                text = _re_b.sub(lambda m: m.group(1) + suf_b, text)
            return text

        # ── Local signal declarations ──────────────────────────────────
        for lname, lw in sorted(locals_.items()):
            f.write(f'  logic [{lw-1}:0] {lname};\n')
        if locals_:
            f.write('\n')

        # ── Metadata shadow locals ─────────────────────────────────────
        if meta_fields:
            f.write('  // Metadata shadow locals (writable copies of metadata inputs)\n')
            for mf in meta_fields:
                f.write(f'  logic [{mf.width-1}:0] meta_{mf.name}_w;\n')
            f.write('\n')

        # ── Pipeline-stage forwarding registers + per-stage working copies ──
        # Exact-match tables now report hit/action_id 1 cycle after their
        # lkp_* inputs, so header/metadata/local state has to be carried
        # forward through an explicit register at the boundary, and each
        # stage needs its own working copy of anything it writes (two
        # always_comb blocks can't both drive the same bare signal name —
        # see `_stage_text` above for which pool uses which stage).
        if n_bounds:
            f.write('  // Pipeline-stage forwarding registers (exact-match table boundary)\n')
            f.write('  logic valid_s1;\n')
            for hname in hdr_valids:
                f.write(f'  logic out_{hname}_valid_s1;\n')
                f.write(f'  logic {hname}_valid_s1;\n')
            for hname, fname, w in hdr_ports:
                f.write(f'  logic [{w-1}:0] out_{hname}_{fname}_s1;\n')
                f.write(f'  logic [{w-1}:0] {hname}_{fname}_s1;\n')
            for mf in meta_fields:
                f.write(f'  logic [{mf.width-1}:0] meta_{mf.name}_w_s1;\n')
            for lname, lw in sorted(locals_.items()):
                f.write(f'  logic [{lw-1}:0] {lname}_s1;\n')
            for fname in sorted(std_meta_outs):
                fw = std_meta_outs[fname]
                f.write(f'  logic [{fw-1}:0] out_std_meta_{fname}_s1;\n')
            for fname in sorted(std_meta_ins):
                fw = std_meta_ins[fname]
                f.write(f'  logic [{fw-1}:0] std_meta_{fname}_s1;\n')
            f.write('  logic drop_s1;\n')
            for reg_name, _ in boundary_forwards[0]:
                f.write(f'  logic {reg_name};\n')
            f.write('\n')

            f.write('  // Stage-0 working copies (pool A: out_*/drop kept separate from\n')
            f.write('  // the real output ports, which stage 1 alone drives)\n')
            for hname in hdr_valids:
                f.write(f'  logic out_{hname}_valid__st0;\n')
            for hname, fname, w in hdr_ports:
                f.write(f'  logic [{w-1}:0] out_{hname}_{fname}__st0;\n')
            for fname in sorted(std_meta_outs):
                fw = std_meta_outs[fname]
                f.write(f'  logic [{fw-1}:0] out_std_meta_{fname}__st0;\n')
            f.write('  logic drop__st0;\n\n')

            f.write('  // Stage-1 working copies (pool B: locals/meta shadow/raw hdr\n')
            f.write('  // and std_meta reads, seeded from the stage-0 forwarding regs)\n')
            for lname, lw in sorted(locals_.items()):
                f.write(f'  logic [{lw-1}:0] {lname}__st1;\n')
            for mf in meta_fields:
                f.write(f'  logic [{mf.width-1}:0] meta_{mf.name}_w__st1;\n')
            for hname in hdr_valids:
                f.write(f'  logic {hname}_valid__st1;\n')
            for hname, fname, w in hdr_ports:
                f.write(f'  logic [{w-1}:0] {hname}_{fname}__st1;\n')
            for fname in sorted(std_meta_ins):
                fw = std_meta_ins[fname]
                f.write(f'  logic [{fw-1}:0] std_meta_{fname}__st1;\n')
            f.write('\n')

        # ── Register memory arrays + write-staging signals ─────────────
        for reg in registers:
            addr_w = max(1, math.ceil(math.log2(reg.size))) if reg.size > 1 else 1
            f.write(f'  // {reg.name}: register<bit<{reg.data_width}>>({reg.size})\n')
            f.write(f'  logic [{reg.data_width-1}:0] {reg.name}_mem [0:{reg.size-1}];\n')
            f.write(f'  logic        {reg.name}_wr_en;\n')
            f.write(f'  logic [{addr_w-1}:0] {reg.name}_wr_addr;\n')
            f.write(f'  logic [{reg.data_width-1}:0] {reg.name}_wr_data;\n')
        if registers:
            f.write('\n  // Zero all register memories at simulation start\n')
            f.write('  initial begin\n')
            for reg in registers:
                f.write(f'    for (int _si = 0; _si < {reg.size}; _si++)\n')
                f.write(f'      {reg.name}_mem[_si] = {reg.data_width}\'b0;\n')
            f.write('  end\n\n')

            reg_reads = _collect_reg_reads(ctrl)
            if reg_reads:
                f.write('  // Register read wires (isolated via assign)\n')
                for reg_name, raw_out, raw_addr in reg_reads:
                    reg_obj = next((r for r in registers if r.name == reg_name), None)
                    dw = reg_obj.data_width if reg_obj else 1
                    read_stage = _reg_read_stage(reg_name)
                    addr_expr = _stage_text(_map_expr(raw_addr), read_stage)
                    f.write(f'  logic [{dw-1}:0] {reg_name}_rd_{raw_out};\n')
                    f.write(f'  assign {reg_name}_rd_{raw_out} = {reg_name}_mem[{addr_expr}];\n')
                f.write('\n')

        # ── Table lookup result wires ──────────────────────────────────
        if table_wires:
            f.write('  // Table lookup result wires\n')
            for tw in table_wires:
                tname = tw['table'].name
                f.write(f'  logic        {tw["hit_sig"]};\n')
                f.write(f'  logic [{tw["id_w"]-1}:0] {tw["aid_sig"]};\n')
                for pname, pw in tw['params']:
                    f.write(f'  logic [{pw-1}:0] {tname}_p_{pname};\n')
            f.write('\n')

        # ── Table module instantiations ────────────────────────────────
        if table_wires:
            f.write('  // Table module instantiations\n')
            for tw in table_wires:
                tbl   = tw['table']
                tname = tbl.name
                depth = tw['depth']
                mt    = tbl.keys[0].match_type if tbl.keys else 'exact'
                is_lpm     = (mt == 'lpm')
                is_ternary = (mt == 'ternary')

                f.write(f'  {tname}_table #(.DEPTH({depth})) u_{tname} (\n')
                f.write('    .clk    (clk),\n')
                f.write('    .rst_n  (rst_n),\n')
                for fname, sig, _ in tw['key_sigs']:
                    f.write(f'    .lkp_{fname}    ({sig}),\n')
                f.write(f'    .hit       ({tw["hit_sig"]}),\n')
                f.write(f'    .action_id ({tw["aid_sig"]}),\n')
                for pname, _ in tw['params']:
                    f.write(f'    .p_{pname}  ({tname}_p_{pname}),\n')
                f.write(f'    .cp_wr_en  ({tname}_cp_wr_en),\n')
                f.write(f'    .cp_wr_idx ({tname}_cp_wr_idx),\n')
                for fname, _, _ in tw['key_sigs']:
                    f.write(f'    .cp_wr_key_{fname} ({tname}_cp_wr_key_{fname}),\n')
                if is_lpm:
                    f.write(f'    .cp_wr_pfx_len ({tname}_cp_wr_pfx_len),\n')
                elif is_ternary:
                    for fname, _, _ in tw['key_sigs']:
                        f.write(f'    .cp_wr_mask_{fname} ({tname}_cp_wr_mask_{fname}),\n')
                f.write(f'    .cp_wr_action ({tname}_cp_wr_action)')
                if tw['params']:
                    f.write(',\n')
                    for i, (pname, _) in enumerate(tw['params']):
                        comma = ',' if i < len(tw['params']) - 1 else ''
                        f.write(f'    .cp_wr_p_{pname} ({tname}_cp_wr_p_{pname}){comma}\n')
                else:
                    f.write('\n')
                f.write('  );\n\n')

        # ── Table hit output assignments ───────────────────────────────
        if table_wires:
            f.write('  // Table hit outputs\n')
            for tw in table_wires:
                tname = tw['table'].name
                f.write(f'  assign {tname}_hit_out = {tw["hit_sig"]};\n')
            f.write('\n')

        # ── Combinational logic (staged) ────────────────────────────────
        # Stage 0 (n_bounds == 0: this is the *only* stage, and this
        # whole section is byte-identical to the original single-block
        # generator — apps with no exact-match table, e.g. qos, are
        # completely unaffected by pipelining).
        buf0 = io.StringIO()
        buf0.write('  always_comb begin\n')
        buf0.write('    drop = 0;\n')

        for lname, lw in sorted(locals_.items()):
            buf0.write(f'    {lname} = {lw}\'b0;\n')

        if meta_fields:
            buf0.write('\n    // Metadata shadow defaults (init from inputs)\n')
            for mf in meta_fields:
                buf0.write(f'    meta_{mf.name}_w = meta_{mf.name};\n')

        for reg in registers:
            if reg_write_stage[reg.name] == 0:
                buf0.write(f'    {reg.name}_wr_en   = 1\'b0;\n')
                buf0.write(f'    {reg.name}_wr_addr = \'0;\n')
                buf0.write(f'    {reg.name}_wr_data = \'0;\n')

        if std_meta_outs:
            buf0.write('\n    // Standard metadata defaults\n')
            for fname in sorted(std_meta_outs):
                fw = std_meta_outs[fname]
                buf0.write(f'    out_std_meta_{fname} = {fw}\'b0;\n')

        buf0.write('\n    // Header valid flag pass-through defaults\n')
        for hname in hdr_valids:
            buf0.write(f'    out_{hname}_valid = {hname}_valid;\n')

        buf0.write('\n    // Header field pass-through defaults\n')
        for hname, fname, _ in hdr_ports:
            buf0.write(f'    out_{hname}_{fname} = {hname}_{fname};\n')

        if stages[0]:
            buf0.write('\n    // apply block'
                        + (' (stage 0 — before the exact-match table split)' if n_bounds else '')
                        + '\n')
            _emit_stmts(buf0, stages[0], amap, '    ', cmap, ctrl.tables)

        buf0.write('  end\n')
        f.write(f'  // ---- Pipeline stage 0{" (combinational, feeds the exact-match table)" if n_bounds else ""} ----\n')
        f.write(_stage_text(buf0.getvalue(), 0))
        f.write('\n')

        if n_bounds:
            # ── Stage-0 -> stage-1 forwarding register ──────────────────
            f.write('  // Forward stage-0 state into stage-1 registers (1-cycle boundary —\n')
            f.write('  // matches the exact-match table\'s registered hit/action_id latency)\n')
            f.write('  always_ff @(posedge clk) begin\n')
            f.write('    if (!rst_n) begin\n')
            f.write('      valid_s1 <= 1\'b0;\n')
            f.write('    end else begin\n')
            f.write('      valid_s1 <= valid_in;\n')
            f.write('      drop_s1 <= drop__st0;\n')
            for lname, _ in sorted(locals_.items()):
                f.write(f'      {lname}_s1 <= {lname};\n')
            for mf in meta_fields:
                f.write(f'      meta_{mf.name}_w_s1 <= meta_{mf.name}_w;\n')
            for hname in hdr_valids:
                f.write(f'      out_{hname}_valid_s1 <= out_{hname}_valid__st0;\n')
                f.write(f'      {hname}_valid_s1 <= {hname}_valid;\n')
            for hname, fname, _ in hdr_ports:
                f.write(f'      out_{hname}_{fname}_s1 <= out_{hname}_{fname}__st0;\n')
                f.write(f'      {hname}_{fname}_s1 <= {hname}_{fname};\n')
            for fname in sorted(std_meta_outs):
                f.write(f'      out_std_meta_{fname}_s1 <= out_std_meta_{fname}__st0;\n')
            for fname in sorted(std_meta_ins):
                f.write(f'      std_meta_{fname}_s1 <= std_meta_{fname};\n')
            for reg_name, raw_cond in boundary_forwards[0]:
                f.write(f'      {reg_name} <= ({_map_cond(raw_cond, cmap)});\n')
            f.write('    end\n')
            f.write('  end\n\n')

            # ── Stage 1 ──────────────────────────────────────────────────
            buf1 = io.StringIO()
            buf1.write('  always_comb begin\n')
            buf1.write('    drop = drop_s1;\n')
            for lname, _ in sorted(locals_.items()):
                buf1.write(f'    {lname} = {lname}_s1;\n')
            for mf in meta_fields:
                buf1.write(f'    meta_{mf.name}_w = meta_{mf.name}_w_s1;\n')
            for hname in hdr_valids:
                buf1.write(f'    out_{hname}_valid = out_{hname}_valid_s1;\n')
                buf1.write(f'    {hname}_valid = {hname}_valid_s1;\n')
            for hname, fname, _ in hdr_ports:
                buf1.write(f'    out_{hname}_{fname} = out_{hname}_{fname}_s1;\n')
                buf1.write(f'    {hname}_{fname} = {hname}_{fname}_s1;\n')
            for fname in sorted(std_meta_outs):
                buf1.write(f'    out_std_meta_{fname} = out_std_meta_{fname}_s1;\n')
            for fname in sorted(std_meta_ins):
                buf1.write(f'    std_meta_{fname} = std_meta_{fname}_s1;\n')

            for reg in registers:
                if reg_write_stage[reg.name] == 1:
                    buf1.write(f'    {reg.name}_wr_en   = 1\'b0;\n')
                    buf1.write(f'    {reg.name}_wr_addr = \'0;\n')
                    buf1.write(f'    {reg.name}_wr_data = \'0;\n')

            if stages[1]:
                buf1.write('\n    // apply block (stage 1 — after the exact-match table split)\n')
                _emit_stmts(buf1, stages[1], amap, '    ', cmap, ctrl.tables)

            buf1.write('  end\n')
            f.write('  // ---- Pipeline stage 1 (1 cycle after stage 0; exact-match table result is valid here) ----\n')
            f.write(_stage_text(buf1.getvalue(), 1))
            f.write('\n')

        # ── Register write-back ────────────────────────────────────────
        if registers:
            f.write('  // Register write-back (initialized via initial block above)\n')
            for reg in registers:
                f.write(f'  always_ff @(posedge clk) begin\n')
                f.write(f'    if ({reg.name}_wr_en)\n')
                f.write(f'      {reg.name}_mem[{reg.name}_wr_addr] <= {reg.name}_wr_data;\n')
                f.write(f'  end\n')
            f.write('\n')

        # ── Pipeline register ──────────────────────────────────────────
        f.write('  always_ff @(posedge clk) begin\n')
        f.write('    if (!rst_n) valid_out <= 0;\n')
        if n_bounds:
            f.write('    else        valid_out <= valid_s1;\n')
        else:
            f.write('    else        valid_out <= valid_in;\n')
        f.write('  end\n\n')

        f.write('endmodule\n')
