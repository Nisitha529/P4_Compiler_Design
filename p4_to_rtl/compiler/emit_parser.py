import math


# ============================================================
# Utility
# ============================================================
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


def _sv_literal(val, width):
    """Convert a bare P4 numeric literal to a proper SV literal.

    '0x800'  → "16'h0800"
    '6'      → "8'd6"
    Named constants and unknown expressions are returned unchanged.
    """
    val = val.strip()
    try:
        if val.startswith('0x') or val.startswith('0X'):
            iv     = int(val, 16)
            digits = max(1, (width + 3) // 4)
            return f"{width}'h{iv:0{digits}X}"
        iv = int(val)
        return f"{width}'d{iv}"
    except ValueError:
        return val   # symbolic name — leave as-is


# ============================================================
# Derive CONST_MAP from ir.consts
# ============================================================
def _build_const_map(ir):
    """Return {P4_const_name: SV_literal} from ir.consts.

    ir.consts entries are {'value': '0x8100', 'width': 16} dicts
    (or legacy plain strings for backward compatibility).
    """
    cmap = {}
    for name, entry in ir.consts.items():
        if isinstance(entry, dict):
            val_str = entry['value'].strip()
            w       = entry.get('width', 32)
        else:
            val_str = str(entry).strip()
            w       = 32

        try:
            if val_str.startswith('0x') or val_str.startswith('0X'):
                iv   = int(val_str, 16)
                digits = max(1, (w + 3) // 4)
                cmap[name] = f"{w}'h{iv:0{digits}X}"
            else:
                iv = int(val_str)
                cmap[name] = f"{w}'d{iv}"
        except ValueError:
            cmap[name] = val_str   # symbolic – leave as-is

    return cmap


# ============================================================
# Derive field-width map from ir.header_instances
# ============================================================
def _build_field_width_map(ir):
    """Return {signal_name: width} from header instances.

    Falls back to header type-defs when instance map is not populated.
    """
    fwmap = {}
    if ir.header_instances:
        for inst in ir.header_instances:
            if inst.is_stack:
                continue
            for fld in inst.header_type.fields:
                if fld.width:
                    fwmap[f'{inst.inst_name}_{fld.name}'] = fld.width
    else:
        for h in ir.headers:
            for fld in h.fields:
                if fld.width:
                    fwmap[f'{h.name}_{fld.name}'] = fld.width
    return fwmap


# ============================================================
# MAIN EMITTER
# ============================================================
def emit_parser(ir, output_path):

    const_map = _build_const_map(ir)
    fwmap     = _build_field_width_map(ir)

    states        = list(ir.parser_states.keys())
    states_upper  = [s.upper() for s in states]

    if "ACCEPT" not in states_upper:
        states_upper.append("ACCEPT")

    state_width    = _calc_enum_width(len(states_upper))
    extract_signals = set()
    select_fields   = set()

    for s in ir.parser_states.values():
        for ext in s.extracts:
            extract_signals.add(f"extract_{ext.header}")
        if s.select:
            select_fields.add(_map_expr(s.select.expression))

    with open(output_path, "w") as f:

        # MODULE HEADER
        f.write("module parser_generated(\n")
        f.write("  input  logic clk,\n")
        f.write("  input  logic rst_n,\n")
        f.write("  input  logic valid_in,\n")

        if select_fields:
            for field in sorted(select_fields):
                w = fwmap.get(field, 16)
                f.write(f"  input  logic [{w-1}:0] {field},\n")
        else:
            f.write("  input logic dummy_select,\n")

        for sig in sorted(extract_signals):
            f.write(f"  output logic {sig},\n")

        f.write("  output logic done\n")
        f.write(");\n\n")

        # ENUM
        f.write(f"  typedef enum logic [{state_width-1}:0] {{\n")
        for i, s in enumerate(states_upper):
            comma = "," if i != len(states_upper) - 1 else ""
            f.write(f"    {s}{comma}\n")
        f.write("  } state_t;\n\n")

        f.write("  state_t state, next_state;\n\n")

        # FSM
        f.write("  always_comb begin\n")
        for sig in extract_signals:
            f.write(f"    {sig} = 0;\n")
        f.write("    done = 0;\n")
        f.write("    next_state = state;\n\n")
        f.write("    case (state)\n\n")

        for name, s in ir.parser_states.items():
            src = name.upper()
            f.write(f"      {src}: begin\n")

            for ext in s.extracts:
                f.write(f"        extract_{ext.header} = 1;\n")

            if s.select:
                sel  = s.select
                expr = _map_expr(sel.expression)
                f.write(f"        case ({expr})\n")
                for val, dst in sel.cases:
                    w      = fwmap.get(expr, 16)
                    sv_val = const_map.get(val) or _sv_literal(val, w)
                    f.write(f"          {sv_val}: next_state = {dst.upper()};\n")
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

        # ACCEPT state
        f.write("      ACCEPT: begin\n")
        f.write("        done = 1;\n")
        f.write(f"        next_state = {states_upper[0]};\n")
        f.write("      end\n\n")

        f.write("    endcase\n")
        f.write("  end\n\n")

        # STATE REGISTER
        f.write("  always_ff @(posedge clk) begin\n")
        f.write("    if (!rst_n)\n")
        f.write("      state <= ACCEPT;\n")   # ACCEPT = idle sentinel; next clock starts parsing
        f.write("    else if (valid_in)\n")
        f.write("      state <= next_state;\n")
        f.write("  end\n\n")

        f.write("endmodule\n")
