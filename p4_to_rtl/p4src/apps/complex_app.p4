/* -*- P4_16 -*- */
#include <core.p4>
#include <v1model.p4>

typedef bit<48> macAddr_t;
typedef bit<32> ip4Addr_t;

header ethernet_t {
    macAddr_t dstAddr;
    macAddr_t srcAddr;
    bit<16>   etherType;
}

header mpls_t {
    bit<20> label;
    bit<3>  tc;
    bit<1>  bos;
    bit<8>  ttl;
}

header ipv4_t {
    bit<4>  version;
    bit<4>  ihl;
    bit<8>  diffserv;
    bit<16> totalLen;
    bit<16> identification;
    bit<3>  flags;
    bit<13> fragOffset;
    bit<8>  ttl;
    bit<8>  protocol;
    bit<16> hdrChecksum;
    ip4Addr_t srcAddr;
    ip4Addr_t dstAddr;
}

header tcp_t {
    bit<16> srcPort;
    bit<16> dstPort;
    bit<32> seqNo;
    bit<32> ackNo;
    bit<4>  dataOffset;
    bit<4>  reserved;
    bit<8>  flags;
    bit<16> window;
    bit<16> checksum;
    bit<16> urgentPtr;
}

header udp_t {
    bit<16> srcPort;
    bit<16> dstPort;
    bit<16> length;
    bit<16> checksum;
}

struct headers {
    ethernet_t   ethernet;
    mpls_t       mpls[3];
    ipv4_t       ipv4;
    tcp_t        tcp;
    udp_t        udp;
}

struct metadata {
    bit<9>  ingress_port;
    bit<9>  egress_port;
    bit<32> packet_length;
    bit<3>  priority;
    bit<16> mcast_grp;
    bit<16> egress_rid;
    bit<1>  checksum_error;
    bit<32> enq_timestamp;
    bit<19> enq_qdepth;
    bit<32> deq_timedelta;
    bit<19> deq_qdepth;
    bit<48> ingress_global_timestamp;
    bit<48> egress_global_timestamp;
    bit<8>  ttl;
    ip4Addr_t next_hop;
    bit<16> mpls_label_swap;
    bit<1>  drop;
    bit<1>  ecmp_select;
}

// Register for connection tracking (TCP state)
register<bit<8>>(1024) conn_state;

parser MyParser(packet_in packet, out headers hdr, inout metadata meta,
                inout standard_metadata_t stdmeta) {

    state start {
        packet.extract(hdr.ethernet);
        transition select(hdr.ethernet.etherType) {
            16w0x8847: parse_mpls_0;
            16w0x0800: parse_ipv4;
            default: accept;
        }
    }

    // Fixed 3-label unroll (matches hdr.mpls[3]'s bound) instead of a
    // dynamic hdr.mpls.next/hdr.mpls.last loop -- dynamic header-stack
    // parsing (runtime-indexed stack writes/reads driven by a data-
    // dependent extract count) is a deliberately out-of-scope compiler
    // limitation, not implemented here by design.
    state parse_mpls_0 {
        packet.extract(hdr.mpls[0]);
        transition select(hdr.mpls[0].bos) {
            1 : parse_ipv4;
            default : parse_mpls_1;
        }
    }

    state parse_mpls_1 {
        packet.extract(hdr.mpls[1]);
        transition select(hdr.mpls[1].bos) {
            1 : parse_ipv4;
            default : parse_mpls_2;
        }
    }

    state parse_mpls_2 {
        packet.extract(hdr.mpls[2]);
        // Last available label slot -- if bos still isn't set here, the
        // stack is exhausted (a malformed/over-long label stack); accept
        // rather than looping forever, since a real hardware parser FSM
        // must be bounded.
        transition select(hdr.mpls[2].bos) {
            1 : parse_ipv4;
            default : accept;
        }
    }

    state parse_ipv4 {
        packet.extract(hdr.ipv4);
        transition select(hdr.ipv4.protocol) {
            6  : parse_tcp;
            17 : parse_udp;
            default: accept;
        }
    }

    state parse_tcp {
        packet.extract(hdr.tcp);
        transition accept;
    }

    state parse_udp {
        packet.extract(hdr.udp);
        transition accept;
    }
}

control MyVerifyChecksum(inout headers hdr, inout metadata meta) {
    apply { }
}

