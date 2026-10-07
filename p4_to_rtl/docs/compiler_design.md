# The P4-to-RTL Compiler — How It Works

*Written for someone picking up the driving seat: what the compiler does, how it
is put together, where the sharp edges are, and how to change it safely.*

This is the orientation document. The `docs/*_plan.md` files are the **history**
— what was built when, what broke, and what the numbers were. Read this first;
go to the plans when you want to know *why* a decision went the way it did.

---

## 1. What this thing is

It takes a **P4 program** and emits **synthesisable SystemVerilog** for an FPGA:
a packet-processing pipeline plus the shell that feeds it (AXI4-Stream in and
out, AXI4-Lite for the control plane). The generated design has been through
real Quartus synthesis, place-and-route and timing analysis on a Cyclone IV
(DE2-115), not just simulation.

It is **not** a general P4 compiler. It handles a deliberate subset, documented
in `docs/supported_p4_subset.md` and summarised in §8 here. The guiding rule
throughout has been: *declare only what compiles, and verify everything that is
declared.*

### The flow, in one picture

The compiler does four things in order. Each box below is a real file you can
open, and each arrow is a data structure you can print.

```
  ┌────────────────────────────────────────────────────────────────────────┐
  │ 1. LET p4c DO THE LANGUAGE                                             │
  │    We never parse P4 ourselves. p4c desugars it -- resolves types,     │
  │    inlines controls, lowers if/else, numbers the actions -- and we     │
  │    read its OUTPUT. This is why the compiler is ~13k lines of Python   │
  │    and not a language front end.                                      │
  └────────────────────────────────────────────────────────────────────────┘
         my_app.p4
            │
            ├── p4test       (XSA / P4RTL programs)  ──▶  MidEnd IR as TEXT
            └── p4c-bm2-ss   (v1model programs)       ──▶  bmv2 JSON
                                   │
  ┌────────────────────────────────┼───────────────────────────────────────┐
  │ 2. NORMALISE INTO A HARDWARE-SHAPED IR                                 │
  │    Two readers, one IR. Everything downstream is architecture-blind.   │
  └────────────────────────────────┼───────────────────────────────────────┘
                                   ▼
                    ingest_p4ir.py   /   ingest_bmv2.py
                                   │
                                   ▼
                      ┌─────────────────────────┐
                      │   hardware IR (ir.py)   │   headers + field widths
                      │                         │   tables + keys + match kind
                      │   ~425 lines, no        │   actions + bodies
                      │   P4 semantics left     │   externs (Register, Counter…)
                      └─────────────────────────┘   parse graph + layout offsets
                                   │
  ┌────────────────────────────────┼───────────────────────────────────────┐
  │ 3. EMIT ONE FILE PER THING                                             │
  │    No emitter knows about another. Each owns one output file.          │
  └────────────────────────────────┼───────────────────────────────────────┘
            ┌──────────────┬───────┴────────┬──────────────┬─────────────┐
            ▼              ▼                ▼              ▼             ▼
    emit_processing   emit_table      emit_top       emit_counters  emit_selftest
    the match-action  one module      the SHELL:     one module     on-chip
    pipeline, split   PER TABLE,      RX, parser,    per Counter    traffic gen
    into stages       with its own    TM, deparser,                 so a board
                      CP window       TX, AXI-Lite   emit_fifo      run needs no
                                                     pkt_beat_buf   external kit
                                   │
  ┌────────────────────────────────┼───────────────────────────────────────┐
  │ 4. WRITE A BUILDABLE DIRECTORY                                         │
  └────────────────────────────────┼───────────────────────────────────────┘
                                   ▼
            generated/<app>/  *.sv  +  <app>.qsf / .sdc  +  testbench/
```

### A worked example: one table becomes three things

Write this in your P4 program:

```p4
action set_port(PortId_t p) { standard_metadata.egress_port = p; }
table l2 {
    key     = { hdr.eth.dst : exact; }
    actions = { set_port; NoAction; }
    size    = 1024;
}
apply { l2.apply(); }
```

and the compiler produces exactly three things for it:

| What | Where | Contains |
|---|---|---|
| **a storage module** | `l2_table.sv` | XOR-fold hash → BRAM, the key/action/parameter memories, the hit compare, and a control-plane write/query port |
| **an instance + a stage** | `processing_generated.sv` | `u_l2` instantiated, the lookup wired to the key field, and the `apply` turned into `case (l2_act_id)` with `set_port`'s body inlined. The table's latency becomes a **pipeline-stage boundary**, so everything after it is re-registered |
| **a control-plane window** | `<app>_top.sv` | AXI4-Lite registers to write an entry (key, action id, parameters, then commit) and to query or delete one |

Change `exact` to `lpm` and only the first of those changes: `l2_table.sv`
becomes a registered priority tree with per-entry prefix masks instead of a hash
and a BRAM. The pipeline and the control plane are unaffected.

### What comes out, at run time

The generated shell is a packet pipeline with the match-action stages in the
middle and the payload routed around them:

