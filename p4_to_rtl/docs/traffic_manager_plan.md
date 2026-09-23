# Traffic Manager — Implementation Plan

**Why now (2026-09-23):** after the egress stage landed, a survey of every
remaining bmv2 app with a real egress control showed each is blocked by
something structural, and for three of them that thing is the traffic manager:

| app | blocked by |
|---|---|
| `ecn` | `enq_qdepth` — a real queue with a measurable depth |
| `multicast` | `mcast_grp` replication — one packet, N egress runs |
| `mri`, `link_monitor`, `flowcache` | header stacks / packet growth — **not** the TM |

So the TM unblocks `ecn` and `multicast`. It is also the piece that makes
`docs/egress_stage_plan.md`'s ingress→egress split match PISA properly:
PISA is `parser → ingress → TM → egress → deparser`, and today egress is
chained combinationally off ingress with the slot ring standing in for the
queueing point.

## The one thing that makes this hard

The shell is **cut-through and strictly in-order**, and those two properties
are load-bearing in a way that reordering breaks:

- Header bytes are already random-access per slot (`slot_hdr[slot][byte]`).
- **Payload bytes are not.** They stream through one shared FWFT FIFO
  (`pkt_beat_fifo`) in *arrival* order, and TX pops it assuming the head
  belongs to the packet it is currently sending.

A scheduler that serves queue B before queue A must transmit packets out of
arrival order — which the shared payload FIFO cannot express. Worse, the
destination queue is not even known while the payload is arriving: it comes
from `egress_port`, which ingress computes after the header cutoff.

So the enabling change is **payload storage addressed by slot**, not by
arrival order. That is step 1, and it is behaviour-preserving on its own.

Cost, measured on the current `load_balance_p4rtl` build: the payload FIFO is
256 × 289 = 73,984 bits. Per-slot at NSLOT=4 it becomes 4 × 256 × 289 =
295,936 bits — 7.4 % of the DE2-115's 3.98 Mbit, up from 1.9 %. That is the
honest price of reordering, and it scales linearly with `--nslot`.

## Where egress goes

Egress must move **after** the queue, because both target apps require it:

- `ecn` marks in egress from `enq_qdepth`, which is only known once the packet
  has been enqueued;
- `multicast` runs egress once per replicated copy, each with its own
  `egress_port`.

Egress therefore stops being combinationally chained off ingress `out_valid`
and is fed from the slot at **dequeue** time. The egress module itself does
not change — only what drives its inputs. Sticky drop still rides in
`slot_drop`.

## Contract

- A **queue** is a FIFO of slot IDs. `QUEUE_COUNT` queues, selected by
  `standard_metadata.egress_port` (low bits) unless the program declares a
  `queue_id`.
- **Enqueue** happens when ingress completes; **dequeue** is the scheduler's
  choice among non-empty queues. Egress runs on dequeue.
- **Order:** packets within one queue stay in order. Across queues, order is
  the scheduler's. This is the first time the shell reorders, and the
  payload-per-slot storage from step 1 is what permits it.
- **`enq_qdepth`** = packets in the target queue at enqueue, **`deq_qdepth`** =
  at dequeue. Both are standard metadata written by the shell.
- **Tail drop:** enqueue to a full queue drops the packet and frees the slot;
  the shell counts it.
- **Replication:** `mcast_group != 0` enqueues one descriptor per member port.
  The slot is released only when the last copy has been transmitted, so slot
  storage carries a copy count.

## Steps

| # | Change | Risk isolated | Green check |
|---|--------|---------------|-------------|
| 1 | Payload storage becomes per-slot; the single shared FWFT FIFO goes | TX reassembly, backpressure, oversize | **done** — every test and every cycle count unchanged |
| 2 | Egress fed from the slot at a dequeue pointer instead of combinationally from ingress | the structural move, with order still trivially preserved | **done** — all tests pass; costs 1 cycle of latency |
| 3 | N queues + round-robin scheduler, queue from `egress_port` | reordering — the real risk | **done** — `tb_egprobe_tm`, reordering demonstrated |
| 4 | `enq_qdepth`/`deq_qdepth`, tail drop; port `ecn` | qdepth semantics under congestion | **done** — `ecn_p4rtl` marks under real congestion |
| 5 | `mcast_group` replication, copy-counted slot release | replication, slot lifetime | **attempted, not landed** — see below |

Step 1 is pure restructuring and left every number identical. Step 2 preserves
*order and content* but is not free: it inserts a real register stage, so it
costs one cycle of latency (see below). The behaviour change — reordering —
starts at step 3.

## Step 1 — done (2026-09-23)

`pkt_beat_fifo` is now instantiated **once per slot** instead of once per
design, with RX writing the instance for `wr_slot` and TX reading the one for
`tx_slot`. The module itself is unchanged, so the first-word fall-through
contract the whole TX path is written against still holds and its unit test
still covers it; only the addressing changed.

Each FIFO holds a whole maximum-length packet (`PFIFO_DEPTH` 256 ≥
`PAYLOAD_MAX_BEATS` 253, and RX stops accepting payload beats at
`MAX_PKT_BEATS`), so a packet can never be blocked by its own FIFO — nor, now,
by another packet's payload. Input backpressure is purely slot availability.

