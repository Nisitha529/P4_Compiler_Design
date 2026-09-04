/*
 * load_balance_xsa.p4 — ECMP load balancer for the XilinxPipeline (xsa.p4)
 * architecture.
 *
 * Functional port of p4src/apps/load_balance.p4 (v1model/V1Switch), which is
 * left untouched as the bmv2 regression reference. The packet-processing
 * behaviour is preserved; the differences below are forced by the target
 * architecture, not by choice:
 *
 *   1. XilinxPipeline has a single MatchAction control -- there is no separate
 *      egress stage. The original's egress-stage `send_frame` table (keyed on
 *      the resolved egress port, rewriting the source MAC) folds into the same
 *      control, applied right after the next-hop table that chooses the port.
 *      The dependency order is identical, so behaviour is unchanged.
 *
 *   2. xsa.p4's standard_metadata_t carries only {drop, ingress_timestamp,
 *      parsed_bytes, parser_error} -- there is no egress_spec/egress_port.
 *      The chosen output port therefore lives in user metadata
 *      (meta.egress_port), and dropping uses standard_metadata.drop, which is
 *      this architecture's own drop mechanism (there is no mark_to_drop()).
 *
 *   3. v1model's hash() extern does not exist here. The equivalent is
 *      Checksum<H>(HashAlgorithm_t.CRC16), which returns a raw CRC with no
 *      base/range arguments. v1model computed `base + (hash % count)`; a
 *      runtime modulo is expensive in hardware, so bucket selection uses a
 *      mask instead -- `base + (hash & mask)` with power-of-two group sizes,
 *      which is standard practice in real ECMP hardware and preserves
 *      flow-consistent (per-5-tuple) bucket assignment. Control-plane entries
 *      must therefore supply ecmp_mask = group_size - 1.
 *
 *   4. update_checksum() in a dedicated MyComputeChecksum control has no
 *      equivalent stage; the IPv4 header checksum is recomputed inline with
 *      xsa.p4's InternetChecksum extern instead. Same RFC 1071 result.
 */

#include <core.p4>
#include "xsa.p4"

const bit<16> TYPE_IPV4 = 0x0800;
const bit<8>  TYPE_TCP  = 6;

typedef bit<48> macAddr_t;
typedef bit<32> ip4Addr_t;
typedef bit<9>  portId_t;

header ethernet_t {
    macAddr_t dstAddr;
    macAddr_t srcAddr;
    bit<16>   etherType;
}

