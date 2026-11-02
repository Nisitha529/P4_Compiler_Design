// ============================================================================
// uramprobe.p4 -- fixture for the BOARD-SELECTED RAM-STYLE PRAGMA on Register
// storage.
//
// Two Registers, deliberately on opposite sides of emit_processing.py's
// URAM_MIN_BITS threshold (288Kb, one UltraScale+ URAM block):
//
//   small  1024 x bit<32>  =   32Kb  -> the board's ordinary block-RAM pragma
//   big   16384 x bit<32>  =  512Kb  -> the board's uram_style_pragma
//
// boards/vcu118.json has carried uram_style_pragma since it was added, with a
// note in its own `notes` field saying no emitter read it -- so on VU9P a large
// table silently went to block RAM, which is the difference between fitting and
// not. This fixture is what makes "the pragma is emitted" a test.
//
// COMPILE-TIME fixture: what it checks is the generated attribute, not
// simulated behaviour, so it has no testbench. See scripts/check_uram.sh.
// ============================================================================
#include <core.p4>
#include "p4rtl.p4"
header eth_t { bit<48> dst; bit<48> src; bit<16> etype; }
struct headers  { eth_t eth; }
struct metadata { bit<32> a; bit<32> b; bit<16> idx; }
parser MyParser(packet_in b, out headers hdr, inout metadata meta,
                inout standard_metadata_t smeta) {
    state start { b.extract(hdr.eth); transition accept; }
}
control MyIngress(inout headers hdr, inout metadata meta,
                  inout standard_metadata_t smeta) {
    Register<bit<32>, bit<16>>(1024)  small;
    Register<bit<32>, bit<16>>(16384) big;
    apply {
        meta.idx = hdr.eth.etype;
        small.read(meta.a, meta.idx);
        big.read(meta.b, meta.idx);
        small.write(meta.idx, meta.a + 1);
        big.write(meta.idx, meta.b + 1);
        smeta.egress_port = 1;
    }
}
control MyEgress(inout headers hdr, inout metadata meta,
                 inout standard_metadata_t smeta) { apply { } }
control MyDeparser(packet_out b, in headers hdr, inout metadata meta,
                   inout standard_metadata_t smeta) { apply { b.emit(hdr.eth); } }
P4RtlPipeline(MyParser(), MyIngress(), MyEgress(), MyDeparser()) main;
