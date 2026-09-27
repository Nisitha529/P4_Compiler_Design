// ============================================================================
// lenprobe.p4 -- regression fixture for the LENGTH-CHANGING deparser
// (docs/length_changing_deparser_plan.md).
//
// Two header instances that the parser never extracts, so both are always
// invalid on input, and the deparser emits them. Ingress makes one or both
// valid depending on the frame's etherType, which INSERTS bytes:
//
//   0x0001 -> insert `tag` (4 bytes) after ethernet          -> out = in + 4
//   0x0002 -> insert `tag` and `tag2` (8 bytes)              -> out = in + 8
//   0x0003 -> make `vlan` invalid (it WAS parsed)            -> out = in - 4
//   anything else -> untouched                               -> out = in
//
// This is the same shape as fiveTuple.p4's InsertVLAN, which is the flagship
// app's whole purpose and has never been exercisable end-to-end because the
// shell reproduces the input length exactly.
//
// The inserted headers carry recognisable constants so a testbench can find
// them by value, and the payload is a counting pattern so a shift by the wrong
// number of bytes is obvious rather than subtle.
// ============================================================================
#include <core.p4>
#include "p4rtl.p4"

header eth_t  { bit<48> dst; bit<48> src; bit<16> etype; }
header vlan_t { bit<16> tci;  bit<16> inner_etype; }
header tag_t  { bit<16> magic; bit<16> seq; }
header tag2_t { bit<16> magic2; bit<16> seq2; }

struct headers  { eth_t eth; tag_t tag; tag2_t tag2; vlan_t vlan; }
struct metadata { bit<16> unused; }

parser MyParser(packet_in b, out headers hdr, inout metadata meta,
                inout standard_metadata_t smeta) {
    state start {
        b.extract(hdr.eth);
        // Only `vlan` is ever parsed. `tag` and `tag2` are insert-only.
        transition select(hdr.eth.etype) {
            16w0x0003 : parse_vlan;
            default   : accept;
        }
    }
    state parse_vlan { b.extract(hdr.vlan); transition accept; }
}

control MyIngress(inout headers hdr, inout metadata meta,
                  inout standard_metadata_t smeta) {
    action fwd(PortId_t port) { smeta.egress_port = port; }
    action insert_one(PortId_t port) {
        smeta.egress_port = port;
        hdr.tag.setValid();
        hdr.tag.magic = 16w0xAA01;
        hdr.tag.seq   = 16w0x1111;
    }
    action insert_two(PortId_t port) {
        smeta.egress_port = port;
        hdr.tag.setValid();
        hdr.tag.magic  = 16w0xAA01;
        hdr.tag.seq    = 16w0x1111;
        hdr.tag2.setValid();
        hdr.tag2.magic2 = 16w0xBB02;
        hdr.tag2.seq2   = 16w0x2222;
    }
    action strip_vlan(PortId_t port) {
        smeta.egress_port = port;
        hdr.vlan.setInvalid();
    }
    table cls {
        key            = { hdr.eth.etype : exact; }
        actions        = { fwd; insert_one; insert_two; strip_vlan; NoAction; }
        size           = 16;
        default_action = NoAction();
    }
    apply { cls.apply(); }
}

control MyEgress(inout headers hdr, inout metadata meta,
                 inout standard_metadata_t smeta) { apply { } }

control MyDeparser(packet_out b, in headers hdr, inout metadata meta,
                   inout standard_metadata_t smeta) {
    apply {
        b.emit(hdr.eth);
        b.emit(hdr.tag);
        b.emit(hdr.tag2);
        b.emit(hdr.vlan);
    }
}

P4RtlPipeline(MyParser(), MyIngress(), MyEgress(), MyDeparser()) main;
