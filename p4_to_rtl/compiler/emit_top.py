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

def _build_axil_regmap(ctrl, amap, fwmap):
    """
    Return list of table register-map entries:
    [
      {
        'tname': str,
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

    for tbl in ctrl.tables:
        tname   = tbl.name
        depth   = tbl.size or 1024
        idx_w   = max(1, math.ceil(math.log2(max(depth, 2))))
        act_ids = _table_action_ids(tbl)
        n_acts  = max(act_ids.values()) + 1 if act_ids else 1
        act_w   = max(1, math.ceil(math.log2(max(n_acts, 2))))
        params  = _table_params(tbl, amap)

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
            kw    = fwmap.get(kname, 32)
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
    for cnt in ctrl.counters:
        cname = cnt.name
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

def emit_top(ir, app_name, output_path, axi_data_width=DEFAULT_AXI_DATA_W, board=None, nslot=4):
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
    regmap = _build_axil_regmap(ctrl, amap, fwmap)

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
                      board, verify_terms=verify_terms, nslot=nslot)


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
                  board=None, verify_terms=None, nslot=4):

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
    needs_byte_len = any(c.counter_type in ('BYTES', 'PACKETS_AND_BYTES')
                          for c in ctrl.counters)

    # Standard-metadata inputs the processing module declares (same scan
    # emit_processing uses, so the two can't disagree about which ports exist).
    # These were previously left completely unconnected: the ports were
    # declared and nothing drove them.
    std_meta_ins = _collect_std_meta_inputs(ctrl)
    # parsed_bytes is the packet's byte count, which the shell already knows
    # how to compute for BYTES-type counters -- reuse it rather than counting
    # twice.
    if 'parsed_bytes' in std_meta_ins:
        needs_byte_len = True

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
    if ir.metadata_fields:
        f.write(',\n\n    // Metadata sideband (valid while m_axis_tvalid for the packet)\n')
        for i, mf in enumerate(ir.metadata_fields):
            comma = ',' if i < len(ir.metadata_fields) - 1 else ''
            f.write(f'    output logic [{mf.width-1}:0] out_meta_{mf.name}{comma}\n')
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
    f.write('  logic slot_drop     [0:NSLOT-1];\n')
    f.write('  `ifndef SYNTHESIS\n')
    f.write('  // synthesis translate_off\n')
    f.write('  initial begin\n')
    f.write('    for (int i = 0; i < NSLOT*HDR_MAX_BYTES; i++) slot_hdr[i] = 8\'d0;\n')
    f.write('  end\n')
    f.write('  // synthesis translate_on\n')
    f.write('  `endif\n')
    f.write('  logic [SLOT_AW:0] wr_ptr, iss_ptr, cmp_ptr, tx_ptr, rel_ptr;\n')
    f.write('  wire  [SLOT_AW-1:0] wr_slot  = wr_ptr[SLOT_AW-1:0];\n')
    f.write('  wire  [SLOT_AW-1:0] iss_slot = iss_ptr[SLOT_AW-1:0];\n')
    f.write('  wire  [SLOT_AW-1:0] cmp_slot = cmp_ptr[SLOT_AW-1:0];\n')
    f.write('  wire  [SLOT_AW-1:0] tx_slot  = tx_ptr[SLOT_AW-1:0];\n')
    f.write('  wire  [SLOT_AW-1:0] rel_slot = rel_ptr[SLOT_AW-1:0];\n')
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

    # payload FIFO
    f.write(f'  localparam int PFIFO_W  = AXI_DATA_W + AXI_DATA_W/8 + 1;  // {{last, keep, data}}\n')
    f.write(f'  localparam int PFIFO_AW = {PFIFO_AW};\n')
    f.write(f'  localparam int PFIFO_DEPTH = 1 << PFIFO_AW;  // {1 << PFIFO_AW} >= PAYLOAD_MAX_BEATS\n')
    f.write('  logic                pfifo_wr_en;\n')
    f.write('  logic [PFIFO_W-1:0]  pfifo_wr_data;\n')
    f.write('  logic                pfifo_full;\n')
    f.write('  logic                pfifo_rd_valid;\n')
    f.write('  logic [PFIFO_W-1:0]  pfifo_rd_data;\n')
    f.write('  logic                pfifo_rd_en;\n')
    f.write('  logic [PFIFO_AW:0]   pfifo_occupancy;\n')
    f.write('  pkt_beat_fifo #(.W(PFIFO_W), .DEPTH(PFIFO_DEPTH), .AW(PFIFO_AW)) u_pfifo (\n')
    f.write('    .clk(clk), .rst_n(rst_n),\n')
    f.write('    .wr_en(pfifo_wr_en), .wr_data(pfifo_wr_data), .full(pfifo_full),\n')
    f.write('    .rd_valid(pfifo_rd_valid), .rd_data(pfifo_rd_data), .rd_en(pfifo_rd_en),\n')
    f.write('    .occupancy(pfifo_occupancy)\n')
    f.write('  );\n')
    f.write('  wire                  pfifo_head_last = pfifo_rd_data[PFIFO_W-1];\n')
    f.write('  wire [AXI_DATA_W/8-1:0] pfifo_head_keep = pfifo_rd_data[AXI_DATA_W +: AXI_DATA_W/8];\n')
    f.write('  wire [AXI_DATA_W-1:0]   pfifo_head_data = pfifo_rd_data[AXI_DATA_W-1:0];\n\n')

    # ── State registers ────────────────────────────────────────────────────────
    f.write('  // ── State registers ──────────────────────────────────────────────────────\n')
    f.write('  //   iss_fire     : one-cycle valid_in pulse to u_proc for slot iss_slot\n')
    f.write('  //   proc_out_valid: u_proc\'s data-ALIGNED valid (out_valid port) -- the\n')
    f.write('  //                  cycle out_*/drop belong to slot cmp_slot\n')
    f.write('  //   tx_hdr_row/tx_in_payload: TX progress through slot tx_slot\n')
    if 'ingress_timestamp' in std_meta_ins:
        tsw = std_meta_ins['ingress_timestamp']
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
    f.write('\n')

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
    for cnt in ctrl.counters:
        idx_w = max(1, math.ceil(math.log2(cnt.size))) if cnt.size > 1 else 1
        f.write(f'  wire {cnt.name}_incr_en;\n')
        f.write(f'  wire [{idx_w-1}:0] {cnt.name}_incr_idx;\n')

    f.write('\n')
    if 'ingress_timestamp' in std_meta_ins:
        tsw = std_meta_ins['ingress_timestamp']
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
        if fname == 'ingress_timestamp':
            f.write(f'    .std_meta_{fname}  (ingress_ts_ctr),\n')
        elif fname == 'parsed_bytes':
            f.write(f'    .std_meta_{fname}  ({fw}\'({{slot_byte_len[iss_slot]}})),\n')
        elif fname == 'parser_error':
            if verify_terms:
                f.write(f'    .std_meta_{fname}  (w_parser_error),\n')
            else:
                # No verify() in this program, so there is nothing that could
                # ever set it: NoError by construction.
                f.write(f'    .std_meta_{fname}  ({fw}\'d0),  // NoError -- program has no verify()\n')
        else:
            f.write(f'    .std_meta_{fname}  ({fw}\'b0),  // no shell source for this field\n')
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
    # cp_wr ports (tables only -- counters have no cp_wr/cp_query/hit_out
    # ports on processing_generated; see the incr_en/incr_idx loop below)
    for ti in regmap:
        if ti.get('is_counter'):
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
    for cnt in ctrl.counters:
        f.write(f'    .{cnt.name}_incr_en  ({cnt.name}_incr_en),\n')
        f.write(f'    .{cnt.name}_incr_idx ({cnt.name}_incr_idx),\n')
    f.write('    .out_valid (proc_out_valid),   // aligned with out_*/drop\n')
    f.write('    .valid_out (proc_valid_out),   // legacy registered-late valid, unused here\n')
    f.write('    .drop      (proc_drop)\n')
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
    for cnt in ctrl.counters:
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
    if needs_byte_len:
        f.write('        slot_byte_len[sl] <= \'0;\n')
    f.write('      end\n')
    f.write('    end else begin\n')
    f.write('      if (accept_beat) begin\n')
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
    f.write('      if (slot_release) begin\n')
    f.write('        rel_ptr <= rel_ptr + 1\'b1;\n')
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
    f.write('  wire iss_hdr_ready = (slot_beat_cnt[iss_slot] * BEAT_BYTES >= cutoff_byte) || slot_done[iss_slot];\n')
    f.write('  assign iss_fire = iss_allocated && iss_hdr_ready;\n')
    f.write('  always_ff @(posedge clk) begin\n')
    f.write('    if (!rst_n) iss_ptr <= \'0;\n')
    f.write('    else if (iss_fire) iss_ptr <= iss_ptr + 1\'b1;\n')
    f.write('  end\n\n')
    if 'ingress_timestamp' in std_meta_ins:
        f.write('  always_ff @(posedge clk) begin\n')
        f.write('    if (!rst_n) ingress_ts_ctr <= \'0;\n')
        f.write('    else        ingress_ts_ctr <= ingress_ts_ctr + 1\'b1;\n')
        f.write('  end\n\n')

    # ── Capture ───────────────────────────────────────────────────────────────
    f.write('  // ── Capture (u_proc.out_valid -> slot cmp_slot) ──────────────────────────\n')
    f.write('  always_ff @(posedge clk) begin\n')
    f.write('    if (!rst_n) cmp_ptr <= \'0;\n')
    f.write('    else if (proc_out_valid) begin\n')
    f.write('      cmp_ptr <= cmp_ptr + 1\'b1;\n')
    f.write('      slot_drop[cmp_slot] <= proc_drop;\n')
    for hname in all_hdr_names:
        if inst_map.get(hname):
            f.write(f'      slot_phv_{hname}_valid[cmp_slot] <= out_{hname}_valid;\n')
    for hname, fname, w in hdr_fields:
        f.write(f'      slot_phv_{hname}_{fname}[cmp_slot] <= out_{hname}_{fname};\n')
    for mf in ir.metadata_fields:
        f.write(f'      slot_meta_{mf.name}[cmp_slot] <= proc_out_meta_{mf.name};\n')
    for cnt in ctrl.counters:
        f.write(f'      slot_cnt_{cnt.name}_en[cmp_slot]  <= {cnt.name}_incr_en;\n')
        f.write(f'      slot_cnt_{cnt.name}_idx[cmp_slot] <= {cnt.name}_incr_idx;\n')
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
    f.write('  wire slot_live    = (cmp_ptr != tx_ptr);\n')
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
    f.write('  wire tx_finish    = last_loaded || discard_done;\n')
    f.write('  wire slot_release = (rel_ptr != tx_ptr) && slot_done[rel_slot];\n')

    f.write('\n')


    f.write('  always_ff @(posedge clk) begin\n')
    f.write('    if (!rst_n) begin\n')
    f.write('      tx_ptr        <= \'0;\n')
    f.write('      tx_in_payload <= 1\'b0;\n')
    f.write('      tx_hdr_row    <= \'0;\n')
    f.write('      tx_out_valid  <= 1\'b0;\n')
    f.write('      tx_out_data   <= \'0;\n')
    f.write('      tx_out_keep   <= \'0;\n')
    f.write('      tx_out_last   <= 1\'b0;\n')

    for mf in ir.metadata_fields:
        f.write(f'      out_meta_{mf.name} <= \'0;\n')
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
    f.write('      end else if (emit_pl) begin\n')
    f.write('        tx_out_valid <= 1\'b1;\n')
    f.write('        tx_out_data  <= pfifo_head_data;\n')
    f.write('        tx_out_keep  <= pfifo_head_keep;\n')
    f.write('        tx_out_last  <= pfifo_head_last;\n')
    for mf in ir.metadata_fields:
        f.write(f'        out_meta_{mf.name} <= slot_meta_{mf.name}[tx_slot];\n')
    f.write('      end\n')
    f.write('      if (tx_finish) begin\n')
    f.write('        tx_in_payload <= 1\'b0;\n')
    f.write('        tx_hdr_row    <= \'0;\n')
    f.write('        tx_ptr        <= tx_ptr + 1\'b1;\n')
    f.write('      end\n')
    f.write('    end\n')
    f.write('  end\n\n')

    # ── Counter externs (serialised at TX: commit on start, apply on finish) ──
    for cnt in ctrl.counters:
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
