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
// Two match-action stages -- IngressMatchAction and EgressMatchAction, named
// for what they do -- with PHV PASS-THROUGH: the
// egress control receives the header vector and metadata exactly as ingress
// left them -- the packet is never re-parsed. The queueing point between them
// is the shell's slot ring (docs/egress_stage_plan.md). drop is sticky
// across the boundary: a packet ingress dropped never "runs" egress.
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

    // -- written by the TRAFFIC MANAGER, read by egress --
    // Depth, in packets, of the queue this packet was put into: at the moment
    // it was enqueued, and at the moment the scheduler took it out again.
    // Both are zero in ingress, which runs before the packet is queued.
    bit<19>      enq_qdepth;
    bit<19>      deq_qdepth;

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
// IMPLEMENTED. execute() is a read-modify-write of one bucket and the colour is
// available to THIS packet, so it sits in the match-action pipeline and carries
// the same hazard as Register: two packets closer together than the pipeline's
// RAW distance can both see the pre-charge state.
//
// The rate and burst are programmed over AXI4-Lite and are per INSTANCE, not
// per index -- one set of knobs for the whole array. The rate is expressed as a
// SHIFT: one unit of allowance returns every 2^cp_rate_shift cycles, which
// keeps a multiplier off the packet path. Charging is per PACKET, not per byte.
enum MeterColor_t { GREEN, RED }
extern Meter<S> {
    Meter(bit<32> n_meters);
    void execute(in S index, out MeterColor_t color);
}

// ── Digest: notify the control plane, does not affect the packet ───────────
// IMPLEMENTED. pack() pushes one entry into a 16-deep FIFO the control plane
// drains over AXI4-Lite. It never touches the packet and never applies
// backpressure: if the control plane is too slow the NEWEST entry is dropped and
// an overflow counter increments, so a notification can be lost but forwarding
// cannot stall. One pack() site per instance, with a fixed entry shape.
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

