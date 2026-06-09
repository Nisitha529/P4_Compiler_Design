import re


def emit_pkg(ir, app_name, output_path):
    """Generate a SystemVerilog package with typedefs and localparams from IR."""

    with open(output_path, 'w') as f:
        f.write(f'package {app_name}_pkg;\n\n')

        if ir.typedefs:
            f.write('  // Typedefs\n')
            for alias, base_type in sorted(ir.typedefs.items()):
                w = _resolve_width(base_type, ir.typedefs)
                if w:
                    f.write(f'  typedef logic [{w-1}:0] {alias};\n')
            f.write('\n')

        if ir.consts:
            f.write('  // Constants\n')
            for name, entry in sorted(ir.consts.items()):
                if isinstance(entry, dict):
                    val_str = entry['value'].strip()
                    w       = entry.get('width', 32)
                else:
                    val_str = str(entry).strip()
                    w       = 32
                sv_val = _to_sv_literal(val_str, w)
                f.write(f'  localparam bit [{w-1}:0] {name} = {sv_val};\n')
            f.write('\n')

        f.write(f'endpackage : {app_name}_pkg\n')


def _resolve_width(type_str, typedefs, _depth=0):
    if _depth > 16:
        return None
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
        return _resolve_width(typedefs[type_str], typedefs, _depth + 1)
    return None


def _to_sv_literal(val_str, width):
    try:
        if val_str.startswith('0x') or val_str.startswith('0X'):
            iv     = int(val_str, 16)
            digits = max(1, (width + 3) // 4)
            return f"{width}'h{iv:0{digits}X}"
        iv = int(val_str)
        return f"{width}'d{iv}"
    except ValueError:
        return val_str
