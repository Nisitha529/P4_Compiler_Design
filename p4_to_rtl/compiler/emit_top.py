"""emit_top.py — generate {app}_top.sv with AXI4-Stream + AXI4-Lite interfaces.

Architecture
============
The generated top-level module wraps parser_generated, processing_generated,
and deparser_generated with proper network-facing interfaces:

  AXI4-Stream slave  (s_axis_*)  ← incoming packet bytes
  AXI4-Stream master (m_axis_*)  → outgoing (modified) packet bytes
  AXI4-Lite slave    (s_axil_*)  → table configuration from CPU

Packet pipeline (store-and-forward):
  IDLE → RX (buffer beats into pkt_buf)
       → PROC (run match-action, then write-back modified header fields)
       → TX (replay pkt_buf over AXI4-Stream out)
       → IDLE

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

from emit_processing import (
    _find_processing_ctrl,
    _table_params,
    _table_action_ids,
    _sig as _proc_sig,
)

# ── Module-level constants ─────────────────────────────────────────────────────

AXI_DATA_W    = 64      # AXI4-Stream bus width (bits)
MAX_PKT_BEATS = 256     # max packet size in AXI4-Stream beats (256 * 8 = 2048 bytes)
AXIL_DATA_W   = 32      # AXI4-Lite data width
AXIL_ADDR_W   = 16      # AXI4-Lite address width
TABLE_AXIL_SZ = 0x100   # bytes of AXI4-Lite address space allocated per table

BEAT_BYTES = AXI_DATA_W // 8   # 8 bytes per beat
MAX_PKT_BYTES = MAX_PKT_BEATS * BEAT_BYTES  # 2048
HDR_IDX_W  = max(1, math.ceil(math.log2(MAX_PKT_BYTES + 1)))  # 11 bits


# ── Header size helpers ────────────────────────────────────────────────────────

def _hdr_bits_total(inst):
    return sum(f.width or 0 for f in inst.header_type.fields)


def _hdr_bytes_total(inst):
    return _hdr_bits_total(inst) // 8


def _is_len_field(fname):
    """True if this field carries the header's own byte-length (like IP IHL)."""
    return fname.lower() in ('hdr_len', 'ihl', 'data_offset', 'dataoffset', 'doff')


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
    """Return SV array-index expression for pkt_buf."""
    if base_expr in (0, '0', "8'd0"):
        return f'pkt_buf[{byte_num}]'
    if byte_num == 0:
        return f'pkt_buf[{base_expr}]'
    return f'pkt_buf[{base_expr}+{byte_num}]'


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
        'regs':  [(reg_name, cp_sig_name, width_bits)],  # in order; last = commit
        'idx_w': int,
        'act_w': int,
      }, ...
    ]
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

        regs = []
        regs.append(('wr_idx',    f'{tname}_cp_wr_idx',    idx_w))
        regs.append(('wr_action', f'{tname}_cp_wr_action', act_w))
        for key in tbl.keys:
            kname = _proc_sig(key.field)
            kw    = fwmap.get(kname, 32)
            regs.append((f'key_{kname}', f'{tname}_cp_wr_key_{kname}', kw))
        for pname, pw in params:
            regs.append((f'p_{pname}', f'{tname}_cp_wr_p_{pname}', pw))
        regs.append(('commit', f'{tname}_cp_wr_en', 1))   # sentinel

        result.append({
            'tname': tname,
            'base':  base,
            'regs':  regs,
            'idx_w': idx_w,
            'act_w': act_w,
        })
        base += TABLE_AXIL_SZ

    return result


# ── AXI4-Lite decoder SV emission ─────────────────────────────────────────────

