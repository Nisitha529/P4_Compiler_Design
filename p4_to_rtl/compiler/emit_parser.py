import math


# ==========================================================
# CONSTANT MAP
# ==========================================================
CONST_MAP = {
    "VLAN_TYPE": "16'h8100",
    "IPV4_TYPE": "16'h0800",
    "UDP_PROT":  "8'h11"
}


# ==========================================================
# FIELD WIDTH MAP
# ==========================================================
FIELD_WIDTHS = {
    "eth_type": 16,
    "vlan_last_tpid": 16,
    "ipv4_protocol": 8
}


# ==========================================================
# Utility
# ==========================================================
def _calc_enum_width(n_states):
    if n_states <= 1:
        return 1
    return math.ceil(math.log2(n_states))


def _map_expr(expr):
    if not expr:
        return "0"

    expr = expr.replace("hdr.", "")
    expr = expr.replace(".", "_")
    return expr


# ==========================================================
# MAIN EMITTER
# ==========================================================
def emit_parser(ir, output_path):

    states = list(ir.parser_states.keys())
    states_upper = [s.upper() for s in states]

    if "ACCEPT" not in states_upper:
        states_upper.append("ACCEPT")

    # --------------------------------------------------
    # CORRECT STATE WIDTH (FIXED BUG)
    # --------------------------------------------------
    state_width = _calc_enum_width(len(states_upper))

    extract_signals = set()
    select_fields = set()

    # --------------------------------------------------
    # Collect signals
    # --------------------------------------------------
    for s in ir.parser_states.values():

        for ext in s.extracts:
            extract_signals.add(f"extract_{ext.header}")

        if s.select:
            select_fields.add(_map_expr(s.select.expression))

    # --------------------------------------------------
    # Generate RTL
    # --------------------------------------------------
    with open(output_path, "w") as f:

        # ==================================================
        # MODULE HEADER
        # ==================================================
        f.write("module parser_generated(\n")
        f.write("  input  logic clk,\n")
        f.write("  input  logic rst_n,\n")
        f.write("  input  logic valid_in,\n")

        # --------------------------------------------------
        # Select inputs (FIXED WIDTH)
        # --------------------------------------------------
        if select_fields:
            for field in sorted(select_fields):
                w = FIELD_WIDTHS.get(field, 16)
                f.write(f"  input  logic [{w-1}:0] {field},\n")
        else:
            f.write("  input logic dummy_select,\n")

        # --------------------------------------------------
        # Extract outputs
        # --------------------------------------------------
        for sig in sorted(extract_signals):
            f.write(f"  output logic {sig},\n")

        f.write("  output logic done\n")
        f.write(");\n\n")

        # ==================================================
        # ENUM (FIXED)
        # ==================================================
        f.write(f"  typedef enum logic [{state_width-1}:0] {{\n")
        for i, s in enumerate(states_upper):
            comma = "," if i != len(states_upper) - 1 else ""
            f.write(f"    {s}{comma}\n")
        f.write("  } state_t;\n\n")

        f.write("  state_t state, next_state;\n\n")

        # ==================================================
        # FSM
        # ==================================================
        f.write("  always_comb begin\n")

        for sig in extract_signals:
            f.write(f"    {sig} = 0;\n")

        f.write("    done = 0;\n")
        f.write("    next_state = state;\n\n")

        f.write("    case (state)\n\n")

        for name, s in ir.parser_states.items():
            src = name.upper()

            f.write(f"      {src}: begin\n")

            # Extraction
            for ext in s.extracts:
                f.write(f"        extract_{ext.header} = 1;\n")

            # SELECT
            if s.select:
                sel = s.select
                expr = _map_expr(sel.expression)

                f.write(f"        case ({expr})\n")

                for val, dst in sel.cases:
                    mapped_val = CONST_MAP.get(val, val)
                    f.write(f"          {mapped_val}: next_state = {dst.upper()};\n")

                if sel.default:
                    f.write(f"          default: next_state = {sel.default.upper()};\n")
                else:
                    f.write("          default: next_state = ACCEPT;\n")

                f.write("        endcase\n")

            elif s.next_state:
                f.write(f"        next_state = {s.next_state.upper()};\n")

            else:
                f.write("        next_state = ACCEPT;\n")

            f.write("      end\n\n")

        # ACCEPT
        f.write("      ACCEPT: begin\n")
        f.write("        done = 1;\n")
        f.write(f"        next_state = {states_upper[0]};\n")
        f.write("      end\n\n")

        f.write("    endcase\n")
        f.write("  end\n\n")

        # ==================================================
        # STATE REGISTER
        # ==================================================
        f.write("  always_ff @(posedge clk) begin\n")
        f.write("    if (!rst_n)\n")
        f.write(f"      state <= {states_upper[0]};\n")
        f.write("    else if (valid_in)\n")
        f.write("      state <= next_state;\n")
        f.write("  end\n\n")

        f.write("endmodule\n")