```
  AXI-Stream in ─▶ RX ─▶ PARSER ─▶ ╔═══════════════╗ ─▶ TRAFFIC ─▶ ╔═════════╗
                   │     (header     ║ INGRESS       ║    MANAGER    ║ EGRESS  ║
                   │      fields)    ║ MATCH-ACTION  ║    queues +   ║ MATCH-  ║
                   │                 ║  tables here  ║    scheduler  ║ ACTION  ║
                   │                 ╚═══════════════╝               ╚════╤════╝
                   │                                                      │
                   └── payload ──▶ pkt_beat_buf ───────────┐              ▼
                       (bypasses the pipeline entirely)    │          DEPARSER
                                                           ▼              │
                                   AXI-Stream out ◀── TX ◀─┴──────────────┘
```

Only the **header vector** goes through the tables; the payload is buffered
per slot and re-joined at TX. `p4src/arch/p4rtl.p4` carries the full version of
this diagram with every signal named.

We lean on `p4c` for parsing and all the hard language semantics, and only
consume its **already-desugared output**. That is why the compiler is ~13k lines
of Python instead of a language front end.

---

## 2. Repository layout

| Path | What lives there |
|---|---|
| `compiler/` | the compiler itself, plain Python 3, no dependencies |
| `compiler/boards/*.json` | per-board facts (device, vendor pragmas) |
| `p4src/arch/` | the P4 **architecture** definitions (see §3) |
| `p4src/apps/` | the P4 **programs** — real apps and small test fixtures |
| `generated/<app>/` | everything the compiler emits for that app, plus its testbenches |
| `rtl/` | a small amount of **hand-written** RTL (AVMM↔AXI-Lite bridge, common bits) |
| `docs/` | this file, plus the per-phase plans and their measured results |

Generated files are committed. That is intentional: it makes every compiler
change show up as a reviewable RTL diff, which is how several real bugs were
caught.

---

## 3. The three architectures

In P4, the *architecture* is the contract between the program and the target: what
controls exist, what metadata they see, what externs they can call. This project
supports three, and which one a program `#include`s decides almost everything
about how it is compiled.

| | `v1model.p4` | `xsa.p4` | **`p4rtl.p4`** |
|---|---|---|---|
| Whose it is | bmv2's, standard | Xilinx's `XilinxPipeline` | **ours** |
| Front end used | `p4c-bm2-ss` → JSON | `p4test` → MidEnd text | `p4test` → MidEnd text |
| Package | `V1Switch(...)` | `XilinxPipeline(...)` | `P4RtlPipeline(...)` |
| Controls | parser, ingress, egress, deparser, 2 checksum | parser, **one** MatchAction, deparser | parser, **ingress**, **egress**, deparser |
| Gets the AXI shell? | **no** — module-level only | yes | yes |
| Traffic manager? | no | no | **yes** |
| Status | kept as a regression reference | working, superseded | **where new work goes** |

**Why three.** v1model came first and its apps are still the reference that
proves the match-action emitters produce correct packet processing — but there is
no top-level shell for it, so those apps are only ever tested at module level.
`xsa.p4` was adopted to get a real, synthesisable top. It turned out to be
missing things we needed (no `egress_port`, no egress stage, no real port model),
so `p4rtl.p4` is the project-owned architecture that fixes those. See
`docs/architecture_proposal_v1.md` for the reasoning and the PISA comparison.

**`p4rtl.p4` standard metadata** — the grouping *is* the contract:

| Field | Width | Written by | Read by | Notes |
|---|---|---|---|---|
| `ingress_port` | 9 | shell, at **start of packet** | ingress, egress | a top-level input |
| `packet_length` | 16 | shell, at **tlast** | either | reading it forces **store-and-forward** for that app |
| `ingress_timestamp` | 64 | shell, at **start of packet** | either | free-running cycle counter |
| `parsed_bytes` | 16 | shell, at issue | either | bytes consumed by `extract()` |
| `parser_error` | — | shell, from `verify()` | either | `error` enum, width from the program |
| `enq_qdepth` | 19 | traffic manager, at enqueue | egress | 0 in ingress — not queued yet |
| `deq_qdepth` | 19 | traffic manager, at dequeue | egress | 0 in ingress |
| `drop` | 1 | pipeline | shell | **sticky** across ingress→egress |
| `egress_port` | 9 | ingress | egress, shell sideband | selects the TM queue |
| `mcast_group` | 16 | ingress | shell | 0 = unicast; else replicate |

Every one of those has a real producer and a real consumer. That rule is why the
list is short.

---

## 4. The compiler, module by module

Roughly in the order they run. Sizes are a rough guide to where the complexity
is.

