# Streaming Shell — Implementation Plan

**Decision (2026-09-19):** the streaming shell is vital and comes first; the
ingress/egress split with PHV pass-through follows it. Built step by step so
each step isolates one class of risk and leaves every test green.

**Harness:** `generated/load_balance_xsa/testbench/tb_load_balance_xsa_stream.sv`
— back-to-back packets with `tvalid` never dropped, every output packet checked
in order against the ECMP tables, plus cycle measurements. It is the regression
target for every step and the yardstick for whether a step helped.

## Baseline (Step 0) — the current single-packet shell

| Test | cycles / packet | ideal | input stalled |
|------|----------------:|------:|--------------:|
| T1 16 × 64 B, output always ready | **24.6** | 2 | **91 %** of beats |
| T2 16 × 256 B | **42.7** | 8 | 80 % |
| T3 16 × 64 B, random output stalls | 25.6 | 2 | 92 % |

The shell runs at roughly **8 % of line rate** on minimum packets: for 91 % of
the cycles a valid beat was offered, `s_axis_tready` was low. The pipeline
inside is not the limit — `tb_ueprobe` T3 already proved it takes a new packet
every cycle — the `pkt_busy` invariant in the shell is (packet N+1 cannot
start until N has drained from RX *and* TX).

Everything passes functionally on the current shell; packets are simply
serialised. Later steps must not change *what* comes out, only *how fast*.

## Why the shell is where it is

Today per packet: RX all beats → arm pipeline (already cut-through at
`cutoff_byte`) → wait `proc_valid_out` + settle → patch changed bytes **in
place** in `pkt_buf_hdr` → TX the buffer → clear. `s_axis_tready = !rx_done`
holds the input off for the whole processing + transmit time.

Two generated modules exist that the shell does not use: `parser_generated`
(the top extracts fields itself, and that is fine — it is a second lowering of
the same parse graph) and **`deparser_generated`** (replaced by in-place
patching). The streaming shell is what finally uses the deparser.

## Steps

| # | Change | Risk isolated | Green check |
|---|--------|---------------|-------------|
| 0 | Harness (above) | wrong tests | **done** — baseline recorded |
| 1 | Payload region becomes a FIFO; header stays single-slot; still one packet at a time | TX reassembly (the BRAM issue/commit read path) | **done** — see below |
| 2 | Output header bytes come from a combinational deparser overlay instead of in-place patching | deparser vs patching equivalence | **done** — see below |
| 3 | Header slot ring (N packets in flight); pipeline results consumed in order; `pkt_busy` removed | ordering, drops mid-stream, stale tails — the real risk | **done** — see below |
| 4 | `tready` low only on genuine FIFO/slot fullness; random input+output stalls; overflow; Quartus fit + timing | backpressure, Fmax regression | **done** — see below |

### Step 1 — done (2026-09-19)

`pkt_beat_fifo` (`compiler/emit_fifo.py`, emitted as `pkt_beat_fifo.sv` next
to every XSA top): first-word-fall-through over block RAM with a 2-entry
output skid, one beat per cycle in and out. **Unit-tested in isolation first**
(`tb_pkt_beat_fifo.sv`, 14 assertions: fill/drain, 2000 words at full rate
with **zero output bubbles**, 2301 random words under long stalls on both
sides with no dup/drop/reorder). Synthesizes as `altsyncram`.

Shell changes (`emit_top.py`): RX pushes payload beats `{last, keep, data}`
into the FIFO; `pkt_keep` shrinks to header rows only; the random-access
payload BRAM and its 2-stage issue/commit TX read are gone. TX is a plain
"load the output register whenever it is free" — header rows from
`pkt_buf_hdr`, then pop the FIFO to an entry marked `last`. A **dropped packet
now arms TX in `tx_discard` mode** and pops its payload out of the FIFO;
before, drop meant "don't arm TX" and the buffer was simply overwritten, which
a FIFO cannot do. Overflow marks the final capturable beat as `last` so the
stored packet still ends cleanly.

| Test | step 0 | step 1 | note |
|------|-------:|-------:|------|
| T1 64 B | 24.6 cyc/pkt | **20.6** | TX now 1 beat/cycle, not 2 |
| T2 256 B | 42.7 | **26.7** | biggest gain: most payload beats |
| T3 64 B + stalls | 25.6 | 21.4 | |
| input stalled | 91 % | 90 % | `pkt_busy` still serialises — step 3 |

