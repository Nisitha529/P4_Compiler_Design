// ============================================================================
// lmprobe.p4 -- link_monitor's byte-counting half, on P4RtlPipeline.
//
// link_monitor.p4 itself CANNOT be ported: its parser walks a header stack
// (hdr.probe_data.next/.last) and its egress does push_front(1), which both
// needs dynamic header stacks -- explicitly out of scope for this compiler --
// and GROWS the packet, which the shell's fixed header/payload beat split
// forbids. What is portable is the half that motivated the work below, and
// this fixture is exactly that half, kept faithful to the original:
//
//   byte_cnt_reg.read (byte_cnt, egress_port);
//   byte_cnt = byte_cnt + packet_length;
//   new_byte_cnt = probe ? 0 : byte_cnt;          // a probe resets the count
//   byte_cnt_reg.write(egress_port, new_byte_cnt);
//
// It is the first fixture combining all three of this pass's changes:
//   * Register<T,S>   -- p4rtl.p4's own spelling, which used to produce RTL
//                        referencing undeclared signals
//   * packet_length   -- accumulated, so a wrong value is visible as a wrong sum
//   * EGRESS state    -- registers living in the egress control, indexed by
//                        the egress_port ingress chose
//
// The running total is reported on the metadata sideband instead of in a
// pushed probe header, since pushing one is what the shell cannot do.
//
// Hazard note: p4rtl.p4 states that a register read sees writes from packets
// at least REGISTER_RAW_DISTANCE earlier. T4 measures that distance for this
// program rather than assuming it.
// ============================================================================
#include <core.p4>
#include "p4rtl.p4"

const bit<16> TYPE_PROBE = 0x0801;

header eth_t { bit<48> dst; bit<48> src; bit<16> etype; }
struct headers  { eth_t eth; }
struct metadata { bit<32> byte_total; bit<9> port_seen; }

parser MyParser(packet_in b, out headers hdr, inout metadata meta,
                inout standard_metadata_t smeta) {
    state start { b.extract(hdr.eth); transition accept; }
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
    apply { port_fwd.apply(); }
}

control MyEgress(inout headers hdr, inout metadata meta,
                 inout standard_metadata_t smeta) {
    Register<bit<32>, bit<4>>(16) byte_cnt_reg;

    apply {
        bit<32> byte_cnt;
        bit<32> new_byte_cnt;
        byte_cnt_reg.read(byte_cnt, (bit<4>)smeta.egress_port);
        byte_cnt = byte_cnt + (bit<32>)smeta.packet_length;
        // A probe frame reports the accumulated total and resets it, exactly
        // as link_monitor resets on a probe passing through.
        new_byte_cnt = (hdr.eth.etype == TYPE_PROBE) ? 32w0 : byte_cnt;
        byte_cnt_reg.write((bit<4>)smeta.egress_port, new_byte_cnt);
        meta.byte_total = byte_cnt;
        meta.port_seen  = smeta.egress_port;
    }
}

control MyDeparser(packet_out b, in headers hdr, inout metadata meta,
                   inout standard_metadata_t smeta) { apply { b.emit(hdr.eth); } }

P4RtlPipeline(MyParser(), MyIngress(), MyEgress(), MyDeparser()) main;