| Module | ~lines | Job |
|---|---:|---|
| `main.py` | 770 | CLI, architecture detection, front-end invocation, emitter orchestration |
| `ingest_p4ir.py` | 1360 | parse `p4test`'s MidEnd text → IR (the XSA / P4RTL path) |
| `ingest_bmv2.py` | 750 | parse bmv2 JSON → IR (the v1model path) |
| `ir.py` | 425 | the hardware IR: headers, tables, actions, externs, pipeline stages |
| `emit_processing.py` | 2440 | **the match-action pipeline** — the heart of the compiler |
| `emit_top.py` | 2800 | **the shell** — AXI interfaces, slot ring, traffic manager, deparser overlay |
| `emit_table.py` | 1330 | one module per table (exact / LPM / ternary) with its control-plane port |
| `emit_selftest.py` | 785 | an on-chip traffic generator/checker, so a board run needs no external tester |
| `timing_model.py` | 490 | cost estimates used by the pipeline-stage budget splitter |
| `emit_parser.py` | 347 | a standalone parser FSM (see the note in §5 — the top does not use it) |
| `emit_counters.py` | 167 | one storage module per `Counter` extern |
| `emit_fifo.py` | 153 | `pkt_beat_buf` — the per-slot payload buffer |
| `emit_user_extern.py` | 116 | a **placeholder** body for each `UserExtern`, written once and never overwritten |
| `emit_deparser.py` | 114 | a standalone deparser (also unused by the top — see §5) |
| `emit_constraints.py` | 99 | `.qsf` / `.sdc` skeletons from the board descriptor |
| `crc_model.py` | 89 | reference CRC used to generate and verify the hardware CRC network |
| `emit_pkg.py` | 60 | the SystemVerilog package of shared types |

### What `emit_processing.py` actually does

This is where most of the subtlety is. It turns one P4 control into one
`processing_generated.sv` (or `egress_processing_generated.sv`):

- **Flattens** actions into the apply block — no call hierarchy survives.
- **Splits the block into pipeline stages.** Every table lookup takes a cycle, so
  the statements after it must run a cycle later. Registers are inserted at each
  boundary, and *every* value still needed downstream is forwarded through them.
  The `timing_model.py` budget can force extra splits on long combinational runs.
- **Two naming pools.** Header/metadata *reads* keep their bare port name in
  stage 0 and get `__stN` copies later; `out_*` pass-through copies and `drop`
  land on the real ports in the *last* stage. They are disjoint sets, which is
  what makes an arbitrary number of stages work.
- **Condition forwarding.** An `if` whose body lands two or more stages later
  needs its condition re-registered at every boundary in between. Getting this
  wrong silently skipped whole `if` blocks — see the streaming-shell plan, step 3.
- **Externs** are lowered in place: CRC networks are unrolled into flat XOR trees
  at emit time, `InternetChecksum` becomes an adder tree, `Counter.count()`
  becomes a one-cycle request to a separate storage module, `Register` becomes a
  memory with staged read/write, and `UserExtern` becomes an instantiation with a
  fixed-latency contract.

Two interface quirks you will meet:

- `valid_out` is registered **one cycle after** `out_*`. `out_valid` is the
  aligned one. Both exist because ten-plus older testbenches assert `valid_out`'s
  exact edge count; the shell uses `out_valid`. Collapsing them is an open
  cleanup.
- Register writes are gated with the pipeline valid of the stage the write lives
  in. Without that they fire every idle cycle — harmless for a Bloom filter,
  corrupting for anything read-modify-write.

---

## 5. The generated design

```
<app>_top.sv                         ← the shell (emit_top.py)
├── parser?                          ← NOT instantiated; see the note below
├── processing_generated.sv          ← ingress match-action
├── egress_processing_generated.sv   ← egress match-action (P4RTL only)
├── <table>_table.sv        (one per table)
├── <Counter>_counter.sv    (one per counter extern)
├── <UserExtern>_user_extern.sv      ← your code goes here
└── pkt_beat_buf.sv                  ← per-slot payload buffer
```

**A note that will otherwise confuse you:** `parser_generated.sv` and
`deparser_generated.sv` are emitted but the top does **not** instantiate them.
The shell extracts header fields itself, directly out of the packet buffer at
layout offsets, and rebuilds the output by overlaying the modified PHV back onto
the received bytes. That is a second lowering of the same parse graph, and it is
the one that runs. The standalone modules are kept because they are independently
testable and document the parse graph. `deparser_generated.sv` also has a known
fixed-slot bug that nothing hits because nothing uses it.

### The shell, end to end

```
 s_axis ─► RX ─► slot ring ─► issue ─► INGRESS ─► enqueue
                                                    │
                                          traffic manager: N queues
                                          + round-robin scheduler
                                                    │
                                         dequeue ─► EGRESS ─► capture
                                                    │
                        deparser overlay ─► TX ─► m_axis
```

Key ideas, each of which exists for a measured reason:

- **Slot ring.** `--nslot` packets in flight (default 4, **must be a power of
  two** — the pointers carry a wrap bit and the compiler now rejects anything
  else). Headers are random-access per slot; each slot has its own payload buffer.
- **Cut-through.** A packet is issued to the pipeline as soon as its *headers*
  have arrived, not the whole frame. `s_axis_tready` drops only when the shell is
  genuinely full. The exception is an app that reads `packet_length`, which
  cannot know its answer until `tlast` — such an app is store-and-forward.
