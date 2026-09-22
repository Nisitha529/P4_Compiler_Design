# Egress Stage with PHV Pass-Through — Implementation Plan

**Decision (2026-09-19):** after the streaming shell, add the ingress/egress
split with **PHV pass-through** — the egress control receives the parsed header
vector (PHV) and metadata exactly as ingress left them, and the packet is
never re-parsed. Same method as the shell: small steps, each isolating one
class of risk, every test green after every step.

## What the egress stage is here

PISA is `parser → ingress → traffic manager → egress → deparser`. The traffic
manager (queues per output port, replication) is what makes egress a distinct
stage: egress runs *after* the forwarding decision, once per output copy, and
sees `egress_port`. This project has one stream in and one stream out, so the
"traffic manager" is the streaming shell's slot ring: packets are already
queued in order between the pipeline and TX. The egress stage is therefore a
second match-action pipeline chained after the first:

```
RX → slot ring → [ingress processing] → PHV → [egress processing] → capture → TX
                        ↑ parsed fields                  ↑ same PHV, no re-parse
```

Why bother without a real TM:

1. **Portability.** Every P4 architecture in use (v1model, PSA, TNA) has an
   egress control; programs put per-port rewrites there (`send_frame` keyed on
   `egress_port`). p4rtl programs should be structured the same way so a TM
   can be inserted later without touching the program.
2. **Drop semantics.** An ingress drop means the TM discards the packet and
   egress never runs. The shell must honour that: egress side effects
   (counters) must not fire for a packet ingress dropped.
3. **The bmv2 apps.** `ecn`, `mri`, `link_monitor`, `multicast`,
   `load_balance` all have real egress controls; the p4test path could not
   express any of them.

**Why pass-through, not an egress parser (the decision):** re-parsing costs a
second parser and a second header buffer read for no information gain — the
PHV egress needs is exactly what ingress has. PSA's egress parser exists for
recirculation/clone metadata, which is out of scope. Pass-through also keeps
the header-length-in == header-length-out constraint unchanged.

## Contract

- `P4RtlPipeline<H,M>(Parser, Ingress, Egress, Deparser)`; both controls are
  `(inout H hdr, inout M meta, inout standard_metadata_t std)`.
- Egress `valid_in` is ingress `out_valid`; egress input PHV = ingress output
  PHV; user metadata and standard metadata pass through the same way.
- `drop` is **sticky**: ingress `drop` enters egress as `drop_in`, is carried
  through the egress stages, and egress can only set it, never clear it.
  Egress counter increments are gated with the incoming drop (egress did not
  "run" on a packet the TM discarded).
- `egress_port` is a standard-metadata field written by ingress, read by
  egress, and exposed on the shell as the sideband `out_std_meta_egress_port`.
- Latency adds: total = ingress stages + egress stages. Throughput unchanged
  (both are one-packet-per-cycle pipelines). Slot occupancy grows by the egress
  latency, so `--nslot` matters slightly more for minimum packets.

## Steps

| # | Change | Risk isolated | Green check |
|---|--------|---------------|-------------|
| 0 | `p4rtl.p4` grows `Ingress`/`Egress`; arch detection + control ingest for `P4RtlPipeline` | frontend | **done** |
| 1 | `egress_processing_generated` emitted on the p4test path: `drop_in`, sticky drop, gated counters | second processing module | **done** |
| 2 | Shell chains ingress → egress (PHV pass-through), captures on egress `out_valid`; regmap/counters from both controls | shell wiring, table-name collisions | **done** — 22/22 + 9/9 unchanged |
| 3 | Probe app `egprobe`: ingress drops some packets and sets `egress_port`; egress counts per port and rewrites a MAC | drop-gating, egress counters, egress_port sideband | **done** — 26/26; Quartus below |

## What landed (2026-09-20)

**Architecture.** `p4src/arch/p4rtl.p4`: `Ingress<H,M>` / `Egress<H,M>`
controls, `P4RtlPipeline<H,M>(Parser, Ingress, Egress, Deparser)`. The
proposal's validation probe grew an egress control; p4test exit 0.

