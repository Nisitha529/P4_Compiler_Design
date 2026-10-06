# Toolchain Constraints — what is actually required, and by which tool

**Status: measured 2026-10-04.** Every claim here comes from running the pattern
through the tool, not from reasoning about it. Where a row says PASS, a probe
compiled and produced the right value.

## Why this document exists

The emitters avoid a number of RTL shapes, and until now each avoidance was
justified only by a comment at its own site saying "iverilog breaks otherwise."
That was a fair description of how each was found and a poor description of what
is true, for three reasons:

- it could not distinguish **illegal SystemVerilog** from **a tool's limitation**;
- it gave no way to tell whether a workaround was still needed;
- it implied one tool was dictating the design, when in fact the constraints come
  from three tools that disagree with each other.

The honest summary is the opposite of what the accumulated comments suggested:
**almost none of these patterns is actually broken.** Nine of eleven are accepted
by all three simulators. The real constraints are few, specific, and in two cases
come from Vivado rather than iverilog.

## Ground truth: the probe matrix

`verification/toolchain_probes/` holds one self-checking module per pattern.
`verification/toolchain_probes/run.sh` runs each through iverilog 11, Vivado
2020.2 `xsim` and Verilator 5.006 and classifies the outcome as PASS, WRONG
(ran, wrong value), STALL (never finished) or REJECT (refused to compile).

| Pattern | iverilog 11 | Vivado xsim | Verilator 5 |
|---|---|---|---|
| Variable part-select as an **lvalue** in `always_comb` | PASS | PASS | PASS |
| …same, with both sources driven by `always_comb` | PASS | PASS | PASS |
| Unpacked array read at a **computed** index in `always_comb` | PASS | PASS | PASS |
| Two write loops over one unpacked array in one `always_comb` | PASS | PASS | PASS |
| `always_comb` that writes a variable then reads it back | PASS | PASS | PASS |
| Unpacked array element in a **continuous assign** | PASS | PASS | PASS |
| Bit-select of an `int` loop variable | PASS | PASS | PASS |
| Two procedural blocks writing one unpacked array | PASS | PASS | PASS |
| **`break` in a `for` loop** | **REJECT** | PASS | PASS |
| **`automatic` variable in `always_comb`** | **REJECT** | PASS | PASS |
| **Identifier used before its declaration** | PASS | **REJECT** | PASS |

So there are exactly **three** hard language-level constraints, and they pull in
opposite directions:

1. **iverilog 11 rejects `break`/`continue`.** Restructure the loop.
2. **iverilog 11 rejects `automatic` inside `always_comb`.** Use a plain
   block-scoped variable.
3. **Vivado `xvlog` rejects a use that precedes the declaration** —
   `[VRFC 10-3380]`. iverilog and Quartus both accept the forward reference.
   This is the one that bites most often, because the emitters build a module
   top-to-bottom and it is natural to reference something emitted later.

Everything else in the list is legal, portable, and simulates identically in all
three tools. Where the emitters still avoid such a pattern, the reason is not the
pattern itself (see below).

## The conflict, and how it is resolved

The length-changing deparser's output-image block reads `hdr_out`. Two tools
disagreed outright about where that block may go:

- `xvlog` **requires** it after `hdr_out`'s declaration, or it will not compile;
- iverilog **stops advancing simulation time** if the block is moved below
  `hdr_out`'s `always_comb`.

Neither will budge, and for a while the design simply could not satisfy both.
The resolution is that the two tools are constraining different things:
SystemVerilog requires the **declaration** before the use, not the **driver**. So
`hdr_out`'s declaration is hoisted above the image block while its driver stays
where its commentary belongs, and both tools are satisfied. The same move fixes
`clearing` in the table and `QCOUNT`/`QSEL_W` in the shell.

**The general rule for the emitters: declare early, drive where it reads best.**

## What is still avoided, and why

These are **not** language constraints. They are shapes that made *this specific
design* stall under iverilog, and in each case the minimal probe passes, so the
trigger is contextual rather than inherent:

- the output image is built by a `case` over achievable `hdr_delta` values rather
  than a computed offset;
