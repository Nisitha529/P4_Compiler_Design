// ============================================================================
// p4rtl.p4 -- proposed project-owned P4_16 architecture (v1 DRAFT)
//
// See docs/architecture_proposal_v1.md for the rationale, the RTL contract
// behind every declaration, and what the compiler still has to build.
//
// Design rules this file follows (learned the hard way on xsa.p4):
//   1. Every standard_metadata_t field has a named producer or consumer in
//      the generated shell. Nothing here is decorative.
//   2. Every extern has an RTL contract, written down in the proposal.
//   3. Nothing is declared that the compiler cannot compile. No `range`,
//      no `field_mask`, no `unused`.
//   4. Stateful primitives state their hazard semantics.
//
// Single match-action stage, like xsa.p4. An egress stage is a v2 item.
// ============================================================================
#include <core.p4>

// ── Port model ──────────────────────────────────────────────────────────────
typedef bit<9>  PortId_t;
typedef bit<16> McastGroup_t;

// ── Standard metadata ───────────────────────────────────────────────────────
struct standard_metadata_t {
    // -- written by the shell BEFORE the parser --
    PortId_t     ingress_port;        // physical port the frame arrived on
    bit<16>      packet_length;       // total bytes on the wire (not just parsed)
    bit<64>      ingress_timestamp;   // free-running cycle counter, sampled at SOP

    // -- written by the parser --
    bit<16>      parsed_bytes;        // bytes consumed by extract()
    error        parser_error;        // NoError unless a verify() failed

    // -- written by the pipeline, READ by the shell after it --
    bit<1>       drop;                // 1 = discard; nothing else below matters
    PortId_t     egress_port;         // unicast destination
    McastGroup_t mcast_group;         // 0 = unicast; else replicate to the group
}

// ── Opaque user block, fixed latency (unchanged from xsa.p4) ────────────────
extern UserExtern<I, O> {
    UserExtern(bit<16> fixed_latency_in_cycles);
    void apply(in I data_in, out O result);
}

// ── Stateful storage with DEFINED hazard semantics ──────────────────────────
// A read returns the value committed by any packet that entered the pipeline
// at least REGISTER_RAW_DISTANCE packets earlier (see proposal §5.3). Two
// packets closer than that may observe stale data; a program that needs
// atomic read-modify-write across back-to-back packets must use a UserExtern
// with its own bypass logic. Making that rule explicit is the whole point.
extern Register<T, S> {
    Register(bit<32> size);
    void read(out T result, in S index);
    void write(in S index, in T value);
}

// ── Counters (unchanged from xsa.p4) ────────────────────────────────────────
enum CounterType_t { PACKETS, BYTES, PACKETS_AND_BYTES }
extern Counter<W, S> {
    Counter(bit<32> n_counters, CounterType_t type);
    void count(in S index);
}

// ── Meter: single-rate two-colour, one bucket per index ─────────────────────
enum MeterColor_t { GREEN, RED }
extern Meter<S> {
    Meter(bit<32> n_meters);
    void execute(in S index, out MeterColor_t color);
}

// ── Digest: notify the control plane, does not affect the packet ───────────
extern Digest<T> {
    Digest();
    void pack(in T data);
}

// ── Hashing / checksums (unchanged from xsa.p4) ─────────────────────────────
enum HashAlgorithm_t { CRC32, CRC16, ONES_COMPLEMENT16 }
extern Checksum<H> {
    Checksum(HashAlgorithm_t hash);
    void apply<T, W>(in T data, out W result);
}
extern InternetChecksum {
    InternetChecksum();
    void clear();
    void add<T>(in T data);
    void subtract<T>(in T data);
    void get<W>(out W result);
}

// ── Pipeline ────────────────────────────────────────────────────────────────
parser  Parser<H, M>(packet_in b, out H hdr, inout M meta,
                     inout standard_metadata_t standard_metadata);
control MatchAction<H, M>(inout H hdr, inout M meta,
                          inout standard_metadata_t standard_metadata);
control Deparser<H, M>(packet_out b, in H hdr, inout M meta,
                       inout standard_metadata_t standard_metadata);

package P4RtlPipeline<H, M>(Parser<H, M> p, MatchAction<H, M> ma, Deparser<H, M> dep);
