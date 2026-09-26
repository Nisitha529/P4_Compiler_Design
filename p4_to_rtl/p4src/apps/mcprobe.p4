// ============================================================================
// mcprobe.p4 -- multicast REPLICATION on the traffic manager
// (docs/traffic_manager_plan.md step 5).
//
// One packet in, N packets out: ingress sets standard_metadata.mcast_group and
// the shell's replication table turns that into one copy per member port. Each
// copy runs EGRESS separately with its own egress_port, so per-port rewrites
// and per-port drops apply per copy -- which is exactly why egress lives after
// the traffic manager rather than before it.
//
// The v1model multicast.p4 also prunes the copy heading back out the port the
// packet arrived on; that check needs ingress_port, which this architecture now
// has, so it is preserved here.
//
//   0x0001 -> unicast to port 1        (no replication)
//   0x00FF -> multicast group 1        (whatever ports the CP programmed)
//   anything else -> no match, port 0
// ============================================================================
#include <core.p4>
#include "p4rtl.p4"

header eth_t { bit<48> dst; bit<48> src; bit<16> etype; }
struct headers  { eth_t eth; }
struct metadata { bit<9> in_port; }

parser MyParser(packet_in b, out headers hdr, inout metadata meta,
                inout standard_metadata_t smeta) {
    state start { b.extract(hdr.eth); transition accept; }
}

control MyIngress(inout headers hdr, inout metadata meta,
                  inout standard_metadata_t smeta) {
    action fwd(PortId_t port)      { smeta.egress_port = port; }
    action mcast(McastGroup_t grp) { smeta.mcast_group = grp; }
    table l2 {
        key            = { hdr.eth.etype : exact; }
        actions        = { fwd; mcast; NoAction; }
        size           = 16;
        default_action = NoAction();
    }
    apply {
        meta.in_port = smeta.ingress_port;
        l2.apply();
    }
}

control MyEgress(inout headers hdr, inout metadata meta,
                 inout standard_metadata_t smeta) {
    action set_smac(bit<48> smac) { hdr.eth.src = smac; }
    table port_smac {
        key            = { smeta.egress_port : exact; }
        actions        = { set_smac; NoAction; }
        size           = 16;
        default_action = NoAction();
    }
    apply {
        // Loop prune: never send a copy back out the port it came in on.
        // Needs ingress_port, and runs per COPY.
        if (smeta.egress_port == meta.in_port) { smeta.drop = 1; }
        port_smac.apply();
    }
}

control MyDeparser(packet_out b, in headers hdr, inout metadata meta,
                   inout standard_metadata_t smeta) { apply { b.emit(hdr.eth); } }

P4RtlPipeline(MyParser(), MyIngress(), MyEgress(), MyDeparser()) main;
