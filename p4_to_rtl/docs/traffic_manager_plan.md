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
| 1 | Payload storage becomes per-slot, and (2026-09-26) re-readable | TX reassembly, backpressure, oversize | **done** — see step 1 revisited |
| 2 | Egress fed from the slot at a dequeue pointer instead of combinationally from ingress | the structural move, with order still trivially preserved | **done** — all tests pass; costs 1 cycle of latency |
| 3 | N queues + round-robin scheduler, queue from `egress_port` | reordering — the real risk | **done** — `tb_egprobe_tm`, reordering demonstrated |
| 4 | `enq_qdepth`/`deq_qdepth`, tail drop; port `ecn` | qdepth semantics under congestion | **done** — `ecn_p4rtl` marks under real congestion |
| 5 | `mcast_group` replication, copy-counted slot release | replication, slot lifetime | **done** — `mcprobe`, 3 copies from 1 packet |

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

## Step 1 revisited — the payload store is re-readable (2026-09-26)

Step 1 was framed as "payload storage addressed by **slot**", and per-slot
`pkt_beat_fifo` instances satisfied that while reusing a proven module. But
addressable per slot is not **re-readable**: a FIFO is consume-on-read, so a
replicated packet's first copy popped every beat and the second found nothing.

`pkt_beat_fifo` is therefore now `pkt_beat_buf`: the same BRAM and the same
2-entry skid that gives the TX path its first-word fall-through contract, but
reads advance a read pointer without destroying anything, and two new inputs
recycle it:

- **`rewind`** — read pointer back to beat 0, so the packet can be sent again.
- **`clear`** — drop the packet; the slot is being released.

`wr_ptr` is now "how many beats this packet has" and only `clear` moves it.
`tb_pkt_beat_buf` (21 assertions) covers order, a full re-read after rewind
producing byte-identical beats, rewinding mid-pass, clear-and-reuse, and random
read stalls. One measured property worth stating: a pointer reset costs a
bounded **startup** of ≤2 cycles (the skid is flushed and the RAM read is
registered) and **zero** bubbles thereafter, so a re-read still streams at line
rate.

All 39 testbenches stayed green and the stream harness numbers were unchanged
(T1 3.69, T4 3.36 cycles/packet), so this was a pure capability addition.

## Step 5 — done (2026-09-26)

With a re-readable payload, replication landed:

- A **member table** (`MCAST_GROUPS` × one bit per queue) programmed over
  AXI4-Lite, reusing the generic table-write machinery.
- On enqueue, a packet with `mcast_group != 0` goes to its **first** member
  queue; the rest are recorded in a per-slot pending bitmap.
- When a copy leaves the wire, the slot's payload is **rewound** and the next
  member is enqueued. Copies are **serialised** — the output PHV lives per
  slot, so two copies in flight would have the second overwrite the first's
  header before TX sent it.
- Only the **last** copy marks the slot transmitted, so the slot is not reused
  while copies remain.
- Each copy's `egress_port` is the queue it came from, so per-port rewrites and
  per-port drops apply per copy. That is the whole reason egress runs after the
  traffic manager.

`mcprobe.p4` + `tb_mcprobe_top` (15 assertions): one packet in → three copies
out, one per member port, each stamped with **its own** port's MAC (egress ran
per copy), each carrying a **byte-identical payload** (the buffer was rewound),
the loop-prune copy dropped while its siblings still go out, and the shell
still flowing afterwards. **40 testbenches green.**

### Two more bugs, both only visible with replication

- **Sticky drop was per slot, not per copy.** `slot_drop` carries the final
  decision for TX, but egress overwrites it for every copy — so the copy the
  loop-prune dropped made every later copy of that packet inherit the drop, and
  only one of three came out. Ingress's decision is now kept separately in
  `slot_ig_drop` and is what each copy's egress starts from.
- **`always_comb` reading per-slot state that an `always_ff` writes back**
  stops iverilog's simulation time. Deriving the next-pending-copy
  combinationally from `slot_pending` did it at *any* index, constant or not,
  because the `always_ff` that writes `slot_pending` is itself conditioned on
  the result. Registering the encode fixes it and costs nothing: a slot's
  pending set only changes at its own `tx_finish`, so the registered value is
  already correct on the cycle it is read.

**Quartus** (`load_balance_p4rtl` selftest, DE2-115) across the whole traffic
manager:

| | pre-TM | step 2 | step 4 | step 5 |
|---|---:|---:|---:|---:|
| Logic elements | 25,533 | 29,500 | 29,495 | 29,510 |
| Memory bits | 275,712 (7 %) | 497,664 (13 %) | 497,664 | 497,664 |
| Fmax (MHz) | 74.1 | 69.0 | 69.8 | 67.5 |

Making the payload buffer re-readable and adding replication cost essentially
nothing in area (+15 LE, no extra memory — the buffer holds the same beats, it
just stops throwing them away) and 2.3 MHz of Fmax. The traffic manager as a
whole is +16 % logic, +6 points of memory and −9 % Fmax against the pre-TM
shell — for per-port queues, a scheduler that genuinely reorders, queue-depth
metadata, tail drop and multicast replication.

### The iverilog rules this work added

Alongside the existing ones (no unpacked-array reads in continuous assigns, no
`break`, no `automatic` in `always_comb`, no bit-select of an `int` loop
variable), **three ways to stop simulation time dead** — no error, no output,
the clock simply stops:

1. An `always_comb` that writes a variable and then reads it back.
2. An `always_comb` indexing an array with a value that arrives combinationally
   from `processing_generated`'s output. Register the index.
3. An `always_comb` reading per-slot state that is written by an `always_ff`
   whose condition depends on that same block's output. Register the result.

All three were isolated the same way: stub the suspect expression to a constant
and see whether time advances again.
