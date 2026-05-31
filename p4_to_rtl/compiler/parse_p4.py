import re


# ============================================================
# Utilities
# ============================================================

def strip_comments(src):
    src = re.sub(r'/\*.*?\*/', '', src, flags=re.DOTALL)
    src = re.sub(r'//[^\n]*', '', src)
    src = re.sub(r'#[^\n]*', '', src)   # strip C preprocessor lines
    return src


def find_matching_brace(src, pos):
    """Given '{' at pos, return (body_between_braces, closing_pos)."""
    assert src[pos] == '{', f"Expected '{{' at {pos}, got {src[pos]!r}"
    depth = 0
    for i in range(pos, len(src)):
        if src[i] == '{':
            depth += 1
        elif src[i] == '}':
            depth -= 1
            if depth == 0:
                return src[pos + 1:i], i
    raise ValueError(f"Unmatched '{{' at pos {pos}")


def find_matching_paren(src, pos):
    """Given '(' at pos, return (content, closing_pos)."""
    assert src[pos] == '(', f"Expected '(' at {pos}"
    depth = 0
    for i in range(pos, len(src)):
        if src[i] == '(':
            depth += 1
        elif src[i] == ')':
            depth -= 1
            if depth == 0:
                return src[pos + 1:i], i
    raise ValueError(f"Unmatched '(' at pos {pos}")


def split_top_level(s, sep, max_splits=None):
    """Split on sep only at paren/brace depth 0."""
    parts, current, depth, splits = [], [], 0, 0
    for ch in s:
        if ch in ('(', '[', '{'):
            depth += 1
        elif ch in (')', ']', '}'):
            depth -= 1
        if ch == sep and depth == 0 and (max_splits is None or splits < max_splits):
            parts.append(''.join(current).strip())
            current = []
            splits += 1
        else:
            current.append(ch)
    parts.append(''.join(current).strip())
    return parts


# ============================================================
# Type resolution
# ============================================================

def resolve_width(type_str, typedefs):
    """Resolve a P4 type expression to its bit width."""
    type_str = type_str.strip()
    for pat in [r'^bit\s*<\s*(\d+)\s*>$',
                r'^int\s*<\s*(\d+)\s*>$',
                r'^varbit\s*<\s*(\d+)\s*>$']:
        m = re.match(pat, type_str)
        if m:
            return int(m.group(1))
    if type_str == 'bool':
        return 1
    if type_str in typedefs:
        return resolve_width(typedefs[type_str], typedefs)
    return None


# ============================================================
# Field parsing  (header / struct bodies)
# ============================================================

def parse_fields(body, typedefs):
    """Return list of field dicts from a header or struct body."""
    fields = []
    for stmt in body.split(';'):
        stmt = stmt.strip()
        if not stmt:
            continue
        # "type_expr  field_name"  or  "type_expr  field_name[N]"
        m = re.match(r'^([\w<>\s]+?)\s+(\w+)(?:\[(\d+)\])?\s*$', stmt)
        if not m:
            continue
        type_str   = m.group(1).strip()
        field_name = m.group(2).strip()
        array_size = int(m.group(3)) if m.group(3) else None
        fields.append({
            'name':       field_name,
            'type':       type_str,
            'width':      resolve_width(type_str, typedefs),
            'array_size': array_size,
        })
    return fields


# ============================================================
# Parser state parsing
# ============================================================

def _parse_extract_calls(body):
    """Find all packet.extract() calls in a state body."""
    extracts = []
    for m in re.finditer(r'packet\.extract\s*\(', body):
        paren_pos = m.end() - 1
        try:
            args_str, _ = find_matching_paren(body, paren_pos)
        except (ValueError, AssertionError):
            continue
        args    = split_top_level(args_str, ',', max_splits=1)
        hdr_arg = args[0].strip()
        hm      = re.match(r'hdr\.(\w+)(?:\.next)?', hdr_arg)
        if not hm:
            continue
        length_expr = args[1].strip() if len(args) > 1 else None
        extracts.append({
            'header':      hm.group(1),
            'dynamic':     length_expr is not None,
            'length_expr': length_expr,
        })
    return extracts


