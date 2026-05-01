import math


def _calc_enum_width(n_states):
    if n_states <= 1:
        return 1
    return math.ceil(math.log2(n_states))


def emit_parser(ir, output_path):

    states = list(ir.parser_states.keys())
    states_upper = [s.upper() for s in states]

    if "ACCEPT" not in states_upper:
        states_upper.append("ACCEPT")

    width = _calc_enum_width(len(states_upper))

    # --------------------------------------------------
    # Collect control signals dynamically
    # --------------------------------------------------
    extract_signals = set()

    for s in ir.parser_states.values():
        for ext in getattr(s, "extracts", []):
            extract_signals.add(f"extract_{ext.header}")

    with open(output_path, "w") as f:

        # ==================================================
        # MODULE HEADER
        # ==================================================
        f.write("module parser_generated(\n")
        f.write("  input  logic clk,\n")
        f.write("  input  logic rst_n,\n\n")

        f.write("  input  logic valid_in,\n")

        # CHANGED: expose parsed fields for select
        f.write("  input  logic [15:0] eth_type,\n\n")

        # CHANGED: control outputs
        for sig in extract_signals:
            f.write(f"  output logic {sig},\n")

        f.write("  output logic done\n")
        f.write(");\n\n")

        # ==================================================
        # STATE ENUM
        # ==================================================
        f.write(f"  typedef enum logic [{width-1}:0] {{\n")

        for i, s in enumerate(states_upper):
            comma = "," if i != len(states_upper) - 1 else ""
            f.write(f"    {s}{comma}\n")

        f.write("  } state_t;\n\n")

        f.write("  state_t state, next_state;\n\n")

        # ==================================================
        # COMBINATIONAL FSM (CONTROL GENERATION)
        # ==================================================
        f.write("  always_comb begin\n")

        # default assignments
        for sig in extract_signals:
            f.write(f"    {sig} = 0;\n")

        f.write("    done = 0;\n")
        f.write("    next_state = state;\n\n")

        f.write("    case (state)\n\n")

        for name, s in ir.parser_states.items():
            src = name.upper()

            f.write(f"      {src}: begin\n")

            # ------------------------------------------
            # Extract signals
            # ------------------------------------------
            for ext in getattr(s, "extracts", []):
                f.write(f"        extract_{ext.header} = 1;\n")

            # ------------------------------------------
            # SELECT logic
            # ------------------------------------------
            if s.select:
                expr = _map_expr(s.select.expression)

                f.write(f"        case ({expr})\n")

                for val, dst in s.select.cases:
                    f.write(f"          {val}: next_state = {dst.upper()};\n")

                if s.select.default:
                    f.write(f"          default: next_state = {s.select.default.upper()};\n")
                else:
                    f.write("          default: next_state = ACCEPT;\n")

                f.write("        endcase\n")

            # ------------------------------------------
            # DIRECT transition
            # ------------------------------------------
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


# ==================================================
# SIMPLE EXPRESSION MAPPER
# ==================================================
def _map_expr(expr):
    expr = expr.replace("hdr.", "")
    expr = expr.replace(".", "_")
    return expr