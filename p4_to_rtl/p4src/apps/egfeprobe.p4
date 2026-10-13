// ============================================================================
// egfeprobe.p4 -- FeatureExport from the EGRESS stage.
//
// feprobe.p4 covers an ingress push. Egress is a different case and had to be
// tested separately for two reasons:
//
//   * the egress stage runs at DEQUEUE, which is the only place enq_qdepth /
//     deq_qdepth mean anything -- so a QoS or congestion feature has to be
//     exported from here, not from ingress;
//   * egress runs for a packet INGRESS ALREADY DROPPED (the shell drives it on
//     deq_fire with drop_in carrying the sticky decision). The egress Counter
//     gates itself on !drop_in so dropped packets are not counted; a push()
//     has no such gate, so whether a dropped packet produces a record was
//     unknown until this probe measured it.
//
// Record: deq_qdepth[15:0] ++ eth.dst[15:0] = 32 bits, a byte multiple, with
// two independent sources so a swapped field is obvious.
// ============================================================================
#include <core.p4>
#include "p4rtl.p4"

header eth_t  { bit<48> dst; bit<48> src; bit<16> etype; }

struct headers  { eth_t eth; }
struct metadata { bit<16> qd; }

parser MyParser(packet_in b, out headers hdr, inout metadata meta,
                inout standard_metadata_t smeta) {
    state start { b.extract(hdr.eth); transition accept; }
}

control MyIngress(inout headers hdr, inout metadata meta,
                  inout standard_metadata_t smeta) {
    action set_port(PortId_t p) { smeta.egress_port = p; }
    action drop_it()            { smeta.drop = 1; }
    table fwd {
        key     = { hdr.eth.etype : exact; }
        actions = { set_port; drop_it; NoAction; }
        size    = 16;
        default_action = NoAction();
    }
    apply { fwd.apply(); }
}

control MyEgress(inout headers hdr, inout metadata meta,
                 inout standard_metadata_t smeta) {

    FeatureExport<bit<32>>() qos_feed;

    apply {
        // Deliberately UNGATED by drop: what that does is the thing under test.
        meta.qd = (bit<16>)smeta.deq_qdepth;
        qos_feed.push(meta.qd ++ hdr.eth.dst[15:0]);
    }
}

control MyDeparser(packet_out b, in headers hdr, inout metadata meta,
                   inout standard_metadata_t smeta) {
    apply { b.emit(hdr.eth); }
}

P4RtlPipeline(MyParser(), MyIngress(), MyEgress(), MyDeparser()) main;
