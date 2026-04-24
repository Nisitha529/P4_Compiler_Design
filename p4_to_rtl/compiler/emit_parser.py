import math


def _calc_enum_width(n_states):
    if n_states <= 1:
        return 1
    return math.ceil(math.log2(n_states))


def emit_parser(ir, output_path):
    states = [s.name.upper() for s in ir.parser_states]

    # Ensure ACCEPT exists
    if "ACCEPT" not in states:
        states.append("ACCEPT")

    num_states = len(states)
    width = _calc_enum_width(num_states)

    with open(output_path, "w") as f:

        # ==================================================
        # Module header (UPDATED)
        # ==================================================
        f.write( "module parser_generated(\n")
        f.write( "  input  logic                 clk,\n")
        f.write( "  input  logic                 rst_n,\n")

        f.write( "  input  logic                 valid_in,\n")
        f.write( "  input  logic [127       : 0] data_in,\n")
        
        f.write(f"  output logic [{width-1} : 0] state_out\n")
        f.write(");\n\n")

        # ==================================================
        # Enum definition
        # ==================================================
        f.write(f"  typedef enum logic [{width-1}:0] {{\n")

        for i, state in enumerate(states):
            comma = "," if i != len(states) - 1 else ""
            f.write(f"    {state}{comma}\n")

        f.write("  } state_t;\n\n")

        # ==================================================
        # State register
        # ==================================================
        f.write("  state_t state;\n\n")

        # ==================================================
        # FSM
        # ==================================================
        f.write("  always_ff @(posedge clk) begin\n")
        f.write("    if (!rst_n) begin\n")
        f.write(f"      state <= {states[0]};\n")
        f.write("    end else if (valid_in) begin\n")
        f.write("      case (state)\n")

        for s in ir.parser_states:
            src = s.name.upper()
            dst = s.transition.upper() if s.transition else "ACCEPT"

            f.write(f"        {src}: begin\n")

            # ------------------------------------------
            # Extraction (future ready)
            # ------------------------------------------
            if getattr(s, "extract", None):
                f.write(f"          // Extract {s.extract}\n")
                f.write("          // TODO: extraction logic here\n")

            # ------------------------------------------
            # Transition
            # ------------------------------------------
            f.write(f"          state <= {dst};\n")
            f.write("        end\n")

        # Default
        f.write("        default: begin\n")
        f.write(f"          state <= {states[0]};\n")
        f.write("        end\n")

        f.write("      endcase\n")
        f.write("    end\n")
        f.write("  end\n\n")

        # ==================================================
        # Output state
        # ==================================================
        f.write("  assign state_out = state;\n\n")

        f.write("endmodule\n")