- **`pkt_beat_buf` is re-readable.** Reads advance a pointer without consuming;
  `rewind` restarts a packet from beat 0 and `clear` empties it. This is what
  makes multicast possible — it was a FIFO once, and the second copy of a
  replicated packet found it empty.
- **The traffic manager** is the queueing point between ingress and egress:
  descriptor FIFOs of slot IDs, one queue per output port, a rotating-priority
  scheduler, `enq_qdepth`/`deq_qdepth`, optional tail drop (`--tm-qlimit`), and
  multicast replication. Dequeue is deliberately throttled (`TM_INFLIGHT`) —
  otherwise nothing ever waits in a queue and the scheduler has no choice to make.
- **Egress runs after the TM**, fed from the slot. That is what lets each
  multicast copy have its own `egress_port` and its own per-port rewrites.
- **Order.** Within a queue, arrival order. Across queues, the scheduler's order —
  the shell reorders, and that is intended.

### Control plane

One AXI4-Lite slave. Each table gets a 256-byte / 64-word window
(`TABLE_AXIL_SZ = 0x100`) laid out
as: index, action id, key fields, prefix length (LPM) or masks (ternary), action
parameters, then a **commit** word whose write performs the update. Counters get
a query window; the replication member table gets one too. The exact word offsets
for an app are in the `14'dN:` case labels in its `<app>_top.sv` — that file is
the authoritative register map, and the testbenches read it that way.

---

## 6. Running it

```bash
# XSA / P4RTL apps need p4test; v1model apps need p4c-bm2-ss
export P4TEST=~/p4c/build/backends/p4test/p4test
export P4C=~/p4c/build/p4c-bm2-ss

cd compiler
python3 main.py <app>                              # architecture auto-detected
python3 main.py load_balance_p4rtl --board de2-115 --self-test
python3 main.py <app> --nslot 8                    # deeper slot ring
python3 main.py <app> --tm-qlimit 2                # enable tail drop
```

Useful flags: `--nslot` (power of two), `--axi-data-width`, `--register-ram`
(infer BRAM for `Register`), `--exact-match-ways`, `--board`, `--self-test`,
`--tm-qlimit`, `--target-freq-mhz`, `--frontend` (override detection).

### Simulating

Icarus Verilog. The pattern is always: the app's package first, then its
non-selftest sources, then the testbench.

```bash
cd generated/<app>
iverilog -g2012 -o sim <app>_pkg.sv $(ls *.sv | grep -v '_pkg\|selftest') \
         testbench/<tb>.sv && vvp sim
```

Every testbench prints `[PASS]`/`[FAIL]` lines and a `Results: N passed, M failed`
summary, so a regression script only has to grep for `0 failed`.

### Synthesising

```bash
quartus_map <proj> && quartus_fit <proj> && quartus_sta <proj>
```

Use `--self-test` for board runs: a bare AXI top needs ~721 pins and the DE2-115
has 523, so the self-test wrapper (on-chip generator + checker) is what actually
fits.

---

## 7. Verification

**40 testbenches, all passing.** Three layers, and the layering matters:

1. **Standalone module tests** — a table, a counter, the payload buffer, the CRC,
   the checksum. These pin a contract in isolation.
2. **Module-level app tests** — drive `processing_generated` directly. All the
   v1model apps live here (there is no shell for them): `firewall` 79,
   `load_balance` 54, `qos` 60, `mri` 50, `basic_tunnel` 44, `ecn` 33,
   `ternary_acl` 29, `multicast` 25.
3. **Top-level tests** — real AXI frames through the whole shell. This is where
   the interesting bugs were. `fiveTuple` 28, `load_balance_xsa_top` 22,
   `load_balance_p4rtl_top` 22, `egprobe` 26, `ioprobe` 18, `mcprobe` 15,
   `egprobe_tm` 10, `lmprobe` 10, `ecn_p4rtl` 9, plus the streaming harness.

**The probe apps are a deliberate technique.** `smprobe`, `regprobe`, `ueprobe`,
`egprobe`, `ioprobe`, `lmprobe`, `ecn_p4rtl`, `mcprobe` are small P4 programs
whose only job is to make one shell feature observable from the AXI interface.
When you add a feature, add a probe: it is much easier to debug than a real app
and it becomes a permanent regression.

**What the testbenches are careful about,** because each of these cost real
debugging time:

- Assert on **event counts** (tlasts, issues, captures, tx starts/finishes), not
  on sampled values at a guessed cycle. A "16 versus 17" mismatch located a
  phantom packet issue immediately.
- Probes at `posedge`+`#1` race a testbench that drives at `#1`. Use the
  data-aligned valid and count events.
- After the traffic manager, **output order is not arrival order**. Assert the
  invariant that actually holds: per-queue order, and per-port counts.

**Hardware results** (`load_balance_p4rtl`, self-test, DE2-115 / EP4CE115):
29,510 LE (26 %), 497,664 memory bits (13 %), **Fmax 67.5 MHz**. The critical
path is the `InternetChecksum` adder tree — application logic, not the shell. The
50 MHz board target closes comfortably; the 100 MHz figure in the generated
`.sdc` does not, and pipelining that checksum is the open item there.

