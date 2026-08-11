"""Delay-cost estimation for the opt-in pipeline-budget scheduler.

This module answers one question: "roughly how many FPGA logic levels does
this RTL expression cost?" -- used to decide where the budget-driven stage
splitter (see emit_processing.py) needs to insert an extra pipeline
register. It is deliberately NOT a general expression-IR for the rest of
the compiler: it never re-serializes anything back to SystemVerilog, it
only ever produces a number.

Honesty about what's actually known vs. estimated (read before touching
the constants below):

  Exactly ONE real measurement exists anywhere in this compiler's history:
  a Vivado synth_design + report_timing run on Artix-7 (xc7a100tcsg324-1 --
  the only part with a working Synthesis license on this machine) of
  firewall's processing_generated.sv, which found the worst path was 16
  logic levels (2x CARRY4, 1x LUT2, 1x LUT3, 2x LUT4, 3x LUT5, 7x LUT6)
  running from an LPM table's leaf register, through its priority-match
  tree, through the caller's action-dispatch mux, through an 8-bit TTL
  decrement, to the next register -- a ~93MHz *pre-route* (no
  place_design/route_design) estimate.

  That is a single COMPOSITE measurement, not independently-separable
  per-operator costs -- there is no way to solve for "cost of a compare"
  vs. "cost of a mux" vs. "cost of an 8-bit add" from one number. The
  per-operator weights below are seeded from textbook FPGA logic-synthesis
  behavior (LUT6 fan-in, fast carry-chain granularity, binary mux/reduction
  trees), NOT derived from measurement, except for one constant
  (CARRY_LEVELS_PER_8B) which is anchored to the one real data point.

  UltraScale+/Versal DEVICE_FACTOR entries are sourced from AMD's public
  product-brief relative-speed claims. They are NOT independently verified
  on this machine -- there is no Synthesis license for that device class
  here (confirmed: xczu9eg fails instantly with a license error).

  Given all of that, this model is deliberately biased to OVER-count
  delay: an over-estimate costs an extra register (harmless); an
  under-estimate produces a false "meets budget" claim (the actual bad
  outcome). Any construct this parser doesn't recognize is charged a large
  fixed penalty and printed as a [WARN], never silently ignored.
"""

import math
import re


# ============================================================
# Calibration data (the one real number) and device scaling (estimates)
# ============================================================

# The only measured quantity in this whole model. See module docstring.
ARTIX7_LEVELS_AT_93MHZ = 16

# 2 logic levels for an 8-bit add/sub is read directly off the one real
# trace above (2x CARRY4 in the worst path, for firewall's 8-bit TTL
# decrement -- 7-series CARRY4 primitives chain 4 bits per level, and the
# measured path crossed two of them for an 8-bit operand). This is the one
# arithmetic-cost constant with an actual measurement behind it; every
# other weight below is textbook FPGA logic-effort estimation.
CARRY_LEVELS_PER_8B = 2

# NOT independently measured -- see module docstring. Sourced from AMD's
# public Vitis/UltraScale+/Versal product-brief relative-speed claims
# (faster fabric generation vs. 7-series), not synthesized or timed on
# this machine (no Synthesis license for these device classes here).
DEVICE_FACTOR = {
    'artix7': 1.0,             # the only real, measured entry
    'ultrascale-plus': 0.6,    # public-doc estimate only, unverified
    'versal': 0.45,            # public-doc estimate only, unverified
}

_UNKNOWN_CONSTRUCT_PENALTY = 64  # deliberately large: fail conservative


def budget_levels(target_mhz, device='artix7'):
    """How many estimated logic levels fit in one cycle at `target_mhz` on
    `device`, scaled from the one real Artix-7 calibration point. Does NOT
    invent a picosecond-per-level constant that was never measured --
    scales the one real (levels, frequency) pair directly instead."""
    if target_mhz <= 0:
        raise ValueError('target_mhz must be positive')
    factor = DEVICE_FACTOR.get(device)
    if factor is None:
        raise ValueError(f'unknown device {device!r}; known: {sorted(DEVICE_FACTOR)}')
    levels = ARTIX7_LEVELS_AT_93MHZ * (93.0 / target_mhz) * factor
    return max(1, round(levels))


