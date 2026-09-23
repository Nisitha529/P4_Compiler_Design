"""emit_top.py — generate {app}_top.sv with AXI4-Stream + AXI4-Lite interfaces.

Architecture
============
The generated top-level module wraps processing_generated with proper
network-facing interfaces (parsing/deparsing are reimplemented inline as
combinational reads/writes of the packet buffer below, not via separate
parser_generated/deparser_generated instances):

  AXI4-Stream slave  (s_axis_*)  ← incoming packet bytes
  AXI4-Stream master (m_axis_*)  → outgoing (modified) packet bytes
  AXI4-Lite slave    (s_axil_*)  → table configuration from CPU

Packet pipeline (cut-through, not store-and-forward):
  RX and TX run concurrently, decoupled, sharing a packet buffer split into
  a fixed-size header region (pkt_buf_hdr) and a payload region
  (pkt_buf_payload). Match-action processing is triggered as soon as a
  dynamically-computed "cutoff" byte position has arrived (every header
  match-action could touch, not the whole packet) rather than waiting for
  the whole packet (s_axis_tlast). TX begins streaming from byte 0 as soon
  as write-back has finalized the header region, chasing RX's arrival
  frontier through the payload region rather than waiting for RX to finish.
  See the state-machine section below for the exact registers/invariants.

AXI4-Lite address map (per table, 4-byte aligned):
  offset 0x00 : cp_wr_idx
  offset 0x04 : cp_wr_action
  offset 0x08 … : cp_wr_key_{field}  (one 32-bit reg each)
  offset after keys : cp_wr_p_{param}  (one 32-bit reg each)
  last offset : commit (write any value → cp_wr_en pulse)
Each table is allocated 256 bytes (0x100) of address space.
"""

import math
import re
from collections import defaultdict, deque

from boards import validate_board
from emit_processing import (
    _find_processing_ctrl,
    _table_params,
    _table_action_ids,
    _sig as _proc_sig,
    _collect_std_meta_inputs,
    _collect_std_meta_outputs,
    _std_meta_fname,
    _std_meta_width,
)

# ── Module-level constants ─────────────────────────────────────────────────────
#
# AXI4-Stream datapath width is a real, user-facing choice (--axi-data-width on
# main.py, threaded through emit_top()'s axi_data_width parameter below) rather
# than a fixed constant -- field extraction/write-back index pkt_buf_hdr/payload
# by byte position, not beat position, so widening the datapath is just a
# matter of re-deriving BEAT_BYTES/MAX_PKT_BYTES/HDR_IDX_W from a different
# axi_data_width and regenerating; no other logic depends on a specific width.
#
# MAX_AXI_DATA_W is a real ceiling, not an arbitrary one: every additional
# doubling of the datapath doubles the per-cycle byte-lane write/mux fan-out
# into pkt_buf_hdr/pkt_buf_payload (each lane is an independent byte-enabled
# write into the same array at a computed offset -- real BRAM primitives are
# only a few bytes wide per port, so a wide logical write synthesizes as
# several parallel banked BRAMs, and area/routing congestion grows with it).
# 512 bits (64 bytes/cycle) matches real high-throughput (100G+-class)
# streaming datapaths and is already generous for this project's only
# synthesis-validated target (a WebPACK-tier Artix-7 part, `xc7a100tcsg324-1`)
# -- going wider than this has not been synthesized or measured on anything in
# this project, so treat it as a hard, unvalidated wall, not a soft suggestion.
DEFAULT_AXI_DATA_W = 256
MAX_AXI_DATA_W     = 512

# Traffic-manager queue count for a program that selects an output port. The
# queue index is the low bits of egress_port, so this is a power of two; the
# round-robin scheduler is a flat priority encoder over it, and each queue
# costs NSLOT entries of SLOT_AW bits, which is negligible. A program with no
# egress_port gets a single queue and the pre-TM behaviour.
TM_QUEUES = 4

# How many packets may be past the scheduler at once -- inside the egress
# pipeline or waiting for the wire. Small enough that packets actually queue
# (otherwise the scheduler never sees a choice and the TM is decorative),
# large enough to cover the egress pipeline's latency so TX never bubbles.
# Measured on the load_balance_p4rtl stream harness (cycles/packet, 64 B):
#   1 -> 5.50   2 -> 3.69   3 -> 3.62   4 -> 3.62
# so 2 is the smallest window that keeps throughput, which is also the one
# that leaves the most packets queued for the scheduler to choose between.
TM_INFLIGHT = 2

MAX_PKT_BEATS = 256     # max packet size in AXI4-Stream beats (beat count is
                        # independent of datapath width; MAX_PKT_BYTES below
                        # scales with whichever width a given run selects)
AXIL_DATA_W   = 32      # AXI4-Lite data width
AXIL_ADDR_W   = 16      # AXI4-Lite address width
TABLE_AXIL_SZ = 0x100   # bytes of AXI4-Lite address space allocated per table


# ── Header size helpers ────────────────────────────────────────────────────────

def _hdr_bits_total(inst):
    return sum(f.width or 0 for f in inst.header_type.fields)


def _hdr_bytes_total(inst):
    return _hdr_bits_total(inst) // 8


def _is_len_field(fname):
    """True if this field carries the header's own byte-length (like IP IHL)."""
    return fname.lower() in ('hdr_len', 'ihl', 'data_offset', 'dataoffset', 'doff')


def _worst_case_hdr_bytes(layouts, inst_map):
    """
    Compile-time upper bound on the byte position one-past-the-end of every
    header in `layouts`, accounting for the *worst-case runtime value* of
    every length field feeding a variable header's base offset (e.g. IPv4
    hdr_len maxes at 15 -> 60 bytes of header+options), not just nominal
    fixed header sizes. Mirrors _emit_offset_vars's var_pred walk but
    computes a Python int instead of emitting a wire -- used only to size
    pkt_buf_hdr; the real, tighter, per-packet cutoff is computed at
    runtime by _emit_cutoff_expr.

    Requires every var_pred length field to be unsigned (true for hdr_len/
    dataOffset-style fields) -- the sizing (and the separate runtime cutoff
    safety argument) both rely on a length field's contribution only ever
    adding bytes, never subtracting.
    """
    worst_base = {}  # inst_name -> worst-case base offset (bytes)

    for layout in layouts:
        inst_name      = layout['inst_name']
        mandatory_base = layout['mandatory_base']
        optional_preds = layout['optional_preds']
        var_pred       = layout['var_pred']

        if not optional_preds and var_pred is None:
            worst_base[inst_name] = mandatory_base
        elif var_pred is None:
            # Worst case: every optional predecessor present.
            worst_base[inst_name] = mandatory_base + sum(sz for _, sz in optional_preds)
        else:
            vname, vfield = var_pred
            prev_worst = worst_base.get(vname, 0)
            vinst = inst_map.get(vname)
            width = None
            if vinst:
                for fld in vinst.header_type.fields:
                    if fld.name == vfield:
                        width = fld.width
                        break
            max_len_words = (2 ** (width or 4)) - 1
            # Same scale factor (32-bit words -> bytes) as _emit_offset_vars.
            worst_base[inst_name] = prev_worst + max_len_words * 4

    worst_end = 0
    for layout in layouts:
        inst_name = layout['inst_name']
        inst = inst_map.get(inst_name)
        if not inst:
            continue
        base = worst_base.get(inst_name, layout['mandatory_base'])
        worst_end = max(worst_end, base + _hdr_bytes_total(inst))

    return worst_end


# ── Byte offset layout computation ────────────────────────────────────────────

def _compute_layout(ir, inst_map):
    """
    Walk all paths from 'start', computing byte offsets for each header.

    Returns list of dicts (in extraction order):
      {
        'inst_name':      str,
        'mandatory_base': int,   # bytes always preceding this header
        'optional_preds': list of (inst_name, size_bytes),  # conditional predecessors
        'var_pred':       (inst_name, len_field_name) or None,
      }
    """
    header_occurrences = defaultdict(list)  # inst_name -> list of frozenset
    header_var_pred    = {}                 # inst_name -> (var_inst, len_field)
    header_order       = []
    header_order_set   = set()

    visited = set()
    queue   = deque()
    queue.append(('start', frozenset(), None))  # (state, mand_set, var_pred)

    while queue:
        state_name, mand_before, var_pred_in = queue.popleft()

        key = (state_name, mand_before, var_pred_in)
        if key in visited:
            continue
        visited.add(key)

        state = ir.parser_states.get(state_name)
        if not state:
            continue

        cur_mand     = set(mand_before)
        cur_var_pred = var_pred_in

        for ext in state.extracts:
            inst_name = ext.header
            if inst_name not in header_order_set:
                header_order.append(inst_name)
                header_order_set.add(inst_name)

            header_occurrences[inst_name].append(frozenset(cur_mand))
            if cur_var_pred and inst_name not in header_var_pred:
                header_var_pred[inst_name] = cur_var_pred

            inst = inst_map.get(inst_name)
            if not ext.dynamic and inst:
                size = _hdr_bytes_total(inst)
                cur_mand.add((inst_name, size))
                # If this header has a length field, mark successors as variable-offset
                for f in inst.header_type.fields:
                    if _is_len_field(f.name) and cur_var_pred is None:
                        cur_var_pred = (inst_name, f.name)
                        break

        def propagate(nxt):
            if nxt in ('accept', 'reject', None):
                return
            queue.append((nxt, frozenset(cur_mand), cur_var_pred))

        if state.next_state:
            propagate(state.next_state)
        if state.select:
            for _, dst in state.select.cases:
                propagate(dst)
            if state.select.default:
                propagate(state.select.default)

    # Build layout entries
    layouts = []
    for inst_name in header_order:
        inst = inst_map.get(inst_name)
        if not inst or inst.is_stack:
            continue

        all_mand_sets = header_occurrences[inst_name]
        if not all_mand_sets:
            continue

        # mandatory = intersection across all occurrences
        mandatory = set(all_mand_sets[0])
        for ms in all_mand_sets[1:]:
            mandatory &= ms

        # optional = union minus mandatory (headers sometimes but not always before this one)
        all_hdrs = set()
        for ms in all_mand_sets:
            all_hdrs |= ms
        optional = all_hdrs - mandatory

        mandatory_base = sum(s for _, s in mandatory)
        optional_preds = sorted(optional, key=lambda x: x[0])

        layouts.append({
            'inst_name':      inst_name,
            'mandatory_base': mandatory_base,
            'optional_preds': optional_preds,
            'var_pred':       header_var_pred.get(inst_name),
        })

    return layouts


# ── SV byte-extraction expression ─────────────────────────────────────────────

def _byte_idx(base_expr, byte_num, target='pkt_buf_hdr'):
    """
    Return SV array-index expression into pkt_buf_hdr. Every field this
    compiler extracts/writes-back lives in the header region by
    construction of HDR_MAX_BYTES's sizing (see _worst_case_hdr_bytes) --
    pkt_buf_payload is only ever touched by the RX-capture/TX-replay
    per-beat routing logic, never by field-level extraction/write-back.
    """
    if base_expr in (0, '0', "8'd0"):
        return f'{target}[{byte_num}]'
    if byte_num == 0:
        return f'{target}[{base_expr}]'
    return f'{target}[{base_expr}+{byte_num}]'


def _extract_expr(base_expr, bit_offset_in_hdr, width, target='pkt_buf_hdr'):
    """
    SV expression to extract 'width' bits starting at bit_offset_in_hdr (MSB-first)
    from a header whose first byte is at pkt_buf[base_expr].
    """
    if width <= 0:
        return "'0"
    parts = []
    bits_rem  = width
    cur_byte  = bit_offset_in_hdr // 8
    cur_bit   = bit_offset_in_hdr % 8   # bits used from MSB so far in this byte

    while bits_rem > 0:
        avail = 8 - cur_bit
        take  = min(avail, bits_rem)
        hi    = 7 - cur_bit
        lo    = hi - take + 1

        ref = _byte_idx(base_expr, cur_byte, target)
        if take == 8:
            parts.append(ref)
        else:
            parts.append(f'{ref}[{hi}:{lo}]')

        bits_rem -= take
        cur_byte += 1
        cur_bit   = 0

    return ('{' + ', '.join(parts) + '}') if len(parts) > 1 else parts[0]


# ── SV byte write-back for one header ─────────────────────────────────────────