control MyIngress(inout headers hdr, inout metadata meta,
                  inout standard_metadata_t stdmeta) {

    // Actions (must precede the tables that reference them -- P4-16 control-
    // local declarations are order-dependent, unlike top-level declarations)
    action conn_track_read() {
        bit<32> index = (bit<32>) hdr.tcp.srcPort ^ (bit<32>) hdr.tcp.dstPort;
        index = index & 1023;
        conn_state.read(meta.ttl, index);  // reuse ttl as temp
        // If connection is established, set priority
        if (meta.ttl == 1) {
            meta.priority = 1;
        }
    }

    action set_egress_port(bit<9> egress_port) {
        stdmeta.egress_port = egress_port;
    }

    action set_next_hop(ip4Addr_t next_hop) {
        meta.next_hop = next_hop;
    }

    action decrement_ttl() {
        hdr.ipv4.ttl = hdr.ipv4.ttl - 1;
        if (hdr.ipv4.ttl == 0) {
            meta.drop = 1;
        }
    }

    action swap_label(bit<20> new_label) {
        hdr.mpls[0].label = new_label;
    }

    action push_mpls(bit<20> label) {
        hdr.mpls.push_front(1);
        hdr.mpls[0].label = label;
        hdr.mpls[0].bos = 0;
        hdr.mpls[0].ttl = 64;
        hdr.ethernet.etherType = 16w0x8847;
    }

    action pop_mpls() {
        hdr.mpls.pop_front(1);
        if (hdr.mpls.size == 0) {
            hdr.ethernet.etherType = 16w0x0800;
        }
    }

    action set_priority(bit<3> prio) {
        meta.priority = prio;
    }

    action set_ecmp_hash() {
        hash(meta.ecmp_select, HashAlgorithm.crc16, (bit<16>)0,
             { hdr.ipv4.srcAddr, hdr.ipv4.dstAddr }, (bit<32>)2);
    }

    // Tables
    // Exact match on ingress port
    table port_policy {
        key = { stdmeta.ingress_port : exact; }
        actions = {
            NoAction;
            set_egress_port;
        }
        size = 64;
        default_action = NoAction();
    }

    // LPM on IPv4 destination
    table ipv4_route {
        key = { hdr.ipv4.dstAddr : lpm; }
        actions = {
            NoAction;
            set_next_hop;
            decrement_ttl;
        }
        size = 1024;
        default_action = NoAction();
    }

    // Ternary on diffserv and TCP flags
    table qos_policy {
        key = {
            hdr.ipv4.diffserv : ternary;
            hdr.tcp.flags     : ternary;
        }
        actions = {
            NoAction;
            set_priority;
        }
        size = 256;
        default_action = NoAction();
    }

    // Exact match on MPLS label for label swapping
    table mpls_swap {
        key = { hdr.mpls[0].label : exact; }
        actions = {
            NoAction;
            swap_label;
            push_mpls;
            pop_mpls;
        }
        size = 512;
        default_action = NoAction();
    }

    // Keyless table for default ECMP group
    table ecmp_group {
        actions = {
            NoAction;
            set_ecmp_hash;
        }
        default_action = set_ecmp_hash();
    }

    apply {
        // 1. Port policy
        port_policy.apply();

        // 2. Connection tracking (if TCP)
        if (hdr.tcp.isValid()) {
            conn_track_read();
        }

        // 3. MPLS processing if MPLS header present
        if (hdr.mpls[0].isValid()) {
            // If we have at least one MPLS label, apply swap/push/pop
            mpls_swap.apply();

            // If label indicates IPv4 payload, we might need to pop
            if (hdr.mpls[0].bos == 1) {
                // Last label, so after this we expect IP
                pop_mpls(); // but we might want to pop only if action says
                // However, this is just a demo; we'll let actions handle it.
            }
        }

        // 4. IPv4 routing (if IPv4 present)
        if (hdr.ipv4.isValid()) {
            // QoS based on diffserv and TCP flags
            if (hdr.tcp.isValid()) {
                qos_policy.apply();
            }
            ipv4_route.apply();
        }

        // 5. ECMP selection (using hash to pick egress port)
        ecmp_group.apply();

        // 6. Drop decision
        if (meta.drop == 1) {
            mark_to_drop(stdmeta);
        }
    }
}

control MyEgress(inout headers hdr, inout metadata meta,
                 inout standard_metadata_t stdmeta) {
    apply { }
}

control MyComputeChecksum(inout headers hdr, inout metadata meta) {
    apply { }
}

control MyDeparser(packet_out packet, in headers hdr) {
    // BMv2's deparser doesn't support if statements -- packet.emit() is
    // already a no-op for an invalid header, so a flat, unconditional emit
    // list has identical semantics to the original nested-if version.
    apply {
        packet.emit(hdr.ethernet);
        packet.emit(hdr.mpls[0]);
        packet.emit(hdr.mpls[1]);
        packet.emit(hdr.mpls[2]);
        packet.emit(hdr.ipv4);
        packet.emit(hdr.tcp);
        packet.emit(hdr.udp);
    }
}

V1Switch(MyParser(), MyVerifyChecksum(), MyIngress(), MyEgress(),
         MyComputeChecksum(), MyDeparser()) main;
