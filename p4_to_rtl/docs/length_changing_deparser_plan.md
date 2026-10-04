# Length-Changing Deparser — Implementation Plan

**Why now (2026-09-27):** with the traffic manager finished, this is the last
*structural* gap in the shell. Everything else on the list is a feature to add or
a cleanup; this one is a property the datapath does not have.

## What is missing

The shell reproduces the input packet's **length and byte positions** exactly.
`hdr_out` overlays the output PHV onto the received bytes at layout offsets, and
TX replays exactly `slot_beat_cnt[tx_slot]` beats:

```
wire tx_beat_cnt_s   = slot_beat_cnt[tx_slot];          // beats RECEIVED
wire hdr_row_is_last = tx_done_s && (tx_hdr_row == tx_beat_cnt_s - 1);
```

So a program that makes a header valid that was not (adding bytes) or invalid
that was (removing bytes) gets an output of the wrong length with a corrupted
tail. P4 allows both; the shell does not.

## What it unblocks — including the flagship app

This matters more than the earlier survey suggested. `fiveTuple.p4` — the app
with a real DE2-115 bitstream and 28 top-level assertions — exists to **insert a
VLAN tag**:

```p4
action InsertVLAN(CounterIndex_t counter_index, bit<3> pcp, bit<1> cfi, bit<12> vid) {
    hdr.new_vlan.setValid();     // never extracted by the parser: always invalid in
    ...
}
```

`new_vlan` is never parsed, so it is always invalid on input, and the deparser
emits it between `eth` and `vlan`. That is a 4-byte insertion. Its own testbench
says so plainly:

> *"fiveTuple.p4's only non-NoAction action is InsertVLAN, which grows the packet
> — packet growing/shrinking is a separate, pre-existing, out-of-scope limitation
> (TX always replays exactly rx_beat_cnt beats), so no test here configures a
> matching table entry with action=InsertVLAN."*

So **the flagship app's entire reason for existing has never been exercised
end-to-end on the shell.** No silent bug — it is honestly documented and routed
around — but it is the strongest argument for doing this work.

| app | needs | unblocked by this? |
|---|---|---|
| `fiveTuple` (`InsertVLAN`) | insert 4 bytes | **yes** |
| `flowcache` | `setValid`/`setInvalid` on `packet_in`/`packet_out` | **yes** |
| `basic_tunnel` | emits `myTunnel`, parsed on input | already fine (no length change) |
| `mri`, `link_monitor` | header **stacks** *and* growth | no — stacks stay descoped |

## The shape of the problem

The packet lives in two places: the first `HDR_MAX_BYTES` bytes in `slot_hdr`,
the rest in that slot's `pkt_beat_buf`. Note the bytes between the real header
extent and `HDR_MAX_BYTES` are **payload** that happens to sit in the header
buffer.

The output byte stream we want is:

```
out[0 .. out_hdr_len-1]   = the deparsed headers, at OUTPUT offsets
out[out_hdr_len .. ]      = original bytes from in_hdr_len onward
                            (first the tail of slot_hdr, then the payload buffer)
```

With `delta = out_hdr_len - in_hdr_len`, everything after the header moves by
`delta` bytes. `delta` is a multiple of 8 bits but **not** of a beat, so this is a
byte-granular shift across beat boundaries: each output beat is assembled from
two consecutive source beats selected by a rotation amount. That is the byte
shifter, and it is the whole job.

### `cutoff_byte` cannot be reused as the header length

Worth stating before anyone builds on it, because the name invites the mistake.
`cutoff_byte` is a **max over worst-case extents**, and for variable-length
headers it uses the **maximum** size, not the actual one. From `fiveTuple`:

```systemverilog
wire w_ipv4opt_cutoff_term = (...) ? (w_ipv4opt_base + 40) : 0;   // 40 = MAX options
wire w_cutoff_max_3 = (w_cutoff_max_2 > w_ipv4opt_cutoff_term) ? ... ;
wire cutoff_byte    = w_cutoff_max_6;
```

That is exactly right for what it does — "every header has certainly arrived by
here", the cut-through trigger — and wrong for a length. Step 1 needs real
**sums of actual sizes**, computed separately for the input validity and the
output validity.

