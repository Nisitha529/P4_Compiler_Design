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

    if not is_lpm and not is_ternary:
        _emit_exact_match_table(table, act_ids, params, act_id_w, depth, fwmap, output_path)
        return

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

        # ── Combinational lookup: balanced priority-match tree ──────────
        # Each entry's match condition only depends on its own storage, so
        # the DEPTH comparisons are already independent (O(1) depth each).
        # The old version picked the winner with a `for` loop threading
        # `!hit` through every iteration -- an O(DEPTH) *serial* priority
        # chain. This reduces the same DEPTH leaf comparisons with a
        # balanced binary tree instead (log2(DEPTH) levels), keeping the
        # exact same "lowest index wins" semantics (CP software still
        # inserts longest-prefix-first for LPM) with a bounded, depth-
        # independent critical path.
        f.write('  // Priority-match reduction: balanced binary tree (log2(DEPTH) levels)\n')
        f.write('  // instead of a serial DEPTH-deep priority chain. Lowest index still wins.\n')

        f.write(f'  logic        hit_l0[0:{depth-1}];\n')
        f.write(f'  logic [{act_id_w-1}:0] act_l0[0:{depth-1}];\n')
        for pname, pw in params:
            f.write(f'  logic [{pw-1}:0] p_{pname}_l0[0:{depth-1}];\n')
        f.write('\n')

        for j in range(depth):
            # NOTE: array elements are pulled out into their own named wire
            # before use, rather than inlined directly into the match
            # expression below. Inlining (e.g. `mem_pfx_len[j]` referenced
            # three times inline inside one `assign`) reproducibly corrupts
            # Icarus Verilog's vvp code generator on parameterized-DEPTH
            # register arrays (confirmed via minimal repro, iverilog 11.0) —
            # this is a simulator code-gen bug, not a synthesis issue, but
            # the workaround is free so it stays in unconditionally.
            if is_lpm and table.keys:
                fname = _field_basename(table.keys[0].field)
                key_w = _key_width(table.keys[0].field, fwmap)
                f.write(f'  logic [{pfx_w-1}:0] _pfx_{j}; assign _pfx_{j} = mem_pfx_len[{j}];\n')
                f.write(f'  logic [{key_w-1}:0] _key_{j}; assign _key_{j} = mem_key_{fname}[{j}];\n')
                cond = (f'(_pfx_{j} == {pfx_w}\'d0 || '
                        f'(lkp_{fname} >> ({key_w} - _pfx_{j})) == '
                        f'(_key_{j} >> ({key_w} - _pfx_{j})))')
            elif is_ternary and table.keys:
                conds = []
                for key in table.keys:
                    kfname = _field_basename(key.field)
                    kw = _key_width(key.field, fwmap)
                    f.write(f'  logic [{kw-1}:0] _key_{kfname}_{j}; assign _key_{kfname}_{j} = mem_key_{kfname}[{j}];\n')
                    f.write(f'  logic [{kw-1}:0] _msk_{kfname}_{j}; assign _msk_{kfname}_{j} = mem_mask_{kfname}[{j}];\n')
                    conds.append(f'((lkp_{kfname} & _msk_{kfname}_{j}) == (_key_{kfname}_{j} & _msk_{kfname}_{j}))')
                cond = ' && '.join(conds)
            else:  # exact (unused here, but kept for completeness)
                conds = [f'(lkp_{_field_basename(k.field)} == mem_key_{_field_basename(k.field)}[{j}])'
                         for k in table.keys]
                cond = ' && '.join(conds)
            f.write(f'  assign hit_l0[{j}] = mem_valid[{j}] && {cond};\n')
            f.write(f'  assign act_l0[{j}] = mem_action[{j}];\n')
            for pname, _ in params:
                f.write(f'  assign p_{pname}_l0[{j}] = mem_p_{pname}[{j}];\n')
        f.write('\n')

        prev_n, level = depth, 0
        while prev_n > 1:
            nxt_n = (prev_n + 1) // 2
            f.write(f'  logic        hit_l{level+1}[0:{nxt_n-1}];\n')
            f.write(f'  logic [{act_id_w-1}:0] act_l{level+1}[0:{nxt_n-1}];\n')
            for pname, pw in params:
                f.write(f'  logic [{pw-1}:0] p_{pname}_l{level+1}[0:{nxt_n-1}];\n')
            for i in range(nxt_n):
                left, right = 2 * i, 2 * i + 1
                if right < prev_n:
                    f.write(f'  assign hit_l{level+1}[{i}] = hit_l{level}[{left}] || hit_l{level}[{right}];\n')
                    f.write(f'  assign act_l{level+1}[{i}] = hit_l{level}[{left}] ? '
                            f'act_l{level}[{left}] : act_l{level}[{right}];\n')
                    for pname, _ in params:
                        f.write(f'  assign p_{pname}_l{level+1}[{i}] = hit_l{level}[{left}] ? '
                                f'p_{pname}_l{level}[{left}] : p_{pname}_l{level}[{right}];\n')
                else:
                    f.write(f'  assign hit_l{level+1}[{i}] = hit_l{level}[{left}];\n')
                    f.write(f'  assign act_l{level+1}[{i}] = act_l{level}[{left}];\n')
                    for pname, _ in params:
                        f.write(f'  assign p_{pname}_l{level+1}[{i}] = p_{pname}_l{level}[{left}];\n')
            f.write('\n')
            prev_n, level = nxt_n, level + 1

        f.write(f'  assign hit       = hit_l{level}[0];\n')
        f.write(f'  assign action_id = hit_l{level}[0] ? act_l{level}[0] : {act_id_w}\'d{default_act_id};\n')
        for pname, pw in params:
            f.write(f'  assign p_{pname} = hit_l{level}[0] ? p_{pname}_l{level}[0] : {pw}\'b0;\n')
        f.write('\n')

        # ── Action encoding comment ───────────────────────────────────
        f.write('  // Action ID encoding:\n')
        for aname, aid in sorted(act_ids.items(), key=lambda x: x[1]):
            f.write(f'  //   {aid} = {aname}\n')
        f.write('\n')

        f.write('endmodule\n')


