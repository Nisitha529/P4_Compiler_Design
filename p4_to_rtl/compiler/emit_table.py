import math
import os
import re

from ir import ActionParam
from timing_model import table_tree_stages, exact_match_tag_compare_stages, TREE_LEVEL_REAL_COST

_STD_META_WIDTHS = {
    'egress_spec': 9, 'ingress_port': 9, 'egress_port': 9,
    'instance_type': 32, 'packet_length': 32, 'priority': 3,
    'mcast_grp': 16, 'egress_rid': 16, 'checksum_error': 1,
}


# ============================================================
# Helpers
# ============================================================

def _find_processing_ctrl(ir, stage='ingress'):
    if stage == 'egress':
        return ir.pipeline.egress
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

def _emit_one_table(ir, table, amap, fwmap, output_path, budget_levels=None, ways=1, enable_query=False):

    act_ids   = _action_ids(table)
    params    = _collect_params(table, amap)
    n_acts    = max(act_ids.values()) + 1
    act_id_w  = max(1, math.ceil(math.log2(n_acts))) if n_acts > 1 else 1

    if not table.keys:
        _emit_keyless_table(table, act_ids, params, act_id_w, output_path)
        return

    # Determine table type from first key (default exact)
    match_type = table.keys[0].match_type if table.keys else 'exact'
    is_lpm     = (match_type == 'lpm')
    is_ternary = (match_type == 'ternary')

    depth = table.size if table.size else 1024

    if not is_lpm and not is_ternary:
        if ways and ways > 1:
            _emit_exact_match_table_assoc(table, act_ids, params, act_id_w, depth, fwmap, output_path, ways, budget_levels=budget_levels)
        else:
            _emit_exact_match_table(table, act_ids, params, act_id_w, depth, fwmap, output_path, budget_levels=budget_levels, enable_query=enable_query)
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
            # Stored as a precomputed prefix *mask*, not a length -- see the
            # CP-write block below for why (avoids a barrel shifter per
            # entry at lookup time).
            fname0 = _field_basename(table.keys[0].field) if table.keys else 'key'
            f.write(f'  logic [{key_w-1}:0] mem_pfx_mask_{fname0}[0:DEPTH-1];\n')
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
        f.write('  `ifndef SYNTHESIS\n')
        f.write('  // synthesis translate_off\n')
        f.write('  initial begin\n')
        f.write('    for (_i = 0; _i < DEPTH; _i = _i + 1)\n')
        f.write('      mem_valid[_i] = 1\'b0;\n')
        f.write('  end\n')
        f.write('  // synthesis translate_on\n')
        f.write('  `endif\n\n')
        f.write('  always_ff @(posedge clk) begin\n')
        f.write('    if (cp_wr_en) begin\n')
        f.write('      mem_valid[cp_wr_idx]  <= 1\'b1;\n')
        for key in table.keys:
            fname = _field_basename(key.field)
            f.write(f'      mem_key_{fname}[cp_wr_idx] <= cp_wr_key_{fname};\n')
        if is_lpm:
            # Shift once here (a control-plane write, rare) instead of once
            # per entry per lookup (every cycle, x DEPTH instances) -- see
            # the leaf-comparison comment below for the actual motivation.
            f.write(f'      mem_pfx_mask_{fname0}[cp_wr_idx] <= '
                    f'(cp_wr_pfx_len == {pfx_w}\'d0) ? {key_w}\'d0 : '
                    f'({{{key_w}{{1\'b1}}}} << ({key_w} - cp_wr_pfx_len));\n')
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

        f.write(f'  logic        hit_l0_c[0:{depth-1}];\n')
        f.write(f'  logic [{act_id_w-1}:0] act_l0_c[0:{depth-1}];\n')
        for pname, pw in params:
            f.write(f'  logic [{pw-1}:0] p_{pname}_l0_c[0:{depth-1}];\n')
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
                # Mask-based compare (like ternary), not a shift-based one.
                # The old version did `(lkp >> (W-pfx)) == (key >> (W-pfx))`
                # -- a *variable-width barrel shifter on both operands, per
                # entry*, re-evaluated every cycle. At DEPTH=1024 that's
                # ~2048 barrel shifter instances and dominated the whole
                # table's area in real synthesis (measured: this one table
                # was 385K of a 386K-cell design). The prefix mask is
                # precomputed once at CP-write time (see above) instead, so
                # the lookup-time cost per entry drops to a plain AND +
                # equality compare -- no shifting at all on the hot path.
                f.write(f'  logic [{key_w-1}:0] _key_{j}; assign _key_{j} = mem_key_{fname}[{j}];\n')
                f.write(f'  logic [{key_w-1}:0] _mask_{j}; assign _mask_{j} = mem_pfx_mask_{fname}[{j}];\n')
                cond = f'((lkp_{fname} & _mask_{j}) == (_key_{j} & _mask_{j}))'
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
            f.write(f'  assign hit_l0_c[{j}] = mem_valid[{j}] && {cond};\n')
            f.write(f'  assign act_l0_c[{j}] = mem_action[{j}];\n')
            for pname, _ in params:
                f.write(f'  assign p_{pname}_l0_c[{j}] = mem_p_{pname}[{j}];\n')
        f.write('\n')

        # Register the leaf level: splits the per-entry match computation
        # (variable-width barrel shift for LPM, mask-compare for ternary --
        # itself a nontrivial combinational depth) from the log2(DEPTH)-level
        # tree reduction that follows. Gives the table a fixed 1-cycle lookup
        # latency, same external timing contract as the hash+BRAM exact-match
        # table, so it plugs into the same pipeline-stage boundary machinery
        # in emit_processing.py.
        f.write(f'  logic        hit_l0[0:{depth-1}];\n')
        f.write(f'  logic [{act_id_w-1}:0] act_l0[0:{depth-1}];\n')
        for pname, pw in params:
            f.write(f'  logic [{pw-1}:0] p_{pname}_l0[0:{depth-1}];\n')
        f.write('  integer _rj;\n')
        f.write('  always_ff @(posedge clk) begin\n')
        f.write('    if (!rst_n) begin\n')
        f.write('      for (_rj = 0; _rj < DEPTH; _rj = _rj + 1)\n')
        f.write('        hit_l0[_rj] <= 1\'b0;\n')
        f.write('    end else begin\n')
        f.write('      for (_rj = 0; _rj < DEPTH; _rj = _rj + 1) begin\n')
        f.write('        hit_l0[_rj] <= hit_l0_c[_rj];\n')
        f.write('        act_l0[_rj] <= act_l0_c[_rj];\n')
        for pname, _ in params:
            f.write(f'        p_{pname}_l0[_rj] <= p_{pname}_l0_c[_rj];\n')
        f.write('      end\n')
        f.write('    end\n')
        f.write('  end\n\n')

        # Opt-in mid-tree pipeline registers (--target-freq-mhz): src_hit/
        # src_act/src_p track *where this iteration reads its previous
        # level from* -- the plain hit_l{level}/act_l{level}/p_*_l{level}
        # names when budget_levels is None (never reassigned outside the
        # insertion branch below, so that case's generated text is
        # byte-identical to before this parameter existed by construction,
        # not by a separate check) or a registered _r copy once a hop's
        # accumulated depth reaches budget_levels tree-levels. See
        # timing_model.table_tree_stages() -- emit_processing.py's
        # scheduler inserts one matching no-op pass-through stage per
        # insertion here, computed from that same shared function so the
        # two files' cycle counts can never drift apart.
        prev_n, level = depth, 0
        src_hit, src_act = 'hit_l0', 'act_l0'
        src_p = {pname: f'p_{pname}_l0' for pname, _ in params}
        levels_since_reg = 0
        n_insertions = 0
        while prev_n > 1:
            nxt_n = (prev_n + 1) // 2
            dst_hit, dst_act = f'hit_l{level+1}', f'act_l{level+1}'
            dst_p = {pname: f'p_{pname}_l{level+1}' for pname, _ in params}
            f.write(f'  logic        {dst_hit}[0:{nxt_n-1}];\n')
            f.write(f'  logic [{act_id_w-1}:0] {dst_act}[0:{nxt_n-1}];\n')
            for pname, pw in params:
                f.write(f'  logic [{pw-1}:0] {dst_p[pname]}[0:{nxt_n-1}];\n')
            for i in range(nxt_n):
                left, right = 2 * i, 2 * i + 1
                if right < prev_n:
                    f.write(f'  assign {dst_hit}[{i}] = {src_hit}[{left}] || {src_hit}[{right}];\n')
                    f.write(f'  assign {dst_act}[{i}] = {src_hit}[{left}] ? '
                            f'{src_act}[{left}] : {src_act}[{right}];\n')
                    for pname, _ in params:
                        f.write(f'  assign {dst_p[pname]}[{i}] = {src_hit}[{left}] ? '
                                f'{src_p[pname]}[{left}] : {src_p[pname]}[{right}];\n')
                else:
                    f.write(f'  assign {dst_hit}[{i}] = {src_hit}[{left}];\n')
                    f.write(f'  assign {dst_act}[{i}] = {src_act}[{left}];\n')
                    for pname, _ in params:
                        f.write(f'  assign {dst_p[pname]}[{i}] = {src_p[pname]}[{left}];\n')
            f.write('\n')
            prev_n, level = nxt_n, level + 1
            levels_since_reg += 1
            src_hit, src_act, src_p = dst_hit, dst_act, dst_p

            is_final_level = (prev_n == 1)
            # Trigger scaled by TREE_LEVEL_REAL_COST -- table_tree_stages()
            # budgets each raw tree level at its real measured cost, not
            # 1:1, so the insertion trigger has to match (see that
            # function's docstring for the real synthesis data behind
            # this). Must stay in lockstep with table_tree_stages()'s own
            # formula or the assert below fires -- exactly the drift this
            # structural guarantee exists to catch.
            if (budget_levels is not None and not is_final_level
                    and levels_since_reg * TREE_LEVEL_REAL_COST >= budget_levels):
                reg_hit, reg_act = f'{dst_hit}_r', f'{dst_act}_r'
                reg_p = {pname: f'{dst_p[pname]}_r' for pname, _ in params}
                lv = f'_rj_l{level}'
                f.write(f'  logic        {reg_hit}[0:{nxt_n-1}];\n')
                f.write(f'  logic [{act_id_w-1}:0] {reg_act}[0:{nxt_n-1}];\n')
                for pname, pw in params:
                    f.write(f'  logic [{pw-1}:0] {reg_p[pname]}[0:{nxt_n-1}];\n')
                f.write(f'  integer {lv};\n')
                f.write('  always_ff @(posedge clk) begin\n')
                f.write('    if (!rst_n) begin\n')
                f.write(f'      for ({lv} = 0; {lv} < {nxt_n}; {lv} = {lv} + 1)\n')
                f.write(f"        {reg_hit}[{lv}] <= 1'b0;\n")
                f.write('    end else begin\n')
                f.write(f'      for ({lv} = 0; {lv} < {nxt_n}; {lv} = {lv} + 1) begin\n')
                f.write(f'        {reg_hit}[{lv}] <= {dst_hit}[{lv}];\n')
                f.write(f'        {reg_act}[{lv}] <= {dst_act}[{lv}];\n')
                for pname, _ in params:
                    f.write(f'        {reg_p[pname]}[{lv}] <= {dst_p[pname]}[{lv}];\n')
                f.write('      end\n')
                f.write('    end\n')
                f.write('  end\n\n')
                src_hit, src_act, src_p = reg_hit, reg_act, reg_p
                levels_since_reg = 0
                n_insertions += 1

        # Structural guarantee (not just "the arithmetic should agree"):
        # this count must exactly match what emit_processing.py's scheduler
        # will independently compute from the same table_tree_stages() for
        # this same (depth, budget_levels) -- a drift here wouldn't crash,
        # it would silently read hit/action_id one cycle too early.
        assert n_insertions == table_tree_stages(depth, budget_levels) - 1, (
            f'{table.name}: inserted {n_insertions} mid-tree registers but '
            f'table_tree_stages({depth}, {budget_levels}) says the scheduler '
            f'expects {table_tree_stages(depth, budget_levels) - 1}'
        )

        # Register the tree's final output instead of exposing it as a raw
        # combinational port. Real synthesis (Vivado, Artix-7) on firewall
        # showed the critical path running clean through this tree's log2
        # (DEPTH) reduction levels *and* straight on through the caller's
        # action-dispatch mux and action-body arithmetic with no register
        # in between (measured: 16 logic levels, ~93MHz worst case, all in
        # one unbroken combinational stretch from this table's leaf
        # register to the caller's output register). Registering hit/
        # action_id/params here gives the table 2-cycle total latency
        # (lookup + this output stage) but cleanly separates "the tree
        # settles" from "the caller acts on it" into two real cycles --
        # the actual fix the timing data pointed at. emit_processing.py's
        # scheduler inserts a matching second no-op register hop so the
        # caller's stage count still lines up (see _schedule_stages).
        f.write(f'  logic hit_c; assign hit_c = hit_l{level}[0];\n')
        f.write(f'  logic [{act_id_w-1}:0] action_id_c;\n')
        f.write(f'  assign action_id_c = hit_l{level}[0] ? act_l{level}[0] : {act_id_w}\'d{default_act_id};\n')
        for pname, pw in params:
            f.write(f'  logic [{pw-1}:0] p_{pname}_c;\n')
            f.write(f'  assign p_{pname}_c = hit_l{level}[0] ? p_{pname}_l{level}[0] : {pw}\'b0;\n')
        f.write('\n')
        f.write('  always_ff @(posedge clk) begin\n')
        f.write('    if (!rst_n) begin\n')
        f.write("      hit <= 1'b0;\n")
        f.write('    end else begin\n')
        f.write('      hit <= hit_c;\n')
        f.write('      action_id <= action_id_c;\n')
        for pname, _ in params:
            f.write(f'      p_{pname} <= p_{pname}_c;\n')
        f.write('    end\n')
        f.write('  end\n\n')

        # ── Action encoding comment ───────────────────────────────────
        f.write('  // Action ID encoding:\n')
        for aname, aid in sorted(act_ids.items(), key=lambda x: x[1]):
            f.write(f'  //   {aid} = {aname}\n')
        f.write('\n')

        f.write('endmodule\n')


