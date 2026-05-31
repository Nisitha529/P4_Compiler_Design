import re
from ir import Assignment, ExternCall, IfStatement, TableApply


# ============================================================
# Constant map from ir.consts
# ============================================================

def _build_const_map(ir):
    """Return {P4_name: SV_literal} for constant resolution in expressions."""
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


# ============================================================
# Signal name helpers
# ============================================================

def _sig(field_expr):
    """P4 field ref -> flat SV identifier (input side).

    hdr.eth.dmac   -> eth_dmac
    meta.echo_port -> meta_echo_port
    """
    s = field_expr.strip()
    s = re.sub(r'^hdr\.', '', s)
    s = re.sub(r'^meta\.', 'meta_', s)
    return s.replace('.', '_')


def _out(field_expr):
    return 'out_' + _sig(field_expr)


def _is_hdr(expr):
    return expr.strip().startswith('hdr.')


def _map_cond(cond, cmap=None):
    """Translate a P4 boolean condition to a SV expression."""
    # table.apply().field → table_field (result variable)
    cond = re.sub(r'(\w+)\.apply\(\)\.(\w+)', r'\1_\2', cond)
    cond = re.sub(r'hdr\.(\w+)\.isValid\(\)', r'\1_valid', cond)
    cond = re.sub(r'hdr\.(\w+)\.(\w+)', r'\1_\2', cond)
    cond = re.sub(r'\bmeta\.(\w+)', r'meta_\1', cond)
    if cmap:
        for name, sv_lit in cmap.items():
            cond = re.sub(r'\b' + re.escape(name) + r'\b', sv_lit, cond)
    return cond


def _map_expr(e, cmap=None):
    """Translate a P4 expression (RHS / assignment) to SV."""
    e = re.sub(r'hdr\.(\w+)\.(\w+)', r'\1_\2', e)
    e = re.sub(r'\bmeta\.(\w+)', r'meta_\1', e)
    if cmap:
        for name, sv_lit in cmap.items():
            e = re.sub(r'\b' + re.escape(name) + r'\b', sv_lit, e)
    return e


def _lhs_sig(lhs):
    """Assignment LHS -> SV signal name.

    hdr field  -> out_x_y
    temp/local -> as-is (cleaned)
    """
    lhs = lhs.strip()
    if _is_hdr(lhs):
        return _out(lhs)
    return re.sub(r'[.\[\]]', '_', lhs)


# ============================================================
# Action call inlining
# ============================================================

def _inline(action_name, amap, depth=0):
    """Recursively inline an action, returning flat list of Assignments."""
    if depth > 16 or action_name not in amap:
        return []
    result = []
    for stmt in amap[action_name].body:
        if isinstance(stmt, Assignment):
            result.append(stmt)
        elif isinstance(stmt, ExternCall):
            result.extend(_inline(stmt.name, amap, depth + 1))
    return result


# ============================================================
# Apply block emitter (recursive)
# ============================================================

def _emit_stmts(f, stmts, amap, ind, cmap, ctrl_tables):
    for stmt in stmts:

        if isinstance(stmt, IfStatement):
            # Emit table stub comment when condition contains table.apply().field
            for tm in re.finditer(r'(\w+)\.apply\(\)\.(\w+)', stmt.condition):
                tname = tm.group(1)
                tbl   = next((t for t in ctrl_tables if t.name == tname), None)
                f.write(f'{ind}// {tname}.apply()\n')
                if tbl:
                    for k in tbl.keys:
                        f.write(f'{ind}//   key: {_map_expr(k.field, cmap)} [{k.match_type}]\n')
                    f.write(f'{ind}//   default: {tbl.default_action}\n')
                f.write(f'{ind}// TODO: drive {tname}_{tm.group(2)} from lookup module\n')

            f.write(f'{ind}if ({_map_cond(stmt.condition, cmap)}) begin\n')
            _emit_stmts(f, stmt.then_body, amap, ind + '  ', cmap, ctrl_tables)
            f.write(f'{ind}end\n')
            if stmt.else_body:
                f.write(f'{ind}else begin\n')
                _emit_stmts(f, stmt.else_body, amap, ind + '  ', cmap, ctrl_tables)
                f.write(f'{ind}end\n')

        elif isinstance(stmt, TableApply):
            tbl = next((t for t in ctrl_tables if t.name == stmt.table_name), None)
            f.write(f'{ind}// {stmt.table_name}.apply()\n')
            if tbl:
                for k in tbl.keys:
                    f.write(f'{ind}//   key: {_map_expr(k.field, cmap)} [{k.match_type}]\n')
                f.write(f'{ind}//   default_action: {tbl.default_action}\n')
            if stmt.result_var:
                f.write(f'{ind}// TODO: drive {stmt.result_var} from CAM lookup module\n')

        elif isinstance(stmt, ExternCall):
            if stmt.name == 'mark_to_drop':
                f.write(f'{ind}drop = 1;\n')
            else:
                assignments = _inline(stmt.name, amap)
                if assignments:
                    f.write(f'{ind}// {stmt.name}()\n')
                    for asgn in assignments:
                        f.write(f'{ind}{_lhs_sig(asgn.lhs)} = {_map_expr(asgn.rhs, cmap)};\n')
                else:
                    f.write(f'{ind}// {stmt.name}()  [extern stub]\n')

        elif isinstance(stmt, Assignment):
            f.write(f'{ind}{_lhs_sig(stmt.lhs)} = {_map_expr(stmt.rhs, cmap)};\n')