- `oimg` (unpacked, for the overlay's element writes) is copied to `oflat`
  (packed) for the beat assembly to read at a variable offset;
- the beat assembly's lanes are unrolled;
- `hdr_delta` is registered at capture rather than derived at TX.

**The honest status of these four is "empirically necessary here, cause not
isolated."** Each was adopted because reverting it made the real design stall and
reinstating it made the stall go away — reproduced more than once, including the
revert experiment. A minimal reproduction has *not* been built, so none of the
four should be described as a known iverilog bug, and the earlier claim in
`compiler_design.md` that each of these patterns "stops simulation time dead" was
wrong as a general statement and has been corrected.

Two things make this much less worrying than it reads:

- All four are **also reasonable hardware**. Unrolled lanes, a registered
  per-packet constant, and a packed vector for a wide variable-offset read are
  what you would write for synthesis anyway. None is a contortion that only a
  simulator would want.
- The design now **passes under a second, independent simulator**, so these
  shapes are not a private arrangement with iverilog.

If someone wants to retire one, the method is in `compiler_design.md`: revert it,
run `scripts/regress.sh`, and if it stalls use the heartbeat plus the per-net spin
counter to name the oscillating net before concluding anything.

## The declare-early rule, in practice

It has now bitten five times, and **every time only under xvlog** — iverilog
accepted all of them:

| Identifier | Used by | Fixed by |
|---|---|---|
| `clearing` | the table's query pipeline | hoisting the declaration (`emit_table.py`) |
| `hdr_out` | the length-changing output image | hoisting the declaration (`emit_top.py`) |
| `QCOUNT` / `QSEL_W` | the multicast slot state | hoisting the localparams (`emit_top.py`) |
| `saw_delta` | a testbench task | hoisting the declaration (`tb_lenprobe_top`) |
| a Digest's `push`/`data`/`overflow`/`wr`/`rd` | `u_proc`'s port list, **and** the AXI4-Lite read decoder | emitting the whole FIFO before both |

The digest case is the instructive one, because the obvious fix was not enough.
Hoisting only `push`/`data` above the `u_proc` instantiation cleared that error
and immediately produced the next one: the read decoder reads the FIFO's
`overflow`/`wr`/`rd` for its status word, and that decoder is emitted *earlier
still*. The whole block had to move ahead of both consumers.

Two habits follow:

- When adding state that the control plane can read, ask **where the decoder is
  emitted** relative to it. The AXI4-Lite decoder comes early; most extern
  storage comes late. Anything the decoder reads has to be declared before it.
- xvlog reports only the **first** such error per module, so clearing one tells
  you nothing about the next. Re-run until it is clean rather than assuming the
  class is dealt with.

And one process note: after any emitter change, **compile the generated file**
rather than trusting the generator's exit status. A generation that stops partway
leaves a truncated, syntactically-unbalanced `.sv`, and iverilog reports that as
`syntax error` on the file's **last** line with `I give up` — which looks like a
problem in whatever file came last on the command line, not like truncation. If a
syntax error points at `endmodule`, check the file's length first.

## Diagnostics worth not filtering

Two iverilog warnings were being discarded by the build scripts, and both carry
real information:

- **`always_comb process has no sensitivities`** — a block whose right-hand sides
  read only constants gets an empty sensitivity list, which iverilog runs as a
  delay-free infinite loop. This is a genuine, immediate cause of simulation time
  stopping. The shipping design has none; it was found because a probe
  accidentally contained one.
- **`sorry: constant selects in always_* processes are not currently supported
  (all bits will be included)`** — iverilog cannot narrow the sensitivity of a
  variable bit/part-select, so it adds the whole vector. For a **read** that is
  merely conservative. It becomes a hazard only when the over-included signal is
  also **written** by the same block, because the block then becomes sensitive to
  its own output. `fiveTuple` emits 1191 of these across 8 signals, all benign
  reads.

Do not blanket-filter iverilog's output. Filter the two known-harmless strings by
name and read the rest.

## Running the checks

```bash
# both simulators, whole suite
scripts/regress.sh --sim all

# the pattern probes
verification/toolchain_probes/run.sh

# Quartus (synthesis-only constraints: multi-driver, inference, timing)
quartus_map --read_settings_files=on generated/fiveTuple/fiveTuple
```

Tool locations on this machine: iverilog `/usr/bin`, Vivado 2020.2
`/tools/Xilinx/Vivado/2020.2/bin` (override with `VIVADO_BIN`), Verilator
`/usr/local/bin`, Quartus 25.1std `/data/intelFPGA_lite/25.1std/quartus/bin`,
p4c `/home/nisitha/p4c/build`.

## Constraints that are synthesis-only

Simulators accept these; Quartus does not. They are not visible to any check
above, so `quartus_map` remains a required step.

- **Two procedural blocks writing one array is a multi-driver.** All three
  simulators resolve it; Quartus refuses to map it.
- `altshift_taps` inference on long register chains, and `ramstyle` on the header
  buffer — see `compiler_design.md`.
