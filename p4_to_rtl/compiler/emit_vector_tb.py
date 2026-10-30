"""emit_vector_tb.py -- generate tb_{app}_vectors.sv: a testbench that takes its
stimulus from a FILE instead of from hand-written assertions.

This is the simulation half of the pcap verification framework
(verification/framework/). The other half is a reference model driven by the
same IR the emitters use. Neither half knows anything about any particular
application:

    user's traffic (pcap)  ->  vector file  ->  THIS testbench  ->  out vector
                           \\->  reference model  ->  expected out  -> compare

Why the testbench has to be GENERATED rather than written once: the stimulus is
app-independent, but the DUT's port list is not. Every program has its own
metadata sideband, its own FeatureExport stream ports, and some have
ingress_port. A single hand-written testbench cannot bind those.

How the port list is obtained: by READING the generated {app}_top.sv and
binding its ports by name -- not by re-deriving them from the IR. emit_top.py
already decides which optional ports exist, and a second derivation here would
be a second source of truth that drifts. (That is not hypothetical: the
--self-test wrapper derived its port list separately and silently left two
INPUTS undriven for weeks; see scripts/check_selftest_ports.py.) An unrecognised
port therefore stops generation with an error naming it, instead of being left
dangling.

Files the generated testbench uses, all paths given as plusargs so one build
serves every pcap:
    +vec_in=<file>    packets to send: "<nbytes> <hex byte>..." per line
    +tbl=<file>       control-plane writes: "<word address> <hex data>" per line
    +vec_out=<file>   packets that came out, same format as vec_in
    +rec_out=<file>   FeatureExport records: "<instance> <hex value>" per line
    +meta_out=<file>  per-packet metadata sideband: "<name>=<hex> ..." per line
"""
import os
import re


class PortError(Exception):
    pass


# Ports the framework knows how to drive or observe. Anything else is refused.
_FIXED_IN = {'clk', 'rst_n',
             's_axis_tdata', 's_axis_tkeep', 's_axis_tvalid', 's_axis_tlast',
             'm_axis_tready',
             's_axil_awaddr', 's_axil_awvalid', 's_axil_wdata', 's_axil_wstrb',
             's_axil_wvalid', 's_axil_bready', 's_axil_araddr', 's_axil_arvalid',
             's_axil_rready'}
_FIXED_OUT = {'s_axis_tready', 'm_axis_tdata', 'm_axis_tkeep', 'm_axis_tvalid',
              'm_axis_tlast', 's_axil_awready', 's_axil_wready', 's_axil_bresp',
              's_axil_bvalid', 's_axil_arready', 's_axil_rdata', 's_axil_rresp',
              's_axil_rvalid'}


def _ports(top_sv, module):
    """[(dir, width, name)] for `module`'s port list, in declaration order."""
    src = open(top_sv).read()
    m = re.search(r'^module\s+' + re.escape(module) + r'\b(.*?)\n\);', src, re.S | re.M)
    if not m:
        raise PortError(f'{top_sv}: no module {module} found')
    out = []
    for line in m.group(1).splitlines():
        line = line.split('//')[0].strip().rstrip(',')
        mm = re.match(r'(input|output)\s+(?:wire|logic|reg)?\s*(\[[^\]]*\]\s*)?'
                      r'([A-Za-z_]\w*)$', line)
        if mm:
            out.append((mm.group(1), (mm.group(2) or '').strip(), mm.group(3)))
    if not out:
        raise PortError(f'{top_sv}: module {module} has no parsable ports')
    return out


def emit_vector_tb(app_name, out_dir, output_path=None):
    """Write tb_{app}_vectors.sv next to the app's other testbenches."""
    top_sv = os.path.join(out_dir, f'{app_name}_top.sv')
    if not os.path.exists(top_sv):
        raise PortError(f'{top_sv} does not exist -- generate the app first')
    ports = _ports(top_sv, f'{app_name}_top')

    ingress_port_w = None
    feeds = []          # [(name, width)] FeatureExport record streams
    meta_outs = []      # [(name, width)] metadata sideband
    for d, w, n in ports:
        if (d == 'input' and n in _FIXED_IN) or (d == 'output' and n in _FIXED_OUT):
            continue
        if n == 'ingress_port' and d == 'input':
            ingress_port_w = w or '[8:0]'
        elif n.endswith('_tready') and d == 'input':
            feeds.append((n[:-len('_tready')], None))
        elif n.endswith('_tdata') and d == 'output':
            pass
        elif n.endswith('_tvalid') and d == 'output':
            pass
        elif d == 'output' and (n.startswith('out_meta_') or n.startswith('out_std_meta_')):
            meta_outs.append((n, w))
        else:
            raise PortError(
                f'{app_name}_top port {n!r} ({d}) is not something this framework '
                f'knows how to drive or observe. Teach emit_vector_tb.py about it '
                f'rather than leaving it unconnected -- an undriven input reads as '
                f'X in simulation and is tied low by synthesis.')
    # widths for the record streams, from their own tdata ports
    wmap = {n: w for _, w, n in ports}
    feeds = [(nm, wmap.get(f'{nm}_tdata', '[31:0]')) for nm, _ in feeds]

    path = output_path or os.path.join(out_dir, 'testbench', f'tb_{app_name}_vectors.sv')
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w') as f:
        _write(f, app_name, ingress_port_w, feeds, meta_outs,
               _cp_ready_cycles(out_dir))
    return path