**Frontend.** `main.py` and `ingest_p4ir.py` detect `P4RtlPipeline`;
`_extract_control_names` returns four names; the control walker became
`_ingest_control(text, name, stage, ir)` and runs for both controls, so
egress gets the same tables/actions/externs/apply support as ingress with
no second code path. Extern-call arguments are now read with paren
matching — `count((bit<4>)smeta.egress_port)` used to be truncated to
`(bit<4>` by a `[^)]*` regex (found by `egprobe`; would have hit any cast
inside any extern call).

**Egress module** (`emit_processing.py`, `drop_in=True` only on the p4test
path — bmv2 egress modules are byte-identical): `drop_in` input, seeds stage
0's `drop` (sticky), forwarded through the stages as a pool-B input, and
every `Counter.count()` in the module emits `incr_en = !drop_in` (renamed to
the stage's copy). `_collect_std_meta_outputs` now also walks the apply
block, so `smeta.egress_port = ...` outside an action gets its port.

**Shell** (`emit_top.py`). One new pointer, `ig_ptr`, between `iss_ptr` and
`cmp_ptr`: advances on ingress `out_valid`, the cycle the PHV is handed to
`u_egress`. Standard metadata rides in the slot ring, exactly as a TM would
carry it:

| field class | written to slot at | read by |
|---|---|---|
| shell-sourced, read by egress (`ingress_timestamp`, `parsed_bytes`, `parser_error`) | issue (`iss_slot`) | `u_egress.std_meta_*` via `ig_slot` |
| written by ingress (`egress_port`, …) | ingress completion (`ig_slot`) | egress input (live wire), TX sideband |
| written by egress | capture (`cmp_slot`) | TX sideband |

Capture (`cmp_ptr`) moves to egress `out_valid`; ingress counter requests
are captured at `ig_slot`, egress ones at `cmp_slot`, both applied at
release as before. The AXI4-Lite regmap covers both controls' tables and
counters (entries tagged `stage`; duplicate names across controls are a
compile error), and pipeline-written standard metadata leaves as
`out_std_meta_<field>` next to the user-metadata sideband. Single-control
apps are unaffected: every xsa app regenerates identically apart from a
removed duplicate `ingress_ts_ctr` driver (a pre-existing multi-driver that
iverilog tolerated).

**Apps.**
- `load_balance_p4rtl.p4`: `send_frame` and the IPv4 checksum in egress,
  `egress_port` as standard metadata. The load_balance_xsa top (22) and
  stream (9) testbenches pass unchanged (only the sideband port renamed),
  with identical cycle counts: ingress 4 + egress 2 boundaries = the xsa
  build's 6, so the split costs nothing here.
- `egprobe.p4` + `tb_egprobe_top.sv` (26 assertions): PHV pass-through
  (ingress retags `etype`, egress keys on the new value), sticky drop
  (ingress-dropped packet: no output, egress counter unchanged), egress's
  own drop (counted — egress ran), unmatched pass-through, a 12-frame
  back-to-back burst with both drop kinds interleaved (8 survivors, all
  counters exact, sideband ports in order), and `ingress_timestamp` read in
  egress being a per-packet issue-time sample (strictly increasing, 2–6
  cycles apart under back-to-back issue).

**Quartus** (load_balance_p4rtl selftest, DE2-115, NSLOT=4): **25,533 LE
(22 %), 17,902 registers, 275,712 memory bits, Fmax 74.1 MHz** — vs the
single-control xsa build's 25,510 LE / 71.3 MHz. The two-module chain costs
+23 LE and gains 2.8 MHz because the InternetChecksum adder tree (still the
critical path, now `u_egress|out_ipv4_*_s2 → slot_phv_ipv4_hdrChecksum`)
sits in a shallower module. 0 `altshift_taps`.

**Not done / next.** A real traffic manager (per-port queues, replication
for `mcast_group`) is the v2 item this stage was shaped for; `ingress_port`
and `packet_length` shell sources (§6 of the proposal; `packet_length`
forces store-and-forward for programs that read it in ingress, since the
shell issues cut-through at the header cutoff); porting the bmv2 apps with
real egress logic that fit the header-length constraint.

## Follow-on pass (2026-09-22): the arrival metadata, and two real bugs

Closing the remaining v1 §6 items turned up two defects that no existing test
could see.

**`Register<T,S>` was declared but not compilable.** `p4rtl.p4` declares
`Register<T, S>`; the ingest only matched the lowercase `register<bit<N>>`
spelling from the `xsa_ext.p4` overlay. The declaration was therefore dropped
while the `.read`/`.write` call sites still emitted `<name>_rd_*` /
`<name>_wr_*` references — the compiler exited 0 and the RTL failed to
elaborate on four undeclared signals. This broke the architecture's own stated
design rule #3. Now ingested natively (index width recorded; the address port
stays sized from `size`, so an out-of-range index wraps as bmv2 does), and a
`Register<T,S>` whose element type is not `bit<N>` is reported rather than
silently dropped.

