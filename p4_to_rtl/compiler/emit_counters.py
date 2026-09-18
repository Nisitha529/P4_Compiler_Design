"""
emit_counters.py — Emit a standalone {CounterName}_counter.sv module per P4
`Counter<W, IdxT>(n_counters, CounterType_t.TYPE) name;` extern declaration.

Unlike `register` (whose storage lives inside processing_generated, since a
register's own action body reads its value back same-cycle), a counter is
never read back inside the apply block — .count() only raises a one-cycle
request (see emit_processing.py's `.count` case in _emit_extern_stub). So a
counter's real storage, real read-modify-write increment, and control-plane
query pipeline all live here, in their own top-level-instantiated module
(wired up by emit_top.py), rather than inside processing_generated.

Modeled on emit_table.py's _emit_exact_match_table CP-query 2-stage
accept/resolve pipeline, but simpler: read-only (no delete), no key-tag
compare (direct-indexed, not hashed), and a real 2-cycle registered
read-modify-write on the increment side (never a bare combinational
`assign` — the same asynchronous-read shape that Quartus was empirically
confirmed to reject BRAM inference for elsewhere in this project).
"""

import math


def emit_counter_module(cnt, output_path):
    """cnt: ir.CounterDecl. Writes {output_path} as a standalone SV module
    named f'{cnt.name}_counter'."""
    idx_w = max(1, math.ceil(math.log2(cnt.size))) if cnt.size > 1 else 1
    has_pkt  = cnt.counter_type in ('PACKETS', 'PACKETS_AND_BYTES')
    has_byte = cnt.counter_type in ('BYTES', 'PACKETS_AND_BYTES')
    subs = []
    if has_pkt:
        subs.append(('pkt', "64'd1"))
    if has_byte:
        # the byte length latched in stage A alongside the request
        subs.append(('byte', "{48'd0, byte_a_len}"))
    delta_expr = dict(subs)

    with open(output_path, 'w') as f:
        f.write(f'module {cnt.name}_counter #(\n')
        f.write(f'  parameter int DEPTH = {cnt.size}\n')
        f.write(') (\n')
        f.write('  input  logic clk,\n')
        f.write('  input  logic rst_n,\n\n')

        f.write('  // Increment request: ONE cycle per packet, everything valid together.\n')
        f.write('  // incr_fire pulses when the shell releases a packet\'s slot (its byte\n')
        f.write('  // length is final by then); incr_req says whether this packet\'s\n')
        f.write('  // .count() ran, incr_idx which entry. The old two-phase commit/done\n')
        f.write('  // interface held a single pending request and a 2-cycle RMW, and\n')
        f.write('  // LOST a count when releases came 2 cycles apart (measured: 33 of 34\n')
        f.write('  // back-to-back minimum packets). This path accepts one request per\n')
        f.write('  // cycle -- see the pipelined RMW below.\n')
        f.write('  input  logic              incr_fire,\n')
        f.write(f'  input  logic              incr_req,\n')
        f.write(f'  input  logic [{idx_w-1}:0] incr_idx,\n')
        if has_byte:
            f.write('  input  logic [15:0] pkt_byte_len,\n')
        f.write('\n')

        f.write('  // Control-plane query (read-only -- counters aren\'t operator-settable,\n')
        f.write('  // only queryable; no delete/write port exists).\n')
        f.write(f'  input  logic              cp_query_en,\n')
        f.write(f'  input  logic [{idx_w-1}:0] cp_query_idx,\n')
        f.write('  output logic              cp_query_busy')
        for sub, _ in subs:
            f.write(f',\n  output logic [63:0]       cp_query_{sub}_value')
        f.write('\n);\n\n')

        for sub, delta in subs:
            f.write(f'  // {sub} sub-counter: {cnt.data_width}-bit value per index, real\n')
            f.write('  // block-RAM-safe registered read-modify-write (never a bare\n')
            f.write('  // combinational `assign` read -- Quartus does not infer BRAM for that\n')
            f.write('  // shape).\n')
            f.write(f'  logic [63:0] {sub}_mem [0:DEPTH-1];\n\n')

            f.write(f'  // Power-on clear: real Cyclone IV BRAM content is unspecified at\n')
            f.write(f'  // power-up (an initial block does not reach synthesis -- see the\n')
            f.write(f'  // identical rationale for exact-match tables\' mem_valid clear FSM\n')
            f.write(f'  // in emit_table.py). Walks every address once before any real\n')
            f.write(f'  // increment or query is trusted. An increment/query issued during\n')
            f.write(f'  // this window is silently not applied that cycle -- accepted as a\n')
            f.write(f'  // low-probability startup-only edge case, same tolerance already\n')
            f.write(f'  // established for tables\' own clear FSM.\n')
            f.write(f"  logic {sub}_clearing = 1'b1;\n")
            f.write(f"  logic [{idx_w-1}:0] {sub}_clr_idx = '0;\n\n")

            # Pipelined read-modify-write, one request per cycle.
            #   stage A (issue): latch the request and issue the BRAM read
            #   stage B (apply): data is back; add; write. If the request now
            #   in A targets the SAME index B just wrote, B's read was issued
            #   on the very edge of that write and returns the stale word --
            #   forward B's new value instead. Two apart is safe: the write
            #   has landed before the later read is issued.
            f.write(f'  logic              {sub}_a_v;\n')
            f.write(f'  logic [{idx_w-1}:0] {sub}_a_idx;\n')
            if sub == 'byte':
                f.write('  logic [15:0]       byte_a_len;\n')
            f.write(f'  logic [63:0]       {sub}_mem_q;\n')
            f.write(f'  logic              {sub}_b_v;\n')
            f.write(f'  logic [{idx_w-1}:0] {sub}_b_idx;\n')
            f.write(f'  logic [63:0]       {sub}_b_new;\n')
            f.write(f'  wire  [63:0]       {sub}_cur = ({sub}_b_v && {sub}_b_idx == {sub}_a_idx) ? {sub}_b_new : {sub}_mem_q;\n')
            f.write(f'  wire  [63:0]       {sub}_nxt = {sub}_cur + {delta_expr[sub]};\n\n')
            f.write('  always_ff @(posedge clk) begin\n')
            f.write(f'    if ({sub}_clearing) begin\n')
            f.write(f"      {sub}_mem[{sub}_clr_idx] <= 64'd0;\n")
            f.write(f'      if ({sub}_clr_idx == DEPTH-1) begin\n')
            f.write(f"        {sub}_clearing <= 1'b0;\n")
            f.write('      end else begin\n')
            f.write(f"        {sub}_clr_idx <= {sub}_clr_idx + 1'b1;\n")
            f.write('      end\n')
            f.write(f"      {sub}_a_v <= 1'b0; {sub}_b_v <= 1'b0;\n")
            f.write('    end else begin\n')
            f.write('      // stage A\n')
            f.write(f'      {sub}_a_v   <= incr_fire && incr_req;\n')
            f.write(f'      {sub}_a_idx <= incr_idx;\n')
            if sub == 'byte':
                f.write('      byte_a_len  <= pkt_byte_len;\n')
            f.write(f'      {sub}_mem_q <= {sub}_mem[incr_idx];\n')
            f.write('      // stage B\n')
            f.write(f'      {sub}_b_v <= {sub}_a_v;\n')
            f.write(f'      if ({sub}_a_v) begin\n')
            f.write(f'        {sub}_mem[{sub}_a_idx] <= {sub}_nxt;\n')
            f.write(f'        {sub}_b_idx <= {sub}_a_idx;\n')
            f.write(f'        {sub}_b_new <= {sub}_nxt;\n')
            f.write('      end\n')
            f.write('    end\n')
            f.write('  end\n\n')

        # ── Control-plane query pipeline (read-only, 2-stage) ────────────────
        clearing_expr = ' || '.join(f'{sub}_clearing' for sub, _ in subs)
        f.write('  // Control-plane query, read-only: a read-only variant of exact-match\n')
        f.write('  // tables\' own CP query pipeline (emit_table.py) -- registered port-B\n')
        f.write('  // read, sticky result held until the next query, no key-tag compare\n')
        f.write('  // (direct-indexed, not hashed) and no delete branch.\n')
        f.write('  logic q_pend_valid;\n')
        f.write(f'  logic [{idx_w-1}:0] q_pend_addr;\n')
        for sub, _ in subs:
            f.write(f'  logic [63:0] q_rd_{sub};\n')
        f.write('\n  always_ff @(posedge clk) begin\n')
        f.write("    if (!rst_n) begin\n")
        f.write("      q_pend_valid <= 1'b0;\n")
        f.write(f'    end else if (cp_query_en && !q_pend_valid && !({clearing_expr})) begin\n')
        f.write("      q_pend_valid <= 1'b1;\n")
        f.write('      q_pend_addr  <= cp_query_idx;\n')
        for sub, _ in subs:
            f.write(f'      q_rd_{sub}   <= {sub}_mem[cp_query_idx];\n')
        f.write('    end else begin\n')
        f.write("      q_pend_valid <= 1'b0;\n")
        f.write('    end\n')
        f.write('  end\n')
        f.write('  assign cp_query_busy = q_pend_valid;\n\n')

        f.write('  // Sticky result: held until the next query, so a polling driver can\n')
        f.write('  // check !cp_query_busy then read at leisure, no single-cycle window.\n')
        for sub, _ in subs:
            f.write(f'  logic [63:0] q_{sub}_r;\n')
        f.write('  always_ff @(posedge clk) begin\n')
        f.write('    if (q_pend_valid) begin\n')
        for sub, _ in subs:
            f.write(f'      q_{sub}_r <= q_rd_{sub};\n')
        f.write('    end\n')
        f.write('  end\n')
        for sub, _ in subs:
            f.write(f'  assign cp_query_{sub}_value = q_{sub}_r;\n')
        f.write('\n')
        f.write('endmodule\n')