def _parse_verify_calls(body):
    verifies = []
    for m in re.finditer(r'\bverify\s*\(', body):
        try:
            args_str, _ = find_matching_paren(body, m.end() - 1)
        except (ValueError, AssertionError):
            continue
        args = split_top_level(args_str, ',', max_splits=1)
        verifies.append({
            'condition': args[0].strip(),
            'error':     args[1].strip() if len(args) > 1 else None,
        })
    return verifies


def _parse_state_body(name, body):
    state = {
        'name':     name,
        'extracts': _parse_extract_calls(body),
        'verifies': _parse_verify_calls(body),
        'transition': None,
        'select':   None,
    }

    sel_m = re.search(r'\btransition\s+select\s*\(', body)
    if sel_m:
        paren_pos           = body.index('(', sel_m.start())
        expr_str, paren_end = find_matching_paren(body, paren_pos)
        brace_pos           = body.index('{', paren_end)
        sel_body, _         = find_matching_brace(body, brace_pos)

        cases, default_state = [], None
        for line in sel_body.split(';'):
            line = line.strip()
            if not line:
                continue
            cm = re.match(r'^(.*?)\s*:\s*(\w+)\s*$', line)
            if cm:
                key = cm.group(1).strip()
                val = cm.group(2).strip()
                if key in ('default', '_'):
                    default_state = val
                else:
                    cases.append((key, val))

        state['select'] = {
            'expr':    expr_str.strip(),
            'cases':   cases,
            'default': default_state,
        }
    else:
        tm = re.search(r'\btransition\s+(\w+)\s*;', body)
        if tm:
            state['transition'] = tm.group(1)

    return state


def parse_parser_block(body):
    """Return list of state dicts from inside a parser { } body."""
    states, pos = [], 0
    while pos < len(body):
        m = re.search(r'\bstate\s+(\w+)\s*\{', body[pos:])
        if not m:
            break
        name      = m.group(1)
        brace_abs = pos + m.start() + m.group(0).index('{')
        try:
            state_body, brace_end = find_matching_brace(body, brace_abs)
        except ValueError:
            break
        states.append(_parse_state_body(name, state_body))
        pos = brace_end + 1
    return states


# ============================================================
# Table / Action parsing
# ============================================================

def _parse_table_body(name, body):
    table = {
        'name':           name,
        'keys':           [],
        'actions':        [],
        'default_action': None,
        'size':           None,
    }

    km = re.search(r'\bkey\s*=\s*\{', body)
    if km:
        brace_pos   = body.index('{', km.start())
        key_body, _ = find_matching_brace(body, brace_pos)
        for line in key_body.split(';'):
            line = line.strip()
            if not line:
                continue
            fm = re.match(r'([\w.]+)\s*:\s*(\w+)', line)
            if fm:
                table['keys'].append({'field': fm.group(1), 'match_type': fm.group(2)})

    am = re.search(r'\bactions\s*=\s*\{', body)
    if am:
        brace_pos    = body.index('{', am.start())
        act_body, _  = find_matching_brace(body, brace_pos)
        for line in act_body.split(';'):
            line = line.strip()
            if line:
                table['actions'].append(line)

    dam = re.search(r'\bdefault_action\s*=\s*(\w+(?:\([^)]*\))?)\s*;', body)
    if dam:
        table['default_action'] = dam.group(1)

    szm = re.search(r'\bsize\s*=\s*(\d+)\s*;', body)
    if szm:
        table['size'] = int(szm.group(1))

    return table


