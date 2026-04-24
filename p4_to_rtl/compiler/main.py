import os

from parse_p4 import parse_p4_file
from ir import IR, ParserState
from emit_parser import emit_parser


def build_ir(parsed):
    ir          = IR()

    parser_info = parsed.get("parser", {})
    states      = parser_info.get("states", [])

    if not states:
        raise RuntimeError("No parser states found in P4 file")

    for s in states:
        ir.add_parser_state(
            name       = s["name"],
            transition = s.get("transition"),
            extract    = s.get("extract"),
            select     = s.get("select")
        )

    return ir


def debug_print_ir(ir):
    print("\n[DEBUG] Parser States:")
    for st in ir.parser_states:
        print(f"  State: {st.name}")
        print(f"    Transition: {st.transition}")
        print(f"    Extract   : {st.extract}")
        print(f"    Select    : {st.select}")
    print("")


def main():
    # Resolve paths
    base_dir   = os.path.dirname(__file__)

    p4_path    = os.path.join(base_dir, "../p4src/apps/default.p4")
    out_dir    = os.path.join(base_dir, "../generated/default")
    out_parser = os.path.join(out_dir, "parser_generated.sv")

    os.makedirs(out_dir, exist_ok=True)

    # Parse P4
    print(f"[INFO] Parsing: {p4_path}")
    parsed = parse_p4_file(p4_path)

    if "parser" not in parsed:
        raise RuntimeError("Parser block not found")

    # Build IR
    ir = build_ir(parsed)

    # Debug IR (VERY IMPORTANT)
    debug_print_ir(ir)

    # Emit RTL
    print("[INFO] Generating parser RTL...")
    emit_parser(ir, out_parser)

    print(f"[SUCCESS] Parser RTL generated at: {out_parser}")


if __name__ == "__main__":
    main()