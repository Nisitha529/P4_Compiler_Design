"""ingest_bmv2.py — Stage 1 IR ingestion for the P4-to-RTL compiler.

Translates the bmv2 JSON produced by:
    p4c --target bmv2 --arch v1model --std p4-16 <app>.p4 -o out.json

into the compiler's hardware-oriented IR (ir.py objects).

bmv2 JSON → IR mapping
-----------------------
header_types[]              Header + HeaderField
headers[]  metadata=False   HeaderInstance
headers[]  metadata=True    MetadataField  (user-defined metadata struct)
headers[]  name='scalars'   LocalVar entries (control-local variables)
parsers[0].parse_states[]   ParserState, Extract, ParserSelect
register_arrays[]           RegisterDecl
actions[]  primitives[]     Action with Assignment / ExternCall body
pipelines[] tables +
            conditionals    ControlBlock, Table, IfStatement, TableApply
deparsers[0].order[]        Deparser.emit_list
"""

import re

from ir import (
    IR,
    ParserState, Extract, ParserSelect,
    Header, HeaderField, HeaderInstance, MetadataField, HeaderStack,
    Table, TableKey,
    Action, ActionParam, Assignment, ExternCall,
    IfStatement, TableApply, ControlBlock, LocalVar, RegisterDecl,
    Deparser,
)


# ============================================================
# Name sanitization
# ============================================================

def _sanitize(name):
    """Strip the control-block qualifier prefix from a p4c-qualified name.

    p4c fully qualifies names with the enclosing control block:
        'MyIngress.ipv4_lpm'    → 'ipv4_lpm'
        'MyIngress.bloom_filter_1' → 'bloom_filter_1'
        'NoAction'              → 'NoAction'   (no dot — unchanged)

    Dots are illegal in SystemVerilog identifiers, so stripping the prefix
    is required before any name is used as a signal, module, or file name.
    """
    return name.rsplit('.', 1)[-1]


def _sanitize_stack_idx(name):
    """bmv2 names each header-stack *element* 'name[idx]' (e.g.
    'srcRoutes[0]') both as its own entry in headers[] and inside any
    expression that references it. Brackets are illegal inside a
    SystemVerilog identifier, so this converts them to 'name_idx'
    everywhere -- header-instance registration, expression strings, and
    deparser emit-list entries alike.
    """
    return re.sub(r'\[(\d+)\]', r'_\1', name)


def _is_synthetic(tbl_json):
    """Return True if this is a p4c-generated 'action wrapper' table.

    p4c lifts inline action calls and code blocks into keyless tables named
    tbl_<something>.  They have no user-visible match keys and a single
    mandatory action.  They should be inlined rather than emitted as modules.
    """
    name = _sanitize(tbl_json.get('name', ''))
    return not tbl_json.get('key') and name.startswith('tbl_')


# ============================================================
# Expression translation  (bmv2 expression tree → string)
# ============================================================