# ============================================================
# Temp variable / local signal detection
# ============================================================

def _build_field_width_map(ir):
    wmap = {}
    for inst in ir.header_instances:
        if inst.is_stack:
            continue
        for fld in inst.header_type.fields:
            if fld.width:
                wmap[f'{inst.inst_name}_{fld.name}'] = fld.width
    if not wmap:
        for h in ir.headers:
            for fld in h.fields:
                if fld.width:
                    wmap[f'{h.name}_{fld.name}'] = fld.width
    return wmap


def _collect_local_signals(ctrl, fwmap):
    """Return {signal_name: width} for non-header LHS signals in actions + apply."""
    locals_ = {}

    def _scan_cond(cond):
        """Pick up table.apply().field result variables from if conditions."""
        for m in re.finditer(r'(\w+)\.apply\(\)\.(\w+)', cond):
            sig = f'{m.group(1)}_{m.group(2)}'
            if sig not in locals_:
                locals_[sig] = 1   # boolean

    def _scan_stmts(stmts):
        for s in stmts:
            if isinstance(s, Assignment) and not _is_hdr(s.lhs):
                n = _lhs_sig(s.lhs)
                if n not in locals_:
                    rhs_sig = _map_expr(s.rhs)
                    locals_[n] = fwmap.get(rhs_sig, 16)
            elif isinstance(s, IfStatement):
                _scan_cond(s.condition)
                _scan_stmts(s.then_body)
                _scan_stmts(s.else_body)
            elif isinstance(s, TableApply) and s.result_var:
                if s.result_var not in locals_:
                    locals_[s.result_var] = 1

    for a in ctrl.actions:
        for stmt in a.body:
            if isinstance(stmt, Assignment) and not _is_hdr(stmt.lhs):
                n = _lhs_sig(stmt.lhs)
                if n not in locals_:
                    rhs_sig = _map_expr(stmt.rhs)
                    locals_[n] = fwmap.get(rhs_sig, 32)

    _scan_stmts(ctrl.statements)
    return locals_


# ============================================================
# Control block resolution
# ============================================================

def _find_processing_ctrl(ir):
    """Return the primary match-action / ingress ControlBlock.

    Precedence:
      1. ir.pipeline.ingress  (set by build_ir from V1Switch/XilinxPipeline args)
      2. Heuristic: first control that is not parser/deparser/verify/compute
    """
    if ir.pipeline.ingress is not None:
        return ir.pipeline.ingress

    _SKIP_KEYWORDS = {
        'parser', 'deparser', 'verify', 'compute', 'checksum',
    }

    for name, block in ir.controls.items():
        name_lo = name.lower()
        if not any(k in name_lo for k in _SKIP_KEYWORDS):
            return block
    return None


# ============================================================
# Main emitter
# ============================================================

def emit_processing(ir, output_path):

    ctrl = _find_processing_ctrl(ir)
    if ctrl is None:
        raise RuntimeError(
            "emit_processing: no processing control block found in ir.controls."
        )

    cmap   = _build_const_map(ir)
    amap   = {a.name: a for a in ctrl.actions}
    fwmap  = _build_field_width_map(ir)
    locals_ = _collect_local_signals(ctrl, fwmap)

    # ── Port lists ────────────────────────────────────────────
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

    with open(output_path, 'w') as f:

        # ── Module declaration ────────────────────────────────
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

        f.write('\n  // Header field outputs (pass-through, optionally modified)\n')
        for hname, fname, w in hdr_ports:
            f.write(f'  output logic [{w-1}:0] out_{hname}_{fname},\n')

        # Expose hit / boolean result vars as outputs for testability
        for lname, lw in sorted(locals_.items()):
            if lw == 1:
                f.write(f'  output logic        {lname}_out,\n')

        f.write('\n  output logic        valid_out,\n')
        f.write('  output logic        drop\n')
        f.write(');\n\n')

        # ── Local signal declarations ─────────────────────────
        for lname, lw in sorted(locals_.items()):
            f.write(f'  logic [{lw-1}:0] {lname};\n')
        if locals_:
            f.write('\n')

        # ── Combinational logic ───────────────────────────────
        f.write('  always_comb begin\n')
        f.write('    drop = 0;\n')

        # Default: zero all local signals
        for lname, lw in sorted(locals_.items()):
            f.write(f'    {lname} = {lw}\'b0;\n')

        f.write('\n    // pass-through defaults\n')
        for hname, fname, _ in hdr_ports:
            f.write(f'    out_{hname}_{fname} = {hname}_{fname};\n')

        if ctrl.statements:
            f.write('\n    // apply block\n')
            _emit_stmts(f, ctrl.statements, amap, '    ', cmap, ctrl.tables)
        else:
            f.write('\n    // (no apply statements)\n')

        f.write('  end\n\n')

        # ── Drive boolean output ports ────────────────────────
        for lname, lw in sorted(locals_.items()):
            if lw == 1:
                f.write(f'  assign {lname}_out = {lname};\n')
        if any(lw == 1 for lw in locals_.values()):
            f.write('\n')

        # ── Pipeline register ─────────────────────────────────
        f.write('  always_ff @(posedge clk) begin\n')
        f.write('    if (!rst_n) valid_out <= 0;\n')
        f.write('    else        valid_out <= valid_in;\n')
        f.write('  end\n\n')

        f.write('endmodule\n')