Every one of the 37 testbenches passes and **every measured cycle count in the
stream harness is bit-identical**, including T7, whose backpressure comes from
slot exhaustion rather than payload fullness once the output is held.

Cost, `load_balance_p4rtl` selftest on the DE2-115:

| | before | after | delta |
|---|---:|---:|---:|
| Logic elements | 25,533 | 27,905 | +2,372 (+9 %) |
| Memory bits | 275,712 (7 %) | 497,664 (13 %) | +221,952 = exactly 3 more FIFOs |
| Fmax | 74.1 MHz | 71.2 MHz | −2.9 MHz (−4 %) |

The extra logic is four sets of FIFO pointer/skid logic plus the read mux; the
memory delta matches the prediction exactly (3 × 73,984 bits). This is the
price of making payload storage addressable, and it scales with `--nslot`.

## Step 2 — done (2026-09-23)

Ingress completion now writes its **whole** result into the slot — header
vector, user metadata, standard metadata, drop and counter requests — and a
new `deq_ptr` selects which slot feeds `u_egress`. Egress reads that stored
state instead of ingress's live outputs.

Nothing about the egress module changed, and with one in-order queue the
dequeue order is the ring order, so content and ordering are identical. What
this buys is the two things steps 3–5 need: a scheduler can choose which slot
to dequeue, and a slot can be run through egress **more than once** (multicast
replication).

It is not free. The store-then-read is a real register stage, so the pipeline
is one cycle longer, and at `--nslot 4` a longer pipeline means fewer packets
in flight:

| test | step 1 | step 2 |
|---|---:|---:|
| T1 16 × 64 B | 3.38 | 3.62 |
| T2 16 × 256 B | 8.62 | 8.69 |
| T4 64 × 64 B | 3.09 | 3.34 |

Minimum-size packets pay the most, which is the same slot-occupancy effect the
streaming shell's step 4 documented; 256 B traffic is still essentially at line
rate. `--nslot` is the lever, and it more than pays the cost back:

| `--nslot` | T1 16 × 64 B | T4 64 × 64 B |
|---|---:|---:|
| 4 (default) | 3.62 | 3.34 |
| 8 | **2.69** | **2.17** |

At 8 slots the input is never back-pressured at all and 64 B traffic runs
better than it ever did before the queueing point existed (step 1 at 4 slots
was 3.38 / 3.09). So the extra stage is not a throughput regression — it is a
depth-vs-latency trade the `--nslot` knob already controls.

**One bug simulation could not see.** Writing the slot arrays from both the
ingress-completion block and the capture block left each array with two
procedural drivers. iverilog accepts that silently; Quartus refuses to map it
(*"Can't resolve multiple constant drivers for net slot_drop[0]"*). The two
events are merged into a single `always_ff` with two independent `if` bodies —
they can fire in the same cycle, but never on the same slot, since a slot
cannot be completing ingress and egress at once. Worth remembering that the
step-1 and step-2 simulations were both fully green before synthesis caught
this.

Cost after the merge, `load_balance_p4rtl` selftest on the DE2-115:

| | step 1 | step 2 | delta |
|---|---:|---:|---:|
| Logic elements | 27,905 | 29,500 | +1,595 (+6 %) |
| Memory bits | 497,664 | 497,664 | unchanged |
| Fmax | 71.2 MHz | 69.0 MHz | −2.2 MHz |

The logic growth is the extra PHV write port into the slot arrays; memory is
untouched because the PHV already lived in registers.

Two things the `--nslot` sweep turned up, neither of them a step-2 regression:

- **`--nslot 6` produced a design that deadlocks.** The ring pointers carry a
  wrap bit and count modulo `2**(SLOT_AW+1)`, which matches the `NSLOT`-entry
  slot arrays only when `NSLOT` is a power of two; at 6 the slot index reaches
  6 and 7 and indexes past them. This was documented as a constraint when the
  ring landed but never enforced, so the failure mode was a silent hang rather
  than an error. `emit_top()` now rejects it, like it already rejected a
  non-power-of-two `axi_data_width`.
- **The stream harness's T7 is `--nslot`-dependent.** It asserts the input got
  back-pressured while sending 8 packets, which can only happen when there are
  fewer than 8 slots. At `--nslot 8` every data assertion still passes and only
  that premise fails. Left as-is: the assertion is correct for the default
  build, and the harness is documented as the default build's yardstick.

## Step 3 — done (2026-09-23)

Everything between "ingress finished" and "TX finished" is now carried by FIFOs
of slot IDs rather than ring pointers, because the scheduler may serve queues
in an order that is not arrival order:

- `tmq[q]` — slots waiting for egress, one FIFO per output queue. The queue is
  the low bits of the `egress_port` ingress wrote; `TM_QUEUES` = 4.
