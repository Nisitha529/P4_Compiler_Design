import math
import os
import re

from ir import ActionParam

_STD_META_WIDTHS = {
    'egress_spec': 9, 'ingress_port': 9, 'egress_port': 9,
    'instance_type': 32, 'packet_length': 32, 'priority': 3,
    'mcast_grp': 16, 'egress_rid': 16, 'checksum_error': 1,
}


# ============================================================
# Helpers
# ============================================================

def _find_processing_ctrl(ir):
    if ir.pipeline.ingress is not None:
        return ir.pipeline.ingress
    _SKIP = {'parser', 'deparser', 'verify', 'compute', 'checksum'}
    for name, block in ir.controls.items():
        if not any(k in name.lower() for k in _SKIP):
            return block
    return None


def _build_field_width_map(ir):
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
    for mf in ir.metadata_fields:
        fwmap[f'meta_{mf.name}'] = mf.width
    # Control-local variables used as table keys (e.g. bit<16> table_key_sport)
    for block in ir.controls.values():
        for lv in block.local_vars:
            if lv.name not in fwmap:
                fwmap[lv.name] = lv.width
    return fwmap


def _key_width(key_field, fwmap):
    """Resolve a table key field width, handling standard_metadata.* and meta.* correctly."""
    m = re.match(r'^standard_metadata\.(\w+)$', key_field.strip())
    if m:
        return _STD_META_WIDTHS.get(m.group(1), 9)
    m = re.match(r'^meta\.(\w+)$', key_field.strip())
    if m:
        return fwmap.get(f'meta_{m.group(1)}', 32)
    return fwmap.get(_sig(key_field), 32)


def _sig(field_expr):
    s = field_expr.strip()
    s = re.sub(r'^hdr\.', '', s)
    s = re.sub(r'^meta\.', 'meta_', s)
    return s.replace('.', '_')


def _field_basename(field_expr):
    """Last component of a dotted field path: hdr.ipv4.dstAddr → dstAddr."""
    return field_expr.strip().split('.')[-1]


def _action_ids(table):
    """Return {action_name: int_id} with NoAction always 0."""
    ids = {}
    next_id = 1
    for raw in table.actions:
        name = raw.strip().rstrip('()')
        if name in ('NoAction',):
            ids[name] = 0
        else:
            if name not in ids:
                ids[name] = next_id
                next_id += 1
    if 'NoAction' not in ids:
        ids['NoAction'] = 0
    return ids


def _collect_params(table, amap):
    """Ordered list of (param_name, width) across all parameterised actions."""
    seen = {}
    for raw in table.actions:
        aname = raw.strip().rstrip('()')
        if aname == 'NoAction':
            continue
        action = amap.get(aname)
        if action is None:
            continue
        for p in action.params:
            if isinstance(p, ActionParam):
                pname, w = p.name, (p.width or 32)
            else:
                pname, w = str(p), 32
            if pname not in seen:
                seen[pname] = w
    return list(seen.items())


# ============================================================
# Single table emitter
# ============================================================

