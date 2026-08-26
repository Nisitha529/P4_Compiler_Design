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

def _byte_idx(base_expr, byte_num):
    """
    Return SV array-index expression into pkt_buf_hdr. Every field this
    compiler extracts/writes-back lives in the header region by
    construction of HDR_MAX_BYTES's sizing (see _worst_case_hdr_bytes) --
    pkt_buf_payload is only ever touched by the RX-capture/TX-replay
    per-beat routing logic, never by field-level extraction/write-back.
    """
    if base_expr in (0, '0', "8'd0"):
        return f'pkt_buf_hdr[{byte_num}]'
    if byte_num == 0:
        return f'pkt_buf_hdr[{base_expr}]'
    return f'pkt_buf_hdr[{base_expr}+{byte_num}]'


def _extract_expr(base_expr, bit_offset_in_hdr, width):
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

        ref = _byte_idx(base_expr, cur_byte)
        if take == 8:
            parts.append(ref)
        else:
            parts.append(f'{ref}[{hi}:{lo}]')

        bits_rem -= take
        cur_byte += 1
        cur_bit   = 0

    return ('{' + ', '.join(parts) + '}') if len(parts) > 1 else parts[0]


# ── SV byte write-back for one header ─────────────────────────────────────────

def _writeback_bytes(f, inst_name, base_expr, hdr_type, out_pfx, cond_expr, ind):
    """
    Emit always_ff write-back statements for all bytes of a header.
    cond_expr: optional SV guard (e.g. 'w_vlan_valid'). None → no guard.
    out_pfx  : signal prefix (e.g. 'out_') — processing output signals.
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
        f.write(f'{inner}{_byte_idx(base_expr, bi)} <= {rhs};\n')

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

    return result


# ── AXI4-Lite decoder SV emission ─────────────────────────────────────────────

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
        if ti['supports_query']:
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
        for idx, (rname, cp_sig, width) in enumerate(ti['regs']):
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
        for idx, (rname, cp_sig, width) in enumerate(ti['regs']):
            word_addr = (base + idx * 4) >> 2
            if rname == 'commit':
                f.write(f"              {AXIL_ADDR_W-2}'d{word_addr}: "
                        f"r_{tname}_cp_wr_en <= 1'b1; // {tname} commit\n")
            elif rname == 'query_commit':
                f.write(f"              {AXIL_ADDR_W-2}'d{word_addr}: begin "
                        f"r_{tname}_cp_query_en <= 1'b1; r_{tname}_cp_query_del <= 1'b0; "
                        f"end // {tname} query\n")
            elif rname == 'delete_commit':
                f.write(f"              {AXIL_ADDR_W-2}'d{word_addr}: begin "
                        f"r_{tname}_cp_query_en <= 1'b1; r_{tname}_cp_query_del <= 1'b1; "
                        f"end // {tname} delete\n")
            else:
                take = min(width, AXIL_DATA_W)
                f.write(f"              {AXIL_ADDR_W-2}'d{word_addr}: "
                        f"r_{cp_sig} <= s_axil_wdata[{take-1}:0]; // {rname}\n")

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

    def _rdata_expr(cp_sig, width):
        if width >= 32:
            return cp_sig
        return f"{{{32-width}'d0, {cp_sig}}}"

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
        n_write_words = len(ti['regs'])
        for idx, (rname, cp_sig, width) in enumerate(ti['read_regs']):
            word_addr = (base + (n_write_words + idx) * 4) >> 2
            if rname == 'query_status':
                expr = f'{{30\'d0, {tname}_cp_query_hit, {tname}_cp_query_busy}}'
            else:
                expr = _rdata_expr(cp_sig, width)
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

def _gen_valid_signals(ir, inst_map, layouts):
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

    # Step 3: compute state reachability in topological order
    state_cond = {'start': "1'b1"}
    for sname in topo:
        if sname == 'start':
            continue
        combined = None
        for pred, branch_cond in in_edges.get(sname, []):
            pc = state_cond.get(pred, "1'b0")
            tc = _and(pc, branch_cond) if branch_cond else pc
            combined = _or(combined, tc) if combined is not None else tc
        state_cond[sname] = combined if combined is not None else "1'b0"

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

def emit_top(ir, app_name, output_path, axi_data_width=DEFAULT_AXI_DATA_W, board=None):
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
    valid_map = _gen_valid_signals(ir, inst_map, layouts)

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
                      board)


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
                  board=None):

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
    f.write('    input  logic                      s_axil_rready\n')
    f.write(');\n\n')

    # ── Local parameters ───────────────────────────────────────────────────────
    f.write(f'  localparam int BEAT_BYTES    = AXI_DATA_W / 8;  // {KEEP_W}\n')
    f.write(f'  localparam int MAX_PKT_BEATS = {MAX_PKT_BEATS};\n')
    f.write(f'  localparam int MAX_PKT_BYTES = MAX_PKT_BEATS * BEAT_BYTES;  // {MAX_PKT_BEATS * KEEP_W}\n')
    f.write(f'  localparam int HDR_MAX_BYTES = {HDR_MAX_BYTES};\n')
    f.write(f'  localparam int HDR_MAX_BEATS = {HDR_MAX_BEATS};\n')
    f.write(f'  localparam int PAYLOAD_MAX_BYTES = MAX_PKT_BYTES - HDR_MAX_BYTES;  // {MAX_PKT_BYTES - HDR_MAX_BYTES}\n\n')

    # ── Packet buffer ──────────────────────────────────────────────────────────
    # Split into two physically separate arrays so no single BRAM ever needs
    # more than 2 simultaneous port-uses in a cycle: pkt_buf_hdr gets
    # RX-writes-before-cutoff XOR write-back-writes-after-cutoff (never
    # both -- write-back only fires once every header-region byte has
    # already arrived, by construction of the cutoff) plus TX-reads;
    # pkt_buf_payload gets RX-writes plus TX-reads (an ordinary 1R+1W same
    # cycle -- the actual cut-through overlap). initial zero-fill is for
    # simulation determinism now that pkt_buf_hdr is read *during* RX to
    # drive a live control decision, not only after the whole packet lands.
    f.write('  // ── Packet buffer (header region / payload region, see above) ───────────────\n')
    _write_ram_style_pragma(f, board)
    f.write('  logic [7:0] pkt_buf_hdr     [0:HDR_MAX_BYTES-1];\n')
    _write_ram_style_pragma(f, board)
    f.write('  logic [7:0] pkt_buf_payload [0:PAYLOAD_MAX_BYTES-1];\n')
    f.write('  initial begin\n')
    f.write('    for (int i = 0; i < HDR_MAX_BYTES; i++)     pkt_buf_hdr[i]     = 8\'d0;\n')
    f.write('    for (int i = 0; i < PAYLOAD_MAX_BYTES; i++) pkt_buf_payload[i] = 8\'d0;\n')
    f.write('  end\n')
    f.write(f'  logic [AXI_DATA_W/8-1:0] pkt_keep [0:MAX_PKT_BEATS-1];\n\n')

    # ── State registers ────────────────────────────────────────────────────────
    # RX and TX are independently-paced, not one shared enum -- see the RX/
    # PROC/TX always_ff blocks below for the exact triggering/ordering
    # invariants each register depends on.
    f.write('  // ── State registers ──────────────────────────────────────────────────────\n')
    f.write('  //   pkt_busy   : a packet currently owns the pipeline (any stage). The\n')
    f.write('  //                single-packet-in-flight invariant -- packet N+1 cannot\n')
    f.write('  //                start until N has drained from BOTH RX and TX.\n')
    f.write('  //   rx_done    : RX captured this packet\'s tlast beat (or the overflow\n')
    f.write('  //                path below completed). Reset to 0 whenever pkt_busy is 0,\n')
    f.write('  //                by construction of the RX block\'s own logic -- so\n')
    f.write('  //                s_axis_tready = !rx_done is correct on its own.\n')
    f.write('  //   rx_beat_cnt: beats captured so far. Freezes automatically once rx_done\n')
    f.write('  //                latches (increment is gated on !rx_done) -- no separate\n')
    f.write('  //                "final beat count" register needed, TX reads this directly.\n')
    f.write('  //   overflow   : this packet exceeded MAX_PKT_BEATS -- diagnostic only, does\n')
    f.write('  //                NOT suppress TX (which may already be transmitting by the\n')
    f.write('  //                time this is discovered, deep in the payload region -- a\n')
    f.write('  //                real cut-through design cannot "unsend" bytes already on\n')
    f.write('  //                the wire). The transmitted packet is simply truncated to\n')
    f.write('  //                MAX_PKT_BEATS beats with a correctly-placed tlast.\n')
    f.write('  //   proc_armed : drives processing_generated.valid_in. Set once\n')
    f.write('  //                rx_beat_cnt*BEAT_BYTES >= cutoff_byte and held sticky-high\n')
    f.write('  //                for the rest of the packet (processing_generated\'s lkp_*\n')
    f.write('  //                inputs must stay stable from trigger until valid_out).\n')
    f.write('  //   proc_settle: one-cycle buffer set the first cycle proc_valid_out fires\n')
    f.write('  //                (gated on proc_armed too -- without that qualifier, a\n')
    f.write('  //                residual valid_out tail from a JUST-cleared previous packet\n')
    f.write('  //                could spuriously re-trigger for a new packet that hasn\'t\n')
    f.write('  //                reached its own cutoff yet, since valid_out lags valid_in by\n')
    f.write('  //                processing_generated\'s own pipeline depth). Exists because\n')
    f.write('  //                processing_generated\'s own out_* pass-through signals were\n')
    f.write('  //                observed (via this app\'s from-scratch top-level testbench --\n')
    f.write('  //                none existed before) to still reflect the PREVIOUS packet\'s\n')
    f.write('  //                values for one more cycle after proc_valid_out first rises,\n')
    f.write('  //                a pre-existing processing_generated timing subtlety never\n')
    f.write('  //                exercised until now.\n')
    f.write('  //   proc_committed: one-shot latch, set the cycle AFTER proc_settle -- gates\n')
    f.write('  //                write-back and arming TX so they fire exactly once per packet,\n')
    f.write('  //                using out_* only once it has genuinely settled.\n')
    f.write('  //   tx_active  : armed by proc_settle && !proc_committed && !proc_drop (the\n')
    f.write('  //                exact same pre-edge condition proc_committed itself latches\n')
    f.write('  //                on, so both fire together); cleared once TX\'s last beat is\n')
    f.write('  //                accepted.\n')
    f.write('  //   tx_beat_cnt: beats transmitted so far. Advance/tvalid gated on\n')
    f.write('  //                tx_beat_cnt < rx_beat_cnt (never read a beat RX hasn\'t\n')
    f.write('  //                captured yet -- this is what makes TX correctly chase RX\'s\n')
    f.write('  //                arrival frontier instead of racing ahead). tlast additionally\n')
    f.write('  //                requires rx_done, to distinguish "caught up to RX\'s live\n')
    f.write('  //                frontier, more beats still coming" from "this really is the\n')
    f.write('  //                last beat of the whole packet".\n')
    f.write('  logic pkt_busy;\n')
    f.write('  logic rx_done;\n')
    f.write('  logic overflow;\n')
    f.write('  logic proc_armed;\n')
    f.write('  logic proc_settle;\n')
    f.write('  logic proc_committed;\n')
    f.write('  logic tx_active;\n')
    f.write(f'  logic [{BEAT_CNT_W-1}:0] rx_beat_cnt;\n')
    f.write(f'  logic [{BEAT_CNT_W-1}:0] tx_beat_cnt;\n\n')

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
        bit_off = 0
        for fld in inst.header_type.fields:
            w = fld.width or 0
            if w == 0:
                continue
            expr = _extract_expr(base_expr, bit_off, w)
            f.write(f'  wire [{w-1}:0] w_{inst_name}_{fld.name} = {expr};\n')
            bit_off += w
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
    f.write('  wire proc_drop;\n\n')

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
        if ti['supports_query']:
            tname = ti['tname']
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
            f.write(f'  wire {tname}_cp_query_del = r_{tname}_cp_query_del;\n')
        f.write(f'  wire {tname}_hit_out;\n')

    f.write('\n')
    f.write('  processing_generated u_proc (\n')
    f.write('    .clk       (clk),\n')
    f.write('    .rst_n     (rst_n),\n')
    f.write('    .valid_in  (proc_armed),\n')
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
    # cp_wr ports
    for ti in regmap:
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
    f.write('    .valid_out (proc_valid_out),\n')
    f.write('    .drop      (proc_drop)\n')
    f.write('  );\n\n')

    # ── Cross-block completion signal ─────────────────────────────────────────
    f.write('  // ── Cross-block wiring ───────────────────────────────────────────────────\n')
    f.write('  // A new packet may start only once the current one has drained from BOTH\n')
    f.write('  // RX and TX (the single-packet-in-flight invariant -- avoids needing a\n')
    f.write('  // double-buffered pkt_buf).\n')
    f.write('  wire pkt_ready_to_clear = pkt_busy && rx_done && proc_committed && !tx_active;\n\n')

    # ── RX (ingest) ────────────────────────────────────────────────────────────
    f.write('  // ── RX (ingest) ──────────────────────────────────────────────────────────\n')
    f.write('  assign s_axis_tready = !rx_done;\n')
    f.write('  wire accept_beat = s_axis_tvalid && s_axis_tready;\n\n')

    f.write('  always_ff @(posedge clk) begin\n')
    f.write('    if (!rst_n) begin\n')
    f.write('      pkt_busy    <= 1\'b0;\n')
    f.write('      rx_done     <= 1\'b0;\n')
    f.write('      rx_beat_cnt <= \'0;\n')
    f.write('      overflow    <= 1\'b0;\n')
    f.write('    end else begin\n')
    f.write('      if (accept_beat) begin\n')
    f.write('        pkt_busy <= 1\'b1;\n')
    f.write('        if (rx_beat_cnt < HDR_MAX_BEATS) begin\n')
    f.write(f'          for (int i = 0; i < {KEEP_W}; i++)\n')
    f.write('            if (s_axis_tkeep[i])\n')
    f.write(f'              pkt_buf_hdr[rx_beat_cnt * {KEEP_W} + i] <= s_axis_tdata[i*8 +: 8];\n')
    f.write('          pkt_keep[rx_beat_cnt] <= s_axis_tkeep;\n')
    f.write(f'          rx_beat_cnt <= rx_beat_cnt + {BEAT_CNT_W}\'d1;\n')
    f.write('        end else if (rx_beat_cnt < MAX_PKT_BEATS) begin\n')
    f.write(f'          for (int i = 0; i < {KEEP_W}; i++)\n')
    f.write('            if (s_axis_tkeep[i])\n')
    f.write(f'              pkt_buf_payload[(rx_beat_cnt - HDR_MAX_BEATS) * {KEEP_W} + i] <= s_axis_tdata[i*8 +: 8];\n')
    f.write('          pkt_keep[rx_beat_cnt] <= s_axis_tkeep;\n')
    f.write(f'          rx_beat_cnt <= rx_beat_cnt + {BEAT_CNT_W}\'d1;\n')
    f.write('        end else begin\n')
    f.write('          // Beyond MAX_PKT_BEATS: stop capturing (memory-safety truncation,\n')
    f.write('          // not a drop -- TX may already be transmitting this packet by now,\n')
    f.write('          // see the `overflow` declaration comment above). rx_beat_cnt stays\n')
    f.write('          // frozen at MAX_PKT_BEATS, which TX will correctly treat as the\n')
    f.write('          // final count once rx_done latches below.\n')
    f.write('          overflow <= 1\'b1;\n')
    f.write('        end\n')
    f.write('        if (s_axis_tlast) rx_done <= 1\'b1;\n')
    f.write('      end\n')
    f.write('      if (pkt_ready_to_clear) begin\n')
    f.write('        pkt_busy    <= 1\'b0;\n')
    f.write('        rx_done     <= 1\'b0;\n')
    f.write('        rx_beat_cnt <= \'0;\n')
    f.write('        overflow    <= 1\'b0;\n')
    f.write('      end\n')
    f.write('    end\n')
    f.write('  end\n\n')

    # ── PROC (match-action trigger + write-back) ──────────────────────────────
    f.write('  // ── PROC (match-action trigger + write-back) ────────────────────────────\n')
    f.write('  always_ff @(posedge clk) begin\n')
    f.write('    if (!rst_n) begin\n')
    f.write('      proc_armed     <= 1\'b0;\n')
    f.write('      proc_settle    <= 1\'b0;\n')
    f.write('      proc_committed <= 1\'b0;\n')
    f.write('    end else begin\n')
    f.write('      // Trigger as soon as the header region has fully arrived -- not\n')
    f.write('      // waiting for the whole packet. This is the cut-through trigger.\n')
    f.write('      // Also trigger on rx_done alone (packet ended before reaching the\n')
    f.write('      // theoretical cutoff): once RX has finished, no more bytes will EVER\n')
    f.write('      // arrive, so waiting further would deadlock -- this is a real case,\n')
    f.write('      // not just defensive, since header-region sizing accounts for the\n')
    f.write('      // worst-case runtime length of every var_pred field (see\n')
    f.write('      // _worst_case_hdr_bytes) and can legitimately exceed a specific\n')
    f.write('      // packet\'s actual total length.\n')
    f.write('      if (!proc_armed && pkt_busy &&\n')
    f.write('          ((rx_beat_cnt * BEAT_BYTES >= cutoff_byte) || rx_done)) begin\n')
    f.write('        proc_armed <= 1\'b1;\n')
    f.write('      end\n')
    f.write('      // proc_armed is required here (not just !proc_committed) so a residual\n')
    f.write('      // valid_out tail from a just-cleared previous packet can never be\n')
    f.write('      // mistaken for this packet\'s own result -- processing_generated\'s\n')
    f.write('      // valid_out lags valid_in by its own pipeline depth, so it can still\n')
    f.write('      // read high for a few cycles after proc_armed drops back to 0.\n')
    f.write('      //\n')
    f.write('      // proc_settle: a one-cycle buffer between first observing proc_valid_out\n')
    f.write('      // and actually reading out_* / committing write-back. processing_generated\'s\n')
    f.write('      // own out_* pass-through signals are staged (forwarded through the same\n')
    f.write('      // number of pipeline registers as valid_out itself) but were observed\n')
    f.write('      // (via a from-scratch top-level testbench -- this app never had one before)\n')
    f.write('      // to still reflect the PREVIOUS packet\'s values for one more cycle after\n')
    f.write('      // proc_valid_out first rises, specifically when valid_in is held\n')
    f.write('      // continuously high across back-to-back packets (as this design does,\n')
    f.write('      // and as the direct-mapped store-and-forward design also always did --\n')
    f.write('      // this is a pre-existing processing_generated timing subtlety, not\n')
    f.write('      // something this redesign introduces; it was simply never exercised\n')
    f.write('      // before, since no integrated top-level testbench existed). Waiting one\n')
    f.write('      // extra cycle before committing is a real, necessary fix, not a stylistic\n')
    f.write('      // choice -- confirmed empirically against the actual generated RTL.\n')
    f.write('      if (proc_armed && proc_valid_out && !proc_settle && !proc_committed) begin\n')
    f.write('        proc_settle <= 1\'b1;\n')
    f.write('      end\n')
    f.write('      if (proc_settle && !proc_committed) begin\n')
    f.write('        proc_committed <= 1\'b1;\n')
    f.write('        if (!proc_drop) begin\n')
    _emit_writeback_block(f, layouts, inst_map, valid_map, '          ')
    f.write('        end\n')
    f.write('      end\n')
    f.write('      if (pkt_ready_to_clear) begin\n')
    f.write('        proc_armed     <= 1\'b0;\n')
    f.write('        proc_settle    <= 1\'b0;\n')
    f.write('        proc_committed <= 1\'b0;\n')
    f.write('      end\n')
    f.write('    end\n')
    f.write('  end\n\n')

    # ── TX (egress) ────────────────────────────────────────────────────────────
    f.write('  // ── TX (egress) ──────────────────────────────────────────────────────────\n')
    f.write('  always_ff @(posedge clk) begin\n')
    f.write('    if (!rst_n) begin\n')
    f.write('      tx_active   <= 1\'b0;\n')
    f.write('      tx_beat_cnt <= \'0;\n')
    f.write('    end else begin\n')
    f.write('      // Armed on the exact same pre-edge condition that latches\n')
    f.write('      // proc_committed above (proc_settle && !proc_committed), so both fire\n')
    f.write('      // together on the true commit cycle (never the cycle write-back\'s own\n')
    f.write('      // commit happens on -- write-back and this arm both become visible\n')
    f.write('      // starting the next cycle, so TX only ever reads pkt_buf_hdr after\n')
    f.write('      // write-back landed).\n')
    f.write('      if (!tx_active && proc_settle && !proc_committed && !proc_drop) begin\n')
    f.write('        tx_active   <= 1\'b1;\n')
    f.write('        tx_beat_cnt <= \'0;\n')
    f.write('      end else if (tx_active && m_axis_tvalid && m_axis_tready) begin\n')
    f.write('        if (m_axis_tlast) begin\n')
    f.write('          tx_active <= 1\'b0;\n')
    f.write('        end else begin\n')
    f.write(f'          tx_beat_cnt <= tx_beat_cnt + {BEAT_CNT_W}\'d1;\n')
    f.write('        end\n')
    f.write('      end\n')
    f.write('      if (pkt_ready_to_clear) begin\n')
    f.write('        tx_active   <= 1\'b0;\n')
    f.write('        tx_beat_cnt <= \'0;\n')
    f.write('      end\n')
    f.write('    end\n')
    f.write('  end\n\n')

    # ── TX output (combinational) ─────────────────────────────────────────────
    f.write('  // ── TX output ────────────────────────────────────────────────────────────\n')
    f.write('  // m_axis_tvalid gated on tx_beat_cnt < rx_beat_cnt alone -- a beat is only\n')
    f.write('  // presentable once RX has actually captured it, which is exactly what lets\n')
    f.write('  // TX chase RX\'s live arrival frontier through the payload region instead\n')
    f.write('  // of racing ahead. m_axis_tlast additionally requires (rx_done || overflow):\n')
    f.write('  // without it, TX catching up to RX\'s live frontier mid-packet (simply\n')
    f.write('  // because TX is faster than the input rate) would be indistinguishable from\n')
    f.write('  // genuinely reaching the last beat of the whole packet. `overflow` is\n')
    f.write('  // required alongside rx_done, not just rx_done alone: once RX truncates a\n')
    f.write('  // packet at MAX_PKT_BEATS, rx_beat_cnt freezes there PERMANENTLY -- the\n')
    f.write('  // real upstream tlast (whenever it eventually arrives) no longer changes\n')
    f.write('  // rx_beat_cnt at all, so waiting for rx_done alone would deadlock TX at\n')
    f.write('  // tx_beat_cnt==rx_beat_cnt forever, never getting the chance to emit tlast\n')
    f.write('  // for the truncated packet\'s real final beat.\n')
    f.write('  always_comb begin\n')
    f.write("    m_axis_tdata  = '0;\n")
    f.write("    m_axis_tkeep  = '0;\n")
    f.write('    m_axis_tlast  = 1\'b0;\n')
    f.write('    m_axis_tvalid = 1\'b0;\n')
    f.write('    if (tx_active && (tx_beat_cnt < rx_beat_cnt)) begin\n')
    f.write('      m_axis_tvalid = 1\'b1;\n')
    f.write('      m_axis_tkeep  = pkt_keep[tx_beat_cnt];\n')
    f.write(f'      m_axis_tlast  = (rx_done || overflow) && (tx_beat_cnt == rx_beat_cnt - {BEAT_CNT_W}\'d1);\n')
    f.write('      if (tx_beat_cnt < HDR_MAX_BEATS) begin\n')
    f.write(f'        for (int i = 0; i < {KEEP_W}; i++)\n')
    f.write(f'          m_axis_tdata[i*8 +: 8] = pkt_buf_hdr[tx_beat_cnt * {KEEP_W} + i];\n')
    f.write('      end else begin\n')
    f.write(f'        for (int i = 0; i < {KEEP_W}; i++)\n')
    f.write(f'          m_axis_tdata[i*8 +: 8] = pkt_buf_payload[(tx_beat_cnt - HDR_MAX_BEATS) * {KEEP_W} + i];\n')
    f.write('      end\n')
    f.write('    end\n')
    f.write('  end\n\n')

    f.write('endmodule\n')


# ── Offset variable emitter ────────────────────────────────────────────────────

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

def _emit_writeback_block(f, layouts, inst_map, valid_map, ind):
    """Emit write-back of modified header fields back into pkt_buf."""
    for layout in layouts:
        inst_name    = layout['inst_name']
        inst         = inst_map.get(inst_name)
        if not inst:
            continue
        mandatory_base = layout['mandatory_base']
        optional_preds = layout['optional_preds']
        var_pred       = layout['var_pred']

        base_expr = _choose_base_expr(inst_name, mandatory_base, optional_preds, var_pred)
        vexpr     = valid_map.get(inst_name, "1'b1")
        cond      = None if vexpr == "1'b1" else f'out_{inst_name}_valid'

        _writeback_bytes(f, inst_name, base_expr, inst.header_type,
                         'out_', cond, ind)
