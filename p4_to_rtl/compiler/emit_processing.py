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


def _std_meta_fname(expr):
    """Return the field name part of standard_metadata.fname."""
    m = re.match(r'^standard_metadata\.(\w+)$', expr.strip())
    return m.group(1) if m else None


def _lhs_sig(lhs):
    lhs = lhs.strip()
    if _is_hdr(lhs):
        return _out(lhs)
    fn = _std_meta_fname(lhs)
    if fn:
        return f'out_std_meta_{fn}'
    return re.sub(r'[.\[\]]', '_', lhs)


def _map_cond(cond, cmap=None):
    cond = re.sub(r'(\w+)\.apply\(\)\.(\w+)', r'\1_\2', cond)
    cond = re.sub(r'hdr\.(\w+)\.isValid\(\)', r'\1_valid', cond)
    cond = re.sub(r'hdr\.(\w+)\.(\w+)', r'\1_\2', cond)
    cond = re.sub(r'\bmeta\.(\w+)', r'meta_\1', cond)
    if cmap:
        for name, sv_lit in cmap.items():
            cond = re.sub(r'\b' + re.escape(name) + r'\b', sv_lit, cond)
    return cond


def _map_expr(e, cmap=None):
    e = re.sub(r'hdr\.(\w+)\.(\w+)', r'\1_\2', e)
    e = re.sub(r'\bmeta\.(\w+)', r'meta_\1', e)
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
    """standard_metadata.* fields assigned in any action body → output ports."""
    fields = {}
    for action in ctrl.actions:
        for stmt in action.body:
            if isinstance(stmt, Assignment):
                fn = _std_meta_fname(stmt.lhs)
                if fn:
                    fields[fn] = _STD_META_WIDTHS.get(fn, 32)
    return fields


def _collect_std_meta_inputs(tables):
    """standard_metadata.* fields used as table keys → input ports."""
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
    return _sig(key_field)


# ============================================================
# Local signal detection
# (skips hdr, std_meta, and known table-wire names)
# ============================================================

def _collect_local_signals(ctrl, fwmap, table_wire_names=None):
    locals_ = {}
    tbl_wires = table_wire_names or set()

    # Param-width lookup for action body inference
    def _param_widths(action):
        pw = {}
        for p in action.params:
            if isinstance(p, ActionParam):
                pw[p.name] = p.width or 32
        return pw

    def _scan_cond(cond):
        for m in re.finditer(r'(\w+)\.apply\(\)\.(\w+)', cond):
            sig = f'{m.group(1)}_{m.group(2)}'
            if sig in tbl_wires:
                continue
            if sig not in locals_:
                locals_[sig] = 1

    def _scan_stmts(stmts):
        for s in stmts:
            if isinstance(s, Assignment):
                if not _is_hdr(s.lhs) and not _is_std_meta(s.lhs):
                    n = _lhs_sig(s.lhs)
                    if n not in locals_ and n not in tbl_wires:
                        rhs_sig = _map_expr(s.rhs)
                        locals_[n] = fwmap.get(rhs_sig, 16)
            elif isinstance(s, IfStatement):
                _scan_cond(s.condition)
                _scan_stmts(s.then_body)
                _scan_stmts(s.else_body)
            elif isinstance(s, TableApply) and s.result_var:
                if s.result_var not in locals_ and s.result_var not in tbl_wires:
                    locals_[s.result_var] = 1

    # Scan action bodies — use param widths for better inference
    for a in ctrl.actions:
        pw = _param_widths(a)
        for stmt in a.body:
            if isinstance(stmt, Assignment):
                if not _is_hdr(stmt.lhs) and not _is_std_meta(stmt.lhs):
                    n = _lhs_sig(stmt.lhs)
                    if n not in locals_ and n not in tbl_wires:
                        rhs = stmt.rhs.strip()
                        if rhs in pw:
                            locals_[n] = pw[rhs]
                        else:
                            rhs_sig = _map_expr(rhs)
                            locals_[n] = fwmap.get(rhs_sig, 32)

    # Control-block local_vars override the inferred widths
    for lv in ctrl.local_vars:
        if lv.name not in tbl_wires:
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
    """Emit a (possibly param-substituted) action body."""
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
    """Apply param substitution then P4→SV expression mapping."""
    for pname, psig in pmap.items():
        text = re.sub(r'(?<!\.)\b' + re.escape(pname) + r'\b', psig, text)
    return _map_expr(text, cmap)


def _collect_reg_reads(ctrl):
    """Return list of (reg_name, raw_out_var, raw_addr_var) for all .read() calls."""
    reads = []
    def _scan(stmts):
        for s in stmts:
            if isinstance(s, ExternCall) and '.' in s.name:
                obj, method = s.name.split('.', 1)
                if method == 'read' and len(s.args) >= 2:
                    reads.append((obj, s.args[0].strip(), s.args[1].strip()))
            elif isinstance(s, IfStatement):
                _scan(s.then_body)
                _scan(s.else_body)
    _scan(ctrl.statements)
    for a in ctrl.actions:
        for s in a.body:
            if isinstance(s, ExternCall) and '.' in s.name:
                obj, method = s.name.split('.', 1)
                if method == 'read' and len(s.args) >= 2:
                    reads.append((obj, s.args[0].strip(), s.args[1].strip()))
    return reads