header ipv4_t {
    bit<4>    version;
    bit<4>    ihl;
    bit<8>    diffserv;
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

header tcp_t {
    bit<16> srcPort;
    bit<16> dstPort;
    bit<32> seqNo;
    bit<32> ackNo;
    bit<4>  dataOffset;
    bit<3>  res;
    bit<3>  ecn;
    bit<6>  ctrl;
    bit<16> window;
    bit<16> checksum;
    bit<16> urgentPtr;
}

/* Struct names must be exactly `headers` / `metadata` -- the p4test ingestion
 * path keys on those names when registering header instances. */
struct headers {
    ethernet_t ethernet;
    ipv4_t     ipv4;
    tcp_t      tcp;
}

struct metadata {
    bit<14>   ecmp_select;   // chosen ECMP bucket (key into ecmp_nhop)
    portId_t  egress_port;   // replaces v1model's standard_metadata.egress_spec
}

parser MyParser(packet_in packet,
                out headers hdr,
                inout metadata meta,
                inout standard_metadata_t smeta) {

    state start {
        transition parse_ethernet;
    }

    state parse_ethernet {
        packet.extract(hdr.ethernet);
        transition select(hdr.ethernet.etherType) {
            TYPE_IPV4 : parse_ipv4;
            default   : accept;
        }
    }

    state parse_ipv4 {
        packet.extract(hdr.ipv4);
        transition select(hdr.ipv4.protocol) {
            TYPE_TCP : parse_tcp;
            default  : accept;
        }
    }

    state parse_tcp {
        packet.extract(hdr.tcp);
        transition accept;
    }
}

control MyProcessing(inout headers hdr,
                     inout metadata meta,
                     inout standard_metadata_t smeta) {

    bit<16> ecmp_hash_val;

    Checksum<bit<16>>(HashAlgorithm_t.CRC16) ecmp_hash;
    InternetChecksum() ipv4_ck;

    action drop_pkt() {
        smeta.drop = 1;
    }

    /* Selects an ECMP bucket for this flow. ecmp_base is the group's first
     * bucket, ecmp_mask is (group_size - 1) -- see note 3 in the file header
     * for why this is a mask rather than v1model's modulo. */
    action set_ecmp_select(bit<14> ecmp_base, bit<16> ecmp_mask) {
        ecmp_hash.apply({ hdr.ipv4.srcAddr,
                          hdr.ipv4.dstAddr,
                          hdr.ipv4.protocol,
                          hdr.tcp.srcPort,
                          hdr.tcp.dstPort },
                        ecmp_hash_val);
        meta.ecmp_select = ecmp_base + (bit<14>)(ecmp_hash_val & ecmp_mask);
    }

    /* Identical to the v1model original: rewrites the destination MAC and the
     * destination IP to the next hop, selects the output port, decrements TTL. */
    action set_nhop(macAddr_t nhop_dmac, ip4Addr_t nhop_ipv4, portId_t port) {
        hdr.ethernet.dstAddr = nhop_dmac;
        hdr.ipv4.dstAddr     = nhop_ipv4;
        meta.egress_port     = port;
        hdr.ipv4.ttl         = hdr.ipv4.ttl - 1;
    }

    action rewrite_mac(macAddr_t smac) {
        hdr.ethernet.srcAddr = smac;
    }

    table ecmp_group {
        key            = { hdr.ipv4.dstAddr : lpm; }
        actions        = { set_ecmp_select; drop_pkt; NoAction; }
        size           = 64;
        default_action = NoAction();
    }

    table ecmp_nhop {
        key            = { meta.ecmp_select : exact; }
        actions        = { set_nhop; drop_pkt; NoAction; }
        size           = 16;
        default_action = NoAction();
    }

    /* Was the v1model egress-stage table; folded in here (see note 1). */
    table send_frame {
        key            = { meta.egress_port : exact; }
        actions        = { rewrite_mac; drop_pkt; NoAction; }
        size           = 16;
        default_action = NoAction();
    }

    apply {
        if (hdr.ipv4.isValid() && hdr.ipv4.ttl > 0) {
            if (ecmp_group.apply().hit) {
                ecmp_nhop.apply();
                send_frame.apply();
            }
        }

        /* Recompute the IPv4 header checksum -- TTL and dstAddr above both
         * invalidate the received one. Same field list as the original's
         * update_checksum() call. */
        ipv4_ck.clear();
        ipv4_ck.add({ hdr.ipv4.version,
                      hdr.ipv4.ihl,
                      hdr.ipv4.diffserv,
                      hdr.ipv4.totalLen,
                      hdr.ipv4.identification,
                      hdr.ipv4.flags,
                      hdr.ipv4.fragOffset,
                      hdr.ipv4.ttl,
                      hdr.ipv4.protocol,
                      hdr.ipv4.srcAddr,
                      hdr.ipv4.dstAddr });
        ipv4_ck.get(hdr.ipv4.hdrChecksum);
    }
}

control MyDeparser(packet_out packet,
                   in headers hdr,
                   inout metadata meta,
                   inout standard_metadata_t smeta) {
    apply {
        packet.emit(hdr.ethernet);
        packet.emit(hdr.ipv4);
        packet.emit(hdr.tcp);
    }
}

XilinxPipeline(
    MyParser(),
    MyProcessing(),
    MyDeparser()
) main;