Numbers moved *only* because the old TX path was 2 cycles/beat; the
serialisation is untouched, as intended. Every top-level test passes
(fiveTuple 28, load_balance_xsa 22, ueprobe 7, regprobe 8, smprobe now 7 —
two new cases: a **224 B dropped packet must leave nothing in the FIFO** and
the next 224 B packet must come out whole, which is the discard-pop path a
64 B frame never reaches). Quartus (selftest top): 17,163 LE (+535 for the
skid), 277,000 memory bits, **Fmax 63.6 MHz**, same critical path as before
(`altshift_taps → pkt_buf_hdr` write-back — step 2 removes it). bmv2 apps are
byte-identical (they do not use `emit_top`).

### Step 2 — done (2026-09-19)

**Finding first:** `deparser_generated.sv` is not usable as the deparser. It
packs every header at a **fixed slot** regardless of validity (fiveTuple's
ipv4 always after the `vlan` slot), so its byte positions disagree with the
real packet whenever an optional header is absent. Latent because nothing
instantiated it and the bmv2 deparser tests only use all-valid headers (a
prefix). Left as-is and flagged; the shell does not use it.

**What replaced in-place patching:** the write-back logic *was* already the
correct deparser — it places each header at its layout-derived byte offset,
the same layout extraction trusts. `_writeback_bytes` gained a target/operator
so the identical placement now also emits `hdr_out`, a combinational overlay:
received header bytes with the pipeline's output PHV written over them at
layout offsets, guarded by output validity. TX transmits `hdr_out`;
`pkt_buf_hdr` is never patched and now has **exactly one writer** (RX), which
is the precondition for step 3's slot ring.

**Equivalence proven, then the check removed:** for one round both paths ran
with a simulation-only comparison of the overlay (snapshotted at the commit
edge, i.e. from the unpatched buffer) against the write-back result one cycle
later. Zero mismatches across every packet of every top-level test, including
fiveTuple's VLAN/no-VLAN cases. Negative control: corrupting one overlay byte
in the generated file fired `DEPARSER MISMATCH byte 22: overlay 40 vs
write-back 3f` on every forwarded packet. Then the write-back, the RX-vs-PROC
arbitration block and its collision assertion were deleted.

Numbers unchanged by design (T1 20.6, T2 26.7). Quartus: 17,349 LE,
**Fmax 65.2 MHz** (63.6 at step 1). The critical path no longer ends in
`pkt_buf_hdr`; it is now `altshift_taps:out_tcp_valid_s1 → hdr_out overlay →
tx_out_data`. The limiter is Quartus packing the pipeline's `_s1.._sN`
forwarding registers into M9K shift registers (`altshift_taps`); keeping them
in flip-flops (`ramstyle = "logic"` / disabling auto shift-register
recognition) is the obvious step-4 lever.

### Step 3 — done (2026-09-19)

| Test | step 0 | step 2 | **step 3** | ideal |
|------|-------:|-------:|-----------:|------:|
| T1 16 × 64 B | 24.6 cyc/pkt | 20.6 | **4.56** | 2 |
| T2 16 × 256 B | 42.7 | 26.7 | **10.56** | 8 |
| T3 64 B + output stalls | 25.6 | 21.4 | **5.00** | 2 |

T1's span is 73 cycles for 32 beats — the "32 beats + one pipeline latency"
target. Slot sweep: NSLOT=2 → 6.75, 4 → 4.56, 8 → 4.56, 16 → 4.56 (input
stall 67 % / 46 % / 26 % / 0 %). **Above 4 slots the span does not move**, so
the ring is no longer the limit — TX is: it spends a start cycle and a
finish cycle around each packet's data beats (~2.5 cycles/packet overhead,
which is all of the gap to ideal on both T1 and T2). Overlapping those with
data is the step-4 optimisation. Default `--nslot 4`.

**Design.** `emit_top.py`: `slot_hdr`/`slot_keep`/`slot_beat_cnt`/`slot_done`/
`slot_overflow` (+ `slot_byte_len`) per slot; four pointers with an extra
wrap bit (`wr_ptr`, `iss_ptr`, `cmp_ptr`, `tx_ptr`) that never overtake each
other; `s_axis_tready = rx_slot_free && !pfifo_full` — never because
anything is busy. Extraction (`w_*`) is muxed from the slot being issued
(`x_hdr`); u_proc gets a **one-cycle `valid_in` pulse** per packet; the
output PHV, drop, metadata and counter requests are captured per slot on
`out_valid`; TX overlays the stored PHV onto the slot's received bytes at
TX time (bases recomputed over the stored PHV as `phv_*_base`), so
cut-through still works when the slot's later rows arrive after the
pipeline finished. Counters: commit on TX start, apply on TX finish.
`pkt_busy`, `proc_armed/settle/committed`, `pkt_ready_to_clear` are gone.

**Three bugs found and fixed on the way — two of them in the compiler, not
the shell, and both invisible under the old single-packet contract:**

