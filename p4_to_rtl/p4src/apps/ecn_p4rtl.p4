/*
 * ecn_p4rtl.p4 -- ECN marking on the project-owned P4RtlPipeline, ported from
 * p4src/apps/ecn.p4 (v1model/V1Switch), which stays as the bmv2 reference.
 *
 * This is the app the traffic manager was built for. v1model's ECN marking
 * reads standard_metadata.enq_qdepth in EGRESS: the depth of the output queue
 * at the moment the packet was enqueued. Before the TM there was no queue to
 * have a depth, so the app could not be expressed at all; now the shell's
 * per-port queues supply it (docs/traffic_manager_plan.md step 4).
 *
 * Differences from the original, all forced by the architecture:
 *   1. egress_spec -> standard_metadata.egress_port (p4rtl has a real one).
 *   2. mark_to_drop() -> standard_metadata.drop = 1 (p4rtl's own mechanism,
 *      same as the xsa port).
 *   3. update_checksum() in MyComputeChecksum -> InternetChecksum recomputed
 *      inline at the end of egress, on the final header state. The original
 *      marks ECN in egress and then recomputes, so the order is preserved.
 *   4. The ECN threshold is scaled to this shell's queue depth. v1model's
 *      bmv2 queues are thousands of packets deep and the original uses 10;
 *      here a queue holds at most --nslot packets, so the threshold is 1 --
 *      "there was already a packet queued ahead of this one".
 */
#include <core.p4>
#include "p4rtl.p4"

const bit<16> TYPE_IPV4 = 0x0800;
const bit<19> ECN_THRESHOLD = 1;

typedef bit<48> macAddr_t;
typedef bit<32> ip4Addr_t;

header ethernet_t {
    macAddr_t dstAddr;
    macAddr_t srcAddr;
    bit<16>   etherType;
}

header ipv4_t {
    bit<4>    version;
    bit<4>    ihl;
    bit<6>    diffserv;
    bit<2>    ecn;
    bit<16>   totalLen;
    bit<16>   identification;
    bit<3>    flags;
    bit<13>   fragOffset;
    bit<8>    ttl;
    bit<8>    protocol;
    bit<16>   hdrChecksum;
    ip4Addr_t srcAddr;
    ip4Addr_t dstAddr;
}

struct headers  { ethernet_t ethernet; ipv4_t ipv4; }
struct metadata { }

parser MyParser(packet_in packet, out headers hdr, inout metadata meta,
                inout standard_metadata_t smeta) {
    state start { transition parse_ethernet; }
    state parse_ethernet {
        packet.extract(hdr.ethernet);
        transition select(hdr.ethernet.etherType) {
            TYPE_IPV4: parse_ipv4;
            default: accept;
        }
    }
    state parse_ipv4 { packet.extract(hdr.ipv4); transition accept; }
}

control MyIngress(inout headers hdr, inout metadata meta,
                  inout standard_metadata_t smeta) {
    action drop_pkt() { smeta.drop = 1; }
    action ipv4_forward(macAddr_t dstAddr, PortId_t port) {
        smeta.egress_port     = port;
        hdr.ethernet.srcAddr  = hdr.ethernet.dstAddr;
        hdr.ethernet.dstAddr  = dstAddr;
        hdr.ipv4.ttl          = hdr.ipv4.ttl - 1;
    }
    table ipv4_lpm {
        key            = { hdr.ipv4.dstAddr : lpm; }
        actions        = { ipv4_forward; drop_pkt; NoAction; }
        size           = 64;
        default_action = NoAction();
    }
    apply {
        if (hdr.ipv4.isValid()) { ipv4_lpm.apply(); }
    }
}

control MyEgress(inout headers hdr, inout metadata meta,
                 inout standard_metadata_t smeta) {
    InternetChecksum() ipv4_ck;

    action mark_ecn() { hdr.ipv4.ecn = 3; }

    apply {
        // Exactly the original's condition: only ECN-capable transports
        // (ECT(0)=2 or ECT(1)=1) are marked, and only when the queue this
        // packet was put into was already congested.
        if (hdr.ipv4.ecn == 1 || hdr.ipv4.ecn == 2) {
            if (smeta.enq_qdepth >= ECN_THRESHOLD) { mark_ecn(); }
        }
        // The original recomputes the IPv4 checksum after egress; TTL and the
        // ECN bits above both invalidate the received one.
        ipv4_ck.clear();
        ipv4_ck.add({ hdr.ipv4.version, hdr.ipv4.ihl, hdr.ipv4.diffserv, hdr.ipv4.ecn,
                      hdr.ipv4.totalLen, hdr.ipv4.identification, hdr.ipv4.flags,
                      hdr.ipv4.fragOffset, hdr.ipv4.ttl, hdr.ipv4.protocol,
                      hdr.ipv4.srcAddr, hdr.ipv4.dstAddr });
        ipv4_ck.get(hdr.ipv4.hdrChecksum);
    }
}

control MyDeparser(packet_out packet, in headers hdr, inout metadata meta,
                   inout standard_metadata_t smeta) {
    apply { packet.emit(hdr.ethernet); packet.emit(hdr.ipv4); }
}

P4RtlPipeline(MyParser(), MyIngress(), MyEgress(), MyDeparser()) main;
