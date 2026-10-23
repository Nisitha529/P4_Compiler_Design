"""Evaluate the expression strings the IR carries, or REFUSE them by name.

The IR keeps expressions as strings (Assignment.rhs, IfStatement.condition,
ParserSelect.expression) in the SystemVerilog-flavoured form the ingesters
produce, and every emitter maps those strings to RTL. The reference model has
to evaluate the same strings over real values.

Written as a tokenizer plus a precedence-climbing parser rather than a
`re.sub` into Python and `eval`, for one reason that matters more than
elegance: this evaluator must be able to say "I do not know what this is".
A model that silently mis-evaluates an expression agrees with nothing and
reports PASS, which is worse than no model at all. Anything outside the
grammar below raises Unsupported, naming the construct, and the framework
reports that program as NOT VERIFIED instead of passing it.

Grammar, in the order precedence climbs:
    ++                      concatenation (P4's, width-summing)
    || && | ^ & == != < <= > >= << >> + - *
    unary ! ~ -
    postfix [hi:lo] [i]
    primary: N'hFF / N'd10 / N'b1 / 'hFF / 42 / N'(expr) / (expr)
             hdr.h.f / meta.f / standard_metadata.f / bare_name
             hdr.h.isValid()

Values are (value, width) pairs: width is tracked because P4 arithmetic wraps
at the field width, and a model that computed in Python's unbounded integers
would disagree with the RTL exactly where overflow is the interesting case.
"""
import re


class Unsupported(Exception):
    """An expression (or construct) this model cannot represent faithfully."""


_TOK = re.compile(r"""
    (?P<ws>\s+)
  | (?P<sized>\d+'[hdbo][0-9a-fA-FxXzZ_]+)
  | (?P<unsized>'[hdbo][0-9a-fA-F_]+)
  | (?P<cast>\d+'\s*\()
  | (?P<dec>\d+)
  | (?P<name>[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)
  | (?P<op><<|>>|<=|>=|==|!=|&&|\|\||\+\+|[-+*&|^~!()\[\]:,<>?/%])
""", re.X)


def tokenize(src):
    toks, pos = [], 0
    while pos < len(src):
        m = _TOK.match(src, pos)
        if not m:
            raise Unsupported(f'cannot tokenize {src[pos:pos+24]!r} in {src!r}')
        pos = m.end()
        kind = m.lastgroup
        if kind == 'ws':
            continue
        toks.append((kind, m.group()))
    toks.append(('end', ''))
    return toks


def _parse_literal(text):
    """N'hFF / N'd10 / 'hFF / 42  ->  (value, width)."""
    if "'" not in text:
        return int(text), max(1, int(text).bit_length())
    wpart, rest = text.split("'", 1)
    base, digits = rest[0].lower(), rest[1:].replace('_', '')
    if any(c in 'xXzZ' for c in digits):
        raise Unsupported(f"literal with x/z cannot be modelled: {text!r}")
    radix = {'h': 16, 'd': 10, 'b': 2, 'o': 8}[base]
    val = int(digits, radix)
    if wpart:
        width = int(wpart)
    else:
        width = {'h': 4 * len(digits), 'b': len(digits),
                 'o': 3 * len(digits), 'd': max(1, val.bit_length())}[base]
    return val & ((1 << width) - 1), width


# precedence: higher binds tighter
_BIN = {
    '++': 1,
    '||': 2, '&&': 3, '|': 4, '^': 5, '&': 6,
    '==': 7, '!=': 7,
    '<': 8, '<=': 8, '>': 8, '>=': 8,
    '<<': 9, '>>': 9,
    '+': 10, '-': 10,
    '*': 11,
}