def table_tree_stages(depth, budget_levels=None):
    """How many pipeline-register hops an LPM/ternary table's
    log2(depth)-level balanced priority-match tree needs (see
    emit_table.py's _emit_one_table). Called identically by emit_table.py
    (how many mid-tree registers to actually insert) and
    emit_processing.py (how many no-op pass-through stages its scheduler
    must insert for that same table), so the two can never drift apart.

    budget_levels=None (default) -> 1: the whole tree builds in a single
    combinational shot, registered only at its output -- today's fixed
    2-cycle table latency (leaf register + this one hop), unchanged.
    Otherwise: split into ceil(tree_levels / budget_levels) hops so no
    single hop's combinational depth exceeds the per-stage budget."""
    if budget_levels is None:
        return 1
    tree_levels = math.ceil(math.log2(depth)) if depth > 1 else 0
    if tree_levels <= 0:
        return 1
    return max(1, math.ceil(tree_levels / budget_levels))


def exact_match_tag_compare_stages(key_widths, budget_levels=None):
    """How many pipeline-register hops an exact-match table's tag-compare
    (the AND-chain of per-key-field equalities run against the BRAM's
    registered read output, see emit_table.py's _emit_exact_match_table)
    needs. Called identically by emit_table.py (whether to insert the
    extra forwarding register) and emit_processing.py (how many no-op
    pass-through stages its scheduler must insert for that same table),
    so the two can never drift apart -- same discipline as
    table_tree_stages() for LPM/ternary tables.

    budget_levels=None (default) -> 1: today's fixed 2-cycle table latency
    (BRAM-read register, tag-compare-and-select purely combinational,
    final output register), unchanged. Otherwise: reuses
    estimate_expr_delay() itself (not a hand-derived formula) on the real
    tag-compare expression shape to decide whether it needs its own
    register between the compare and the select -- 2 hops if so, 1 if the
    compare already fits the budget."""
    if budget_levels is None or not key_widths:
        return 1
    width_of = {}
    parts = []
    for i, w in enumerate(key_widths):
        a, b = f'k{i}a', f'k{i}b'
        width_of[a] = w
        width_of[b] = w
        parts.append(f'({a} == {b})')
    expr = ' && '.join(parts)
    cost = estimate_expr_delay(expr, lambda n: width_of.get(n))
    return 2 if cost > budget_levels else 1


# ============================================================
# Expression tokenizer
# ============================================================

_TOKEN_RE = re.compile(r"""
    \s*(?:
      (?P<sized_lit>\d+'[bdohBDOH][0-9a-fA-F_xXzZ]+)
    | (?P<unsized_lit>'[bdohBDOH][0-9a-fA-F_xXzZ]+)
    | (?P<decimal>\d+)
    | (?P<ident>[a-zA-Z_][a-zA-Z0-9_$]*)
    | (?P<op>\|\||&&|==|!=|<=|>=|<<|>>|[|^&<>+\-*/!~?:(){}\[\],])
    )""", re.VERBOSE)


def _tokenize(text):
    pos, out = 0, []
    while pos < len(text):
        if text[pos].isspace():
            pos += 1
            continue
        m = _TOKEN_RE.match(text, pos)
        if not m or m.end() == pos:
            raise ValueError(f'unrecognized token at {text[pos:pos+16]!r}')
        pos = m.end()
        kind = m.lastgroup
        out.append((kind, m.group(kind)))
    return out


def _literal_width(tok_text):
    """Width of a sized literal like `8'd0` or `32'hDEADBEEF`; None if
    unsized (caller falls back to a default width)."""
    m = re.match(r"^(\d+)'", tok_text)
    return int(m.group(1)) if m else None


