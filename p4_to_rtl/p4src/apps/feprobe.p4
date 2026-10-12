// ============================================================================
// feprobe.p4 -- regression fixture for FeatureExport<T>: the AXI4-Stream
// record feed that exists for the on-chip TCN accelerator.
//
// It pins the things that are easy to get wrong and silent when wrong:
//   * N packets in => N records out, when the consumer is always ready
//   * each record FIELD lands at its declared bit position (every field is
//     given a distinguishable value, so a swapped or shifted field shows up)
//   * the packet path NEVER stalls when the consumer is not ready -- records
//     are dropped (newest first) and counted, and tvalid obeys the stream
//     protocol once raised
//   * a record is produced even for a packet ingress DROPS (dropped attack
//     packets are still evidence, which is the whole point for an IDS)
//
// The record is built with ++, which is also the regression for that operator.
// Widths: 16 + 16 + 16 + 8 + 8 = 64, already a byte multiple, so no padding.
// ============================================================================
#include <core.p4>
#include "p4rtl.p4"

header eth_t  { bit<48> dst; bit<48> src; bit<16> etype; }

struct headers  { eth_t eth; }
struct metadata {
    bit<16> flow_id;
    bit<16> seen;
    bit<8>  dir;
}

parser MyParser(packet_in b, out headers hdr, inout metadata meta,
                inout standard_metadata_t smeta) {
    state start { b.extract(hdr.eth); transition accept; }
}

control MyIngress(inout headers hdr, inout metadata meta,
                  inout standard_metadata_t smeta) {

    FeatureExport<bit<64>>() tcn_feed;

    action set_port(PortId_t p) { smeta.egress_port = p; }
    action drop_it()            { smeta.drop = 1; }

    table fwd {
        key     = { hdr.eth.etype : exact; }
        actions = { set_port; drop_it; NoAction; }
        size    = 16;
        default_action = NoAction();
    }

    apply {
        // Distinguishable per-field values: the low bits of etype pick the
        // flow, the frame length and the ethertype are independent, and dir is
        // a constant so a shifted field is obvious.
        meta.dir = 8w0xA5;

        fwd.apply();

        // Pushed AFTER fwd.apply(), so a packet the table dropped still feeds
        // the TCN. That is deliberate -- see p4rtl.p4's FeatureExport note.
        // Five operands from five DIFFERENT sources, so a swapped or shifted
        // field is unmistakable and p4test's copy propagation cannot collapse
        // two of them into the same expression.
        tcn_feed.push(hdr.eth.etype ++ smeta.packet_length ++ hdr.eth.dst[15:0]
                      ++ meta.dir ++ smeta.parsed_bytes[7:0]);
    }
}

control MyEgress(inout headers hdr, inout metadata meta,
                 inout standard_metadata_t smeta) { apply { } }

control MyDeparser(packet_out b, in headers hdr, inout metadata meta,
                   inout standard_metadata_t smeta) {
    apply { b.emit(hdr.eth); }
}

P4RtlPipeline(MyParser(), MyIngress(), MyEgress(), MyDeparser()) main;
