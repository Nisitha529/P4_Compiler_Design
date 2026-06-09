import os
import argparse

from parse_p4 import parse_p4_file, resolve_width
from ir import (
    IR,
    ParserState, Extract, ParserSelect,
    Header, HeaderField, HeaderStack,
    HeaderInstance, MetadataField,
    Table, TableKey,
    Action, ActionParam, Assignment, ExternCall,
    IfStatement, TableApply, ControlBlock,
    LocalVar, RegisterDecl,
    Deparser,
)
from emit_parser import emit_parser
from emit_processing import emit_processing
from emit_deparser import emit_deparser
from emit_table import emit_tables
from emit_pkg import emit_pkg


# ============================================================
# Statement builder  (parsed dict -> IR node)
# ============================================================
def _build_stmt(d):
    if d is None:
        return None
    t = d.get('type')
    if t == 'table_apply':
        ta = TableApply(d['table'])
        ta.result_var = d.get('result_var')
        return ta
    if t == 'action_call':
        return ExternCall(d['action'], d.get('args', []))
    if t == 'method_call':
        label = f"{d['obj']}.{d['method']}"
        return ExternCall(label, d.get('args', []))
    if t == 'assign':
        return Assignment(d['lhs'], d['rhs'])
    if t == 'method_call':
        label = f"{d['obj']}.{d['method']}"
        return ExternCall(label, d.get('args', []))
    if t == 'if':
        s = IfStatement(d['condition'])
        for sub in d.get('then', []):
            n = _build_stmt(sub)
            if n is not None:
                s.add_then(n)
        for sub in d.get('else', []):
            n = _build_stmt(sub)
            if n is not None:
                s.add_else(n)
        return s
    return None


