"""
ingest_p4ir.py — Parse clean MidEnd P4 IR (from p4test --dump) into hardware IR.

Replaces the bmv2-JSON ingestion path for XSA/p4test-based compilation.
Produces the same ir.IR that the emit_*.py stages consume.
"""

import re
from ir import (
    IR, Header, HeaderField, HeaderInstance, MetadataField,
    ParserState, ParserSelect, Extract, Verify,
    Table, TableKey, Action, ActionParam, Assignment, ExternCall,
    ControlBlock, Deparser, LocalVar, RegisterDecl, CounterDecl,
    IfStatement, TableApply,
)


# ─────────────────────────────────────────────────────────────────────────────
# Text utilities
# ─────────────────────────────────────────────────────────────────────────────

def _strip_comments(text):
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.DOTALL)
    text = re.sub(r'//[^\n]*', '', text)
    return text


def _bit_width(type_str):
    """'bit<N>' → N (int), 'bool' → 1, else None."""
    t = type_str.strip()
    m = re.match(r'bit<(\d+)>$', t)
    if m:
        return int(m.group(1))
    if t == 'bool':
        return 1
    return None


def _find_block(text, brace_pos):
    """Return (inner, end_pos) for the {...} block whose opening { is at brace_pos."""
    depth = 0
    i = brace_pos
    while i < len(text):
        if text[i] == '{':
            depth += 1
        elif text[i] == '}':
            depth -= 1
            if depth == 0:
                return text[brace_pos + 1:i], i + 1
        i += 1
    return text[brace_pos + 1:], len(text)


def _read_matching_paren(text, open_pos):
    """Return (inner, end_pos) for the (...) block whose opening ( is at open_pos."""
    depth = 0
    i = open_pos
    while i < len(text):
        if text[i] == '(':
            depth += 1
        elif text[i] == ')':
            depth -= 1
            if depth == 0:
                return text[open_pos + 1:i], i + 1
        i += 1
    return text[open_pos + 1:], len(text)


