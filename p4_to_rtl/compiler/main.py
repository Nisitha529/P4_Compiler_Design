import os
import argparse
import shutil
import subprocess
import json
import tempfile

from ir import ActionParam, Assignment, ExternCall
from emit_parser import emit_parser
from emit_processing import emit_processing
from emit_deparser import emit_deparser
from emit_table import emit_tables
from emit_pkg import emit_pkg
from ingest_bmv2 import ingest_bmv2


# ============================================================
# p4c invocation  (Stage 1 front-end)
# ============================================================

def _run_p4c(p4_path, p4c_bin=None):
    """Invoke p4c to compile a P4 source file to bmv2 JSON.

    Binary resolution order:
      1. --p4c CLI argument  (p4c_bin parameter)
      2. P4C environment variable
      3. 'p4c'       on PATH
      4. 'p4c-bm2-ss' on PATH

    Raises RuntimeError with setup instructions if p4c is not found,
    or if compilation fails.  Returns the parsed bmv2 JSON dict.
    """
    binary = (p4c_bin
              or os.environ.get('P4C')
              or shutil.which('p4c')
              or shutil.which('p4c-bm2-ss'))

    if not binary:
        raise RuntimeError(
            "\n[ERROR] p4c not found.\n"
            "\nSetup options (choose one):\n"
            "  1. Add p4c to your PATH after installing it\n"
            "  2. Set the P4C environment variable:\n"
            "       export P4C=/path/to/p4c\n"
            "  3. Pass --p4c on the command line:\n"
            "       python main.py firewall --p4c /path/to/p4c\n"
            "\nInstallation: https://github.com/p4lang/p4c\n"
        )

    tmp_dir  = tempfile.mkdtemp(prefix='p4rtl_')
    tmp_json = os.path.join(tmp_dir, 'out.json')

    try:
        print(f"[INFO] p4c binary : {binary}")
        print(f"[INFO] P4 source  : {p4_path}")
        result = subprocess.run(
            [binary,
             '--target', 'bmv2',
             '--arch',   'v1model',
             '--std',    'p4-16',
             p4_path,
             '-o', tmp_json],
            capture_output=True, text=True, timeout=60
        )

        # p4c writes both warnings and errors to stderr
        if result.stderr.strip():
            tag = '[ERROR] p4c' if result.returncode != 0 else '[WARN]  p4c'
            for line in result.stderr.strip().splitlines():
                print(f"  {tag}: {line}")

        if result.returncode != 0:
            raise RuntimeError("p4c compilation failed — correct the P4 errors above")

        with open(tmp_json) as f:
            return json.load(f)

    except subprocess.TimeoutExpired:
        raise RuntimeError("p4c timed out after 60 s")
    except FileNotFoundError:
        raise RuntimeError(
            f"\n[ERROR] p4c binary not executable: {binary}\n"
            "Check the path and re-run."
        )
    finally:
        shutil.rmtree(tmp_dir, ignore_errors=True)


# ============================================================
# Debug printer
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
            param_strs = [
                f"{p.type_str} {p.name}" if isinstance(p, ActionParam) else str(p)
                for p in a.params
            ]
            print(f"  Action: {a.name}({', '.join(param_strs)})")
            for stmt in a.body:
                if isinstance(stmt, Assignment):
                    print(f"    {stmt.lhs} = {stmt.rhs}")
                elif isinstance(stmt, ExternCall):
                    print(f"    call {stmt.name}({', '.join(stmt.args)})")

    if ir.pipeline.deparser and ir.pipeline.deparser.emit_list:
        print("\n[DEBUG] ── Deparser Emits ───────────────────────")
        for e in ir.pipeline.deparser.emit_list:
            print(f"  emit(hdr.{e})")

    print("")


# ============================================================
# Main compiler driver
# ============================================================

def run_compiler(app_name, p4c_bin=None):

    base_dir = os.path.dirname(os.path.abspath(__file__))

    # Locate P4 source — case-insensitive match as fallback
    p4_path = os.path.join(base_dir, f"../p4src/apps/{app_name}.p4")
    if not os.path.exists(p4_path):
        apps_dir = os.path.join(base_dir, "../p4src/apps")
        if os.path.isdir(apps_dir):
            for fname in os.listdir(apps_dir):
                if fname.lower() == f"{app_name.lower()}.p4":
                    app_name = fname[:-3]
                    p4_path  = os.path.join(apps_dir, fname)
                    break

    if not os.path.exists(p4_path):
        raise FileNotFoundError(f"P4 source not found: {p4_path}")

    out_dir        = os.path.join(base_dir, f"../generated/{app_name}")
    out_parser     = os.path.join(out_dir, "parser_generated.sv")
    out_processing = os.path.join(out_dir, "processing_generated.sv")
    out_deparser   = os.path.join(out_dir, "deparser_generated.sv")

    os.makedirs(out_dir, exist_ok=True)

    # ── Stage 1: p4c → bmv2 JSON → hardware IR ───────────────────────
    bmv2_json = _run_p4c(p4_path, p4c_bin)

    print("[INFO] Building hardware IR from bmv2 JSON...")
    ir = ingest_bmv2(bmv2_json)

    debug_ir(ir)

    # ── Stage 5: RTL code generation ─────────────────────────────────
    out_pkg = os.path.join(out_dir, f"{app_name}_pkg.sv")
    print("[INFO] Generating SV package...")
    emit_pkg(ir, app_name, out_pkg)
    print(f"[SUCCESS] SV package       -> {out_pkg}")

    print("[INFO] Generating parser RTL...")
    emit_parser(ir, out_parser)
    print(f"[SUCCESS] Parser RTL       -> {out_parser}")

    if ir.controls:
        print("[INFO] Generating table RTL...")
        emit_tables(ir, out_dir)

        print("[INFO] Generating processing RTL...")
        emit_processing(ir, out_processing)
        print(f"[SUCCESS] Processing RTL   -> {out_processing}")
    else:
        print("[SKIP] No control blocks — skipping processing RTL")

    if ir.pipeline.deparser and ir.pipeline.deparser.emit_list:
        print("[INFO] Generating deparser RTL...")
        emit_deparser(ir, out_deparser)
        print(f"[SUCCESS] Deparser RTL     -> {out_deparser}")
    else:
        print("[SKIP] No deparser emit list — skipping deparser RTL")


# ============================================================
# CLI entry point
# ============================================================

def main():
    parser = argparse.ArgumentParser(
        description="P4-to-RTL Compiler  (p4c bmv2 front-end)",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "p4c setup (one of the following):\n"
            "  Install   : https://github.com/p4lang/p4c\n"
            "  By flag   : --p4c /usr/local/bin/p4c\n"
            "  By env    : export P4C=/usr/local/bin/p4c\n"
            "  By PATH   : ensure 'p4c' or 'p4c-bm2-ss' is in your PATH\n"
        ),
    )
    parser.add_argument(
        "app",
        help="P4 application name, without the .p4 extension",
    )
    parser.add_argument(
        "--p4c",
        metavar="PATH",
        default=None,
        help="Explicit path to the p4c binary (overrides P4C env var and PATH)",
    )
    args = parser.parse_args()
    run_compiler(args.app, p4c_bin=args.p4c)


if __name__ == "__main__":
    main()
