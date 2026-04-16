import os

from parse_p4 import parse_p4_file
from ir import IR
from emit_parser import emit_parser


def main():
    # --------------------------------------------------
    # Resolve paths safely
    # --------------------------------------------------
    base_dir = os.path.dirname(__file__)

    p4_path = os.path.join(base_dir, "../p4src/apps/default.p4")
    out_path = os.path.join(base_dir, "../generated/default/parser_generated.sv")

    # --------------------------------------------------
    # Parse P4
    # --------------------------------------------------
    parsed = parse_p4_file(p4_path)

    if "parser" not in parsed or "states" not in parsed["parser"]:
        raise RuntimeError("Parser extraction failed")

    # --------------------------------------------------
    # Build IR
    # --------------------------------------------------
    ir = IR()

    for s in parsed["parser"]["states"]:
        ir.add_parser_state(s["name"], s["transition"])

    # --------------------------------------------------
    # Emit RTL
    # --------------------------------------------------
    emit_parser(ir, out_path)

    print(f"[INFO] Parser RTL generated at: {out_path}")


if __name__ == "__main__":
    main()