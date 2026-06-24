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
        if hdr_name == 'standard_metadata':
            return f'standard_metadata.{fld_name}'
        if hdr_name.startswith('scalars'):   # control-local variable
            return fld_name
        return f'hdr.{hdr_name}.{fld_name}'

    if t == 'runtime_data':
        return rd[v]['name'] if v < len(rd) else f'param_{v}'

    if t == 'hexstr':
        return v

    if t == 'bool':
        return '1' if v else '0'

    if t == 'header':
        return f'hdr.{v}'

    if t == 'expression':
        return _expr(v, rd)

    # Operator node: {op, left, right}
    op    = node.get('op')
    left  = node.get('left')
    right = node.get('right')

    if op == 'valid':
        hname = _expr(right, rd).replace('hdr.', '')
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
    if op == 'd2b':            # bool-to-bit cast
        return _expr(right, rd)

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
        reg = params[1].get('value', '')
        return ExternCall(f'{reg}.read', [p(0), p(2)])

    if op == 'register_write':
        # register_write(reg_name, index, value)
        reg = params[0].get('value', '')
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
        hdr = params[0].get('value', '')
        return ExternCall(f'hdr.{hdr}.setValid', [])

    if op == 'remove_header':
        hdr = params[0].get('value', '')
        return ExternCall(f'hdr.{hdr}.setInvalid', [])

    if op == 'drop':
        return ExternCall('mark_to_drop', ['standard_metadata'])

    # Unsupported primitives (counter.count, clone, digest, …) become stubs
    # that emit an UNIMPLEMENTED comment in the generated RTL
    args = [p(i) for i in range(len(params))]
    return ExternCall(f'_bmv2_{op}', args)


# ============================================================
# Control-flow DAG reconstruction
# ============================================================

def _reconstruct_flow(node_name, tables_map, conds_map, visited=None):
    """Walk the bmv2 pipeline DAG (tables + conditionals) and return a list of
    IfStatement / TableApply IR nodes in execution order.

    The DAG is defined by:
      conditionals[i].true_next / false_next  → next node name
      tables[i].next_tables[action_name]      → next node name

    Limitation: branches that diverge and later reconverge (join points)
    are approximated — the common successor is handled when both branches
    independently reach it.  Full post-dominator analysis would be needed
    for the general case; for v1model sequential pipelines this is sufficient.
    """
    if visited is None:
        visited = set()
    if not node_name or node_name in visited:
        return []

    visited = visited | {node_name}   # immutable copy per branch
    stmts   = []

    if node_name in conds_map:
        cond     = conds_map[node_name]
        expr_str = _expr(cond.get('expression', {}))
        if_stmt  = IfStatement(expr_str)
        true_n   = cond.get('true_next')
        false_n  = cond.get('false_next')

        for s in _reconstruct_flow(true_n,  tables_map, conds_map, visited):
            if_stmt.add_then(s)
        for s in _reconstruct_flow(false_n, tables_map, conds_map, visited):
            if_stmt.add_else(s)
        stmts.append(if_stmt)

    elif node_name in tables_map:
        tbl = tables_map[node_name]
        ta  = TableApply(tbl['name'])
        stmts.append(ta)

        next_nodes = tbl.get('next_tables', {})
        successors = {v for v in next_nodes.values() if v is not None}

        if len(successors) == 1:
            # All actions converge to the same next node — emit sequentially
            stmts.extend(
                _reconstruct_flow(successors.pop(), tables_map, conds_map, visited)
            )
        elif len(successors) > 1:
            # Per-action divergence — use __HIT__ / __MISS__ as the split point
            hit_next  = next_nodes.get('__HIT__')
            miss_next = next_nodes.get('__MISS__')
            if hit_next or miss_next:
                ta.result_var = f'{tbl["name"]}_result'
                branch = IfStatement(f'{tbl["name"]}_result')
                for s in _reconstruct_flow(hit_next,  tables_map, conds_map, visited):
                    branch.add_then(s)
                for s in _reconstruct_flow(miss_next, tables_map, conds_map, visited):
                    branch.add_else(s)
                stmts.append(branch)

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

    # Collect scalars fields as a lookup for control-local variable widths
    scalar_widths = {}   # field_name → width
    for ht in bm.get('header_types', []):
        if ht['name'].startswith('scalars'):
            for fspec in ht.get('fields', []):
                fname, fwidth = fspec[0], fspec[1]
                if isinstance(fwidth, int) and fwidth > 0:
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
            ir.add_header_instance(HeaderInstance(
                inst_name   = hname,
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
                    state.add_extract(Extract(hdr_ref))

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
    reg_map = {}   # name → RegisterDecl
    for reg in bm.get('register_arrays', []):
        rd = RegisterDecl(reg['name'], reg['bitwidth'], reg['size'])
        reg_map[reg['name']] = rd

    # ── 5. Actions ────────────────────────────────────────────────────
    actions_by_name = {}   # action name → Action
    for act in bm.get('actions', []):
        a          = Action(act['name'])
        rd_list    = act.get('runtime_data', [])

        for rd in rd_list:
            a.add_param(ActionParam(
                rd['name'],
                f'bit<{rd["bitwidth"]}>',
                rd['bitwidth'],
            ))

        for prim in act.get('primitives', []):
            stmt = _prim(prim, rd_list, calcs)
            if stmt is not None:
                a.add_statement(stmt)

        actions_by_name[act['name']] = a
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
            t = Table(tbl['name'])

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
                t.add_action(aname)
                a = actions_by_name.get(aname)
                if a and aname not in action_added:
                    block.add_action(a)
                    action_added.add(aname)

            # Default action from static entry (if present in JSON)
            de = tbl.get('default_entry', {})
            if de:
                da_id   = de.get('action_id')
                actions = tbl.get('actions', [])
                action_ids = tbl.get('action_ids', [])
                if da_id is not None and da_id in action_ids:
                    idx = action_ids.index(da_id)
                    if idx < len(actions):
                        t.set_default(actions[idx])

            t.set_size(tbl.get('max_size', 1024))
            block.add_table(t)
            ir.add_table(t)
            tables_map[tbl['name']] = tbl

        # Conditionals index
        conds_map = {c['name']: c for c in pipe.get('conditionals', [])}

        # Reconstruct the sequential apply-block flow from the DAG
        init_node = pipe.get('init_table')
        for stmt in _reconstruct_flow(init_node, tables_map, conds_map):
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
        d.emit_list = list(deps[0].get('order', []))
        ir.pipeline.deparser = d

    return ir