def _writeback_bytes(f, inst_name, base_expr, hdr_type, out_pfx, cond_expr, ind,
                     target='pkt_buf_hdr', op='<='):
    """
    Emit per-byte placement statements for all bytes of a header, at the
    header's layout-derived byte offset (base_expr + byte index).
    cond_expr: optional SV guard (e.g. 'w_vlan_valid'). None → no guard.
    out_pfx  : signal prefix (e.g. 'out_') — processing output signals.
    target/op: `pkt_buf_hdr` + `<=` is the original registered write-back;
               `hdr_out` + `=` is the combinational deparser overlay
               (step 2 of docs/streaming_shell_plan.md) -- same placement
               logic, so the two can never disagree about WHERE a byte goes.
    """
    total_bits  = sum(fld.width or 0 for fld in hdr_type.fields)
    total_bytes = total_bits // 8

    # Map: byte_idx -> list of (out_sig, fld_hi, fld_lo, byte_hi, byte_lo)
    byte_map = defaultdict(list)
    bit_off = 0
    for fld in hdr_type.fields:
        w = fld.width or 0
        if w == 0:
            continue
        sig = f'{out_pfx}{inst_name}_{fld.name}'
        fld_start = bit_off
        fld_end   = bit_off + w
        for bi in range(fld_start // 8, (fld_end - 1) // 8 + 1):
            b_start = bi * 8
            b_end   = b_start + 8
            ov_s    = max(fld_start, b_start)
            ov_e    = min(fld_end,   b_end)
            if ov_s >= ov_e:
                continue
            taken   = ov_e - ov_s
            b_hi    = 7 - (ov_s - b_start)
            b_lo    = b_hi - taken + 1
            f_hi    = w - 1 - (ov_s - fld_start)
            f_lo    = f_hi - taken + 1
            byte_map[bi].append((sig, w, f_hi, f_lo, b_hi, b_lo, taken))
        bit_off += w

    if cond_expr:
        f.write(f'{ind}if ({cond_expr}) begin\n')
        inner = ind + '    '
    else:
        inner = ind

    for bi in range(total_bytes):
        parts = byte_map.get(bi, [])
        if not parts:
            continue
        parts.sort(key=lambda x: -x[4])   # sort by byte_hi descending (MSB first)
        pieces = []
        for sig, fw, fh, fl, bh, bl, taken in parts:
            if taken == fw:        # whole field
                pieces.append(sig)
            elif fh == fl:         # single bit
                pieces.append(f'{sig}[{fh}]')
            else:
                pieces.append(f'{sig}[{fh}:{fl}]')
        rhs = ('{' + ', '.join(pieces) + '}') if len(pieces) > 1 else pieces[0]
        f.write(f'{inner}{_byte_idx(base_expr, bi, target)} {op} {rhs};\n')

    if cond_expr:
        f.write(f'{ind}end\n')


# ── AXI4-Lite register map ─────────────────────────────────────────────────────

def _build_axil_regmap(ctrl, amap, fwmap, ectrl=None, eamap=None):
    """
    Return list of table register-map entries, ingress control first, then
    (P4RtlPipeline) the egress control's, each tagged 'stage' so the
    instantiation code knows which processing module the cp_* ports belong
    to. Table and counter names must be unique across the two controls: they
    name the AXI4-Lite windows and the storage modules.
    [
      {
        'tname': str,
        'stage': 'ingress' | 'egress',
        'base':  int,   # byte offset in AXI4-Lite address space
        'regs':  [(reg_name, cp_sig_name, width_bits)],  # WRITABLE words, in order
        'read_regs': [(reg_name, cp_sig_name_or_None, width_bits)],  # READ-ONLY words
        'idx_w': int,
        'act_w': int,
        'params': [(pname, pw), ...],
        'supports_query': bool,  # True only for real-keyed exact-match tables --
            # see _emit_exact_match_table's cp_query_* ports. LPM/ternary/keyless
            # tables (and, if ever reached here, the d-way associative exact-match
            # variant -- emit_top.py never threads --exact-match-ways today, so
            # every table this file generates is ways=1) don't get query/delete.
      }, ...
    ]

    `regs` is iterated verbatim by the write-decode case in _emit_axil_decoder --
    anything placed there becomes writable, so read-only registers must only ever
    go in `read_regs`, never `regs`.
    """
    result = []
    base   = 0
    seen   = {}

    for stage, c, am in (('ingress', ctrl, amap), ('egress', ectrl, eamap)):
      if c is None:
        continue
      for tbl in c.tables:
        tname   = tbl.name
        if tname in seen:
            raise ValueError(f"table '{tname}' is declared in both the {seen[tname]} "
                             f"and {stage} controls -- names must be unique across the pipeline")
        seen[tname] = stage
        depth   = tbl.size or 1024
        idx_w   = max(1, math.ceil(math.log2(max(depth, 2))))
        act_ids = _table_action_ids(tbl)
        n_acts  = max(act_ids.values()) + 1 if act_ids else 1
        act_w   = max(1, math.ceil(math.log2(max(n_acts, 2))))
        params  = _table_params(tbl, am)

        mt = tbl.keys[0].match_type if tbl.keys else 'exact'
        supports_query = bool(tbl.keys) and mt not in ('lpm', 'ternary')

        regs = []
        regs.append(('wr_idx',    f'{tname}_cp_wr_idx',    idx_w))
        regs.append(('wr_action', f'{tname}_cp_wr_action', act_w))
        key_regs = []  # (kbase, kw) -- reused below for query_key_*
        for key in tbl.keys:
            kname = _proc_sig(key.field)                 # e.g. 'ipv4_src' -- fwmap width lookup
            kbase = key.field.strip().split('.')[-1]      # e.g. 'src' -- matches processing_generated's
                                                            # actual cp_wr_key_{basename} port name
                                                            # (emit_processing.py uses _field_basename,
                                                            # not the full dotted-path _sig -- pre-existing
                                                            # mismatch, fixed here since it otherwise blocks
                                                            # even compiling {app}_top.sv against
                                                            # processing_generated.sv)
            # Widths: header fields from fwmap; standard_metadata keys (e.g.
            # egress_port in a P4RtlPipeline egress table) from the
            # architecture's own struct, matching the cp_wr_key_* port width.
            # metadata keys (meta.X) are resolved by the caller through fwmap too.
            kw    = fwmap.get(kname)
            if kw is None:
                sm = _std_meta_fname(key.field)
                kw = _std_meta_width(sm, 32) if sm else 32
            key_regs.append((kbase, kw))
            regs.append((f'key_{kbase}', f'{tname}_cp_wr_key_{kbase}', kw))
        # LPM/ternary tables carry one extra control-plane input each beyond
        # the plain key words -- emit_processing.py already declares these as
        # real ports (cp_wr_pfx_len / cp_wr_mask_{field}) and wires them into
        # the table instance, but nothing here ever exposed or connected them,
        # so on this frontend an LPM table's prefix length sat permanently
        # undriven and the table could never be correctly populated. Widths
        # below mirror emit_processing.py's own port declarations exactly.
        if mt == 'lpm':
            key_w = key_regs[0][1] if key_regs else 32
            pfx_w = max(1, math.ceil(math.log2(key_w + 1)))
            regs.append(('wr_pfx_len', f'{tname}_cp_wr_pfx_len', pfx_w))
        elif mt == 'ternary':
            for kbase, kw in key_regs:
                regs.append((f'wr_mask_{kbase}', f'{tname}_cp_wr_mask_{kbase}', kw))
        for pname, pw in params:
            regs.append((f'p_{pname}', f'{tname}_cp_wr_p_{pname}', pw))
        regs.append(('commit', f'{tname}_cp_wr_en', 1))   # sentinel

        read_regs = []
        if supports_query:
            for kbase, kw in key_regs:
                regs.append((f'query_key_{kbase}', f'{tname}_cp_query_key_{kbase}', kw))
            # Two separate trigger words (not one word with a mode bit) --
            # clearer verbs for a driver. Both ultimately pulse the same
            # cp_query_en; _emit_axil_decoder sets cp_query_del from which
            # one was written.
            regs.append(('query_commit',  f'{tname}_cp_query_en', 1))
            regs.append(('delete_commit', f'{tname}_cp_query_en', 1))

            # cp_sig=None for query_status: it's a composite (busy@bit0,
            # hit@bit1), not a single existing port -- _emit_axil_decoder
            # special-cases it rather than reading a wire directly.
            read_regs.append(('query_status', None, 32))
            read_regs.append(('query_action_id', f'{tname}_cp_query_action_id', act_w))
            for pname, pw in params:
                read_regs.append((f'query_p_{pname}', f'{tname}_cp_query_p_{pname}', pw))

        result.append({
            'tname': tname,
            'stage': stage,
            'base':  base,
            'regs':  regs,
            'read_regs': read_regs,
            'idx_w': idx_w,
            'act_w': act_w,
            'params': params,
            'supports_query': supports_query,
        })
        base += TABLE_AXIL_SZ

    # Counter externs get their own register-map entry, reusing the same
    # generic AXI4-Lite staging/write-FSM/read-FSM machinery in
    # _emit_axil_decoder as tables -- but with a smaller, read-only shape
    # (query-only, no cp_wr_en/commit word, no delete, no "hit" concept: an
    # index is always valid). Marked 'is_counter' so _emit_axil_decoder and
    # the u_proc wiring below skip the table-only cp_wr/cp_query_del/hit_out
    # ports a counter doesn't have -- a counter's storage lives in its own
    # separate {Name}_counter module (see emit_counters.py), not inside
    # processing_generated, so it isn't wired through u_proc's table ports
    # at all.
    for stage, c in (('ingress', ctrl), ('egress', ectrl)):
      if c is None:
        continue
      for cnt in c.counters:
        cname = cnt.name
        if cname in seen:
            raise ValueError(f"'{cname}' is declared in both the {seen[cname]} and "
                             f"{stage} controls -- table/counter names must be unique across the pipeline")
        seen[cname] = stage
        idx_w = max(1, math.ceil(math.log2(max(cnt.size, 2))))
        has_pkt  = cnt.counter_type in ('PACKETS', 'PACKETS_AND_BYTES')
        has_byte = cnt.counter_type in ('BYTES', 'PACKETS_AND_BYTES')

        regs = [
            ('query_idx',    f'{cname}_cp_query_idx', idx_w),
            ('query_commit', f'{cname}_cp_query_en',  1),
        ]
        read_regs = [('query_status', None, 32)]
        if has_pkt:
            read_regs += [('value_pkt_lo', f'{cname}_cp_query_pkt_value[31:0]',  32),
                          ('value_pkt_hi', f'{cname}_cp_query_pkt_value[63:32]', 32)]
        if has_byte:
            read_regs += [('value_byte_lo', f'{cname}_cp_query_byte_value[31:0]',  32),
                          ('value_byte_hi', f'{cname}_cp_query_byte_value[63:32]', 32)]

        result.append({
            'tname': cname,
            'stage': stage,
            'base':  base,
            'regs':  regs,
            'read_regs': read_regs,
            'idx_w': idx_w,
            'act_w': 0,
            'params': [],
            'supports_query': True,
            'is_counter': True,
            'has_pkt': has_pkt,
            'has_byte': has_byte,
        })
        base += TABLE_AXIL_SZ

    return result


# ── AXI4-Lite decoder SV emission ─────────────────────────────────────────────

def _reg_words(regs):
    """Expand a register list into the 32-bit bus words it occupies.

    Yields (word_offset, word_name, cp_sig, lo, take) for every word. A
    register no wider than the bus is one word at bit 0. A WIDER one -- a
    48-bit MAC action parameter, a 48-bit MAC exact-match key -- spans
    ceil(width/32) consecutive words, least-significant word first, named
    <reg>_w0, <reg>_w1, ...

    Before this, every register was exactly one word and anything wider was
    silently clipped to the low 32 bits in BOTH directions
    (`take = min(width, 32)` on write, `r_rdata <= cp_sig` on read). A
    48-bit MAC could never be programmed or read back with a non-zero upper
    16 bits. fiveTuple never exposed it because every one of its keys and
    params is <= 32 bits; load_balance_xsa's nhop_dmac / smac are the first
    48-bit ones. Callers that only need one entry per register (the u_proc
    port wiring) keep iterating the original list; only the address decoder
    and its word-count bookkeeping go through this."""
    off = 0
    for rname, cp_sig, width in regs:
        n = max(1, math.ceil(width / AXIL_DATA_W))
        for w in range(n):
            lo   = w * AXIL_DATA_W
            take = min(AXIL_DATA_W, width - lo)
            yield off, (rname if n == 1 else f'{rname}_w{w}'), cp_sig, lo, take
            off += 1


def _n_words(regs):
    return sum(max(1, math.ceil(w / AXIL_DATA_W)) for _, _, w in regs)


def _emit_axil_decoder(f, regmap):
    """Emit AXI4-Lite staging registers and write/read channel state machines."""
    if not regmap:
        return

    # Staging registers for all tables
    f.write('\n  // ── AXI4-Lite staging registers ─────────────────────────────────────────\n')
    for ti in regmap:
        tname = ti['tname']
        for rname, cp_sig, width in ti['regs']:
            if rname in ('commit', 'query_commit', 'delete_commit'):
                continue
            f.write(f'  logic [{width-1}:0] r_{cp_sig};\n')
        if ti['supports_query'] and not ti.get('is_counter'):
            f.write(f'  logic r_{tname}_cp_query_del;\n')

    # cp_wr_en / cp_query_en per-table
    for ti in regmap:
        f.write(f'  logic r_{ti["tname"]}_cp_wr_en;\n')
        if ti['supports_query']:
            f.write(f'  logic r_{ti["tname"]}_cp_query_en;\n')

    f.write('''
  // AXI4-Lite write channel state machine
  typedef enum logic [1:0] {
    AXIL_IDLE  = 2'd0,
    AXIL_WDATA = 2'd1,
    AXIL_BRESP = 2'd2
  } axil_st_t;

  axil_st_t               axil_st;
  logic [AXIL_ADDR_W-1:0] axil_awaddr_r;

  assign s_axil_awready = (axil_st == AXIL_IDLE);
  assign s_axil_bvalid  = (axil_st == AXIL_BRESP);
  assign s_axil_bresp   = 2\'b00;

''')

    # Real AXI4-Lite backpressure: a commit-type word (commit/query_commit/
    # delete_commit) for a table that's currently mid-query/delete must not
    # be accepted -- wready itself stays low (the master, per protocol,
    # keeps wvalid/wdata stable) until the table is free, rather than
    # accepting-then-silently-dropping the write. Only tables with
    # supports_query have a busy concept at all; every other commit-type
    # word is never stalled (unconditional commit, same as before this
    # feature existed).
    f.write('  // Commit-type words for a busy table stall wready instead of silently\n')
    f.write('  // dropping the write (see cp_query_busy on the query/delete pipeline).\n')
    f.write('  logic pending_commit_busy;\n')
    f.write('  always @(*) begin\n')
    f.write("    pending_commit_busy = 1'b0;\n")
    f.write('    case (axil_awaddr_r[AXIL_ADDR_W-1:2])\n')
    for ti in regmap:
        if not ti['supports_query']:
            continue
        tname = ti['tname']
        base  = ti['base']
        commit_words = []
        # Same word expansion as the decoder, so a commit word that sits AFTER
        # a >32-bit register lands on the address the decoder actually gave it.
        for idx, rname, cp_sig, lo, take in _reg_words(ti['regs']):
            if rname in ('commit', 'query_commit', 'delete_commit'):
                commit_words.append((base + idx * 4) >> 2)
        # One case arm per address (not a comma-joined multi-value label --
        # iverilog doesn't reliably handle those inside always_comb: "sorry:
        # constant selects in always_* processes are not currently supported").
        for w in commit_words:
            f.write(f"      {AXIL_ADDR_W-2}'d{w}: pending_commit_busy = {tname}_cp_query_busy;\n")
    f.write('      default: pending_commit_busy = 1\'b0;\n')
    f.write('    endcase\n')
    f.write('  end\n')
    f.write('  assign s_axil_wready = (axil_st == AXIL_WDATA) && !pending_commit_busy;\n\n')

    f.write('  always_ff @(posedge clk) begin\n')
    f.write('    if (!rst_n) begin\n')
    f.write('      axil_st <= AXIL_IDLE;\n')
    for ti in regmap:
        f.write(f'      r_{ti["tname"]}_cp_wr_en <= 1\'b0;\n')
        if ti['supports_query']:
            f.write(f'      r_{ti["tname"]}_cp_query_en <= 1\'b0;\n')
    f.write('    end else begin\n')
    # Default: de-assert all commit-type pulses each cycle
    for ti in regmap:
        f.write(f'      r_{ti["tname"]}_cp_wr_en <= 1\'b0;\n')
        if ti['supports_query']:
            f.write(f'      r_{ti["tname"]}_cp_query_en <= 1\'b0;\n')
    f.write('      case (axil_st)\n')
    f.write('        AXIL_IDLE: begin\n')
    f.write('          if (s_axil_awvalid) begin\n')
    f.write('            axil_awaddr_r <= s_axil_awaddr;\n')
    f.write('            axil_st       <= AXIL_WDATA;\n')
    f.write('          end\n')
    f.write('        end\n')
    f.write('        AXIL_WDATA: begin\n')
    f.write('          if (s_axil_wvalid && s_axil_wready) begin\n')
    f.write('            case (axil_awaddr_r[AXIL_ADDR_W-1:2])  // word address\n')

    for ti in regmap:
        tname = ti['tname']
        base  = ti['base']
        for idx, rname, cp_sig, lo, take in _reg_words(ti['regs']):
            word_addr = (base + idx * 4) >> 2
            if rname == 'commit':
                f.write(f"              {AXIL_ADDR_W-2}'d{word_addr}: "
                        f"r_{tname}_cp_wr_en <= 1'b1; // {tname} commit\n")
            elif rname == 'query_commit':
                if ti.get('is_counter'):
                    f.write(f"              {AXIL_ADDR_W-2}'d{word_addr}: "
                            f"r_{tname}_cp_query_en <= 1'b1; // {tname} query\n")
                else:
                    f.write(f"              {AXIL_ADDR_W-2}'d{word_addr}: begin "
                            f"r_{tname}_cp_query_en <= 1'b1; r_{tname}_cp_query_del <= 1'b0; "
                            f"end // {tname} query\n")
            elif rname == 'delete_commit':
                f.write(f"              {AXIL_ADDR_W-2}'d{word_addr}: begin "
                        f"r_{tname}_cp_query_en <= 1'b1; r_{tname}_cp_query_del <= 1'b1; "
                        f"end // {tname} delete\n")
            else:
                dst = f"r_{cp_sig}" if lo == 0 and take == AXIL_DATA_W else f"r_{cp_sig}[{lo+take-1}:{lo}]"
                if lo == 0 and take < AXIL_DATA_W:
                    dst = f"r_{cp_sig}"      # narrow reg: whole thing, no slice needed
                f.write(f"              {AXIL_ADDR_W-2}'d{word_addr}: "
                        f"{dst} <= s_axil_wdata[{take-1}:0]; // {rname}\n")

    f.write('              default: ; // ignore unknown address\n')
    f.write('            endcase\n')
    f.write('            axil_st <= AXIL_BRESP;\n')
    f.write('          end\n')
    f.write('        end\n')
    f.write('        AXIL_BRESP: begin\n')
    f.write('          if (s_axil_bready) axil_st <= AXIL_IDLE;\n')
    f.write('        end\n')
    f.write('        default: axil_st <= AXIL_IDLE;\n')
    f.write('      endcase\n')
    f.write('    end\n')
    f.write('  end\n\n')

    # AXI4-Lite read channel: a real 2-state FSM (AR/R are the only two
    # channels here, unlike the write side's AW/W/B, so 2 states is the
    # structurally correct analog of the write side's 3 -- not a shortcut).
    # arready must be state-gated (not unconditionally 1) so a second
    # ARVALID can't be wrongly accepted while a prior RDATA is still
    # pending RREADY.
    f.write('  // AXI4-Lite read channel\n')
    f.write('  typedef enum logic {\n')
    f.write("    AXIL_R_IDLE = 1'd0,\n")
    f.write("    AXIL_R_DATA = 1'd1\n")
    f.write('  } axil_rst_t;\n\n')
    f.write('  axil_rst_t   axil_rst;\n')
    f.write('  logic [31:0] r_rdata;\n\n')
    f.write('  assign s_axil_arready = (axil_rst == AXIL_R_IDLE);\n')
    f.write('  assign s_axil_rdata   = r_rdata;\n')
    f.write('  assign s_axil_rresp   = 2\'b00;\n')
    f.write('  assign s_axil_rvalid  = (axil_rst == AXIL_R_DATA);\n\n')

    def _rdata_expr(cp_sig, lo, take):
        src = cp_sig if (lo == 0 and take == AXIL_DATA_W) else f"{cp_sig}[{lo+take-1}:{lo}]"
        if lo == 0 and take < AXIL_DATA_W:
            src = cp_sig   # narrow reg: whole thing
        if take >= 32:
            return src
        return f"{{{32-take}'d0, {src}}}"

    f.write('  always_ff @(posedge clk) begin\n')
    f.write('    if (!rst_n) begin\n')
    f.write('      axil_rst <= AXIL_R_IDLE;\n')
    f.write('    end else begin\n')
    f.write('      case (axil_rst)\n')
    f.write('        AXIL_R_IDLE: begin\n')
    f.write('          if (s_axil_arvalid) begin\n')
    f.write('            case (s_axil_araddr[AXIL_ADDR_W-1:2])  // word address\n')
    for ti in regmap:
        tname = ti['tname']
        base  = ti['base']
        n_write_words = _n_words(ti['regs'])
        for idx, rname, cp_sig, lo, take in _reg_words(ti['read_regs']):
            word_addr = (base + (n_write_words + idx) * 4) >> 2
            if rname == 'query_status':
                if ti.get('is_counter'):
                    expr = f'{{31\'d0, {tname}_cp_query_busy}}'
                else:
                    expr = f'{{30\'d0, {tname}_cp_query_hit, {tname}_cp_query_busy}}'
            else:
                expr = _rdata_expr(cp_sig, lo, take)
            f.write(f"              {AXIL_ADDR_W-2}'d{word_addr}: r_rdata <= {expr}; // {tname} {rname}\n")
    f.write("              default: r_rdata <= 32'd0;\n")
    f.write('            endcase\n')
    f.write('            axil_rst <= AXIL_R_DATA;\n')
    f.write('          end\n')
    f.write('        end\n')
    f.write('        AXIL_R_DATA: begin\n')
    f.write('          if (s_axil_rready) axil_rst <= AXIL_R_IDLE;\n')
    f.write('        end\n')
    f.write('        default: axil_rst <= AXIL_R_IDLE;\n')
    f.write('      endcase\n')
    f.write('    end\n')
    f.write('  end\n\n')


# ── Parser select signal extraction ───────────────────────────────────────────

def _collect_select_signals(ir):
    """Return set of signal names used in parser select expressions."""
    sigs = set()
    for state in ir.parser_states.values():
        if state.select and state.select.expression:
            expr = state.select.expression
            # Convert 'hdr.eth.type' → 'w_eth_type'
            m = re.match(r'hdr\.(\w+)\.(\w+)', expr)
            if m:
                sigs.add(f'w_{m.group(1)}_{m.group(2)}')
    return sigs


# ── Validity signal expressions ────────────────────────────────────────────────

def _verify_cond_to_w(cond):
    """Map a parser verify() condition onto the top's extracted-field wires.

    ingest_p4ir.py has already run the text through _convert_expr, so literals
    are SV-ready (4'd4) and stack indices are flattened; all that is left is
    hdr.<inst>.<field> -> w_<inst>_<field>, the same naming the validity
    expressions above use."""
    return re.sub(r'\bhdr\.(\w+)\.(\w+)\b', r'w_\1_\2', cond)


def _split_verify_args(raw):
    """(condition, error_literal) from Verify.condition, splitting on the
    LAST top-level comma -- the condition may contain commas of its own."""
    depth, cut = 0, -1
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


def _gen_valid_signals(ir, inst_map, layouts, verify_out=None):
    """
    Compute a combinational SV validity expression for each header instance.

    Algorithm:
      1. Build in-edge list: for each state, the (predecessor, branch_condition) pairs.
      2. Topological sort (parser is acyclic, so DFS post-order).
      3. In topological order, compute each state's reachability condition as
         OR of (pred_cond AND branch_cond) over all predecessors.  Because
         predecessor conditions are final before successors are computed, no
         state is re-visited and no condition is redundantly OR-ed.
      4. Map each header to the condition of the state that extracts it.

    Returns dict: {inst_name: sv_expr}
    """

    def _or(a, b):
        if a == "1'b1" or b == "1'b1": return "1'b1"
        if not a: return b
        if not b: return a
        if a == b: return a
        return f'({a} || {b})'

    def _and(a, b):
        if a == "1'b1": return b
        if b == "1'b1": return a
        if not a or not b: return "1'b1"
        if a == b: return a
        return f'({a} && {b})'

    _SINKS = frozenset({'accept', 'reject', None})

    # Step 1: build in-edges  state → [(pred, branch_cond|None)]
    in_edges = defaultdict(list)
    for sname, state in ir.parser_states.items():
        if state.select:
            sel_expr = state.select.expression or ''
            m = re.match(r'hdr\.(\w+)\.(\w+)', sel_expr)
            sel_sig = f'w_{m.group(1)}_{m.group(2)}' if m else sel_expr
            for val, dst in state.select.cases:
                if dst not in _SINKS:
                    sv_val = _p4lit_to_sv(val)
                    in_edges[dst].append((sname, f'({sel_sig} == {sv_val})'))
            if state.select.default and state.select.default not in _SINKS:
                in_edges[state.select.default].append((sname, None))
        elif state.next_state and state.next_state not in _SINKS:
            in_edges[state.next_state].append((sname, None))

    # Step 2: topological sort via DFS post-order (reverse)
    visited_topo = set()
    topo = []

    def _dfs(s):
        if s in visited_topo or s in _SINKS:
            return
        visited_topo.add(s)
        state = ir.parser_states.get(s)
        if state:
            if state.select:
                for _, dst in state.select.cases:
                    _dfs(dst)
                if state.select.default:
                    _dfs(state.select.default)
            elif state.next_state:
                _dfs(state.next_state)
        topo.append(s)

    _dfs('start')
    topo.reverse()   # now topo[0] = 'start'

    # verify() lowering. P4: a failing verify transitions to `reject`, so
    # nothing AFTER that state is reached -- but the header the state itself
    # extracted stays valid, because P4 extracts first and verifies after.
    # Both fall out of folding each state's verify conditions into its
    # OUTGOING edges only: a state's own reachability (and so its header's
    # validity, step 4) is unaffected, while every successor's reachability
    # now also requires this state's verifies to have passed.
    #
    # This is the parallel-extractor counterpart of emit_parser.py's REJECT
    # state. The FSM there is a reference model that no generated top
    # instantiates; THIS is the lowering that ships, so without this the
    # verify() had no effect on the synthesized design at all.
    verify_ok = {}     # state -> SV condition that all its verifies pass
    verify_list = {}   # state -> [(cond_w, err_literal)] in source order
    for sname, state in ir.parser_states.items():
        terms = []
        for v in getattr(state, 'verifies', []):
            cond, errv = _split_verify_args(v.condition)
            if errv is None:
                continue
            terms.append((_verify_cond_to_w(cond), errv))
        if terms:
            verify_list[sname] = terms
            ok = None
            for c, _ in terms:
                ok = _and(ok, f'({c})') if ok else f'({c})'
            verify_ok[sname] = ok

    # Step 3: compute state reachability in topological order
    state_cond = {'start': "1'b1"}
    for sname in topo:
        if sname == 'start':
            continue
        combined = None
        for pred, branch_cond in in_edges.get(sname, []):
            pc = state_cond.get(pred, "1'b0")
            tc = _and(pc, branch_cond) if branch_cond else pc
            if pred in verify_ok:
                tc = _and(tc, verify_ok[pred])
            combined = _or(combined, tc) if combined is not None else tc
        state_cond[sname] = combined if combined is not None else "1'b0"

    # parser_error terms, for the caller: (state reached, this verify FAILED,
    # error code), in topological then source order -- so a priority chain
    # over them reports the FIRST failure on the packet's actual path, which
    # is what the FSM would have latched.
    if verify_out is not None:
        for sname in topo:
            for cond_w, errv in verify_list.get(sname, []):
                verify_out.append((state_cond.get(sname, "1'b0"), cond_w, errv))

    # Step 4: map headers to their state's condition
    valid_map = {}
    for sname, state in ir.parser_states.items():
        s_cond = state_cond.get(sname, "1'b0")
        for ext in state.extracts:
            h = ext.header
            valid_map[h] = _or(valid_map[h], s_cond) if h in valid_map else s_cond

    return valid_map


def _p4lit_to_sv(lit):
    """Convert a P4 literal like '16w0x8100' to SV '16\'h8100'."""
    lit = lit.strip()
    m = re.match(r'(\d+)w0[xX]([0-9a-fA-F]+)', lit)
    if m:
        w, h = m.group(1), m.group(2)
        return f"{w}'h{h.upper()}"
    m = re.match(r'(\d+)w(\d+)', lit)
    if m:
        w, d = m.group(1), m.group(2)
        return f"{w}'d{d}"
    # Already SV-style
    return lit


# ── Offset variable name for a header ─────────────────────────────────────────

def _offset_var(inst_name):
    return f'w_{inst_name}_base'


def _has_var_pred_on_non_dynamic(var_pred, inst_map):
    """Return True if the variable predecessor header is NOT dynamic."""
    if var_pred is None:
        return False
    vname, _ = var_pred
    return True  # if listed, it's real


# ── Main emitter ──────────────────────────────────────────────────────────────

def emit_top(ir, app_name, output_path, axi_data_width=DEFAULT_AXI_DATA_W, board=None, nslot=4,
             tm_qlimit=None):
    """Generate {app_name}_top.sv with AXI4-Stream and AXI4-Lite interfaces.

    axi_data_width: AXI4-Stream TDATA width in bits (default 256). Must be a
    power of 2, >=8, and <= MAX_AXI_DATA_W -- see the ceiling's rationale
    above. Re-validated here (not just in main.py's CLI parsing) since
    emit_top() can be called directly/programmatically, not only via the CLI.
    board: None (default) = today's behavior exactly, both ram_style pragma
        sites emit Vivado's hardcoded default, byte-identical to before this
        parameter existed. Otherwise a board descriptor dict (see
        boards.py/load_board) -- makes those pragmas vendor-correct.
        Re-validated here for the same reason as axi_data_width above.
    """
    if board is not None:
        validate_board(board)

    if axi_data_width < 8 or (axi_data_width & (axi_data_width - 1)) != 0:
        raise ValueError(
            f'axi_data_width must be a power of 2, >=8 (got {axi_data_width})'
        )
    # The slot-ring pointers are SLOT_AW+1 bits with a wrap bit, so they count
    # modulo 2**(SLOT_AW+1) while the slot arrays have NSLOT entries. Those two
    # agree only when NSLOT is a power of two; at NSLOT=6 the slot index reaches
    # 6 and 7, which index past the arrays, and the design hangs. Documented as
    # a constraint since the ring landed, but nothing enforced it -- so the
    # failure mode was a silent hang in simulation, not a compiler error.
    if nslot < 1 or (nslot & (nslot - 1)) != 0:
        raise ValueError(
            f'nslot must be a power of 2 (got {nslot}) -- the slot-ring pointers '
            f'carry a wrap bit and count modulo a power of two, so any other '
            f'value indexes past the slot arrays and deadlocks'
        )
    if axi_data_width > MAX_AXI_DATA_W:
        raise ValueError(
            f'axi_data_width={axi_data_width} exceeds MAX_AXI_DATA_W='
            f'{MAX_AXI_DATA_W} -- see the ceiling\'s rationale in this file\'s '
            f'module-level constants section (BRAM byte-lane fan-out grows '
            f'with width, and nothing wider than this has been synthesized '
            f'or measured on this project\'s only validated target)'
        )

    beat_bytes    = axi_data_width // 8
    max_pkt_bytes = MAX_PKT_BEATS * beat_bytes
    hdr_idx_w     = max(1, math.ceil(math.log2(max_pkt_bytes + 1)))

    inst_map = {inst.inst_name: inst for inst in ir.header_instances
                if not inst.is_stack}

    layouts = _compute_layout(ir, inst_map)
    verify_terms = []
    valid_map = _gen_valid_signals(ir, inst_map, layouts, verify_out=verify_terms)

    ctrl = _find_processing_ctrl(ir)
    if ctrl is None:
        with open(output_path, 'w') as f:
            f.write(f'// {app_name}_top.sv — no processing control block\n')
        return

    amap  = {a.name: a for a in ctrl.actions}
    fwmap = _build_fwmap(ir)
    # P4RtlPipeline egress control (docs/egress_stage_plan.md). Same
    # "has real content" test main.py uses to decide whether
    # egress_processing_generated is emitted at all, so the two agree.
    ectrl = ir.pipeline.egress
    if ectrl is not None and not (ectrl.tables or ectrl.statements):
        ectrl = None
    eamap = {a.name: a for a in ectrl.actions} if ectrl else None
    regmap = _build_axil_regmap(ctrl, amap, fwmap, ectrl=ectrl, eamap=eamap)

    # Determine which headers are non-stack and appear in emit list
    emit_list = (ir.pipeline.deparser.emit_list
                 if ir.pipeline.deparser else [])
    emit_insts = [inst_map[h] for h in emit_list if h in inst_map]

    total_hdr_bits  = sum(_hdr_bits_total(inst) for inst in emit_insts)
    total_hdr_bytes = total_hdr_bits // 8

    with open(output_path, 'w') as f:
        _write_module(f, ir, app_name, inst_map, layouts, valid_map,
                      ctrl, amap, fwmap, regmap,
                      emit_insts, total_hdr_bytes,
                      axi_data_width, beat_bytes, max_pkt_bytes, hdr_idx_w,
                      board, verify_terms=verify_terms, nslot=nslot,
                      ectrl=ectrl, tm_qlimit=tm_qlimit)


def _build_fwmap(ir):
    fwmap = {}
    for inst in ir.header_instances:
        if inst.is_stack:
            continue
        for fld in inst.header_type.fields:
            if fld.width:
                fwmap[f'{inst.inst_name}_{fld.name}'] = fld.width
    for mf in ir.metadata_fields:
        fwmap[f'meta_{mf.name}'] = mf.width
    for block in ir.controls.values():
        for lv in block.local_vars:
            if lv.name not in fwmap:
                fwmap[lv.name] = lv.width
    return fwmap


# ── Module body writer ────────────────────────────────────────────────────────

def _write_ram_style_pragma(f, board):
    """board=None (default) = today's exact hardcoded Vivado pragma, byte-
    identical to before this parameter existed. Otherwise uses the board
    descriptor's own ram_style_pragma (or, if falsy, an explanatory comment
    instead of guessing at unverified syntax)."""
    if board is None:
        f.write('  (* ram_style = "block" *)\n')
        return
    pragma = board['ram_style_pragma']
    if pragma:
        f.write(f'  {pragma}\n')
    else:
        f.write(f"  // ram_style: board '{board['name']}' ({board['vendor']}) defines no RAM-style pragma\n")


def _write_module(f, ir, app_name, inst_map, layouts, valid_map,
                  ctrl, amap, fwmap, regmap, emit_insts, total_hdr_bytes,
                  axi_data_width, beat_bytes, max_pkt_bytes, hdr_idx_w,
                  board=None, verify_terms=None, nslot=4, ectrl=None, tm_qlimit=None):

    BEAT_W     = axi_data_width
    KEEP_W     = beat_bytes
    MAX_PKT_BYTES = max_pkt_bytes
    HDR_IDX_W  = hdr_idx_w
    BEAT_CNT_W = max(1, math.ceil(math.log2(MAX_PKT_BEATS + 1)))

    # Header-region sizing: worst-case runtime byte extent of every header
    # this app could ever need to write back, rounded up to a whole beat so
    # the RX/TX per-beat pkt_buf_hdr/pkt_buf_payload routing mux never needs
    # to split a beat across the two arrays. Must be >=1 beat and capped at
    # MAX_PKT_BEATS (defensive; real apps' header regions are far smaller).
    HDR_MAX_BYTES = _worst_case_hdr_bytes(layouts, inst_map)
    HDR_MAX_BYTES = ((HDR_MAX_BYTES + KEEP_W - 1) // KEEP_W) * KEEP_W
    HDR_MAX_BYTES = max(KEEP_W, min(HDR_MAX_BYTES, MAX_PKT_BYTES))
    # Structurally guaranteed while MAX_PKT_BEATS stays >=2 (MAX_PKT_BYTES is
    # MAX_PKT_BEATS*KEEP_W, so it only approaches KEEP_W -- and PAYLOAD_MAX_BYTES
    # only approaches 0 -- if MAX_PKT_BEATS itself were reduced to ~1). Asserted
    # explicitly rather than left implicit, since axi_data_width is now a real
    # user-facing choice (--axi-data-width) and a future edit to MAX_PKT_BEATS
    # could otherwise silently produce a malformed pkt_buf_payload array bound.
    if HDR_MAX_BYTES >= MAX_PKT_BYTES:
        raise ValueError(
            f'{app_name}: header region ({HDR_MAX_BYTES} bytes) leaves no room '
            f'for a payload region within MAX_PKT_BYTES ({MAX_PKT_BYTES} bytes) '
            f'-- increase MAX_PKT_BEATS or reduce axi_data_width'
        )
    HDR_MAX_BEATS = HDR_MAX_BYTES // KEEP_W

    # Whether any counter extern needs the packet's total byte length (only
    # BYTES/PACKETS_AND_BYTES counters do) -- gates whether pkt_byte_len is
    # emitted at all, so apps with no such counter (or no counters) get
    # byte-identical output to before this feature existed.
    # Counters of BOTH controls: storage modules, slot capture and the AXI
    # windows are per counter regardless of which control calls .count().
    ig_counters  = list(ctrl.counters)
    eg_counters  = list(ectrl.counters) if ectrl else []
    all_counters = ig_counters + eg_counters
    needs_byte_len = any(c.counter_type in ('BYTES', 'PACKETS_AND_BYTES')
                          for c in all_counters)

    # Standard-metadata inputs the processing module declares (same scan
    # emit_processing uses, so the two can't disagree about which ports exist).
    # These were previously left completely unconnected: the ports were
    # declared and nothing drove them.
    std_meta_ins = _collect_std_meta_inputs(ctrl)
    # ── Standard metadata across the ingress -> egress boundary ─────────────
    # The slot ring is the queueing point, so it carries the packet's standard
    # metadata between the stages, exactly as a traffic manager would:
    #   ig_std_outs : fields ingress WRITES (out_std_meta_* ports) -- captured
    #                 into the slot at ingress completion and fed to egress
    #   eg_std_outs : fields egress WRITES -- captured at egress completion
    #   eg_shell_std: fields egress READS that ingress does not write -- these
    #                 are shell-sourced (timestamp, parsed_bytes, parser_error),
    #                 sampled into the slot at issue time so egress sees the
    #                 SAME packet's values, not a later packet's live inputs
    # Every pipeline-written field leaves the shell as the sideband
    # out_std_meta_<field>, alongside the user-metadata sideband.
    ig_std_outs  = _collect_std_meta_outputs(ctrl)
    eg_std_ins   = _collect_std_meta_inputs(ectrl) if ectrl else {}
    eg_std_outs  = _collect_std_meta_outputs(ectrl) if ectrl else {}
    eg_shell_std = {k: w for k, w in eg_std_ins.items() if k not in ig_std_outs}
    sideband_std = dict(ig_std_outs); sideband_std.update(eg_std_outs)
    # shell-sourced fields SOME control reads (drives ingress_ts_ctr/byte_len)
    shell_std_used = dict(std_meta_ins); shell_std_used.update(eg_shell_std)
    # parsed_bytes is the packet's byte count, which the shell already knows
    # how to compute for BYTES-type counters -- reuse it rather than counting
    # twice.
    if 'parsed_bytes' in shell_std_used:
        needs_byte_len = True

    # Shell-written standard metadata that has to be sampled per packet at
    # START OF PACKET, not read live at issue: issue is cut-through and can
    # land while RX is already receiving a LATER packet, so a live read would
    # hand the pipeline the wrong packet's value.
    # Written by the traffic manager, not at issue: enq_qdepth is recorded into
    # the slot when the packet is enqueued, deq_qdepth is valid combinationally
    # on the dequeue cycle (which is exactly when egress samples its inputs).
    TM_WRITTEN  = ('enq_qdepth', 'deq_qdepth')
    SOP_SAMPLED = ('ingress_timestamp', 'ingress_port')
    sop_std = {f: w for f, w in shell_std_used.items() if f in SOP_SAMPLED}
    tm_std  = {f: w for f, w in shell_std_used.items() if f in TM_WRITTEN}
    # packet_length is the whole frame, so it is final only at tlast --
    # a program that reads it cannot be issued cut-through (see iss_hdr_ready).
    needs_pkt_len = 'packet_length' in shell_std_used
    if needs_pkt_len:
        needs_byte_len = True
    # Fields egress reads that the shell must record per packet. SOP-sampled
    # ones already have their own slot array (slot_sop_*), so only the
    # issue-time ones (parsed_bytes, parser_error, packet_length) need a
    # second copy taken at issue.
    eg_issue_std = {k: w for k, w in eg_shell_std.items()
                    if k not in sop_std and k not in tm_std}
    eg_tm_std    = {k: w for k, w in eg_shell_std.items() if k in tm_std}
    slot_std = dict(ig_std_outs); slot_std.update(eg_std_outs); slot_std.update(eg_issue_std)

    def _shell_std_src(fname, fw):
        """The shell's source expression for a shell-written std-meta field at
        ISSUE time (what ingress's std_meta_* input is connected to, and what
        the slot records for egress to read later)."""
        if fname in TM_WRITTEN:
            # Ingress runs BEFORE the traffic manager, so the packet has not
            # been queued yet and neither depth exists for it.
            return f"{fw}'d0"
        if fname in sop_std:
            return f'slot_sop_{fname}[iss_slot]'
        if fname == 'parsed_bytes':
            # Bytes consumed by extract(), which is exactly what cutoff_byte
            # is: the byte position at which every header this packet's parse
            # path extracts has landed. NOT slot_byte_len -- that is a running
            # count of bytes RECEIVED, so at a cut-through issue it reports the
            # beats that happen to have arrived, not the parsed header length.
            return f"{fw}'(cutoff_byte)"
        if fname == 'packet_length':
            # Final because issue waits for slot_done when this is read.
            return f"{fw}'({{slot_byte_len[iss_slot]}})"
        if fname == 'parser_error':
            return 'w_parser_error' if verify_terms else f"{fw}'d0"
        return f"{fw}'b0"

    # ── Module header ──────────────────────────────────────────────────────────
    f.write(f'module {app_name}_top #(\n')
    f.write(f'    parameter int AXI_DATA_W  = {BEAT_W},\n')
    f.write(f'    parameter int AXIL_ADDR_W = {AXIL_ADDR_W}\n')
    f.write(') (\n')
    f.write('    input  logic clk,\n')
    f.write('    input  logic rst_n,\n')
    f.write('\n    // AXI4-Stream slave — packet in\n')
    f.write('    input  logic [AXI_DATA_W-1:0]    s_axis_tdata,\n')
    f.write('    input  logic [AXI_DATA_W/8-1:0]  s_axis_tkeep,\n')
    f.write('    input  logic                      s_axis_tvalid,\n')
    f.write('    output logic                      s_axis_tready,\n')
    f.write('    input  logic                      s_axis_tlast,\n')
    f.write('\n    // AXI4-Stream master — packet out\n')
    f.write('    output logic [AXI_DATA_W-1:0]    m_axis_tdata,\n')
    f.write('    output logic [AXI_DATA_W/8-1:0]  m_axis_tkeep,\n')
    f.write('    output logic                      m_axis_tvalid,\n')
    f.write('    input  logic                      m_axis_tready,\n')
    f.write('    output logic                      m_axis_tlast,\n')
    f.write('\n    // AXI4-Lite slave — table control plane\n')
    f.write('    input  logic [AXIL_ADDR_W-1:0]   s_axil_awaddr,\n')
    f.write('    input  logic                      s_axil_awvalid,\n')
    f.write('    output logic                      s_axil_awready,\n')
    f.write('    input  logic [31:0]               s_axil_wdata,\n')
    f.write('    input  logic [3:0]                s_axil_wstrb,\n')
    f.write('    input  logic                      s_axil_wvalid,\n')
    f.write('    output logic                      s_axil_wready,\n')
    f.write('    output logic [1:0]                s_axil_bresp,\n')
    f.write('    output logic                      s_axil_bvalid,\n')
    f.write('    input  logic                      s_axil_bready,\n')
    if 'ingress_port' in shell_std_used:
        ipw = shell_std_used['ingress_port']
        f.write('\n    // Physical port the frame arrived on. Sampled at SOP into the\n')
        f.write('    // packet\'s slot and delivered as standard_metadata.ingress_port.\n')
        f.write('    // One stream in means one port here: an integrator with several\n')
        f.write('    // ports instantiates this core per port (or drives it from tuser).\n')
        f.write(f'    input  logic [{ipw-1}:0]{" " * max(1, 15 - len(str(ipw-1)))}ingress_port,\n')
    f.write('    input  logic [AXIL_ADDR_W-1:0]   s_axil_araddr,\n')
    f.write('    input  logic                      s_axil_arvalid,\n')
    f.write('    output logic                      s_axil_arready,\n')
    f.write('    output logic [31:0]               s_axil_rdata,\n')
    f.write('    output logic [1:0]                s_axil_rresp,\n')
    f.write('    output logic                      s_axil_rvalid,\n')
    f.write('    input  logic                      s_axil_rready')
    # Metadata sideband. User metadata is the only channel an XSA app has for a
    # per-packet decision -- xsa.p4's standard_metadata_t has no egress_spec /
    # egress_port / ingress_port at all -- so it has to leave the shell. Exposed
    # as plain outputs rather than packed into m_axis_tuser: that keeps the
    # shell's AXI4-Stream contract untouched and lets an integrator map the
    # fields to tuser (or anywhere else) themselves.
    sideband = [(f'out_meta_{mf.name}', mf.width) for mf in ir.metadata_fields]
    # Pipeline-written standard metadata (P4RtlPipeline: egress_port,
    # mcast_group, ...) leaves the same way -- it is the shell's port model.
    sideband += [(f'out_std_meta_{fn}', fw) for fn, fw in sorted(sideband_std.items())]
    if sideband:
        f.write(',\n\n    // Metadata sideband (valid while m_axis_tvalid for the packet)\n')
        for i, (pname, pw) in enumerate(sideband):
            comma = ',' if i < len(sideband) - 1 else ''
            f.write(f'    output logic [{pw-1}:0] {pname}{comma}\n')
    else:
        f.write('\n')
    f.write(');\n\n')

    # ── Local parameters ───────────────────────────────────────────────────────
    f.write(f'  localparam int BEAT_BYTES    = AXI_DATA_W / 8;  // {KEEP_W}\n')
    f.write(f'  localparam int MAX_PKT_BEATS = {MAX_PKT_BEATS};\n')
    f.write(f'  localparam int MAX_PKT_BYTES = MAX_PKT_BEATS * BEAT_BYTES;  // {MAX_PKT_BEATS * KEEP_W}\n')
    f.write(f'  localparam int HDR_MAX_BYTES = {HDR_MAX_BYTES};\n')
    f.write(f'  localparam int HDR_MAX_BEATS = {HDR_MAX_BEATS};\n')
    f.write(f'  localparam int PAYLOAD_MAX_BYTES = MAX_PKT_BYTES - HDR_MAX_BYTES;  // {MAX_PKT_BYTES - HDR_MAX_BYTES}\n')
    f.write(f'  localparam int PAYLOAD_MAX_BEATS = PAYLOAD_MAX_BYTES / BEAT_BYTES;  // {(MAX_PKT_BEATS * KEEP_W - HDR_MAX_BYTES) // KEEP_W}\n\n')
    _payload_beats = (MAX_PKT_BEATS * KEEP_W - HDR_MAX_BYTES) // KEEP_W
    PFIFO_AW = max(1, math.ceil(math.log2(max(2, _payload_beats))))
    NSLOT    = nslot
    SLOT_AW  = max(1, math.ceil(math.log2(NSLOT)))
    # ── Traffic-manager queues (TM step 3) ────────────────────────────────
    # One queue per output port the program can actually select, capped so the
    # round-robin scheduler stays a flat priority encoder. The queue index is
    # the low bits of the egress_port ingress wrote; a program with no
    # egress_port has a single queue and behaves exactly as before.
    QCOUNT = TM_QUEUES if 'egress_port' in ig_std_outs else 1
    QSEL_W = max(1, math.ceil(math.log2(QCOUNT)))

    # ── Packet buffer ──────────────────────────────────────────────────────────
    # pkt_buf_hdr is INTENTIONALLY left a plain register array, no ramstyle
    # pragma: the header field-extraction section below reads it combinationally
    # at dozens of independent runtime-computed byte addresses every cycle (one
    # per extracted field) -- a real Quartus synthesis run confirmed this pattern
    # cannot map onto block RAM regardless of how RX/TX/write-back are
    # restructured (Quartus fell back to a fully-unrolled per-index comparator/
    # mux network -- the actual cause of a 2M+ ALUT explosion measured on this
    # design), and at HDR_MAX_BYTES's real size (128 bytes for fiveTuple) a
    # plain register array is trivially cheap anyway. Do NOT re-add a ramstyle
    # pragma here without re-deriving this from scratch -- it was tried and
    # measured to make things catastrophically worse, not better.
    #
    # pkt_buf_payload is the one array here actually large enough to need real
    # BRAM (8064 bytes for fiveTuple at the default width), and its only two
    # accessors -- RX's per-beat write and TX's per-beat read -- are both
    # naturally row-aligned and provably never target the same row on the same
    # cycle (rx_beat_cnt only advances the cycle after RX's own write to its
    # current row commits, and TX's fetch-issue gate is tx_beat_cnt<rx_beat_cnt),
    # so it's organized as a 2D row array with ordinary 1R+1W BRAM semantics --
    # no mirroring needed (contrast emit_selftest.py's tmpl_buf, which has 3
    # genuinely concurrent accessors and does need mirroring).
    # ── Header slot ring + payload FIFO (step 3: N packets in flight) ─────────
    f.write('  // ── Header slot ring ─────────────────────────────────────────────────────\n')
    f.write('  // NSLOT packets can be in flight at once. Each slot holds one packet\'s\n')
    f.write('  // header region (HDR_MAX_BYTES) as received, its per-row keep, its beat\n')
    f.write('  // count / done / overflow, and -- once the pipeline has finished with it --\n')
    f.write('  // the pipeline\'s output PHV, drop decision and metadata. Four pointers\n')
    f.write('  // walk the ring in order and never overtake each other:\n')
    f.write('  //   wr_ptr  : RX fills this slot          (advances on tlast)\n')
    f.write('  //   iss_ptr : next slot to issue to u_proc (advances on issue)\n')
    f.write('  //   cmp_ptr : next slot expecting a result (advances on out_valid)\n')
    f.write('  //   tx_ptr  : TX drains this slot         (advances on last beat / discard)\n')
    f.write('  // Each carries one extra bit so "full" and "empty" are distinguishable.\n')
    f.write('  // Payload beats do not live in slots: they stream through u_pfifo in\n')
    f.write('  // arrival order, and since every stage is in-order, the head of the FIFO\n')
    f.write('  // is always the first payload beat of the slot TX is on.\n')
    f.write(f'  localparam int NSLOT   = {NSLOT};\n')
    f.write(f'  localparam int SLOT_AW = {SLOT_AW};\n')
    f.write('  logic [7:0] slot_hdr [0:NSLOT*HDR_MAX_BYTES-1];\n')
    f.write('  logic [AXI_DATA_W/8-1:0] slot_keep [0:NSLOT*HDR_MAX_BEATS-1];\n')
    f.write(f'  logic [{BEAT_CNT_W-1}:0] slot_beat_cnt [0:NSLOT-1];\n')
    f.write('  logic slot_done     [0:NSLOT-1];\n')
    f.write('  logic slot_overflow [0:NSLOT-1];\n')
    if needs_byte_len:
        f.write('  logic [15:0] slot_byte_len [0:NSLOT-1];\n')
    # Per-packet standard metadata. Declared here, with the rest of the slot
    # ring, because the processing instantiation below reads them -- this file
    # keeps every declaration ahead of its first use (Vivado's xvlog rejects a
    # forward reference that iverilog accepts; see the extraction section).
    for fn, fw in sorted(sop_std.items()):
        f.write(f'  logic [{fw-1}:0] slot_sop_{fn} [0:NSLOT-1];   // sampled at SOP\n')
    if 'enq_qdepth' in tm_std:
        f.write(f'  logic [{tm_std["enq_qdepth"]-1}:0] slot_enq_qdepth [0:NSLOT-1];   // depth at enqueue\n')
    for fn, fw in sorted(slot_std.items()):
        f.write(f'  logic [{fw-1}:0] slot_std_meta_{fn} [0:NSLOT-1];\n')
    f.write('  logic slot_drop     [0:NSLOT-1];\n')
    f.write('  logic slot_txdone   [0:NSLOT-1];   // TX has sent (or discarded) this slot\n')
    f.write('  logic tx_finish;    // driven in the TX section; read here to set slot_txdone\n')
    f.write('  `ifndef SYNTHESIS\n')
    f.write('  // synthesis translate_off\n')
    f.write('  initial begin\n')
    f.write('    for (int i = 0; i < NSLOT*HDR_MAX_BYTES; i++) slot_hdr[i] = 8\'d0;\n')
    f.write('  end\n')
    f.write('  // synthesis translate_on\n')
    f.write('  `endif\n')
    f.write('  logic [SLOT_AW:0] wr_ptr, iss_ptr, rel_ptr;\n')
    if not ectrl:
        f.write('  logic [SLOT_AW:0] cmp_ptr;   // no egress stage: completion is issue order\n')
    f.write('  wire  [SLOT_AW-1:0] wr_slot  = wr_ptr[SLOT_AW-1:0];\n')
    f.write('  wire  [SLOT_AW-1:0] iss_slot = iss_ptr[SLOT_AW-1:0];\n')
    if ectrl:
        f.write('  // ig_ptr: slot whose packet is currently completing INGRESS (advances on\n')
        f.write('  // u_proc.out_valid, when the PHV is handed to u_egress); sits between\n')
        f.write('  // iss_ptr and cmp_ptr. The slot ring is the queueing point between the\n')
        f.write('  // two controls, so the packet\'s standard metadata rides in the slot.\n')
        f.write('  logic [SLOT_AW:0] ig_ptr;\n')
        f.write('  wire  [SLOT_AW-1:0] ig_slot = ig_ptr[SLOT_AW-1:0];\n')
        f.write('  // deq_ptr: the QUEUEING POINT (TM step 2). Ingress writes its result\n')
        f.write('  // into the slot and enqueues it here; egress is fed FROM the slot when\n')
        f.write('  // this pointer selects it, not combinationally from ingress. With one\n')
        f.write('  // in-order queue that is the ring itself, so order is unchanged -- but\n')
        f.write('  // egress now reads stored state, which is what lets a scheduler pick\n')
        f.write('  // the order later, and lets one packet be run through egress more than\n')
        f.write('  // once for multicast replication.\n')
    f.write('  wire  [SLOT_AW-1:0] rel_slot = rel_ptr[SLOT_AW-1:0];\n')
    # ── Queues (TM step 3) ────────────────────────────────────────────────
    # Everything between "ingress finished" and "TX finished" is now carried by
    # FIFOs of SLOT IDS rather than by ring pointers, because the scheduler may
    # serve queues in an order that is not arrival order:
    #   tmq[q]  : slots waiting for egress, one FIFO per output queue
    #   egq     : slots inside the egress pipeline, in dequeue order
    #   txq     : slots that finished egress, waiting for the wire
    # Each holds at most NSLOT entries, since that is how many packets exist.
    f.write('\n  // ── Traffic manager: per-queue slot FIFOs ────────────────────────────────\n')
    if not ectrl:
        f.write('  // (this program has no egress control, so the scheduler degenerates:\n')
        f.write('  //  ingress completion feeds the transmit queue directly)\n')
    if ectrl:
        f.write(f'  localparam int QCOUNT = {QCOUNT};\n')
        f.write(f'  localparam int QSEL_W = {QSEL_W};\n')
        f.write('  logic [SLOT_AW-1:0] tmq_mem [0:QCOUNT*NSLOT-1];\n')
        f.write('  logic [SLOT_AW:0]   tmq_wr  [0:QCOUNT-1];\n')
        f.write('  logic [SLOT_AW:0]   tmq_rd  [0:QCOUNT-1];\n')
        f.write('  logic [QCOUNT-1:0]  tmq_nonempty;\n')
        f.write('  // depth of each queue, in packets -- this is what enq/deq_qdepth report\n')
        f.write('  logic [SLOT_AW:0]   tmq_depth [0:QCOUNT-1];\n')
        f.write('  always_comb\n')
        f.write('    for (int q = 0; q < QCOUNT; q++) begin\n')
        f.write('      tmq_depth[q]    = tmq_wr[q] - tmq_rd[q];\n')
        f.write('      tmq_nonempty[q] = (tmq_wr[q] != tmq_rd[q]);\n')
        f.write('    end\n')
        f.write('  // egress in-flight and transmit queues\n')
        f.write('  logic [SLOT_AW-1:0] egq_mem [0:NSLOT-1];\n')
        f.write('  logic [SLOT_AW:0]   egq_wr, egq_rd;\n')
    f.write('  logic [SLOT_AW-1:0] txq_mem [0:NSLOT-1];\n')
    f.write('  logic [SLOT_AW:0]   txq_wr, txq_rd;\n')
    f.write('  logic [SLOT_AW-1:0] cmp_slot;   // slot leaving the pipeline this cycle\n')
    f.write('  logic [SLOT_AW-1:0] tx_slot;    // slot TX is sending\n')
    if ectrl:
        f.write('  // ── Scheduler: round robin over non-empty queues ────────────────────────\n')
        f.write('  // One dequeue per cycle (u_egress accepts one packet per cycle). The\n')
        f.write('  // rotating priority means a busy queue cannot starve the others; with a\n')
        f.write('  // single queue this degenerates to "take the oldest", as before.\n')
        f.write('  logic [QSEL_W-1:0] rr_ptr;\n')
        f.write('  logic [QSEL_W-1:0] sched_q;\n')
        f.write('  logic              sched_valid;\n')
        # Unrolled at emit time: QCOUNT is a compile-time constant, and a
        # rotated priority encoder written as a loop needs either `automatic`
        # (unsupported by iverilog 11) or a bit-select of an int loop
        # variable (also unsupported). Offsets wrap for free because QCOUNT is
        # a power of two, so rr_ptr + k IS (rr_ptr + k) mod QCOUNT.
        # Lowest priority is emitted first so the highest-priority match, the
        # last assignment, wins.
        f.write('  always_comb begin\n')
        f.write('    sched_valid = 1\'b0;\n')
        f.write('    sched_q     = \'0;\n')
        for k in range(QCOUNT - 1, -1, -1):
            idx = 'rr_ptr' if k == 0 else f"(rr_ptr + {QSEL_W}'d{k})"
            f.write(f'    if (tmq_nonempty[{idx}]) begin\n')
            f.write(f'      sched_valid = 1\'b1;\n')
            f.write(f'      sched_q     = {idx};\n')
            f.write(f'    end\n')
        f.write('  end\n')
        # tmq_mem / tmq_rd are UNPACKED arrays, and iverilog 11 will not read an
        # unpacked-array element from a continuous assign -- the same rule the
        # header-extraction section follows. These have to be always_comb.
        f.write('  logic [SLOT_AW-1:0] deq_slot;\n')
        f.write('  logic [SLOT_AW:0]   deq_qdepth_now;\n')
        if 'enq_qdepth' in tm_std:
            f.write(f'  logic [{tm_std["enq_qdepth"]-1}:0] enq_qdepth_of_deq;\n')
        f.write('  always_comb begin\n')
        f.write('    deq_slot       = tmq_mem[sched_q*NSLOT + tmq_rd[sched_q][SLOT_AW-1:0]];\n')
        f.write('    deq_qdepth_now = tmq_depth[sched_q];\n')
        if 'enq_qdepth' in tm_std:
            f.write('    enq_qdepth_of_deq = slot_enq_qdepth[deq_slot];\n')
        f.write('  end\n')
        f.write('  // A queue only means something if packets WAIT in it. Dequeue is\n')
        f.write('  // therefore gated on how many packets are already past the scheduler\n')
        f.write('  // (in the egress pipeline or waiting for the wire): while TX is busy\n')
        f.write('  // sending one packet, the rest accumulate in their queues and the\n')
        f.write('  // scheduler gets a real choice. Ungated, everything would drain\n')
        f.write('  // straight through in arrival order and the scheduler would never\n')
        f.write('  // see two non-empty queues at once.\n')
        f.write(f'  localparam int TM_INFLIGHT = {TM_INFLIGHT};\n')
        f.write('  wire [SLOT_AW+1:0] tm_inflight = (egq_wr - egq_rd) + (txq_wr - txq_rd);\n')
        f.write('  wire               deq_fire = sched_valid && (tm_inflight < TM_INFLIGHT);\n')
    f.write('  always_comb begin\n')
    if ectrl:
        f.write('    // Bypass: an egress control with NO pipeline boundary (no table, no\n')
        f.write('    // split) has out_valid = valid_in, so a slot is pushed to this FIFO\n')
        f.write('    // and popped from it on the SAME edge. The pop would then read an\n')
        f.write('    // entry that has not landed yet -- X, which propagates into tx_slot\n')
        f.write('    // and wedges TX. When the FIFO is empty the packet completing egress\n')
        f.write('    // can only be the one being dequeued this cycle.\n')
        f.write('    cmp_slot = (egq_wr == egq_rd) ? deq_slot : egq_mem[egq_rd[SLOT_AW-1:0]];\n')
    else:
        f.write('    cmp_slot = cmp_ptr[SLOT_AW-1:0];\n')
    f.write('    tx_slot  = txq_mem[txq_rd[SLOT_AW-1:0]];\n')
    f.write('  end\n')

    f.write('  // rel_ptr: RELEASE pointer, trails tx_ptr. TX moving on (tx_ptr) and the\n')
    f.write('  // slot being reusable are different events: on an OVERSIZE packet the\n')
    f.write('  // FIFO entry marked last is pushed at MAX_PKT_BEATS while the link\'s real\n')
    f.write('  // tlast arrives later, so TX can finish while RX is still receiving into\n')
    f.write('  // the slot. Releasing then wiped the slot under RX and the remaining\n')
    f.write('  // beats were re-read as a new packet\'s header rows (deadlocked T8).\n')
    f.write('  // A slot is released only once its tlast has been seen.\n')
    f.write('  wire  [SLOT_AW:0] n_alloc  = wr_ptr - rel_ptr;\n')
    f.write('  wire  rx_slot_free = (n_alloc < NSLOT);\n\n')

    # x_hdr: the header bytes of the slot being ISSUED (feeds field extraction)
    f.write('  // Header bytes of the slot being issued to the pipeline -- every w_* field\n')
    f.write('  // below is extracted from this. (Procedural mux, not continuous assigns\n')
    f.write('  // from array elements -- see the note at the extraction block.)\n')
    f.write('  logic [7:0] x_hdr [0:HDR_MAX_BYTES-1];\n')
    f.write('  always_comb for (int i = 0; i < HDR_MAX_BYTES; i++) x_hdr[i] = slot_hdr[iss_slot*HDR_MAX_BYTES + i];\n\n')

    # ── payload storage: one FWFT FIFO PER SLOT (TM step 1) ───────────────
    # Payload bytes used to stream through ONE shared FIFO in arrival order,
    # which made the transmit order the arrival order by construction -- a
    # scheduler that serves one queue before another cannot express itself in
    # that structure. Giving each slot its own FIFO makes payload storage
    # addressable by slot, which is what lets a later step transmit slots in
    # an order the scheduler picks (docs/traffic_manager_plan.md).
    #
    # Each FIFO is sized to hold a WHOLE maximum-length packet
    # (PFIFO_DEPTH >= PAYLOAD_MAX_BEATS, and RX stops accepting payload beats
    # at MAX_PKT_BEATS), so a packet can never be blocked by its own FIFO --
    # and no longer by another packet's payload either. Input backpressure is
    # now purely slot availability. The cost is NSLOT x the payload memory.
    #
    # pkt_beat_fifo is reused unchanged: it already provides the first-word
    # fall-through behaviour the TX path is written against, and it has its
    # own unit test, so this step does not re-derive any of that.
    f.write(f'  localparam int PFIFO_W  = AXI_DATA_W + AXI_DATA_W/8 + 1;  // {{last, keep, data}}\n')
    f.write(f'  localparam int PFIFO_AW = {PFIFO_AW};\n')
    f.write(f'  localparam int PFIFO_DEPTH = 1 << PFIFO_AW;  // {1 << PFIFO_AW} >= PAYLOAD_MAX_BEATS\n')
    f.write('  logic [NSLOT-1:0]    pfifo_wr_en_v;\n')
    f.write('  logic [PFIFO_W-1:0]  pfifo_wr_data;   // shared: only slot wr_slot is written\n')
    f.write('  logic [NSLOT-1:0]    pfifo_full_v;\n')
    f.write('  logic [NSLOT-1:0]    pfifo_rd_valid_v;\n')
    f.write('  logic [PFIFO_W-1:0]  pfifo_rd_data_v [0:NSLOT-1];\n')
    f.write('  logic [NSLOT-1:0]    pfifo_rd_en_v;\n')
    f.write('  genvar gs;\n')
    f.write('  generate for (gs = 0; gs < NSLOT; gs++) begin : g_pfifo\n')
    f.write('    pkt_beat_fifo #(.W(PFIFO_W), .DEPTH(PFIFO_DEPTH), .AW(PFIFO_AW)) u_pfifo (\n')
    f.write('      .clk(clk), .rst_n(rst_n),\n')
    f.write('      .wr_en(pfifo_wr_en_v[gs]), .wr_data(pfifo_wr_data), .full(pfifo_full_v[gs]),\n')
    f.write('      .rd_valid(pfifo_rd_valid_v[gs]), .rd_data(pfifo_rd_data_v[gs]),\n')
    f.write('      .rd_en(pfifo_rd_en_v[gs]),\n')
    f.write('      .occupancy()\n')
    f.write('    );\n')
    f.write('  end endgenerate\n')
    f.write('  // Views of the slot each side is working on. Unpacked-array elements are\n')
    f.write('  // read in always_comb, never a continuous assign (iverilog 11 rejects the\n')
    f.write('  // latter -- the same rule the header extraction section follows).\n')
    f.write('  logic                pfifo_full;\n')
    f.write('  logic                pfifo_rd_valid;\n')
    f.write('  logic [PFIFO_W-1:0]  pfifo_rd_data;\n')
    f.write('  logic                pfifo_rd_en;\n')
    f.write('  logic                pfifo_wr_en;\n')
    f.write('  always_comb begin\n')
    f.write('    pfifo_full     = pfifo_full_v[wr_slot];\n')
    f.write('    pfifo_rd_valid = pfifo_rd_valid_v[tx_slot];\n')
    f.write('    pfifo_rd_data  = pfifo_rd_data_v[tx_slot];\n')
    f.write('    for (int sl = 0; sl < NSLOT; sl++) begin\n')
    f.write('      pfifo_wr_en_v[sl] = pfifo_wr_en && (wr_slot == sl[SLOT_AW-1:0]);\n')
    f.write('      pfifo_rd_en_v[sl] = pfifo_rd_en && (tx_slot == sl[SLOT_AW-1:0]);\n')
    f.write('    end\n')
    f.write('  end\n')
    f.write('  wire                  pfifo_head_last = pfifo_rd_data[PFIFO_W-1];\n')
    f.write('  wire [AXI_DATA_W/8-1:0] pfifo_head_keep = pfifo_rd_data[AXI_DATA_W +: AXI_DATA_W/8];\n')
    f.write('  wire [AXI_DATA_W-1:0]   pfifo_head_data = pfifo_rd_data[AXI_DATA_W-1:0];\n\n')

    # ── State registers ────────────────────────────────────────────────────────
    f.write('  // ── State registers ──────────────────────────────────────────────────────\n')
    f.write('  //   iss_fire     : one-cycle valid_in pulse to u_proc for slot iss_slot\n')
    f.write('  //   proc_out_valid: u_proc\'s data-ALIGNED valid (out_valid port) -- the\n')
    f.write('  //                  cycle out_*/drop belong to slot cmp_slot\n')
    f.write('  //   tx_hdr_row/tx_in_payload: TX progress through slot tx_slot\n')
    if 'ingress_timestamp' in shell_std_used:
        tsw = shell_std_used['ingress_timestamp']
        f.write(f'  logic [{tsw-1}:0] ingress_ts_ctr;   // free-running, bit<{tsw}> per the architecture\n')
    f.write(f'  logic [{BEAT_CNT_W-1}:0] tx_hdr_row;\n')
    f.write('  logic tx_in_payload;\n')
    f.write('  logic tx_out_valid;\n')
    f.write(f'  logic [{KEEP_W*8-1}:0] tx_out_data;\n')
    f.write(f'  logic [{KEEP_W-1}:0] tx_out_keep;\n')
    f.write('  logic tx_out_last;\n\n')

    # ── Header field wires (extracted from pkt_buf) ────────────────────────────
    f.write('  // ── Header field extraction from pkt_buf ────────────────────────────────\n')
    f.write('  //    Fields extracted using big-endian (network byte order) bit mapping.\n\n')

    # Offset-var and field-extraction wires are interleaved per-header, in
    # layouts' topological (parse) order, rather than emitted as two flat
    # blocks -- because of a real cross-toolchain finding: Vivado's xvlog
    # (unlike iverilog) rejects a `wire X = expr_referencing_Y;` when Y's own
    # declaration appears later in the file, even though this is ordinary,
    # valid Verilog (module-level net/continuous-assign order has no
    # synthesis/simulation meaning) -- iverilog tolerates the forward
    # reference, xvlog does not. The dependency runs BOTH directions: an
    # offset-var can need an earlier header's plain field (e.g. an eth_type
    # check gating a variable-base header), and it can ALSO need an earlier
    # variable-base header's OWN field (e.g. an ipv4-options header's offset
    # depending on ipv4's hdr_len field, where ipv4 itself has a variable
    # base if an optional VLAN tag precedes it) -- so a simple two-bucket
    # split (fixed-base fields, then all offset-vars, then variable-base
    # fields) isn't sufficient; only true per-header interleaving in parse
    # order is, since `layouts` is already in that order and a header's
    # offset/var_pred predecessor is always an earlier entry in it.
    emitted_offset_vars = set()
    for layout in layouts:
        _emit_offset_var_for(f, layout, layouts, valid_map, HDR_IDX_W, emitted_offset_vars)

        inst_name = layout['inst_name']
        inst      = inst_map.get(inst_name)
        if not inst:
            continue
        base_expr = _choose_base_expr(inst_name, layout['mandatory_base'],
                                       layout['optional_preds'], layout['var_pred'])
        f.write(f'  // {inst_name} — base: {base_expr}\n')
        # Declared as `logic` and read inside always_comb, NOT as
        # `wire x = pkt_buf_hdr[...]`. A continuous assign that reads an
        # element of this array was observed to never evaluate at all in
        # Icarus Verilog 11 -- stuck at its initial X from time zero while the
        # array element itself read correctly -- for some fields and not
        # others (w_ipv4_ttl dead, w_ipv4_protocol beside it fine), with no
        # difference in how they were written. Found by the first top-level
        # test of an app that rewrites headers (tb_load_balance_xsa_top); the
        # same failure class had already hit the LPM table's assign-copies
        # and its reduction tree (emit_table.py). Procedural reads have been
        # robust in every instance. Synthesis is identical either way.
        bit_off = 0
        fields_here = []
        for fld in inst.header_type.fields:
            w = fld.width or 0
            if w == 0:
                continue
            f.write(f'  logic [{w-1}:0] w_{inst_name}_{fld.name};\n')
            fields_here.append((fld.name, _extract_expr(base_expr, bit_off, w, target='x_hdr')))
            bit_off += w
        if fields_here:
            f.write('  always_comb begin\n')
            for fname, expr in fields_here:
                f.write(f'    w_{inst_name}_{fname} = {expr};\n')
            f.write('  end\n')
        f.write('\n')

    # ── Header validity wires ──────────────────────────────────────────────────
    f.write('  // ── Header validity (derived from extracted fields) ──────────────────────\n')
    layout_names     = [l['inst_name'] for l in layouts]
    layout_name_set  = set(layout_names)
    # Action-only headers: exist in the IR but never extracted by the parser
    # (e.g. new_vlan inserted by an action).  Their input fields are tied to '0.
    action_only_names = [inst.inst_name for inst in ir.header_instances
                         if not inst.is_stack
                         and inst.inst_name not in layout_name_set]
    all_hdr_names = layout_names + action_only_names

    for hname in all_hdr_names:
        vexpr = valid_map.get(hname, "1'b0")
        f.write(f'  wire w_{hname}_valid = {vexpr};\n')
    f.write('\n')

    # ── Parser error (verify() lowered into the parallel extractor) ─────────
    # Priority chain over every verify on the packet's ACTUAL path: the first
    # one that is both reached and failing reports its code, else NoError.
    # This is what the FSM in parser_generated would have latched in its
    # REJECT state -- but that FSM is not in this datapath, so it is
    # recomputed here from the same terms.
    if verify_terms:
        err_w = max(1, getattr(ir, 'error_width', 0) or 1)
        no_err = getattr(ir, 'error_values', {}).get('NoError', 0)
        f.write('  // ── standard_metadata.parser_error (from parser verify()) ────────────────\n')
        expr = f"{err_w}'d{no_err}"
        for reach, cond_w, errv in reversed(verify_terms):
            expr = f"(({reach}) && !({cond_w})) ? {errv} : {expr}"
        f.write(f'  wire [{err_w-1}:0] w_parser_error = {expr};\n\n')

    # ── Header-region cutoff (drives when match-action processing triggers) ────
    # Placed after validity wires since its per-header terms reference the
    # same field/offset wires validity did (forward-reference-safe either
    # way in SV, kept in dependency order for readability).
    f.write('  // ── Header-region cutoff ──────────────────────────────────────────────────\n')
    _emit_cutoff_expr(f, layouts, inst_map, valid_map, HDR_IDX_W)

    # Emit field extraction wires for action-only headers (all zero — not in packet)
    if action_only_names:
        f.write('  // Action-only headers (not in received packet; inputs tied to 0)\n')
        for hname in action_only_names:
            inst = inst_map.get(hname)
            if not inst:
                continue
            for fld in inst.header_type.fields:
                if fld.width:
                    f.write(f"  wire [{fld.width-1}:0] w_{hname}_{fld.name} = '0;\n")
        f.write('\n')

    # ── Processing module instantiation ───────────────────────────────────────
    f.write('  // ── processing_generated ─────────────────────────────────────────────────\n')
    f.write('  //    Signals prefixed proc_out_* are the match-action outputs.\n\n')

    # Declare proc_out wires
    for hname in all_hdr_names:
        inst = inst_map.get(hname)
        if not inst:
            continue
        f.write(f'  wire out_{hname}_valid;\n')
        for fld in inst.header_type.fields:
            if fld.width:
                f.write(f'  wire [{fld.width-1}:0] out_{hname}_{fld.name};\n')
    f.write('  wire proc_valid_out;\n')
    f.write('  wire proc_out_valid;\n')
    f.write('  wire proc_drop;\n')
    f.write('  logic iss_fire;\n')
    for mf in ir.metadata_fields:
        f.write(f'  wire [{mf.width-1}:0] proc_out_meta_{mf.name};\n')
    for fn, fw in sorted(ig_std_outs.items()):
        f.write(f'  wire [{fw-1}:0] ig_out_std_meta_{fn};\n')
    if ectrl:
        f.write('  // egress_processing_generated outputs (the FINAL PHV the shell captures)\n')
        for hname in all_hdr_names:
            inst = inst_map.get(hname)
            if not inst:
                continue
            f.write(f'  wire eg_out_{hname}_valid;\n')
            for fld in inst.header_type.fields:
                if fld.width:
                    f.write(f'  wire [{fld.width-1}:0] eg_out_{hname}_{fld.name};\n')
        f.write('  wire eg_valid_out;\n')
        f.write('  wire eg_out_valid;\n')
        f.write('  wire eg_drop;\n')
        for mf in ir.metadata_fields:
            f.write(f'  wire [{mf.width-1}:0] eg_out_meta_{mf.name};\n')
        for fn, fw in sorted(eg_std_outs.items()):
            f.write(f'  wire [{fw-1}:0] eg_out_std_meta_{fn};\n')
    f.write('\n')
    # Names of the signals the shell captures at pipeline completion: the
    # egress module's when there is one, else ingress's.
    fin_valid = 'eg_out_valid' if ectrl else 'proc_out_valid'
    fin_drop  = 'eg_drop' if ectrl else 'proc_drop'
    fin_hdr   = 'eg_out_' if ectrl else 'out_'
    fin_meta  = 'eg_out_meta_' if ectrl else 'proc_out_meta_'

    # Plain (no-initializer) query-result wires declared here, BEFORE the
    # AXI4-Lite decoder -- the decoder's own read-side logic (query_status/
    # query_action_id/query_p_* word reads) and pending_commit_busy mux
    # reference these by name (e.g. `pending_commit_busy = FiveTuple_cp_query_busy;`),
    # and Vivado's xvlog (unlike iverilog) rejects referencing a signal
    # before its own declaration. A bare `wire X;` has no initializer to
    # depend on anything itself, so hoisting just these (not the r_*-register
    # ALIAS wires below, which must stay AFTER the decoder since they
    # reference ITS registers) resolves this direction of the same
    # cross-toolchain forward-reference class fixed above for header fields.
    for ti in regmap:
        if not ti['supports_query']:
            continue
        tname = ti['tname']
        if ti.get('is_counter'):
            # Counter query results come from the separate {tname}_counter
            # module (see emit_counters.py), not from processing_generated --
            # no _hit/_action_id/params concept, just busy + the value(s).
            f.write(f'  wire {tname}_cp_query_busy;\n')
            if ti.get('has_pkt'):
                f.write(f'  wire [63:0] {tname}_cp_query_pkt_value;\n')
            if ti.get('has_byte'):
                f.write(f'  wire [63:0] {tname}_cp_query_byte_value;\n')
            continue
        f.write(f'  wire {tname}_cp_query_busy;\n')
        f.write(f'  wire {tname}_cp_query_hit;\n')
        f.write(f'  wire [{ti["act_w"]-1}:0] {tname}_cp_query_action_id;\n')
        for pname, pw in ti['params']:
            f.write(f'  wire [{pw-1}:0] {tname}_cp_query_p_{pname};\n')
    f.write('\n')

    _emit_axil_decoder(f, regmap)

    # Declare cp_wr staging regs wires (for processing instantiation) -- these
    # ALIAS the decoder's own r_{tname}_cp_wr_*/r_{tname}_cp_query_*
    # registers (e.g. `wire [W-1:0] {cp_sig} = r_{cp_sig};`), so must stay
    # AFTER _emit_axil_decoder, which is what actually declares those registers.
    for ti in regmap:
        tname = ti['tname']
        for rname, cp_sig, width in ti['regs']:
            if rname == 'commit':
                f.write(f'  wire {tname}_cp_wr_en = r_{tname}_cp_wr_en;\n')
            elif rname in ('query_commit', 'delete_commit'):
                continue  # cp_query_en/del declared once, explicitly, below
            else:
                f.write(f'  wire [{width-1}:0] {cp_sig} = r_{cp_sig};\n')
        if ti['supports_query']:
            f.write(f'  wire {tname}_cp_query_en  = r_{tname}_cp_query_en;\n')
            if not ti.get('is_counter'):
                f.write(f'  wire {tname}_cp_query_del = r_{tname}_cp_query_del;\n')
        if not ti.get('is_counter'):
            f.write(f'  wire {tname}_hit_out;\n')

    # Counter increment-request wires -- these connect u_proc's new
    # {cname}_incr_en/_incr_idx output ports straight through to the
    # separate {cname}_counter module instantiated below (after
    # pkt_ready_to_clear, which that module also needs).
    for cnt in all_counters:
        idx_w = max(1, math.ceil(math.log2(cnt.size))) if cnt.size > 1 else 1
        f.write(f'  wire {cnt.name}_incr_en;\n')
        f.write(f'  wire [{idx_w-1}:0] {cnt.name}_incr_idx;\n')

    f.write('\n')
    if 'ingress_timestamp' in shell_std_used:
        tsw = shell_std_used['ingress_timestamp']
        f.write('  // ── ingress_timestamp source ───────────────────────────────────────────\n')
        f.write('  always_ff @(posedge clk) begin\n')
        f.write('    if (!rst_n) ingress_ts_ctr <= \'0;\n')
        f.write('    else        ingress_ts_ctr <= ingress_ts_ctr + 1\'b1;\n')
        f.write('  end\n\n')

    f.write('  processing_generated u_proc (\n')
    f.write('    .clk       (clk),\n')
    f.write('    .rst_n     (rst_n),\n')
    f.write('    .valid_in  (iss_fire),\n')
    # valid flags
    for hname in all_hdr_names:
        f.write(f'    .{hname}_valid     (w_{hname}_valid),\n')
    # field inputs
    for hname in all_hdr_names:
        inst = inst_map.get(hname)
        if not inst:
            continue
        for fld in inst.header_type.fields:
            if fld.width:
                f.write(f'    .{hname}_{fld.name}  (w_{hname}_{fld.name}),\n')
    # Metadata inputs. P4 user metadata is zero-initialized -- the parser
    # never writes it on this path (parser_generated has no metadata ports at
    # all), and xsa.p4 defines no architectural producer for it, so there is
    # nothing else that could legitimately drive these.
    for mf in ir.metadata_fields:
        f.write(f'    .meta_{mf.name}  ({mf.width}\'b0),\n')
    # Standard-metadata inputs. Each field the ARCHITECTURE defines gets a real
    # source here where the shell can actually produce one; anything it cannot
    # is tied off explicitly and said so, rather than left floating.
    for fname in sorted(std_meta_ins):
        fw = std_meta_ins[fname]
        src = _shell_std_src(fname, fw)
        note = ''
        if fname == 'parser_error' and not verify_terms:
            # No verify() in this program, so there is nothing that could
            # ever set it: NoError by construction.
            note = '  // NoError -- program has no verify()'
        elif fname in TM_WRITTEN:
            note = '  // 0 in ingress: the packet is not queued yet'
        elif fname in sop_std:
            note = '  // sampled at SOP'
        elif fname == 'packet_length':
            note = '  // final: issue waits for tlast'
        elif fname == 'parsed_bytes':
            note = '  // bytes consumed by extract()'
        elif fname != 'parser_error':
            note = '  // no shell source for this field'
        f.write(f'    .std_meta_{fname}  ({src}),{note}\n')
    # valid flag outputs
    for hname in all_hdr_names:
        f.write(f'    .out_{hname}_valid     (out_{hname}_valid),\n')
    # field outputs
    for hname in all_hdr_names:
        inst = inst_map.get(hname)
        if not inst:
            continue
        for fld in inst.header_type.fields:
            if fld.width:
                f.write(f'    .out_{hname}_{fld.name}  (out_{hname}_{fld.name}),\n')
    for mf in ir.metadata_fields:
        f.write(f'    .out_meta_{mf.name}  (proc_out_meta_{mf.name}),\n')
    for fn in sorted(ig_std_outs):
        f.write(f'    .out_std_meta_{fn}  (ig_out_std_meta_{fn}),\n')
    # cp_wr ports (tables only -- counters have no cp_wr/cp_query/hit_out
    # ports on processing_generated; see the incr_en/incr_idx loop below)
    for ti in regmap:
        if ti.get('is_counter') or ti['stage'] != 'ingress':
            continue
        tname = ti['tname']
        f.write(f'    .{tname}_cp_wr_en  ({tname}_cp_wr_en),\n')
        for rname, cp_sig, width in ti['regs']:
            if rname not in ('commit', 'query_commit', 'delete_commit'):
                f.write(f'    .{cp_sig} ({cp_sig}),\n')
        if ti['supports_query']:
            f.write(f'    .{tname}_cp_query_en  ({tname}_cp_query_en),\n')
            f.write(f'    .{tname}_cp_query_del ({tname}_cp_query_del),\n')
            f.write(f'    .{tname}_cp_query_busy ({tname}_cp_query_busy),\n')
            f.write(f'    .{tname}_cp_query_hit  ({tname}_cp_query_hit),\n')
            f.write(f'    .{tname}_cp_query_action_id ({tname}_cp_query_action_id),\n')
            for pname, pw in ti['params']:
                f.write(f'    .{tname}_cp_query_p_{pname} ({tname}_cp_query_p_{pname}),\n')
        f.write(f'    .{tname}_hit_out  ({tname}_hit_out),\n')
    # Counter increment-request ports
    for cnt in ig_counters:
        f.write(f'    .{cnt.name}_incr_en  ({cnt.name}_incr_en),\n')
        f.write(f'    .{cnt.name}_incr_idx ({cnt.name}_incr_idx),\n')
    f.write('    .out_valid (proc_out_valid),   // aligned with out_*/drop\n')
    f.write('    .valid_out (proc_valid_out),   // legacy registered-late valid, unused here\n')
    f.write('    .drop      (proc_drop)\n')
    f.write('  );\n\n')

    # ── Egress processing module (P4RtlPipeline): PHV pass-through ──────────
    if ectrl:
        f.write('  // ── egress_processing_generated: PHV pass-through, fed at DEQUEUE ────────\n')
        f.write('  // Every input comes from the packet\'s SLOT, written when ingress\n')
        f.write('  // finished: the header vector, user metadata and standard metadata\n')
        f.write('  // exactly as ingress left them -- the packet is never re-parsed.\n')
        f.write('  // drop is sticky: ingress\'s decision enters as drop_in and egress can\n')
        f.write('  // only add to it (its counters are gated on drop_in inside the module).\n')
        f.write('  // Reading from the slot rather than from u_proc\'s outputs is what makes\n')
        f.write('  // the queueing point real -- see deq_ptr above.\n')
        f.write('  egress_processing_generated u_egress (\n')
        f.write('    .clk       (clk),\n')
        f.write('    .rst_n     (rst_n),\n')
        f.write('    .valid_in  (deq_fire),\n')
        f.write('    .drop_in   (slot_drop[deq_slot]),\n')
        for hname in all_hdr_names:
            if inst_map.get(hname):
                f.write(f'    .{hname}_valid     (slot_phv_{hname}_valid[deq_slot]),\n')
            else:
                f.write(f'    .{hname}_valid     (1\'b0),\n')
        for hname in all_hdr_names:
            inst = inst_map.get(hname)
            if not inst:
                continue
            for fld in inst.header_type.fields:
                if fld.width:
                    f.write(f'    .{hname}_{fld.name}  (slot_phv_{hname}_{fld.name}[deq_slot]),\n')
        for mf in ir.metadata_fields:
            f.write(f'    .meta_{mf.name}  (slot_meta_{mf.name}[deq_slot]),\n')
        for fname in sorted(eg_std_ins):
            if fname == 'enq_qdepth':
                f.write(f'    .std_meta_{fname}  (enq_qdepth_of_deq),   // TM: depth when enqueued\n')
            elif fname == 'deq_qdepth':
                f.write(f'    .std_meta_{fname}  ({eg_std_ins[fname]}\'(deq_qdepth_now)),   // TM: depth right now\n')
            elif fname in sop_std:
                f.write(f'    .std_meta_{fname}  (slot_sop_{fname}[deq_slot]),   // shell-sourced, sampled at SOP\n')
            else:
                f.write(f'    .std_meta_{fname}  (slot_std_meta_{fname}[deq_slot]),   // from the slot\n')
        for hname in all_hdr_names:
            f.write(f'    .out_{hname}_valid     (eg_out_{hname}_valid),\n')
        for hname in all_hdr_names:
            inst = inst_map.get(hname)
            if not inst:
                continue
            for fld in inst.header_type.fields:
                if fld.width:
                    f.write(f'    .out_{hname}_{fld.name}  (eg_out_{hname}_{fld.name}),\n')
        for mf in ir.metadata_fields:
            f.write(f'    .out_meta_{mf.name}  (eg_out_meta_{mf.name}),\n')
        for fn in sorted(eg_std_outs):
            f.write(f'    .out_std_meta_{fn}  (eg_out_std_meta_{fn}),\n')
        for ti in regmap:
            if ti.get('is_counter') or ti['stage'] != 'egress':
                continue
            tname = ti['tname']
            f.write(f'    .{tname}_cp_wr_en  ({tname}_cp_wr_en),\n')
            for rname, cp_sig, width in ti['regs']:
                if rname not in ('commit', 'query_commit', 'delete_commit'):
                    f.write(f'    .{cp_sig} ({cp_sig}),\n')
            if ti['supports_query']:
                f.write(f'    .{tname}_cp_query_en  ({tname}_cp_query_en),\n')
                f.write(f'    .{tname}_cp_query_del ({tname}_cp_query_del),\n')
                f.write(f'    .{tname}_cp_query_busy ({tname}_cp_query_busy),\n')
                f.write(f'    .{tname}_cp_query_hit  ({tname}_cp_query_hit),\n')
                f.write(f'    .{tname}_cp_query_action_id ({tname}_cp_query_action_id),\n')
                for pname, pw in ti['params']:
                    f.write(f'    .{tname}_cp_query_p_{pname} ({tname}_cp_query_p_{pname}),\n')
            f.write(f'    .{tname}_hit_out  ({tname}_hit_out),\n')
        for cnt in eg_counters:
            f.write(f'    .{cnt.name}_incr_en  ({cnt.name}_incr_en),\n')
            f.write(f'    .{cnt.name}_incr_idx ({cnt.name}_incr_idx),\n')
        f.write('    .out_valid (eg_out_valid),   // aligned with out_*/drop\n')
        f.write('    .valid_out (eg_valid_out),\n')
        f.write('    .drop      (eg_drop)\n')
        f.write('  );\n\n')

    # ═════════════════════════════════════════════════════════════════════════
    # Streaming datapath (step 3): RX -> slot ring -> issue -> u_proc ->
    # capture -> TX, with NSLOT packets in flight and every stage in order.
    # ═════════════════════════════════════════════════════════════════════════
    hdr_fields = []   # (inst_name, fld_name, width) for every non-stack header
    for hname in all_hdr_names:
        inst = inst_map.get(hname)
        if not inst:
            continue
        for fld in inst.header_type.fields:
            if fld.width:
                hdr_fields.append((hname, fld.name, fld.width))

    # ── Per-slot result storage (written at out_valid, read by TX) ────────────
    f.write('  // ── Per-slot pipeline results ────────────────────────────────────────────\n')
    f.write('  // Captured on u_proc.out_valid (the data-ALIGNED valid) into slot cmp_slot.\n')
    f.write('  // The output PHV is stored, not an overlaid byte image, because at\n')
    f.write('  // completion the slot\'s later header rows may not have arrived yet\n')
    f.write('  // (cut-through): the overlay is done at TX time, when TX waits for them.\n')
    for hname in all_hdr_names:
        if inst_map.get(hname):
            f.write(f'  logic slot_phv_{hname}_valid [0:NSLOT-1];\n')
    for hname, fname, w in hdr_fields:
        f.write(f'  logic [{w-1}:0] slot_phv_{hname}_{fname} [0:NSLOT-1];\n')
    for mf in ir.metadata_fields:
        f.write(f'  logic [{mf.width-1}:0] slot_meta_{mf.name} [0:NSLOT-1];\n')
    for cnt in all_counters:
        f.write(f'  logic slot_cnt_{cnt.name}_en [0:NSLOT-1];\n')
        f.write(f'  logic [{_counter_idx_w(cnt)-1}:0] slot_cnt_{cnt.name}_idx [0:NSLOT-1];\n')
    f.write('\n')

    # ── RX ────────────────────────────────────────────────────────────────────
    f.write('  // ── RX (ingest) ──────────────────────────────────────────────────────────\n')
    f.write('  // Accept whenever the next slot is free and the payload FIFO has room.\n')
    f.write('  // Never because the pipeline or TX is busy -- that is the whole point.\n')
    f.write('  assign s_axis_tready = rx_slot_free && !pfifo_full;\n')
    f.write('  wire accept_beat = s_axis_tvalid && s_axis_tready;\n')
    f.write(f'  wire [{BEAT_CNT_W-1}:0] rx_beat_cnt = slot_beat_cnt[wr_slot];\n')
    f.write('  wire accept_payload_beat = accept_beat && (rx_beat_cnt >= HDR_MAX_BEATS) && (rx_beat_cnt < MAX_PKT_BEATS);\n')
    f.write('  assign pfifo_wr_en   = accept_payload_beat;\n')
    f.write('  assign pfifo_wr_data = { (s_axis_tlast || (rx_beat_cnt == MAX_PKT_BEATS - 1)),\n')
    f.write('                            s_axis_tkeep, s_axis_tdata };\n\n')

    f.write('  logic rx_active;   // a packet is being received into wr_slot\n')
    f.write('  always_ff @(posedge clk) begin\n')
    f.write('    if (!rst_n) begin\n')
    f.write('      wr_ptr <= \'0;\n')
    f.write('      rel_ptr <= \'0;\n')
    f.write('      rx_active <= 1\'b0;\n')
    f.write('      for (int sl = 0; sl < NSLOT; sl++) begin\n')
    f.write('        slot_beat_cnt[sl] <= \'0; slot_done[sl] <= 1\'b0; slot_overflow[sl] <= 1\'b0;\n')
    f.write('        slot_txdone[sl] <= 1\'b0;\n')
    if needs_byte_len:
        f.write('        slot_byte_len[sl] <= \'0;\n')
    f.write('      end\n')
    f.write('    end else begin\n')
    f.write('      if (accept_beat) begin\n')
    if sop_std:
        f.write('        if (!rx_active) begin   // start of packet\n')
        for fn in sorted(sop_std):
            src = 'ingress_ts_ctr' if fn == 'ingress_timestamp' else fn
            f.write(f'          slot_sop_{fn}[wr_slot] <= {src};\n')
        f.write('        end\n')
    if needs_byte_len:
        popcount_terms = ' + '.join(f"{{15'd0, s_axis_tkeep[{i}]}}" for i in range(KEEP_W))
        f.write(f'        slot_byte_len[wr_slot] <= slot_byte_len[wr_slot] + ({popcount_terms});\n')
    f.write('        if (rx_beat_cnt < HDR_MAX_BEATS) begin\n')
    f.write(f'          for (int i = 0; i < {KEEP_W}; i++)\n')
    f.write('            if (s_axis_tkeep[i])\n')
    f.write(f'              slot_hdr[wr_slot*HDR_MAX_BYTES + rx_beat_cnt*{KEEP_W} + i] <= s_axis_tdata[i*8 +: 8];\n')
    f.write('          slot_keep[wr_slot*HDR_MAX_BEATS + rx_beat_cnt] <= s_axis_tkeep;\n')
    f.write(f'          slot_beat_cnt[wr_slot] <= rx_beat_cnt + {BEAT_CNT_W}\'d1;\n')
    f.write('        end else if (rx_beat_cnt < MAX_PKT_BEATS) begin\n')
    f.write(f'          slot_beat_cnt[wr_slot] <= rx_beat_cnt + {BEAT_CNT_W}\'d1;\n')
    f.write('        end else begin\n')
    f.write('          slot_overflow[wr_slot] <= 1\'b1;   // truncated; FIFO entry already marked last\n')
    f.write('        end\n')
    f.write('        rx_active <= !s_axis_tlast;\n')
    f.write('        if (s_axis_tlast) begin\n')
    f.write('          slot_done[wr_slot] <= 1\'b1;\n')
    f.write('          wr_ptr <= wr_ptr + 1\'b1;\n')
    f.write('        end\n')
    f.write('      end\n')
    f.write('      // slot release: TX has moved past rel_slot AND its tlast has arrived\n')
    f.write('      // TX finished with a slot: mark it, so release (which happens in\n')
    f.write('      // arrival order) can tell which slots are done under reordering.\n')
    f.write('      if (tx_finish) slot_txdone[tx_slot] <= 1\'b1;\n')
    f.write('      if (slot_release) begin\n')
    f.write('        rel_ptr <= rel_ptr + 1\'b1;\n')
    f.write('        slot_txdone[rel_slot] <= 1\'b0;\n')
    f.write('        slot_beat_cnt[rel_slot] <= \'0; slot_done[rel_slot] <= 1\'b0; slot_overflow[rel_slot] <= 1\'b0;\n')
    if needs_byte_len:
        f.write('        slot_byte_len[rel_slot] <= \'0;\n')
    f.write('      end\n')
    f.write('    end\n')
    f.write('  end\n\n')

    # ── Issue ─────────────────────────────────────────────────────────────────
    f.write('  // ── Issue (one-cycle valid_in pulse per packet) ──────────────────────────\n')
    f.write('  // Slot iss_slot is issuable once it is allocated (RX has at least started\n')
    f.write('  // it) and its header region has arrived -- the same cutoff the old shell\n')
    f.write('  // armed on. u_proc is a free-running pipeline: it captures the w_* inputs\n')
    f.write('  // on the issue edge, so nothing has to be held afterwards and the next\n')
    f.write('  // slot can be issued on the very next cycle.\n')
    f.write('  // iss_ptr can legitimately be ONE ahead of wr_ptr (a packet issued cut-\n')
    f.write('  // through before its tlast). "Behind" therefore has to exclude that case,\n')
    f.write('  // or an empty future slot would look allocated.\n')
    f.write('  wire iss_behind_wr = (iss_ptr != wr_ptr) && (iss_ptr != wr_ptr + 1\'b1);\n')
    f.write('  // "RX is mid-packet in wr_slot" is tracked EXPLICITLY (rx_active), not\n')
    f.write('  // inferred from slot_beat_cnt != 0: wr_ptr advances on tlast even when the\n')
    f.write('  // next slot still holds an older packet awaiting TX, and that packet\'s\n')
    f.write('  // beat count is nonzero too -- inferring from it re-issued a stale slot.\n')
    f.write('  wire iss_allocated = iss_behind_wr || ((iss_ptr == wr_ptr) && rx_active);\n')
    if needs_pkt_len:
        f.write('  // This program reads standard_metadata.packet_length, which is the\n')
        f.write('  // whole frame\'s byte count and is therefore not known until tlast.\n')
        f.write('  // Issue waits for the complete packet: STORE-AND-FORWARD for this\n')
        f.write('  // app, cut-through for every app that does not read it.\n')
        f.write('  wire iss_hdr_ready = slot_done[iss_slot];\n')
    else:
        f.write('  wire iss_hdr_ready = (slot_beat_cnt[iss_slot] * BEAT_BYTES >= cutoff_byte) || slot_done[iss_slot];\n')
    f.write('  assign iss_fire = iss_allocated && iss_hdr_ready;\n')
    f.write('  always_ff @(posedge clk) begin\n')
    f.write('    if (!rst_n) iss_ptr <= \'0;\n')
    f.write('    else if (iss_fire) begin\n')
    f.write('      iss_ptr <= iss_ptr + 1\'b1;\n')
    for fn, fw in sorted(eg_issue_std.items()):
        f.write(f'      slot_std_meta_{fn}[iss_slot] <= {_shell_std_src(fn, fw)};   // for egress\n')
    f.write('    end\n')
    f.write('  end\n\n')
    # ── Ingress completion (enqueue) and egress completion (capture) ──────────
    # ONE always_ff, not two. Both events write the same per-slot arrays
    # (slot_drop, slot_phv_*, slot_meta_*, ...), and two procedural blocks
    # driving one array is a multi-driver: iverilog tolerates it, Quartus
    # rejects it outright ("Can't resolve multiple constant drivers"). They
    # can fire in the same cycle -- on different slots, since a slot cannot be
    # completing ingress and egress at once -- so the two if-bodies are
    # independent and the array simply has one driver.
    if ectrl:
        f.write('  // Queue selection and the tail-drop test, declared ahead of the block\n')
        f.write('  // below that reads them (this file keeps declarations before uses).\n')
        if QCOUNT > 1:
            f.write(f'  wire [QSEL_W-1:0] enq_q = ig_out_std_meta_egress_port[QSEL_W-1:0];\n')
        else:
            f.write('  wire [QSEL_W-1:0] enq_q = \'0;\n')
        if tm_qlimit is not None:
            f.write(f'  localparam int TM_QLIMIT = {tm_qlimit};\n')
            f.write('  logic tail_drop;\n')
            f.write('  always_comb tail_drop = (tmq_depth[enq_q] >= TM_QLIMIT);\n')
            f.write('  logic [31:0] tm_tail_drops;   // observable via the shell, not the CP\n')
    f.write('  // ── Enqueue (ingress done) and capture (egress done) ─────────────────────\n')
    if ectrl:
        f.write('  // Ingress writes its WHOLE result into the slot -- that store is the\n')
        f.write('  // queueing point\'s packet state, which u_egress reads back at dequeue.\n')
        f.write('  // Egress then overwrites the same slot with the final PHV.\n')
    f.write('  always_ff @(posedge clk) begin\n')
    f.write('    if (!rst_n) begin\n')
    if ectrl:
        f.write('      ig_ptr  <= \'0;\n')
    else:
        f.write('      cmp_ptr <= \'0;\n')
    f.write('    end else begin\n')
    if ectrl:
        f.write('      if (proc_out_valid) begin\n')
        f.write('        ig_ptr <= ig_ptr + 1\'b1;\n')
        if 'enq_qdepth' in tm_std:
            f.write(f'        slot_enq_qdepth[ig_slot] <= {tm_std["enq_qdepth"]}\'(tmq_depth[enq_q]);\n')
        if tm_qlimit is not None:
            f.write('        // Tail drop: the target queue is at its limit, so the traffic\n')
            f.write('        // manager discards this packet. It still walks the rest of the\n')
            f.write('        // pipeline as a dropped packet (egress side effects suppressed,\n')
            f.write('        // TX discards the bytes), which is how its slot gets released.\n')
            f.write('        slot_drop[ig_slot] <= proc_drop || tail_drop;\n')
        else:
            f.write('        slot_drop[ig_slot] <= proc_drop;\n')
        for hname in all_hdr_names:
            if inst_map.get(hname):
                f.write(f'        slot_phv_{hname}_valid[ig_slot] <= out_{hname}_valid;\n')
        for hname, fname, w in hdr_fields:
            f.write(f'        slot_phv_{hname}_{fname}[ig_slot] <= out_{hname}_{fname};\n')
        for mf in ir.metadata_fields:
            f.write(f'        slot_meta_{mf.name}[ig_slot] <= proc_out_meta_{mf.name};\n')
        for fn in sorted(ig_std_outs):
            f.write(f'        slot_std_meta_{fn}[ig_slot] <= ig_out_std_meta_{fn};\n')
        for cnt in ig_counters:
            f.write(f'        slot_cnt_{cnt.name}_en[ig_slot]  <= {cnt.name}_incr_en;\n')
            f.write(f'        slot_cnt_{cnt.name}_idx[ig_slot] <= {cnt.name}_incr_idx;\n')
        f.write('      end\n')
    f.write(f'      if ({fin_valid}) begin\n')
    if not ectrl:
        # No egress stage: completion order is issue order, so the ring pointer
        # still names the completing slot. With egress it comes off egq.
        f.write('        cmp_ptr <= cmp_ptr + 1\'b1;\n')
    f.write(f'        slot_drop[cmp_slot] <= {fin_drop};\n')
    for hname in all_hdr_names:
        if inst_map.get(hname):
            f.write(f'        slot_phv_{hname}_valid[cmp_slot] <= {fin_hdr}{hname}_valid;\n')
    for hname, fname, w in hdr_fields:
        f.write(f'        slot_phv_{hname}_{fname}[cmp_slot] <= {fin_hdr}{hname}_{fname};\n')
    for mf in ir.metadata_fields:
        f.write(f'        slot_meta_{mf.name}[cmp_slot] <= {fin_meta}{mf.name};\n')
    if ectrl:
        for fn in sorted(eg_std_outs):
            f.write(f'        slot_std_meta_{fn}[cmp_slot] <= eg_out_std_meta_{fn};\n')
        for cnt in eg_counters:
            f.write(f'        slot_cnt_{cnt.name}_en[cmp_slot]  <= {cnt.name}_incr_en;\n')
            f.write(f'        slot_cnt_{cnt.name}_idx[cmp_slot] <= {cnt.name}_incr_idx;\n')
    else:
        for fn in sorted(ig_std_outs):
            f.write(f'        slot_std_meta_{fn}[cmp_slot] <= ig_out_std_meta_{fn};\n')
        for cnt in ig_counters:
            f.write(f'        slot_cnt_{cnt.name}_en[cmp_slot]  <= {cnt.name}_incr_en;\n')
            f.write(f'        slot_cnt_{cnt.name}_idx[cmp_slot] <= {cnt.name}_incr_idx;\n')
    f.write('      end\n')
    f.write('    end\n')
    f.write('  end\n\n')

    if ectrl:
        f.write('  // ── Queue bookkeeping: enqueue, schedule, egress in-flight, transmit ─────\n')
        f.write('  always_ff @(posedge clk) begin\n')
        f.write('    if (!rst_n) begin\n')
        f.write('      for (int q = 0; q < QCOUNT; q++) begin tmq_wr[q] <= \'0; tmq_rd[q] <= \'0; end\n')
        f.write('      egq_wr <= \'0; egq_rd <= \'0; txq_wr <= \'0; txq_rd <= \'0; rr_ptr <= \'0;\n')
        f.write('    end else begin\n')
        f.write('      // enqueue: ingress finished, pick the queue from egress_port\n')
        f.write('      if (proc_out_valid) begin\n')
        f.write('        tmq_mem[enq_q*NSLOT + tmq_wr[enq_q][SLOT_AW-1:0]] <= ig_slot;\n')
        f.write('        tmq_wr[enq_q] <= tmq_wr[enq_q] + 1\'b1;\n')
        f.write('      end\n')
        f.write('      // dequeue: hand the scheduled slot to u_egress and remember it\n')
        f.write('      if (deq_fire) begin\n')
        f.write('        tmq_rd[sched_q] <= tmq_rd[sched_q] + 1\'b1;\n')
        f.write('        rr_ptr <= (sched_q == QCOUNT-1) ? \'0: sched_q + 1\'b1;\n')
        f.write('        egq_mem[egq_wr[SLOT_AW-1:0]] <= deq_slot;\n')
        f.write('        egq_wr <= egq_wr + 1\'b1;\n')
        f.write('      end\n')
        f.write('      // egress finished: that slot is ready for the wire\n')
        f.write('      if (eg_out_valid) begin\n')
        f.write('        egq_rd <= egq_rd + 1\'b1;\n')
        f.write('        txq_mem[txq_wr[SLOT_AW-1:0]] <= cmp_slot;\n')
        f.write('        txq_wr <= txq_wr + 1\'b1;\n')
        f.write('      end\n')
        f.write('      if (tx_finish) txq_rd <= txq_rd + 1\'b1;\n')
        f.write('    end\n')
        f.write('  end\n\n')
        if tm_qlimit is not None:
            f.write('  always_ff @(posedge clk) begin\n')
            f.write('    if (!rst_n) tm_tail_drops <= \'0;\n')
            f.write('    else if (proc_out_valid && tail_drop) tm_tail_drops <= tm_tail_drops + 1\'b1;\n')
            f.write('  end\n\n')
    else:
        # No egress control: ingress completion feeds the transmit queue
        # directly, so there is nothing to schedule -- one queue, in order.
        f.write('  // ── Transmit queue (no egress stage: completion is issue order) ─────────\n')
        f.write('  always_ff @(posedge clk) begin\n')
        f.write('    if (!rst_n) begin\n')
        f.write('      txq_wr <= \'0; txq_rd <= \'0;\n')
        f.write('    end else begin\n')
        f.write('      if (proc_out_valid) begin\n')
        f.write('        txq_mem[txq_wr[SLOT_AW-1:0]] <= cmp_slot;\n')
        f.write('        txq_wr <= txq_wr + 1\'b1;\n')
        f.write('      end\n')
        f.write('      if (tx_finish) txq_rd <= txq_rd + 1\'b1;\n')
        f.write('    end\n')
        f.write('  end\n\n')

    # ── TX-side views of slot tx_slot ─────────────────────────────────────────
    f.write('  // ── TX-side view of slot tx_slot ─────────────────────────────────────────\n')
    f.write('  logic [7:0] t_hdr [0:HDR_MAX_BYTES-1];\n')
    f.write('  always_comb for (int i = 0; i < HDR_MAX_BYTES; i++) t_hdr[i] = slot_hdr[tx_slot*HDR_MAX_BYTES + i];\n')
    for hname in all_hdr_names:
        if inst_map.get(hname):
            f.write(f'  wire phv_{hname}_valid = slot_phv_{hname}_valid[tx_slot];\n')
    for hname, fname, w in hdr_fields:
        f.write(f'  wire [{w-1}:0] phv_{hname}_{fname} = slot_phv_{hname}_{fname}[tx_slot];\n')
    f.write('\n')
    # phv_*_base: the same offset arithmetic as w_*_base, over the STORED output
    # PHV (header length is preserved by the program, so the offsets agree).
    import io as _io, re as _re
    _buf = _io.StringIO()
    _emitted = set()
    for layout in layouts:
        _emit_offset_var_for(_buf, layout, layouts, valid_map, hdr_idx_w, _emitted)
    _txt = _re.sub(r'\bw_', 'phv_', _buf.getvalue())
    if _txt.strip():
        f.write('  // header byte offsets over the stored PHV (same arithmetic as w_*_base)\n')
        f.write(_txt)
        f.write('\n')

    # ── Deparser overlay for the slot TX is on ─────────────────────────────────
    f.write('  // ── Deparser: header-region assembly for slot tx_slot ────────────────────\n')
    f.write('  // Received bytes of the slot with its stored output PHV overlaid at each\n')
    f.write('  // header\'s layout offset, guarded by the stored output validity.\n')
    f.write('  logic [7:0] hdr_out [0:HDR_MAX_BYTES-1];\n')
    f.write('  always_comb begin\n')
    f.write('    for (int i = 0; i < HDR_MAX_BYTES; i++) hdr_out[i] = t_hdr[i];\n')
    _emit_writeback_block(f, layouts, inst_map, valid_map, '    ', target='hdr_out', op='=',
                          fld_pfx='phv_', base_pfx='phv_')
    f.write('  end\n\n')

    # ── TX ────────────────────────────────────────────────────────────────────
    f.write('  // ── TX (egress) ──────────────────────────────────────────────────────────\n')
    f.write('  // No start cycle and no finish-on-consume: the slot at tx_slot is "live"\n')
    f.write('  // the moment its result is captured (cmp_ptr != tx_ptr), its first row\n')
    f.write('  // loads on any cycle the output register is free, and the packet is\n')
    f.write('  // FINISHED when its last beat is LOADED into tx_out (the data is a copy,\n')
    f.write('  // so the slot can be released right then). tx_ptr advances on that\n')
    f.write('  // edge, so on the cycle the last beat is consumed the next slot\'s first\n')
    f.write('  // row is already loading -- one beat per cycle across packet boundaries.\n')
    f.write('  // Before this TX cost ~2.5 cycles per packet on top of its beats (a\n')
    f.write('  // start cycle plus finish-on-consume), which was the whole gap to ideal.\n')
    f.write('  // Per-slot facts (drop, metadata, counter request) are read straight\n')
    f.write('  // from the slot each cycle -- they are stable for the slot\'s lifetime --\n')
    f.write('  // so nothing needs latching at a start event. The metadata sideband\n')
    f.write('  // rides in tx_out with the beat, so it changes exactly when the first\n')
    f.write('  // beat of the next packet is presented.\n')
    f.write('  wire tx_consumed  = tx_out_valid && m_axis_tready;\n')
    f.write('  wire tx_slot_free = !tx_out_valid || tx_consumed;\n')
    f.write('  wire slot_live    = (txq_wr != txq_rd);\n')
    f.write('  wire cur_discard  = slot_drop[tx_slot];\n')
    f.write(f'  wire [{BEAT_CNT_W-1}:0] tx_beat_cnt_s = slot_beat_cnt[tx_slot];\n')
    f.write('  wire tx_done_s        = slot_done[tx_slot];\n')
    f.write('  wire pkt_ends_in_hdr  = tx_done_s && (tx_beat_cnt_s <= HDR_MAX_BEATS);\n')
    f.write('  wire hdr_row_ready    = (tx_hdr_row < tx_beat_cnt_s) && (tx_hdr_row < HDR_MAX_BEATS);\n')
    f.write(f'  wire hdr_row_is_last  = tx_done_s && (tx_hdr_row == tx_beat_cnt_s - {BEAT_CNT_W}\'d1);\n')
    f.write('  wire emit_hdr    = slot_live && !cur_discard && !tx_in_payload && hdr_row_ready && tx_slot_free;\n')
    f.write('  wire emit_pl     = slot_live && !cur_discard &&  tx_in_payload && pfifo_rd_valid && tx_slot_free;\n')
    f.write('  wire discard_pop = slot_live &&  cur_discard && pfifo_rd_valid;\n')
    f.write('  assign pfifo_rd_en = emit_pl || discard_pop;\n')
    f.write('  wire last_loaded  = (emit_hdr && hdr_row_is_last) || (emit_pl && pfifo_head_last);\n')
    f.write('  wire discard_done = slot_live && cur_discard && (pkt_ends_in_hdr || (discard_pop && pfifo_head_last));\n')
    f.write('  assign tx_finish  = last_loaded || discard_done;\n')
    # Release: a slot is reusable once TX has finished it AND its reception is
    # complete. Transmission order is now the scheduler's, so "TX has finished
    # it" is a per-slot flag rather than a pointer comparison. Slots are still
    # RELEASED in arrival order (rel_ptr), which keeps the allocator a ring:
    # a slot transmitted early waits for older slots to be freed. With a
    # round-robin scheduler every queue drains, so the wait is bounded; a free
    # list would remove it at the cost of an allocator.
    f.write('  wire slot_release = slot_done[rel_slot] && slot_txdone[rel_slot];\n')

    f.write('\n')


    f.write('  always_ff @(posedge clk) begin\n')
    f.write('    if (!rst_n) begin\n')

    f.write('      tx_in_payload <= 1\'b0;\n')
    f.write('      tx_hdr_row    <= \'0;\n')
    f.write('      tx_out_valid  <= 1\'b0;\n')
    f.write('      tx_out_data   <= \'0;\n')
    f.write('      tx_out_keep   <= \'0;\n')
    f.write('      tx_out_last   <= 1\'b0;\n')

    for mf in ir.metadata_fields:
        f.write(f'      out_meta_{mf.name} <= \'0;\n')
    for fn in sorted(sideband_std):
        f.write(f'      out_std_meta_{fn} <= \'0;\n')
    f.write('    end else begin\n')

    f.write('      if (tx_consumed) tx_out_valid <= 1\'b0;\n')
    f.write('      if (emit_hdr) begin\n')
    f.write('        tx_out_valid <= 1\'b1;\n')
    f.write(f'        for (int i = 0; i < {KEEP_W}; i++)\n')
    f.write(f'          tx_out_data[i*8 +: 8] <= hdr_out[tx_hdr_row * {KEEP_W} + i];\n')
    f.write('        tx_out_keep  <= slot_keep[tx_slot*HDR_MAX_BEATS + tx_hdr_row];\n')
    f.write('        tx_out_last  <= hdr_row_is_last;\n')
    f.write(f'        tx_hdr_row   <= tx_hdr_row + {BEAT_CNT_W}\'d1;\n')
    f.write('        if (!hdr_row_is_last && tx_hdr_row == HDR_MAX_BEATS - 1) tx_in_payload <= 1\'b1;\n')
    for mf in ir.metadata_fields:
        f.write(f'        out_meta_{mf.name} <= slot_meta_{mf.name}[tx_slot];\n')
    for fn in sorted(sideband_std):
        f.write(f'        out_std_meta_{fn} <= slot_std_meta_{fn}[tx_slot];\n')
    f.write('      end else if (emit_pl) begin\n')
    f.write('        tx_out_valid <= 1\'b1;\n')
    f.write('        tx_out_data  <= pfifo_head_data;\n')
    f.write('        tx_out_keep  <= pfifo_head_keep;\n')
    f.write('        tx_out_last  <= pfifo_head_last;\n')
    for mf in ir.metadata_fields:
        f.write(f'        out_meta_{mf.name} <= slot_meta_{mf.name}[tx_slot];\n')
    for fn in sorted(sideband_std):
        f.write(f'        out_std_meta_{fn} <= slot_std_meta_{fn}[tx_slot];\n')
    f.write('      end\n')
    f.write('      if (tx_finish) begin\n')
    f.write('        tx_in_payload <= 1\'b0;\n')
    f.write('        tx_hdr_row    <= \'0;\n')

    f.write('      end\n')
    f.write('    end\n')
    f.write('  end\n\n')

    # ── Counter externs (one request per packet at slot release) ──────────────
    for cnt in all_counters:
        has_pkt  = cnt.counter_type in ('PACKETS', 'PACKETS_AND_BYTES')
        has_byte = cnt.counter_type in ('BYTES', 'PACKETS_AND_BYTES')
        f.write(f'  {cnt.name}_counter #(.DEPTH({cnt.size})) u_{cnt.name} (\n')
        f.write('    .clk (clk), .rst_n (rst_n),\n')
        # One request per packet, on the cycle its slot is released: the slot
        # is still intact during that cycle (the clear lands on the edge), and
        # its byte length is final -- release waits for the packet's tlast.
        f.write('    .incr_fire (slot_release),\n')
        f.write(f'    .incr_req  (slot_cnt_{cnt.name}_en[rel_slot]),\n')
        f.write(f'    .incr_idx  (slot_cnt_{cnt.name}_idx[rel_slot]),\n')
        if has_byte:
            f.write('    .pkt_byte_len (slot_byte_len[rel_slot]),\n')
        f.write(f'    .cp_query_en  ({cnt.name}_cp_query_en),\n')
        f.write(f'    .cp_query_idx ({cnt.name}_cp_query_idx),\n')
        f.write(f'    .cp_query_busy ({cnt.name}_cp_query_busy)')
        if has_pkt:
            f.write(f',\n    .cp_query_pkt_value ({cnt.name}_cp_query_pkt_value)')
        if has_byte:
            f.write(f',\n    .cp_query_byte_value ({cnt.name}_cp_query_byte_value)')
        f.write('\n  );\n\n')

    # ── TX output ──────────────────────────────────────────────────────────────
    f.write('  // ── TX output ────────────────────────────────────────────────────────────\n')
    f.write('  // Plain registered pass-through -- see the always_ff above for the fetch/\n')
    f.write('  // issue logic that fills tx_out_*. tlast is additionally gated on tx_out_valid\n')
    f.write('  // defensively (tx_out_last could otherwise hold a stale value across a clear).\n')
    f.write('  assign m_axis_tvalid = tx_out_valid;\n')
    f.write('  assign m_axis_tdata  = tx_out_data;\n')
    f.write('  assign m_axis_tkeep  = tx_out_keep;\n')
    f.write('  assign m_axis_tlast  = tx_out_valid && tx_out_last;\n\n')

    f.write('endmodule\n')


# ── Offset variable emitter ────────────────────────────────────────────────────

def _counter_idx_w(cnt):
    return max(1, math.ceil(math.log2(cnt.size))) if cnt.size > 1 else 1


def _emit_offset_var_for(f, layout, layouts, valid_map, hdr_idx_w, emitted):
    """
    Emit the wire declaration for one header's runtime-computed byte offset
    (a no-op if this header has only mandatory predecessors -- fixed offset,
    no variable needed -- or its var was already emitted). Factored out of
    _emit_offset_vars so callers can interleave this per-header, in the same
    topological (parse) order as field-wire emission -- required because a
    var_pred offset can reference an EARLIER header's own field (e.g. an
    ipv4-options header's offset depending on ipv4's hdr_len field), which
    must itself already be declared. See the caller in _write_module for the
    full cross-toolchain (Vivado xvlog vs iverilog) rationale.
    """
    inst_name      = layout['inst_name']
    mandatory_base = layout['mandatory_base']
    optional_preds = layout['optional_preds']
    var_pred       = layout['var_pred']

    if not optional_preds and var_pred is None:
        return  # fixed offset, no var needed

    var_name = _offset_var(inst_name)
    if var_name in emitted:
        return
    emitted.add(var_name)

    if optional_preds and var_pred is None:
        # offset = mandatory_base + sum(size if opt_valid else 0 for opt, size in optional_preds)
        terms = [str(mandatory_base)]
        for opt_name, opt_size in optional_preds:
            vexpr = valid_map.get(opt_name, "1'b0")
            terms.append(f'({vexpr} ? {opt_size} : 0)')
        expr = ' + '.join(terms)
        f.write(f'  wire [{hdr_idx_w-1}:0] {var_name} = {expr};\n')

    elif var_pred is not None:
        vname, vfield = var_pred
        # base = previous header's offset + (length_field * scale)
        # hdr_len field has scale factor 4 (32-bit words → bytes)
        prev_var = _offset_var(vname)
        prev_layout = next((l for l in layouts if l['inst_name'] == vname), None)
        has_prev_var = (prev_layout and
                        (prev_layout['optional_preds'] or prev_layout['var_pred'] is not None))
        prev_base_expr = prev_var if has_prev_var else str(
            prev_layout['mandatory_base'] if prev_layout else 0)
        hdr_bytes_var = f'w_{vname}_hdr_bytes'
        if hdr_bytes_var not in emitted:
            emitted.add(hdr_bytes_var)
            f.write(f'  wire [{hdr_idx_w-1}:0] {hdr_bytes_var} = '
                    f'{{{hdr_idx_w-4}\'b0, w_{vname}_{vfield}}} << 2;\n')
        f.write(f'  wire [{hdr_idx_w-1}:0] {var_name} = '
                f'{prev_base_expr} + {hdr_bytes_var};\n')


def _emit_offset_vars(f, layouts, inst_map, valid_map, hdr_idx_w):
    """
    Emit wire declarations for runtime-computed header byte offsets, for
    every header in one pass (see _emit_offset_var_for for the per-header
    logic). Headers with only mandatory predecessors (fixed offset) need no
    variable. Headers with optional or variable predecessors get a
    w_{name}_base wire. Not used by _write_module directly any more (its own
    field/offset emission is interleaved per-header instead, see there) --
    kept as the simple non-interleaved form for any future caller that
    doesn't have this file's specific forward-reference constraint.
    """
    emitted = set()
    for layout in layouts:
        _emit_offset_var_for(f, layout, layouts, valid_map, hdr_idx_w, emitted)
    f.write('\n')


def _emit_cutoff_expr(f, layouts, inst_map, valid_map, hdr_idx_w):
    """
    Emit `cutoff_byte`: the smallest byte position at which every header
    this specific packet could contain (given what's arrived so far) has
    fully landed in pkt_buf_hdr. RX triggers match-action processing the
    first cycle rx_beat_cnt*BEAT_BYTES >= cutoff_byte holds, instead of
    waiting for the whole packet -- this is what makes the design
    cut-through rather than store-and-forward.

    Write-back rewrites EVERY header in `layouts` unconditionally (gated
    only by that header's own validity, since processing_generated already
    pass-throughs untouched fields) -- so the correct footprint is "every
    header with any bytes has arrived", not just the fields match-action
    actually reads.

    Each header's term is gated by its own validity wire (so e.g. an
    absent VLAN doesn't inflate the cutoff for non-VLAN packets). This is
    safe to sample every cycle and trigger on first-true despite depending
    on not-yet-fully-arrived data early on: a header's own term always
    dominates (shields) any later header's data-dependent base-offset
    computation from false-triggering on stale bytes, because every
    var_pred length field is unsigned (see _worst_case_hdr_bytes) -- if a
    length field's own byte hasn't arrived yet, its stale value can only
    make a later term compute too LOW, never mask a still-outstanding
    earlier one, since the earlier header's own (always-correct) term is
    already in the max.
    """
    terms = []
    for layout in layouts:
        inst_name = layout['inst_name']
        inst = inst_map.get(inst_name)
        if not inst:
            continue
        mandatory_base = layout['mandatory_base']
        optional_preds = layout['optional_preds']
        var_pred       = layout['var_pred']
        base_expr = _choose_base_expr(inst_name, mandatory_base, optional_preds, var_pred)
        size  = _hdr_bytes_total(inst)
        vexpr = valid_map.get(inst_name, "1'b1")
        term_name = f'w_{inst_name}_cutoff_term'
        if vexpr == "1'b1":
            f.write(f'  wire [{hdr_idx_w-1}:0] {term_name} = {base_expr} + {size};\n')
        else:
            f.write(f'  wire [{hdr_idx_w-1}:0] {term_name} = '
                    f'{vexpr} ? ({base_expr} + {size}) : {hdr_idx_w}\'d0;\n')
        terms.append(term_name)

    if not terms:
        f.write(f"  wire [{hdr_idx_w-1}:0] cutoff_byte = {hdr_idx_w}'d0;\n")
    else:
        # Reduce via named intermediate wires, not nested inline expression
        # text -- chaining `(({expr}) > ({t}) ? ({expr}) : ({t}))` directly
        # would re-embed the whole growing expression twice at every step
        # (once as the true-branch, once inside the condition), blowing up
        # exponentially with header count.
        acc = terms[0]
        for i, t in enumerate(terms[1:], start=1):
            acc_name = f'w_cutoff_max_{i}'
            f.write(f'  wire [{hdr_idx_w-1}:0] {acc_name} = '
                    f'({acc} > {t}) ? {acc} : {t};\n')
            acc = acc_name
        f.write(f'  wire [{hdr_idx_w-1}:0] cutoff_byte = {acc};\n')
    f.write('\n')


def _choose_base_expr(inst_name, mandatory_base, optional_preds, var_pred):
    """Return the SV base expression for a header's byte offset."""
    if not optional_preds and var_pred is None:
        return mandatory_base   # plain int
    return _offset_var(inst_name)


# ── Write-back block ──────────────────────────────────────────────────────────

def _emit_writeback_block(f, layouts, inst_map, valid_map, ind,
                          target='pkt_buf_hdr', op='<=', fld_pfx='out_', base_pfx='w_'):
    """Emit placement of the pipeline's output header fields at their layout
    offsets -- into pkt_buf_hdr (registered write-back) or hdr_out
    (combinational deparser overlay), see _writeback_bytes."""
    for layout in layouts:
        inst_name    = layout['inst_name']
        inst         = inst_map.get(inst_name)
        if not inst:
            continue
        mandatory_base = layout['mandatory_base']
        optional_preds = layout['optional_preds']
        var_pred       = layout['var_pred']

        base_expr = _choose_base_expr(inst_name, mandatory_base, optional_preds, var_pred)
        if not isinstance(base_expr, int):
            base_expr = base_expr.replace('w_', base_pfx, 1)
        vexpr     = valid_map.get(inst_name, "1'b1")
        cond      = None if vexpr == "1'b1" else f'{fld_pfx}{inst_name}_valid'

        _writeback_bytes(f, inst_name, base_expr, inst.header_type,
                         fld_pfx, cond, ind, target=target, op=op)