# ============================================================
# Keyless table: unconditional control-plane-configurable default action
# ============================================================
#
# A P4 table with no `key = {...}` block always applies its default
# action -- but that default action (and its parameters) is still a
# control-plane-writable runtime value (P4Runtime's "set default table
# entry"), not a compile-time constant, even though there's no match/no
# hit logic at all. This is the simplest possible "table": a single
# control-plane-writable action_id + parameter register bank, `hit`
# hardwired true, output available combinationally (no lookup latency of
# any kind -- there's no key comparison to register a boundary around).

def _emit_keyless_table(table, act_ids, params, act_id_w, output_path):
    default_act_name = (table.default_action or 'NoAction').rstrip('()')
    default_act_id   = act_ids.get(default_act_name, 0)

    with open(output_path, 'w') as f:
        f.write(f'module {table.name}_table (\n')
        f.write('  input  logic clk,\n')
        f.write('  input  logic rst_n,\n')

        f.write('\n  // Result (no key -- always hits the configured default action)\n')
        f.write('  output logic        hit,\n')
        f.write(f'  output logic [{act_id_w-1}:0] action_id,\n')
        for pname, pw in params:
            f.write(f'  output logic [{pw-1}:0] p_{pname},\n')

        f.write('\n  // Control-plane write port (synchronous) -- sets the default action\n')
        f.write('  input  logic        cp_wr_en,\n')
        f.write(f'  input  logic [{act_id_w-1}:0] cp_wr_action')
        if params:
            f.write(',\n')
            for i, (pname, pw) in enumerate(params):
                comma = ',' if i < len(params) - 1 else ''
                f.write(f'  input  logic [{pw-1}:0] cp_wr_p_{pname}{comma}\n')
        else:
            f.write('\n')
        f.write(');\n\n')

        f.write(f'  logic [{act_id_w-1}:0] action_id_r;\n')
        for pname, pw in params:
            f.write(f'  logic [{pw-1}:0] p_{pname}_r;\n')
        f.write('\n')

        f.write('  always_ff @(posedge clk) begin\n')
        f.write('    if (!rst_n) begin\n')
        f.write(f'      action_id_r <= {act_id_w}\'d{default_act_id};\n')
        for pname, pw in params:
            f.write(f'      p_{pname}_r <= {pw}\'b0;\n')
        f.write('    end else if (cp_wr_en) begin\n')
        f.write('      action_id_r <= cp_wr_action;\n')
        for pname, _ in params:
            f.write(f'      p_{pname}_r <= cp_wr_p_{pname};\n')
        f.write('    end\n')
        f.write('  end\n\n')

        f.write("  assign hit       = 1'b1;\n")
        f.write('  assign action_id = action_id_r;\n')
        for pname, _ in params:
            f.write(f'  assign p_{pname} = p_{pname}_r;\n')
        f.write('\n')

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

