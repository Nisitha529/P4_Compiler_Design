import os
import argparse
import glob
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
from ingest_p4ir import ingest_p4ir
from emit_top import emit_top, DEFAULT_AXI_DATA_W, MAX_AXI_DATA_W
from timing_model import budget_levels as _budget_levels, DEVICE_FACTOR


# ============================================================
# Architecture detection from P4 source text
# ============================================================

def _detect_p4_arch(p4_path):
    """Return 'xsa', 'v1model', or 'unknown' based on package instantiation."""
    try:
        with open(p4_path) as f:
            src = f.read()
    except OSError:
        return 'unknown'
    if 'XilinxPipeline' in src:
        return 'xsa'
    if 'V1Switch' in src:
        return 'v1model'
    return 'unknown'


# ============================================================
# p4test front-end  (p4fpga-style: front-end only, clean MidEnd IR)
# ============================================================

def _run_p4c_frontend(p4_path, p4test_bin=None):
    """
    Invoke p4test --dump to produce a clean MidEnd P4 IR file.

    Binary resolution order:
      1. p4test_bin parameter  (--p4test CLI flag)
      2. P4TEST environment variable
      3. ~/p4c/build/backends/p4test/p4test  (standard build location)
      4. 'p4test' on PATH

    Returns the MidEnd P4 IR as a string.
    """
    home = os.path.expanduser('~')
    binary = (
        p4test_bin
        or os.environ.get('P4TEST')
        or (lambda p: p if os.path.isfile(p) else None)(
            os.path.join(home, 'p4c/build/backends/p4test/p4test'))
        or shutil.which('p4test')
    )

    if not binary:
        raise RuntimeError(
            "\n[ERROR] p4test not found.\n"
            "\nSetup options (choose one):\n"
            "  1. Build p4c: cd ~/p4c/build && make p4test\n"
            "  2. Set the P4TEST environment variable:\n"
            "       export P4TEST=/path/to/p4test\n"
            "  3. Pass --p4test on the command line:\n"
            "       python main.py fiveTuple --p4test /path/to/p4test\n"
        )

    # p4c include directories — try common locations from the binary path upward
    binary_dir = os.path.dirname(os.path.abspath(binary))
    p4c_includes = None
    for candidate in [
        os.path.join(binary_dir, 'p4include'),              # backends/p4test/p4include
        os.path.join(binary_dir, '../p4include'),           # build/p4include
        os.path.join(binary_dir, '../../p4include'),        # two levels up
        os.path.join(binary_dir, '../../../p4include'),
    ]:
        candidate = os.path.normpath(candidate)
        if os.path.isdir(candidate) and os.path.isfile(os.path.join(candidate, 'core.p4')):
            p4c_includes = candidate
            break

    arch_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), '../p4src/arch')
    arch_dir = os.path.normpath(arch_dir)

    dump_dir = tempfile.mkdtemp(prefix='p4ir_')

    try:
        cmd = [
            binary,
            '--std', 'p4-16',
            '--dump', dump_dir,
            '--top4', 'MidEndLast',
        ]
        if p4c_includes:
            cmd += ['-I', p4c_includes]
        if os.path.isdir(arch_dir):
            cmd += ['-I', arch_dir]
        cmd.append(p4_path)

        print(f"[INFO] p4test binary  : {binary}")
        print(f"[INFO] P4 source      : {p4_path}")
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)

        if result.stderr.strip():
            tag = '[ERROR] p4test' if result.returncode != 0 else '[WARN]  p4test'
            for line in result.stderr.strip().splitlines():
                print(f"  {tag}: {line}")

        if result.returncode != 0:
            raise RuntimeError("p4test compilation failed — correct the P4 errors above")

        # Find the last MidEndLast dump file
        pattern = os.path.join(dump_dir, '*MidEndLast*.p4')
        candidates = sorted(glob.glob(pattern))
        if not candidates:
            # Fall back to any MidEnd file
            candidates = sorted(glob.glob(os.path.join(dump_dir, '*MidEnd*.p4')))
        if not candidates:
            raise RuntimeError(
                f"p4test ran successfully but no MidEnd dump found in {dump_dir}.\n"
                "Try: p4test --dump /tmp/p4dump --top4 MidEndLast your.p4"
            )

        midend_path = candidates[-1]
        print(f"[INFO] MidEnd IR file : {midend_path}")
        with open(midend_path) as f:
            return f.read()

    except subprocess.TimeoutExpired:
        raise RuntimeError("p4test timed out after 60 s")
    except FileNotFoundError:
        raise RuntimeError(f"\n[ERROR] p4test binary not executable: {binary}\n")
    finally:
        shutil.rmtree(dump_dir, ignore_errors=True)


