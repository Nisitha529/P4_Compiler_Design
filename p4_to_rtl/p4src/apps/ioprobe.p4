// ============================================================================
// ioprobe.p4 -- regression fixture for the three shell-sourced standard
// metadata fields that describe the packet's ARRIVAL, rather than its
// contents: ingress_port, packet_length and parsed_bytes.
//
// Each has a distinct contract, and each was wrong or missing before:
//
//   * ingress_port   -- a top-level input, sampled at START OF PACKET into
//                       the packet's slot. Issue is cut-through and can fire
//                       while RX is already receiving a LATER packet, so a
//                       live read at issue would hand the pipeline the wrong
//                       packet's port. T4 drives a changing port value during
//                       a back-to-back burst precisely to catch that.
//   * packet_length  -- the whole frame's byte count, so it is not known
//                       until tlast. A program that reads it is issued
//                       store-and-forward; every other program stays
//                       cut-through. T2 uses frames of four different sizes.
//   * parsed_bytes   -- bytes consumed by extract(), i.e. 14 for a non-IP
//                       frame and 34 for an IPv4 one, INDEPENDENT of the
//                       frame's size. It used to be wired to the shell's
//                       running received-byte counter, which at a cut-through
//                       issue reported whichever beats had arrived (32 for
//                       every frame here) -- T3 pins the real value.
//
// The egress control is deliberately empty: this also covers a P4RtlPipeline
// app that has no egress stage, which must behave exactly like the
// single-control path.
// ============================================================================
#include <core.p4>
#include "p4rtl.p4"

header eth_t  { bit<48> dst; bit<48> src; bit<16> etype; }
header ipv4_t {
    bit<4>  version; bit<4>  ihl;    bit<8>  diffserv; bit<16> totalLen;
    bit<16> id;      bit<3>  flags;  bit<13> fragOffset;
    bit<8>  ttl;     bit<8>  protocol; bit<16> hdrChecksum;
    bit<32> srcAddr; bit<32> dstAddr;
}
struct headers  { eth_t eth; ipv4_t ipv4; }
struct metadata { bit<9> iport; bit<16> plen; bit<16> pbytes; }

parser MyParser(packet_in b, out headers hdr, inout metadata meta,
                inout standard_metadata_t smeta) {
    state start {
        b.extract(hdr.eth);
        transition select(hdr.eth.etype) { 16w0x0800 : parse_ipv4; default : accept; }
    }
    state parse_ipv4 { b.extract(hdr.ipv4); transition accept; }
}

control MyIngress(inout headers hdr, inout metadata meta,
                  inout standard_metadata_t smeta) {
    action fwd(PortId_t port) { smeta.egress_port = port; }
    table port_fwd {
        key            = { smeta.ingress_port : exact; }
        actions        = { fwd; NoAction; }
        size           = 16;
        default_action = NoAction();
    }
    apply {
        // Copied to the sideband so a testbench can read all three per packet.
        meta.iport  = smeta.ingress_port;
        meta.plen   = smeta.packet_length;
        meta.pbytes = smeta.parsed_bytes;
        port_fwd.apply();
        // A behavioural use of packet_length, not just a copy: oversized
        // frames are dropped, which only works if the value is final.
        if (smeta.packet_length > 16w128) { smeta.drop = 1; }
    }
}

control MyEgress(inout headers hdr, inout metadata meta,
                 inout standard_metadata_t smeta) { apply { } }

control MyDeparser(packet_out b, in headers hdr, inout metadata meta,
                   inout standard_metadata_t smeta) {
    apply { b.emit(hdr.eth); b.emit(hdr.ipv4); }
}

P4RtlPipeline(MyParser(), MyIngress(), MyEgress(), MyDeparser()) main;