def _parse_action_body(name, params_str, body):
    params = []
    for p in params_str.split(','):
        p = re.sub(r'^(in|out|inout)\s+', '', p.strip())
        pm = re.match(r'([\w<>]+)\s+(\w+)', p)
        if pm:
            params.append(pm.group(2))

    statements = []
    _KEYWORDS = {'if', 'else', 'for', 'while', 'switch', 'return'}

    # Assignments: lhs = rhs;
    for m in re.finditer(r'([\w.\[\]]+)\s*=\s*([^;{]+?)\s*;', body):
        lhs = m.group(1).strip()
        if lhs not in _KEYWORDS:
            statements.append({'type': 'assign', 'lhs': lhs, 'rhs': m.group(2).strip()})

    # No-argument calls: fn();  or  obj.method();
    for m in re.finditer(r'\b(\w+)\s*\(\s*\)\s*;', body):
        fn = m.group(1)
        if fn not in _KEYWORDS:
            statements.append({'type': 'call', 'name': fn})

    # Method calls with arguments: obj.method(args);
    for m in re.finditer(r'\b(\w+)\.(\w+)\s*\(([^)]+)\)\s*;', body):
        obj    = m.group(1)
        method = m.group(2)
        args   = [a.strip() for a in m.group(3).split(',') if a.strip()]
        if method not in _KEYWORDS:
            statements.append({
                'type': 'method_call',
                'obj': obj, 'method': method, 'args': args,
            })

    return {'name': name, 'params': params, 'body': statements}


# ============================================================
# Apply block parsing
# ============================================================

def _parse_single_or_block(body, pos):
    """Extract the body of a then / else clause starting at pos.

    If the next non-whitespace token is '{', returns the braced block.
    Otherwise collects a single statement up to and including the ';'.
    Returns (inner_body_str, end_pos).
    """
    while pos < len(body) and body[pos] in ' \t\n\r':
        pos += 1
    if pos >= len(body):
        return '', pos
    if body[pos] == '{':
        inner, end = find_matching_brace(body, pos)
        return inner, end + 1
    try:
        semi = body.index(';', pos)
        return body[pos:semi + 1], semi + 1
    except ValueError:
        return body[pos:], len(body)