1. **`valid_out` was not aligned with `out_*`** (`emit_processing.py`).
   `valid_out <= valid_sN` is registered one cycle after the last stage
   while `out_*` are combinational from the stage-N registers. Under
   back-to-back issue, `out_*` on a `valid_out` cycle belong to the NEXT
   packet — measured: sampling at `valid_out` got **0/20** packets right.
   Ten-plus testbenches assert `valid_out`'s exact "1 baseline + N boundary"
   edge count, so re-timing it stays a separate cleanup; instead a purely
   additive `out_valid` port (`= valid_sN`) is emitted, aligned with the
   data (**20/20**), and the shell captures on that.
2. **Forwarded `if` conditions were stale across inserted stages**
   (`emit_processing.py`). `_split_stage` registers a split condition at
   the boundary and rewrites the consumer to read that register — correct
   only if the consumer is in the very next stage. A table's no-op latency
   stage (or UserExtern latency, or a budget split) puts it two or more
   stages later, while the register is rewritten every cycle from live
   inputs. With one-cycle issue this skipped load_balance_xsa's entire
   `if (ipv4.isValid() && ttl > 0)` block on isolated packets; the
   back-to-back stream passed only because the next slot was also IPv4.
   Fixed by `_forward_conds_through_stages()`: every condition register
   still referenced downstream is re-registered at each intervening
   boundary (`<name>_pK`) exactly like the `_sK` data registers, and the
   consumers renamed. This also fixed `tb_fiveTuple_counters_e2e` (the
   `.count()` action was inside such a block).