// ============================================================================
// ── Pipeline ────────────────────────────────────────────────────────────────
//
// TWO MATCH-ACTION STAGES. The control types are named for what they DO, not
// only for where they sit: a reader of this file should not have to guess
// whether match-action tables are supported. They are -- they are the point.
// Declare `table`s inside IngressMatchAction and EgressMatchAction exactly as
// you would in any P4_16 program; the compiler gives each one its own RTL
// module and its own AXI4-Lite control-plane window.
//
// (`table` is a core P4_16 language construct, so no architecture declares it
//  -- not v1model.p4, not xsa.p4, not this file. What an architecture provides
//  is the control blocks that tables go inside.)
//
//                              AXI4-Lite  (control plane)
//                                   │  s_axil_*
//                                   ▼
//                 ┌───────────────────────────────────────────┐
//                 │  regmap: one window PER TABLE (add/query/  │
//                 │  delete), counters, registers, mcast table │
//                 └──────┬──────────────────────┬──────────────┘
//                        │ cp_wr_*  /  cp_query_*
//   s_axis_*   ┌──────┐  │                      │
//  ──────────▶ │  RX  │ allocate a slot from the ring (NSLOT)
//   (AXI-S in) └───┬──┘
//                  ├─ header bytes ─▶ slot_hdr[slot]        payload beats
//                  │                                             │
//                  ▼                                             ▼
//        ┌────────────────────┐                      ┌────────────────────┐
//        │ PARSER  (inlined)  │ extract → w_*        │ pkt_beat_buf[slot] │
//        │  = Parser<H,M>     │ cutoff_byte ⇒ issue  │ re-readable;       │
//        └─────────┬──────────┘ (cut-through)        │ rewind = multicast │
//                  │                                 └─────────┬──────────┘
//                  ▼                                           │
//    ╔═══════════════════════════════════════════╗             │
//    ║  INGRESS MATCH-ACTION                     ║             │
//    ║    = IngressMatchAction<H,M>              ║             │
//    ║  ───────────────────────────────────────  ║             │
//    ║   __st0  ──▶  __st1  ──▶  __st2  ──▶ ...  ║  stages split
//    ║  ┌────────────────┐   ┌────────────────┐  ║  at table latency
//    ║  │ TABLE lookup   │──▶│ action bodies  │  ║             │
//    ║  │ hash+BRAM /    │   │ + externs      │  ║ ◀── TABLES  │
//    ║  │ LPM tree /     │   │ Register,      │  ║     LIVE    │
//    ║  │ ternary tree   │   │ Counter, ...   │  ║     HERE    │
//    ║  └────────────────┘   └────────────────┘  ║             │
//    ╚═══════════════════════╤═══════════════════╝             │
//                            ▼  result captured into the slot  │
//        ┌───────────────────────────────────────┐             │
//        │          TRAFFIC MANAGER              │             │
//        │  tmq[0..QCOUNT-1] slot-ID FIFOs       │ enq_qdepth  │
//        │  rotating-priority scheduler          │ deq_qdepth  │
//        │  multicast replication (serialised)   │             │
//        └───────────────────┬───────────────────┘             │
//                            ▼  at DEQUEUE                     │
//    ╔═══════════════════════════════════════════╗             │
//    ║  EGRESS MATCH-ACTION                      ║             │
//    ║    = EgressMatchAction<H,M>               ║ ◀── TABLES  │
//    ║  ───────────────────────────────────────  ║     LIVE    │
//    ║   __st0  ──▶  __st1  ──▶  ...             ║     HERE    │
//    ║   PHV PASS-THROUGH: never re-parsed       ║             │
//    ║   drop is STICKY from ingress             ║             │
//    ╚═══════════════════════╤═══════════════════╝             │
//                            ▼                                 │
//        ┌───────────────────────────────────────┐             │
//        │ DEPARSER (inlined) = Deparser<H,M>    │             │
//        │  received bytes + output PHV overlay; │             │
//        │  length-changing splice at tx_pstart  │             │
//        └───────────────────┬───────────────────┘             │
//                            ▼                                 │
//        ┌───────────────────────────────────────┐             │
//        │ TX beat assembly:  header │ payload ◀─┼─────────────┘
//        └───────────────────┬───────────────────┘
//                            ▼  m_axis_*   (AXI-S out)
//
// The PAYLOAD never enters the match-action path. Only the header vector does.
//
// A table looks like this -- nothing architecture-specific about it:
//
//     action set_port(PortId_t p) { standard_metadata.egress_port = p; }
//     table l2 {
//         key     = { hdr.eth.dst : exact; }    // or lpm / ternary
//         actions = { set_port; NoAction; }
//         size    = 1024;
//         default_action = NoAction();
//     }
//     apply { l2.apply(); }
//
// ============================================================================
parser  Parser<H, M>(packet_in b, out H hdr, inout M meta,
                     inout standard_metadata_t standard_metadata);

// The first match-action stage: runs BEFORE the traffic manager, so it is what
// chooses the output port / multicast group and therefore the queue.
control IngressMatchAction<H, M>(inout H hdr, inout M meta,
                                 inout standard_metadata_t standard_metadata);

// The second match-action stage: runs AFTER the traffic manager, at dequeue,
// which is what makes enq_qdepth/deq_qdepth meaningful and what lets a program
// react to congestion (ECN) or rewrite per-egress-port state.
control EgressMatchAction<H, M>(inout H hdr, inout M meta,
                                inout standard_metadata_t standard_metadata);

control Deparser<H, M>(packet_out b, in H hdr, inout M meta,
                       inout standard_metadata_t standard_metadata);

package P4RtlPipeline<H, M>(Parser<H, M> p,
                            IngressMatchAction<H, M> ig,
                            EgressMatchAction<H, M> eg,
                            Deparser<H, M> dep);