# ============================================================
# IR Builder
# ============================================================
def build_ir(parsed):
    ir = IR()

    # ------------------------------------------------
    # 1. Typedefs and constants
    # ------------------------------------------------
    ir.set_typedefs(parsed.get('typedefs', {}))
    ir.set_consts(parsed.get('consts', {}))

    typedefs = ir.typedefs

    # ------------------------------------------------
    # 2. Header type definitions
    # ------------------------------------------------
    for hdr in parsed.get('headers', []):
        h = Header(hdr['name'])
        for f in hdr['fields']:
            h.add_field(HeaderField(f['name'], f['width']))
        ir.add_header(h)   # also populates ir.header_type_map

    # ------------------------------------------------
    # 3. Header instances + metadata fields from structs
    # ------------------------------------------------
    for struct in parsed.get('structs', []):

        if struct['name'] == 'headers':
            for field in struct['fields']:
                htype = ir.header_type_map.get(field['type'])
                if htype:
                    inst = HeaderInstance(
                        inst_name  = field['name'],
                        type_name  = field['type'],
                        header_type= htype,
                        is_stack   = field.get('array_size') is not None,
                        stack_size = field.get('array_size') or 0,
                    )
                    ir.add_header_instance(inst)
                    if inst.is_stack:
                        ir.add_header_stack(HeaderStack(field['name'], inst.stack_size))

        elif struct['name'] == 'metadata':
            for field in struct['fields']:
                w = resolve_width(field['type'], typedefs)
                if w:
                    ir.add_metadata_field(MetadataField(field['name'], w))

    # ------------------------------------------------
    # 4. Parser states
    # ------------------------------------------------
    parser_info = parsed.get('parser', {})
    states      = parser_info.get('states', [])

    if not states:
        raise RuntimeError("No parser states found in P4 file")

    for s in states:
        state = ParserState(s['name'])

        for ext in s.get('extracts', []):
            state.add_extract(
                Extract(ext['header'], dynamic=ext['dynamic'], length_expr=ext['length_expr'])
            )

        if s.get('transition'):
            state.set_transition(s['transition'])

        if s.get('select'):
            sel_info = s['select']
            sel      = ParserSelect(sel_info['expr'])
            for val, dst in sel_info.get('cases', []):
                sel.add_case(val, dst)
            if sel_info.get('default'):
                sel.set_default(sel_info['default'])
            state.set_select(sel)

        ir.add_parser_state(state)

    ir.set_start_state(states[0]['name'])

    # ------------------------------------------------
    # 5. Control blocks  (tables, actions, apply)
    # ------------------------------------------------
    for ctrl_name, ctrl_raw in parsed.get('controls', {}).items():

        block = ControlBlock(ctrl_name)

        # -- local tables --
        for tbl in ctrl_raw.get('tables', []):
            t = Table(tbl['name'])
            for k in tbl.get('keys', []):
                t.add_key(TableKey(k['field'], k['match_type']))
            for a in tbl.get('actions', []):
                t.add_action(a)
            if tbl.get('default_action'):
                t.set_default(tbl['default_action'])
            if tbl.get('size'):
                t.set_size(tbl['size'])
            block.add_table(t)
            ir.add_table(t)

        # -- local actions --
        for act in ctrl_raw.get('actions', []):
            a = Action(act['name'])
            for p in act.get('params', []):
                if isinstance(p, dict):
                    type_str = p.get('type', '')
                    w = resolve_width(type_str, typedefs)
                    a.add_param(ActionParam(p['name'], type_str, w))
                else:
                    a.add_param(ActionParam(str(p), '', None))
            for stmt in act.get('body', []):
                t = stmt.get('type')
                if t == 'assign':
                    a.add_statement(Assignment(stmt['lhs'], stmt['rhs']))
                elif t == 'call':
                    a.add_statement(ExternCall(stmt['name'], stmt.get('args', [])))
                elif t == 'method_call':
                    label = f"{stmt['obj']}.{stmt['method']}"
                    a.add_statement(ExternCall(label, stmt.get('args', [])))
            block.add_action(a)
            ir.add_action(a)

        # -- local variable declarations --
        for lv in ctrl_raw.get('local_vars', []):
            block.add_local_var(LocalVar(lv['name'], lv['type'], lv['width']))

        # -- register extern declarations --
        for rv in ctrl_raw.get('registers', []):
            block.add_register(RegisterDecl(rv['name'], rv['data_width'], rv['size']))

        # -- apply block statements --
        for stmt_dict in ctrl_raw.get('apply', {}).get('stmts', []):
            node = _build_stmt(stmt_dict)
            if node is not None:
                block.add_statement(node)

        # -- deparser emit list --
        emits = ctrl_raw.get('apply', {}).get('emits', [])
        if emits:
            if ir.pipeline.deparser is None:
                ir.pipeline.deparser = Deparser()
            ir.pipeline.deparser.emit_list.extend(emits)

        ir.add_control(block)

    # ------------------------------------------------
    # 6. Map pipeline stages from arch args
    # ------------------------------------------------
    pipeline_info = parsed.get('pipeline')
    if pipeline_info:
        arch = pipeline_info['arch']
        args = [a.strip() for a in pipeline_info['args']]
        if arch == 'V1Switch' and len(args) >= 6:
            # V1Switch(parser, verify, ingress, egress, compute, deparser)
            ir.set_pipeline_stage('ingress', ir.controls.get(args[2]))
            ir.set_pipeline_stage('egress',  ir.controls.get(args[3]))
        elif arch == 'XilinxPipeline' and len(args) >= 3:
            # XilinxPipeline(parser, matchaction, deparser)
            ir.set_pipeline_stage('ingress', ir.controls.get(args[1]))

    return ir