class Evaluator:
    """env must provide lookup(path)->(val,width) and is_valid(hdr)->bool."""

    def __init__(self, env):
        self.env = env

    def eval(self, src):
        self.toks = tokenize(src)
        self.i = 0
        self.src = src
        v = self._expr(0)
        if self._peek()[0] != 'end':
            raise Unsupported(f'trailing {self._peek()[1]!r} in {src!r}')
        return v

    # ---- token helpers ----
    def _peek(self):
        return self.toks[self.i]

    def _next(self):
        t = self.toks[self.i]
        self.i += 1
        return t

    def _expect(self, text):
        k, v = self._next()
        if v != text:
            raise Unsupported(f'expected {text!r}, found {v!r} in {self.src!r}')

    # ---- grammar ----
    def _expr(self, min_prec):
        lhs = self._unary()
        while True:
            kind, text = self._peek()
            if kind != 'op' or text not in _BIN or _BIN[text] < min_prec:
                break
            self._next()
            rhs = self._expr(_BIN[text] + 1)
            lhs = self._apply(text, lhs, rhs)
        return lhs

    def _unary(self):
        kind, text = self._peek()
        if kind == 'op' and text in ('!', '~', '-'):
            self._next()
            v, w = self._unary()
            if text == '!':
                return (0 if v else 1), 1
            if text == '~':
                return (~v) & ((1 << w) - 1), w
            return (-v) & ((1 << w) - 1), w
        if kind == 'op' and text in ('?', '/', '%'):
            raise Unsupported(f'operator {text!r} is not modelled (in {self.src!r})')
        return self._postfix()

    def _postfix(self):
        v, w = self._primary()
        while True:
            kind, text = self._peek()
            if kind == 'op' and text == '[':
                self._next()
                hi, _ = self._expr(0)
                if self._peek()[1] == ':':
                    self._next()
                    lo, _ = self._expr(0)
                else:
                    lo = hi
                self._expect(']')
                if hi < lo:
                    raise Unsupported(f'reversed slice [{hi}:{lo}] in {self.src!r}')
                nw = hi - lo + 1
                v, w = (v >> lo) & ((1 << nw) - 1), nw
            elif kind == 'op' and text == '?':
                raise Unsupported(f'ternary ?: is not modelled (in {self.src!r})')
            else:
                return v, w

    def _primary(self):
        kind, text = self._next()
        if kind in ('sized', 'unsized', 'dec'):
            return _parse_literal(text)
        if kind == 'cast':                      # N'( expr )
            width = int(text.split("'")[0])
            v, _ = self._expr(0)
            self._expect(')')
            return v & ((1 << width) - 1), width
        if kind == 'op' and text == '(':
            v = self._expr(0)
            self._expect(')')
            return v
        if kind == 'name':
            # hdr.h.isValid() is the only call form modelled
            if self._peek()[1] == '(':
                self._next()
                self._expect(')')
                if text.endswith('.isValid'):
                    return (1 if self.env.is_valid(text[:-len('.isValid')]) else 0), 1
                raise Unsupported(f'call {text}() is not modelled')
            return self.env.lookup(text)
        raise Unsupported(f'unexpected {text!r} in {self.src!r}')

    def _apply(self, op, a, b):
        (av, aw), (bv, bw) = a, b
        if op == '++':
            return ((av << bw) | bv), aw + bw
        if op in ('==', '!='):
            return (1 if ((av == bv) == (op == '==')) else 0), 1
        if op in ('<', '<=', '>', '>='):
            r = {'<': av < bv, '<=': av <= bv, '>': av > bv, '>=': av >= bv}[op]
            return (1 if r else 0), 1
        if op == '&&':
            return (1 if (av and bv) else 0), 1
        if op == '||':
            return (1 if (av or bv) else 0), 1
        w = max(aw, bw)
        mask = (1 << w) - 1
        if op == '&':
            return (av & bv) & mask, w
        if op == '|':
            return (av | bv) & mask, w
        if op == '^':
            return (av ^ bv) & mask, w
        if op == '+':
            return (av + bv) & mask, w
        if op == '-':
            return (av - bv) & mask, w
        if op == '*':
            return (av * bv) & mask, w
        if op == '<<':
            return (av << bv) & mask, aw
        if op == '>>':
            return (av >> bv) & mask, aw
        raise Unsupported(f'operator {op!r} is not modelled')
