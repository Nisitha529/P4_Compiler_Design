// ============================================================================
// egprobe.p4 -- regression fixture for the P4RtlPipeline EGRESS stage with
// PHV pass-through (docs/egress_stage_plan.md).
//
// Ingress decides; egress acts on the decision. Every contract of the
// ingress -> egress boundary has a packet that only passes if it holds:
//
//   * PHV pass-through   : egress reads hdr.eth.etype as ingress LEFT it (ingress
//                          rewrites etype for one class of frame; egress keys
//                          on the rewritten value) and rewrites hdr.eth.src.
//   * egress_port        : written by ingress (std meta), read by egress as a
//                          table key, and exposed on the sideband.
//   * sticky drop        : ingress drops etype 0xBAD1 frames. Egress must not
//                          be able to resurrect them, AND its per-port counter
//                          must not count them -- a dropped packet never "runs"
//                          egress. Egress itself drops etype 0xBEEF frames
//                          (after ingress forwarded them), so both directions
//                          of the boundary are exercised.
//   * shell std-meta in egress: egress copies ingress_timestamp into user
//                          metadata. The shell samples it at ISSUE for this
//                          packet; under back-to-back traffic a later packet's
//                          live counter value would be wrong.
//   * egress counters    : tx_pkts counts per egress_port, queried over AXI.
//
// Frame classes (by etype):  0x0001..0x0004 -> port N via l2 table (ingress),
//   0x00F0 -> ingress rewrites etype to 0x0002 and port 2 (pass-through test),
//   0xBAD1 -> ingress drop, 0xBEEF -> port 1 then egress drop, else no match
//   (port stays 0, egress leaves the frame alone).
// ============================================================================
#include <core.p4>
#include "p4rtl.p4"

header eth_t { bit<48> dst; bit<48> src; bit<16> etype; }
struct headers  { eth_t eth; }
struct metadata { bit<64> ts; }

parser MyParser(packet_in b, out headers hdr, inout metadata meta,
                inout standard_metadata_t smeta) {
    state start { b.extract(hdr.eth); transition accept; }
}

control MyIngress(inout headers hdr, inout metadata meta,
                  inout standard_metadata_t smeta) {
    action fwd(PortId_t port) { smeta.egress_port = port; }
    action drop_pkt()         { smeta.drop = 1; }
    action retag()            { hdr.eth.etype = 16w0x0002; smeta.egress_port = 2; }
    table l2 {
        key            = { hdr.eth.etype : exact; }
        actions        = { fwd; drop_pkt; retag; NoAction; }
        size           = 16;
        default_action = NoAction();
    }
    apply { l2.apply(); }
}

control MyEgress(inout headers hdr, inout metadata meta,
                 inout standard_metadata_t smeta) {
    Counter<bit<64>, bit<4>>(16, CounterType_t.PACKETS) tx_pkts;
    action set_smac(bit<48> smac) { hdr.eth.src = smac; }
    action drop_pkt()             { smeta.drop = 1; }
    table port_smac {
        key            = { smeta.egress_port : exact; }
        actions        = { set_smac; NoAction; }
        size           = 16;
        default_action = NoAction();
    }
    apply {
        meta.ts = smeta.ingress_timestamp;
        // Egress sees the etype as ingress LEFT it: a retagged 0x00F0 frame
        // arrives here as 0x0002, and only 0xBEEF is dropped here.
        if (hdr.eth.etype == 16w0xBEEF) { drop_pkt(); }
        port_smac.apply();
        tx_pkts.count((bit<4>)smeta.egress_port);
    }
}

control MyDeparser(packet_out b, in headers hdr, inout metadata meta,
                   inout standard_metadata_t smeta) { apply { b.emit(hdr.eth); } }

P4RtlPipeline(MyParser(), MyIngress(), MyEgress(), MyDeparser()) main;