def _expr(node, runtime_data=None):
    """Recursively convert a bmv2 expression node to a P4-compatible string.

    The resulting string is compatible with the existing _map_expr() /
    _map_cond() helpers in emit_processing.py — i.e. it uses the
    hdr.HEADER.FIELD  and  standard_metadata.FIELD  naming conventions.
    """
    rd = runtime_data or []
    if node is None:
        return '0'
    if not isinstance(node, dict):
        return str(node)

    t = node.get('type')
    v = node.get('value')

    if t == 'field':
        hdr_name, fld_name = v[0], v[1]
        if fld_name == '$valid$':           # bmv2 header-validity pseudo-field
            return f'hdr.{_sanitize_stack_idx(hdr_name)}.isValid()'
        if hdr_name == 'standard_metadata':
            return f'standard_metadata.{fld_name}'
        if hdr_name.startswith('scalars'):
            # Dotted: user struct field (e.g. 'metadata.ecmp_select') → 'meta.ecmp_select'
            # Plain:  compiler temporary (e.g. 'tmp_0')               → 'tmp_0'
            if '.' in fld_name:
                return 'meta.' + fld_name.rsplit('.', 1)[-1]
            return fld_name
        return f'hdr.{_sanitize_stack_idx(hdr_name)}.{fld_name}'

    if t in ('runtime_data', 'local'):
        # 'local' is bmv2's alternate encoding for an action-parameter
        # reference inside nested expressions (e.g. inside a jump_if_zero
        # condition) -- same index scheme as 'runtime_data'.
        return rd[v]['name'] if v < len(rd) else f'param_{v}'

    if t == 'hexstr':
        # bmv2 uses '0x...' C-style hex; convert to unsized SV hex 'h...
        if isinstance(v, str) and v.lower().startswith('0x'):
            hex_digits = v[2:]
            return f"'h{hex_digits.upper()}"
        return str(v)

    if t == 'bool':
        return '1' if v else '0'

    if t == 'header':
        return f'hdr.{_sanitize_stack_idx(v)}'

    if t == 'expression':
        return _expr(v, rd)

    # Operator node: {op, left, right}
    op    = node.get('op')
    left  = node.get('left')
    right = node.get('right')

    if op == 'valid':
        hname = _sanitize_stack_idx(_expr(right, rd).replace('hdr.', ''))
        return f'hdr.{hname}.isValid()'
    if op == 'not':
        return f'!({_expr(right, rd)})'
    if op in ('and', '&&'):
        return f'({_expr(left, rd)} && {_expr(right, rd)})'
    if op in ('or', '||'):
        return f'({_expr(left, rd)} || {_expr(right, rd)})'
    if op == '==':
        return f'({_expr(left, rd)} == {_expr(right, rd)})'
    if op == '!=':
        return f'({_expr(left, rd)} != {_expr(right, rd)})'
    if op in ('-', '+', '^', '&', '|', '<<', '>>', '<', '>', '<=', '>='):
        return f'({_expr(left, rd)} {op} {_expr(right, rd)})'
    if op == 'two_comp_mod':   # bmv2 modular (wrap-around) subtraction
        return f'({_expr(left, rd)} - {_expr(right, rd)})'
    if op in ('d2b', 'b2d'):   # bool<->bit cast: no-op in this string-based IR
        return _expr(right, rd)
    if op == 'usat_cast':
        # Saturating cast -- this is how p4c-bm2-ss lowers P4's `|-|`
        # (saturating subtract): `left` is the expression to saturate
        # (typically a plain `-`, which can underflow), `right` is the
        # target bit-width. Reconstruct the clamp-at-0 ternary explicitly
        # for the subtraction case; anything else falls back to an
        # unclamped pass-through rather than silently producing '0'.
        width_val = right.get('value') if isinstance(right, dict) else None
        try:
            width = int(width_val, 16) if isinstance(width_val, str) else int(width_val)
        except (TypeError, ValueError):
            width = None
        inner = left
        if isinstance(inner, dict) and inner.get('type') == 'expression':
            inner = inner.get('value')
        if isinstance(inner, dict) and inner.get('op') == '-' and width is not None:
            a_txt = _expr(inner.get('left'), rd)
            b_txt = _expr(inner.get('right'), rd)
            return f'(({a_txt} < {b_txt}) ? {width}\'d0 : ({a_txt} - {b_txt}))'
        return _expr(left, rd)

    return '0'


# ============================================================
# Action primitive translation  (bmv2 primitive → IR node)
# ============================================================

