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
 12-15                 reserved
 16 .. 16+TMPL_WORDS-1        tmpl_buf  RW (word = 4 bytes, big-endian: a
                               32-bit write W places W[31:24] at the lowest
                               byte offset -- matches how a human hand-writing
                               a header field, e.g. a 32-bit IPv4 address, as
                               one hex literal expects it to land on the wire)
 16+TMPL_WORDS .. +TMPL_WORDS-1  cap_buf  R (write ignored)

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

CTRL_WORDS = 16   # bytes 0x00-0x3C


def emit_selftest_top(ir, app_name, output_path, axi_data_width=DEFAULT_AXI_DATA_W):
    """Generate {app_name}_selftest_top.sv.

    ir: accepted for interface symmetry with the other emit_*() functions and
        future-proofing; unused today -- the wrapper is protocol-agnostic by
        construction (the whole point of the writable-template design).
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
    max_pkt_bytes = MAX_PKT_BEATS * beat_bytes
    pktlen_w      = max(1, math.ceil(math.log2(max_pkt_bytes + 1)))
    vary_w        = max(1, math.ceil(math.log2(max_pkt_bytes)))

    tmpl_words       = max_pkt_bytes // 4
    tmpl_base_word   = CTRL_WORDS
    cap_base_word    = tmpl_base_word + tmpl_words
    cap_words        = max_pkt_bytes // 4
    addr_span_words  = cap_base_word + cap_words

    with open(output_path, 'w') as f:
        f.write(f'// {app_name}_selftest_top.sv -- opt-in on-chip packet generator + capture\n')
        f.write(f'// wrapper around {app_name}_top.sv (generated by --self-test). See\n')
        f.write('// compiler/emit_selftest.py for the full design rationale and register map.\n')
        f.write(f'// axi_data_width={axi_data_width} (MUST match the {app_name}_top.sv this wraps)\n\n')

        _write_module(f, app_name, axi_data_width, beat_bytes, max_pkt_bytes,
                      pktlen_w, vary_w, tmpl_words, tmpl_base_word,
                      cap_base_word, cap_words, addr_span_words)


def _write_module(f, app_name, axi_data_width, beat_bytes, max_pkt_bytes,
                   pktlen_w, vary_w, tmpl_words, tmpl_base_word,
                   cap_base_word, cap_words, addr_span_words):

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
    f.write('    input  logic                       st_axil_rready\n')
    f.write(');\n\n')

    f.write('  localparam int KEEP_W        = AXI_DATA_W / 8;  // {}\n'.format(beat_bytes))
    f.write(f'  localparam int MAX_PKT_BYTES = {MAX_PKT_BEATS} * KEEP_W;  // {max_pkt_bytes}\n')
    f.write(f'  localparam int TMPL_BASE_WORD  = {tmpl_base_word};\n')
    f.write(f'  localparam int CAP_BASE_WORD   = {cap_base_word};\n')
    f.write(f'  localparam int ADDR_SPAN_WORDS = {addr_span_words};\n\n')

    # ── Template / capture buffers ──────────────────────────────────────────
    f.write('  // Template buffer (software-written packet content, read+write over\n')
    f.write('  // st_axil_*) and capture buffer (written only by the capture FSM below,\n')
    f.write('  // read over st_axil_*). Real BRAM cost -- see this file\'s module docstring.\n')
    f.write('  logic [7:0] tmpl_buf [0:MAX_PKT_BYTES-1];\n')
    f.write('  logic [7:0] cap_buf  [0:MAX_PKT_BYTES-1];\n')
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
    f.write('    for (int i = 0; i < MAX_PKT_BYTES; i++) tmpl_buf[i] = 8\'d0;\n')
    f.write('    for (int i = 0; i < MAX_PKT_BYTES; i++) cap_buf[i]  = 8\'d0;\n')
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
    f.write('    .s_axil_rdata(s_axil_rdata), .s_axil_rresp(s_axil_rresp), .s_axil_rvalid(s_axil_rvalid), .s_axil_rready(s_axil_rready)\n')
    f.write('  );\n\n')

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

    _write_generator(f, pktlen_w, vary_w)
    _write_capture(f)
    _write_axil_decoder(f, pktlen_w, vary_w, tmpl_base_word, cap_base_word, addr_span_words, max_pkt_bytes)

    f.write('endmodule\n')


def _write_generator(f, pktlen_w, vary_w):
    f.write('  // ── Packet generator ─────────────────────────────────────────────────────\n')
    f.write('  typedef enum logic [1:0] {\n')
    f.write("    GEN_IDLE = 2'd0,\n")
    f.write("    GEN_SEND = 2'd1,\n")
    f.write("    GEN_GAP  = 2'd2\n")
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
    f.write('          gen_axis_tdata[i*8 +: 8] = tmpl_buf[beat_idx * KEEP_W + i];\n')
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
    f.write('    end else begin\n')
    f.write('      case (gen_st)\n')
    f.write('        GEN_IDLE: begin\n')
    f.write('          if (r_gen_start) begin\n')
    f.write(f'            pkt_len_r     <= (gen_pkt_len_reg > MAX_PKT_BYTES) ? {pktlen_w}\'(MAX_PKT_BYTES) : gen_pkt_len_reg;\n')
    f.write('            pkt_count_r   <= gen_pkt_count_reg;\n')
    f.write('            vary_offset_r <= gen_vary_offset_reg;\n')
    f.write('            vary_enable_r <= gen_vary_enable_reg;\n')
    f.write('            ipg_r         <= gen_ipg_reg;\n')
    f.write('            vary_val      <= tmpl_buf[gen_vary_offset_reg];\n')
    f.write("            pkt_idx       <= 32'd0;\n")
    f.write("            beat_idx      <= '0;\n")
    f.write("            sent_count    <= 32'd0;\n")
    f.write("            gen_done      <= 1'b0;\n")
    f.write("            if (gen_pkt_count_reg == 32'd0 || gen_pkt_len_reg == '0) begin\n")
    f.write("              gen_busy <= 1'b0;\n")
    f.write("              gen_done <= 1'b1;\n")
    f.write('            end else begin\n')
    f.write("              gen_busy <= 1'b1;\n")
    f.write('              gen_st   <= GEN_SEND;\n')
    f.write('            end\n')
    f.write('          end\n')
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
    f.write("              end else if (ipg_r == 32'd0) begin\n")
    f.write('                gen_st <= GEN_SEND;\n')
    f.write('              end else begin\n')
    f.write('                ipg_cnt <= ipg_r;\n')
    f.write('                gen_st  <= GEN_GAP;\n')
    f.write('              end\n')
    f.write('            end else begin\n')
    f.write("              beat_idx <= beat_idx + 9'd1;\n")
    f.write('            end\n')
    f.write('          end\n')
    f.write('        end\n')
    f.write('        GEN_GAP: begin\n')
    f.write("          if (ipg_cnt <= 32'd1) begin\n")
    f.write('            gen_st <= GEN_SEND;\n')
    f.write('          end else begin\n')
    f.write("            ipg_cnt <= ipg_cnt - 32'd1;\n")
    f.write('          end\n')
    f.write('        end\n')
    f.write('        default: gen_st <= GEN_IDLE;\n')
    f.write('      endcase\n')
    f.write('    end\n')
    f.write('  end\n\n')


def _write_capture(f):
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
    f.write('      for (int i = 0; i < KEEP_W; i = i + 1) begin\n')
    f.write('        if (cap_axis_tkeep[i] && ((write_cursor + i) < MAX_PKT_BYTES))\n')
    f.write('          cap_buf[write_cursor + i] <= cap_axis_tdata[i*8 +: 8];\n')
    f.write('      end\n')
    f.write('      if (cap_axis_tlast) begin\n')
    f.write("        cap_byte_count <= write_cursor + {24'd0, cap_valid_bytes};\n")
    f.write("        write_cursor   <= 32'd0;  // ready for the next packet, if any\n")
    f.write("        cap_done       <= 1'b1;\n")
    f.write('      end else begin\n')
    f.write("        write_cursor <= write_cursor + {24'd0, cap_valid_bytes};\n")
    f.write('      end\n')
    f.write('    end\n')
    f.write('  end\n\n')


def _write_axil_decoder(f, pktlen_w, vary_w, tmpl_base_word, cap_base_word, addr_span_words, max_pkt_bytes):
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
    f.write('    end else begin\n')
    f.write("      r_gen_start <= 1'b0;\n")
    f.write("      r_cap_start <= 1'b0;\n")
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
    f.write('                default: ; // 6,7,9,10,11 read-only; 12-15 reserved\n')
    f.write('              endcase\n')
    f.write(f"            end else if (st_axil_awaddr_r[ST_AXIL_ADDR_W-1:2] < 14'd{cap_base_word}) begin\n")
    f.write('              // template buffer word write -- big-endian byte packing (see register map)\n')
    f.write(f"              tmpl_buf[(st_axil_awaddr_r[ST_AXIL_ADDR_W-1:2] - 14'd{tmpl_base_word})*4+0] <= st_axil_wdata[31:24];\n")
    f.write(f"              tmpl_buf[(st_axil_awaddr_r[ST_AXIL_ADDR_W-1:2] - 14'd{tmpl_base_word})*4+1] <= st_axil_wdata[23:16];\n")
    f.write(f"              tmpl_buf[(st_axil_awaddr_r[ST_AXIL_ADDR_W-1:2] - 14'd{tmpl_base_word})*4+2] <= st_axil_wdata[15:8];\n")
    f.write(f"              tmpl_buf[(st_axil_awaddr_r[ST_AXIL_ADDR_W-1:2] - 14'd{tmpl_base_word})*4+3] <= st_axil_wdata[7:0];\n")
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
    f.write('  // exact race this caught previously).\n')
    f.write('  typedef enum logic {\n')
    f.write("    ST_AXIL_R_IDLE = 1'd0,\n")
    f.write("    ST_AXIL_R_DATA = 1'd1\n")
    f.write('  } st_axil_rst_t;\n')
    f.write('  st_axil_rst_t st_axil_rst;\n')
    f.write('  logic [31:0] st_r_rdata;\n\n')

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
    f.write('                default: st_r_rdata <= 32\'d0;\n')
    f.write('              endcase\n')
    f.write(f"            end else if (st_axil_araddr[ST_AXIL_ADDR_W-1:2] < 14'd{cap_base_word}) begin\n")
    f.write(f"              st_r_rdata <= {{tmpl_buf[(st_axil_araddr[ST_AXIL_ADDR_W-1:2] - 14'd{tmpl_base_word})*4+0],\n")
    f.write(f"                             tmpl_buf[(st_axil_araddr[ST_AXIL_ADDR_W-1:2] - 14'd{tmpl_base_word})*4+1],\n")
    f.write(f"                             tmpl_buf[(st_axil_araddr[ST_AXIL_ADDR_W-1:2] - 14'd{tmpl_base_word})*4+2],\n")
    f.write(f"                             tmpl_buf[(st_axil_araddr[ST_AXIL_ADDR_W-1:2] - 14'd{tmpl_base_word})*4+3]}};\n")
    f.write(f"            end else if (st_axil_araddr[ST_AXIL_ADDR_W-1:2] < 14'd{addr_span_words}) begin\n")
    f.write(f"              st_r_rdata <= {{cap_buf[(st_axil_araddr[ST_AXIL_ADDR_W-1:2] - 14'd{cap_base_word})*4+0],\n")
    f.write(f"                             cap_buf[(st_axil_araddr[ST_AXIL_ADDR_W-1:2] - 14'd{cap_base_word})*4+1],\n")
    f.write(f"                             cap_buf[(st_axil_araddr[ST_AXIL_ADDR_W-1:2] - 14'd{cap_base_word})*4+2],\n")
    f.write(f"                             cap_buf[(st_axil_araddr[ST_AXIL_ADDR_W-1:2] - 14'd{cap_base_word})*4+3]}};\n")
    f.write('            end else begin\n')
    f.write("              st_r_rdata <= 32'd0;\n")
    f.write('            end\n')
    f.write('            st_axil_rst <= ST_AXIL_R_DATA;\n')
    f.write('          end\n')
    f.write('        end\n')
    f.write('        ST_AXIL_R_DATA: begin\n')
    f.write('          if (st_axil_rready) st_axil_rst <= ST_AXIL_R_IDLE;\n')
    f.write('        end\n')
    f.write('        default: st_axil_rst <= ST_AXIL_R_IDLE;\n')
    f.write('      endcase\n')
    f.write('    end\n')
    f.write('  end\n\n')
