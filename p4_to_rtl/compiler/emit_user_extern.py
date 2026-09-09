"""
emit_user_extern.py — Emit a *placeholder* {Name}_user_extern.sv per P4
`UserExtern<I, O>(fixed_latency_in_cycles) name;` declaration.

UserExtern is xsa.p4's escape hatch. The architecture deliberately provides no
`register`, no meter, no stateful primitive of any kind — UserExtern is the
only sanctioned way for an XSA program to express stateful or multi-cycle
logic, and what goes inside the block is by definition not something the
compiler can know.

So the split of responsibility is:

  * The COMPILER owns the latency contract. It presents `data_in` and then
    holds the entire rest of the packet context — every header field, metadata
    shadow, local and valid bit — in step for exactly `fixed_latency_in_cycles`
    before reading `result` (see _split_stages_for_user_externs in
    emit_processing.py). A user cannot fix this from inside their own module.

  * The USER owns the body. This file is a working placeholder so that a
    freshly-compiled program elaborates, simulates and synthesizes before the
    real block is written; the generated body is a pure `LATENCY`-deep shift
    register, i.e. the identity function delayed by the declared latency.

Because this file is USER CODE once edited, it is written ONCE and never
overwritten. Regenerating the app leaves an existing file untouched; delete it
to get a fresh placeholder back.
"""

import os


def emit_user_extern_module(ue, output_path):
    """Write a placeholder module for UserExternDecl `ue`.

    Returns 'created' if the file was written, 'kept' if a file was already
    there (user code — never clobbered)."""
    if os.path.exists(output_path):
        return 'kept'

    iw, ow, lat = ue.in_width, ue.out_width, ue.latency

    # How the placeholder maps I -> O. Widths are independent in P4, so be
    # explicit rather than relying on SystemVerilog's implicit truncation.
    if ow == iw:
        body_expr = f'{ue.name}_pipe[{lat-1}]' if lat > 0 else 'data_in'
    elif ow < iw:
        body_expr = (f'{ue.name}_pipe[{lat-1}][{ow-1}:0]' if lat > 0
                     else f'data_in[{ow-1}:0]')
    else:
        src = f'{ue.name}_pipe[{lat-1}]' if lat > 0 else 'data_in'
        body_expr = f"{{{ow-iw}'b0, {src}}}"

    with open(output_path, 'w') as f:
        f.write(f'''// ============================================================================
// {ue.name}_user_extern.sv
//
//   UserExtern<bit<{iw}>, bit<{ow}>>({lat}) {ue.name};
//
// PLACEHOLDER — REPLACE THE BODY WITH YOUR OWN LOGIC.
//
// This file was generated once and will NOT be regenerated or overwritten:
// once you edit it, it is your source file. Delete it to get a fresh
// placeholder back.
//
// THE CONTRACT YOU MUST KEEP
//   `result` must correspond to the `data_in` presented exactly {lat} clock
//   cycle{'s' if lat != 1 else ''} earlier — no more, no less, every cycle, with no back-pressure
//   and no variable latency. processing_generated does not inspect this
//   module: it presents data_in, then holds the entire rest of the packet
//   context (headers, metadata, locals, valid) in step for {lat} cycle{'s' if lat != 1 else ''} and
//   reads `result` on the far side. If your block takes a different number of
//   cycles, change fixed_latency_in_cycles in the P4 source and recompile —
//   do not absorb the difference here, because the packet context around you
//   will not move with it.
//
//   `valid_in` marks a real packet in the presented cycle. It is provided so
//   stateful blocks only update on real traffic; a purely combinational or
//   feed-forward block may ignore it. Note that `result` is read on the
//   {lat}-cycle boundary regardless of valid_in.
//
// THE PLACEHOLDER BEHAVIOUR
//   A {lat}-deep shift register: the identity function, delayed by the
//   declared latency{'' if ow == iw else f', then {"truncated" if ow < iw else "zero-extended"} from {iw} to {ow} bits'}.
//   It is latency-correct, so the generated pipeline elaborates, simulates and
//   synthesizes as-is — it simply does not compute anything useful yet.
// ============================================================================
`timescale 1ns/1ps

module {ue.name} (
  input  logic                clk,
  input  logic                rst_n,
  input  logic                valid_in,
  input  logic [{iw-1}:0] data_in,
  output logic [{ow-1}:0] result
);

''')
        if lat > 0:
            f.write(f'  logic [{iw-1}:0] {ue.name}_pipe [0:{lat-1}];\n\n')
            f.write('  integer _i;\n')
            f.write('  always_ff @(posedge clk) begin\n')
            f.write('    if (!rst_n) begin\n')
            f.write(f'      for (_i = 0; _i < {lat}; _i = _i + 1)\n')
            f.write(f'        {ue.name}_pipe[_i] <= {iw}\'b0;\n')
            f.write('    end else begin\n')
            f.write(f'      {ue.name}_pipe[0] <= data_in;\n')
            if lat > 1:
                f.write(f'      for (_i = 1; _i < {lat}; _i = _i + 1)\n')
                f.write(f'        {ue.name}_pipe[_i] <= {ue.name}_pipe[_i-1];\n')
            f.write('    end\n')
            f.write('  end\n\n')
        else:
            f.write('  // fixed_latency_in_cycles = 0: purely combinational.\n\n')
        f.write(f'  assign result = {body_expr};\n\n')
        f.write('endmodule\n')
    return 'created'