def _prim(primitive, runtime_data, calcs):
    """Translate one bmv2 action primitive to an Assignment or ExternCall.

    Returns None for unrecognised primitives (they are silently skipped).
    """
    op     = primitive['op']
    params = primitive.get('parameters', [])
    rd     = runtime_data

    def p(i):
        return _expr(params[i], rd) if i < len(params) else '0'

    if op == 'assign':
        return Assignment(p(0), p(1))

    if op == 'mark_to_drop':
        return ExternCall('mark_to_drop', ['standard_metadata'])

    if op == 'register_read':
        # register_read(dest, reg_name, index)
        reg = _sanitize(params[1].get('value', ''))
        return ExternCall(f'{reg}.read', [p(0), p(2)])

    if op == 'register_write':
        # register_write(reg_name, index, value)
        reg = _sanitize(params[0].get('value', ''))
        return ExternCall(f'{reg}.write', [p(1), p(2)])

    if op == 'modify_field_with_hash_based_offset':
        # hash(dest, algo, base, {fields}, max)
        dest     = p(0)
        calc_ref = params[2].get('value', '') if len(params) > 2 else ''
        max_val  = p(3) if len(params) > 3 else '4096'
        calc     = calcs.get(calc_ref, {})
        fields   = [_expr(inp, rd) for inp in calc.get('input', [])]
        return ExternCall('hash',
                          [dest, 'HashAlgorithm.crc16', '0',
                           '{' + ', '.join(fields) + '}', max_val])

    if op == 'add_header':
        hdr = _sanitize_stack_idx(params[0].get('value', ''))
        return ExternCall(f'hdr.{hdr}.setValid', [])

    if op == 'remove_header':
        hdr = _sanitize_stack_idx(params[0].get('value', ''))
        return ExternCall(f'hdr.{hdr}.setInvalid', [])

    if op == 'drop':
        return ExternCall('mark_to_drop', ['standard_metadata'])

    # Unsupported primitives (counter.count, clone, digest, …) become stubs
    # that emit an UNIMPLEMENTED comment in the generated RTL
    args = [p(i) for i in range(len(params))]
    return ExternCall(f'_bmv2_{op}', args)


def _jump_target(param):
    v = param['value']
    if isinstance(v, str):
        return int(v, 16) if v.lower().startswith('0x') else int(v)
    return int(v)


def _translate_primitives(primitives, rd, calcs, start=0, end=None):
    """Translate a slice of an action's primitive list to IR statements.

    A ternary or if/else *inside a single action body* is lowered by
    p4c-bm2-ss to `_jump_if_zero(cond, else_idx)` / `_jump(merge_idx)`
    branch primitives (index-based, like a tiny bytecode) -- a different,
    lower-level mechanism than the conditionals/tables DAG used for
    apply-block control flow (see `_reconstruct_flow`). Left untranslated,
    these primitives silently vanish (no IR node recognizes `_jump*` as an
    op), so whichever branch they guard just never executes. Reconstruct
    them into a normal IfStatement instead.
    """
    if end is None:
        end = len(primitives)
    stmts = []
    i = start
    while i < end:
        prim = primitives[i]
        op = prim['op']

        if op == '_jump_if_zero':
            cond_expr = _expr(prim['parameters'][0], rd)
            else_idx  = _jump_target(prim['parameters'][1])
            # A well-formed then-branch ends with an unconditional `_jump`
            # to the merge point (skipping the else-branch). If it's not
            # there, treat this as an if-with-no-else: the "else" target
            # is just where normal flow continues.
            merge_idx = else_idx
            then_last = else_idx - 1
            if start < then_last < end and primitives[then_last]['op'] == '_jump':
                merge_idx = _jump_target(primitives[then_last]['parameters'][0])
                then_stmts = _translate_primitives(primitives, rd, calcs, i + 1, then_last)
            else:
                then_stmts = _translate_primitives(primitives, rd, calcs, i + 1, else_idx)
            else_stmts = (_translate_primitives(primitives, rd, calcs, else_idx, merge_idx)
                          if merge_idx > else_idx else [])

            ifstmt = IfStatement(cond_expr)
            for s in then_stmts:
                ifstmt.add_then(s)
            for s in else_stmts:
                ifstmt.add_else(s)
            stmts.append(ifstmt)
            i = merge_idx
            continue

        if op == '_jump':
            # Unconditional jump with no enclosing `_jump_if_zero` in this
            # slice -- shouldn't normally occur, but follow it rather than
            # silently dropping whatever it was meant to skip.
            i = _jump_target(prim['parameters'][0])
            continue

        stmt = _prim(prim, rd, calcs)
        if stmt is not None:
            stmts.append(stmt)
        i += 1

    return stmts