There is a shortcut for the *shift amount* specifically:

```
delta = Σ_h  size_h × ( out_valid_h − in_valid_h )
```

Only headers whose validity actually **changes** contribute. A variable-length
header whose validity is unchanged contributes zero whatever its size is — so its
size expression is never needed. That covers every case we care about
(`fiveTuple`'s `new_vlan`, `flowcache`'s `packet_in`/`packet_out`, `lenprobe`'s
tags), and the compiler can emit a `[WARN]` for the one case it does not: a
*variable-length* header whose validity changes.

The output packet length is then just `slot_byte_len + delta` — no header extent
needed at all.

The pieces already exist:

- `phv_*_valid` / `w_*_valid` — output and input validity per header, already
  emitted.
- `phv_*_base` — output header offsets, already computed from the **output** PHV
  validity (`_emit_offset_var_for` re-run with a `w_` → `phv_` rename). So the
  deparser already places headers at output offsets *within* the fixed image.
- `pkt_beat_buf` is re-readable and has a skid, which is the natural place to
  hold the 2-beat window a shifter needs.

What does not exist: an **output** header extent, an output length, and the shift.

### The reframing: input layout and output layout are different things

`_compute_layout()` walks the **parser graph** from `start`. A header the parser
never extracts therefore has **no layout entry at all** — no offset, no
write-back. Confirmed on the `lenprobe` fixture: its two insert-only headers are
in `struct headers` and in the deparser's emit list, and the generated overlay
places only `eth` and `vlan`:

```systemverilog
hdr_out[12] = phv_eth_etype[15:8];
hdr_out[13] = phv_eth_etype[7:0];
if (phv_vlan_valid) begin
    hdr_out[14]   = phv_vlan_tci[15:8];     // ...and nothing for tag / tag2
```

So `setValid()` on a never-parsed header is silently ignored today, and
`setInvalid()` leaves the received bytes in place.