# ============================================================
# Exact-match table: hash-indexed BRAM lookup, fixed 1-cycle latency
# ============================================================
#
# The old exact-match implementation was a fully-unrolled combinational
# scan over all DEPTH entries (see git history) — DEPTH parallel wide
# comparators resolved in zero clock cycles. That is not synthesizable
# at any real frequency once DEPTH grows past a handful of entries.
#
# This version XOR-folds the concatenated key down to an IDX_W-bit
# address, uses it directly as a BRAM index (synthesis tools infer
# block RAM from the mem_* arrays), and verifies the read with a tag
# compare against the stored key to detect hash collisions. Lookup
# latency is a constant 1 cycle regardless of DEPTH.
#
# Known limitation: this is a direct-mapped hash table (no chaining /
# no multi-way associativity). A control-plane write whose key hashes
# to an already-occupied slot silently overwrites that slot. Choose
# DEPTH with enough headroom over the expected live-entry count to
# keep collision probability low; a d-way associative version is the
# natural follow-up if collisions become a problem in practice.

def _emit_exact_match_table(table, act_ids, params, act_id_w, depth, fwmap, output_path):
    idx_w = max(1, math.ceil(math.log2(depth))) if depth > 1 else 1

    key_fields = [(_field_basename(k.field), _key_width(k.field, fwmap)) for k in table.keys]
    key_w      = sum(w for _, w in key_fields)
    n_chunks   = max(1, math.ceil(key_w / idx_w))
    padded_w   = n_chunks * idx_w

    default_act_name = (table.default_action or 'NoAction').rstrip('()')
    default_act_id   = act_ids.get(default_act_name, 0)

    def _concat(prefix):
        # table.keys order, MSB-first concat — must match between write-side and read-side calls
        return ', '.join(f'{prefix}{fname}' for fname, _ in reversed(key_fields))

    with open(output_path, 'w') as f:
        f.write(f'module {table.name}_table #(\n')
        f.write(f'  parameter int DEPTH = {depth}\n')
        f.write(') (\n')
        f.write('  input  logic clk,\n')
        f.write('  input  logic rst_n,\n')

        f.write('\n  // Lookup key (combinational)\n')
        for fname, w in key_fields:
            f.write(f'  input  logic [{w-1}:0] lkp_{fname},\n')

        f.write('\n  // Lookup result (registered — 1 cycle after lkp_* is presented)\n')
        f.write('  output logic        hit,\n')
        f.write(f'  output logic [{act_id_w-1}:0] action_id,\n')
        for pname, pw in params:
            f.write(f'  output logic [{pw-1}:0] p_{pname},\n')

        f.write('\n  // Control-plane write port (synchronous)\n')
        f.write('  input  logic        cp_wr_en,\n')
        f.write(f'  input  logic [{idx_w-1}:0] cp_wr_idx,  // unused: exact-match tables self-address via hash(key)\n')
        for fname, w in key_fields:
            f.write(f'  input  logic [{w-1}:0] cp_wr_key_{fname},\n')
        f.write(f'  input  logic [{act_id_w-1}:0] cp_wr_action')
        if params:
            f.write(',\n')
            for i, (pname, pw) in enumerate(params):
                comma = ',' if i < len(params) - 1 else ''
                f.write(f'  input  logic [{pw-1}:0] cp_wr_p_{pname}{comma}\n')
        else:
            f.write('\n')
        f.write(');\n\n')

        f.write('  // Entry storage (synthesizes to block RAM)\n')
        f.write('  logic        mem_valid  [0:DEPTH-1];\n')
        for fname, w in key_fields:
            f.write(f'  logic [{w-1}:0] mem_key_{fname}[0:DEPTH-1];\n')
        f.write(f'  logic [{act_id_w-1}:0] mem_action[0:DEPTH-1];\n')
        for pname, pw in params:
            f.write(f'  logic [{pw-1}:0] mem_p_{pname}[0:DEPTH-1];\n')
        f.write('\n')

        f.write('  integer _i;\n')
        f.write('  initial begin\n')
        f.write('    for (_i = 0; _i < DEPTH; _i = _i + 1)\n')
        f.write('      mem_valid[_i] = 1\'b0;\n')
        f.write('  end\n\n')

        f.write(f'  // XOR-fold hash: {key_w}-bit key -> {idx_w}-bit BRAM address\n')
        f.write(f'  function automatic logic [{idx_w-1}:0] hash_key(input logic [{padded_w-1}:0] k);\n')
        f.write(f'    logic [{idx_w-1}:0] h;\n')
        f.write('    integer c;\n')
        f.write('    begin\n')
        f.write("      h = '0;\n")
        f.write(f'      for (c = 0; c < {n_chunks}; c = c + 1)\n')
        f.write(f'        h = h ^ k[c*{idx_w} +: {idx_w}];\n')
        f.write('      hash_key = h;\n')
        f.write('    end\n')
        f.write('  endfunction\n\n')

        f.write(f'  logic [{padded_w-1}:0] wr_key_concat;\n')
        f.write(f'  assign wr_key_concat = {{{padded_w - key_w}\'d0, {_concat("cp_wr_key_")}}};\n' if padded_w > key_w
                else f'  assign wr_key_concat = {{{_concat("cp_wr_key_")}}};\n')
        f.write(f'  logic [{idx_w-1}:0] wr_addr;\n')
        f.write('  assign wr_addr = hash_key(wr_key_concat);\n\n')

        f.write(f'  logic [{padded_w-1}:0] lkp_key_concat;\n')
        f.write(f'  assign lkp_key_concat = {{{padded_w - key_w}\'d0, {_concat("lkp_")}}};\n' if padded_w > key_w
                else f'  assign lkp_key_concat = {{{_concat("lkp_")}}};\n')
        f.write(f'  logic [{idx_w-1}:0] lkp_addr;\n')
        f.write('  assign lkp_addr = hash_key(lkp_key_concat);\n\n')

        f.write('  // Synchronous write (control plane)\n')
        f.write('  always_ff @(posedge clk) begin\n')
        f.write('    if (cp_wr_en) begin\n')
        f.write('      mem_valid[wr_addr]  <= 1\'b1;\n')
        for fname, _ in key_fields:
            f.write(f'      mem_key_{fname}[wr_addr] <= cp_wr_key_{fname};\n')
        f.write('      mem_action[wr_addr] <= cp_wr_action;\n')
        for pname, _ in params:
            f.write(f'      mem_p_{pname}[wr_addr] <= cp_wr_p_{pname};\n')
        f.write('    end\n')
        f.write('  end\n\n')

        f.write('  // Registered BRAM read + tag-compare stage (1-cycle lookup latency)\n')
        f.write('  logic        valid_r;\n')
        for fname, w in key_fields:
            f.write(f'  logic [{w-1}:0] key_r_{fname};\n')
            f.write(f'  logic [{w-1}:0] mem_key_r_{fname};\n')
        f.write(f'  logic [{act_id_w-1}:0] action_id_r;\n')
        for pname, pw in params:
            f.write(f'  logic [{pw-1}:0] p_r_{pname};\n')
        f.write('\n')

        f.write('  always_ff @(posedge clk) begin\n')
        f.write('    if (!rst_n) begin\n')
        f.write('      valid_r <= 1\'b0;\n')
        f.write('    end else begin\n')
        f.write('      valid_r     <= mem_valid[lkp_addr];\n')
        for fname, _ in key_fields:
            f.write(f'      key_r_{fname}     <= lkp_{fname};\n')
            f.write(f'      mem_key_r_{fname} <= mem_key_{fname}[lkp_addr];\n')
        f.write('      action_id_r <= mem_action[lkp_addr];\n')
        for pname, _ in params:
            f.write(f'      p_r_{pname} <= mem_p_{pname}[lkp_addr];\n')
        f.write('    end\n')
        f.write('  end\n\n')

        tag_match = ' && '.join(f'(mem_key_r_{fname} == key_r_{fname})' for fname, _ in key_fields) or "1'b1"
        f.write(f'  assign hit       = valid_r && {tag_match};\n')
        f.write(f'  assign action_id = hit ? action_id_r : {act_id_w}\'d{default_act_id};\n')
        for pname, pw in params:
            f.write(f'  assign p_{pname} = hit ? p_r_{pname} : {pw}\'b0;\n')
        f.write('\n')

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