**Register writes were never gated by packet validity.** `<reg>_wr_en` is
combinational from its stage's registers, which hold after a packet drains, so
it stayed asserted and rewrote the same address *every idle cycle*. Invisible
in every existing app — `firewall` and `regprobe` both write a constant, and
rewriting `1` is idempotent — but it corrupts any read-modify-write: an
accumulator re-accumulates once per cycle. `tb_lmprobe_top` caught it
immediately (64 B frame, total 128). The write-back is now
`if (<reg>_wr_en && <valid of the write's stage>)`.

**`parsed_bytes` was the wrong quantity.** It was wired to `slot_byte_len`, the
shell's running count of bytes *received* — so at a cut-through issue it
reported whichever beats had arrived (32 for every frame at the default width),
not bytes consumed by `extract()`. It is now `cutoff_byte`, which is exactly
the extracted-header extent for this packet's parse path.

**`ingress_port`** is a top-level input, sampled at **start of packet** into
the packet's slot. Issue is cut-through and runs behind RX, so a live read at
issue can belong to a later packet; `tb_ioprobe_top` T4 changes the port on
every frame of a back-to-back burst to pin this. `ingress_timestamp` moved to
the same SOP sampling, which is what `p4rtl.p4` always claimed it was.

**`packet_length`** is the whole frame, known only at tlast. A program that
reads it has `iss_hdr_ready = slot_done[iss_slot]` — **store-and-forward for
that app**, cut-through for every app that does not.

### New fixtures

| fixture | covers | assertions |
|---|---|---|
| `ioprobe` | `ingress_port` (incl. SOP sampling under a burst), `packet_length` at four sizes and as a drop decision, `parsed_bytes` size-independence; also a P4RtlPipeline app with an **empty egress** | 18 |
| `lmprobe` | `Register<T,S>` + `packet_length` + egress state keyed by `egress_port`; measures the register read-after-write distance on both read paths | 10 |

**Quartus** (lmprobe selftest, DE2-115, NSLOT=4): 5,039 LE (4 %), 3,325
registers, 270,880 memory bits, **Fmax 89.0 MHz** — the egress `Register`
array infers as memory and is not on the critical path (that is the shell's
`tx_out_keep → write_cursor`). Store-and-forward issue costs latency, not
Fmax.

### `link_monitor` cannot be ported — and neither can the rest

The plan named `link_monitor` as the proof app. That was wrong: its first half
(registers keyed by `egress_port`, accumulating `packet_length`) is now
expressible, but its parser walks `hdr.probe_data.next/.last` and its egress
does `push_front(1)` — dynamic header stacks, which are out of scope, and a
packet that grows, which the fixed header/payload beat split forbids.
`lmprobe` is that portable half, kept faithful, with the report on the sideband
instead of in a pushed header.

Checking the others: **every** remaining bmv2 app with a real egress control is
blocked by something structural, not by a missing metadata field:

| app | blocked by |
|---|---|
| `ecn` | `enq_qdepth` — needs a real traffic-manager queue |
| `mri` | header stacks + the packet grows |
| `link_monitor` | header stacks + the packet grows |
| `multicast` | `mcast_grp` replication (the loop-prune half is now expressible) |
| `flowcache` | `setValid()` on a new header — the packet grows |

So the traffic manager and a length-changing deparser are what unblock real
apps now; no further metadata work does.