# ============================================================
# Recursive-descent cost/width evaluator
#
# Parses and folds in one pass -- each parse function returns (width,
# cost) directly rather than building a separate AST object, since cost
# estimation is the only consumer and there's no need to re-walk a
# materialized tree afterward.
# ============================================================

class _Parser:
    def __init__(self, tokens, width_of, default_width):
        self.toks = tokens
        self.i = 0
        self.width_of = width_of
        self.default_width = default_width

    def _peek(self):
        return self.toks[self.i] if self.i < len(self.toks) else (None, None)

    def _eat(self, expect=None):
        kind, text = self._peek()
        if expect is not None and text != expect:
            raise ValueError(f'expected {expect!r}, got {text!r}')
        self.i += 1
        return kind, text

    def _at_end(self):
        return self.i >= len(self.toks)

    # expr := ternary
    def parse(self):
        w, c = self._ternary()
        if not self._at_end():
            raise ValueError(f'unexpected trailing tokens at {self._peek()}')
        return w, c

    # ternary := logic_or ('?' ternary ':' ternary)?
    def _ternary(self):
        cw, cc = self._logic_or()
        _, text = self._peek()
        if text == '?':
            self._eat('?')
            tw, tc = self._ternary()
            self._eat(':')
            ew, ec = self._ternary()
            # 1 level for the final 2:1 select mux, on top of whichever
            # operand path is more expensive.
            return max(tw, ew), cc + 1 + max(tc, ec)
        return cw, cc

    def _binary_level(self, next_level, ops, weight_fn):
        w, c = next_level()
        while True:
            _, text = self._peek()
            if text not in ops:
                return w, c
            self._eat(text)
            rw, rc = next_level()
            rw_combined = max(w, rw)
            c = c + rc + weight_fn(rw_combined)
            w = rw_combined

    def _logic_or(self):
        return self._binary_level(self._logic_and, {'||'}, lambda w: 1)

    def _logic_and(self):
        return self._binary_level(self._bit_or, {'&&'}, lambda w: 1)

    def _bit_or(self):
        return self._binary_level(self._bit_xor, {'|'}, lambda w: 1)

    def _bit_xor(self):
        return self._binary_level(self._bit_and, {'^'}, lambda w: 1)

    def _bit_and(self):
        return self._binary_level(self._equality, {'&'}, lambda w: 1)

    def _equality(self):
        return self._binary_level(
            self._relational, {'==', '!='}, lambda w: max(1, math.ceil(math.log2(max(w, 1) + 1))))

    def _relational(self):
        return self._binary_level(
            self._shift, {'<', '>', '<=', '>='},
            lambda w: math.ceil(max(w, 1) / 8) * CARRY_LEVELS_PER_8B)

    def _shift(self):
        # Shift by a constant is pure wiring (0 cost); shift by a variable
        # is a barrel shifter (log2(width) levels) -- emit_table.py's own
        # comments independently call out variable-width shifts as
        # expensive for exactly this reason (the LPM prefix-shift rewrite
        # earlier this project specifically existed to eliminate one).
        w, c = self._additive()
        while True:
            _, text = self._peek()
            if text not in ('<<', '>>'):
                return w, c
            shift_start = self.i
            self._eat(text)
            was_const = self._peek()[0] in ('decimal', 'sized_lit', 'unsized_lit')
            rw, rc = self._additive()
            if was_const:
                c = c + rc
            else:
                c = c + rc + max(1, math.ceil(math.log2(max(w, 1) + 1)))
            _ = shift_start  # kept for clarity, not otherwise used

    def _additive(self):
        return self._binary_level(
            self._unary, {'+', '-'},
            lambda w: math.ceil(max(w, 1) / 8) * CARRY_LEVELS_PER_8B)

    def _unary(self):
        _, text = self._peek()
        if text in ('!', '~', '-'):
            self._eat(text)
            w, c = self._unary()
            return w, c + (1 if text != '-' else math.ceil(max(w, 1) / 8) * CARRY_LEVELS_PER_8B)
        return self._postfix()

    def _postfix(self):
        w, c = self._primary()
        while True:
            _, text = self._peek()
            if text != '[':
                return w, c
            self._eat('[')
            # Bit-select: cost-free (pure routing); width = hi-lo+1 for a
            # range, 1 for a single index. Parse loosely -- only the width
            # matters here, not evaluating the index expressions.
            first = self._const_or_none()
            _, nxt = self._peek()
            if nxt == ':':
                self._eat(':')
                second = self._const_or_none()
                w = (first - second + 1) if (first is not None and second is not None) else self.default_width
            else:
                w = 1
            self._eat(']')

    def _const_or_none(self):
        """Best-effort: consume one primary and return its integer value
        if it was a plain literal, else None (dynamic index)."""
        kind, text = self._peek()
        if kind == 'decimal':
            self._eat(text)
            return int(text)
        if kind in ('sized_lit', 'unsized_lit'):
            self._eat(text)
            return None  # not bothering to decode radix here; width-only use
        # Anything else (an identifier/expression) -- consume one primary
        # so the outer '[' ... ']' still balances, but we don't know the value.
        self._primary()
        return None

    def _primary(self):
        kind, text = self._peek()
        if kind == 'sized_lit':
            self._eat(text)
            return _literal_width(text) or self.default_width, 0
        if kind in ('unsized_lit', 'decimal'):
            self._eat(text)
            # Unsized literals (`'h01`) and bare decimals are
            # context-sized in real Verilog -- they take on whatever width
            # the expression around them needs (e.g. `ipv4_ttl - 'h01`
            # costs like an 8-bit subtract when ipv4_ttl is 8 bits, not a
            # 32-bit one). Modeling that properly would need real
            # context-width propagation; the cheap, safe approximation is
            # to give literals a small width so they never *inflate* a
            # combined-width cost via max(width) -- confirmed necessary by
            # this module's own __main__ calibration check, which caught
            # a real 8-vs-32-bit-cost bug here before this comment existed.
            return 1, 0
        if kind == 'ident':
            self._eat(text)
            return self.width_of(text) or self.default_width, 0
        if text == '(':
            self._eat('(')
            w, c = self._ternary()
            self._eat(')')
            return w, c
        if text == '{':
            self._eat('{')
            total_w, total_c = 0, 0
            if self._peek()[1] != '}':
                while True:
                    w, c = self._ternary()
                    total_w += w
                    total_c = max(total_c, c)  # concat operands evaluate in parallel
                    if self._peek()[1] == ',':
                        self._eat(',')
                        continue
                    break
            self._eat('}')
            return total_w, total_c  # concatenation itself: 0 extra levels (routing)
        raise ValueError(f'unexpected token {text!r} in primary')