def _emit_extern_stub(f, stmt, ind, pmap, cmap):
    """Emit RTL for extern calls: mark_to_drop, hash(), register.read/write."""
    name = stmt.name

    if name == 'mark_to_drop':
        f.write(f'{ind}drop = 1;\n')
        return

    # hash(out_var, algorithm, base, {fields}, max) → XOR-based behavioral stub
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
            xor_expr = ' ^ '.join(fields) if fields else '32\'d0'
            f.write(f'{ind}// hash() stub — XOR-based behavioral approximation\n')
            f.write(f'{ind}{out_var} = ({xor_expr}) & {bits}\'h{(2**bits - 1):X};\n')
        else:
            f.write(f'{ind}// hash() [incomplete args — stub]\n')
        return

    if '.' in name:
        obj, method = name.split('.', 1)
        if method == 'read' and len(stmt.args) >= 2:
            # Use pre-generated assign wire to break always_comb→mem sensitivity
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
        f.write(f'{ind}// {name}({", ".join(stmt.args)})  [extern stub]\n')
        return

    f.write(f'{ind}// {name}({", ".join(stmt.args)})  [extern stub]\n')


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

    # Execute default action on miss (when default is not NoAction)
    if default_name not in ('NoAction',):
        action = amap.get(default_name)
        f.write(f' else begin // {default_name} on miss\n')
        if action:
            _emit_inlined_body(f, action.body, {}, cmap, ind + '  ')
        f.write(f'{ind}end\n')
    else:
        f.write('\n')


# ============================================================
# Apply-block statement emitter
# ============================================================

def _emit_stmts(f, stmts, amap, ind, cmap, ctrl_tables):
    for stmt in stmts:

        if isinstance(stmt, IfStatement):
            # Detect any table.apply().field patterns in the condition
            tbl_applies = list(re.finditer(r'(\w+)\.apply\(\)\.(\w+)', stmt.condition))

            f.write(f'{ind}if ({_map_cond(stmt.condition, cmap)}) begin\n')

            # For each table referenced in the condition, emit its case statement
            # immediately inside the if block (the table is already looked up
            # combinatorially by the submodule; this only runs the action body)
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
                # Action call with arguments from apply block
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
                    f.write(f'{ind}// {stmt.name}()  [extern stub]\n')
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
        table_wires.append({
            'table': tbl, 'hit_sig': f'{tbl.name}_hit',
            'aid_sig': f'{tbl.name}_act_id', 'id_w': id_w,
            'params': params, 'key_sigs': key_sigs,
        })

    # Names of all table-result wires (to exclude from locals)
    tbl_wire_names = set()
    for tw in table_wires:
        tbl_wire_names.add(tw['hit_sig'])
        tbl_wire_names.add(tw['aid_sig'])
        for pname, _ in tw['params']:
            tbl_wire_names.add(f"{tw['table'].name}_p_{pname}")

    locals_ = _collect_local_signals(ctrl, fwmap, tbl_wire_names)

    # Register names (for memory array generation)
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
            f.write('\n  // Metadata\n')
            for mf in meta_fields:
                f.write(f'  input  logic [{mf.width-1}:0] meta_{mf.name},\n')

        if std_meta_ins:
            f.write('\n  // Standard metadata inputs (table key sources)\n')
            for fname in sorted(std_meta_ins):
                fw = std_meta_ins[fname]
                f.write(f'  input  logic [{fw-1}:0] std_meta_{fname},\n')

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
                depth = 1024
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

        f.write('\n  output logic        valid_out,\n')
        f.write('  output logic        drop\n')
        f.write(');\n\n')

        # ── Local signal declarations ──────────────────────────────────
        for lname, lw in sorted(locals_.items()):
            f.write(f'  logic [{lw-1}:0] {lname};\n')
        if locals_:
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
            # Use initial blocks to zero memories — avoids NBA cascade during reset
            f.write('\n  // Zero all register memories at simulation start\n')
            f.write('  initial begin\n')
            for reg in registers:
                f.write(f'    for (int _si = 0; _si < {reg.size}; _si++)\n')
                f.write(f'      {reg.name}_mem[_si] = {reg.data_width}\'b0;\n')
            f.write('  end\n\n')

            # Assign wires for reads — break always_comb sensitivity to the mem array.
            # Convergent loop: always_comb→addr→assign→val→always_comb settles in 2 steps.
            reg_reads = _collect_reg_reads(ctrl)
            if reg_reads:
                f.write('  // Register read wires (isolated via assign)\n')
                for reg_name, raw_out, raw_addr in reg_reads:
                    # find data width for this register
                    reg_obj = next((r for r in registers if r.name == reg_name), None)
                    dw = reg_obj.data_width if reg_obj else 1
                    addr_expr = _map_expr(raw_addr)
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
                depth = 1024
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
                # CP write port connections
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

        # ── Combinational logic ────────────────────────────────────────
        f.write('  always_comb begin\n')
        f.write('    drop = 0;\n')

        # Default local signals
        for lname, lw in sorted(locals_.items()):
            f.write(f'    {lname} = {lw}\'b0;\n')

        # Default write-staging for registers
        for reg in registers:
            f.write(f'    {reg.name}_wr_en   = 1\'b0;\n')
            f.write(f'    {reg.name}_wr_addr = \'0;\n')
            f.write(f'    {reg.name}_wr_data = \'0;\n')

        if std_meta_outs:
            f.write('\n    // Standard metadata defaults\n')
            for fname in sorted(std_meta_outs):
                fw = std_meta_outs[fname]
                f.write(f'    out_std_meta_{fname} = {fw}\'b0;\n')

        f.write('\n    // pass-through defaults\n')
        for hname, fname, _ in hdr_ports:
            f.write(f'    out_{hname}_{fname} = {hname}_{fname};\n')

        if ctrl.statements:
            f.write('\n    // apply block\n')
            _emit_stmts(f, ctrl.statements, amap, '    ', cmap, ctrl.tables)

        f.write('  end\n\n')

        # ── Register write-back (synchronous, no rst_n clear — initial block handles init)
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
        f.write('    else        valid_out <= valid_in;\n')
        f.write('  end\n\n')

        f.write('endmodule\n')
