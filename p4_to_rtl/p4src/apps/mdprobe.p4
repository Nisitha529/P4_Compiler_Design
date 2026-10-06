// ============================================================================
// mdprobe.p4 -- regression fixture for the two p4rtl.p4 externs that were
// DECLARED but never implemented: Meter<S> and Digest<T>.
//
// Both were a trap before this: a program could legally call them, the
// compiler exited 0, and nothing happened. This app exists so that cannot
// recur silently.
//
//   * Meter   -- single-rate two-colour token bucket, one bucket per index.
//                `execute(idx, colour)` is a read-modify-write of that bucket
//                and the colour is available to THIS packet, so it has to sit
//                in the match-action pipeline (like Register.read), not be
//                deferred to slot release (like Counter.count).
//   * Digest  -- `pack(data)` pushes one entry into a FIFO the control plane
//                drains over AXI4-Lite. It must NOT affect the packet, which
//                is the property the testbench pins.
//
// The metered colour is copied into user metadata so it leaves the module and
// synthesis cannot delete the bucket as dead logic -- the same trap regprobe.p4
// documents for registers.
// ============================================================================
#include <core.p4>
#include "p4rtl.p4"

header eth_t  { bit<48> dst; bit<48> src; bit<16> etype; }

struct headers  { eth_t eth; }
struct metadata {
    bit<8>  colour;     // 0 = GREEN, 1 = RED, as the meter reported it
    bit<16> midx;       // which bucket was charged
}

parser MyParser(packet_in b, out headers hdr, inout metadata meta,
                inout standard_metadata_t smeta) {
    state start { b.extract(hdr.eth); transition accept; }
}

control MyIngress(inout headers hdr, inout metadata meta,
                  inout standard_metadata_t smeta) {

    Meter<bit<10>>(1024) rate_limit;
    Digest<bit<48>>()    seen_src;

    action pass_through(PortId_t p) {
        smeta.egress_port = p;
    }

    table fwd {
        key     = { hdr.eth.dst : exact; }
        actions = { pass_through; NoAction; }
        size    = 16;
        default_action = NoAction();
    }

    apply {
        // Charge the bucket selected by the low bits of etherType, so different
        // frames hit different buckets and the per-index state is observable.
        MeterColor_t c;
        rate_limit.execute((bit<10>)hdr.eth.etype, c);
        meta.colour = (c == MeterColor_t.RED) ? 8w1 : 8w0;
        meta.midx   = (bit<16>)hdr.eth.etype;

        // A RED packet is dropped; GREEN continues. This is the standard
        // single-rate policer shape.
        if (c == MeterColor_t.RED) {
            smeta.drop = 1;
        }

        // Tell the control plane which source MAC we saw. Must not change
        // the packet.
        seen_src.pack(hdr.eth.src);

        fwd.apply();
    }
}

control MyEgress(inout headers hdr, inout metadata meta,
                 inout standard_metadata_t smeta) { apply { } }

control MyDeparser(packet_out b, in headers hdr, inout metadata meta,
                   inout standard_metadata_t smeta) {
    apply { b.emit(hdr.eth); }
}

P4RtlPipeline(MyParser(), MyIngress(), MyEgress(), MyDeparser()) main;