---

## 8. What is supported, and what is not

**Supported:** headers and structs, a parser with `select` and `verify()`,
`exact` / `lpm` / `ternary` tables with actions and parameters, arithmetic and
bit manipulation, `isValid`/`setValid`/`setInvalid`, `InternetChecksum`,
`Checksum<H>` with a real CRC16, `Counter`, `Register`, `UserExtern`,
`standard_metadata` as its architecture declares it, and (P4RTL) the full
traffic manager.

**Not supported, on purpose:**

| Gap | Why |
|---|---|
| Dynamic header stacks (`hdr.x.next`, `.last`, `push_front`) | explicitly descoped |
| Anything that **changes packet length** (`setValid` on a new header, header push) | the header/payload split is at a fixed beat boundary; needs a byte shifter |
| `range` match kind | no demand; `exact`/`lpm`/`ternary` are what the emitters implement |
| `Meter`, `Digest` | declared in `p4rtl.p4`, **not yet ingested or emitted** |
| `clone`, `recirculate`, `resubmit` | need packet replication paths the shell does not have |
| A v1model top-level shell | v1model apps stay module-level; new work targets P4RTL |

That fifth row is worth knowing about: `p4rtl.p4` declares `Meter` and `Digest`
but nothing compiles them. This breaks the architecture's own rule #3 and is a
good first task — `Register<T,S>` was in exactly that state until recently and
produced RTL that referenced undeclared signals.

**Which real apps are still blocked, and by what** (surveyed, not assumed):

| app | blocked by |
|---|---|
| `mri`, `link_monitor` | header stacks **and** packet growth |
| `flowcache` | `setValid()` on a new header — packet growth |
| `multicast` (the v1model one) | now unblocked in principle — the TM does replication |

So the remaining structural gap is the **length-changing deparser**. Nothing else
in the metadata or extern area blocks a real app.

---

## 8b. Meter and Digest, and what the memory measurement actually showed

### Meter and Digest are implemented (2026-10-06)

Both were declared in `p4rtl.p4` and had no implementation, which is the worst
combination: a program could legally call either, the compiler exited 0, and the
call came out as a `/* UNIMPLEMENTED EXTERN */` comment. `p4src/apps/mdprobe.p4`
plus `tb_mdprobe_top` (13 assertions) exists so that cannot happen quietly again.

**Meter** is single-rate two-colour, one bucket per index, and the per-index
state is a **debit** rather than a token count. That is not a stylistic choice.
A token bucket has to start *full* — a fresh meter must pass traffic — but "full"
is `cp_burst`, a runtime value, and BRAM power-up content cannot be pre-loaded
with it. An initialiser would need a power-on fill FSM, and that FSM would be a
third accessor on the bucket memory, which costs a duplicate copy of the storage.
A debit starts at **zero**, which reset and a cleared BRAM already give, so the
first packet on every index is GREEN with no initialisation at all:

```
decay = (now - last_ts) >> cp_rate_shift     one unit per 2^shift cycles
debt  = max(0, stored - decay)
GREEN = debt < cp_burst                      then debt+1 is stored
RED   = debt >= cp_burst                     nothing is charged
```

The shift keeps a multiplier off the packet path. Cost is one unit per **packet**
(packet-rate policing); byte-rate would need `packet_length` plumbed in.
`cp_rate_shift` and `cp_burst` are per **instance**, not per index — one set of
knobs for the whole array — which is a real restriction, stated in `p4rtl.p4`.
The read-modify-write hazard is the same as `Register`'s, for the same reason.

**Digest** pushes into a 16-deep FIFO the control plane drains over AXI4-Lite
(`status` = overflow count + occupancy, then the data words, then a one-cycle
`pop`). A digest that is not drained fast enough **drops the newest entry and
counts it** rather than stalling: `pack()` is a notification, and it must never
apply backpressure to forwarding.

Two bugs found building it, both the same shape as earlier ones:

- the push was **ungated**, so it re-pushed every idle cycle and overflowed a
  16-deep FIFO inside one packet — the identical trap the register writes had.
- gating it on the module's `out_valid` fixed the overflow but read back **all
  zeros**, because the data packed is the *pack stage's* view of the packet and
  `out_valid` samples stages too late. The port is now a registered one-cycle
  pulse captured at the pack's own stage valid.

`MeterColor_t` also needed resolving to its 1-bit encoding in **both** `_map_expr`
and `_map_cond` (a policer is `if (colour == MeterColor_t.RED)`, so the condition
path matters), and the enum had to be added to the local-variable patterns in
*two* places in `ingest_p4ir.py` — the declaration parse and the `name_map`.
p4test renames `MeterColor_t c;` to `c_0` and records the original in `@name`,
so with only the first, the local was declared as `c` while every expression
still said `c_0`.

### Table memory: halved by inferring TRUE dual port (2026-10-07)

Every table memory used to be instantiated **twice**, which put `fiveTuple` over
the DE2-115: 555 M9K blocks against 432. It is now one copy each, and **runtime
readback is kept** -- nothing was given up.