# ============================================================
# Debug Printer
# ============================================================
def debug_ir(ir):

    print("\n[DEBUG] ── Headers ──────────────────────────────")
    for h in ir.headers:
        fields_str = ', '.join(
            f"{f.name}[{f.width}b]" if f.width else f.name
            for f in h.fields
        )
        print(f"  {h.name}: {fields_str}")

    if ir.header_instances:
        print("\n[DEBUG] ── Header Instances ─────────────────────")
        for inst in ir.header_instances:
            tag = f"[{inst.stack_size}]" if inst.is_stack else ""
            print(f"  {inst.inst_name}{tag} : {inst.type_name}")

    if ir.metadata_fields:
        print("\n[DEBUG] ── Metadata Fields ──────────────────────")
        for mf in ir.metadata_fields:
            print(f"  {mf.name}[{mf.width}b]")

    if ir.header_stacks:
        print("\n[DEBUG] ── Header Stacks ────────────────────────")
        for hs in ir.header_stacks:
            print(f"  {hs.name}[{hs.size}]")

    print("\n[DEBUG] ── Parser States ────────────────────────")
    for name, st in ir.parser_states.items():
        print(f"  State: {name}")
        print(f"    Extracts : {[e.header for e in st.extracts]}")
        print(f"    Next     : {st.next_state}")
        if st.select:
            print(f"    Select({st.select.expression}):")
            for val, dst in st.select.cases:
                print(f"      {val} -> {dst}")
            print(f"      default -> {st.select.default}")

    if ir.controls:
        print("\n[DEBUG] ── Control Blocks ───────────────────────")
        for cname, cb in ir.controls.items():
            print(f"  Control: {cname}")
            print(f"    Tables  : {[t.name for t in cb.tables]}")
            print(f"    Actions : {[a.name for a in cb.actions]}")
            print(f"    Stmts   : {len(cb.statements)} top-level statement(s)")

    if ir.tables:
        print("\n[DEBUG] ── Tables ───────────────────────────────")
        for t in ir.tables:
            print(f"  Table: {t.name}")
            for k in t.keys:
                print(f"    key: {k.field} [{k.match_type}]")
            print(f"    actions: {t.actions}")
            print(f"    default: {t.default_action}")

    if ir.actions:
        print("\n[DEBUG] ── Actions ──────────────────────────────")
        for a in ir.actions:
            param_strs = [f"{p.type_str} {p.name}" if isinstance(p, ActionParam) else str(p)
                          for p in a.params]
            print(f"  Action: {a.name}({', '.join(param_strs)})")
            for stmt in a.body:
                if isinstance(stmt, Assignment):
                    print(f"    {stmt.lhs} = {stmt.rhs}")
                elif isinstance(stmt, ExternCall):
                    print(f"    call {stmt.name}()")
                else:
                    print(f"    {stmt}")

    if ir.pipeline.deparser and ir.pipeline.deparser.emit_list:
        print("\n[DEBUG] ── Deparser Emits ───────────────────────")
        for e in ir.pipeline.deparser.emit_list:
            print(f"  emit(hdr.{e})")

    print("")


# ============================================================
# MAIN DRIVER
# ============================================================
def run_compiler(app_name):

    base_dir = os.path.dirname(__file__)

    # Try exact name first, then case-insensitive match for convenience
    p4_path = os.path.join(base_dir, f"../p4src/apps/{app_name}.p4")
    if not os.path.exists(p4_path):
        apps_dir = os.path.join(base_dir, "../p4src/apps")
        for fname in os.listdir(apps_dir):
            if fname.lower() == f"{app_name.lower()}.p4":
                app_name = fname[:-3]   # use the real on-disk name
                p4_path  = os.path.join(apps_dir, fname)
                break
    out_dir         = os.path.join(base_dir, f"../generated/{app_name}")
    out_parser      = os.path.join(out_dir, "parser_generated.sv")
    out_processing  = os.path.join(out_dir, "processing_generated.sv")
    out_deparser    = os.path.join(out_dir, "deparser_generated.sv")

    if not os.path.exists(p4_path):
        raise FileNotFoundError(f"P4 file not found: {p4_path}")

    os.makedirs(out_dir, exist_ok=True)

    print(f"[INFO] Parsing P4: {p4_path}")
    parsed = parse_p4_file(p4_path)

    if 'parser' not in parsed:
        raise RuntimeError("Parser block not found in P4")

    print("[INFO] Building IR...")
    ir = build_ir(parsed)

    debug_ir(ir)

    out_pkg = os.path.join(out_dir, f"{app_name}_pkg.sv")
    print("[INFO] Generating SV package...")
    emit_pkg(ir, app_name, out_pkg)
    print(f"[SUCCESS] SV package     -> {out_pkg}")

    print("[INFO] Generating parser RTL...")
    emit_parser(ir, out_parser)
    print(f"[SUCCESS] Parser RTL   -> {out_parser}")

    if ir.controls:
        print("[INFO] Generating table RTL...")
        emit_tables(ir, out_dir)

        print("[INFO] Generating processing RTL...")
        emit_processing(ir, out_processing)
        print(f"[SUCCESS] Processing RTL -> {out_processing}")
    else:
        print("[SKIP] No control blocks found — skipping processing RTL")

    if ir.pipeline.deparser and ir.pipeline.deparser.emit_list:
        print("[INFO] Generating deparser RTL...")
        emit_deparser(ir, out_deparser)
        print(f"[SUCCESS] Deparser RTL   -> {out_deparser}")
    else:
        print("[SKIP] No deparser emit list — skipping deparser RTL")


# ============================================================
# CLI ENTRY
# ============================================================
def main():
    parser = argparse.ArgumentParser(description="P4 to RTL Compiler")
    parser.add_argument("app", type=str, help="P4 application name (without .p4)")
    args = parser.parse_args()
    run_compiler(args.app)


# ============================================================
# ENTRY POINT
# ============================================================
if __name__ == "__main__":
    main()