# ============================================================
# Control-flow DAG reconstruction
# ============================================================

def _dag_successors(node_name, tables_map, conds_map):
    """Every node this DAG node can transition to (both branches of a
    conditional, or every distinct next_tables target of a table)."""
    if not node_name:
        return []
    if node_name in conds_map:
        c = conds_map[node_name]
        return [n for n in (c.get('true_next'), c.get('false_next')) if n]
    if node_name in tables_map:
        nxt = tables_map[node_name].get('next_tables', {})
        return list({v for v in nxt.values() if v is not None})
    return []


def _find_merge_node(start_a, start_b, tables_map, conds_map):
    """Find the nearest DAG node reachable from *both* start_a and
    start_b, i.e. where two branches of a conditional (or a table's
    hit/miss split) reconverge -- or None if they never do.

    Without this, a naive recursive walk of the DAG duplicates whichever
    node the branches share into *both* reconstructed branches instead of
    representing it as one statement that runs after the if/else
    regardless of which side was taken. That duplication is silently
    harmless for a purely-combinational, single-cycle emitter (one copy
    ends up on a now-unreachable path, e.g. gated by a condition that's
    already been ruled out) but breaks once pipeline staging treats each
    copy as a separate, independently-scheduled occurrence of the same
    table apply -- see basic_tunnel.p4's `if (ipv4 && !tunnel) {A} ; if
    (tunnel) {B}`, which p4c's bmv2 backend represents as a DAG where both
    branches of the first check lead to the second check.

    Level-synchronized BFS from both starts so the result is the nearest
    shared node, not just any shared node.
    """
    if start_a is None or start_b is None:
        return None
    if start_a == start_b:
        return start_a

    seen_a, seen_b = {start_a}, {start_b}
    frontier_a, frontier_b = [start_a], [start_b]

    while frontier_a or frontier_b:
        next_a = []
        for n in frontier_a:
            for s in _dag_successors(n, tables_map, conds_map):
                if s in seen_b:
                    return s
                if s not in seen_a:
                    seen_a.add(s)
                    next_a.append(s)
        next_b = []
        for n in frontier_b:
            for s in _dag_successors(n, tables_map, conds_map):
                if s in seen_a:
                    return s
                if s not in seen_b:
                    seen_b.add(s)
                    next_b.append(s)
        frontier_a, frontier_b = next_a, next_b

    return None