# ============================================================
# p4c bmv2 front-end  (legacy v1model path)
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

def run_compiler(app_name, p4c_bin=None, p4test_bin=None, frontend=None, budget_levels=None, ways=1,
                  axi_data_width=DEFAULT_AXI_DATA_W):
    """
    frontend: 'bmv2' | 'p4test' | None (auto-detect from P4 source)
    budget_levels: None (default) = today's behavior exactly, no budget-splitting.
        Otherwise, an int logic-level budget per pipeline stage (see timing_model.py).
    ways: 1 (default) = today's behavior exactly, direct-mapped exact-match tables.
        Otherwise, d-way set-associative exact-match tables (see emit_table.py's
        _emit_exact_match_table_assoc).
    axi_data_width: AXI4-Stream TDATA width in bits for the p4test/XSA frontend's
        top-level (default 256; ignored for the bmv2 frontend, which has no
        byte-stream I/O). See emit_top.py's MAX_AXI_DATA_W for the ceiling's
        rationale.
    """

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
    out_top        = os.path.join(out_dir, f"{app_name}_top.sv")

    os.makedirs(out_dir, exist_ok=True)

    # ── Stage 1: choose front-end based on architecture ───────────────
    if frontend is None:
        arch = _detect_p4_arch(p4_path)
        frontend = 'p4test' if arch == 'xsa' else 'bmv2'
        print(f"[INFO] Detected architecture : {arch}  → using {frontend} frontend")

    # CP query/delete (see emit_table.py's enable_query) is only reachable
    # through emit_top.py's AXI4-Lite control plane, which only exists for
    # the p4test/XSA frontend -- the bmv2 frontend has no bus wrapper at
    # all, so its output must stay byte-identical regardless of table shape.
    enable_query = (frontend == 'p4test')

    if frontend == 'p4test':
        print("[INFO] Running p4test MidEnd front-end...")
        midend_text = _run_p4c_frontend(p4_path, p4test_bin)
        print("[INFO] Building hardware IR from MidEnd P4 IR...")
        ir = ingest_p4ir(midend_text)
    else:
        print("[INFO] Running p4c-bm2-ss front-end...")
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
        emit_tables(ir, out_dir, budget_levels=budget_levels, ways=ways, enable_query=enable_query)

        print("[INFO] Generating processing RTL...")
        emit_processing(ir, out_processing, budget_levels=budget_levels, ways=ways, enable_query=enable_query)
        print(f"[SUCCESS] Processing RTL   -> {out_processing}")
    else:
        print("[SKIP] No control blocks — skipping processing RTL")

    # Egress control block, linear (one-packet-in-one-packet-out) case only —
    # e.g. ecn.p4's ECN marking, mri.p4's swtrace hop-count table. Does NOT
    # cover multicast-style replication (egress running once per replica),
    # which needs a fan-out/queueing model this compiler doesn't have.
    eg = ir.pipeline.egress
    if eg is not None and (eg.tables or eg.statements):
        out_egress_processing = os.path.join(out_dir, "egress_processing_generated.sv")
        print("[INFO] Generating egress table RTL...")
        emit_tables(ir, out_dir, stage='egress', budget_levels=budget_levels, ways=ways, enable_query=enable_query)

        print("[INFO] Generating egress processing RTL...")
        emit_processing(ir, out_egress_processing, stage='egress', budget_levels=budget_levels, ways=ways, enable_query=enable_query)
        print(f"[SUCCESS] Egress processing RTL -> {out_egress_processing}")

    if ir.pipeline.deparser and ir.pipeline.deparser.emit_list:
        print("[INFO] Generating deparser RTL...")
        emit_deparser(ir, out_deparser)
        print(f"[SUCCESS] Deparser RTL     -> {out_deparser}")
    else:
        print("[SKIP] No deparser emit list — skipping deparser RTL")

    if frontend == 'p4test':
        print("[INFO] Generating top-level RTL (AXI4-Stream + AXI4-Lite)...")
        emit_top(ir, app_name, out_top, axi_data_width=axi_data_width)
        print(f"[SUCCESS] Top-level RTL    -> {out_top}")


# ============================================================
# CLI entry point
# ============================================================