def parse_apply_body(apply_body):
    """Recursively parse statements in an apply {} block.

    Recognises (with or without braces on then/else branches):
      - if / else / else-if chains
      - result = table.apply().field;
      - table.apply();
      - action_name();
      - lhs = rhs;   (local-variable assignments)
    """
    stmts  = []
    _SKIP  = {'isValid', 'setValid', 'setInvalid', 'push_front', 'pop_front'}
    pos    = 0

    while pos < len(apply_body):
        while pos < len(apply_body) and apply_body[pos] in ' \t\n\r':
            pos += 1
        if pos >= len(apply_body):
            break

        # ── if statement (with or without braces) ─────────────────────────────
        m = re.match(r'if\s*\(', apply_body[pos:])
        if m:
            paren_abs           = pos + apply_body[pos:].index('(')
            cond_str, paren_end = find_matching_paren(apply_body, paren_abs)
            then_body, new_pos  = _parse_single_or_block(apply_body, paren_end + 1)

            stmt = {
                'type':      'if',
                'condition': cond_str.strip(),
                'then':      parse_apply_body(then_body),
                'else':      [],
            }

            # Scan for optional else / else-if
            scan = new_pos
            while scan < len(apply_body) and apply_body[scan] in ' \t\n\r':
                scan += 1

            if re.match(r'else\s', apply_body[scan:]) or \
               (scan < len(apply_body) and apply_body[scan:scan+4] == 'else'):
                em = re.match(r'else\s*', apply_body[scan:])
                if em:
                    after_else = scan + em.end()

                    if re.match(r'if\s*\(', apply_body[after_else:]):
                        # else if: extract the full else-if block as a string
                        elif_paren = after_else + apply_body[after_else:].index('(')
                        elif_cond, elif_pend = find_matching_paren(apply_body, elif_paren)
                        elif_then, elif_end  = _parse_single_or_block(apply_body, elif_pend + 1)

                        elif_src = f'if ({elif_cond.strip()}) {{{elif_then}}}'

                        # look for a trailing else after the elif block
                        sc2 = elif_end
                        while sc2 < len(apply_body) and apply_body[sc2] in ' \t\n\r':
                            sc2 += 1
                        em2 = re.match(r'else\s*', apply_body[sc2:])
                        if em2:
                            trailing_else_start = sc2 + em2.end()
                            trail_body, trail_end = _parse_single_or_block(
                                apply_body, trailing_else_start)
                            elif_src += f' else {{{trail_body}}}'
                            elif_end  = trail_end

                        stmt['else'] = parse_apply_body(elif_src)
                        new_pos = elif_end
                    else:
                        # plain else
                        else_body, else_end = _parse_single_or_block(
                            apply_body, after_else)
                        stmt['else'] = parse_apply_body(else_body)
                        new_pos = else_end

            pos = new_pos
            stmts.append(stmt)
            continue

        # ── result = table.apply().field; ─────────────────────────────────────
        m = re.match(
            r'(\w+)\s*=\s*(\w+)\.apply\s*\(\s*\)\.(\w+)\s*;',
            apply_body[pos:])
        if m:
            stmts.append({
                'type':         'table_apply',
                'table':        m.group(2),
                'result_var':   m.group(1),
                'result_field': m.group(3),
            })
            pos += m.end()
            continue

        # ── table.apply(); ────────────────────────────────────────────────────
        m = re.match(r'(\w+)\.apply\s*\(\s*\)\s*;', apply_body[pos:])
        if m:
            stmts.append({'type': 'table_apply', 'table': m.group(1)})
            pos += m.end()
            continue

        # ── action_name(); ────────────────────────────────────────────────────
        m = re.match(r'(\w+)\s*\(\s*\)\s*;', apply_body[pos:])
        if m:
            fn = m.group(1)
            if fn not in _SKIP:
                stmts.append({'type': 'action_call', 'action': fn})
            pos += m.end()
            continue

        # ── assignment: lhs = rhs; ────────────────────────────────────────────
        m = re.match(r'([\w.\[\]]+)\s*=\s*([^;{]+?)\s*;', apply_body[pos:])
        if m:
            lhs = m.group(1).strip()
            if lhs not in {'if', 'else', 'return', 'while', 'for', 'switch'}:
                stmts.append({
                    'type': 'assign',
                    'lhs':  lhs,
                    'rhs':  m.group(2).strip(),
                })
                pos += m.end()
                continue

        pos += 1

    return stmts


# ============================================================
# Control block parsing
# ============================================================

def parse_control_block(body):
    result = {
        'tables':  [],
        'actions': [],
        'apply':   {'stmts': [], 'emits': []},
    }

    # Tables
    pos = 0
    while True:
        m = re.search(r'\btable\s+(\w+)\s*\{', body[pos:])
        if not m:
            break
        name      = m.group(1)
        brace_abs = pos + m.start() + m.group(0).index('{')
        tbl_body, brace_end = find_matching_brace(body, brace_abs)
        result['tables'].append(_parse_table_body(name, tbl_body))
        pos = brace_end + 1

    # Actions
    pos = 0
    while True:
        m = re.search(r'\baction\s+(\w+)\s*\((.*?)\)\s*\{', body[pos:])
        if not m:
            break
        name      = m.group(1)
        params    = m.group(2)
        brace_abs = pos + m.start() + m.group(0).rindex('{')
        act_body, brace_end = find_matching_brace(body, brace_abs)
        result['actions'].append(_parse_action_body(name, params, act_body))
        pos = brace_end + 1

    # Apply block
    am = re.search(r'\bapply\s*\{', body)
    if am:
        brace_pos          = body.index('{', am.start())
        apply_body, _      = find_matching_brace(body, brace_pos)
        result['apply']['stmts']  = parse_apply_body(apply_body)
        result['apply']['emits']  = [
            em.group(1)
            for em in re.finditer(r'packet\.emit\s*\(\s*hdr\.(\w+)\s*\)\s*;', apply_body)
        ]

    return result