def _cp_ready_cycles(out_dir):
    """Cycles to wait after reset before the first control-plane write.

    Every generated match table starts with a power-on clear sweep that walks
    all DEPTH addresses, and a CP write arriving during the sweep is SILENTLY
    DROPPED (the `clearing` gate in emit_table.py's output). The table gives
    the control plane no way to ask whether it has finished, so the only thing
    a writer can do is wait out the worst case.

    Found by putting fiveTuple into the pcap framework: its table is 8192
    entries deep, this testbench waited 8 cycles, every entry it wrote was
    thrown away, and all six packets that should have matched came out
    untouched -- looking exactly like a table that does not work. The
    hand-written testbench for the same app never noticed, because by its
    first CP write several thousand cycles of earlier tests have gone by.

    It is latent for any app whose table is deeper than the lead-in, not just
    this one: load_balance's 64-deep ecmp_group sits inside that window and
    only survives because writing its first entry takes ~50 cycles.
    """
    depth = 0
    for fn in sorted(os.listdir(out_dir)):
        if not fn.endswith('_table.sv'):
            continue
        with open(os.path.join(out_dir, fn)) as fh:
            for m in re.finditer(r'parameter\s+int\s+DEPTH\s*=\s*(\d+)', fh.read()):
                depth = max(depth, int(m.group(1)))
    return depth + 32 if depth else 0


