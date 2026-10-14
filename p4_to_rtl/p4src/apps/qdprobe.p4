// ============================================================================
// qdprobe.p4 -- the TRAFFIC MANAGER's queue-depth arithmetic, above one packet.
//
// egfeprobe.p4 proved that deq_qdepth REACHES a FeatureExport record. It could
// not prove the depth itself was right: with the default slot ring (NSLOT=4)
// and TM_INFLIGHT=2, at most two packets can ever be waiting, so the depth it
// observed was 1 and the arithmetic above 1 was untested.
//
// This probe exports BOTH ends of a packet's queueing life --
//
//     enq_qdepth : how many packets were already in the target queue when
//                  this one was enqueued (it does not count itself)
//     deq_qdepth : how deep that queue is on the cycle this packet is
//                  dequeued (it DOES count itself)
//
// -- so a burst held behind a stalled transmitter produces a record per packet
// whose depths can be checked against the arrival order, not just against zero.
// Build it with a slot ring deep enough for a real queue:
//
//     python3 -m compiler.main qdprobe --nslot 8 --cp-map
//
// Record: enq_qdepth[7:0] ++ deq_qdepth[7:0] ++ eth.dst[15:0] = 32 bits, a
// byte multiple. eth.dst[15:0] carries the sender's sequence number, so each
// record says WHICH packet the two depths belong to -- without it a drained
// burst is just a bag of numbers.
// ============================================================================
#include <core.p4>
#include "p4rtl.p4"

header eth_t  { bit<48> dst; bit<48> src; bit<16> etype; }

struct headers  { eth_t eth; }
struct metadata { bit<8> enqd; bit<8> deqd; }

parser MyParser(packet_in b, out headers hdr, inout metadata meta,
                inout standard_metadata_t smeta) {
    state start { b.extract(hdr.eth); transition accept; }
}

control MyIngress(inout headers hdr, inout metadata meta,
                  inout standard_metadata_t smeta) {
    // The queue a packet lands in is egress_port[1:0], so the table is how the
    // test steers a burst into ONE queue (to build depth) or spreads it over
    // several (to give the scheduler a choice).
    action set_port(PortId_t p) { smeta.egress_port = p; }
    table fwd {
        key     = { hdr.eth.etype : exact; }
        actions = { set_port; NoAction; }
        size    = 16;
        default_action = NoAction();
    }
    apply { fwd.apply(); }
}

control MyEgress(inout headers hdr, inout metadata meta,
                 inout standard_metadata_t smeta) {

    FeatureExport<bit<32>>() qd_feed;

    apply {
        meta.enqd = (bit<8>)smeta.enq_qdepth;
        meta.deqd = (bit<8>)smeta.deq_qdepth;
        qd_feed.push(meta.enqd ++ meta.deqd ++ hdr.eth.dst[15:0]);
    }
}

control MyDeparser(packet_out b, in headers hdr, inout metadata meta,
                   inout standard_metadata_t smeta) {
    apply { b.emit(hdr.eth); }
}

P4RtlPipeline(MyParser(), MyIngress(), MyEgress(), MyDeparser()) main;