# ============================================================
# Top-level entry point
# ============================================================

def parse_p4_file(filepath):
    with open(filepath, 'r') as f:
        src = f.read()

    src = strip_comments(src)

    result = {
        'typedefs': {},
        'consts':   {},
        'headers':  [],
        'structs':  [],
        'parser':   {'states': []},
        'controls': {},
        'pipeline': None,
    }

    typedefs = {}

    # 1. typedefs  ─  typedef bit<48> MacAddr;
    for m in re.finditer(r'\btypedef\s+([\w<>]+)\s+(\w+)\s*;', src):
        typedefs[m.group(2)] = m.group(1)
    result['typedefs'] = typedefs

    # 2. constants  ─  const bit<16> VLAN_TYPE = 0x8100;
    #    Store both value string and resolved bit width for SV literal generation.
    for m in re.finditer(r'\bconst\s+([\w<>]+)\s+(\w+)\s*=\s*([^;]+)\s*;', src):
        type_str = m.group(1).strip()
        name     = m.group(2).strip()
        val      = m.group(3).strip()
        w        = resolve_width(type_str, typedefs) or 32
        result['consts'][name] = {'value': val, 'width': w}

    # 3. header type definitions
    pos = 0
    while True:
        m = re.search(r'\bheader\s+(\w+)\s*\{', src[pos:])
        if not m:
            break
        name      = m.group(1)
        brace_abs = pos + m.start() + m.group(0).index('{')
        hdr_body, brace_end = find_matching_brace(src, brace_abs)
        result['headers'].append({'name': name, 'fields': parse_fields(hdr_body, typedefs)})
        pos = brace_end + 1

    # 4. struct definitions
    pos = 0
    while True:
        m = re.search(r'\bstruct\s+(\w+)\s*\{', src[pos:])
        if not m:
            break
        name      = m.group(1)
        brace_abs = pos + m.start() + m.group(0).index('{')
        struct_body, brace_end = find_matching_brace(src, brace_abs)
        fields = []
        for stmt in struct_body.split(';'):
            stmt = stmt.strip()
            if not stmt:
                continue
            fm = re.match(r'^([\w<>]+?)(?:\[(\d+)\])?\s+(\w+)\s*$', stmt)
            if fm:
                fields.append({
                    'name':       fm.group(3),
                    'type':       fm.group(1),
                    'array_size': int(fm.group(2)) if fm.group(2) else None,
                })
        result['structs'].append({'name': name, 'fields': fields})
        pos = brace_end + 1

    # 5. parser block
    pm = re.search(r'\bparser\s+\w+\s*\(', src)
    if pm:
        paren_pos            = src.index('(', pm.start())
        _, paren_end         = find_matching_paren(src, paren_pos)
        brace_pos            = src.index('{', paren_end)
        parser_body, _       = find_matching_brace(src, brace_pos)
        result['parser']['states'] = parse_parser_block(parser_body)

    # 6. control blocks
    pos = 0
    while True:
        m = re.search(r'\bcontrol\s+(\w+)\s*\(', src[pos:])
        if not m:
            break
        ctrl_name  = m.group(1)
        abs_start  = pos + m.start()
        paren_pos  = src.index('(', abs_start)
        _, par_end = find_matching_paren(src, paren_pos)
        brace_pos  = src.index('{', par_end)
        ctrl_body, brace_end = find_matching_brace(src, brace_pos)
        result['controls'][ctrl_name] = parse_control_block(ctrl_body)
        pos = brace_end + 1

    # 7. pipeline instantiation  ─  V1Switch(...) main;
    pipe_m = re.search(
        r'(V1Switch|XilinxPipeline)\s*\((.*?)\)\s*main\s*;', src, re.DOTALL
    )
    if pipe_m:
        args = [a.strip().rstrip('()') for a in pipe_m.group(2).split(',')]
        result['pipeline'] = {'arch': pipe_m.group(1), 'args': args}

    return result