def main():
    parser = argparse.ArgumentParser(
        description="P4-to-RTL Compiler  (p4fpga-style: p4test MidEnd front-end)",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Frontend selection:\n"
            "  XSA apps   (XilinxPipeline) → p4test MidEnd IR  [auto]\n"
            "  v1model apps (V1Switch)     → p4c-bm2-ss JSON   [auto]\n"
            "\np4test setup (for XSA / p4test frontend):\n"
            "  Build p4c : cd ~/p4c/build && make p4test\n"
            "  By flag   : --p4test ~/p4c/build/backends/p4test/p4test\n"
            "  By env    : export P4TEST=/path/to/p4test\n"
            "\np4c setup (for v1model / bmv2 frontend):\n"
            "  By flag   : --p4c /usr/local/bin/p4c\n"
            "  By env    : export P4C=/usr/local/bin/p4c\n"
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
        help="Path to p4c-bm2-ss binary (v1model frontend)",
    )
    parser.add_argument(
        "--p4test",
        metavar="PATH",
        default=None,
        help="Path to p4test binary (XSA / MidEnd frontend)",
    )
    parser.add_argument(
        "--frontend",
        choices=['p4test', 'bmv2'],
        default=None,
        help="Force a specific frontend (default: auto-detect from P4 source)",
    )
    parser.add_argument(
        "--target-freq-mhz",
        metavar="FLOAT",
        type=float,
        default=None,
        help=(
            "Opt-in pipeline delay budget, in MHz. Default: unset, meaning no "
            "budget-splitting -- identical output to not passing this flag at all. "
            "When set, stages are split to fit a logic-level budget derived from a "
            "single real Artix-7 calibration point (see timing_model.py). For "
            "--device other than artix7, the result is an UNVERIFIED ESTIMATE: this "
            "machine has no Synthesis license for UltraScale+/Versal."
        ),
    )
    parser.add_argument(
        "--device",
        choices=sorted(DEVICE_FACTOR),
        default='artix7',
        help="Target device family for --target-freq-mhz budget scaling (default: artix7)",
    )
    parser.add_argument(
        "--exact-match-ways",
        metavar="N",
        type=int,
        default=1,
        help=(
            "Opt-in d-way set-associative storage for exact-match tables. "
            "Default: 1 (direct-mapped, identical output to not passing this flag at "
            "all). When N>1, a control-plane write whose key hashes to an "
            "already-occupied bucket is only a genuine collision (see the table's "
            "{table}_wr_collision output) once all N ways at that bucket hold "
            "different keys. LPM/ternary/keyless tables ignore this flag."
        ),
    )
    parser.add_argument(
        "--axi-data-width",
        metavar="BITS",
        type=int,
        default=DEFAULT_AXI_DATA_W,
        help=(
            f"AXI4-Stream TDATA width, in bits, for the p4test/XSA frontend's "
            f"top-level (default: {DEFAULT_AXI_DATA_W}; ignored for the bmv2 "
            f"frontend, which has no byte-stream I/O). Must be a power of 2, "
            f">=8, and <={MAX_AXI_DATA_W}. Field extraction/write-back index the "
            f"packet buffer by byte position, not beat position, so this is the "
            f"only thing that needs to change to retarget the datapath width -- "
            f"but every doubling doubles the per-cycle byte-lane write/mux fan-out "
            f"into the packet buffer, so wider is a real area/routing cost, not "
            f"free throughput. {MAX_AXI_DATA_W} is a hard ceiling: nothing wider "
            f"has been synthesized or measured on this project's only validated "
            f"target (a WebPACK-tier Artix-7 part)."
        ),
    )
    args = parser.parse_args()

    if args.exact_match_ways < 1:
        parser.error("--exact-match-ways must be >= 1")

    if (args.axi_data_width < 8
            or (args.axi_data_width & (args.axi_data_width - 1)) != 0):
        parser.error(
            f"--axi-data-width must be a power of 2, >=8 (got {args.axi_data_width})"
        )
    if args.axi_data_width > MAX_AXI_DATA_W:
        parser.error(
            f"--axi-data-width={args.axi_data_width} exceeds the maximum "
            f"supported width ({MAX_AXI_DATA_W}) -- see --help for why this "
            f"ceiling exists."
        )

    levels = None
    if args.target_freq_mhz is not None:
        levels = _budget_levels(args.target_freq_mhz, args.device)
        print(
            f"[INFO] Pipeline delay budget: {levels} logic levels/stage "
            f"(target {args.target_freq_mhz} MHz on {args.device})"
        )
        if args.device != 'artix7':
            print(
                "[WARN] --device "
                f"{args.device} timing is an UNVERIFIED ESTIMATE "
                "(no Synthesis license for this device class on this machine) -- "
                "only artix7 numbers come from real synthesis/timing runs."
            )

    run_compiler(
        args.app,
        p4c_bin=args.p4c,
        p4test_bin=args.p4test,
        frontend=args.frontend,
        budget_levels=levels,
        ways=args.exact_match_ways,
        axi_data_width=args.axi_data_width,
    )


if __name__ == "__main__":
    main()
