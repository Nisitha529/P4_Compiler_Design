"""emit_selftest.py — generate {app}_selftest_top.sv: an opt-in on-chip packet
generator + capture wrapper around the already-generated {app}_top.sv, so the
packet-processor RTL this compiler produces can be exercised on real FPGA
hardware without a real Ethernet MAC/PHY.

Deliberately a pure additive wrapper: {app}_top.sv is instantiated UNMODIFIED
(no parameter override -- its HDR_MAX_BYTES/HDR_MAX_BEATS are Python-computed
literals baked in at generation time, not re-derived from AXI_DATA_W at
elaboration, so this function must always be called with the SAME
axi_data_width value the corresponding emit_top() call used). emit_top.py
itself is never touched by this feature.

Two AXI4-Lite slave ports are exposed: the table control-plane bus is passed
straight through to {app}_top unchanged (existing table CP interface stays
externally usable exactly as today); a second, independent, smaller AXI4-Lite
slave (st_axil_*) is added for generator/capture control -- deliberately its
own bus/FSM rather than extending {app}_top's table regmap, so this feature
carries zero risk to already-verified table CP logic.

Generator model: a writable template buffer (software writes real packet
bytes via st_axil_*, same way a testbench constructs a packet), streamed out
gen_pkt_count times with an optional auto-incrementing sweep byte
(gen_vary_offset/gen_vary_enable) for parametric variation across a burst
(e.g. walk a source-port byte to hit many table entries in one run) --
protocol-agnostic in the compiler, since software controls the exact bytes.

Resource cost (real, not hidden): {app}_top.sv already owns MAX_PKT_BYTES of
packet buffering. This wrapper adds 2x MAX_PKT_BYTES more (tmpl_buf+cap_buf)
-- on-chip packet buffering roughly triples when this feature is used: 8KB->
24KB at the 256-bit default axi_data_width, 16KB->48KB at the 512-bit
ceiling. Opt-in only (--self-test on main.py).

Register map (self-test AXI4-Lite bus, word-addressed, AXI4-Lite word = 4B):
  0  gen_pkt_len       RW  bytes to send per packet
  1  gen_pkt_count     RW  packets in burst
  2  gen_vary_offset   RW  template byte offset that auto-increments per packet
  3  gen_vary_enable   RW  bit0 = enable sweep
  4  gen_ipg           RW  inter-packet gap, clock cycles
  5  gen_start         W   write-strobe (any value), effective only from idle
  6  gen_status        R   bit0=busy, bit1=done
  7  gen_sent_count    R   packets completed this burst
  8  cap_start         W   write-strobe, arms capture -- MUST be written BEFORE
                            gen_start (see cut-through note below)
  9  cap_status        R   bit0=armed/busy, bit1=done/valid
 10  cap_byte_count    R   bytes captured for the last completed packet
 11  max_pkt_bytes     R   = MAX_PKT_BYTES (capability discovery -- this value
                            changes with --axi-data-width, don't hardcode it)
 12  rec_arm           W   write-strobe: clear every FeatureExport record
                            buffer, its count and its total
     rec_info          R   {depth[31:16], words_per_entry[15:8], n_inst[7:0]}
                            -- capability discovery, same idea as word 11
 13  rec_sel           RW  which FeatureExport instance words 14/15 and the
                            record window below refer to (0..n_inst-1, in
                            declaration order: ingress instances first, then
                            egress -- the same order as <app>_top's ports and
                            the cp_map's feature_exports list)
 14  rec_count         R   records STORED for rec_sel (saturates at depth)
 15  rec_total         R   records SEEN for rec_sel since rec_arm. Greater than
                            rec_count means the buffer filled and later records
                            were not stored -- that difference IS the overflow
                            indication, so there is no separate flag.
 (words 12-15 read as 0 when the program declares no FeatureExport)
 16  gen_ingress_port  RW  the ingress_port the generator claims for every
                            packet it sends. Present only when the program
                            actually reads standard_metadata.ingress_port, in
                            which case {app}_top has a matching INPUT -- which
                            this wrapper used to leave undriven, so on hardware
                            every packet looked like it arrived on port 0 (or
                            on X in simulation) with nothing to say otherwise.
                            Defaults to 0, which is what the undriven case
                            effectively did, so no existing behaviour moves.
 17  tmpl_base_word    R   \
 18  cap_base_word     R    > the three window bases, so software (and the
 19  rec_base_word     R   /  testbenches) stop hardcoding them. They move with
                            --axi-data-width and with this map; word 11 was
                            already here for exactly this reason.
 20-31                 reserved
 16 .. 16+TMPL_WORDS-1        tmpl_buf  RW (word = 4 bytes, big-endian: a
                               32-bit write W places W[31:24] at the lowest
                               byte offset -- matches how a human hand-writing
                               a header field, e.g. a 32-bit IPv4 address, as
                               one hex literal expects it to land on the wire)
 16+TMPL_WORDS .. +CAP_WORDS-1    cap_buf  R (write ignored)
 then REC_DEPTH*REC_WORDS words        record window for rec_sel, R (write
                            ignored): entry e word w is at e*REC_WORDS + w,
                            word 0 holding the record's LOW 32 bits

FeatureExport records (p4rtl's AXI4-Stream feature ports) are captured here
because without it this wrapper could not see them at all: it instantiates
{app}_top and, before this, simply left the record ports unconnected -- which
makes <name>_tready an UNDRIVEN INPUT of the core (Vivado ties it low), so the
shell's staging FIFO filled and every record after it was counted as dropped.
On a board whose only master is JTAG-to-AXI that made the feature stream, which
is the whole product of a TCN/IDS-style program, unobservable. Now tready is
tied HIGH inside the wrapper, every record is accepted, and the first REC_DEPTH
of them per instance are readable over st_axil_*. <name>_tdata/<name>_tvalid
are also brought out as wrapper OUTPUTS for an ILA or DMA tap; there is
deliberately no tready input, because letting an outside consumer stall the
stream is exactly what the never-backpressure contract forbids.

Records are kept FIRST-N, not last-N (a full buffer stops storing rather than
overwriting): the interesting records in a bring-up burst are the early ones,
and rec_total still reports everything that happened.

Real, demonstrable ordering requirement (not just a caveat): {app}_top.sv's
cut-through datapath can start m_axis output before s_axis input finishes, so
cap_start must be issued before gen_start -- otherwise capture can arm
mid-packet and record a truncated/misaligned suffix.

Only meaningful for the p4test/XSA frontend (only that frontend produces a
{app}_top.sv to wrap). Getting a real bus master (Vivado's JTAG-to-AXI-Master
IP, or the Quartus/System-Console equivalent) onto the board to actually
drive st_axil_*/s_axil_* is a separate board-integration step, out of scope
for this compiler.
"""
import math

from emit_top import (DEFAULT_AXI_DATA_W, MAX_AXI_DATA_W, MAX_PKT_BEATS,
                       AXIL_ADDR_W, AXIL_DATA_W)
from emit_table import _find_processing_ctrl
from emit_top import _collect_std_meta_inputs, _collect_std_meta_outputs

CTRL_WORDS = 32   # bytes 0x00-0x7C
# Records held per FeatureExport instance. Deliberately small: this is a
# bring-up window, not a data path -- a real consumer attaches to the
# <name>_t* stream ports (or, off-chip, to a DMA behind them). 32 entries of
# at most 2 words is ~2 Kbit per instance, so it stays in registers and never
# competes with the packet buffers for BRAM.
REC_DEPTH  = 32


