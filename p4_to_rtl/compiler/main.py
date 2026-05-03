import os
import argparse

from parse_p4 import parse_p4_file
from ir import IR, ParserState, Extract, ParserSelect
from emit_parser import emit_parser


# ============================================================
# IR Builder
# ============================================================
def build_ir(parsed):
    ir = IR()

    parser_info = parsed.get("parser", {})
    states = parser_info.get("states", [])

    if not states:
        raise RuntimeError("No parser states found in P4 file")

    for s in states:
        state = ParserState(s["name"])

        # --------------------------------
        # Extracts (FIXED: support multiple)
        # --------------------------------
        for ext in s.get("extracts", []):
            state.add_extract(Extract(ext))

        # --------------------------------
        # Transition
        # --------------------------------
        if s.get("transition"):
            state.set_transition(s["transition"])

        # --------------------------------
        # Select
        # --------------------------------
        if s.get("select"):
            sel_info = s["select"]

            sel = ParserSelect(sel_info["expr"])

            for val, dst in sel_info.get("cases", []):
                sel.add_case(val, dst)

            if sel_info.get("default"):
                sel.set_default(sel_info["default"])

            state.set_select(sel)

        ir.add_parser_state(state)

    # --------------------------------
    # Start state
    # --------------------------------
    ir.set_start_state(states[0]["name"])

    return ir


# ============================================================
# Debug Printer
# ============================================================
def debug_ir(ir):
    print("\n[DEBUG] Parser IR:")

    for name, st in ir.parser_states.items():
        print(f"  State: {name}")
        print(f"    Extracts : {[e.header for e in st.extracts]}")
        print(f"    Next     : {st.next_state}")
        print(f"    Select   : {st.select.expression if st.select else None}")

    print("")


# ============================================================
# MAIN DRIVER
# ============================================================
def run_compiler(app_name):

    base_dir = os.path.dirname(__file__)

    p4_path = os.path.join(base_dir, f"../p4src/apps/{app_name}.p4")
    out_dir = os.path.join(base_dir, f"../generated/{app_name}")
    out_parser = os.path.join(out_dir, "parser_generated.sv")

    # --------------------------------
    # Validate input
    # --------------------------------
    if not os.path.exists(p4_path):
        raise FileNotFoundError(f"P4 file not found: {p4_path}")

    os.makedirs(out_dir, exist_ok=True)

    # --------------------------------
    # Parse P4
    # --------------------------------
    print(f"[INFO] Parsing P4: {p4_path}")
    parsed = parse_p4_file(p4_path)

    if "parser" not in parsed:
        raise RuntimeError("Parser block not found in P4")

    # --------------------------------
    # Build IR
    # --------------------------------
    print("[INFO] Building IR...")
    ir = build_ir(parsed)

    debug_ir(ir)

    # --------------------------------
    # Emit RTL
    # --------------------------------
    print("[INFO] Generating parser RTL...")
    emit_parser(ir, out_parser)

    print(f"[SUCCESS] Generated parser RTL at:\n  {out_parser}")


# ============================================================
# CLI ENTRY
# ============================================================
def main():
    parser = argparse.ArgumentParser(
        description="P4 to RTL Compiler (Parser Stage)"
    )

    parser.add_argument(
        "app",
        type=str,
        help="P4 application name (without .p4)"
    )

    args = parser.parse_args()

    run_compiler(args.app)


# ============================================================
# ENTRY POINT
# ============================================================
if __name__ == "__main__":
    main()