def _reconstruct_flow(node_name, tables_map, conds_map, actions_by_name=None,
                      visited=None):
    """Walk the bmv2 pipeline DAG (tables + conditionals) and return a list of
    IfStatement / TableApply / Assignment / ExternCall IR nodes in execution order.

    The DAG is defined by:
      conditionals[i].true_next / false_next  → next node name
      tables[i].next_tables[action_name]      → next node name

    Synthetic (keyless tbl_*) tables are inlined: their single mandatory action's
    body is inserted directly rather than emitting a TableApply.
    """
    if visited is None:
        visited = set()
    if not node_name or node_name in visited:
        return []

    visited = visited | {node_name}   # immutable copy per branch
    stmts   = []
    amap    = actions_by_name or {}

    if node_name in conds_map:
        cond     = conds_map[node_name]
        expr_str = _expr(cond.get('expression', {}))
        if_stmt  = IfStatement(expr_str)
        true_n   = cond.get('true_next')
        false_n  = cond.get('false_next')

        # If both branches eventually reconverge on the same node, stop
        # each branch's walk right there (branch_visited) instead of
        # letting both duplicate it, then emit it once after the if/else.
        merge = _find_merge_node(true_n, false_n, tables_map, conds_map)
        branch_visited = visited | ({merge} if merge else set())

        for s in _reconstruct_flow(true_n,  tables_map, conds_map, amap, branch_visited):
            if_stmt.add_then(s)
        for s in _reconstruct_flow(false_n, tables_map, conds_map, amap, branch_visited):
            if_stmt.add_else(s)
        if if_stmt.then_body or if_stmt.else_body:
            stmts.append(if_stmt)

        if merge:
            stmts.extend(_reconstruct_flow(merge, tables_map, conds_map, amap, visited))

    elif node_name in tables_map:
        tbl       = tables_map[node_name]
        san_name  = _sanitize(tbl['name'])
        synthetic = _is_synthetic(tbl)

        if not synthetic:
            ta = TableApply(san_name)
            stmts.append(ta)
        else:
            # Inline synthetic table's mandatory single action body
            raw_actions = tbl.get('actions', [])
            if raw_actions:
                act = amap.get(_sanitize(raw_actions[0]))
                if act:
                    stmts.extend(act.body)

        next_nodes = tbl.get('next_tables', {})
        successors = {v for v in next_nodes.values() if v is not None}

        if len(successors) == 1:
            # All actions converge to the same next node — emit sequentially
            stmts.extend(
                _reconstruct_flow(successors.pop(), tables_map, conds_map, amap, visited)
            )
        elif len(successors) > 1:
            # Per-action divergence — use __HIT__ / __MISS__ as the split point
            hit_next  = next_nodes.get('__HIT__')
            miss_next = next_nodes.get('__MISS__')
            if hit_next or miss_next:
                merge = _find_merge_node(hit_next, miss_next, tables_map, conds_map)
                branch_visited = visited | ({merge} if merge else set())

                if not synthetic:
                    ta.result_var = f'{san_name}_result'
                    branch = IfStatement(f'{san_name}_result')
                    for s in _reconstruct_flow(hit_next,  tables_map, conds_map, amap, branch_visited):
                        branch.add_then(s)
                    for s in _reconstruct_flow(miss_next, tables_map, conds_map, amap, branch_visited):
                        branch.add_else(s)
                    if branch.then_body or branch.else_body:
                        stmts.append(branch)
                else:
                    # synthetic table with divergent actions — follow successors
                    for succ in [hit_next, miss_next]:
                        if succ:
                            stmts.extend(
                                _reconstruct_flow(succ, tables_map, conds_map, amap, branch_visited)
                            )

                if merge:
                    stmts.extend(_reconstruct_flow(merge, tables_map, conds_map, amap, visited))

    return stmts


# ============================================================
# Main entry point
# ============================================================

