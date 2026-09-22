# P4RTL Architecture — Proposal v1

**Status:** DRAFT for discussion. Nothing in the compiler targets this yet.
**Architecture file:** [`p4src/arch/p4rtl.p4`](../p4src/arch/p4rtl.p4) — type-checks under p4test with every declaration exercised (Appendix A).
**Supersedes:** `xsa.p4` (AMD/Xilinx property) as the target for the XSA-path apps.

---

## 1. Why a project-owned architecture

`xsa.p4` is AMD's. It is also about 50 lines: one four-field `standard_metadata_t`, four externs, and a package of parser → *one* match-action stage → deparser. It is a "P4-to-RTL block" architecture, not a switch architecture, and porting real applications to it has exposed where that runs out.

This proposal is not a wish list. Every gap below was hit while porting `load_balance`, building `UserExtern`, or making the standard-metadata fields real, and every addition has an RTL contract (§5) describing exactly what the generated shell or the compiler owns.

## 2. What xsa.p4 is missing

| # | Gap | Where we hit it |
|---|-----|-----------------|
| 1 | **No forwarding model.** No `ingress_port`, no `egress_port`, no multicast. Every app invents `meta.egress_port`; the shell cannot know which user field is the port. | `load_balance_xsa` — the egress decision is only observable because the compiler exports arbitrary metadata on a sideband. |
| 2 | **Single stage, no egress.** No queueing point, no per-egress-port processing. | `qos` — an egress-side concept on real hardware. |
| 3 | **No packet-level primitives.** No `clone`, `recirculate`, `resubmit`, `truncate`, `digest`. MAC learning is inexpressible. | The bmv2 externs left unimplemented in `complex_app`, `mri`, `source_routing`. |
| 4 | **State is under-specified.** No `register`/`meter` (deliberate, and sound). But `UserExtern` is a pure function of one input — no address, no read/write, no atomicity. The escape hatch leaves the hardest problem entirely to the user. | `firewall` port abandoned; `regprobe` needed an out-of-architecture overlay. |
| 5 | **Fixed-latency externs only.** No ready/valid; the pipeline cannot stall. External DRAM, crypto engines, anything with variable latency is out. | `UserExtern(fixed_latency_in_cycles)` by construction. |
| 6 | **Incomplete standard metadata.** No total packet length (the shell computes it for counters but P4 can't read it), no egress timestamp, no checksum-error flag. | `pkt_byte_len` exists in every top and is invisible to the program. |
| 7 | **Declared but unsupported.** `range`, `field_mask`, and a `match_kind` literally named `unused`. | The compiler silently compiles a `range` key as exact. |
| 8 | **Unspecified semantics.** What happens after parser reject? What does `drop` mean — discard or mark? | We chose "forward with `parser_error` set, let the control decide"; xsa.p4 doesn't say. |

## 3. Design rules

These came out of debugging, and they matter more than the feature list.

1. **Every `standard_metadata_t` field has a named producer or consumer in the shell.** Three of xsa.p4's four fields were dead RTL for months — declared, ported, tied to nothing — and compiled without a warning. A field with no shell-side owner does not go in the struct.
2. **Every extern comes with an RTL contract, not just a P4 signature.** `UserExtern` only became real once "the compiler owns the latency staging, the user owns the body" was written down and tested.
3. **A stateful primitive states its hazard semantics.** A `Register` with undefined read-after-write behaviour across back-to-back packets is worse than no register, because it works in single-packet tests and fails under load.
4. **Declare only what the compiler compiles.** No `unused`. No `range` until the emitter has it.
5. **Additive over xsa.p4 wherever possible.** Every existing XSA app should port by changing the include and the package name.

## 4. The proposed architecture (v1)

Full text in `p4src/arch/p4rtl.p4`. Summary of what changes relative to xsa.p4:

### 4.1 Standard metadata

```p4
struct standard_metadata_t {
    // written by the shell BEFORE the parser
    PortId_t     ingress_port;
    bit<16>      packet_length;
    bit<64>      ingress_timestamp;
    // written by the parser
    bit<16>      parsed_bytes;
    error        parser_error;
    // written by the pipeline, READ by the shell after it
    bit<1>       drop;
    PortId_t     egress_port;
    McastGroup_t mcast_group;      // 0 = unicast
}
```

Four fields kept from xsa.p4 (all now real), four added. The grouping — *shell writes / parser writes / pipeline writes* — is the contract.

### 4.2 Externs

| Extern | Status | Notes |
|--------|--------|-------|
| `UserExtern<I,O>(latency)` | kept | unchanged |
| `Counter<W,S>` | kept | unchanged |
| `Checksum<H>`, `InternetChecksum` | kept | unchanged |
| **`Register<T,S>(size)`** | new | `read`/`write`, with the hazard rule in §5.3 |
| **`Meter<S>(n)`** | new | single-rate two-colour, `execute(index, out color)` |
| **`Digest<T>()`** | new | `pack(data)` — control-plane notification, packet unaffected |

### 4.3 Pipeline

`Parser → Ingress → Egress → Deparser`, package `P4RtlPipeline<H,M>`.
**Revised 2026-09-19 (user decision, after the streaming shell landed):** the
egress stage is in v1, with **PHV pass-through** — egress receives the header
vector and metadata exactly as ingress left them, no re-parse. The queueing
point between the two is the streaming shell's slot ring; `drop` is sticky
across it. Contract and step plan: `docs/egress_stage_plan.md`.

### 4.4 Removed

`match_kind { range, field_mask, unused }`. `core.p4` already provides `exact`, `ternary`, `lpm` — the three the emitter implements.

## 5. RTL contracts

This is the part that makes it an architecture rather than a header file.

### 5.1 Port model (`ingress_port`, `egress_port`, `mcast_group`)

- **Shell provides `ingress_port`** as a top-level input (`input logic [8:0] ingress_port`), sampled at start-of-packet, held for the packet.
- **Shell exposes `egress_port` and `mcast_group`** as top-level outputs, latched at packet commit exactly as the existing metadata sideband is — this is that mechanism, given standard names so a platform can act on them.
- **Multicast is the platform's job.** `mcast_group != 0` is presented on the sideband; the shell emits the packet once. Replication belongs in the egress fabric, not in this pipeline. This keeps the shell single-packet and avoids the deepest cut (packet replication) in v1.

### 5.2 `packet_length`

Already computed (`pkt_byte_len`, currently gated on byte-counters). Ungated and connected to `std_meta_packet_length`. Zero new logic.

### 5.3 `Register<T,S>` — the hazard rule

Emitted exactly as today's `--register-ram` path: a synchronous-read memory, write registered, one pipeline boundary in front of every `.read()`.

**Contract:** a `read(index)` by packet *N* returns the value committed by the most recent `write(index)` from any packet that entered the pipeline **at least `REGISTER_RAW_DISTANCE` packets earlier**, where that distance is a per-design constant the compiler reports (it equals the number of pipeline stages between the read stage and the write stage). Two packets closer than that to the same index may observe stale data.

That is not a limitation being hidden — it is what the hardware does, said out loud. A program needing atomic RMW across back-to-back packets (a true per-flow counter under line-rate hits to one flow) uses a `UserExtern` with its own bypass network. The firewall's bloom filter — write on SYN, read on the reverse flow many packets later — is well inside the contract, which is why the earlier decision to deprioritize it can be revisited under this architecture.

### 5.4 `Meter<S>`

Per-index token bucket, `execute(index, out color)`. Emitted like `Counter`: a standalone module with a registered RMW on the bucket, rate/burst programmed over AXI4-Lite alongside the table regmap. Same hazard rule as `Register` (a bucket read sees writes ≥ distance packets earlier), which for a rate limiter is acceptable — a few packets of slack in the colour decision is normal.

### 5.5 `Digest<T>`

`pack(data)` pushes `data` into a FIFO readable over AXI4-Lite (`digest_valid`, `digest_data` words, `digest_pop`). Fixed depth; on overflow the newest is dropped and a sticky overflow bit is set. The packet is unaffected. This is the metadata-sideband idea applied to a queue instead of a latch.

### 5.6 Parser reject (semantics xsa.p4 never stated)

A failing `verify()` transitions to `reject`. The packet **continues through the pipeline** with `parser_error` set and headers after the failing state marked invalid. The control block decides what to do; the default program behaviour (no check) is to forward. This is what the shell implements today; the architecture now says so.

### 5.7 `drop`

`drop = 1` means the shell emits nothing for this packet. It is a discard, not a mark. Stated because xsa.p4 didn't.

## 6. Compiler impact

Honest sizing. "Works" means verified end-to-end today on the XSA path.

| Item | State | Work |
|------|-------|------|
| Read `standard_metadata_t` from the program | works | none — widths already come from the dump |
| `ingress_timestamp`, `parsed_bytes`, `parser_error` | works | none |
| `drop` | works | none |
| Metadata sideband (basis for `egress_port`/`mcast_group`) | works | rename/standardise the shell ports |
| `ingress_port` | **done 2026-09-22** | top-level input, sampled at SOP into the packet's slot |
| `packet_length` | **done 2026-09-22** | connected; reading it makes the app store-and-forward (§5.2) |
| `UserExtern`, `Counter`, `Checksum`, `InternetChecksum` | works | none |
| `Register` | **done 2026-09-22** — `Register<T,S>` is ingested natively; was declared-but-uncompilable | still optional: make `--register-ram` the default for this arch |
| `Meter` | — | new `emit_meter.py`, modelled on `emit_counters.py` (registered RMW + AXI4-Lite programming) |
| `Digest` | — | FIFO + AXI4-Lite read port in the shell; call site is a one-line push |
| Package/arch detection (`P4RtlPipeline`) | — | `main.py::_detect_p4_arch`, `ingest_p4ir::_detect_arch`/`_extract_control_names`: a few lines each |
| `mcast_group` | — | one more sideband field; replication is out of scope |

Nothing in v1 requires touching the staging machinery, the table emitters, or the parser lowering.

## 7. Phasing

**v1 (this proposal):** everything in §4. Port `fiveTuple`, `load_balance_xsa`, and the three probes by changing the include and package name; they must pass their existing top-level tests unchanged. Then rebuild the `firewall` on `Register` under the §5.3 contract — the app that xsa.p4 could not express.

**v2 candidates, in order of value:**
1. **Variable-latency extern** — `UserExternVL<I,O>` with ready/valid. Needs a pipeline stall, which is real work in `emit_processing`, but is what lets the pipeline talk to DRAM.
2. ~~**Egress stage**~~ — moved into v1 (§4.3). What remains v2 is a real traffic manager (per-port queues) between the two controls.
3. `clone` / `recirculate` — need packet replication in the shell.

Deliberately not planned: `range` match (no demand), `resubmit`.

## 8. Open questions

1. **`PortId_t` width.** 9 bits (v1model convention, 512 ports) vs the DE2-115's actual port count. Wider costs nothing in the pipeline; it only sizes the sideband.
2. **Meter model.** Single-rate two-colour is the simplest that is useful. srTCM/trTCM (three-colour) if there is a use case.
3. **`Register` RAW distance — report or enforce?** Reporting it (a `[INFO]` line and a comment in the RTL) is v1. Enforcing it (the compiler inserts a bypass) is what makes back-to-back RMW safe and is a v2 candidate.
4. **Keep `xsa.p4` support?** Yes — the compiler reads the architecture from the program, so both coexist. The question is only which one new apps target.

---

## Appendix A — validation

`p4src/arch/p4rtl.p4` was checked with

```
p4test --std p4-16 -I <p4c>/p4include -I p4src/arch probe.p4
```

against a program that exercises every declaration: `Register` read+write, `Counter`, `Meter` with a `RED` drop, `Digest` on a table miss, `Checksum<CRC16>` over a tuple, a 2-cycle `UserExtern` writing `egress_port`, `verify()` with a program-declared error compared against `parser_error`, `packet_length`, `ingress_port`, and `mcast_group`. Exit 0, no errors. The probe is reproduced below; it is not yet compilable by `main.py` (package detection is a §6 item).

```p4
#include <core.p4>
#include "p4rtl.p4"
header eth_t { bit<48> dst; bit<48> src; bit<16> etype; }
struct headers  { eth_t eth; }
struct metadata { bit<16> h; MeterColor_t c; bit<8> st; }
error { BadEther }
parser P(packet_in b, out headers hdr, inout metadata meta, inout standard_metadata_t sm) {
    state start { b.extract(hdr.eth); verify(hdr.eth.etype != 0xFFFF, error.BadEther); transition accept; }
}
control IG(inout headers hdr, inout metadata meta, inout standard_metadata_t sm) {
    Register<bit<8>, bit<12>>(4096) flow_state;
    Counter<bit<64>, bit<9>>(512, CounterType_t.PACKETS_AND_BYTES) per_port;
    Meter<bit<9>>(512) port_meter;
    Digest<bit<48>>() learn;
    Checksum<bit<16>>(HashAlgorithm_t.CRC16) h16;
    UserExtern<bit<48>, bit<9>>(2) mac_lookup;
    action fwd(PortId_t p) { sm.egress_port = p; }
    table l2 { key = { hdr.eth.dst: exact; } actions = { fwd; NoAction; } size = 1024; }
    apply {
        per_port.count(sm.ingress_port);
        port_meter.execute(sm.ingress_port, meta.c);
        if (meta.c == MeterColor_t.RED) { sm.drop = 1; }
        h16.apply<tuple<bit<48>, bit<48>>, bit<16>>({hdr.eth.dst, hdr.eth.src}, meta.h);
        flow_state.read(meta.st, (bit<12>)meta.h);
        flow_state.write((bit<12>)meta.h, meta.st + 1);
        if (!l2.apply().hit) { learn.pack(hdr.eth.src); mac_lookup.apply(hdr.eth.dst, sm.egress_port); }
        if (sm.packet_length > 1500) { sm.drop = 1; }
        if (sm.parser_error != error.NoError) { sm.drop = 1; }
        sm.mcast_group = 0;
    }
}
control EG(inout headers hdr, inout metadata meta, inout standard_metadata_t sm) {
    Counter<bit<64>, bit<9>>(512, CounterType_t.PACKETS) tx_pkts;
    action smac(bit<48> m) { hdr.eth.src = m; }
    table port_smac { key = { sm.egress_port: exact; } actions = { smac; NoAction; } size = 512; }
    apply { port_smac.apply(); tx_pkts.count(sm.egress_port); }
}
control D(packet_out b, in headers hdr, inout metadata meta, inout standard_metadata_t sm) { apply { b.emit(hdr.eth); } }
P4RtlPipeline(P(), IG(), EG(), D()) main;
```