- `egq` — slots inside the egress pipeline, in dequeue order.
- `txq` — slots that finished egress, waiting for the wire.
- `slot_txdone[]` — a per-slot flag, because "TX has finished this slot" is no
  longer a pointer comparison. Slots are still *released* in arrival order
  (`rel_ptr`), which keeps the allocator a ring; a slot transmitted early waits
  for older slots. Round-robin drains every queue, so the wait is bounded.

The scheduler is a rotating priority encoder, **unrolled at emit time**: written
as a loop it needs either `automatic` (unsupported by iverilog 11) or a
bit-select of an `int` loop variable (also unsupported). `QCOUNT` is a power of
two, so `rr_ptr + k` wraps for free.

**Queues only mean something if packets wait in them.** Ungated, every packet
drained straight through in arrival order and the scheduler never saw two
non-empty queues — the TM would have been decorative. Dequeue is therefore
gated on how many packets are already past the scheduler (`TM_INFLIGHT`).
Measured on the stream harness (cycles/packet, 64 B): 1 → 5.50, 2 → 3.69,
3 → 3.62, 4 → 3.62. **2** is the smallest window that keeps full throughput,
which is also the one that leaves the most packets queued.

`tb_egprobe_tm` (10 assertions) is the proof: per-queue FIFO order, round-robin
fairness, nothing lost or duplicated, and the headline —

```
arrival order 101 102 103 104  ->  output order 101 102 104 103
```

the first time this shell has ever emitted packets out of arrival order.

Two existing assertions in `tb_egprobe_top` had encoded "output order ==
arrival order" and now fail by design; they were rewritten to the invariant
that actually holds — per-port counts, and per-port timestamp monotonicity.

## Step 4 — done (2026-09-23)

`enq_qdepth` and `deq_qdepth` are new `standard_metadata_t` fields written by
the traffic manager: `enq_qdepth` is recorded into the slot when the packet is
enqueued, `deq_qdepth` is valid combinationally on the dequeue cycle, which is
exactly when egress samples its inputs. Both read 0 in ingress, which runs
before the packet is queued.

Tail drop is a `--tm-qlimit N` knob: enqueueing to a queue already at depth N
marks the packet dropped (it still walks the pipeline as a dropped packet, which
is how its slot gets released) and bumps a counter. It defaults to off, because
queue occupancy is already bounded by the slot count — a limit only bites when
set below `--nslot`.

**`ecn_p4rtl.p4`** is the app this was built for, ported from the v1model
original: it marks congestion in egress from `enq_qdepth`, which did not exist
until the shell had queues. `tb_ecn_p4rtl_top` (9 assertions) creates real
congestion by holding the output low: an uncongested packet is unmarked, packets
queued behind one are marked CE, non-ECT traffic is never marked, and marking
stops once congestion clears. The threshold is scaled from the original's 10 to
1, since a queue here holds at most `--nslot` packets rather than bmv2's
thousands.

### A bug worth recording

`tb_lmprobe_top` deadlocked after step 3. The cause: an egress control with
**no pipeline boundary** (no table, no split) has `out_valid = valid_in`, so a
slot is pushed to and popped from the egress in-flight FIFO on the same edge —
the pop read an entry that had not landed, X propagated into `tx_slot`, and TX
wedged. Fixed with a bypass: when the FIFO is empty, the packet completing
egress can only be the one being dequeued this cycle. `egprobe` never showed it
because its egress has a table.

**Quartus** after steps 3–4 (`load_balance_p4rtl` selftest, DE2-115):

| | pre-TM | step 1 | step 2 | step 4 |
|---|---:|---:|---:|---:|
| Logic elements | 25,533 | 27,905 | 29,500 | 29,495 |
| Memory bits | 275,712 | 497,664 | 497,664 | 497,664 |
| Fmax (MHz) | 74.1 | 71.2 | 69.0 | 69.8 |

The queues and scheduler are essentially free on top of step 2 — they are a few
small FIFOs of slot indices — so the whole traffic manager costs about
+16 % logic, +6 points of memory and −6 % Fmax against the pre-TM shell.

## Step 5 — attempted, not landed (2026-09-23)

Replication was implemented end to end — a CP-programmable member table in the
AXI map, a per-slot pending-copy bitmap, serialised copies (the next copy is
enqueued only once the previous has left the wire), copy-counted release, and
a per-copy `egress_port` — plus an `mcprobe.p4` fixture and testbench.

**Serialising the copies is the design decision to revisit.** The output PHV
lives per *slot*, not per copy: egress rewrites the slot, so two copies in
flight at once would have the second overwrite the first's header before TX had
sent it. Serialising avoids that without touching storage; per-copy PHV would
be a packet-descriptor rewrite of the whole shell.

It is **not** in the tree. The build elaborated and unicast still worked
(`tb_mcprobe_top` T1 passed), but the first multicast packet stalled simulation
time — a zero-delay loop somewhere in the new combinational logic. One
self-triggering `always_comb` was found and fixed (a block that wrote
`ig_members` and then read it back), which was not the whole cause. Rather than
leave RTL in the tree that hangs, `emit_top.py` was restored to the verified
step-4 state and the fixture removed. The work is reproducible from this
description; the next attempt should build the replication logic up in smaller
pieces, checking after each that simulation time still advances.