def _p4_lit_to_sv(lit):
    """Convert a P4 numeric literal to SV: '16w0x8100' → \"16'h8100\", '8w6' → \"8'd6\"."""
    lit = lit.strip()
    m = re.match(r'^(\d+)w(0[xX][0-9a-fA-F]+)$', lit)
    if m:
        bits = int(m.group(1))
        val = int(m.group(2), 16)
        digits = max(1, (bits + 3) // 4)
        return f"{bits}'h{val:0{digits}X}"
    m = re.match(r'^(\d+)w(\d+)$', lit)
    if m:
        bits, val = int(m.group(1)), int(m.group(2))
        return f"{bits}'d{val}"
    return lit


def _sanitize_stack_idx(name):
    """
    Header-stack element syntax (hdr.vlan[0]) has no direct SV identifier
    equivalent -- 'vlan[0]' is not a legal signal-name fragment. Convert to
    'vlan_0', matching ingest_bmv2.py's own _sanitize_stack_idx() exactly
    (same fix, same naming convention, ported to this frontend's ingestion
    -- this file had no equivalent sanitization until a real, demonstrated
    bug (illegal 'vlan[0]_tpid'-shaped ports/wires in generated RTL) showed
    the gap). Only static, compile-time-constant indices ever reach here
    (P4-16 requires stack-element indices to be compile-time constants for
    this syntax; dynamic .next/.last indexing is a separate, deliberately
    unsupported feature -- see feedback_no_dynamic_header_stack).
    """
    return re.sub(r'\[(\d+)\]', r'_\1', name)


def _convert_expr(expr):
    """Convert P4 expression literals to SV-ready strings."""
    expr = expr.strip()
    # P4 boolean literals
    if expr == 'true':
        return "1'b1"
    if expr == 'false':
        return "1'b0"
    # P4 numeric literals (Nw0xHH or NwD)
    expr = re.sub(r'\b(\d+w(?:0[xX][0-9a-fA-F]+|\d+))',
                  lambda m: _p4_lit_to_sv(m.group(1)), expr)
    # Header-stack element syntax (hdr.vlan[0].tpid) -> hdr.vlan_0.tpid, so
    # every downstream consumer (emit_parser.py's/emit_processing.py's own
    # hdr.-stripping dot-to-underscore mapping) sees a plain dotted path,
    # never a bracket -- same "sanitize once, at ingestion" discipline
    # ingest_bmv2.py already uses.
    expr = _sanitize_stack_idx(expr)
    return expr


# ─────────────────────────────────────────────────────────────────────────────
# Annotation helpers
# ─────────────────────────────────────────────────────────────────────────────

# Matches one or more annotations: @hidden, @name("..."), @noWarn("..."), etc.
_ANN_PAT = r'(?:@\w+(?:\s*\([^)]*\))?\s*)*'


def _extract_name_annotation(ann_text):
    """
    Extract canonical name from @name("...") annotation.
    - Strips control-block prefix:  "MyProcessing.FiveTuple" → "FiveTuple"
    - Keeps field references intact: "hdr.ipv4.src"  → "hdr.ipv4.src"
    - Strips leading dot:           ".NoAction"      → "NoAction"
    """
    m = re.search(r'@name\s*\(\s*"([^"]+)"\s*\)', ann_text)
    if not m:
        return None
    name = m.group(1).lstrip('.')   # strip leading '.' for ".NoAction"
    # Only strip the qualifier if it is a control-block prefix, not a P4 field path
    _FIELD_PREFIXES = ('hdr.', 'meta.', 'standard_metadata.')
    if '.' in name and not any(name.startswith(p) for p in _FIELD_PREFIXES):
        name = name.rsplit('.', 1)[-1]
    return name or None


def _is_hidden(ann_text):
    # '@' is not a word character, so \b doesn't work here — use plain substring search
    return '@hidden' in ann_text


# ─────────────────────────────────────────────────────────────────────────────
# Header / struct parsing
# ─────────────────────────────────────────────────────────────────────────────

def _parse_header_types(text):
    """Return {type_name: Header} for all `header NAME { ... }` blocks."""
    result = {}
    for m in re.finditer(r'\bheader\s+(\w+)\s*\{', text):
        name = m.group(1)
        body, _ = _find_block(text, m.end() - 1)
        hdr = Header(name)
        for line in body.split(';'):
            line = line.strip()
            fm = re.match(r'(varbit|bit)<(\d+)>\s+(\w+)', line)
            if fm:
                w = int(fm.group(2))
                fname = fm.group(3)
                hdr.add_field(HeaderField(fname, w if w > 0 else None))
        result[name] = hdr
    return result


def _parse_structs(text, header_type_map):
    """Parse `struct headers { ... }` and `struct metadata { ... }`."""
    header_instances = []
    metadata_fields = []

    for m in re.finditer(r'\bstruct\s+(\w+)\s*\{', text):
        sname = m.group(1)
        body, _ = _find_block(text, m.end() - 1)

        if sname in ('headers', 'Headers'):
            for line in body.split(';'):
                line = line.strip()
                # TYPE[N] NAME;  (header stack) -- register N independent
                # instances (NAME_0..NAME_{N-1}), matching the fixed-size
                # unroll this compiler supports (N is a compile-time
                # constant from the array bound; dynamic .next/.last
                # indexing is a separate, deliberately unsupported feature
                # -- see feedback_no_dynamic_header_stack). Without this,
                # a stack-typed member matched NEITHER this branch NOR the
                # plain-header branch below (the '[' breaks \w+), so it was
                # silently registered as NO header instance at all -- a
                # real, previously-undiscovered gap distinct from (and
                # upstream of) the parser/deparser bracket-sanitization fix
                # in _convert_expr/_sanitize_stack_idx.
                sm = re.match(r'(\w+)\s*\[\s*(\d+)\s*\]\s+(\w+)', line)
                if sm:
                    type_name, size_str, inst_name = sm.group(1), sm.group(2), sm.group(3)
                    hdr_type = header_type_map.get(type_name)
                    if hdr_type:
                        for i in range(int(size_str)):
                            header_instances.append(
                                HeaderInstance(f'{inst_name}_{i}', type_name, hdr_type)
                            )
                    continue

                fm = re.match(r'(\w+)\s+(\w+)', line)
                if fm:
                    type_name, inst_name = fm.group(1), fm.group(2)
                    hdr_type = header_type_map.get(type_name)
                    if hdr_type:
                        header_instances.append(
                            HeaderInstance(inst_name, type_name, hdr_type)
                        )
        elif sname in ('metadata', 'Metadata', 'user_metadata_t'):
            for line in body.split(';'):
                line = line.strip()
                fm = re.match(r'bit<(\d+)>\s+(\w+)', line)
                if fm:
                    metadata_fields.append(MetadataField(fm.group(2), int(fm.group(1))))

    return header_instances, metadata_fields


# ─────────────────────────────────────────────────────────────────────────────
# Architecture detection
# ─────────────────────────────────────────────────────────────────────────────

def _detect_arch(text):
    if re.search(r'\bXilinxPipeline\s*<', text):
        return 'xsa'
    if re.search(r'\bV1Switch\s*<', text):
        return 'v1model'
    return 'unknown'


def _extract_control_names(text, arch):
    """
    Return (parser_name, ingress_name, deparser_name) from package instantiation.
    """
    if arch == 'xsa':
        m = re.search(
            r'XilinxPipeline\s*<[^>]*>\s*\(\s*(\w+)\s*\(\s*\)\s*,\s*(\w+)\s*\(\s*\)\s*,\s*(\w+)',
            text)
        if m:
            return m.group(1), m.group(2), m.group(3)
    elif arch == 'v1model':
        m = re.search(
            r'V1Switch\s*<[^>]*>\s*\(\s*(\w+)\s*\(\s*\)\s*,\s*\w+\s*\(\s*\)\s*,'
            r'\s*(\w+)\s*\(\s*\)\s*,\s*\w+\s*\(\s*\)\s*,\s*\w+\s*\(\s*\)\s*,\s*(\w+)',
            text)
        if m:
            return m.group(1), m.group(2), m.group(3)
    return None, None, None


# ─────────────────────────────────────────────────────────────────────────────
# Action parameter parser
# ─────────────────────────────────────────────────────────────────────────────

def _parse_action_params(params_text):
    """
    Parse `@name("X") bit<N> local_name, ...`
    Returns (list[ActionParam], {local_name: canonical_name}).
    """
    params = []
    name_map = {}

    # Split by ',' at depth 0
    parts, depth, current = [], 0, []
    for ch in params_text:
        if ch in '(<':
            depth += 1
            current.append(ch)
        elif ch in ')>':
            depth -= 1
            current.append(ch)
        elif ch == ',' and depth == 0:
            parts.append(''.join(current).strip())
            current = []
        else:
            current.append(ch)
    if current:
        parts.append(''.join(current).strip())

    for part in parts:
        part = part.strip()
        if not part:
            continue
        canon = _extract_name_annotation(part)
        # Strip all annotations
        clean = re.sub(r'@\w+(?:\s*\([^)]*\))?', '', part).strip()
        # Match: type local_name
        m = re.match(r'(bit<\d+>|bool|\w+(?:<[^>]*>)?)\s+(\w+)$', clean)
        if m:
            type_str = m.group(1)
            local_name = m.group(2)
            width = _bit_width(type_str)
            p_name = canon if canon else local_name
            params.append(ActionParam(p_name, type_str, width or 32))
            if local_name != p_name:
                name_map[local_name] = p_name

    return params, name_map


# ─────────────────────────────────────────────────────────────────────────────
# Action body parser
# ─────────────────────────────────────────────────────────────────────────────

def _subst_names(text, name_map):
    """Substitute all local names with canonical names (word-boundary safe)."""
    for local, canon in name_map.items():
        text = re.sub(r'\b' + re.escape(local) + r'\b', canon, text)
    return text


def _parse_action_body(body_text, name_map=None):
    """Parse action body into IR Assignment / ExternCall nodes."""
    nm = name_map or {}
    stmts = []

    for raw in body_text.split(';'):
        raw = raw.strip()
        if not raw:
            continue

        raw = _subst_names(raw, nm)

        # hdr.X.setValid() / hdr.X.setInvalid()
        m = re.match(r'(hdr\.\w+)\.(setValid|setInvalid)\s*\(\s*\)', raw)
        if m:
            stmts.append(ExternCall(f'{m.group(1)}.{m.group(2)}', []))
            continue

        # packet.emit<T>(hdr.X) — deparser only, skip in action
        if re.match(r'packet\s*\.\s*emit\s*<', raw):
            continue

        # verify(COND, ERROR) — skip
        if re.match(r'verify\s*\(', raw):
            continue

        # EXTERN.method(ARGS)
        m = re.match(r'(\w+)\s*\.\s*(\w+)\s*\(([^)]*)\)', raw)
        if m:
            obj, method, args_str = m.group(1), m.group(2), m.group(3)
            args = [_convert_expr(a.strip()) for a in args_str.split(',') if a.strip()]
            stmts.append(ExternCall(f'{obj}.{method}', args))
            continue

        # LHS = RHS  (skip == comparisons)
        m = re.match(r'(.+?)\s*=\s*(.+)', raw, re.DOTALL)
        if m and '==' not in m.group(0):
            lhs = _convert_expr(m.group(1).strip())
            rhs = _convert_expr(m.group(2).strip())
            stmts.append(Assignment(lhs, rhs))

    return stmts


# ─────────────────────────────────────────────────────────────────────────────
# Apply-block parser
# ─────────────────────────────────────────────────────────────────────────────

def _flatten(items):
    result = []
    for item in items:
        if isinstance(item, list):
            result.extend(_flatten(item))
        elif item is not None:
            result.append(item)
    return result


class _ApplyParser:
    """Recursive-descent parser for a P4 control apply block."""

    def __init__(self, text, real_tables, hidden_tables, name_map):
        self.text = text
        self.pos = 0
        self.real_tables = real_tables   # {local_name: Table}
        self.hidden_tables = hidden_tables  # {local_name: [stmts]}
        self.name_map = name_map

    def _skip_ws(self):
        while self.pos < len(self.text) and self.text[self.pos].isspace():
            self.pos += 1

    def _remaining(self):
        return self.text[self.pos:]

    def _read_parens(self):
        """Read balanced (...), advance pos past ')', return inner."""
        inner, end = _read_matching_paren(self.text, self.pos)
        self.pos = end
        return inner

    def _read_block(self):
        """Read balanced {...}, advance pos past '}', return inner."""
        inner, end = _find_block(self.text, self.pos)
        self.pos = end
        return inner

    def _read_to_semi(self):
        depth = 0
        start = self.pos
        while self.pos < len(self.text):
            ch = self.text[self.pos]
            if ch in '({[':
                depth += 1
            elif ch in ')}]':
                depth -= 1
            elif ch == ';' and depth == 0:
                result = self.text[start:self.pos].strip()
                self.pos += 1
                return result
            self.pos += 1
        return self.text[start:self.pos].strip()

    def _subst(self, s):
        return _subst_names(s, self.name_map)

    def parse_stmts(self):
        stmts = []
        while True:
            self._skip_ws()
            if self.pos >= len(self.text):
                break
            result = self._parse_one()
            if result is None:
                continue
            if isinstance(result, list):
                stmts.extend(result)
            else:
                stmts.append(result)
        return stmts

    def _parse_one(self):
        self._skip_ws()
        rest = self._remaining()
        if not rest:
            return None

        # if statement
        if re.match(r'if\s*\(', rest):
            return self._parse_if()

        # NAME.apply() as a standalone statement
        m = re.match(r'(\w+)\.apply\(\)', rest)
        if m:
            local_name = m.group(1)
            canon_name = self.name_map.get(local_name, local_name)
            self.pos += len(m.group())

            # consume optional .hit/.miss qualifier
            self._skip_ws()
            ext_m = re.match(r'\.\w+(?:\(\))?', self._remaining())
            if ext_m:
                self.pos += len(ext_m.group())

            # consume semicolon
            self._skip_ws()
            if self._remaining().startswith(';'):
                self.pos += 1

            if local_name in self.hidden_tables:
                return self.hidden_tables[local_name]
            elif local_name in self.real_tables:
                return TableApply(canon_name)
            return None

        # empty semicolons
        if rest.startswith(';'):
            self.pos += 1
            return None

        # Generic statement up to ';'
        stmt_text = self._read_to_semi()
        if not stmt_text:
            return None
        stmt_text = self._subst(stmt_text)

        # assignment (exclude == and !=)
        m = re.match(r'(.+?)\s*=\s*(.+)$', stmt_text, re.DOTALL)
        if m and '==' not in stmt_text and '!=' not in stmt_text:
            lhs = m.group(1).strip()
            rhs = _convert_expr(m.group(2).strip())
            return Assignment(lhs, rhs)

        # extern call as statement
        m = re.match(r'(\w+)\.(\w+)\s*\(([^)]*)\)', stmt_text)
        if m:
            obj = m.group(1)
            args = [_convert_expr(a.strip()) for a in m.group(3).split(',') if a.strip()]
            return ExternCall(f'{obj}.{m.group(2)}', args)

        return None

    def _parse_if(self):
        m = re.match(r'if\s*', self._remaining())
        self.pos += len(m.group())

        cond_inner = self._read_parens()
        cond_inner = self._subst(cond_inner)
        cond_inner = _convert_expr(cond_inner)

        self._skip_ws()
        then_inner = self._read_block()
        then_stmts = _ApplyParser(
            then_inner, self.real_tables, self.hidden_tables, self.name_map
        ).parse_stmts()

        if_stmt = IfStatement(cond_inner)
        for s in _flatten(then_stmts):
            if_stmt.add_then(s)

        self._skip_ws()
        if re.match(r'else[\s{]', self._remaining()):
            m = re.match(r'else\s*', self._remaining())
            self.pos += len(m.group())
            self._skip_ws()

            if re.match(r'if\s*\(', self._remaining()):
                nested = self._parse_if()
                for s in _flatten([nested]):
                    if_stmt.add_else(s)
            else:
                else_inner = self._read_block()
                else_stmts = _ApplyParser(
                    else_inner, self.real_tables, self.hidden_tables, self.name_map
                ).parse_stmts()
                for s in _flatten(else_stmts):
                    if_stmt.add_else(s)

        return if_stmt


# ─────────────────────────────────────────────────────────────────────────────
# Control body parser  (regex-first, annotation-aware)
# ─────────────────────────────────────────────────────────────────────────────

# Pattern for zero-or-more annotations preceding a keyword
_ANN = r'(?:@\w+(?:\s*\([^)]*\))?\s*)*'


def _collect_name_maps(body_text):
    """
    Pass-1: collect {local_name → canonical_name} from all annotated declarations
    in the control body (actions, tables, local vars, extern instances).
    """
    name_map = {}

    def _reg(local, ann_text):
        canon = _extract_name_annotation(ann_text) or local
        if local != canon:
            name_map[local] = canon

    # Actions: annotations + 'action NAME('
    for m in re.finditer(r'(' + _ANN + r')\baction\s+(\w+)\s*\(', body_text):
        _reg(m.group(2), m.group(1))

    # Tables: annotations + 'table NAME {'
    for m in re.finditer(r'(' + _ANN + r')\btable\s+(\w+)\s*\{', body_text):
        _reg(m.group(2), m.group(1))

    # Local variables: annotations + 'bit<N> NAME;' or 'bool NAME;'
    for m in re.finditer(r'(' + _ANN + r')\b(bit<\d+>|bool)\s+(\w+)\s*;', body_text):
        _reg(m.group(3), m.group(1))

    # Extern instances: annotations + 'TYPE<...>(...) NAME;'
    # Use [^;{]* for template args to handle nested <bit<N>> patterns
    for m in re.finditer(r'(' + _ANN + r')\b(\w+)\s*<[^;{]*>\s*\([^;{)]*\)\s+(\w+)\s*;', body_text):
        _reg(m.group(3), m.group(1))

    # Register instances: annotations + 'register<bit<N>>(N) NAME;'
    for m in re.finditer(r'(' + _ANN + r')\bregister\s*<[^;{]*>\s*\([^;{)]*\)\s+(\w+)\s*;', body_text):
        _reg(m.group(2), m.group(1))

    return name_map


def _parse_control_body(body_text, ctrl_name):
    """
    Returns (local_vars, registers, counters, actions, tables, apply_text, name_map).
    actions : [(local_name, Action, is_hidden)]
    tables  : [(local_name, Table|None, is_hidden, default_action_local_name)]
    """
    text = body_text
    local_vars = []
    registers = []
    counters = []
    actions_out = []
    tables_out = []
    apply_text = ''

    # ── Pass 1: Build name map ────────────────────────────────────────────────
    name_map = _collect_name_maps(text)

    # ── Find apply block ─────────────────────────────────────────────────────
    am = re.search(r'\bapply\s*\{', text)
    if am:
        brace_pos = text.index('{', am.start())
        apply_text, _ = _find_block(text, brace_pos)

    # ── Local variables ───────────────────────────────────────────────────────
    for m in re.finditer(r'(' + _ANN + r')\b(bit<(\d+)>|bool)\s+(\w+)\s*;', text):
        ann_text = m.group(1)
        type_str = m.group(2)
        local_name = m.group(4)
        width = _bit_width(type_str) or 1
        canon = _extract_name_annotation(ann_text) or local_name
        canon = name_map.get(local_name, canon)
        local_vars.append(LocalVar(canon, type_str, width))

    # ── Register externs ──────────────────────────────────────────────────────
    # Match: @ann register<bit<N>>(SIZE) name;  (nested <> handled by [^;{]*)
    for m in re.finditer(
        r'(' + _ANN + r')\bregister\s*<\s*bit<(\d+)>\s*>\s*\((\d+)\)\s+(\w+)\s*;', text
    ):
        ann_text = m.group(1)
        dw = int(m.group(2))
        sz = int(m.group(3))
        local_name = m.group(4)
        canon = _extract_name_annotation(ann_text) or local_name
        canon = name_map.get(local_name, canon)
        registers.append(RegisterDecl(canon, dw, sz))

    # ── Counter externs ──────────────────────────────────────────────────────
    # Match: @ann Counter<bit<W>, bit<S>>(N_COUNTERS, CounterType_t.TYPE) name;
    # By the time p4test's MidEnd dump reaches here, typedef'd index types and
    # const sizes are already resolved to literal bit<N>/digits, so no
    # constant-folding is needed here -- same as register's SIZE literal
    # above. One real difference confirmed against an actual dump, though:
    # the constructor's n_counters argument (typed bit<32> by the extern's
    # own signature) prints as a WIDTH-PREFIXED literal, e.g. `32w8192`, not
    # plain `8192` -- the optional `(?:\d+w)?` below strips that prefix.
    for m in re.finditer(
        r'(' + _ANN + r')\bCounter\s*<\s*bit<(\d+)>\s*,\s*bit<(\d+)>\s*>\s*'
        r'\(\s*(?:\d+w)?(\d+)\s*,\s*CounterType_t\.(\w+)\s*\)\s+(\w+)\s*;', text
    ):
        ann_text = m.group(1)
        dw = int(m.group(2))
        # group(3) = index width -- not stored; addr width is re-derived from
        # size downstream, the same way RegisterDecl's addr width is.
        n_counters = int(m.group(4))
        ctype = m.group(5)
        local_name = m.group(6)
        canon = _extract_name_annotation(ann_text) or local_name
        canon = name_map.get(local_name, canon)
        counters.append(CounterDecl(canon, dw, n_counters, ctype))

    # ── Actions ───────────────────────────────────────────────────────────────
    for m in re.finditer(r'(' + _ANN + r')\baction\s+(\w+)\s*\(', text):
        ann_text = m.group(1)
        local_name = m.group(2)
        hidden = _is_hidden(ann_text)
        canon = _extract_name_annotation(ann_text) or local_name
        canon = name_map.get(local_name, canon)

        # Find matching ')' for the params
        paren_open = text.index('(', m.end() - 1)
        params_inner, paren_end = _read_matching_paren(text, paren_open)
        params, param_nm = _parse_action_params(params_inner)

        # Find the action body
        brace_start = text.index('{', paren_end - 1)
        body, _ = _find_block(text, brace_start)

        full_nm = {**name_map, **param_nm}
        action = Action(canon)
        for p in params:
            action.add_param(p)
        for stmt in _parse_action_body(body, full_nm):
            action.add_statement(stmt)

        actions_out.append((local_name, action, hidden))

    # ── Tables ────────────────────────────────────────────────────────────────
    for m in re.finditer(r'(' + _ANN + r')\btable\s+(\w+)\s*\{', text):
        ann_text = m.group(1)
        local_name = m.group(2)
        hidden = _is_hidden(ann_text)
        canon = _extract_name_annotation(ann_text) or local_name
        canon = name_map.get(local_name, canon)

        brace_start = text.index('{', m.end() - 1)
        tbl_body, _ = _find_block(text, brace_start)

        if hidden:
            da_m = re.search(r'\bdefault_action\s*=\s*(\w+)\s*\(\s*\)', tbl_body)
            default_action = da_m.group(1) if da_m else None
            tables_out.append((local_name, None, True, default_action))
        else:
            tbl = Table(canon)

            # key = { ... }
            key_m = re.search(r'\bkey\s*=\s*\{([^}]*)\}', tbl_body, re.DOTALL)
            if key_m:
                for key_line in key_m.group(1).split(';'):
                    key_line = key_line.strip()
                    if not key_line:
                        continue
                    # FIELD : MATCH_TYPE  @name("canonical")
                    km = re.match(r'([^:]+)\s*:\s*(\w+)(.*)', key_line)
                    if km:
                        raw_field = km.group(1).strip()
                        match_type = km.group(2).strip()
                        rest_ann = km.group(3)
                        # Prefer @name annotation for field reference
                        canon_field = _extract_name_annotation(rest_ann)
                        if canon_field:
                            field = canon_field
                        else:
                            # Substitute local names in field
                            field = _subst_names(raw_field, name_map)
                        tbl.add_key(TableKey(field, match_type))

            # actions = { ... }
            act_m = re.search(r'\bactions\s*=\s*\{([^}]*)\}', tbl_body, re.DOTALL)
            if act_m:
                for aline in act_m.group(1).split(';'):
                    aname = aline.strip().rstrip('()').strip()
                    if aname:
                        aname_canon = name_map.get(aname, aname)
                        tbl.add_action(aname_canon)

            # size
            size_m = re.search(r'\bsize\s*=\s*(\d+)', tbl_body)
            if size_m:
                tbl.set_size(int(size_m.group(1)))

            # default_action
            da_m = re.search(r'\bdefault_action\s*=\s*(\w+)\s*\(\s*\)', tbl_body)
            if da_m:
                tbl.set_default(name_map.get(da_m.group(1), da_m.group(1)))

            tables_out.append((local_name, tbl, False, None))

    return local_vars, registers, counters, actions_out, tables_out, apply_text, name_map


# ─────────────────────────────────────────────────────────────────────────────
# Top-level block finders
# ─────────────────────────────────────────────────────────────────────────────

def _find_control_body(text, ctrl_name):
    m = re.search(r'\bcontrol\s+' + re.escape(ctrl_name) + r'\s*\([^)]*\)\s*\{', text)
    if not m:
        return None
    brace_pos = text.index('{', m.start())
    body, _ = _find_block(text, brace_pos)
    return body


def _find_parser_body(text, parser_name):
    m = re.search(r'\bparser\s+' + re.escape(parser_name) + r'\s*\([^)]*\)\s*\{', text)
    if not m:
        return None
    brace_pos = text.index('{', m.start())
    body, _ = _find_block(text, brace_pos)
    return body


# ─────────────────────────────────────────────────────────────────────────────
# Parser state parser
# ─────────────────────────────────────────────────────────────────────────────

def _parse_parser_states(body_text):
    """Parse all `state NAME { ... }` blocks → {name: ParserState}."""
    states = {}

    for m in re.finditer(r'\bstate\s+(\w+)\s*\{', body_text):
        sname = m.group(1)
        body, _ = _find_block(body_text, m.end() - 1)
        state = ParserState(sname)

        # packet.extract<TYPE>(hdr.FIELD)  or  packet.extract<TYPE>(hdr.FIELD, LEN)
        for em in re.finditer(r'packet\s*\.\s*extract\s*<\s*(\w+)\s*>\s*\(([^)]*)\)', body):
            args_str = em.group(2)
            args = [a.strip() for a in args_str.split(',')]
            hdr_ref = args[0]
            hdr_field = hdr_ref.split('.')[-1] if '.' in hdr_ref else hdr_ref
            hdr_field = _sanitize_stack_idx(hdr_field)
            is_dynamic = len(args) > 1
            len_expr = _convert_expr(args[1]) if is_dynamic else None
            state.add_extract(Extract(hdr_field, dynamic=is_dynamic, length_expr=len_expr))

        # verify(COND, ERROR)
        for vm in re.finditer(r'verify\s*\(([^;]+)\)', body):
            state.add_verify(Verify(vm.group(1).strip()))

        # transition select(...) { cases }
        sel_m = re.search(r'\btransition\s+select\s*\(([^)]+)\)\s*\{', body)
        if sel_m:
            sel_expr = _convert_expr(sel_m.group(1).strip())
            brace_pos = body.index('{', sel_m.start())
            sel_body, _ = _find_block(body, brace_pos)
            sel = ParserSelect(sel_expr)
            for line in sel_body.split(';'):
                line = line.strip()
                if not line:
                    continue
                cm = re.match(r'(.+?)\s*:\s*(\w+)', line)
                if cm:
                    val = _convert_expr(cm.group(1).strip())
                    dst = cm.group(2).strip()
                    if val == 'default':
                        sel.set_default(dst)
                    else:
                        sel.add_case(val, dst)
            state.set_select(sel)
        else:
            tm = re.search(r'\btransition\s+(\w+)\s*;', body)
            if tm:
                state.set_transition(tm.group(1))

        states[sname] = state

    return states


# ─────────────────────────────────────────────────────────────────────────────
# Deparser parser
# ─────────────────────────────────────────────────────────────────────────────

def _parse_deparser(body_text):
    """Extract emit list from deparser control body."""
    emit_list = []
    # (\w+(?:\[\d+\])?) also matches a header-stack element (hdr.vlan[0]) --
    # without this the whole packet.emit(hdr.vlan[0]) statement silently
    # failed to match at all (finditer just skips it, no error), a real,
    # previously-undiscovered bug: emitting a stack element was silently
    # dropped from the deparser entirely, not just misnamed.
    for m in re.finditer(r'packet\s*\.\s*emit\s*<[^>]*>\s*\(\s*hdr\.(\w+(?:\[\d+\])?)\s*\)', body_text):
        emit_list.append(_sanitize_stack_idx(m.group(1)))
    return emit_list


# ─────────────────────────────────────────────────────────────────────────────
# Main entry point
# ─────────────────────────────────────────────────────────────────────────────

def ingest_p4ir(p4_text: str) -> IR:
    """Parse MidEnd P4 IR text → hardware IR."""
    ir = IR()
    text = _strip_comments(p4_text)

    # 1. Header types
    header_type_map = _parse_header_types(text)
    for hdr in header_type_map.values():
        ir.add_header(hdr)

    # 2. Struct definitions
    hdr_instances, meta_fields = _parse_structs(text, header_type_map)
    for inst in hdr_instances:
        ir.add_header_instance(inst)
    for mf in meta_fields:
        ir.add_metadata_field(mf)

    # 3. Architecture + control names
    arch = _detect_arch(text)
    parser_name, ingress_name, deparser_name = _extract_control_names(text, arch)
    if not parser_name:
        parser_name, ingress_name, deparser_name = 'MyParser', 'MyProcessing', 'MyDeparser'

    # 4. Parser states
    parser_body = _find_parser_body(text, parser_name)
    if parser_body:
        for state in _parse_parser_states(parser_body).values():
            ir.add_parser_state(state)
        if 'start' in ir.parser_states:
            ir.set_start_state('start')

    # 5. Match-action control (ingress)
    ctrl_body = _find_control_body(text, ingress_name)
    if ctrl_body:
        local_vars, registers, counters, actions_raw, tables_raw, apply_text, name_map = \
            _parse_control_body(ctrl_body, ingress_name)

        ctrl = ControlBlock(ingress_name)

        for lv in local_vars:
            ctrl.add_local_var(lv)

        for reg in registers:
            ctrl.add_register(reg)

        for cnt in counters:
            ctrl.add_counter(cnt)

        # Build action lookup dicts
        actions_by_local = {}
        actions_by_canon = {}
        for (local_name, action, _hidden) in actions_raw:
            actions_by_local[local_name] = action
            actions_by_canon[action.name] = action
            ctrl.add_action(action)
            ir.add_action(action)

        # Build table maps
        real_tables = {}     # local_name → Table
        hidden_tables = {}   # local_name → [stmts]

        for (local_name, table_or_none, is_hidden, default_action_name) in tables_raw:
            if is_hidden:
                if default_action_name:
                    act = (actions_by_local.get(default_action_name)
                           or actions_by_canon.get(default_action_name)
                           or actions_by_local.get(name_map.get(default_action_name, ''))
                           or actions_by_canon.get(name_map.get(default_action_name, '')))
                    hidden_tables[local_name] = list(act.body) if act else []
                else:
                    hidden_tables[local_name] = []
            else:
                real_tables[local_name] = table_or_none
                ctrl.add_table(table_or_none)
                ir.add_table(table_or_none)

        # Parse apply block
        if apply_text:
            ap = _ApplyParser(apply_text, real_tables, hidden_tables, name_map)
            for stmt in ap.parse_stmts():
                ctrl.add_statement(stmt)

        ir.add_control(ctrl)
        ir.set_pipeline_stage('ingress', ctrl)

    # 6. Deparser
    dep_body = _find_control_body(text, deparser_name)
    if dep_body:
        dep = Deparser()
        for hdr_name in _parse_deparser(dep_body):
            dep.emit_list.append(hdr_name)
        ir.set_pipeline_stage('deparser', dep)

    return ir