def estimate_expr_delay(expr_str, width_of=None, default_width=32):
    """Estimate the combinational logic-level cost of an RTL expression
    string (an Assignment.rhs or IfStatement.condition, in this
    compiler's post-_map_expr/_map_cond textual form).

    `width_of(name) -> int | None` resolves an identifier's bit width
    (e.g. via emit_processing.py's fwmap/locals_ tables); pass None to
    always use `default_width`.

    Never raises: on any parse failure (an expression shape this
    deliberately-narrow grammar doesn't handle), prints a [WARN] and
    returns a large fixed penalty -- conservative by design, since an
    under-estimate here would produce a false "meets budget" claim.
    """
    if width_of is None:
        width_of = lambda _name: None
    try:
        tokens = _tokenize(expr_str)
        if not tokens:
            return 0
        _, cost = _Parser(tokens, width_of, default_width).parse()
        return cost
    except (ValueError, IndexError, RecursionError) as e:
        print(f'[WARN] timing_model: could not estimate delay of {expr_str!r} '
              f'({e}) -- charging conservative penalty of {_UNKNOWN_CONSTRUCT_PENALTY}')
        return _UNKNOWN_CONSTRUCT_PENALTY


if __name__ == '__main__':
    # Hand sanity-check against the one real calibration case (Phase 0):
    # firewall's ipv4_forward action does `hdr.ipv4.ttl = hdr.ipv4.ttl - 1`
    # (an 8-bit subtract) and the table dispatch around it is a `unique
    # case` mux -- the real trace measured 16 total levels for that
    # subtract *plus* the LPM tree *plus* the dispatch mux combined. Here
    # we can only estimate the arithmetic sliver of that path in isolation:
    ttl_w = lambda name: {'ipv4_ttl': 8}.get(name)
    cost = estimate_expr_delay("(ipv4_ttl - 'h01)", ttl_w)
    print(f"'(ipv4_ttl - 'h01)' (8-bit subtract) estimated at {cost} levels "
          f'(real trace: 2 CARRY4 levels for this same op, so this should be {CARRY_LEVELS_PER_8B})')
    assert cost == CARRY_LEVELS_PER_8B, 'calibration sanity check failed'

    ternary_cost = estimate_expr_delay(
        "((ipv4_ttl < 'h01) ? 8'd0 : (ipv4_ttl - 'h01))", ttl_w)
    print(f"saturating-subtract ternary estimated at {ternary_cost} levels")

    print(f'budget_levels(93, "artix7")   = {budget_levels(93, "artix7")} '
          f'(should equal the real calibration point, {ARTIX7_LEVELS_AT_93MHZ})')
    assert budget_levels(93, 'artix7') == ARTIX7_LEVELS_AT_93MHZ
    print(f'budget_levels(400, "ultrascale-plus") = {budget_levels(400, "ultrascale-plus")} (ESTIMATE, unverified)')
    print(f'budget_levels(400, "versal")          = {budget_levels(400, "versal")} (ESTIMATE, unverified)')

    # table_tree_stages: firewall's real ipv4_lpm table, DEPTH=1024,
    # tree_levels=ceil(log2(1024))=10.
    assert table_tree_stages(1024, None) == 1, 'None must stay the fixed 2-cycle default'
    assert table_tree_stages(1024, budget_levels(400, 'artix7')) == 3, \
        f'expected 3 hops at 400MHz/artix7 (budget={budget_levels(400, "artix7")}), got ' \
        f'{table_tree_stages(1024, budget_levels(400, "artix7"))}'
    assert table_tree_stages(2, None) == 1
    assert table_tree_stages(1, 4) == 1, 'DEPTH=1 has no tree at all'
    print(f'table_tree_stages(1024, None)                        = {table_tree_stages(1024, None)}')
    print(f'table_tree_stages(1024, budget_levels(400,"artix7"))  = '
          f'{table_tree_stages(1024, budget_levels(400, "artix7"))} (ESTIMATE-driven, real formula)')

    # exact_match_tag_compare_stages: firewall's real check_ports table,
    # 2 key fields (ingress_port, egress_spec), both 9 bits -- confirmed
    # by real Vivado synthesis to need splitting once the LPM tree no
    # longer dominates (see the architecture-redesign plan, Phase 6).
    assert exact_match_tag_compare_stages([9, 9], None) == 1, 'None must stay the fixed 2-cycle default'
    assert exact_match_tag_compare_stages([9, 9], budget_levels(400, 'artix7')) == 2, \
        'expected a split at 400MHz/artix7 for check_ports-shaped keys'
    assert exact_match_tag_compare_stages([], 4) == 1, 'no key fields -> nothing to split'
    assert exact_match_tag_compare_stages([16], 4) == 2, 'single-field key must not crash the parser'
    print(f'exact_match_tag_compare_stages([9,9], None)                       = '
          f'{exact_match_tag_compare_stages([9, 9], None)}')
    print(f'exact_match_tag_compare_stages([9,9], budget_levels(400,"artix7")) = '
          f'{exact_match_tag_compare_stages([9, 9], budget_levels(400, "artix7"))} (ESTIMATE-driven, real formula)')
    print('OK')