def _write(f, app, ingress_port_w, feeds, meta_outs, cp_ready_cycles=0):
    f.write(f'// tb_{app}_vectors.sv -- GENERATED by compiler/emit_vector_tb.py.\n')
    f.write('// File-driven testbench for the pcap verification framework: it makes no\n')
    f.write('// claim about what the right answer is. It sends what it is given, records\n')
    f.write('// what comes out, and the framework compares that against the reference\n')
    f.write('// model. Do not hand-edit; regenerate.\n')
    f.write('//\n')
    f.write('// Plusargs: +vec_in= +tbl= +vec_out= +rec_out= +meta_out=\n')
    f.write('`timescale 1ns/1ps\n\n')
    f.write(f'module tb_{app}_vectors;\n\n')
    f.write('  parameter  int TB_BEAT_BYTES = 32;   // overridden with -P for other widths\n')
    f.write('  localparam int TB_AXI_DATA_W = TB_BEAT_BYTES * 8;\n')
    f.write('  localparam int MAX_BYTES     = 16384;\n\n')
    f.write('  logic clk = 0;\n')
    f.write('  always #5 clk = ~clk;\n')
    f.write('  logic rst_n;\n\n')
    f.write('  logic [TB_AXI_DATA_W-1:0] s_axis_tdata;\n')
    f.write('  logic [TB_BEAT_BYTES-1:0] s_axis_tkeep;\n')
    f.write('  logic s_axis_tvalid = 0, s_axis_tready, s_axis_tlast = 0;\n')
    f.write('  logic [TB_AXI_DATA_W-1:0] m_axis_tdata;\n')
    f.write('  logic [TB_BEAT_BYTES-1:0] m_axis_tkeep;\n')
    f.write('  logic m_axis_tvalid, m_axis_tready = 1\'b1, m_axis_tlast;\n\n')
    f.write('  logic [15:0] s_axil_awaddr = 0; logic s_axil_awvalid = 0, s_axil_awready;\n')
    f.write('  logic [31:0] s_axil_wdata = 0;  logic [3:0] s_axil_wstrb = 0;\n')
    f.write('  logic s_axil_wvalid = 0, s_axil_wready; logic [1:0] s_axil_bresp;\n')
    f.write('  logic s_axil_bvalid, s_axil_bready = 1\'b1;\n')
    f.write('  logic [15:0] s_axil_araddr = 0; logic s_axil_arvalid = 0, s_axil_arready;\n')
    f.write('  logic [31:0] s_axil_rdata;  logic [1:0] s_axil_rresp;\n')
    f.write('  logic s_axil_rvalid, s_axil_rready = 1\'b1;\n\n')
    if ingress_port_w:
        f.write(f'  logic {ingress_port_w} ingress_port = \'0;   // +in_port= sets it\n\n')
    for nm, w in feeds:
        f.write(f'  logic {w} {nm}_tdata;\n  logic {nm}_tvalid;\n')
    if feeds:
        f.write('\n')
    for nm, w in meta_outs:
        f.write(f'  logic {w if w else ""} {nm};\n')
    if meta_outs:
        f.write('\n')

    f.write(f'  {app}_top dut (\n')
    f.write('    .clk(clk), .rst_n(rst_n),\n')
    f.write('    .s_axis_tdata(s_axis_tdata), .s_axis_tkeep(s_axis_tkeep),\n')
    f.write('    .s_axis_tvalid(s_axis_tvalid), .s_axis_tready(s_axis_tready),\n')
    f.write('    .s_axis_tlast(s_axis_tlast),\n')
    f.write('    .m_axis_tdata(m_axis_tdata), .m_axis_tkeep(m_axis_tkeep),\n')
    f.write('    .m_axis_tvalid(m_axis_tvalid), .m_axis_tready(m_axis_tready),\n')
    f.write('    .m_axis_tlast(m_axis_tlast),\n')
    f.write('    .s_axil_awaddr(s_axil_awaddr), .s_axil_awvalid(s_axil_awvalid),\n')
    f.write('    .s_axil_awready(s_axil_awready), .s_axil_wdata(s_axil_wdata),\n')
    f.write('    .s_axil_wstrb(s_axil_wstrb), .s_axil_wvalid(s_axil_wvalid),\n')
    f.write('    .s_axil_wready(s_axil_wready), .s_axil_bresp(s_axil_bresp),\n')
    f.write('    .s_axil_bvalid(s_axil_bvalid), .s_axil_bready(s_axil_bready),\n')
    f.write('    .s_axil_araddr(s_axil_araddr), .s_axil_arvalid(s_axil_arvalid),\n')
    f.write('    .s_axil_arready(s_axil_arready), .s_axil_rdata(s_axil_rdata),\n')
    f.write('    .s_axil_rresp(s_axil_rresp), .s_axil_rvalid(s_axil_rvalid),\n')
    f.write('    .s_axil_rready(s_axil_rready)')
    if ingress_port_w:
        f.write(',\n    .ingress_port(ingress_port)')
    for nm, _ in feeds:
        f.write(f',\n    .{nm}_tdata({nm}_tdata), .{nm}_tvalid({nm}_tvalid), '
                f'.{nm}_tready(1\'b1)')
    for nm, _ in meta_outs:
        f.write(f',\n    .{nm}({nm})')
    f.write('\n  );\n\n')

    f.write('  // ── control-plane write ─────────────────────────────────────────────────\n')
    f.write('  task automatic axil_write(input int word_addr, input logic [31:0] data);\n')
    f.write('    bit aw_done, w_done;\n')
    f.write('    @(negedge clk);\n')
    f.write('    s_axil_awaddr = word_addr * 4; s_axil_awvalid = 1\'b1;\n')
    f.write('    s_axil_wdata = data; s_axil_wstrb = 4\'hF; s_axil_wvalid = 1\'b1;\n')
    f.write('    aw_done = 0; w_done = 0;\n')
    f.write('    while (!aw_done || !w_done) begin\n')
    f.write('      @(posedge clk); #1;\n')
    f.write('      if (!aw_done && s_axil_awready) aw_done = 1;\n')
    f.write('      if (!w_done && s_axil_wready)   w_done  = 1;\n')
    f.write('    end\n')
    f.write('    @(negedge clk); s_axil_awvalid = 1\'b0; s_axil_wvalid = 1\'b0;\n')
    f.write('  endtask\n\n')

    f.write('  // ── output capture ──────────────────────────────────────────────────────\n')
    f.write('  // Sampled on the NEGEDGE, where m_axis holds the beat being PRESENTED.\n')
    f.write('  // Read just after the posedge instead, the output register has already\n')
    f.write('  // advanced and which beat a capture lands on depends on when tready rose.\n')
    f.write('  int    out_fd, rec_fd, meta_fd;\n')
    f.write('  byte   rx [0:MAX_BYTES-1];\n')
    f.write('  int    rx_n = 0;\n')
    f.write('  int    out_pkts = 0;\n')
    f.write('  always @(negedge clk) if (rst_n && m_axis_tvalid && m_axis_tready) begin\n')
    f.write('    for (int i = 0; i < TB_BEAT_BYTES; i++)\n')
    f.write('      if (m_axis_tkeep[i] && rx_n < MAX_BYTES) begin\n')
    f.write('        rx[rx_n] = m_axis_tdata[i*8 +: 8]; rx_n = rx_n + 1;\n')
    f.write('      end\n')
    f.write('    if (m_axis_tlast) begin\n')
    f.write('      $fwrite(out_fd, "%0d", rx_n);\n')
    f.write('      for (int i = 0; i < rx_n; i++) $fwrite(out_fd, " %02x", rx[i]);\n')
    f.write('      $fwrite(out_fd, "\\n");\n')
    if meta_outs:
        f.write('      if (meta_fd != 0) begin\n')
        f.write('        $fwrite(meta_fd, "pkt");\n')
        for nm, _ in meta_outs:
            f.write(f'        $fwrite(meta_fd, " {nm}=%0h", {nm});\n')
        f.write('        $fwrite(meta_fd, "\\n");\n')
        f.write('      end\n')
    f.write('      rx_n = 0; out_pkts = out_pkts + 1;\n')
    f.write('    end\n')
    f.write('  end\n\n')
    for nm, _ in feeds:
        f.write(f'  always @(negedge clk) if (rst_n && {nm}_tvalid && rec_fd != 0)\n')
        f.write(f'    $fwrite(rec_fd, "{nm} %0h\\n", {nm}_tdata);\n')
    f.write('\n')

    f.write('  // ── the run ─────────────────────────────────────────────────────────────\n')
    f.write('  string vec_in, tbl_f, vec_out_f, rec_out_f, meta_out_f;\n')
    f.write('  int    in_fd, tbl_fd, nb, got, in_port, drain;\n')
    f.write('  byte   tx [0:MAX_BYTES-1];\n')
    f.write('  int    sent = 0;\n\n')
    f.write('  task automatic send_one(input int n);\n')
    f.write('    logic [TB_AXI_DATA_W-1:0] beat;\n')
    f.write('    logic [TB_BEAT_BYTES-1:0] keep;\n')
    f.write('    int nbeats, stall;\n')
    f.write('    nbeats = (n + TB_BEAT_BYTES - 1) / TB_BEAT_BYTES;\n')
    f.write('    for (int b = 0; b < nbeats; b++) begin\n')
    f.write('      beat = \'0; keep = \'0;\n')
    f.write('      for (int i = 0; i < TB_BEAT_BYTES; i++)\n')
    f.write('        if (b*TB_BEAT_BYTES + i < n) begin\n')
    f.write('          beat[i*8 +: 8] = tx[b*TB_BEAT_BYTES + i];\n')
    f.write('          keep[i] = 1\'b1;\n')
    f.write('        end\n')
    f.write('      @(negedge clk);\n')
    f.write('      s_axis_tdata = beat; s_axis_tkeep = keep;\n')
    f.write('      s_axis_tvalid = 1\'b1; s_axis_tlast = (b == nbeats - 1);\n')
    f.write('      @(posedge clk);\n')
    f.write('      // Bounded: a wedged DUT stops retiring slots and tready never\n')
    f.write('      // returns. Unbounded, that turns a design failure into a run that\n')
    f.write('      // never ends, which a framework can only report as a timeout.\n')
    f.write('      stall = 0;\n')
    f.write('      while (!s_axis_tready && stall < 20000) begin\n')
    f.write('        @(posedge clk); stall = stall + 1;\n')
    f.write('      end\n')
    f.write('      if (stall >= 20000) begin\n')
    f.write('        $display("[VECTB-ERROR] s_axis_tready low for %0d cycles after %0d packet(s)", stall, sent);\n')
    f.write('        $fclose(out_fd); $finish;\n')
    f.write('      end\n')
    f.write('      #1;\n')
    f.write('    end\n')
    f.write('    @(negedge clk); s_axis_tvalid = 1\'b0; s_axis_tlast = 1\'b0;\n')
    f.write('    sent = sent + 1;\n')
    f.write('  endtask\n\n')
    f.write('  initial begin\n')
    f.write('    if (!$value$plusargs("vec_in=%s", vec_in))   begin $display("[VECTB-ERROR] +vec_in= missing");  $finish; end\n')
    f.write('    if (!$value$plusargs("vec_out=%s", vec_out_f)) begin $display("[VECTB-ERROR] +vec_out= missing"); $finish; end\n')
    f.write('    if (!$value$plusargs("tbl=%s", tbl_f))       tbl_f = "";\n')
    f.write('    if (!$value$plusargs("rec_out=%s", rec_out_f)) rec_out_f = "";\n')
    f.write('    if (!$value$plusargs("meta_out=%s", meta_out_f)) meta_out_f = "";\n')
    f.write('    if (!$value$plusargs("in_port=%0d", in_port)) in_port = 0;\n')
    f.write('    out_fd = $fopen(vec_out_f, "w");\n')
    # if/else rather than a ternary: Verilator will not parse $fopen inside a
    # conditional expression ("unexpected $fopen, expecting TYPE-IDENTIFIER"),
    # and this testbench is the one the coverage build runs, so it has to be
    # readable by three simulators rather than two.
    #
    # Unset means fd 0 and the write is SKIPPED -- it must never fall back to
    # the packet file. An earlier version did exactly that, so a caller that
    # omitted +rec_out=/+meta_out= got metadata lines interleaved into its
    # packet vector, which then failed to parse. The packet output is the one
    # thing this file must not corrupt.
    f.write('    rec_fd  = 0;\n')
    f.write('    meta_fd = 0;\n')
    f.write('    if (rec_out_f != "")  rec_fd  = $fopen(rec_out_f, "w");\n')
    f.write('    if (meta_out_f != "") meta_fd = $fopen(meta_out_f, "w");\n')
    f.write('    if (out_fd == 0) begin $display("[VECTB-ERROR] cannot write %0s", vec_out_f); $finish; end\n\n')
    f.write('    rst_n = 0;\n')
    f.write('    repeat (5) @(posedge clk); @(negedge clk); rst_n = 1;\n')
    f.write('    @(posedge clk); #1;\n')
    if cp_ready_cycles:
        f.write('    // Wait out every table\'s power-on clear sweep before writing a\n')
        f.write('    // single entry: a write that lands during the sweep is dropped and\n')
        f.write('    // the table then reports no hit, with nothing to say it happened.\n')
        f.write('    // The count is the deepest table plus a margin -- see\n')
        f.write('    // _cp_ready_cycles in compiler/emit_vector_tb.py.\n')
        f.write(f'    repeat ({cp_ready_cycles}) @(posedge clk);\n')
    if ingress_port_w:
        f.write('    ingress_port = in_port[$bits(ingress_port)-1:0];\n')
    f.write('\n    // control plane: "<word address> <hex data>" per line\n')
    f.write('    if (tbl_f != "") begin\n')
    f.write('      int a; logic [31:0] d;\n')
    f.write('      tbl_fd = $fopen(tbl_f, "r");\n')
    f.write('      if (tbl_fd == 0) begin $display("[VECTB-ERROR] cannot read %0s", tbl_f); $finish; end\n')
    f.write('      while ($fscanf(tbl_fd, "%d %h", a, d) == 2) axil_write(a, d);\n')
    f.write('      $fclose(tbl_fd);\n')
    f.write('      repeat (8) @(posedge clk);\n')
    f.write('    end\n\n')
    f.write('    // stimulus: "<nbytes> <hex byte>..." per line\n')
    f.write('    in_fd = $fopen(vec_in, "r");\n')
    f.write('    if (in_fd == 0) begin $display("[VECTB-ERROR] cannot read %0s", vec_in); $finish; end\n')
    f.write('    while ($fscanf(in_fd, "%d", nb) == 1) begin\n')
    f.write('      if (nb <= 0 || nb > MAX_BYTES) begin\n')
    f.write('        $display("[VECTB-ERROR] packet length %0d out of range", nb); $finish;\n')
    f.write('      end\n')
    f.write('      for (int i = 0; i < nb; i++) begin\n')
    f.write('        got = $fscanf(in_fd, "%h", tx[i]);\n')
    f.write('        if (got != 1) begin $display("[VECTB-ERROR] short packet line"); $finish; end\n')
    f.write('      end\n')
    f.write('      send_one(nb);\n')
    f.write('      repeat (4) @(posedge clk);\n')
    f.write('    end\n')
    f.write('    $fclose(in_fd);\n\n')
    f.write('    // Drain: scaled by how much was sent, so a long pcap is not cut off.\n')
    f.write('    drain = 400 + sent * 200;\n')
    f.write('    repeat (drain) @(posedge clk);\n')
    f.write('    $display("[VECTB] sent=%0d out=%0d", sent, out_pkts);\n')
    f.write('    $fclose(out_fd);\n')
    f.write('    if (rec_fd  != 0) $fclose(rec_fd);\n')
    f.write('    if (meta_fd != 0) $fclose(meta_fd);\n')
    f.write('    $finish;\n')
    f.write('  end\n\n')
    f.write('endmodule\n')