def _emit_exact_match_table(table, act_ids, params, act_id_w, depth, fwmap, output_path, budget_levels=None, enable_query=False):
    # enable_query: False (default) = today's behavior exactly, byte-identical
    # output to before this parameter existed -- no query/delete port, no
    # query pipeline, plain single-branch write. True only for the XSA/
    # p4test frontend's AXI4-Lite control plane (see emit_top.py), which is
    # the only thing that can ever drive these new ports -- every bmv2-
    # pipeline app has no bus wrapper to reach them at all, so this stays
    # off for all 8 of those apps regardless of table shape.
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
        if params or enable_query:
            f.write(',\n')
            for i, (pname, pw) in enumerate(params):
                last = (i == len(params) - 1)
                comma = ',' if (not last or enable_query) else ''
                f.write(f'  input  logic [{pw-1}:0] cp_wr_p_{pname}{comma}\n')
        else:
            f.write('\n')

        if enable_query:
            f.write('\n  // Control-plane query/delete port (synchronous, 2-cycle staged --\n')
            f.write('  // shares the write port\'s memory access, time-multiplexed, rather\n')
            f.write('  // than adding a 3rd BRAM port). cp_query_del=0: read-only lookup by\n')
            f.write('  // key. cp_query_del=1: lookup, and if found, delete it. Results are\n')
            f.write('  // sticky (held until the next query) so a polling driver can check\n')
            f.write('  // !cp_query_busy then read at leisure, no single-cycle window.\n')
            f.write('  input  logic        cp_query_en,\n')
            f.write('  input  logic        cp_query_del,\n')
            for fname, w in key_fields:
                f.write(f'  input  logic [{w-1}:0] cp_query_key_{fname},\n')
            f.write('  output logic        cp_query_busy,\n')
            f.write('  output logic        cp_query_hit,\n')
            f.write(f'  output logic [{act_id_w-1}:0] cp_query_action_id')
            if params:
                f.write(',\n')
                for i, (pname, pw) in enumerate(params):
                    comma = ',' if i < len(params) - 1 else ''
                    f.write(f'  output logic [{pw-1}:0] cp_query_p_{pname}{comma}\n')
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
        f.write('  `ifndef SYNTHESIS\n')
        f.write('  // synthesis translate_off\n')
        f.write('  initial begin\n')
        f.write('    for (_i = 0; _i < DEPTH; _i = _i + 1)\n')
        f.write('      mem_valid[_i] = 1\'b0;\n')
        f.write('  end\n')
        f.write('  // synthesis translate_on\n')
        f.write('  `endif\n\n')

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

        if enable_query:
            f.write(f'  logic [{padded_w-1}:0] q_key_concat;\n')
            f.write(f'  assign q_key_concat = {{{padded_w - key_w}\'d0, {_concat("cp_query_key_")}}};\n' if padded_w > key_w
                    else f'  assign q_key_concat = {{{_concat("cp_query_key_")}}};\n')
            f.write(f'  logic [{idx_w-1}:0] q_addr;\n')
            f.write('  assign q_addr = hash_key(q_key_concat);\n\n')

        if not enable_query:
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
        else:
            f.write('  // Control-plane query/delete pipeline, stage 1: latch the request\n')
            f.write('  // and issue a registered port-B read at q_addr to see what\'s there.\n')
            f.write('  // Gated on !q_pend_valid (a new query is only accepted once the\n')
            f.write('  // previous one has resolved) and !cp_wr_en (never start a query the\n')
            f.write('  // same cycle a plain write is committing).\n')
            f.write('  logic q_pend_valid, q_pend_del;\n')
            f.write(f'  logic [{idx_w-1}:0] q_pend_addr;\n')
            for fname, w in key_fields:
                f.write(f'  logic [{w-1}:0] q_pend_key_{fname};\n')
            f.write('  logic q_rd_valid;\n')
            for fname, w in key_fields:
                f.write(f'  logic [{w-1}:0] q_rd_key_{fname};\n')
            f.write(f'  logic [{act_id_w-1}:0] q_rd_action;\n')
            for pname, pw in params:
                f.write(f'  logic [{pw-1}:0] q_rd_p_{pname};\n')
            f.write('\n')

            f.write('  always_ff @(posedge clk) begin\n')
            f.write('    if (!rst_n) begin\n')
            f.write("      q_pend_valid <= 1'b0;\n")
            f.write('    end else if (cp_query_en && !q_pend_valid && !cp_wr_en && !clearing) begin\n')
            f.write("      q_pend_valid <= 1'b1;\n")
            f.write('      q_pend_del   <= cp_query_del;\n')
            f.write('      q_pend_addr  <= q_addr;\n')
            for fname, _ in key_fields:
                f.write(f'      q_pend_key_{fname} <= cp_query_key_{fname};\n')
            f.write('      q_rd_valid   <= mem_valid[q_addr];\n')
            for fname, _ in key_fields:
                f.write(f'      q_rd_key_{fname} <= mem_key_{fname}[q_addr];\n')
            f.write('      q_rd_action  <= mem_action[q_addr];\n')
            for pname, _ in params:
                f.write(f'      q_rd_p_{pname} <= mem_p_{pname}[q_addr];\n')
            f.write('    end else begin\n')
            f.write("      q_pend_valid <= 1'b0;\n")
            f.write('    end\n')
            f.write('  end\n')
            f.write('  assign cp_query_busy = q_pend_valid;\n\n')

            f.write('  // Stage 2: resolve against the now-valid read (fires the cycle\n')
            f.write('  // right after accept, since stage 1\'s own else-branch clears\n')
            f.write('  // q_pend_valid one cycle later -- same timing relationship the\n')
            f.write('  // write path already has between its own accept and commit).\n')
            q_tag_match = ' && '.join(f'(q_rd_key_{fname} == q_pend_key_{fname})' for fname, _ in key_fields) or "1'b1"
            f.write(f'  logic q_match; assign q_match = q_rd_valid && {q_tag_match};\n\n')

            f.write('  logic        q_hit_r;\n')
            f.write(f'  logic [{act_id_w-1}:0] q_action_id_r;\n')
            for pname, pw in params:
                f.write(f'  logic [{pw-1}:0] q_p_{pname}_r;\n')
            f.write('  always_ff @(posedge clk) begin\n')
            f.write('    if (!rst_n) begin\n')
            f.write("      q_hit_r       <= 1'b0;\n")
            f.write(f"      q_action_id_r <= {act_id_w}'d0;\n")
            for pname, pw in params:
                f.write(f"      q_p_{pname}_r <= {pw}'d0;\n")
            f.write('    end else if (q_pend_valid) begin\n')
            f.write('      q_hit_r       <= q_match;\n')
            f.write(f"      q_action_id_r <= q_match ? q_rd_action : {act_id_w}'d0;\n")
            for pname, pw in params:
                f.write(f"      q_p_{pname}_r <= q_match ? q_rd_p_{pname} : {pw}'d0;\n")
            f.write('    end\n')
            f.write('  end\n')
            f.write('  assign cp_query_hit = q_hit_r;\n')
            f.write('  assign cp_query_action_id = q_action_id_r;\n')
            for pname, _ in params:
                f.write(f'  assign cp_query_p_{pname} = q_p_{pname}_r;\n')
            f.write('\n')

            f.write('  // Real power-on clear for mem_valid: the initial-block zero-fill above\n')
            f.write('  // is excluded from real synthesis (translate_off), so Quartus never sees\n')
            f.write('  // an init hint for this BRAM -- real Cyclone IV power-up content is\n')
            f.write('  // otherwise unspecified, which would let the table report spurious hits\n')
            f.write('  // on entries the control plane never wrote. This FSM walks every address\n')
            f.write('  // once, forcing mem_valid low, before any real write/query/lookup is\n')
            f.write('  // allowed to see memory content. Deliberately NOT gated on rst_n: table\n')
            f.write('  // entries must persist across a soft rst_n pulse (existing, tested\n')
            f.write('  // behavior -- see tb_FiveTuple_table_query_delete_standalone.sv), so this\n')
            f.write('  // has to be a genuine one-shot power-on sequence, driven purely by each\n')
            f.write('  // register\'s own inline initial value (a standard, synthesizable FPGA\n')
            f.write('  // idiom -- distinct from the procedural initial-BLOCK LOOP that hit\n')
            f.write('  // Quartus\'s 5000-iteration cap; a single register\'s declared reset value\n')
            f.write('  // is just its configuration-time power-up state, not an unrolled loop).\n')
            f.write('  // A write/query issued while clearing is in progress is silently\n')
            f.write('  // dropped (see cp_query_en\'s !clearing gate above) -- accepted as a\n')
            f.write('  // low-probability edge case, since DEPTH cycles is microseconds of real\n')
            f.write('  // wall-clock time, not something realistic control-plane software would\n')
            f.write('  // race against.\n')
            f.write("  logic clearing = 1'b1;\n")
            f.write(f"  logic [{idx_w-1}:0] clr_idx = '0;\n\n")

            f.write('  // Synchronous write (control plane) -- extended, not duplicated, to add\n')
            f.write('  // the delete-commit branch AND the power-on clear above: this is the one\n')
            f.write('  // place mem_valid needs multiple writers, and it must stay a single\n')
            f.write('  // always_ff with if/else-if so at most one branch can ever drive the\n')
            f.write('  // array per cycle. The plain write is additionally gated !q_pend_valid so\n')
            f.write('  // a write colliding with an in-flight query/delete is dropped here rather\n')
            f.write('  // than corrupting anything -- the AXI4-Lite decoder is responsible for\n')
            f.write('  // never letting that collision reach this port in the first place (see\n')
            f.write('  // cp_query_busy-gated backpressure on the write channel).\n')
            f.write('  always_ff @(posedge clk) begin\n')
            f.write('    if (clearing) begin\n')
            f.write("      mem_valid[clr_idx] <= 1'b0;\n")
            f.write('      if (clr_idx == DEPTH-1) begin\n')
            f.write("        clearing <= 1'b0;\n")
            f.write('      end else begin\n')
            f.write("        clr_idx <= clr_idx + 1'b1;\n")
            f.write('      end\n')
            f.write('    end else if (cp_wr_en && !q_pend_valid) begin\n')
            f.write('      mem_valid[wr_addr]  <= 1\'b1;\n')
            for fname, _ in key_fields:
                f.write(f'      mem_key_{fname}[wr_addr] <= cp_wr_key_{fname};\n')
            f.write('      mem_action[wr_addr] <= cp_wr_action;\n')
            for pname, _ in params:
                f.write(f'      mem_p_{pname}[wr_addr] <= cp_wr_p_{pname};\n')
            f.write('    end else if (q_pend_valid && q_pend_del && q_match) begin\n')
            f.write("      mem_valid[q_pend_addr] <= 1'b0;\n")
            f.write('    end\n')
            f.write('  end\n\n')

        # Opt-in tag-compare split (--target-freq-mhz): n_stages/split track
        # whether the tag-compare needs its own register between "compare"
        # and "select" instead of both happening combinationally in the
        # same cycle as the BRAM reads on either side. See
        # timing_model.exact_match_tag_compare_stages() -- emit_processing.py's
        # scheduler inserts a matching no-op pass-through stage per hop,
        # computed from that same shared function so the two files' cycle
        # counts can never drift apart.
        n_stages = exact_match_tag_compare_stages([w for _, w in key_fields], budget_levels)
        split = (n_stages == 2)

        f.write(f'  // Registered BRAM read + tag-compare stage ({n_stages}-cycle lookup latency)\n')
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
        if enable_query:
            f.write('      valid_r     <= clearing ? 1\'b0 : mem_valid[lkp_addr];\n')
        else:
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
        f.write(f'  logic hit_c; assign hit_c = valid_r && {tag_match};\n')

        # mux_sel feeds both the action-select mux below and the final
        # output register's `hit` input -- always the same value in this
        # design. Unsplit: straight off hit_c, identical text to before
        # this parameter existed. Split: register hit_c (and the still-
        # needed action_id_r/p_r_* payload) one more cycle first, so the
        # tag-compare settles in its own cycle instead of bridging
        # directly from one BRAM's registered output into the next
        # register's control input within a single clock period (this is
        # exactly the real critical path a Vivado synthesis run found).
        mux_sel = 'hit_c'
        act_src = 'action_id_r'
        p_src   = {pname: f'p_r_{pname}' for pname, _ in params}

        if split:
            f.write('  logic hit_mid;\n')
            f.write(f'  logic [{act_id_w-1}:0] action_id_r2;\n')
            for pname, pw in params:
                f.write(f'  logic [{pw-1}:0] p_r2_{pname};\n')
            f.write('  always_ff @(posedge clk) begin\n')
            f.write('    if (!rst_n) begin\n')
            f.write("      hit_mid <= 1'b0;\n")
            f.write('    end else begin\n')
            f.write('      hit_mid      <= hit_c;\n')
            f.write('      action_id_r2 <= action_id_r;\n')
            for pname, _ in params:
                # Unconditional every cycle, never hit-gated -- a hit-gated
                # version would let a stale payload from a previous hit
                # leak into a later miss cycle.
                f.write(f'      p_r2_{pname} <= p_r_{pname};\n')
            f.write('    end\n')
            f.write('  end\n\n')
            mux_sel = 'hit_mid'
            act_src = 'action_id_r2'
            p_src   = {pname: f'p_r2_{pname}' for pname, _ in params}

        # Registered output (same reasoning as the LPM/ternary tree's final
        # stage): keeps the action-select settling in its own cycle instead
        # of fusing straight into the caller's action-dispatch mux and
        # arithmetic. emit_processing.py's scheduler matches n_stages.
        f.write(f'  logic [{act_id_w-1}:0] action_id_c;\n')
        f.write(f'  assign action_id_c = {mux_sel} ? {act_src} : {act_id_w}\'d{default_act_id};\n')
        for pname, pw in params:
            f.write(f'  logic [{pw-1}:0] p_{pname}_c;\n')
            f.write(f'  assign p_{pname}_c = {mux_sel} ? {p_src[pname]} : {pw}\'b0;\n')
        f.write('\n')
        f.write('  always_ff @(posedge clk) begin\n')
        f.write('    if (!rst_n) begin\n')
        f.write("      hit <= 1'b0;\n")
        f.write('    end else begin\n')
        f.write(f'      hit <= {mux_sel};\n')
        f.write('      action_id <= action_id_c;\n')
        for pname, _ in params:
            f.write(f'      p_{pname} <= p_{pname}_c;\n')
        f.write('    end\n')
        f.write('  end\n\n')

        assert n_stages == exact_match_tag_compare_stages([w for _, w in key_fields], budget_levels), (
            f'{table.name}: split={split} but the scheduler will independently '
            f'compute a different stage count for the same inputs'
        )

        f.write('  // Action ID encoding:\n')
        for aname, aid in sorted(act_ids.items(), key=lambda x: x[1]):
            f.write(f'  //   {aid} = {aname}\n')
        f.write('\n')

        f.write('endmodule\n')