| | before | after |
|---|---:|---:|
| M9K blocks | 555 / 432 (128 %) | **423 / 432 (98 %)** |
| Memory bits | 4,546,560 (114 %) | **3,465,216 (87 %)** |
| Logic elements | 71,015 (62 %) | **51,652 (45 %)** |
| RAM modes | 27 x Simple Dual Port | **10 x True Dual Port** + 9 Simple |

The logic saving was a side effect: the duplicate memories' address and control
logic went with them, and the reset-free registers below need no reset network.

**What was actually wrong.** An M9K can be *simple* dual port (one write port,
one read port) or *true* dual port (two ports, each read **or** write). A table
needs one write and two reads -- the per-packet lookup and the control-plane
query -- which is three users but only **two accesses per cycle**, because the
two control-plane users never coincide. That fits true dual port exactly. Quartus
was choosing simple dual port, so each instance could serve only one reader and
it duplicated the storage to serve the other.

Two things were preventing the inference, and **both** have to be right:

1. **The control-plane port must be exactly two branches, write or read, and the
   write branch must also drive that port's read output.** That last part is how
   read-during-write behaviour gets declared; without it the port infers
   write-only and the query read becomes a second reader. Four branches (clear /
   write / delete / query-read) defeat inference *completely* -- Quartus gives up
   and tries to build the array from registers ("Cannot convert all sets of
   registers into RAM megafunctions"). The three write conditions are therefore
   merged into one `cp_wr` with a muxed address and muxed write data, and the
   power-on clear sweep moved to its own block.
2. **No reset on the lookup port's WIDE read-output registers.** A reset branch
   on a memory's read-output register stops true-dual-port inference on its own.
   `valid_r` keeps its reset (it feeds `hit`, which must be a defined 0 after
   reset) and is one bit wide; the key copies, action id and parameters are
   reset-free, which is safe because every consumer gates on `hit`.

Isolated on an 8192x32 array, which is how the cause was pinned down:

| probe | result |
|---|---|
| two-branch CP port, no reset on the read register | 262,144 bits -- 1 x True Dual Port |
| same, **plus a reset** on the read register | 524,288 bits -- 2 x Simple Dual Port |
| reset removed, `clearing ? ... :` ternary kept | 262,144 -- single, so the ternary is innocent |
| reset on `valid_r` only, wide registers reset-free | 270,336 -- single |

**Still outstanding: the counters.** They are duplicated by the same mechanism
(the 9 remaining Simple Dual Port instances include 4 counter copies, ~64
blocks). They are a harder case: their memory sees two writes (increment
write-back and the power-on clear) and two reads (the read-modify-write and the
control-plane query), and increments happen on most cycles, so a query read in a
two-branch template would have to **wait for a cycle with no increment** and hold
`cp_query_busy` until it got one. That is extra logic rather than a re-shape, and
the current 98 % memory figure leaves little headroom, so it is the obvious next
saving.

**Two process notes from getting this wrong twice first.** The earlier
conclusion recorded here -- that the duplication was the unavoidable price of
runtime readback -- was wrong, and it was reached by reasoning about port counts
instead of testing a template. A 15-line probe plus `quartus_map` settled it in
minutes. And `quartus_map` alone is not enough for memory questions: it reports a
pre-fit estimate with `AUTO` block types and double-counts instances. Only
`quartus_fit` gives real M9K counts.

## 9. Sharp edges — read before you write RTL generators

These all cost hours. They are in the generated-code comments too, but here they
are together.

### Icarus Verilog (the simulator, v11)

- No `break`, no `continue`. Put the bound in the loop condition.
- No `automatic` variables inside `always_comb`.
- No bit-select of an `int` loop variable (`k[0]`) — use `k % 2`.
- Declarations go at the **top** of a block.
- Never read an **unpacked array element in a continuous assign**. Use
  `always_comb`.
- No unpacked structs; `fork…join_any` + `disable fork` crashes `vvp`; no
  `real'()` cast; queue pops must be `x = q.pop_front()`.
- **Simulation time stopping dead** — no error, no output, the clock simply
  stops. This has happened six times, and the shapes involved are listed below.
  **Read `docs/toolchain_constraints.md` before treating any of them as a rule:**
  every one was isolated into a standalone probe and run through iverilog, Vivado
  `xsim` and Verilator, and *nine of eleven patterns pass in all three*. So these
  are not "patterns that break iverilog" — they are shapes that stalled **this
  design**, for reasons not yet isolated to a minimal case:
  1. An `always_comb` that writes a variable and then reads it back.
  2. An `always_comb` indexing an array with a value that arrives
     *combinationally* from `processing_generated`'s output. Register the index.
  3. An `always_comb` reading per-slot state written by an `always_ff` whose
     condition depends on that same block's output. Register the result.
  4. A variable part-select as an lvalue — `data[i*8 +: 8] = ...` in a loop.
     Unrolling the loop fixed a real stall; the isolated pattern is fine.
  5. Reading an unpacked array at a computed index inside `always_comb`. Staging
     through a packed copy fixed a real stall; the isolated pattern is fine.
  6. A second write loop over the same unpacked array in one `always_comb`.
     Collapsing to one unconditional loop fixed a real stall; isolated, fine.

  Items 4–6 came out of the length-changing deparser. An earlier revision of this
  document asserted each one "stops iverilog advancing simulation time"; the probe
  matrix shows that is **wrong as a general claim**, and the honest statement is
  the one above. What all six have in common is a block that ends up sensitive to
  something it writes — that mechanism is real, but which construct triggers it
  depends on context.

  Two genuine, isolated language constraints *were* confirmed, and they are the
  only ones: iverilog 11 rejects **`break`/`continue`** and **`automatic` inside
  `always_comb`**. A third comes from the other direction — Vivado's `xvlog`
  rejects **an identifier used before its declaration**, which iverilog and
  Quartus both accept. Declare early; drive where it reads best.

- **Finding a stall.** Two tools make this much shorter than guessing:
  - a heartbeat — `initial forever #N $display("t=%0t", $time);` — separates a
    **time stall** from a **logic deadlock** (a testbench waiting on a packet that
    never arrives). They are indistinguishable from the outside.
  - a per-net spin counter — `always @(sig) bump(...)` printing once a count
    crosses a threshold — **names** the oscillating net: the one spinning while
    everything upstream of it is stable. This found the length-changing stall in
    one run after a dozen failed guesses.

  Then stub the suspect expression to a constant and see whether time advances.

- **Do not blanket-filter iverilog's warnings.** Two were being discarded by the
  build scripts and both carry real information: `always_comb process has no
  sensitivities` is a genuine delay-free infinite loop, and `sorry: constant
  selects ... all bits will be included` means the sensitivity list was widened to
  the whole vector — harmless for a read, a self-trigger if that signal is also
  written by the block. Filter those two by name and read the rest.

- **A variable part-select lvalue can corrupt data rather than stalling.**
  `hdr_out_flat[q*8 +: 8] = hdr_out[q]` silently duplicated four bytes of a
  shifted packet tail and looked exactly like a logic bug for a whole session.

### Two bugs the bmv2 path hid, and what they have in common

Both were found by running the suite under a **second simulator** and then
chasing a port-width warning that had been dismissed as cosmetic. Both lived in
the v1model/bmv2 frontend path, and both made a table silently never match --
the worst failure shape, because a miss looks like "no matching entry".

**1. A table keyed on user metadata got an undeclared signal.**
bmv2 reports such a key as `['scalars', 'metadata.<field>']`. The *expression*
path in `ingest_bmv2.py` normalised that to `meta.<field>`; the *table-key* path
did not -- it assumed every `scalars` entry was a control-local temporary and
passed the name through verbatim. The key was then wired to
`metadata_<field>`, which nothing declares, so it became an **undriven implicit
1-bit wire**. `load_balance`'s entire ECMP next-hop lookup was dead this way.
Both paths now share `_scalars_field()`.

**2. The key-staging fixup did not count extern writes.**
`_meta_key_producing_stage` decides whether a table's `meta.*` key must read the
stage-suffixed name (`meta_x_w__stK`) instead of the stage-0 input. It looked
only for an `Assignment` writing that field. In `load_balance` the field is
written by **`hash()`** inside `set_ecmp_select` -- an `ExternCall` with its
destination as the first argument -- so the analysis reported "produced at stage
0" and wired the key to the module input, which never carries the hash result.
`register.read` has the same shape and the same exposure. Both are now
recognised by `_extern_writes_meta()`.

**An out-parameter is a write.** That is the lesson worth carrying: any dataflow
analysis in this compiler that scans for `Assignment` needs to ask whether an
extern's out-argument can do the same job. The `xsa`/`p4rtl` paths were correct
all along, which is why this survived -- the only affected app was the one real
bmv2 application whose logic depends on a two-level lookup.

**Why no test caught it:** `tb_load_balance` never populated either ECMP table
and described them as "RTL-stubbed (hit always 0)". They were real, just empty.
Its 54 assertions could not see a broken key. Section 5 of that testbench now
populates both over their CP ports and drives a packet through the real
two-level lookup; it fails against the old RTL and passes against the fixed RTL.
**If a testbench calls part of the design a stub, check whether that is still
true before trusting the rest of the file.**

### Port width mismatches are not cosmetic

`tb_firewall` passed 194/194 under iverilog and failed 26 assertions under
Vivado `xsim`. The cause was a testbench declaring `logic [3:0] lpm_cp_idx` and
connecting it to an 8-bit port: **iverilog zero-pads the missing high bits,
xsim drives them `Z`**, so the control-plane write landed at an undefined
address and the table stayed empty. Wider-than-port connections merely truncate
and are harmless; **narrower-than-port is a real portability bug.** Treat
`Port N (x) of M expects A bits, got B` with `B < A` as an error, not a warning.

### Quartus (things simulation will not catch)

- **Two procedural blocks writing one array is a multi-driver.** iverilog accepts
  it silently; Quartus refuses to map it. Both the step-1 and step-2 traffic
  manager simulations were fully green before synthesis caught this. **Run
  `quartus_map` after any change that adds a writer to a slot array.**
- Quartus packs long forwarding-register chains into `altshift_taps` (M9K shift
  registers) and they became the critical path. The board descriptors carry a
  `shift_reg_pragma` (`AUTO_SHIFT_REGISTER_RECOGNITION OFF` on Altera,
  `shreg_extract = "no"` on Xilinx) that lifted Fmax 66 → 71 MHz.
- Do **not** put a `ramstyle` pragma on the header buffer. It was tried: Quartus
  fell back to a per-index comparator network and the design exploded past 2M
  ALUTs. The header buffer is read combinationally at dozens of runtime-computed
  offsets every cycle; it has to be registers.
- Quartus may reject a procedural `initial` loop over a large array
  ("must terminate within 5000 iterations"). Use
  `// synthesis translate_off`, which it honours, rather than `ifndef SYNTHESIS`.

### P4 front end

- `p4test`'s MidEnd dump leaves `#include <core.p4>` **unexpanded** and prints
  width-prefixed literals (`32w4096`, `16w3`). Strip the prefix or the regex
  silently fails to match — which drops a declaration while its call sites still
  emit, giving RTL that references undeclared signals.
- Name the header struct exactly `headers` and the metadata struct `metadata`.
  A `_t` suffix on the struct type triggers a known naming bug where every field
  port is named after the header *type* instead of the *instance*.
- Exact-match tables are direct-mapped by a nibble-XOR hash. When you pick test
  keys, check they do not collide — `0xDEAD` and `0xBEEF` do, which silently
  evicted a test's own entry.

---

## 10. How to do the common things

### Add a new app

1. Write `p4src/apps/<name>.p4`, including `"p4rtl.p4"` and instantiating
   `P4RtlPipeline`. Structs named `headers` / `metadata`.
2. Type-check it alone first — this catches most mistakes in seconds:
   ```bash
   p4test --std p4-16 -I ~/p4c/p4include -I p4src/arch p4src/apps/<name>.p4
   ```
3. `python3 main.py <name>` and read the `[DEBUG]` IR dump: are all the tables
   there, with the right match kinds? Any `UNIMPLEMENTED EXTERN` or `WARN`?
4. Elaborate before writing a testbench — it is a fast sanity gate:
   ```bash
   iverilog -g2012 -o /dev/null <app>_pkg.sv $(ls *.sv | grep -v '_pkg\|selftest')
   ```
5. Copy the closest existing top-level testbench and adapt it. `egprobe`'s is a
   good base (AXI helpers, table programming, a frame driver, a collector).

### Add a shell feature

Work in **small, separately verified steps** — this is the single most useful
habit in this codebase. Both times a step was built all at once, it ended in a
long hunt for a simulation stall; both times it was built incrementally, the
failing piece was obvious. For each step: regenerate, run the app's tests, then
run the full regression, then `quartus_map` if you touched slot state.

### Add an extern

1. Recognise the declaration in `ingest_p4ir.py` (mind the width-prefixed
   literals), and add a `[WARN]` for shapes you do not support — never drop a
   declaration silently.
2. Add the call-site lowering in `emit_processing.py`.
3. If it needs storage, give it its own module like `emit_counters.py` does.
4. Write a probe app and a standalone testbench.

### Run the whole regression

There is no committed runner script — the pattern is: for each app directory,
compile every `testbench/*.sv` against that app's non-selftest sources and grep
for `0 failed`. Worth committing one if you are going to iterate; it takes about
ten minutes on this tree.

---

## 11. Where to look next

Ranked by value, with the reasoning:

1. **Length-changing deparser.** The only remaining *structural* blocker for real
   apps (`flowcache`, and half of `mri`/`link_monitor`). Needs a byte shifter in
   the TX path.
2. **`Meter` and `Digest`.** Declared in `p4rtl.p4` and not implemented, which
   violates the architecture's own rule. `emit_counters.py` is the model.
3. **Pipeline the `InternetChecksum` adder tree.** It is the critical path; this
   is what would take Fmax past ~70 MHz.
4. **Collapse `valid_out` / `out_valid`.** Pure cleanup; touches ~10 testbenches.
5. **A committed regression runner**, and CI if you want it.

### The history, if you need the reasoning

| Document | Covers |
|---|---|
| `streaming_shell_plan.md` | the 4-step rewrite from one-packet-at-a-time to a streaming shell, with per-step numbers |
| `egress_stage_plan.md` | the ingress/egress split, PHV pass-through, and the arrival-metadata pass |
| `traffic_manager_plan.md` | queues, scheduler, qdepth, tail drop, replication — and the two false starts |
| `architecture_proposal_v1.md` | why `p4rtl.p4` exists, and the PISA/PSA comparison |
| `supported_p4_subset.md`, `ir_design.md`, `codegen_plan.md`, `verification_plan.md` | earlier design notes |

Each plan records what broke as well as what worked. The failures are the more
useful half.
