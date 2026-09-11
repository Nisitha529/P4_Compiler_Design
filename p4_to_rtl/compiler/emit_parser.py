import math
import re

from boards import validate_board


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
def _split_verify(raw):
    """Split a raw `verify(...)` argument string into (condition, error_value).

    ingest_p4ir.py stores the whole argument list as Verify.condition, and by
    the time it gets here `error.X` has already been rewritten to a numeric
    literal (see _parse_error_enum), so the text looks like
        "hdr.ipv4.version == 4w4 && hdr.ipv4.hdr_len >= 4w5, 4w8"
    Split on the LAST top-level comma: the condition itself may contain commas
    inside a function call or concatenation."""
    depth = 0
    cut = -1
    for i, ch in enumerate(raw):
        if ch in '([{':
            depth += 1
        elif ch in ')]}':
            depth -= 1
        elif ch == ',' and depth == 0:
            cut = i
    if cut < 0:
        return raw.strip(), None
    return raw[:cut].strip(), raw[cut + 1:].strip()


def _verify_field_refs(cond):
    """Signal names a verify condition reads, in _map_expr form.

    These have to become parser input ports. The parser otherwise only receives
    the fields it `select`s on, so without this a verify on any other field
    (hdr.ipv4.version, hdr.tcp.dataOffset, ...) would reference an undeclared
    signal."""
    return {_map_expr(m) for m in re.findall(r'hdr\.\w+(?:\.\w+)*', cond)}


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
def emit_parser(ir, output_path, board=None):
    """
    board: None (default) = today's behavior exactly -- emits Vivado's
        `(* fsm_encoding = "one_hot" *)` unconditionally, byte-identical to
        before this parameter existed. Otherwise a board descriptor dict
        (see boards.py/load_board) -- makes that pragma vendor-correct.
        Re-validated here since this function can be called directly, not
        only via the CLI.
    """
    if board is not None:
        validate_board(board)

    const_map = _build_const_map(ir)
    fwmap     = _build_field_width_map(ir)

    states        = list(ir.parser_states.keys())
    states_upper  = [s.upper() for s in states]

    # verify(cond, error) per state, with `error.X` already numeric. Everything
    # below that depends on these is gated on `has_verifies`, so a program with
    # no verify() emits byte-identical RTL to before this feature existed.
    verify_map = {}     # state name -> [(condition_text, error_literal)]
    verify_fields = set()
    for name, st in ir.parser_states.items():
        vs = []
        for v in st.verifies:
            cond, errv = _split_verify(v.condition)
            if errv is None:
                # verify(cond) with no error argument is not legal P4-16; skip
                # rather than emit a REJECT with an undefined error code.
                continue
            vs.append((cond, errv))
            verify_fields |= _verify_field_refs(cond)
        if vs:
            verify_map[name] = vs
    has_verifies = bool(verify_map)
    # Width of standard_metadata.parser_error, from the architecture's own
    # error enum (see ingest_p4ir._parse_error_enum) -- not a fixed guess.
    err_w = max(1, getattr(ir, 'error_width', 0) or 1)
    no_error = getattr(ir, 'error_values', {}).get('NoError', 0)

    if "ACCEPT" not in states_upper:
        states_upper.append("ACCEPT")
    # REJECT is P4's own terminal parser state: verify() failing transitions
    # there. Like ACCEPT it asserts `done` -- the packet is finished parsing,
    # just badly -- so the pipeline advances and the control block sees a
    # non-NoError standard_metadata.parser_error and decides what to do. Not
    # asserting done would stall the pipeline on a malformed packet.
    if has_verifies and "REJECT" not in states_upper:
        states_upper.append("REJECT")

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

        # A verify condition reads fields the FSM does not select on, so its
        # operands need input ports too.
        all_in_fields = set(select_fields) | verify_fields
        if all_in_fields:
            for field in sorted(all_in_fields):
                w = fwmap.get(field, 16)
                f.write(f"  input  logic [{w-1}:0] {field},\n")
        else:
            f.write("  input logic dummy_select,\n")

        for sig in sorted(extract_signals):
            f.write(f"  output logic {sig},\n")

        if has_verifies:
            f.write(f"  output logic [{err_w-1}:0] parser_error,\n")
        f.write("  output logic done\n")
        f.write(");\n\n")

        # ENUM
        f.write(f"  typedef enum logic [{state_width-1}:0] {{\n")
        for i, s in enumerate(states_upper):
            comma = "," if i != len(states_upper) - 1 else ""
            f.write(f"    {s}{comma}\n")
        f.write("  } state_t;\n\n")

        if board is None:
            f.write('  (* fsm_encoding = "one_hot" *)\n')
        else:
            fsm_pragma = board['fsm_encoding_pragma']
            if fsm_pragma:
                f.write(f'  {fsm_pragma}\n')
            else:
                f.write(
                    f"  // fsm_encoding: board '{board['name']}' ({board['vendor']}) has no "
                    f"reliable inline attribute for this -- set state-machine encoding via "
                    f"your toolchain's Assignment/Settings UI instead\n"
                )
        f.write("  state_t state, next_state;\n")
        if has_verifies:
            f.write(f"  logic [{err_w-1}:0] err_next;\n")
        f.write("\n")

        # FSM
        f.write("  always_comb begin\n")
        # sorted(), not bare set iteration: Python's set order varies between
        # runs, so this block used to emit its defaults in a different order
        # each time. The RTL was equivalent, but every regeneration produced a
        # spurious diff in parser_generated.sv, which made "did my change alter
        # any output?" expensive to answer. The declaration loop above was
        # already sorted; this one was missed.
        for sig in sorted(extract_signals):
            f.write(f"    {sig} = 0;\n")
        f.write("    done = 0;\n")
        f.write("    next_state = state;\n")
        if has_verifies:
            # Hold by default: an error latched in one state has to survive
            # until the packet finishes parsing.
            f.write("    err_next = parser_error;\n")
        f.write("\n")
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

            # verify() last, so it OVERRIDES the transition chosen above --
            # which is exactly P4's semantics: a failing verify aborts the
            # state's transition and goes to reject. The extract pulses above
            # deliberately stay asserted: P4 extracts the header first and only
            # then evaluates the verify, so the header really was extracted.
            # Conditions are checked in source order and the first failure
            # wins, again matching P4.
            for cond, errv in verify_map.get(name, []):
                sv_cond = _map_expr(cond)
                f.write(f"        // verify({cond}, {errv})\n")
                f.write(f"        if (!({sv_cond})) begin\n")
                f.write(f"          next_state = REJECT;\n")
                f.write(f"          err_next   = {_sv_literal(errv, err_w)};\n")
                f.write(f"        end\n")

            f.write("      end\n\n")

        # ACCEPT state
        f.write("      ACCEPT: begin\n")
        f.write("        done = 1;\n")
        f.write(f"        next_state = {states_upper[0]};\n")
        f.write("      end\n\n")

        if has_verifies:
            # Same shape as ACCEPT -- done still asserts, so a malformed packet
            # moves through the pipeline instead of stalling it, carrying its
            # error code. err_next clears here so the NEXT packet starts at
            # NoError; parser_error itself still reads the error during this
            # cycle, because the register only takes err_next at the edge.
            f.write("      REJECT: begin\n")
            f.write("        done = 1;\n")
            f.write(f"        err_next = {err_w}'d{no_error};\n")
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

        if has_verifies:
            f.write("  // standard_metadata.parser_error. Advances with the FSM so it is\n")
            f.write("  // valid in the same cycle `done` asserts for its packet.\n")
            f.write("  always_ff @(posedge clk) begin\n")
            f.write("    if (!rst_n)\n")
            f.write(f"      parser_error <= {err_w}'d{no_error};\n")
            f.write("    else if (valid_in)\n")
            f.write("      parser_error <= err_next;\n")
            f.write("  end\n\n")

        f.write("endmodule\n")