# ============================================================
# Exact-match table: d-way set-associative variant
# ============================================================
#
# Only reached when ways > 1 -- ways <= 1 always dispatches to the plain
# _emit_exact_match_table() above, completely untouched, so default output
# stays byte-identical by construction. Fixes the direct-mapped table's
# documented collision gap: a CP write whose key hashes to an
# already-occupied bucket now only overwrites a DIFFERENT key once all
# `ways` slots at that bucket are occupied (see `wr_collision` output);
# until then it lands in a free way, or updates its own way in place if
# the key is already stored there.
#
# Same DEPTH-bucket addressing / hash_key() as the direct-mapped version --
# associativity multiplies capacity per bucket by `ways`, it does not
# change the number of buckets or the hash function.
#
# CP writes are staged over 2 cycles instead of 1: every mem_* read in this
# file is a registered (synchronous) BRAM read, so deciding which of the
# `ways` slots to write into needs a registered read of all of them first
# -- cycle N latches the write request and issues that read, cycle N+1
# decides the target way from the now-valid read data and commits. A new
# write is only accepted once the previous one has fully committed
# (`cp_wr_en && !wr_pend_valid`), exposed as `cp_wr_busy` -- without this
# gate, two cp_wr_en pulses on consecutive cycles would double-drive the
# same way-array's read/write port in the same cycle. This 2-cycle write
# latency is a real, new contract change from the direct-mapped table
# (whose write is immediate/single-cycle) but is a non-issue in practice:
# control-plane writes are software-driven, not per-packet hot-path
# traffic. Packet-lookup latency is completely unaffected (still exactly
# exact_match_tag_compare_stages() cycles) -- only the CP-write path grows.