def ingest_bmv2(bm):
    """Translate a parsed bmv2 JSON dict into the hardware-oriented IR.

    Parameters
    ----------
    bm : dict
        The result of json.load() on p4c's bmv2 JSON output file.

    Returns
    -------
    IR
        A fully populated IR object ready for the emit_*.py code generators.
    """
    ir = IR()

    # ── 1. Header types → Header + HeaderField objects ────────────────
    htype_map = {}   # type_name → Header
    for ht in bm.get('header_types', []):
        h = Header(ht['name'])
        for fspec in ht.get('fields', []):
            fname  = fspec[0]
            fwidth = fspec[1]
            if isinstance(fwidth, int) and fwidth > 0:
                h.add_field(HeaderField(fname, fwidth))
        ir.add_header(h)
        htype_map[ht['name']] = h

    # Collect scalars fields as a lookup for control-local variable widths.
    # p4c represents:
    #   - Compiler temporaries (tmp_0, _padding_0) as plain names → LocalVar
    #   - User metadata struct fields (metadata.ecmp_select) as dotted names
    #     → MetadataField (exposed as input port with writable shadow)
    scalar_widths = {}   # plain field_name → width
    for ht in bm.get('header_types', []):
        if ht['name'].startswith('scalars'):
            for fspec in ht.get('fields', []):
                fname, fwidth = fspec[0], fspec[1]
                if not (isinstance(fwidth, int) and fwidth > 0):
                    continue
                if '.' in fname:
                    # user struct field (e.g., 'metadata.ecmp_select')
                    field_name = fname.rsplit('.', 1)[-1]
                    ir.add_metadata_field(MetadataField(field_name, fwidth))
                else:
                    scalar_widths[fname] = fwidth

    # ── 2. Headers → instances, metadata fields, header stacks ───────
    for hdr in bm.get('headers', []):
        hname     = hdr['name']
        is_meta   = hdr.get('metadata', False)
        htype_obj = htype_map.get(hdr['header_type'])

        # Skip p4c synthetic internals
        if hname == 'standard_metadata' or hname.startswith('scalars'):
            continue
        if htype_obj is None:
            continue

        if is_meta:
            # User-defined metadata struct → individual MetadataField entries
            for fld in htype_obj.fields:
                if fld.width:
                    ir.add_metadata_field(MetadataField(fld.name, fld.width))
        else:
            # bmv2 lists each header-stack *element* here too, named
            # 'name[idx]' -- sanitize so it becomes a legal SV identifier.
            ir.add_header_instance(HeaderInstance(
                inst_name   = _sanitize_stack_idx(hname),
                type_name   = hdr['header_type'],
                header_type = htype_obj,
                is_stack    = False,
            ))

    # Header stacks (e.g. vlan_tag[2])
    for hs in bm.get('header_stacks', []):
        htype_obj = htype_map.get(hs['header_type'])
        if htype_obj:
            inst = HeaderInstance(
                inst_name   = hs['name'],
                type_name   = hs['header_type'],
                header_type = htype_obj,
                is_stack    = True,
                stack_size  = hs.get('size', 1),
            )
            ir.add_header_instance(inst)
            ir.add_header_stack(HeaderStack(hs['name'], hs.get('size', 1)))

    # ── 3. Parser states ──────────────────────────────────────────────
    parsers = bm.get('parsers', [])
    if parsers:
        parser_def = parsers[0]
        for ps in parser_def.get('parse_states', []):
            state = ParserState(ps['name'])

            for op in ps.get('parser_ops', []):
                if op['op'] == 'extract':
                    hdr_ref = op['parameters'][0].get('value', '')
                    # hdr_ref is the header instance name (string) in bmv2
                    state.add_extract(Extract(_sanitize_stack_idx(hdr_ref)))

            tkey        = ps.get('transition_key', [])
            transitions = ps.get('transitions', [])

            if tkey and transitions:
                # Build select from the first transition key field
                key_expr = _expr(tkey[0])
                sel = ParserSelect(key_expr)
                for tr in transitions:
                    dst = tr.get('next_state') or 'accept'
                    if tr['type'] == 'default':
                        sel.set_default(dst)
                    else:
                        sel.add_case(tr['value'], dst)
                state.set_select(sel)
            elif transitions:
                default = next(
                    (t for t in transitions if t['type'] == 'default'), None
                )
                if default and default.get('next_state'):
                    state.set_transition(default['next_state'])

            ir.add_parser_state(state)

        init = parser_def.get('init_state', '')
        if init:
            ir.set_start_state(init)
        elif ir.parser_states:
            ir.set_start_state(next(iter(ir.parser_states)))

    # ── 4. Register arrays and hash calculations ──────────────────────
    calcs   = {c['name']: c for c in bm.get('calculations', [])}
    reg_map = {}   # sanitized name → RegisterDecl
    for reg in bm.get('register_arrays', []):
        san = _sanitize(reg['name'])
        rd = RegisterDecl(san, reg['bitwidth'], reg['size'])
        reg_map[san] = rd

    # ── 5. Actions ────────────────────────────────────────────────────
    actions_by_name = {}   # sanitized action name → Action
    for act in bm.get('actions', []):
        san_name   = _sanitize(act['name'])
        a          = Action(san_name)
        rd_list    = act.get('runtime_data', [])

        for rd in rd_list:
            a.add_param(ActionParam(
                rd['name'],
                f'bit<{rd["bitwidth"]}>',
                rd['bitwidth'],
            ))

        for stmt in _translate_primitives(act.get('primitives', []), rd_list, calcs):
            a.add_statement(stmt)

        actions_by_name[san_name] = a
        ir.add_action(a)

    # ── 6. Pipelines → ControlBlock ──────────────────────────────────
    for pipe in bm.get('pipelines', []):
        block = ControlBlock(pipe['name'])

        # Attach register declarations and scalar (control-local) variables
        # to the ingress block where v1model declares them
        if pipe['name'] == 'ingress':
            for rd in reg_map.values():
                block.add_register(rd)
            for vname, vwidth in scalar_widths.items():
                block.add_local_var(LocalVar(vname, f'bit<{vwidth}>', vwidth))

        # Tables
        tables_map = {}   # node name → raw table dict (for DAG traversal)
        action_added = set()

        for tbl in pipe.get('tables', []):
            # Keep raw name in tables_map so DAG edges (also raw) can be resolved
            tables_map[tbl['name']] = tbl

            # Synthetic keyless wrapper tables are inlined by _reconstruct_flow
            if _is_synthetic(tbl):
                continue

            t = Table(_sanitize(tbl['name']))

            for k in tbl.get('key', []):
                target = k.get('target', [])   # [header_name, field_name]
                if len(target) < 2:
                    continue
                hdr_name, fld_name = target[0], target[1]
                if hdr_name == 'standard_metadata':
                    field_str = f'standard_metadata.{fld_name}'
                elif hdr_name.startswith('scalars'):
                    field_str = fld_name          # control-local variable
                else:
                    field_str = f'hdr.{hdr_name}.{fld_name}'
                t.add_key(TableKey(field_str, k['match_type']))

            for aname in tbl.get('actions', []):
                san_aname = _sanitize(aname)
                t.add_action(san_aname)
                a = actions_by_name.get(san_aname)
                if a and san_aname not in action_added:
                    block.add_action(a)
                    action_added.add(san_aname)

            # Default action from static entry (if present in JSON)
            de = tbl.get('default_entry', {})
            if de:
                da_id      = de.get('action_id')
                actions    = tbl.get('actions', [])
                action_ids = tbl.get('action_ids', [])
                if da_id is not None and da_id in action_ids:
                    idx = action_ids.index(da_id)
                    if idx < len(actions):
                        t.set_default(_sanitize(actions[idx]))

            t.set_size(tbl.get('max_size', 1024))
            block.add_table(t)
            ir.add_table(t)

        # Conditionals index
        conds_map = {c['name']: c for c in pipe.get('conditionals', [])}

        # Reconstruct the sequential apply-block flow from the DAG
        init_node = pipe.get('init_table')
        for stmt in _reconstruct_flow(init_node, tables_map, conds_map, actions_by_name):
            block.add_statement(stmt)

        ir.add_control(block)

        # Map to pipeline role
        if pipe['name'] == 'ingress':
            ir.set_pipeline_stage('ingress', block)
        elif pipe['name'] == 'egress':
            ir.set_pipeline_stage('egress', block)

    # ── 7. Deparser ───────────────────────────────────────────────────
    deps = bm.get('deparsers', [])
    if deps:
        d = Deparser()
        d.emit_list = [_sanitize_stack_idx(n) for n in deps[0].get('order', [])]
        ir.pipeline.deparser = d

    return ir
