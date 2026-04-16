import math


def _calc_enum_width(n_states):
    if n_states <= 1:
        return 1
    return math.ceil(math.log2(n_states))


def emit_parser(ir, output_path):
    states = [s.name.upper() for s in ir.parser_states]

    # Always include ACCEPT state
    if "ACCEPT" not in states:
        states.append("ACCEPT")

    num_states = len(states)
    width = _calc_enum_width(num_states)

    with open(output_path, "w") as f:

        # --------------------------------------------------
        # Module header
        # --------------------------------------------------
        f.write("module parser_generated(\n")
        f.write("  input  logic clk,\n")
        f.write("  input  logic rst_n\n")
        f.write(");\n\n")

        # --------------------------------------------------
        # State enum
        # --------------------------------------------------
        f.write(f"  typedef enum logic [{width-1}:0] {{\n")

        for i, state in enumerate(states):
            if i != len(states) - 1:
                f.write(f"    {state},\n")
            else:
                f.write(f"    {state}\n")

        f.write("  } state_t;\n\n")

        # --------------------------------------------------
        # State register
        # --------------------------------------------------
        f.write("  state_t state;\n\n")

        # --------------------------------------------------
        # FSM logic
        # --------------------------------------------------
        f.write("  always_ff @(posedge clk) begin\n")
        f.write("    if (!rst_n) begin\n")
        f.write(f"      state <= {states[0]};\n")
        f.write("    end else begin\n")
        f.write("      case (state)\n")

        for s in ir.parser_states:
            src = s.name.upper()
            dst = s.transition.upper()

            f.write(f"        {src}: begin\n")
            f.write(f"          state <= {dst};\n")
            f.write("        end\n")

        # default safety
        f.write("        default: begin\n")
        f.write(f"          state <= {states[0]};\n")
        f.write("        end\n")

        f.write("      endcase\n")
        f.write("    end\n")
        f.write("  end\n\n")

        f.write("endmodule\n")