3. **Shell: `emit_pl` popped the next packet's first beat on the finish
   cycle** (tx_slot_free is true while tx_in_payload is still set), sending
   it out ahead of that packet's headers. Gated on `!(tx_out_valid &&
   tx_out_last)`. Also: `iss_allocated` must track "RX mid-packet"
   explicitly (`rx_active`), because `wr_ptr` advances on tlast into a slot
   that may still hold an older, unreleased packet with a nonzero beat count
   — inferring from the count re-issued a stale slot (16 tlasts, 17 issues).

All top-level tests pass (load_balance_xsa_top 22, stream 3, fiveTuple 28,
counters_e2e 5, smprobe 7, ueprobe 7, regprobe 8) and every bmv2
module-level test still passes with the condition-forwarding change
(firewall 79, load_balance 54, qos 60, ternary_acl 29). Quartus (selftest,
NSLOT=4): 23,879 LE (21 %), 15,848 regs, **Fmax 68.3 MHz** (65.2 at step 2);
critical path still sourced at the `altshift_taps` valid shift register.

### Step 4 — done (2026-09-19)

Four sub-steps, each verified before the next.

**4a — TX rewrite (finish-at-load).** The step-3 TX side spent extra cycles
per packet: a separate "finish" state after the last beat, a `tx_last_loaded`
guard, and a byte-length latch. Rewritten so the packet finishes on the same
cycle its last beat is loaded into the output register (`tx_finish =
last_loaded || discard_done`), a header row is emitted whenever
`hdr_row_ready && tx_slot_free`, and a dropped packet's payload run is popped
with no output cycles at all (`discard_pop`). `s_axis_tready` is now exactly
`rx_slot_free && !pfifo_full`. T1 24.6 → **3.19** cycles/pkt, T2 42.7 →
**8.62** (line rate for 256 B: 8 beats/pkt + 0.6 overhead).

**4b — Robustness (T4–T8 in `tb_load_balance_xsa_stream`).** Added
64×64 B, random input+output stalls, mixed sizes (64–1500 B), FIFO-full
(8×2048 B with the output held) and oversize (4×9000 B > `MAX_PKT_BEATS`).
Two real bugs, both in slot release:

1. **Byte counts read after slot release.** `slot_byte_len[tx_slot]` was
   read on the finish cycle, after the slot could already be reused.
   Fixed by adding a fifth pointer, `rel_ptr`, that trails `tx_ptr`; the
   slot's `byte_len`/`cnt_*` are consumed from `rel_slot` at release time.
2. **Oversize packets released while still being received.** TX finished a
   packet whose header rows were complete while RX was still consuming its
   overflow beats, so the slot was reused mid-reception (T8 hang). Release
   is gated on `slot_done[rel_slot]`: `slot_release = (rel_ptr != tx_ptr)
   && slot_done[rel_slot]`.

T7's first version deadlocked itself (held the output until all input was
in — with a 2048-beat FIFO that is a true deadlock, not a bug); the test
now releases the output on a timer and checks FIFO-full stalls `tready`
without losing data.

**4c — Fmax.** Quartus placed the `_s1.._sN` forwarding registers in
`altshift_taps` (M9K shift registers), whose output was the critical path at
every step so far. Boards now carry a `shift_reg_pragma`
(`AUTO_SHIFT_REGISTER_RECOGNITION OFF` on Altera, `shreg_extract = "no"` on
Xilinx) emitted on `processing_generated`. Fmax **66.1 → 71.3 MHz**, +1.6 K
LE (the taps become real registers), 0 `altshift_taps`. The remaining
critical path is the `InternetChecksum` adder tree
(`out_ipv4_*_s6 → slot_phv_ipv4_hdrChecksum`) — an application-level
combinational depth, not the shell.

**4d — Counters at one packet per cycle.** The counter's old 2-cycle
FSM (`pkt_commit` then `pkt_done`) and single `pend` slot lost increments
under back-to-back minimum packets — `tb_fiveTuple_counters_e2e` T3
(32 × 42 B, back-to-back) counted **33/34**. Rewritten as a two-stage
pipelined read-modify-write: stage A registers the request and reads
`mem[idx]`, stage B writes `mem[idx] <= cur + delta`, with a same-index
bypass (`cur = (b_v && b_idx == a_idx) ? b_new : mem_q`) so consecutive
hits on one index accumulate correctly. The interface is now a single
`incr_fire` cycle driven from `slot_release`; `pkt_byte_len` rides with it.
Standalone TBs gained back-to-back same-index/different-index tests
(PacketCounter 10, ByteCounter 6); e2e counts **34/34, 1428 bytes**.

**Final numbers (NSLOT=4, iverilog):**

| Test | Packets | cycles/pkt | Input stalled |
|------|---------|-----------:|--------------:|
| T1 16×64 B | 16 | 3.38 | 27 % |
| T2 16×256 B | 16 | 8.62 (line rate) | 0 % |
| T4 64×64 B | 64 | 3.09 | 32 % |
| T5 in+out stalls, 128 B | 32 | 10.34 | — (test-driven) |
| T6 mixed 64–1500 B | 24 | line rate | 0 % |
| T7 FIFO-full | 8×2048 B | — | 29 % (correct) |
| T8 oversize 9000 B | 4 | truncated correctly | 0 % |

Minimum-size packets are the one case still above line rate: 64 B is two
beats, and with four slots the shell can hold at most four packets across
a ~13-cycle pipeline, so `tready` drops ~30 % of the time. This is the
`--nslot` knob (`main.py --nslot 8`), not a shell bug.

Regression: all 33 live testbenches pass (XSA top-level: load_balance_xsa
23 + top 22 + stream 9 + fifo 14, fiveTuple 28 + selftest 15 + avmm 7 +
parser 10 + table 29 + counters 7 + 10 + 6, regprobe 8 + 8, smprobe 7 + 7,
ueprobe 8 + 7; bmv2: firewall 79 ×2 + 7 + 7 + 7 + 4 + 11, load_balance 54,
qos 60, ternary_acl 29, mri 50, basic_tunnel 44, ecn 33, multicast 25).

Quartus (selftest, NSLOT=4, DE2-115, EP4CE115): **25,510 LE (22 %), 17,906
registers, 275,712 memory bits (7 %), Fmax 71.3 MHz**, 0 `altshift_taps`;
unchanged from 4c since load_balance_xsa has no counters. Worst path
`out_ipv4_*_s6 → slot_phv_ipv4_hdrChecksum` (InternetChecksum adder tree).
The 50 MHz DE2-115 target closes with 40 % margin; the 100 MHz constraint
in the generated `.sdc` does not (-4.0 ns), which is an application-side
checksum-pipelining item, not a shell item.

### Constraints carried through (stated, not hidden)

- **Header length in == header length out.** The header/payload split is at a
  fixed beat boundary (`HDR_MAX_BEATS`), so no byte realignment is needed as
  long as the program does not add or remove headers. The in-place design has
  exactly this constraint today, so nothing regresses. Length-changing
  programs (push/pop encapsulation) are a follow-on needing a byte shifter.
- **In-order.** The pipeline is in-order, so completion order == issue order
  and output reassembly needs no reorder buffer. A dropped packet's payload
  run is popped and discarded.
- **Backpressure means fullness.** After step 4, `s_axis_tready` drops only
  when the payload FIFO or the header slot ring is actually full — never
  because the pipeline is busy.

### Target

Step 3 should bring T1 from 24.6 to roughly `2 + (pipeline latency / 16)`
cycles per packet — i.e. the span should approach `32 beats + ~40 cycles of
latency` instead of 394. Step 4 confirms it survives backpressure and still
closes 50 MHz on the DE2-115.