That is the real insight: **the input layout (where bytes arrived — the parse
graph) and the output layout (where bytes go — the deparser's emit list) are two
different things.** They have been conflated because until now they were always
identical. Everything in this plan follows from separating them:

- input layout → `cutoff_byte`, field extraction, `HDR_MAX_BYTES` for RX
- output layout → the deparser overlay's offsets, `out_hdr_len`, and the shift

`HDR_MAX_BYTES` must then be sized from the **output** worst case (every emitted
header valid), not the input one. On `lenprobe` the input worst case is 18 bytes
and the output worst case is 26; both happen to round up to the same 32-byte beat,
which is luck, not correctness.

## Steps

| # | Change | Risk isolated | Green check |
|---|--------|---------------|-------------|
| 0 | Fixture + **failing** baseline: a probe that inserts a header, and one that removes one | that the tests actually pin the gap | **done** — `lenprobe`, 2/8 pass, the 6 failures are exactly the gap |
| 1 | The emit-list header set, per-slot input validity, and `hdr_delta` | the validity arithmetic | **done** — 40/40 unchanged, delta verified 0/+4/+8/−4 |
| 2 | The output layout: emit-order offsets, the splice point, and the length-changing gate | the offset arithmetic, in isolation | **done** — 40/40 unchanged; offsets verified against the model |
| 3 | The emission itself: re-placed header image, the 2-beat payload shifter, output `tkeep`/`tlast` | the shifter — the real risk | **done** — `lenprobe` 16/16, all four cases byte-for-byte |
| 4 | Length-dependent metadata: keep `packet_length` as the **received** length, fix counters and `totalLen`-style fields | metadata semantics under a length change | **done** — `lenprobe` 26/26, both lengths asserted |
| 5 | Turn on `fiveTuple`'s `InsertVLAN` and port `flowcache` | real apps | **done** — `fiveTuple` T12 byte-for-byte, 116/116; `flowcache` port still open |

Steps 1 and 2 must leave every number unchanged — they are pure restructuring.
The behaviour change starts at step 3.

## Decisions to settle before step 3

These change the work, and they are judgement calls rather than derivable facts.
My default is given, but they are worth a look:

1. **Growth past the buffer.** A packet that grows can exceed `MAX_PKT_BEATS`, or
   its header can exceed `HDR_MAX_BYTES`. *Default:* size the header region from
   the worst case with **every** header valid (`_worst_case_hdr_bytes` already
   does this), and treat an overflowing packet the same as an oversize one today
   — truncate and mark it. The alternative is to drop it, which is more honest but
   changes `tready` behaviour.
2. **Does `packet_length` mean the received or the transmitted length?**
   *Default:* the **received** length. It is ingress metadata describing arrival,
   and that is what v1model means. The transmitted length is then not visible to
   the program, which is fine — nothing asks for it.
3. **Do byte counters count in or out?** *Default:* **received** bytes, i.e.
   unchanged from today, so `Counter` semantics do not shift under this work.
4. **Shift granularity.** *Default:* a full byte-granular shifter. A cheaper
   option is to constrain insertions to multiples of the beat width, which would
   make `fiveTuple`'s 4-byte VLAN impossible — so, not that.
5. **Is store-and-forward acceptable for length-changing apps?** Cut-through
   issues a packet before its tail has arrived, which is fine for the shifter
   since TX is downstream of the whole slot. *Default:* keep cut-through; no
   change needed. Flagged because it is the kind of thing that turns out to
   matter three steps in.


## Step 0 — done (2026-09-27)

`p4src/apps/lenprobe.p4` + `tb_lenprobe_top` (8 assertions). Two insert-only
headers the parser never extracts, plus a parsed VLAN that can be removed, with
a counting payload so a shift by the wrong number of bytes is obvious. Each case
is an exact byte-for-byte comparison against the packet the P4 program says
should come out, and the testbench prints *how* it failed rather than just that
it did:

```
== T1: fwd -- nothing changes, out == in ==
    [INFO] T1: 64 bytes out, byte-for-byte correct
    [PASS] T1: 64 bytes out
    [PASS] T1: byte-for-byte identical to the input
== T2: insert_one -- 4 bytes appear after ethernet ==
    [INFO] T2: WRONG LENGTH -- got 64 bytes, expected 68
    [FAIL] T2: 68 bytes out (64 + 4)
== T3: insert_two -- 8 bytes appear after ethernet ==
    [INFO] T3: WRONG LENGTH -- got 64 bytes, expected 72
== T4: strip_vlan -- a parsed 4-byte VLAN is removed ==
    [INFO] T4: WRONG LENGTH -- got 64 bytes, expected 60

  Results: 2 passed, 6 failed  (total 8)
```

T1 (no length change) passes, which is the control: the harness itself is sound.
The other three are stuck at the input length, which is the gap stated exactly.
This file is expected to fail until step 3 lands — the header says so, so nobody
mistakes it for a regression.


## Step 1 — done (2026-09-27)

Three pieces, all additive:

**The IR now records `varbit`.** `HeaderField` kept only a width, so
`varbit<320>` and `bit<320>` were indistinguishable — and a varbit's width is a
*maximum*, not an actual size. `HeaderField.is_varbit` and
`Header.is_variable_length` close that, which is what lets the delta model know
which headers it cannot size at compile time.

**Input validity is now stored per slot.** `w_*_valid` is the live extraction
result for the *issue* slot; by the time TX needs it, it belongs to a later
packet. `slot_in_valid_<h>[]` is sampled at issue, alongside the existing
`slot_phv_<h>_valid[]` which holds the output validity.

**`hdr_delta`** is emitted as one signed term per emitted header:

```systemverilog
wire signed [7:0] hdr_d_tag =
    (phv_tag_valid            ? 8'sd4 : 8'sd0)
  - (slot_in_valid_tag[tx_slot] ? 8'sd4 : 8'sd0);
wire signed [7:0] hdr_delta = hdr_d_eth + hdr_d_tag + hdr_d_tag2 + hdr_d_vlan;
```

Verified at runtime on `lenprobe`, which is why the fixture existed first:

| case | `hdr_delta` |
|---|---:|
| T1 `fwd` — nothing changes | **0** |
| T2 `insert_one` | **+4** |
| T3 `insert_two` | **+8** |
| T4 `strip_vlan` | **−4** |

Nothing consumes it yet, so all 40 existing testbenches are unchanged.

Variable-length emitted headers are excluded from the sum and the compiler now
**says so** rather than leaving it implicit:

```
[NOTE]  variable-length emitted header(s) ipv4opt, tcpopt: excluded from the
        deparser's length delta, which assumes their validity is the same on
        input and output. A program that adds or removes one of these would
        need its runtime length here.
```

That assumption holds for every program in the tree (`fiveTuple`'s option
headers are parsed and emitted alike). Step 3 should turn it into a real static
check — scan both controls for `setValid`/`setInvalid` on such a header — rather
than a note.


## The TX model for steps 2–3 (worked out before building)

Two facts make this tractable:

1. **Every length change happens inside the header region.** The payload is
   untouched content; it only lands at a *shifted output position*.
2. **Only headers up to the last changeable one need re-placing.** Everything
   after it keeps its internal layout and simply moves — so the existing overlay
   (modified fields written at their ORIGINAL positions) can be reused for the
   whole tail, shifted.

So the output byte at position `p` is:

```
out(p) = (p < S) ? new_hdr[p]                 // re-placed headers, output offsets
                 : src(p - delta)             // everything else, shifted

src(q) = (q < HDR_MAX_BYTES) ? hdr_ovl[q]     // today's overlay, unchanged
                             : payload_byte(q - HDR_MAX_BYTES)
```

- `S` = the output end of the **last header whose validity can change** =
  `out_base(h_last) + (valid ? size : 0)`.
- `out_base` is a running sum over the deparser's emit order, gated by output
  validity. It is only needed up to `S`, so **only headers before the last
  changeable one need a compile-time size** — which is why `fiveTuple` works
  despite having two varbit headers: `new_vlan` is second in the emit list and
  the varbits are fourth and sixth, safely past `S`.
- Output length = `slot_byte_len + hdr_delta`.

Worked through on `lenprobe` (emit order `eth, tag, tag2, vlan`):

| case | out_bases | `S` | `delta` | tail source |
|---|---|---:|---:|---|
| `fwd` | eth 0 | 14 | 0 | `src(p)` |
| `insert_one` | eth 0, tag 14 | 18 | +4 | `src(p−4)` → orig from 14 |
| `insert_two` | eth 0, tag 14, tag2 18 | 22 | +8 | `src(p−8)` → orig from 14 |
| `strip_vlan` | eth 0 | 14 | −4 | `src(p+4)` → orig from 18 |

Each row is the packet the P4 program describes, so the model is right.

**The shifter.** `HDR_MAX_BYTES` is a whole number of beats, so the payload's
output rotation is `rot = delta mod BEAT_BYTES` — a fixed amount for the whole
packet. Each output beat is therefore assembled from a **two-beat window** of the
payload stream at byte offset `rot`, which is one mux level, not a general
crossbar.

**Gating.** A program can only change its length if it calls
`setValid`/`setInvalid` on a header the deparser emits. The compiler detects that
statically and keeps the simpler fixed-length TX path otherwise, so every app
that cannot change length gets byte-identical RTL. Exactly two apps take the new
path today:

```
lenprobe             CAN change length
fiveTuple            CAN change length      <- the flagship, via InsertVLAN
```

That is a good verification split: `fiveTuple`'s existing suite exercises the new
path with `delta == 0` at runtime (its tests never configure `InsertVLAN`), and
`lenprobe` exercises `delta != 0`.


## Step 2 — done (2026-09-27)

**The length-changing gate.** A program can only change its own length if it
calls `setValid`/`setInvalid` on a header the deparser emits.
`_validity_changing_headers()` finds those by walking action bodies and
if-branches (a `setValid` almost always sits inside a table action), and the
compiler says so:

```
lenprobe    [INFO] Length-changing deparser: tag, tag2, vlan can be added/removed
fiveTuple   [INFO] Length-changing deparser: new_vlan can be added/removed
```

Everything else keeps the fixed-length TX path and byte-identical RTL. Exactly
two apps take the new path, which is the verification split we want:
`fiveTuple` exercises it with `delta == 0` at runtime, `lenprobe` with
`delta != 0`.

**The output layout.** A running sum over the deparser's emit order, gated by
output validity — the first time the compiler has had an output layout at all:

```systemverilog
wire [13:0] obase_eth  = 14'd0;
wire [13:0] obase_tag  = obase_eth  + (phv_eth_valid  ? 14'd14 : 14'd0);
wire [13:0] obase_tag2 = obase_tag  + (phv_tag_valid  ? 14'd4  : 14'd0);
wire [13:0] obase_vlan = obase_tag2 + (phv_tag2_valid ? 14'd4  : 14'd0);
wire [13:0] tx_splice  = obase_vlan + (phv_vlan_valid ? 14'd4  : 14'd0);
```

**A guard, not an assumption.** Only headers up to the splice need a
compile-time size, so a varbit header *past* it is fine — but one at or before it
is a hard error with the reason spelled out, rather than silently wrong RTL:

> `header(s) X are variable-length and sit at or before the last header whose
> validity changes (Y). The deparser needs a compile-time size for every header
> up to that point to compute output offsets.`

`fiveTuple` passes that guard: `new_vlan` is second in the emit list and its two
varbit headers are fourth and sixth.

**Verified against the model**, which is why the fixture came first:

| case | `hdr_delta` | `tx_splice` |
|---|---:|---:|
| `fwd` | 0 | 14 |
| `insert_one` | +4 | 18 |
| `insert_two` | +8 | 22 |
| `strip_vlan` | −4 | 14 |

Every value matches the table worked out above. Nothing consumes them yet, so
all 40 existing testbenches pass unchanged — `fiveTuple` included, which now
carries the new wires.

## Step 3 — the remaining piece

Everything it needs is now in place and verified (`hdr_delta`, `tx_splice`,
`obase_*`, per-slot input validity, a re-readable payload buffer). What is left
is the emission:

1. **The re-placed header image** for output bytes `[0, tx_splice)`: the headers
   in `split_names` written at `obase_*` rather than at input offsets. The
   existing `_emit_writeback_block` already does this shape — it needs to take
   the output bases instead.
2. **The shifted tail** for `p >= tx_splice`: `src(p - hdr_delta)`, where `src`
   is the existing overlay below `HDR_MAX_BYTES` and the payload buffer above it.
3. **The shifter**: `rot = hdr_delta mod BEAT_BYTES` is constant for the packet,
   so each output beat comes from a two-beat window of the payload stream at
   offset `rot` — one mux level. `pkt_beat_buf` already has a 2-entry skid, which
   is the natural place to take the window from.
4. **Output length, `tkeep`, `tlast`** from `slot_byte_len + hdr_delta` rather
   than from the received beat count.

The one interaction to be careful about is **oversize packets**: `slot_byte_len`
counts every received byte including those RX truncated, so a length-derived
`tlast` must still defer to the existing truncation terminator rather than trying
to emit beats that were never stored. The stream harness's T8 covers that case.


## Step 3 — done (2026-09-30)

TX no longer has a header phase and a payload phase. It emits **one byte
stream**: the output header image up to `tx_pstart`, then the payload. A beat is
just "the next `BEAT_BYTES` of it", and `tkeep`/`tlast` fall out of the output
length, which is how a shorter or longer packet terminates.

**The output image** takes the existing overlay (modified fields at their
*original* positions), shifts it by `hdr_delta`, then re-places the headers that
did not simply move:

```systemverilog
always_comb begin
  int q;
  for (int p = 0; p < HDR_OUT_BYTES; p++) begin
    q = p - hdr_delta;
    oimg[p] = (q >= 0 && q < HDR_MAX_BYTES) ? hdr_out[q] : 8'h00;
  end
  if (phv_eth_valid) begin oimg[obase_eth] = ...; end     // at OUTPUT offsets
  if (phv_tag_valid) begin oimg[obase_tag] = ...; end
end
```

Everything below `tx_splice` is covered by the re-placement; everything above it
is the shifted original, which is right because those headers keep their internal
layout and only move.

**The shifter.** `tx_pstart` is not beat-aligned when `hdr_delta` is not a
multiple of the beat width, so the payload lanes split: lanes at or above
`tx_rot` come from the current payload beat, lanes below it from the previous
one. One mux level over a two-beat window, with `pl_prev` holding the older beat.
The final beat of a grown packet may need **only** `pl_prev`, which is why
`pl_prev_v` can stand in for an empty buffer head.

**Result** — all four cases byte-for-byte correct, including the payload shift:

```
[INFO] T1: 64 bytes out, byte-for-byte correct
[INFO] T2: 68 bytes out, byte-for-byte correct
[INFO] T3: 72 bytes out, byte-for-byte correct
[INFO] T4: 60 bytes out, byte-for-byte correct
  Results: 16 passed, 0 failed
```

### Three bugs, and two of them were predicted

- **Signed/unsigned contamination.** Verilog makes a whole expression unsigned as
  soon as one operand is, so `tx_in_len + hdr_delta` turned −4 into 252 and a
  64-byte packet came out as **316 bytes**. Every mixed expression is now forced
  signed and narrowed back. The arithmetic bugs in this project have almost all
  been this shape.
- **Truncated packets** — flagged in the step-2 write-up before it was hit, and it
  duly failed `fiveTuple`'s oversize test. `slot_byte_len` counts every byte
  *received*, including the ones RX discarded past `MAX_PKT_BEATS`, so a
  length-derived `tlast` asked TX for beats that were never stored. The input
  length is now clamped to what the slot actually holds.
- **Two more simulation-time stalls**, both the documented class. The second one
  only appeared once `hdr_delta` was non-zero for the first time — the shifted
  read `hdr_out[p - hdr_delta]` indexes an **unpacked** array at a computed
  offset from inside `always_comb`. Copying the overlay into a packed vector
  first (`hdr_out_flat[q*8 +: 8]`) fixes it; a packed part-select with a variable
  base is fine, and so is copying element-by-element at the loop index, which is
  what the existing `t_hdr` copy already does. The first one: `hdr_delta`
  as a six-term expression reading per-slot arrays at a *combinational* index,
  feeding a 160-iteration `always_comb`. Isolated in one step by stubbing it to a
  constant. The fix is also the better design — the delta is a per-packet fact,
  so it is computed **once at capture** into `slot_hdr_delta[]` and read at TX as
  a single slot lookup, the same shape as the `phv_*_valid` views that have
  always worked.

### `fiveTuple`'s `InsertVLAN` now runs for real

`tb_fiveTuple_counters_e2e` is titled *"real packet -> InsertVLAN -> counters"*
and is the one test that configures a table entry with `action=InsertVLAN`. It
used to pass only because the inserted VLAN was silently dropped and the test
checked counters rather than bytes. It is now genuinely inserting 4 bytes and
still passes 7/7 — which is also how the second stall above was found.

### Where this leaves the gate

Only programs that call `setValid`/`setInvalid` on an emitted header take the new
path; everything else keeps byte-identical RTL. That is `lenprobe` and
`fiveTuple`, and `fiveTuple`'s full suite (28 + 15 + 7 + 10 + 29 + counters)
exercises the new path with `delta == 0`, which is exactly the regression you
want on a restructure this size.

## Step 4 — done (2026-10-03)

Metadata under a length change, pinned by assertions rather than left as a
documented intention. `lenprobe` grew to 26 assertions (from 16) and a second
metadata field, and the app now copies both `packet_length` and `parsed_bytes`
into user metadata so the testbench can read them off the wire.

What the assertions establish:

- **`packet_length` is the RECEIVED length.** A 64-byte frame reports 64 whether
  it leaves as 68, 72 or 60. This was decision 2 above; it is now checked rather
  than assumed.
- **`parsed_bytes` is the extracted extent**, not the output length — 14 with
  only ethernet parsed, 18 with the tag. Step 1 had wired this to
  `slot_byte_len` by mistake (the whole packet, not the header extent); it reads
  `cutoff_byte` now.
- **A program can stamp the received length into a header it just inserted.**
  `insert_stamp` sets `tag.seq = packet_length`; a 96-byte input comes out at
  100 bytes with `tag.seq == 0x0060`. That is the `ipv4.totalLen` pattern working
  end to end — the program does the arithmetic, the shell just makes the input
  available at the right time.
- **Store-and-forward combines with the length change.** The grown packet's
  beats and `tkeep`/`tlast` are right whether the slot completed before TX
  started or during it.

Byte counters still count received bytes (decision 3), unchanged.

## Step 5 — done (2026-10-03)

`fiveTuple`'s `InsertVLAN` runs end to end. `tb_fiveTuple_top` gained
`cp_write_insertvlan` (the same entry shape as the existing writer, with
`action = 1` and the four parameters at words 7..10) and **T12**: a 106-byte UDP
frame matching an entry with `pcp=5, cfi=1, vid=42`.

T12 checks four things, and the fourth is the one that matters: a whole-frame
comparison against an expected image built in the testbench. It passes —
106 bytes in, 110 out, `eth.type` rewritten to `0x8100`, the tag reading
`B0 2A 08 00` (the original `0x0800` carried into `tpid`), and every byte of the
tail shifted by exactly four.

**`fiveTuple`: 116 assertions across 8 testbenches, all green** (top 32,
table query/delete 29, parser 10, packet counter 10, byte counter 6, counters
e2e 7, selftest top 15, selftest AVMM 7). Full suite: **654 + 22 = 676
assertions, 0 failures.**

### One real bug, and four ways iverilog hid it

> **Corrected 2026-10-04.** The table below says these four constructs are
> defective. A probe matrix across iverilog, Vivado `xsim` and Verilator
> (`verification/toolchain_probes/`) showed that three of the four are accepted
> and correct in all three simulators in isolation. They did fix real stalls in
> this design, but the characterisation below is wrong as a general claim --
> see `docs/toolchain_constraints.md` for what is actually true. The *bug*
> described here, `phv_*_base` reading the output PHV, is unaffected.

The bug was a single wrong signal, and it is the kind this architecture invites:

> **`phv_*_base` was computed from the OUTPUT PHV.** Those offsets index the
> **received** bytes — `hdr_out` overlays the output PHV onto the bytes that
> arrived — so they have to follow the input layout. For a fixed-length program
> the two agree, which is why this stood for as long as it did. `fiveTuple`
> rewrites `eth.type` to `0x8100`, and the generated offset was literally
> `phv_ipv4_base = 14 + ((phv_eth_type == 16'h8100) ? 4 : 0)` — so the deparser
> read ipv4 at the offset a VLAN-tagged frame would have had, four bytes too
> high, and duplicated `45 00 00 00` into bytes 22..25.

The fix is to read the validity sampled at issue instead: `slot_in_valid_*` was
already being captured for `hdr_delta`, so the offsets now use
`phv_in_valid_*` views of it. The arithmetic is otherwise untouched. One caveat
stated in the code: a `var_pred` length field (`ipv4.hdr_len`) still comes from
the output PHV, so a program that *rewrote* one would need its received value
stored too. None does, and the varbit guard from step 2 already rejects a
variable-length header at or before the splice.

Finding it took far longer than fixing it, because **four separate iverilog
defects sat between the bug and the symptom** — three of them silent. All four
are now worked around in the emitter, with the reason written at each site:

| Construct | What iverilog does |
|---|---|
| `tx_beat_data[i*8 +: 8] = ...` (variable part-select **lvalue**) | "constant selects … all bits will be included" — treats it as a whole-vector access, so the block becomes sensitive to its own output and **re-triggers forever**. Simulation time stopped dead. Only appeared once `hdr_delta != 0`, because at `tx_rot == 0` every lane takes the same branch and the repeated whole-vector write settles. |
| `oimg[p]` — unpacked read at a **computed** index inside `always_comb` | same self-retrigger, in whichever block reads it |
| a **second** write loop over the same unpacked array in one `always_comb` (clear-then-fill) | same self-retrigger — and this one fired with `hdr_delta == 0`, so it broke tests that had been passing |
| `hdr_out_flat[q*8 +: 8] = hdr_out[q]` (the same lvalue, used as a workaround for the above) | **silently wrong data** — duplicated four bytes of the shifted tail, which is how it masqueraded as the real bug for an entire debugging session |

The shapes the emitter uses now, all four avoided:

- the shift is a **`case` over every achievable `hdr_delta`**, so each branch
  reads `hdr_out` at a *constant* offset. The achievable set is small — each
  changeable header either appears (+size), disappears (−size), or does neither.
- each branch writes **every** `oimg` element exactly once, unconditionally.
- `oflat`, a packed copy of `oimg` built with constant indices on both sides,
  bridges to the beat assembly; a variable part-select is safe to **read**.
- the beat's 32 lanes are **unrolled at emit time**, so every part-select lvalue
  has a constant base.

The method that actually worked, after a lot of guessing that did not: a
heartbeat `initial forever #N $display($time)` to tell a time stall from a logic
deadlock, then an `always @(sig) bump(...)` counter on each suspect net to name
the one spinning. That pointed straight at `tx_beat_data` — a block with no
changing inputs — in one run. Worth reaching for first next time.

### Not done here

**Quartus run: done 2026-10-04, 0 errors, 140 warnings.** Analysis & synthesis
succeeds, so nothing here is an illegal construct or a multi-driver. The numbers:

| | logic elements | registers | memory bits |
|---|---|---|---|
| `fiveTuple_top` (datapath) | 71,420 | 30,623 | 4,546,560 |
| `fiveTuple_selftest_top` | 164,289 | 88,635 | 4,694,016 |
| EP4CE115F29C7 available | ~114,480 | — | 3,981,312 (432 x M9K) |

So the **datapath fits in logic (62%) and overflows block RAM by ~14%**, and the
**selftest harness is what breaks the logic budget** -- it adds 92,869 LEs, more
than the datapath itself. The harness is a test fixture, not the product, but it
can no longer be synthesised onto this board alongside the design.

The RAM overflow is **the P4 program's own resource request**, not compiler
bloat: `fiveTuple.p4` declares `size = 8192` on the exact-match table and two
`Counter<bit<64>, bit<13>>(8192)` instances. Three 8192-entry structures plus
2 x 8192 x 64 bits of counters do not fit a Cyclone IV E. Lower `NUM_COUNTERS`
and the table `size` and it fits; that is the program author's call.

One genuine compiler-side lead, though: the reported 4,546,560 bits is about
**1.85x the ~2.46 Mbit the design logically needs**. The table splits its key
across one 8192-deep memory *per field* (32/32/8/16/16 bits), and on Cyclone IV a
narrow-but-deep memory rounds up to whole M9K blocks, wasting most of each. 493
M9Ks are needed where 432 exist. Packing the key fields into one wide memory is
the obvious thing to try, and would likely bring the design inside the device
without touching the P4. It is worth doing before trusting the numbers: the new path adds
`oflat` (a 1280-bit combinational vector) and 32 unrolled beat lanes, and while
nothing here adds a *writer* to a slot array — the usual multi-driver trap —
the area and Fmax effect is unmeasured. Gating `slot_in_valid_*` on
`can_change_len` also *removes* dead per-slot arrays from every other app, which
should help them slightly.

**`flowcache` not ported.** Step 5 as written paired `InsertVLAN` with a
`flowcache` port. The shell blocker is gone, so that is now an app-level task
rather than an RTL one, and it is the natural next piece.

## Original notes on steps 4 and 5


- **Step 4 — length-dependent metadata.** `packet_length` and the byte counters
  still report the **received** length, which is the documented default and is
  what v1model means. What is *not* yet handled is a program that recomputes a
  length field of its own (`ipv4.totalLen`) after inserting a header — it would
  have to do that arithmetic itself in P4, which is fine, but worth stating.
- **Step 5 — turn on `fiveTuple`'s `InsertVLAN`.** The shell can now do it; what
  remains is a testbench that configures a table entry with `action=InsertVLAN`
  and checks a 4-byte VLAN tag really appears. That is the payoff this whole
  phase was for, and it is now a testbench change rather than an RTL one.