def _emit_axil_decoder(f, regmap):
    """Emit AXI4-Lite staging registers and write-channel state machine."""
    if not regmap:
        return

    # Staging registers for all tables
    f.write('\n  // ── AXI4-Lite staging registers ─────────────────────────────────────────\n')
    for ti in regmap:
        tname = ti['tname']
        for rname, cp_sig, width in ti['regs']:
            if rname == 'commit':
                continue
            f.write(f'  logic [{width-1}:0] r_{cp_sig};\n')

    # cp_wr_en per-table
    for ti in regmap:
        f.write(f'  logic r_{ti["tname"]}_cp_wr_en;\n')

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
  assign s_axil_wready  = (axil_st == AXIL_WDATA);
  assign s_axil_bvalid  = (axil_st == AXIL_BRESP);
  assign s_axil_bresp   = 2\'b00;

  // AXI4-Lite read channel — tables are write-only; always acknowledge with 0
  assign s_axil_arready = 1\'b1;
  assign s_axil_rdata   = \'0;
  assign s_axil_rresp   = 2\'b00;
  assign s_axil_rvalid  = s_axil_arvalid;

''')

    f.write('  always_ff @(posedge clk) begin\n')
    f.write('    if (!rst_n) begin\n')
    f.write('      axil_st <= AXIL_IDLE;\n')
    for ti in regmap:
        f.write(f'      r_{ti["tname"]}_cp_wr_en <= 1\'b0;\n')
    f.write('    end else begin\n')
    # Default: de-assert all cp_wr_en each cycle
    for ti in regmap:
        f.write(f'      r_{ti["tname"]}_cp_wr_en <= 1\'b0;\n')
    f.write('      case (axil_st)\n')
    f.write('        AXIL_IDLE: begin\n')
    f.write('          if (s_axil_awvalid) begin\n')
    f.write('            axil_awaddr_r <= s_axil_awaddr;\n')
    f.write('            axil_st       <= AXIL_WDATA;\n')
    f.write('          end\n')
    f.write('        end\n')
    f.write('        AXIL_WDATA: begin\n')
    f.write('          if (s_axil_wvalid) begin\n')
    f.write('            case (axil_awaddr_r[AXIL_ADDR_W-1:2])  // word address\n')

    for ti in regmap:
        tname = ti['tname']
        base  = ti['base']
        for idx, (rname, cp_sig, width) in enumerate(ti['regs']):
            word_addr = (base + idx * 4) >> 2
            if rname == 'commit':
                f.write(f"              {AXIL_ADDR_W-2}'d{word_addr}: "
                        f"r_{tname}_cp_wr_en <= 1'b1; // {tname} commit\n")
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

def emit_top(ir, app_name, output_path):
    """Generate {app_name}_top.sv with AXI4-Stream and AXI4-Lite interfaces."""

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
                      emit_insts, total_hdr_bytes)


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

def _write_module(f, ir, app_name, inst_map, layouts, valid_map,
                  ctrl, amap, fwmap, regmap, emit_insts, total_hdr_bytes):

    BEAT_W     = AXI_DATA_W
    KEEP_W     = BEAT_W // 8
    BEAT_CNT_W = max(1, math.ceil(math.log2(MAX_PKT_BEATS + 1)))
    TX_BEAT_W  = BEAT_CNT_W

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
    f.write(f'  localparam int MAX_PKT_BYTES = MAX_PKT_BEATS * BEAT_BYTES;  // {MAX_PKT_BEATS * KEEP_W}\n\n')

    # ── Packet buffer ──────────────────────────────────────────────────────────
    f.write('  // ── Packet buffer ────────────────────────────────────────────────────────\n')
    f.write('  logic [7:0]                              pkt_buf  [0:MAX_PKT_BYTES-1];\n')
    f.write(f'  logic [AXI_DATA_W/8-1:0]               pkt_keep [{MAX_PKT_BEATS-1}:0];\n')
    f.write(f'  logic [{BEAT_CNT_W-1}:0]               beat_cnt;  // beats received\n')
    f.write(f'  logic [{BEAT_CNT_W-1}:0]               tx_beat;   // beat being transmitted\n\n')

    # ── State machine ──────────────────────────────────────────────────────────
    f.write('  // ── State machine ────────────────────────────────────────────────────────\n')
    f.write('  typedef enum logic [2:0] {\n')
    f.write('    ST_IDLE = 3\'d0,\n')
    f.write('    ST_RX   = 3\'d1,\n')
    f.write('    ST_PROC = 3\'d2,\n')
    f.write('    ST_TX   = 3\'d3,\n')
    f.write('    ST_DROP = 3\'d4\n')
    f.write('  } state_t;\n')
    f.write('  state_t state;\n\n')

    # ── Header field wires (extracted from pkt_buf) ────────────────────────────
    f.write('  // ── Header field extraction from pkt_buf ────────────────────────────────\n')
    f.write('  //    Fields extracted using big-endian (network byte order) bit mapping.\n\n')

    # First pass: generate offset variable declarations (ordered by dependency)
    # We need to generate offset vars BEFORE the field wires that depend on them.
    _emit_offset_vars(f, layouts, inst_map, valid_map)

    # Second pass: generate field extraction wires
    for layout in layouts:
        inst_name = layout['inst_name']
        inst      = inst_map.get(inst_name)
        if not inst:
            continue
        mandatory_base = layout['mandatory_base']
        optional_preds = layout['optional_preds']
        var_pred       = layout['var_pred']

        # Choose the base expression for this header
        base_expr = _choose_base_expr(inst_name, mandatory_base, optional_preds, var_pred)

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

    # Declare cp_wr staging regs wires (for processing instantiation)
    for ti in regmap:
        tname = ti['tname']
        for rname, cp_sig, width in ti['regs']:
            if rname == 'commit':
                f.write(f'  wire {tname}_cp_wr_en = r_{tname}_cp_wr_en;\n')
            else:
                f.write(f'  wire [{width-1}:0] {cp_sig} = r_{cp_sig};\n')
        f.write(f'  wire {tname}_hit_out;\n')

    f.write('\n')
    f.write('  processing_generated u_proc (\n')
    f.write('    .clk       (clk),\n')
    f.write('    .rst_n     (rst_n),\n')
    f.write('    .valid_in  (state == ST_PROC),\n')
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
            if rname != 'commit':
                f.write(f'    .{cp_sig} ({cp_sig}),\n')
        f.write(f'    .{tname}_hit_out  ({tname}_hit_out),\n')
    f.write('    .valid_out (proc_valid_out),\n')
    f.write('    .drop      (proc_drop)\n')
    f.write('  );\n\n')

    # ── AXI4-Lite decoder ─────────────────────────────────────────────────────
    _emit_axil_decoder(f, regmap)

    # ── RX state machine ──────────────────────────────────────────────────────
    f.write('  // ── RX / state machine ───────────────────────────────────────────────────\n')
    f.write('  assign s_axis_tready = (state == ST_IDLE) || (state == ST_RX);\n\n')

    f.write('  always_ff @(posedge clk) begin\n')
    f.write('    if (!rst_n) begin\n')
    f.write('      state    <= ST_IDLE;\n')
    f.write('      beat_cnt <= \'0;\n')
    f.write('      tx_beat  <= \'0;\n')
    f.write('    end else case (state)\n\n')

    f.write('      ST_IDLE: begin\n')
    f.write('        if (s_axis_tvalid) begin\n')
    f.write('          beat_cnt <= \'0;\n')
    f.write('          state    <= ST_RX;\n')
    f.write('        end\n')
    f.write('      end\n\n')

    f.write('      ST_RX: begin\n')
    f.write('        if (s_axis_tvalid && s_axis_tready) begin\n')
    f.write('          // Capture one beat (AXI4-Stream byte 0 = tdata[7:0])\n')
    f.write(f'          for (int i = 0; i < {KEEP_W}; i++)\n')
    f.write('            if (s_axis_tkeep[i])\n')
    f.write(f'              pkt_buf[beat_cnt * {KEEP_W} + i] <= s_axis_tdata[i*8 +: 8];\n')
    f.write('          pkt_keep[beat_cnt] <= s_axis_tkeep;\n')
    f.write(f'          beat_cnt          <= beat_cnt + {BEAT_CNT_W}\'d1;\n')
    f.write('          if (s_axis_tlast) state <= ST_PROC;\n')
    f.write('        end\n')
    f.write('      end\n\n')

    f.write('      ST_PROC: begin\n')
    f.write('        if (proc_valid_out) begin\n')
    f.write('          // Write-back modified header fields into pkt_buf\n')
    f.write('          if (!proc_drop) begin\n')
    _emit_writeback_block(f, layouts, inst_map, valid_map, '            ')
    f.write('          end\n')
    f.write('          tx_beat <= \'0;\n')
    f.write('          state   <= proc_drop ? ST_IDLE : ST_TX;\n')
    f.write('        end\n')
    f.write('      end\n\n')

    f.write('      ST_TX: begin\n')
    f.write('        if (m_axis_tvalid && m_axis_tready) begin\n')
    f.write(f'          if (tx_beat == beat_cnt - {BEAT_CNT_W}\'d1)\n')
    f.write('            state <= ST_IDLE;\n')
    f.write('          else\n')
    f.write(f'            tx_beat <= tx_beat + {BEAT_CNT_W}\'d1;\n')
    f.write('        end\n')
    f.write('      end\n\n')

    f.write('      default: state <= ST_IDLE;\n')
    f.write('    endcase\n')
    f.write('  end\n\n')

    # ── TX output logic ────────────────────────────────────────────────────────
    f.write('  // ── TX output ─────────────────────────────────────────────────────────────\n')
    f.write('  always_comb begin\n')
    f.write("    m_axis_tdata  = '0;\n")
    f.write("    m_axis_tkeep  = '0;\n")
    f.write('    m_axis_tlast  = 1\'b0;\n')
    f.write('    m_axis_tvalid = 1\'b0;\n')
    f.write('    if (state == ST_TX) begin\n')
    f.write('      m_axis_tvalid = 1\'b1;\n')
    f.write('      m_axis_tkeep  = pkt_keep[tx_beat];\n')
    f.write(f'      m_axis_tlast  = (tx_beat == beat_cnt - {BEAT_CNT_W}\'d1);\n')
    f.write(f'      for (int i = 0; i < {KEEP_W}; i++)\n')
    f.write(f'        m_axis_tdata[i*8 +: 8] = pkt_buf[tx_beat * {KEEP_W} + i];\n')
    f.write('    end\n')
    f.write('  end\n\n')

    f.write('endmodule\n')


# ── Offset variable emitter ────────────────────────────────────────────────────

def _emit_offset_vars(f, layouts, inst_map, valid_map):
    """
    Emit wire declarations for runtime-computed header byte offsets.
    Headers with only mandatory predecessors (fixed offset) need no variable.
    Headers with optional or variable predecessors get a w_{name}_base wire.
    """
    # Track which headers have already emitted an offset var
    emitted = set()

    for layout in layouts:
        inst_name    = layout['inst_name']
        mandatory_base = layout['mandatory_base']
        optional_preds = layout['optional_preds']
        var_pred       = layout['var_pred']

        if not optional_preds and var_pred is None:
            continue  # fixed offset, no var needed

        var_name = _offset_var(inst_name)
        if var_name in emitted:
            continue
        emitted.add(var_name)

        if optional_preds and var_pred is None:
            # offset = mandatory_base + sum(size if opt_valid else 0 for opt, size in optional_preds)
            terms = [str(mandatory_base)]
            for opt_name, opt_size in optional_preds:
                vexpr = valid_map.get(opt_name, "1'b0")
                terms.append(f'({vexpr} ? {opt_size} : 0)')
            expr = ' + '.join(terms)
            f.write(f'  wire [{HDR_IDX_W-1}:0] {var_name} = {expr};\n')

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
                f.write(f'  wire [{HDR_IDX_W-1}:0] {hdr_bytes_var} = '
                        f'{{{HDR_IDX_W-4}\'b0, w_{vname}_{vfield}}} << 2;\n')
            f.write(f'  wire [{HDR_IDX_W-1}:0] {var_name} = '
                    f'{prev_base_expr} + {hdr_bytes_var};\n')

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