def _emit_exact_match_table_assoc(table, act_ids, params, act_id_w, depth, fwmap,
                                   output_path, ways, budget_levels=None):
    idx_w = max(1, math.ceil(math.log2(depth))) if depth > 1 else 1
    ways_w = max(1, math.ceil(math.log2(ways)))

    key_fields = [(_field_basename(k.field), _key_width(k.field, fwmap)) for k in table.keys]
    key_w      = sum(w for _, w in key_fields)
    n_chunks   = max(1, math.ceil(key_w / idx_w))
    padded_w   = n_chunks * idx_w

    default_act_name = (table.default_action or 'NoAction').rstrip('()')
    default_act_id   = act_ids.get(default_act_name, 0)

    def _concat(prefix):
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

        f.write('\n  // Lookup result (registered — same latency as the direct-mapped table)\n')
        f.write('  output logic        hit,\n')
        f.write(f'  output logic [{act_id_w-1}:0] action_id,\n')
        for pname, pw in params:
            f.write(f'  output logic [{pw-1}:0] p_{pname},\n')

        f.write('\n  // Control-plane write port (synchronous, 2-cycle staged allocate+commit)\n')
        f.write('  input  logic        cp_wr_en,\n')
        f.write(f'  input  logic [{idx_w-1}:0] cp_wr_idx,  // unused: exact-match tables self-address via hash(key)\n')
        for fname, w in key_fields:
            f.write(f'  input  logic [{w-1}:0] cp_wr_key_{fname},\n')
        f.write(f'  input  logic [{act_id_w-1}:0] cp_wr_action,\n')
        for pname, pw in params:
            f.write(f'  input  logic [{pw-1}:0] cp_wr_p_{pname},\n')

        f.write('\n  // Control-plane write status outputs\n')
        f.write('  output logic        wr_collision,\n')
        f.write('  output logic        cp_wr_busy\n')
        f.write(');\n\n')

        f.write(f'  // Entry storage, {ways} ways per bucket (synthesizes to {ways} parallel\n')
        f.write('  // block RAMs -- port A below = continuous packet-lookup reads, port B =\n')
        f.write('  // staged control-plane write allocate+commit)\n')
        for w in range(ways):
            f.write(f'  logic        mem_valid_w{w}  [0:DEPTH-1];\n')
            for fname, kw in key_fields:
                f.write(f'  logic [{kw-1}:0] mem_key_w{w}_{fname}[0:DEPTH-1];\n')
            f.write(f'  logic [{act_id_w-1}:0] mem_action_w{w}[0:DEPTH-1];\n')
            for pname, pw in params:
                f.write(f'  logic [{pw-1}:0] mem_p_w{w}_{pname}[0:DEPTH-1];\n')
        f.write('\n')

        f.write('  integer _i;\n')
        f.write('  `ifndef SYNTHESIS\n')
        f.write('  // synthesis translate_off\n')
        f.write('  initial begin\n')
        f.write('    for (_i = 0; _i < DEPTH; _i = _i + 1) begin\n')
        for w in range(ways):
            f.write(f'      mem_valid_w{w}[_i] = 1\'b0;\n')
        f.write('    end\n')
        f.write('  end\n')
        f.write('  // synthesis translate_on\n')
        f.write('  `endif\n\n')

        f.write(f'  // XOR-fold hash: {key_w}-bit key -> {idx_w}-bit BRAM address (same as the\n')
        f.write('  // direct-mapped table -- ways multiplies capacity per bucket, not bucket count)\n')
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

        # ---- CP-write pipeline: cycle N latch + allocation-read, cycle N+1 decide + commit ----
        f.write('  // Control-plane write pipeline, stage 1: latch the incoming request and\n')
        f.write('  // issue a registered per-way read at wr_addr to see what is already there.\n')
        f.write('  // Gated on !wr_pend_valid -- a new write is only accepted once the previous\n')
        f.write('  // one has fully committed (see cp_wr_busy).\n')
        f.write('  logic wr_pend_valid;\n')
        f.write(f'  logic [{idx_w-1}:0] wr_pend_addr;\n')
        for fname, kw in key_fields:
            f.write(f'  logic [{kw-1}:0] wr_pend_key_{fname};\n')
        f.write(f'  logic [{act_id_w-1}:0] wr_pend_action;\n')
        for pname, pw in params:
            f.write(f'  logic [{pw-1}:0] wr_pend_p_{pname};\n')
        f.write('\n')
        for w in range(ways):
            f.write(f'  logic alloc_rd_valid_w{w};\n')
            for fname, kw in key_fields:
                f.write(f'  logic [{kw-1}:0] alloc_rd_key_w{w}_{fname};\n')
        f.write('\n')

        f.write('  always_ff @(posedge clk) begin\n')
        f.write('    if (!rst_n) begin\n')
        f.write("      wr_pend_valid <= 1'b0;\n")
        f.write('    end else if (cp_wr_en && !wr_pend_valid) begin\n')
        f.write("      wr_pend_valid   <= 1'b1;\n")
        f.write('      wr_pend_addr    <= wr_addr;\n')
        for fname, _ in key_fields:
            f.write(f'      wr_pend_key_{fname} <= cp_wr_key_{fname};\n')
        f.write('      wr_pend_action  <= cp_wr_action;\n')
        for pname, _ in params:
            f.write(f'      wr_pend_p_{pname} <= cp_wr_p_{pname};\n')
        for w in range(ways):
            f.write(f'      alloc_rd_valid_w{w} <= mem_valid_w{w}[wr_addr];\n')
            for fname, _ in key_fields:
                f.write(f'      alloc_rd_key_w{w}_{fname} <= mem_key_w{w}_{fname}[wr_addr];\n')
        f.write('    end else begin\n')
        f.write("      wr_pend_valid <= 1'b0;\n")
        f.write('    end\n')
        f.write('  end\n\n')
        f.write('  assign cp_wr_busy = wr_pend_valid;\n\n')

        f.write('  // Control-plane write pipeline, stage 2: decide which way to write into\n')
        f.write('  // from stage 1\'s now-valid read, and commit.\n')
        for w in range(ways):
            match_terms = ' && '.join(
                f'(alloc_rd_key_w{w}_{fname} == wr_pend_key_{fname})' for fname, _ in key_fields
            ) or "1'b1"
            f.write(f'  logic key_match_w{w}; assign key_match_w{w} = alloc_rd_valid_w{w} && {match_terms};\n')
            f.write(f'  logic free_w{w}; assign free_w{w} = !alloc_rd_valid_w{w};\n')
        f.write('\n')
        has_match = ' | '.join(f'key_match_w{w}' for w in range(ways))
        has_free  = ' | '.join(f'free_w{w}' for w in range(ways))
        f.write(f'  logic alloc_has_match; assign alloc_has_match = {has_match};\n')
        f.write(f'  logic alloc_has_free;  assign alloc_has_free  = {has_free};\n\n')

        f.write(f'  logic [{ways_w-1}:0] alloc_way;\n')
        f.write('  always_comb begin\n')
        f.write(f"    alloc_way = '0;  // default -- avoids inferring a latch; way 0 also the\n")
        f.write('                      // genuine-collision fallback (flagged by wr_collision)\n')
        for w in range(ways):
            kw = 'if' if w == 0 else 'else if'
            f.write(f'    {kw} (key_match_w{w}) alloc_way = {w};\n')
        for w in range(ways):
            f.write(f'    else if (free_w{w}) alloc_way = {w};\n')
        f.write('  end\n\n')

        f.write('  assign wr_collision = wr_pend_valid && !alloc_has_match && !alloc_has_free;\n\n')

        f.write('  always_ff @(posedge clk) begin\n')
        f.write('    if (wr_pend_valid) begin\n')
        f.write('      case (alloc_way)\n')
        for w in range(ways):
            f.write(f'        {w}: begin\n')
            f.write(f"          mem_valid_w{w}[wr_pend_addr]  <= 1'b1;\n")
            for fname, _ in key_fields:
                f.write(f'          mem_key_w{w}_{fname}[wr_pend_addr] <= wr_pend_key_{fname};\n')
            f.write(f'          mem_action_w{w}[wr_pend_addr] <= wr_pend_action;\n')
            for pname, _ in params:
                f.write(f'          mem_p_w{w}_{pname}[wr_pend_addr] <= wr_pend_p_{pname};\n')
            f.write('        end\n')
        f.write('        default: ;\n')
        f.write('      endcase\n')
        f.write('    end\n')
        f.write('  end\n\n')

        # ---- Packet-lookup path: per-way registered read + tag compare + mux ----
        n_stages = exact_match_tag_compare_stages([w for _, w in key_fields], budget_levels)
        split = (n_stages == 2)

        f.write(f'  // Registered per-way BRAM read + tag-compare stage ({n_stages}-cycle lookup\n')
        f.write('  // latency, unaffected by associativity -- packet-lookup port A of each way,\n')
        f.write('  // completely independent of the CP-write pipeline\'s port B above)\n')
        for fname, w in key_fields:
            f.write(f'  logic [{w-1}:0] key_r_{fname};\n')
        for w in range(ways):
            f.write(f'  logic        valid_r_w{w};\n')
            for fname, kw in key_fields:
                f.write(f'  logic [{kw-1}:0] mem_key_r_w{w}_{fname};\n')
            f.write(f'  logic [{act_id_w-1}:0] action_id_r_w{w};\n')
            for pname, pw in params:
                f.write(f'  logic [{pw-1}:0] p_r_w{w}_{pname};\n')
        f.write('\n')

        f.write('  always_ff @(posedge clk) begin\n')
        f.write('    if (!rst_n) begin\n')
        for w in range(ways):
            f.write(f"      valid_r_w{w} <= 1'b0;\n")
        f.write('    end else begin\n')
        for fname, _ in key_fields:
            f.write(f'      key_r_{fname} <= lkp_{fname};\n')
        for w in range(ways):
            f.write(f'      valid_r_w{w}     <= mem_valid_w{w}[lkp_addr];\n')
            for fname, _ in key_fields:
                f.write(f'      mem_key_r_w{w}_{fname} <= mem_key_w{w}_{fname}[lkp_addr];\n')
            f.write(f'      action_id_r_w{w} <= mem_action_w{w}[lkp_addr];\n')
            for pname, _ in params:
                f.write(f'      p_r_w{w}_{pname} <= mem_p_w{w}_{pname}[lkp_addr];\n')
        f.write('    end\n')
        f.write('  end\n\n')

        f.write('  // Per-way tag compare, OR-reduce, and a defaulted priority mux (default\n')
        f.write('  // assignment first, then if/else-if with no bare else needed -- avoids\n')
        f.write('  // inferring a latch). Keys are unique across ways at a given bucket by\n')
        f.write('  // construction, so at most one way should ever hit; priority order only\n')
        f.write('  // matters as a defined tie-break.\n')
        for w in range(ways):
            tag_match = ' && '.join(
                f'(mem_key_r_w{w}_{fname} == key_r_{fname})' for fname, _ in key_fields
            ) or "1'b1"
            f.write(f'  logic hit_way_w{w}; assign hit_way_w{w} = valid_r_w{w} && {tag_match};\n')
        f.write('\n')
        hit_or = ' | '.join(f'hit_way_w{w}' for w in range(ways))
        f.write(f'  logic hit_c; assign hit_c = {hit_or};\n\n')

        f.write(f'  logic [{act_id_w-1}:0] action_id_sel;\n')
        for pname, pw in params:
            f.write(f'  logic [{pw-1}:0] p_{pname}_sel;\n')
        f.write('  always_comb begin\n')
        f.write('    action_id_sel = action_id_r_w0;\n')
        for pname, _ in params:
            f.write(f'    p_{pname}_sel = p_r_w0_{pname};\n')
        for w in range(ways):
            kw = 'if' if w == 0 else 'else if'
            f.write(f'    {kw} (hit_way_w{w}) begin\n')
            f.write(f'      action_id_sel = action_id_r_w{w};\n')
            for pname, _ in params:
                f.write(f'      p_{pname}_sel = p_r_w{w}_{pname};\n')
            f.write('    end\n')
        f.write('  end\n\n')

        f.write('  // synthesis translate_off\n')
        f.write('  always_ff @(posedge clk) begin\n')
        f.write('    if (rst_n) begin\n')
        hit_sum = ' + '.join(f'hit_way_w{w}' for w in range(ways))
        f.write(f'      if (({hit_sum}) > 1)\n')
        f.write(f'        $error("%m: key present in more than one way at the same bucket -- CP-write allocator bug");\n')
        f.write('    end\n')
        f.write('  end\n')
        f.write('  // synthesis translate_on\n\n')

        # ---- Phase 6 tag-compare split, reused unchanged, retargeted onto hit_c/action_id_sel/p_*_sel ----
        mux_sel = 'hit_c'
        act_src = 'action_id_sel'
        p_src   = {pname: f'p_{pname}_sel' for pname, _ in params}

        if split:
            f.write('  logic hit_mid;\n')
            f.write(f'  logic [{act_id_w-1}:0] action_id_r2;\n')
            for pname, pw in params:
                f.write(f'  logic [{pw-1}:0] p_r2_{pname};\n')
            f.write('  always_ff @(posedge clk) begin\n')
            f.write('    if (!rst_n) begin\n')
            f.write("      hit_mid <= 1'b0;\n")
            f.write('    end else begin\n')
            f.write('      hit_mid      <= hit_c;\n')
            f.write('      action_id_r2 <= action_id_sel;\n')
            for pname, _ in params:
                f.write(f'      p_r2_{pname} <= p_{pname}_sel;\n')
            f.write('    end\n')
            f.write('  end\n\n')
            mux_sel = 'hit_mid'
            act_src = 'action_id_r2'
            p_src   = {pname: f'p_r2_{pname}' for pname, _ in params}

        f.write(f'  logic [{act_id_w-1}:0] action_id_c;\n')
        f.write(f'  assign action_id_c = {mux_sel} ? {act_src} : {act_id_w}\'d{default_act_id};\n')
        for pname, pw in params:
            f.write(f'  logic [{pw-1}:0] p_{pname}_c;\n')
            f.write(f'  assign p_{pname}_c = {mux_sel} ? {p_src[pname]} : {pw}\'b0;\n')
        f.write('\n')
        f.write('  always_ff @(posedge clk) begin\n')
        f.write('    if (!rst_n) begin\n')
        f.write("      hit <= 1'b0;\n")
        f.write('    end else begin\n')
        f.write(f'      hit <= {mux_sel};\n')
        f.write('      action_id <= action_id_c;\n')
        for pname, _ in params:
            f.write(f'      p_{pname} <= p_{pname}_c;\n')
        f.write('    end\n')
        f.write('  end\n\n')

        assert n_stages == exact_match_tag_compare_stages([w for _, w in key_fields], budget_levels), (
            f'{table.name}: split={split} but the scheduler will independently '
            f'compute a different stage count for the same inputs'
        )

        f.write('  // Action ID encoding:\n')
        for aname, aid in sorted(act_ids.items(), key=lambda x: x[1]):
            f.write(f'  //   {aid} = {aname}\n')
        f.write('\n')

        f.write('endmodule\n')


