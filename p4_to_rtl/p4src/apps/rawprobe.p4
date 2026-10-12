// ============================================================================
// rawprobe.p4 -- fixture for the reported Register READ-AFTER-WRITE DISTANCE.
//
// A register read, a table apply, then the write-back, so the read and the
// write land in DIFFERENT pipeline stages and the reported distance is > 1.
// Every other app in the tree reads and writes in the same stage and reports 1,
// so without this the multi-stage arithmetic was never exercised.
//
// This is a COMPILE-TIME fixture: what it checks is the [INFO] line, not
// simulated behaviour, so it has no testbench. Expected output:
//
//   [INFO] Register 'last_ts': RAW distance 3 packet(s)
//          (read stage 0, write-back stage 2)
//
// It is also the shape a per-flow feature feed uses (last-seen timestamp, flow
// packet index), which is why the number matters: a burst of same-flow packets
// is what a scan or a flood looks like, and that is exactly when packets are
// closest together and most likely to read the pre-update value.
// ============================================================================
#include <core.p4>
#include "p4rtl.p4"
header eth_t { bit<48> dst; bit<48> src; bit<16> etype; }
struct headers  { eth_t eth; }
struct metadata { bit<32> prev; bit<16> idx; }
parser MyParser(packet_in b, out headers hdr, inout metadata meta,
                inout standard_metadata_t smeta) {
    state start { b.extract(hdr.eth); transition accept; }
}
control MyIngress(inout headers hdr, inout metadata meta,
                  inout standard_metadata_t smeta) {
    Register<bit<32>, bit<16>>(1024) last_ts;
    action set_port(PortId_t p) { smeta.egress_port = p; }
    table fwd {
        key = { hdr.eth.etype : exact; }
        actions = { set_port; NoAction; }
        size = 16; default_action = NoAction();
    }
    apply {
        meta.idx = hdr.eth.etype;
        last_ts.read(meta.prev, meta.idx);     // stage R
        fwd.apply();                            // a stage boundary
        last_ts.write(meta.idx, meta.prev + 1); // stage W, later
    }
}
control MyEgress(inout headers hdr, inout metadata meta,
                 inout standard_metadata_t smeta) { apply { } }
control MyDeparser(packet_out b, in headers hdr, inout metadata meta,
                   inout standard_metadata_t smeta) { apply { b.emit(hdr.eth); } }
P4RtlPipeline(MyParser(), MyIngress(), MyEgress(), MyDeparser()) main;