def _emit_one_table(ir, table, amap, fwmap, output_path):

    act_ids   = _action_ids(table)
    params    = _collect_params(table, amap)
    n_acts    = max(act_ids.values()) + 1
    act_id_w  = max(1, math.ceil(math.log2(n_acts))) if n_acts > 1 else 1

    # Determine table type from first key (default exact)
    match_type = table.keys[0].match_type if table.keys else 'exact'
    is_lpm     = (match_type == 'lpm')
    is_ternary = (match_type == 'ternary')

    depth = table.size if table.size else 1024

    with open(output_path, 'w') as f:

        # ── Module declaration ────────────────────────────────────────
        f.write(f'module {table.name}_table #(\n')
        f.write(f'  parameter int DEPTH = {depth}\n')
        f.write(') (\n')
        f.write('  input  logic clk,\n')
        f.write('  input  logic rst_n,\n')

        # Lookup key inputs
        f.write('\n  // Lookup key (combinational)\n')
        for key in table.keys:
            fname = _field_basename(key.field)
            w     = _key_width(key.field, fwmap)
            f.write(f'  input  logic [{w-1}:0] lkp_{fname},\n')

        # Lookup result outputs
        f.write('\n  // Lookup result\n')
        f.write('  output logic        hit,\n')
        f.write(f'  output logic [{act_id_w-1}:0] action_id,\n')

        for pname, pw in params:
            f.write(f'  output logic [{pw-1}:0] p_{pname},\n')

        # CP write port
        f.write('\n  // Control-plane write port (synchronous)\n')
        f.write('  input  logic        cp_wr_en,\n')
        idx_w = max(1, math.ceil(math.log2(depth))) if depth > 1 else 1
        f.write(f'  input  logic [{idx_w-1}:0] cp_wr_idx,\n')
        for key in table.keys:
            fname = _field_basename(key.field)
            w     = _key_width(key.field, fwmap)
            f.write(f'  input  logic [{w-1}:0] cp_wr_key_{fname},\n')
        if is_lpm:
            key_w = _key_width(table.keys[0].field, fwmap) if table.keys else 32
            pfx_w = max(1, math.ceil(math.log2(key_w + 1)))
            f.write(f'  input  logic [{pfx_w-1}:0] cp_wr_pfx_len,\n')
        elif is_ternary:
            for key in table.keys:
                fname = _field_basename(key.field)
                w     = _key_width(key.field, fwmap)
                f.write(f'  input  logic [{w-1}:0] cp_wr_mask_{fname},\n')
        f.write(f'  input  logic [{act_id_w-1}:0] cp_wr_action')
        if params:
            f.write(',\n')
            for i, (pname, pw) in enumerate(params):
                comma = ',' if i < len(params) - 1 else ''
                f.write(f'  input  logic [{pw-1}:0] cp_wr_p_{pname}{comma}\n')
        else:
            f.write('\n')
        f.write(');\n\n')

        # ── Entry storage ─────────────────────────────────────────────
        f.write('  // Entry storage\n')
        f.write(f'  logic        mem_valid  [0:DEPTH-1];\n')
        for key in table.keys:
            fname = _field_basename(key.field)
            w     = _key_width(key.field, fwmap)
            f.write(f'  logic [{w-1}:0] mem_key_{fname}[0:DEPTH-1];\n')
        if is_lpm:
            f.write(f'  logic [{pfx_w-1}:0] mem_pfx_len[0:DEPTH-1];\n')
        elif is_ternary:
            for key in table.keys:
                fname = _field_basename(key.field)
                w     = _key_width(key.field, fwmap)
                f.write(f'  logic [{w-1}:0] mem_mask_{fname}[0:DEPTH-1];\n')
        f.write(f'  logic [{act_id_w-1}:0] mem_action[0:DEPTH-1];\n')
        for pname, pw in params:
            f.write(f'  logic [{pw-1}:0] mem_p_{pname}[0:DEPTH-1];\n')
        f.write('\n')

        # ── CP write (synchronous) ────────────────────────────────────
        # Use initial block to zero mem_valid at simulation start
        # (avoids expensive loop on every reset edge for large tables)
        f.write('  integer _i;\n')
        f.write('  initial begin\n')
        f.write('    for (_i = 0; _i < DEPTH; _i = _i + 1)\n')
        f.write('      mem_valid[_i] = 1\'b0;\n')
        f.write('  end\n\n')
        f.write('  always_ff @(posedge clk) begin\n')
        f.write('    if (cp_wr_en) begin\n')
        f.write('      mem_valid[cp_wr_idx]  <= 1\'b1;\n')
        for key in table.keys:
            fname = _field_basename(key.field)
            f.write(f'      mem_key_{fname}[cp_wr_idx] <= cp_wr_key_{fname};\n')
        if is_lpm:
            f.write('      mem_pfx_len[cp_wr_idx] <= cp_wr_pfx_len;\n')
        elif is_ternary:
            for key in table.keys:
                fname = _field_basename(key.field)
                f.write(f'      mem_mask_{fname}[cp_wr_idx] <= cp_wr_mask_{fname};\n')
        f.write('      mem_action[cp_wr_idx] <= cp_wr_action;\n')
        for pname, _ in params:
            f.write(f'      mem_p_{pname}[cp_wr_idx] <= cp_wr_p_{pname};\n')
        f.write('    end\n')
        f.write('  end\n\n')

        # ── Combinational lookup ──────────────────────────────────────
        # Default action id when no match
        default_act_name = (table.default_action or 'NoAction').rstrip('()')
        default_act_id   = act_ids.get(default_act_name, 0)

        f.write('  // Combinational lookup\n')
        f.write('  // LPM: first-match wins; CP software should insert longest-prefix-first.\n')
        f.write('  always @(*) begin\n')
        f.write('    hit       = 1\'b0;\n')
        f.write(f'    action_id = {act_id_w}\'d{default_act_id};\n')
        for pname, pw in params:
            f.write(f'    p_{pname} = {pw}\'b0;\n')
        f.write('    for (int _j = 0; _j < DEPTH; _j++) begin\n')
        f.write('      if (!hit && mem_valid[_j]) begin\n')

        if is_lpm and table.keys:
            fname = _field_basename(table.keys[0].field)
            key_w = _key_width(table.keys[0].field, fwmap)
            # Shift-based LPM comparison: top pfx_len bits must match
            f.write(f'        if (mem_pfx_len[_j] == {pfx_w}\'d0 ||\n')
            f.write(f'            (lkp_{fname} >> ({key_w} - mem_pfx_len[_j])) ==\n')
            f.write(f'            (mem_key_{fname}[_j] >> ({key_w} - mem_pfx_len[_j]))) begin\n')
        elif is_ternary and table.keys:
            conditions = []
            for key in table.keys:
                fname = _field_basename(key.field)
                conditions.append(
                    f'(lkp_{fname} & mem_mask_{fname}[_j]) == '
                    f'(mem_key_{fname}[_j] & mem_mask_{fname}[_j])'
                )
            f.write('        if (' + ' &&\n            '.join(conditions) + ') begin\n')
        else:  # exact
            conditions = [f'lkp_{_field_basename(k.field)} == mem_key_{_field_basename(k.field)}[_j]'
                          for k in table.keys]
            f.write('        if (' + ' && '.join(conditions) + ') begin\n')

        f.write('          hit       = 1\'b1;\n')
        f.write('          action_id = mem_action[_j];\n')
        for pname, _ in params:
            f.write(f'          p_{pname} = mem_p_{pname}[_j];\n')
        f.write('        end\n')
        f.write('      end\n')
        f.write('    end\n')
        f.write('  end\n\n')

        # ── Action encoding comment ───────────────────────────────────
        f.write('  // Action ID encoding:\n')
        for aname, aid in sorted(act_ids.items(), key=lambda x: x[1]):
            f.write(f'  //   {aid} = {aname}\n')
        f.write('\n')

        f.write('endmodule\n')


# ============================================================
# Public entry point
# ============================================================

def emit_tables(ir, out_dir):
    """Generate one _table.sv per table in the processing control block."""
    ctrl = _find_processing_ctrl(ir)
    if ctrl is None:
        return
    amap  = {a.name: a for a in ctrl.actions}
    fwmap = _build_field_width_map(ir)
    for tbl in ctrl.tables:
        if not tbl.keys:
            continue
        out_path = os.path.join(out_dir, f'{tbl.name}_table.sv')
        _emit_one_table(ir, tbl, amap, fwmap, out_path)
        print(f'[SUCCESS] Table RTL      -> {out_path}')