# ============================================================
# Public entry point
# ============================================================

def emit_tables(ir, out_dir, stage='ingress', budget_levels=None, ways=1, enable_query=False):
    """Generate one _table.sv per table in the processing control block.
    budget_levels: None (default) = no mid-tree pipeline splitting, output
    identical to before this parameter existed. See table_tree_stages().
    ways: 1 (default) = direct-mapped exact-match tables, output identical
    to before this parameter existed. >1 = d-way set-associative exact-match
    tables (LPM/ternary/keyless tables ignore this).
    enable_query: False (default) = today's behavior exactly, no CP query/
    delete port. True adds a query/delete port to plain (ways<=1) exact-match
    tables -- see _emit_exact_match_table. Only meaningful for the p4test/XSA
    frontend's AXI4-Lite control plane (emit_top.py); the bmv2 frontend has
    no bus wrapper to ever drive these ports, so main.py never sets this for it."""
    ctrl = _find_processing_ctrl(ir, stage)
    if ctrl is None:
        return
    amap  = {a.name: a for a in ctrl.actions}
    fwmap = _build_field_width_map(ir)
    for tbl in ctrl.tables:
        if not tbl.actions:
            continue
        out_path = os.path.join(out_dir, f'{tbl.name}_table.sv')
        _emit_one_table(ir, tbl, amap, fwmap, out_path, budget_levels=budget_levels, ways=ways, enable_query=enable_query)
        print(f'[SUCCESS] Table RTL      -> {out_path}')