def emit_selftest_top(ir, app_name, output_path, axi_data_width=DEFAULT_AXI_DATA_W):
    """Generate {app_name}_selftest_top.sv.

    ir: read ONLY for the program's FeatureExport declarations (record capture
        below). The packet datapath part of this wrapper stays
        protocol-agnostic by construction -- the whole point of the
        writable-template design.
    axi_data_width: MUST match the axi_data_width the corresponding emit_top()
        call for this app used (see module docstring). Re-validated here
        (not just in main.py's CLI parsing) since this function can be called
        directly/programmatically, not only via the CLI -- same dual-
        validation precedent as emit_top()'s own axi_data_width parameter.
    """
    if axi_data_width < 8 or (axi_data_width & (axi_data_width - 1)) != 0:
        raise ValueError(
            f'axi_data_width must be a power of 2, >=8 (got {axi_data_width})'
        )
    if axi_data_width > MAX_AXI_DATA_W:
        raise ValueError(
            f'axi_data_width={axi_data_width} exceeds MAX_AXI_DATA_W='
            f'{MAX_AXI_DATA_W} -- see emit_top.py for the ceiling\'s rationale'
        )

    beat_bytes    = axi_data_width // 8
    if beat_bytes < 4:
        raise ValueError(
            f'--self-test requires axi_data_width >= 32 (KEEP_W >= 4 bytes): the '
            f'template/capture buffers are stored as KEEP_W-byte BRAM rows so a '
            f'4-byte AXI4-Lite word write/read can never cross a row boundary -- '
            f'got axi_data_width={axi_data_width}. This is a real, not arbitrary, '
            f'restriction (found necessary when fixing a real Quartus ALUT-explosion '
            f'bug from these buffers failing BRAM inference); narrower widths were '
            f'never exercised by any app/testbench in this project anyway.'
        )
    max_pkt_bytes = MAX_PKT_BEATS * beat_bytes
    pktlen_w      = max(1, math.ceil(math.log2(max_pkt_bytes + 1)))
    vary_w        = max(1, math.ceil(math.log2(max_pkt_bytes)))

    tmpl_words       = max_pkt_bytes // 4
    tmpl_base_word   = CTRL_WORDS
    cap_base_word    = tmpl_base_word + tmpl_words
    cap_words        = max_pkt_bytes // 4
    rec_base_word    = cap_base_word + cap_words

    # FeatureExport instances, in the SAME order emit_top.py lays out its
    # ports (ingress control first, then egress) -- that order is the
    # instance index software selects with rec_sel, and the cp_map lists the
    # instances in it too, so the three cannot drift.
    _ctrl  = _find_processing_ctrl(ir)
    _ectrl = getattr(getattr(ir, 'pipeline', None), 'egress', None)
    if _ectrl is not None and not (_ectrl.tables or _ectrl.statements):
        _ectrl = None
    fe_all = list(getattr(_ctrl, 'feature_exports', []) or []) if _ctrl else []
    if _ectrl is not None:
        fe_all += list(getattr(_ectrl, 'feature_exports', []) or [])

    # Does {app}_top have an ingress_port INPUT? Composed exactly as
    # emit_top.py composes shell_std_used (see its `shell_std_used =` line):
    # inputs the ingress control reads, plus the ones egress reads that
    # ingress does not itself produce. Same helpers, so the two cannot drift
    # in how a field is detected -- and scripts/check_selftest_ports.py
    # checks the RESULT structurally, which is what actually guarantees every
    # core input ends up driven.
    _std_ins = dict(_collect_std_meta_inputs(_ctrl)) if _ctrl else {}
    if _ectrl is not None:
        _ig_outs = _collect_std_meta_outputs(_ctrl)
        for _k, _w in _collect_std_meta_inputs(_ectrl).items():
            if _k not in _ig_outs:
                _std_ins[_k] = _w
    ingress_port_w = _std_ins.get('ingress_port')

    # One uniform entry geometry for every instance, sized from the WIDEST
    # record: a per-instance stride would make the address decode depend on
    # which instance is selected, for no gain -- these buffers are tiny.
    rec_words = max((((fe.padded_width + 31) // 32) for fe in fe_all), default=0)
    rec_depth = REC_DEPTH if fe_all else 0
    rec_span  = rec_depth * rec_words
    addr_span_words  = rec_base_word + rec_span

    # Real-BRAM row storage: each row is exactly one KEEP_W-byte AXI4-Stream
    # beat wide (ROW_BYTES==KEEP_W -- see the module docstring's "full BRAM
    # reorganization" note for why: a byte array accessed at KEEP_W independent
    # lane addresses per cycle, as this used to be, cannot map onto real block
    # RAM -- Quartus fell back to per-index combinational logic, the actual
    # cause of a measured 2M+ ALUT explosion on real hardware). tmpl_rows ==
    # MAX_PKT_BEATS by construction (max_pkt_bytes is exactly MAX_PKT_BEATS
    # beat_bytes-sized beats). words_per_row/wpr_shift describe how many
    # 4-byte AXI4-Lite words fit in one row, for the CP read/write address
    # translation (word_idx -> row, word-within-row).
    tmpl_rows     = max_pkt_bytes // beat_bytes
    words_per_row = beat_bytes // 4
    wpr_shift     = int(math.log2(words_per_row))

    with open(output_path, 'w') as f:
        f.write(f'// {app_name}_selftest_top.sv -- opt-in on-chip packet generator + capture\n')
        f.write(f'// wrapper around {app_name}_top.sv (generated by --self-test). See\n')
        f.write('// compiler/emit_selftest.py for the full design rationale and register map.\n')
        f.write(f'// axi_data_width={axi_data_width} (MUST match the {app_name}_top.sv this wraps)\n\n')

        _write_module(f, app_name, axi_data_width, beat_bytes, max_pkt_bytes,
                      pktlen_w, vary_w, tmpl_words, tmpl_base_word,
                      cap_base_word, cap_words, addr_span_words,
                      tmpl_rows, words_per_row, wpr_shift,
                      fe_all, rec_base_word, rec_depth, rec_words, rec_span,
                      ingress_port_w)


def _write_module(f, app_name, axi_data_width, beat_bytes, max_pkt_bytes,
                   pktlen_w, vary_w, tmpl_words, tmpl_base_word,
                   cap_base_word, cap_words, addr_span_words,
                   tmpl_rows, words_per_row, wpr_shift,
                   fe_all, rec_base_word, rec_depth, rec_words, rec_span,
                   ingress_port_w):

    # ── Module header ────────────────────────────────────────────────────────
    f.write(f'module {app_name}_selftest_top #(\n')
    f.write(f'    parameter int AXI_DATA_W     = {axi_data_width},\n')
    f.write(f'    parameter int AXIL_ADDR_W    = {AXIL_ADDR_W},\n')
    f.write(f'    parameter int ST_AXIL_ADDR_W = {AXIL_ADDR_W}\n')
    f.write(') (\n')
    f.write('    input  logic clk,\n')
    f.write('    input  logic rst_n,\n')
    f.write('\n    // Table control-plane AXI4-Lite -- passthrough to {app}_top, unchanged\n'.replace('{app}', app_name))
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
    f.write('    input  logic                      s_axil_rready,\n')
    f.write('\n    // Self-test AXI4-Lite -- generator/capture control (see register map above)\n')
    f.write('    input  logic [ST_AXIL_ADDR_W-1:0] st_axil_awaddr,\n')
    f.write('    input  logic                       st_axil_awvalid,\n')
    f.write('    output logic                       st_axil_awready,\n')
    f.write('    input  logic [31:0]                st_axil_wdata,\n')
    f.write('    input  logic [3:0]                 st_axil_wstrb,\n')
    f.write('    input  logic                       st_axil_wvalid,\n')
    f.write('    output logic                       st_axil_wready,\n')
    f.write('    output logic [1:0]                 st_axil_bresp,\n')
    f.write('    output logic                       st_axil_bvalid,\n')
    f.write('    input  logic                       st_axil_bready,\n')
    f.write('    input  logic [ST_AXIL_ADDR_W-1:0] st_axil_araddr,\n')
    f.write('    input  logic                       st_axil_arvalid,\n')
    f.write('    output logic                       st_axil_arready,\n')
    f.write('    output logic [31:0]                st_axil_rdata,\n')
    f.write('    output logic [1:0]                 st_axil_rresp,\n')
    f.write('    output logic                       st_axil_rvalid,\n')
    if fe_all:
        f.write('    input  logic                       st_axil_rready,\n')
        f.write('\n    // FeatureExport record streams, brought out for an ILA/DMA tap.\n')
        f.write('    // OUTPUTS ONLY, on purpose: there is no tready input, because an\n')
        f.write('    // outside consumer stalling this stream is what the never-\n')
        f.write('    // backpressure contract forbids. tready is tied high below and the\n')
        f.write('    // supported readback path is the record window on st_axil_*.\n')
        for i, fe in enumerate(fe_all):
            comma = ',' if i < len(fe_all) - 1 else ''
            f.write(f'    output logic [{fe.padded_width-1}:0] {fe.name}_tdata,\n')
            f.write(f'    output logic {fe.name}_tvalid{comma}\n')
    else:
        f.write('    input  logic                       st_axil_rready\n')
    f.write(');\n\n')

    f.write('  localparam int KEEP_W        = AXI_DATA_W / 8;  // {}\n'.format(beat_bytes))
    f.write(f'  localparam int MAX_PKT_BYTES = {MAX_PKT_BEATS} * KEEP_W;  // {max_pkt_bytes}\n')
    f.write(f'  localparam int TMPL_BASE_WORD  = {tmpl_base_word};\n')
    f.write(f'  localparam int CAP_BASE_WORD   = {cap_base_word};\n')
    f.write(f'  localparam int ADDR_SPAN_WORDS = {addr_span_words};\n')
    f.write(f'  localparam int TMPL_ROWS     = {tmpl_rows};  // == MAX_PKT_BEATS; one row per beat\n')
    f.write(f'  localparam int CAP_ROWS      = TMPL_ROWS;\n')
    f.write(f'  localparam int WORDS_PER_ROW = {words_per_row};  // KEEP_W/4\n')
    if fe_all:
        f.write(f'  localparam int REC_BASE_WORD = {rec_base_word};\n')
        f.write(f'  localparam int REC_DEPTH     = {rec_depth};   // records kept per instance\n')
        f.write(f'  localparam int REC_WORDS     = {rec_words};   // 32-bit words per record\n')
        f.write(f'  localparam int REC_NINST     = {len(fe_all)};\n')
    f.write('\n')

    # ── Template / capture buffers ──────────────────────────────────────────
    # Real-BRAM row storage (see module docstring's "full BRAM reorganization"
    # note): each row is exactly one KEEP_W-byte beat wide. tmpl_buf needs 3
    # logically-independent accessors -- CP write, CP read, and the
    # generator/vary-sweep read (st_axil_st and st_axil_rst below are
    # independent AXI4-Lite write/read state machines, so a CP write-accept
    # and a CP read-issue can genuinely coincide on the same cycle) -- one
    # more than a single BRAM's 2-port ceiling, so it's physically MIRRORED
    # into two identical copies, both driven by the SAME CP-write
    # enable/address/data every cycle so they can never diverge:
    # tmpl_word_cp pairs with the CP's own read (1R+1W), tmpl_word_gen pairs
    # with the generator/vary read (also 1R+1W -- safe to share one port
    # since those two reads are the same FSM and provably never overlap: the
    # vary-sweep read always completes strictly before the first per-beat
    # read is even issued). cap_buf only ever needs 2 accessors (capture-FSM
    # write, CP read), so cap_word needs no mirroring.
    f.write('  // Template buffer (software-written packet content, read+write over\n')
    f.write('  // st_axil_*) and capture buffer (written only by the capture FSM below,\n')
    f.write('  // read over st_axil_*). Real BRAM cost -- see this file\'s module docstring.\n')
    f.write('  // tmpl_buf is MIRRORED (tmpl_word_cp/tmpl_word_gen) because it has 3\n')
    f.write('  // independent concurrent accessors (CP write, CP read, generator/vary\n')
    f.write('  // read) -- one more than a single BRAM\'s 2-port ceiling; both copies are\n')
    f.write('  // always written identically so they can never diverge. cap_buf only\n')
    f.write('  // ever has 2 accessors (capture-FSM write, CP read), no mirroring needed.\n')
    f.write('  // PACKED byte dimension ([KEEP_W-1:0][7:0], not a fully-unpacked 2D array) --\n')
    f.write('  // this specific shape is what Quartus\'s byte-enable RAM inference template\n')
    f.write('  // actually matches (Intel\'s "Recommended HDL Coding Styles" doc, Example\n')
    f.write('  // 12-26) -- a fully-unpacked `[0:N-1][0:M-1]` array is syntactically valid\n')
    f.write('  // but is never even ATTEMPTED for RAM inference by real Quartus.\n')
    f.write('  logic [KEEP_W-1:0][7:0] tmpl_word_cp  [0:TMPL_ROWS-1];\n')
    f.write('  logic [KEEP_W-1:0][7:0] tmpl_word_gen [0:TMPL_ROWS-1];\n')
    f.write('  logic [KEEP_W-1:0][7:0] cap_word      [0:CAP_ROWS-1];\n')
    # Simulation-only zero-fill, excluded from synthesis: real hardware needs
    # no reset value here (tmpl_buf is written by software before use,
    # cap_buf by the capture FSM before being read) -- this exists purely
    # for simulation determinism. Required, not cosmetic: a real Quartus
    # synthesis run of this file hit "Loop error... must terminate within
    # 5000 iterations" at MAX_PKT_BYTES=8192 -- Quartus caps procedural
    # for-loop unrolling in initial blocks, and this loop (correctly)
    # exceeds that for any real packet-size buffer.
    #
    # `ifndef SYNTHESIS alone did NOT resolve this on real Quartus (found
    # empirically -- the loop error persisted, meaning Quartus's Analysis &
    # Synthesis does not reliably predefine SYNTHESIS, contrary to the
    # first attempt's assumption) -- switched to `// synthesis
    # translate_off` / `// synthesis translate_on`, a much older,
    # comment-based directive (not a preprocessor macro, so it can't
    # silently fail to apply the way an undefined `ifdef would) that every
    # major FPGA synthesis tool, Quartus and Vivado both, recognizes
    # natively as "skip this block during synthesis." Kept alongside the
    # `ifndef SYNTHESIS guard (harmless, may help other future toolchains)
    # rather than removed, but translate_off/on is now the real, load-
    # bearing mechanism.
    f.write('  `ifndef SYNTHESIS\n')
    f.write('  // synthesis translate_off\n')
    f.write('  initial begin\n')
    f.write('    for (int i = 0; i < TMPL_ROWS; i++) tmpl_word_cp[i]  = \'0;\n')
    f.write('    for (int i = 0; i < TMPL_ROWS; i++) tmpl_word_gen[i] = \'0;\n')
    f.write('    for (int i = 0; i < CAP_ROWS; i++)  cap_word[i]      = \'0;\n')
    f.write('  end\n')
    f.write('  // synthesis translate_on\n')
    f.write('  `endif\n\n')

    # ── Core instantiation ───────────────────────────────────────────────────
    f.write(f'  logic [AXI_DATA_W-1:0] gen_axis_tdata;\n')
    f.write(f'  logic [KEEP_W-1:0]     gen_axis_tkeep;\n')
    f.write('  logic                   gen_axis_tvalid, gen_axis_tready, gen_axis_tlast;\n\n')
    f.write(f'  logic [AXI_DATA_W-1:0] cap_axis_tdata;\n')
    f.write(f'  logic [KEEP_W-1:0]     cap_axis_tkeep;\n')
    f.write('  logic                   cap_axis_tvalid, cap_axis_tlast;\n\n')

    f.write(f'  {app_name}_top u_core (\n')
    f.write('    .clk(clk), .rst_n(rst_n),\n')
    f.write('    .s_axis_tdata(gen_axis_tdata), .s_axis_tkeep(gen_axis_tkeep),\n')
    f.write('    .s_axis_tvalid(gen_axis_tvalid), .s_axis_tready(gen_axis_tready), .s_axis_tlast(gen_axis_tlast),\n')
    f.write('    .m_axis_tdata(cap_axis_tdata), .m_axis_tkeep(cap_axis_tkeep),\n')
    f.write("    .m_axis_tvalid(cap_axis_tvalid), .m_axis_tready(1'b1), .m_axis_tlast(cap_axis_tlast),\n")
    f.write('    .s_axil_awaddr(s_axil_awaddr), .s_axil_awvalid(s_axil_awvalid), .s_axil_awready(s_axil_awready),\n')
    f.write('    .s_axil_wdata(s_axil_wdata), .s_axil_wstrb(s_axil_wstrb), .s_axil_wvalid(s_axil_wvalid), .s_axil_wready(s_axil_wready),\n')
    f.write('    .s_axil_bresp(s_axil_bresp), .s_axil_bvalid(s_axil_bvalid), .s_axil_bready(s_axil_bready),\n')
    f.write('    .s_axil_araddr(s_axil_araddr), .s_axil_arvalid(s_axil_arvalid), .s_axil_arready(s_axil_arready),\n')
    f.write('    .s_axil_rdata(s_axil_rdata), .s_axil_rresp(s_axil_rresp), .s_axil_rvalid(s_axil_rvalid), .s_axil_rready(s_axil_rready)')
    if ingress_port_w:
        f.write(',\n')
        f.write('    // Driven from a register, not left dangling: an undriven input reads as\n')
        f.write('    // X in simulation and is tied low by synthesis, so the program would see\n')
        f.write('    // every packet arrive on port 0 with nothing saying so.\n')
        f.write('    .ingress_port(gen_ingress_port_reg)')
    if fe_all:
        f.write(',\n')
        f.write('    // tready tied HIGH: the record capture below never backpressures the\n')
        f.write('    // core, which is the contract these ports are built on. Leaving them\n')
        f.write('    // unconnected (as this wrapper did before) makes tready an undriven\n')
        f.write('    // INPUT -- tied low by synthesis -- so the staging FIFO fills and every\n')
        f.write('    // record after it is counted as dropped.\n')
        for i, fe in enumerate(fe_all):
            comma = ',' if i < len(fe_all) - 1 else ''
            f.write(f'    .{fe.name}_tdata({fe.name}_tdata), .{fe.name}_tvalid({fe.name}_tvalid), '
                    f'.{fe.name}_tready(1\'b1){comma}\n')
    else:
        f.write('\n')
    f.write('  );\n\n')

    if ingress_port_w:
        f.write(f'  logic [{ingress_port_w-1}:0] gen_ingress_port_reg;\n\n')

    # Bare (no-initializer) staging-register declarations hoisted here,
    # BEFORE _write_generator -- its own logic references gen_pkt_len_reg/
    # etc. by name, but those are only ever DECLARED inside
    # _write_axil_decoder (which runs after it, since it also needs
    # gen_busy/cap_busy/etc. from the generator/capture blocks). Vivado's
    # xvlog (unlike iverilog) rejects referencing a signal before its own
    # declaration -- same cross-toolchain forward-reference class already
    # found and fixed in emit_top.py.
    f.write(f'  logic [{pktlen_w-1}:0] gen_pkt_len_reg;\n')
    f.write("  logic [31:0] gen_pkt_count_reg;\n")
    f.write(f'  logic [{vary_w-1}:0] gen_vary_offset_reg;\n')
    f.write('  logic gen_vary_enable_reg;\n')
    f.write("  logic [31:0] gen_ipg_reg;\n\n")

    _write_generator(f, pktlen_w, vary_w, beat_bytes)
    _write_capture(f, beat_bytes)
    _write_record_capture(f, fe_all, rec_depth, rec_words)
    _write_axil_decoder(f, pktlen_w, vary_w, tmpl_base_word, cap_base_word, addr_span_words,
                        max_pkt_bytes, words_per_row, wpr_shift,
                        fe_all, rec_base_word, rec_depth, rec_words, ingress_port_w)

    f.write('endmodule\n')


def _write_generator(f, pktlen_w, vary_w, beat_bytes):
    keep_w_shift = int(math.log2(beat_bytes))  # ROW_BYTES==KEEP_W -- see docstring

    f.write('  // ── Packet generator ─────────────────────────────────────────────────────\n')
    f.write('  // tmpl_word_gen is real BRAM now (1-cycle registered read: an address held\n')
    f.write('  // during cycle T produces data at cycle T+1, unconditionally, every cycle --\n')
    f.write('  // see gen_rd_addr/gen_rd_data below). The invariant this whole FSM maintains\n')
    f.write('  // is "gen_rd_addr == beat_idx+1" throughout GEN_SEND (gen_rd_addr always one\n')
    f.write('  // beat AHEAD of what is currently being presented) -- both the initial priming\n')
    f.write('  // (GEN_VARY_WAIT/GEN_VARY_EXTRACT/GEN_PRIME_NEXT) and the steady-state advance\n')
    f.write('  // (self-incrementing gen_rd_addr, NOT deriving it from beat_idx -- deriving it\n')
    f.write('  // from beat_idx in the SAME cycle beat_idx itself advances makes them equal\n')
    f.write('  // instead of one-ahead, landing data exactly one cycle late) exist only to\n')
    f.write('  // establish and preserve that invariant. GEN_PRIME_NEXT is shared by burst\n')
    f.write('  // start (after GEN_VARY_EXTRACT) and every inter-packet transition (after\n')
    f.write('  // GEN_GAP, or directly from GEN_SEND\'s own tlast branch when IPG==0) -- both\n')
    f.write('  // cases need the identical "advance gen_rd_addr from beat 0\'s already-primed\n')
    f.write('  // row to beat 1\'s" step immediately before GEN_SEND. IPG==0 back-to-back\n')
    f.write('  // packets therefore always pay a minimum 1-cycle gap now (unavoidable real\n')
    f.write('  // BRAM latency) -- fine, T5\'s check is gap>=gen_ipg, satisfied trivially at\n')
    f.write('  // gen_ipg==0 by any nonnegative gap.\n')
    f.write('  typedef enum logic [2:0] {\n')
    f.write("    GEN_IDLE        = 3'd0,\n")
    f.write("    GEN_VARY_WAIT   = 3'd1,\n")
    f.write("    GEN_VARY_EXTRACT = 3'd2,\n")
    f.write("    GEN_PRIME_NEXT  = 3'd3,\n")
    f.write("    GEN_SEND        = 3'd4,\n")
    f.write("    GEN_GAP         = 3'd5\n")
    f.write('  } gen_st_t;\n')
    f.write('  gen_st_t gen_st;\n\n')

    f.write(f'  logic [{pktlen_w-1}:0] pkt_len_r;\n')
    f.write('  logic [31:0] pkt_count_r;\n')
    f.write(f'  logic [{vary_w-1}:0] vary_offset_r;\n')
    f.write('  logic vary_enable_r;\n')
    f.write('  logic [31:0] ipg_r;\n\n')

    f.write('  logic [31:0] pkt_idx, sent_count, ipg_cnt;\n')
    f.write("  logic [8:0]  beat_idx;  // holds 0..256 (MAX_PKT_BEATS)\n")
    f.write('  logic [7:0]  vary_val;\n')
    f.write('  logic        gen_busy, gen_done;\n\n')

    f.write('  // Real-BRAM prefetch: gen_rd_addr is the row about to be fetched (issued one\n')
    f.write('  // cycle ahead of when gen_rd_data needs to hold it), unconditional every\n')
    f.write('  // cycle -- the FSM below only ever controls WHEN gen_rd_addr changes.\n')
    f.write('  // Backpressure is free: when gen_axis_tready==0, gen_rd_addr simply isn\'t\n')
    f.write('  // rewritten, so the already-prefetched row holds steady.\n')
    f.write('  logic [8:0] gen_rd_addr;\n')
    f.write('  logic [AXI_DATA_W-1:0] gen_rd_data;\n')
    f.write('  always_ff @(posedge clk) gen_rd_data <= tmpl_word_gen[gen_rd_addr];\n\n')

    f.write('  logic [31:0] gen_nbeats_c;\n')
    f.write('  assign gen_nbeats_c = (pkt_len_r + KEEP_W - 1) / KEEP_W;\n')
    f.write('  assign gen_axis_tvalid = (gen_st == GEN_SEND);\n')
    f.write("  assign gen_axis_tlast  = (gen_st == GEN_SEND) && (beat_idx == gen_nbeats_c - 1);\n\n")

    f.write('  always @(*) begin\n')
    f.write('    for (int i = 0; i < KEEP_W; i = i + 1) begin\n')
    f.write('      if ((beat_idx * KEEP_W + i) < pkt_len_r) begin\n')
    f.write("        gen_axis_tkeep[i] = 1'b1;\n")
    f.write('        if (vary_enable_r && ((beat_idx * KEEP_W + i) == vary_offset_r))\n')
    f.write('          gen_axis_tdata[i*8 +: 8] = vary_val;\n')
    f.write('        else\n')
    f.write('          gen_axis_tdata[i*8 +: 8] = gen_rd_data[i*8 +: 8];\n')
    f.write('      end else begin\n')
    f.write("        gen_axis_tkeep[i] = 1'b0;\n")
    f.write("        gen_axis_tdata[i*8 +: 8] = 8'h00;\n")
    f.write('      end\n')
    f.write('    end\n')
    f.write('  end\n\n')

    f.write('  logic r_gen_start;  // one-cycle strobe, set by the self-test AXIL decoder below\n\n')

    f.write('  always_ff @(posedge clk) begin\n')
    f.write('    if (!rst_n) begin\n')
    f.write('      gen_st      <= GEN_IDLE;\n')
    f.write("      gen_busy    <= 1'b0;\n")
    f.write("      gen_done    <= 1'b0;\n")
    f.write("      pkt_len_r     <= '0;\n")
    f.write("      pkt_count_r   <= 32'd0;\n")
    f.write("      vary_offset_r <= '0;\n")
    f.write("      vary_enable_r <= 1'b0;\n")
    f.write("      ipg_r         <= 32'd0;\n")
    f.write("      pkt_idx     <= 32'd0;\n")
    f.write("      sent_count  <= 32'd0;\n")
    f.write("      beat_idx    <= '0;\n")
    f.write("      vary_val    <= 8'd0;\n")
    f.write("      ipg_cnt     <= 32'd0;\n")
    f.write("      gen_rd_addr <= '0;\n")
    f.write('    end else begin\n')
    f.write('      case (gen_st)\n')
    f.write('        GEN_IDLE: begin\n')
    f.write('          if (r_gen_start) begin\n')
    f.write(f'            pkt_len_r     <= (gen_pkt_len_reg > MAX_PKT_BYTES) ? {pktlen_w}\'(MAX_PKT_BYTES) : gen_pkt_len_reg;\n')
    f.write('            pkt_count_r   <= gen_pkt_count_reg;\n')
    f.write('            vary_offset_r <= gen_vary_offset_reg;\n')
    f.write('            vary_enable_r <= gen_vary_enable_reg;\n')
    f.write('            ipg_r         <= gen_ipg_reg;\n')
    f.write("            pkt_idx       <= 32'd0;\n")
    f.write("            beat_idx      <= '0;\n")
    f.write("            sent_count    <= 32'd0;\n")
    f.write("            gen_done      <= 1'b0;\n")
    f.write("            if (gen_pkt_count_reg == 32'd0 || gen_pkt_len_reg == '0) begin\n")
    f.write("              gen_busy <= 1'b0;\n")
    f.write("              gen_done <= 1'b1;\n")
    f.write('            end else begin\n')
    f.write("              gen_busy    <= 1'b1;\n")
    f.write(f'              gen_rd_addr <= 9\'(gen_vary_offset_reg[{vary_w-1}:{keep_w_shift}]);\n')
    f.write('              gen_st      <= GEN_VARY_WAIT;\n')
    f.write('            end\n')
    f.write('          end\n')
    f.write('        end\n')
    f.write('        GEN_VARY_WAIT: begin\n')
    f.write('          // Pure wait: gen_rd_data does NOT yet hold the vary-offset\'s row here\n')
    f.write('          // (the read using the address set in GEN_IDLE only lands at the START\n')
    f.write('          // of the NEXT cycle) -- must not touch gen_rd_addr this cycle, or the\n')
    f.write('          // in-flight fetch is lost before it ever lands.\n')
    f.write('          gen_st <= GEN_VARY_EXTRACT;\n')
    f.write('        end\n')
    f.write('        GEN_VARY_EXTRACT: begin\n')
    f.write('          // gen_rd_data NOW holds the vary-offset\'s row. Extract the byte, then\n')
    f.write('          // issue beat 0\'s prefetch on the same shared read port (safe -- these\n')
    f.write('          // two reads never overlap, this FSM issues them strictly in sequence).\n')
    if keep_w_shift > 0:
        f.write(f'          vary_val    <= gen_rd_data[vary_offset_r[{keep_w_shift-1}:0] * 8 +: 8];\n')
    else:
        f.write('          vary_val    <= gen_rd_data[0 +: 8];\n')
    f.write("          gen_rd_addr <= '0;\n")
    f.write('          gen_st      <= GEN_PRIME_NEXT;\n')
    f.write('        end\n')
    f.write('        GEN_PRIME_NEXT: begin\n')
    f.write('          // Shared by burst-start and every inter-packet transition: gen_rd_addr\n')
    f.write('          // currently holds beat 0\'s row address (primed by whichever state got\n')
    f.write('          // us here), about to become gen_rd_data at the start of GEN_SEND --\n')
    f.write('          // advance it to beat 1\'s address now, establishing the steady-state\n')
    f.write('          // "gen_rd_addr == beat_idx+1" invariant before GEN_SEND ever checks it.\n')
    f.write("          gen_rd_addr <= gen_rd_addr + 9'd1;\n")
    f.write('          gen_st      <= GEN_SEND;\n')
    f.write('        end\n')
    f.write('        GEN_SEND: begin\n')
    f.write('          if (gen_axis_tvalid && gen_axis_tready) begin\n')
    f.write('            if (gen_axis_tlast) begin\n')
    f.write("              sent_count <= sent_count + 32'd1;\n")
    f.write("              pkt_idx    <= pkt_idx + 32'd1;\n")
    f.write("              beat_idx   <= '0;\n")
    f.write("              if (vary_enable_r) vary_val <= vary_val + 8'd1;\n")
    f.write("              if (pkt_idx + 32'd1 == pkt_count_r) begin\n")
    f.write("                gen_busy <= 1'b0;\n")
    f.write("                gen_done <= 1'b1;\n")
    f.write('                gen_st   <= GEN_IDLE;\n')
    f.write("              end else begin\n")
    f.write("                // Prime beat 0 of the next packet now -- held steady (never\n")
    f.write("                // re-advanced) for however long GEN_GAP takes, if any; only the\n")
    f.write("                // final GEN_PRIME_NEXT step (right before GEN_SEND resumes)\n")
    f.write("                // advances it again. This is why parking here for a long gap is\n")
    f.write("                // safe: the read keeps re-settling on the SAME correct address.\n")
    f.write("                gen_rd_addr <= '0;\n")
    f.write("                if (ipg_r == 32'd0) begin\n")
    f.write('                  gen_st <= GEN_PRIME_NEXT;\n')
    f.write('                end else begin\n')
    f.write('                  ipg_cnt <= ipg_r;\n')
    f.write('                  gen_st  <= GEN_GAP;\n')
    f.write('                end\n')
    f.write('              end\n')
    f.write('            end else begin\n')
    f.write("              beat_idx    <= beat_idx + 9'd1;\n")
    f.write("              gen_rd_addr <= gen_rd_addr + 9'd1;\n")
    f.write('            end\n')
    f.write('          end\n')
    f.write('        end\n')
    f.write('        GEN_GAP: begin\n')
    f.write('          // gen_rd_addr stays parked at beat 0\'s row throughout -- see the\n')
    f.write('          // comment where it was set, above.\n')
    f.write("          if (ipg_cnt <= 32'd1) begin\n")
    f.write('            gen_st <= GEN_PRIME_NEXT;\n')
    f.write('          end else begin\n')
    f.write("            ipg_cnt <= ipg_cnt - 32'd1;\n")
    f.write('          end\n')
    f.write('        end\n')
    f.write('        default: gen_st <= GEN_IDLE;\n')
    f.write('      endcase\n')
    f.write('    end\n')
    f.write('  end\n\n')


def _write_capture(f, beat_bytes):
    keep_w_shift = int(math.log2(beat_bytes))  # ROW_BYTES==KEEP_W -- see docstring

    f.write('  // ── Packet capture ───────────────────────────────────────────────────────\n')
    f.write('  // m_axis_tready is tied high in u_core\'s instantiation above -- capture\n')
    f.write('  // never backpressures the DUT. A single cap_start arms recording for every\n')
    f.write('  // packet that arrives afterward, not just one: write_cursor resets to 0 at\n')
    f.write('  // the start of each new packet (right after the previous one\'s tlast), so\n')
    f.write('  // a multi-packet burst\'s LAST packet is what ends up in cap_buf/cap_byte_count\n')
    f.write('  // when the burst finishes -- captures only the most recent completed packet\n')
    f.write('  // (not every packet in a burst), bounding BRAM cost honestly. cap_done is a\n')
    f.write('  // sticky flag (set on the first completed packet, held through later ones),\n')
    f.write('  // not a terminal state -- recording never stops on its own, only a fresh\n')
    f.write('  // cap_start re-arms/resets it.\n')
    f.write('  typedef enum logic {\n')
    f.write("    CAP_IDLE  = 1'd0,\n")
    f.write("    CAP_ARMED = 1'd1\n")
    f.write('  } cap_st_t;\n')
    f.write('  cap_st_t cap_st;\n')
    f.write('  logic [31:0] write_cursor;   // resets to 0 at the start of each new packet\n')
    f.write('  logic [31:0] cap_byte_count; // length of the last COMPLETED packet (held stable)\n')
    f.write('  logic        cap_done;       // sticky: at least one packet captured since arm\n')
    f.write('  logic        cap_busy;\n')
    f.write('  assign cap_busy = (cap_st == CAP_ARMED);\n\n')

    f.write('  logic [7:0] cap_valid_bytes;  // popcount(cap_axis_tkeep) this beat\n')
    f.write('  always @(*) begin\n')
    f.write("    cap_valid_bytes = 8'd0;\n")
    f.write('    for (int i = 0; i < KEEP_W; i = i + 1)\n')
    f.write("      if (cap_axis_tkeep[i]) cap_valid_bytes = cap_valid_bytes + 8'd1;\n")
    f.write('  end\n\n')

    f.write('  // write_cursor only ever advances by a full KEEP_W (every non-last beat\n')
    f.write('  // carries a full tkeep -- only the tlast beat is ever partial), so it is\n')
    f.write('  // always exactly row-aligned at the moment of every real write -- cap_row\n')
    f.write('  // is a pure bit-select (KEEP_W is a power of 2), not a division.\n')
    f.write(f'  wire [31:0] cap_row = write_cursor[31:{keep_w_shift}];\n\n')

    f.write('  logic r_cap_start;  // one-cycle strobe, set by the self-test AXIL decoder below\n\n')

    f.write('  always_ff @(posedge clk) begin\n')
    f.write('    if (!rst_n) begin\n')
    f.write('      cap_st         <= CAP_IDLE;\n')
    f.write("      write_cursor   <= 32'd0;\n")
    f.write("      cap_byte_count <= 32'd0;\n")
    f.write("      cap_done       <= 1'b0;\n")
    f.write('    end else if (r_cap_start) begin\n')
    f.write('      cap_st         <= CAP_ARMED;\n')
    f.write("      write_cursor   <= 32'd0;\n")
    f.write("      cap_byte_count <= 32'd0;\n")
    f.write("      cap_done       <= 1'b0;\n")
    f.write('    end else if (cap_st == CAP_ARMED && cap_axis_tvalid) begin\n')
    f.write('      // No separate "cap_row < CAP_ROWS" bounds guard here (unlike the old\n')
    f.write('      // per-lane code this replaced): write_cursor is structurally bounded to\n')
    f.write('      // MAX_PKT_BEATS-1 beats (the wrapped core never presents more, by its own\n')
    f.write('      // MAX_PKT_BEATS), so cap_row can never reach CAP_ROWS -- an extra guard\n')
    f.write('      // level here was found to stop Quartus\'s byte-enable RAM inference\n')
    f.write('      // template from matching at all (0 bits inferred despite an otherwise\n')
    f.write('      // correct packed declaration and byte-indexed write).\n')
    f.write('      // Statically unrolled (not a `for` loop, even though KEEP_W is compile-\n')
    f.write('      // time-known and this is logically identical either way): Quartus\'s\n')
    f.write('      // byte-enable RAM inference template was found NOT to match a `for`-loop\n')
    f.write('      // form of this write, only a literal, explicit if-per-byte sequence\n')
    f.write('      // (matching Intel\'s own "Recommended HDL Coding Styles" example exactly).\n')
    for b in range(beat_bytes):
        f.write(f'      if (cap_axis_tkeep[{b}]) cap_word[cap_row][{b}] <= cap_axis_tdata[{b*8} +: 8];\n')
    f.write('      if (cap_axis_tlast) begin\n')
    f.write("        cap_byte_count <= write_cursor + {24'd0, cap_valid_bytes};\n")
    f.write("        write_cursor   <= 32'd0;  // ready for the next packet, if any\n")
    f.write("        cap_done       <= 1'b1;\n")
    f.write('      end else begin\n')
    f.write("        write_cursor <= write_cursor + {24'd0, cap_valid_bytes};\n")
    f.write('      end\n')
    f.write('    end\n')
    f.write('  end\n\n')


def _write_record_capture(f, fe_all, rec_depth, rec_words):
    """Capture FeatureExport records into a per-instance window readable over
    st_axil_*.

    One entry per record, REC_WORDS 32-bit words wide, written in a single
    cycle as ONE wide element -- not as REC_WORDS separate word writes, which
    would be two writes into one array in one cycle (a pattern this project
    has twice found stops iverilog advancing simulation time, and that real
    RAM inference does not match either).

    The array is deliberately plain REGISTERS, not a RAM: it holds
    REC_NINST * REC_DEPTH * REC_WORDS * 32 bits -- about 2 Kbit per instance --
    and a RAM would need one write port per instance, because two instances
    declared in the same control push on the SAME cycle (feprobe.p4 does
    exactly that). Registers make that free; one shared RAM port would have had
    to drop a record.
    """
    if not fe_all:
        return
    idx_w = max(1, (rec_depth - 1).bit_length())
    sel_w = max(1, (len(fe_all) - 1).bit_length())
    f.write('  // ── FeatureExport record capture ─────────────────────────────────────────\n')
    f.write('  // Each instance keeps the FIRST REC_DEPTH records since rec_arm. A full\n')
    f.write('  // buffer stops storing rather than overwriting -- in a bring-up burst the\n')
    f.write('  // early records are the interesting ones -- while rec_total keeps counting\n')
    f.write('  // everything pushed, so (rec_total - rec_count) is exactly how many were\n')
    f.write('  // not kept.\n')
    f.write('  logic [REC_WORDS*32-1:0] rec_entry [0:REC_NINST*REC_DEPTH-1];\n')
    f.write('  logic [31:0] rec_count_v [0:REC_NINST-1];\n')
    f.write('  logic [31:0] rec_total_v [0:REC_NINST-1];\n')
    f.write('  logic        r_rec_arm;    // one-cycle strobe from the decoder below\n')
    f.write(f'  logic [{sel_w-1}:0] rec_sel_reg;\n\n')
    f.write('  // Simulation-only zero-fill, same reason (and same directive) as the\n')
    f.write('  // packet buffers above: hardware needs no reset value here.\n')
    f.write('  // synthesis translate_off\n')
    f.write('  initial begin\n')
    f.write("    for (int i = 0; i < REC_NINST*REC_DEPTH; i++) rec_entry[i] = '0;\n")
    f.write('  end\n')
    f.write('  // synthesis translate_on\n\n')
    for i, fe in enumerate(fe_all):
        pad = rec_words * 32 - fe.padded_width
        f.write(f'  // instance {i}: {fe.name}, {fe.padded_width}-bit record\n')
        f.write('  always_ff @(posedge clk) begin\n')
        f.write('    if (!rst_n || r_rec_arm) begin\n')
        f.write(f"      rec_count_v[{i}] <= 32'd0;\n")
        f.write(f"      rec_total_v[{i}] <= 32'd0;\n")
        f.write(f'    end else if ({fe.name}_tvalid) begin\n')
        f.write(f"      rec_total_v[{i}] <= rec_total_v[{i}] + 32'd1;\n")
        f.write(f'      if (rec_count_v[{i}] < REC_DEPTH) begin\n')
        f.write(f'        rec_entry[{i}*REC_DEPTH + rec_count_v[{i}][{idx_w-1}:0]] <=\n')
        if pad > 0:
            f.write(f"            {{{pad}'d0, {fe.name}_tdata}};\n")
        else:
            f.write(f'            {fe.name}_tdata;\n')
        f.write(f"        rec_count_v[{i}] <= rec_count_v[{i}] + 32'd1;\n")
        f.write('      end\n')
        f.write('    end\n')
        f.write('  end\n\n')
    f.write('  // The selected instance\'s counters. always_comb, not an assign: reading an\n')
    f.write('  // unpacked-array element from a continuous assignment is a pattern iverilog\n')
    f.write('  // 11 rejects (the same rule the shell\'s per-slot arrays follow).\n')
    f.write('  logic [31:0] rec_count_sel, rec_total_sel;\n')
    f.write('  always_comb begin\n')
    f.write('    rec_count_sel = rec_count_v[rec_sel_reg];\n')
    f.write('    rec_total_sel = rec_total_v[rec_sel_reg];\n')
    f.write('  end\n\n')


def _write_axil_decoder(f, pktlen_w, vary_w, tmpl_base_word, cap_base_word, addr_span_words,
                         max_pkt_bytes, words_per_row, wpr_shift,
                         fe_all, rec_base_word, rec_depth, rec_words, ingress_port_w):
    f.write('  // ── Self-test AXI4-Lite decoder (own bus, own FSM -- see register map above) ──\n')
    f.write('  // (staging-register declarations for gen_pkt_len_reg/etc. are hoisted to\n')
    f.write('  // before _write_generator -- see the call site in _write_module.)\n\n')

    f.write('  typedef enum logic [1:0] {\n')
    f.write("    ST_AXIL_IDLE  = 2'd0,\n")
    f.write("    ST_AXIL_WDATA = 2'd1,\n")
    f.write("    ST_AXIL_BRESP = 2'd2\n")
    f.write('  } st_axil_st_t;\n')
    f.write('  st_axil_st_t st_axil_st;\n')
    f.write('  logic [ST_AXIL_ADDR_W-1:0] st_axil_awaddr_r;\n\n')

    f.write('  // Row/word-within-row split for the tmpl_buf CP write below -- WORDS_PER_ROW\n')
    f.write('  // (KEEP_W/4) 4-byte AXI4-Lite words fit in one KEEP_W-byte BRAM row; both are\n')
    f.write('  // powers of 2 so this is a pure bit-select, never a division.\n')
    f.write(f"  wire [13:0] wr_word_idx = st_axil_awaddr_r[ST_AXIL_ADDR_W-1:2] - 14'd{tmpl_base_word};\n")
    if words_per_row > 1:
        f.write(f'  wire [13:0] wr_row = wr_word_idx[13:{wpr_shift}];\n\n')
    else:
        f.write('  wire [13:0] wr_row = wr_word_idx;\n\n')

    f.write('  assign st_axil_awready = (st_axil_st == ST_AXIL_IDLE);\n')
    f.write('  assign st_axil_bvalid  = (st_axil_st == ST_AXIL_BRESP);\n')
    f.write("  assign st_axil_bresp   = 2'b00;\n")
    f.write('  assign st_axil_wready  = (st_axil_st == ST_AXIL_WDATA);\n\n')

    f.write('  always_ff @(posedge clk) begin\n')
    f.write('    if (!rst_n) begin\n')
    f.write('      st_axil_st <= ST_AXIL_IDLE;\n')
    f.write("      r_gen_start <= 1'b0;\n")
    f.write("      r_cap_start <= 1'b0;\n")
    f.write("      gen_pkt_len_reg     <= '0;\n")
    f.write("      gen_pkt_count_reg   <= 32'd0;\n")
    f.write("      gen_vary_offset_reg <= '0;\n")
    f.write("      gen_vary_enable_reg <= 1'b0;\n")
    f.write("      gen_ipg_reg         <= 32'd0;\n")
    if ingress_port_w:
        f.write("      gen_ingress_port_reg <= '0;\n")
    if fe_all:
        f.write("      r_rec_arm   <= 1'b0;\n")
        f.write("      rec_sel_reg <= '0;\n")
    f.write('    end else begin\n')
    f.write("      r_gen_start <= 1'b0;\n")
    f.write("      r_cap_start <= 1'b0;\n")
    if fe_all:
        f.write("      r_rec_arm   <= 1'b0;\n")
    f.write('      case (st_axil_st)\n')
    f.write('        ST_AXIL_IDLE: begin\n')
    f.write('          if (st_axil_awvalid) begin\n')
    f.write('            st_axil_awaddr_r <= st_axil_awaddr;\n')
    f.write('            st_axil_st       <= ST_AXIL_WDATA;\n')
    f.write('          end\n')
    f.write('        end\n')
    f.write('        ST_AXIL_WDATA: begin\n')
    f.write('          if (st_axil_wvalid && st_axil_wready) begin\n')
    f.write(f"            if (st_axil_awaddr_r[ST_AXIL_ADDR_W-1:2] < 14'd{tmpl_base_word}) begin\n")
    f.write('              case (st_axil_awaddr_r[ST_AXIL_ADDR_W-1:2])\n')
    f.write(f'                14\'d0: gen_pkt_len_reg     <= st_axil_wdata[{pktlen_w-1}:0];\n')
    f.write("                14'd1: gen_pkt_count_reg   <= st_axil_wdata;\n")
    f.write(f'                14\'d2: gen_vary_offset_reg <= st_axil_wdata[{vary_w-1}:0];\n')
    f.write("                14'd3: gen_vary_enable_reg <= st_axil_wdata[0];\n")
    f.write("                14'd4: gen_ipg_reg         <= st_axil_wdata;\n")
    f.write("                14'd5: r_gen_start         <= 1'b1;\n")
    f.write("                14'd8: r_cap_start         <= 1'b1;\n")
    if fe_all:
        f.write("                14'd12: r_rec_arm          <= 1'b1;\n")
        f.write(f"                14'd13: rec_sel_reg        <= st_axil_wdata[{max(1, (len(fe_all)-1).bit_length())-1}:0];\n")
    if ingress_port_w:
        f.write(f"                14'd16: gen_ingress_port_reg <= st_axil_wdata[{ingress_port_w-1}:0];\n")
    f.write('                default: ; // the rest are read-only or reserved\n')
    f.write('              endcase\n')
    f.write(f"            end else if (st_axil_awaddr_r[ST_AXIL_ADDR_W-1:2] < 14'd{cap_base_word}) begin\n")
    f.write('              // template buffer word write -- big-endian byte packing (see register\n')
    f.write('              // map). Both mirrored copies written identically every cycle so they\n')
    f.write('              // can never diverge -- see the buffer declaration comment.\n')

    def _emit_tmpl_word_write(word_off, indent):
        # True two-level indexing (byte INDEX, not a bit-position part-select) --
        # required for Quartus's byte-enable RAM inference template to match.
        byte0, byte1, byte2, byte3 = word_off * 4 + 0, word_off * 4 + 1, word_off * 4 + 2, word_off * 4 + 3
        for arr in ('tmpl_word_cp', 'tmpl_word_gen'):
            f.write(f'{indent}{arr}[wr_row][{byte0}] <= st_axil_wdata[31:24];\n')
            f.write(f'{indent}{arr}[wr_row][{byte1}] <= st_axil_wdata[23:16];\n')
            f.write(f'{indent}{arr}[wr_row][{byte2}] <= st_axil_wdata[15:8];\n')
            f.write(f'{indent}{arr}[wr_row][{byte3}] <= st_axil_wdata[7:0];\n')

    if words_per_row > 1:
        f.write(f'              case (wr_word_idx[{wpr_shift-1}:0])\n')
        for word_off in range(words_per_row):
            f.write(f"                {wpr_shift}'d{word_off}: begin\n")
            _emit_tmpl_word_write(word_off, '                  ')
            f.write('                end\n')
        f.write('                default: ;\n')
        f.write('              endcase\n')
    else:
        _emit_tmpl_word_write(0, '              ')
    f.write('            end\n')
    f.write('            // cap_buf region (and beyond): write ignored, still BRESP\'d below\n')
    f.write('            st_axil_st <= ST_AXIL_BRESP;\n')
    f.write('          end\n')
    f.write('        end\n')
    f.write('        ST_AXIL_BRESP: begin\n')
    f.write('          if (st_axil_bready) st_axil_st <= ST_AXIL_IDLE;\n')
    f.write('        end\n')
    f.write('        default: st_axil_st <= ST_AXIL_IDLE;\n')
    f.write('      endcase\n')
    f.write('    end\n')
    f.write('  end\n\n')

    f.write('  // AXI4-Lite read channel. Note the DELIBERATE choice to sample st_r_rdata\n')
    f.write('  // via a real registered case (below), and to expose it through st_axil_rdata\n')
    f.write('  // for exactly one cycle while st_axil_rst==ST_AXIL_R_DATA -- a testbench must\n')
    f.write('  // sample it UNDELAYED at that same edge, not one edge later, since\n')
    f.write("  // st_axil_rready is expected to be tied high by most drivers (see this\n")
    f.write("  // project's own tb_fiveTuple_top.sv axil_read task and its comments for the\n")
    f.write('  // exact race this caught previously). ST_AXIL_R_WAIT is NEW: tmpl_buf/cap_buf\n')
    f.write('  // are real BRAM now (1-cycle registered read: an address held during cycle T\n')
    f.write('  // produces data at cycle T+1), so those addresses need TWO extra cycles\n')
    f.write('  // between issuing the row read and presenting it -- ST_AXIL_R_WAIT is a pure\n')
    f.write('  // wait (the row read issued on the R_IDLE->R_WAIT edge is only IN FLIGHT\n')
    f.write('  // during R_WAIT, not yet valid -- touching st_r_row here would lose it before\n')
    f.write('  // it lands), ST_AXIL_R_EXTRACT is where tmpl_word_cp_rdata/cap_word_rdata\n')
    f.write('  // actually hold the requested row and get sliced into st_r_rdata. Control-\n')
    f.write('  // register reads are unaffected, still resolved same-cycle straight to\n')
    f.write('  // R_DATA, preserving the undelayed-sampling invariant above for every address\n')
    f.write('  // class.\n')
    f.write('  typedef enum logic [1:0] {\n')
    f.write("    ST_AXIL_R_IDLE    = 2'd0,\n")
    f.write("    ST_AXIL_R_WAIT    = 2'd1,\n")
    f.write("    ST_AXIL_R_EXTRACT = 2'd2,\n")
    f.write("    ST_AXIL_R_DATA    = 2'd3\n")
    f.write('  } st_axil_rst_t;\n')
    f.write('  st_axil_rst_t st_axil_rst;\n')
    f.write('  logic [31:0] st_r_rdata;\n')
    f.write('  logic [13:0] st_r_row;\n')
    if words_per_row > 1:
        f.write(f'  logic [{wpr_shift-1}:0] st_r_word_off;\n')
    f.write('  logic        st_r_is_cap;\n')
    if fe_all:
        idx_w = max(1, (rec_depth - 1).bit_length())
        f.write(f'  logic [{idx_w-1}:0] st_r_rec_idx;\n')
        if rec_words > 1:
            f.write(f'  logic [{max(1,(rec_words-1).bit_length())-1}:0] st_r_rec_word;\n')
        f.write('  logic        st_r_is_rec;\n')
    f.write('\n')

    f.write('  // Unconditional registered row read -- always-on, consumed only while\n')
    f.write('  // st_axil_rst==ST_AXIL_R_WAIT. Reading both arrays every cycle regardless of\n')
    f.write('  // which is actually needed is harmless (plain BRAM reads, no side effects)\n')
    f.write('  // and avoids needing extra muxing on the address feeding this port.\n')
    f.write('  logic [AXI_DATA_W-1:0] tmpl_word_cp_rdata;\n')
    f.write('  logic [AXI_DATA_W-1:0] cap_word_rdata;\n')
    f.write('  always_ff @(posedge clk) begin\n')
    f.write('    tmpl_word_cp_rdata <= tmpl_word_cp[st_r_row];\n')
    f.write('    cap_word_rdata     <= cap_word[st_r_row];\n')
    f.write('  end\n\n')
    if fe_all:
        f.write('  // The selected record, fetched on the same R_IDLE->R_WAIT edge as the\n')
        f.write('  // buffer rows above, so the record window shares their read timing.\n')
        f.write('  // rec_sel_reg picks the instance; the index is within that instance.\n')
        f.write('  logic [REC_WORDS*32-1:0] rec_entry_rdata;\n')
        f.write('  always_ff @(posedge clk) begin\n')
        f.write('    rec_entry_rdata <= rec_entry[rec_sel_reg*REC_DEPTH + st_r_rec_idx];\n')
        f.write('  end\n\n')

    f.write('  assign st_axil_arready = (st_axil_rst == ST_AXIL_R_IDLE);\n')
    f.write('  assign st_axil_rdata   = st_r_rdata;\n')
    f.write("  assign st_axil_rresp   = 2'b00;\n")
    f.write('  assign st_axil_rvalid  = (st_axil_rst == ST_AXIL_R_DATA);\n\n')

    f.write('  always_ff @(posedge clk) begin\n')
    f.write('    if (!rst_n) begin\n')
    f.write('      st_axil_rst <= ST_AXIL_R_IDLE;\n')
    f.write('    end else begin\n')
    f.write('      case (st_axil_rst)\n')
    f.write('        ST_AXIL_R_IDLE: begin\n')
    f.write('          if (st_axil_arvalid) begin\n')
    f.write(f"            if (st_axil_araddr[ST_AXIL_ADDR_W-1:2] < 14'd{tmpl_base_word}) begin\n")
    f.write('              case (st_axil_araddr[ST_AXIL_ADDR_W-1:2])\n')
    f.write("                14'd6:  st_r_rdata <= {30'd0, gen_done, gen_busy};\n")
    f.write("                14'd7:  st_r_rdata <= sent_count;\n")
    f.write("                14'd9:  st_r_rdata <= {30'd0, cap_done, cap_busy};\n")
    f.write("                14'd10: st_r_rdata <= cap_byte_count;\n")
    f.write(f"                14'd11: st_r_rdata <= 32'd{max_pkt_bytes};\n")
    if fe_all:
        f.write(f"                14'd12: st_r_rdata <= {{16'd{rec_depth}, 8'd{rec_words}, 8'd{len(fe_all)}}};\n")
        f.write("                14'd13: st_r_rdata <= {28'd0, rec_sel_reg};\n")
        f.write("                14'd14: st_r_rdata <= rec_count_sel;\n")
        f.write("                14'd15: st_r_rdata <= rec_total_sel;\n")
    if ingress_port_w:
        f.write("                14'd16: st_r_rdata <= {23'd0, gen_ingress_port_reg};\n")
    f.write(f"                14'd17: st_r_rdata <= 32'd{tmpl_base_word};\n")
    f.write(f"                14'd18: st_r_rdata <= 32'd{cap_base_word};\n")
    f.write(f"                14'd19: st_r_rdata <= 32'd{rec_base_word};\n")
    f.write('                default: st_r_rdata <= 32\'d0;\n')
    f.write('              endcase\n')
    f.write('              st_axil_rst <= ST_AXIL_R_DATA;\n')
    f.write(f"            end else if (st_axil_araddr[ST_AXIL_ADDR_W-1:2] < 14'd{cap_base_word}) begin\n")
    f.write(f"              st_r_row    <= (st_axil_araddr[ST_AXIL_ADDR_W-1:2] - 14'd{tmpl_base_word}) >> {wpr_shift};\n")
    if words_per_row > 1:
        f.write(f"              st_r_word_off <= (st_axil_araddr[ST_AXIL_ADDR_W-1:2] - 14'd{tmpl_base_word}) & 14'd{words_per_row-1};\n")
    f.write("              st_r_is_cap <= 1'b0;\n")
    f.write('              st_axil_rst <= ST_AXIL_R_WAIT;\n')
    # The cap_buf region ends where the record window begins -- NOT at
    # addr_span_words, which now spans the records too. Using the span here
    # made this branch swallow every record address and left the record
    # branch below unreachable: counts read back fine and the record DATA
    # came back as X, because the read was dispatched to cap_word.
    f.write(f"            end else if (st_axil_araddr[ST_AXIL_ADDR_W-1:2] < 14'd{rec_base_word}) begin\n")
    f.write(f"              st_r_row    <= (st_axil_araddr[ST_AXIL_ADDR_W-1:2] - 14'd{cap_base_word}) >> {wpr_shift};\n")
    if words_per_row > 1:
        f.write(f"              st_r_word_off <= (st_axil_araddr[ST_AXIL_ADDR_W-1:2] - 14'd{cap_base_word}) & 14'd{words_per_row-1};\n")
    f.write("              st_r_is_cap <= 1'b1;\n")
    if fe_all:
        f.write("              st_r_is_rec <= 1'b0;\n")
    f.write('              st_axil_rst <= ST_AXIL_R_WAIT;\n')
    if fe_all:
        rec_span = rec_depth * rec_words
        f.write(f"            end else if (st_axil_araddr[ST_AXIL_ADDR_W-1:2] < 14'd{rec_base_word + rec_span}) begin\n")
        f.write('              // Record window for rec_sel: entry e word w at e*REC_WORDS + w.\n')
        idx_w = max(1, (rec_depth - 1).bit_length())
        if rec_words > 1:
            wsh = (rec_words - 1).bit_length()
            f.write(f"              st_r_rec_idx  <= (st_axil_araddr[ST_AXIL_ADDR_W-1:2] - 14'd{rec_base_word}) >> {wsh};\n")
            f.write(f"              st_r_rec_word <= (st_axil_araddr[ST_AXIL_ADDR_W-1:2] - 14'd{rec_base_word}) & 14'd{rec_words-1};\n")
        else:
            f.write(f"              st_r_rec_idx  <= (st_axil_araddr[ST_AXIL_ADDR_W-1:2] - 14'd{rec_base_word});\n")
        f.write("              st_r_is_cap <= 1'b0;\n")
        f.write("              st_r_is_rec <= 1'b1;\n")
        f.write('              st_axil_rst <= ST_AXIL_R_WAIT;\n')
    f.write('            end else begin\n')
    f.write("              st_r_rdata <= 32'd0;\n")
    f.write('              st_axil_rst <= ST_AXIL_R_DATA;\n')
    f.write('            end\n')
    f.write('          end\n')
    f.write('        end\n')
    f.write('        ST_AXIL_R_WAIT: begin\n')
    f.write('          // Pure wait: the row read issued on the R_IDLE->R_WAIT edge is only\n')
    f.write('          // in flight here, not yet valid in tmpl_word_cp_rdata/cap_word_rdata --\n')
    f.write('          // must not touch st_r_row this cycle, or the in-flight fetch is lost.\n')
    f.write('          st_axil_rst <= ST_AXIL_R_EXTRACT;\n')
    f.write('        end\n')
    f.write('        ST_AXIL_R_EXTRACT: begin\n')
    f.write('          // tmpl_word_cp_rdata/cap_word_rdata NOW hold row st_r_row.\n')

    def _emit_row_extract(word_off, indent):
        b0, b1, b2, b3 = (word_off * 4 + 0) * 8, (word_off * 4 + 1) * 8, (word_off * 4 + 2) * 8, (word_off * 4 + 3) * 8
        f.write(f'{indent}st_r_rdata <= st_r_is_cap\n')
        f.write(f'{indent}  ? {{cap_word_rdata[{b0} +: 8], cap_word_rdata[{b1} +: 8], cap_word_rdata[{b2} +: 8], cap_word_rdata[{b3} +: 8]}}\n')
        f.write(f'{indent}  : {{tmpl_word_cp_rdata[{b0} +: 8], tmpl_word_cp_rdata[{b1} +: 8], tmpl_word_cp_rdata[{b2} +: 8], tmpl_word_cp_rdata[{b3} +: 8]}};\n')

    rec_ind = '            ' if fe_all else '          '
    if fe_all:
        f.write('          if (st_r_is_rec) begin\n')
        if rec_words > 1:
            f.write('            case (st_r_rec_word)\n')
            for w in range(rec_words):
                f.write(f"              {max(1,(rec_words-1).bit_length())}'d{w}: "
                        f"st_r_rdata <= rec_entry_rdata[{w*32} +: 32];\n")
            f.write("              default: st_r_rdata <= 32'd0;\n")
            f.write('            endcase\n')
        else:
            f.write('            st_r_rdata <= rec_entry_rdata[31:0];\n')
        f.write('          end else begin\n')
    if words_per_row > 1:
        f.write(f'{rec_ind}case (st_r_word_off)\n')
        for word_off in range(words_per_row):
            f.write(f"{rec_ind}  {wpr_shift}'d{word_off}: begin\n")
            _emit_row_extract(word_off, rec_ind + '    ')
            f.write(f'{rec_ind}  end\n')
        f.write(f"{rec_ind}  default: st_r_rdata <= 32'd0;\n")
        f.write(f'{rec_ind}endcase\n')
    else:
        _emit_row_extract(0, rec_ind)
    if fe_all:
        f.write('          end\n')
    f.write('          st_axil_rst <= ST_AXIL_R_DATA;\n')
    f.write('        end\n')
    f.write('        ST_AXIL_R_DATA: begin\n')
    f.write('          if (st_axil_rready) st_axil_rst <= ST_AXIL_R_IDLE;\n')
    f.write('        end\n')
    f.write('        default: st_axil_rst <= ST_AXIL_R_IDLE;\n')
    f.write('      endcase\n')
    f.write('    end\n')
    f.write('  end\n\n')
