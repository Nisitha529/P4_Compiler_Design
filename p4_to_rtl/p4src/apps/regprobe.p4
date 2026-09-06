// ============================================================================
// regprobe.p4 -- minimal XSA-architecture application that exercises the
// `register` extern. It is the only xsa-path app with registers, so it is the
// regression fixture for two things:
//   * ingest_p4ir.py's register-declaration parse (p4test prints the
//     constructor size as a width-prefixed literal, `32w4096`, not `4096`)
//   * emit_processing.py's `--register-ram` synchronous-read emission on the
//     p4test frontend
//
// Deliberately NOT degenerate: the read and write addresses are different
// expressions and the write is conditional, so the memory cannot be constant-
// folded away by synthesis (an earlier version used one address and a constant
// write value, and Quartus optimized the whole array out -- 0 memory bits;
// a constant write VALUE additionally makes every flip-flop "stuck at VCC" in
// the default async-read form, which would flatter the --register-ram control).
//
// The read result is left in METADATA only -- deliberately. That is the check
// that user-metadata OUTPUT ports work: user metadata used to be emitted as
// input-only (`input logic [0:0] meta_v1`, no `out_meta_*`), so this value
// could not leave the module and Quartus deleted the entire 4096x1 RAM as dead
// logic (0 memory bits). xsa.p4's standard_metadata_t has no egress_spec /
// egress_port / ingress_port at all, so user metadata is the ONLY channel an
// XSA app has for a per-packet decision -- which is why this had to be fixed
// rather than worked around.
// ============================================================================
#include <core.p4>
#include "xsa_ext.p4"

header eth_t { bit<48> dst; bit<48> src; bit<16> etype; }

struct headers  { eth_t eth; }
struct metadata { bit<1> v1; bit<32> pos; }

parser MyParser(packet_in b, out headers hdr, inout metadata meta,
                inout standard_metadata_t smeta) {
    state start { b.extract(hdr.eth); transition accept; }
}

control MyProcessing(inout headers hdr, inout metadata meta,
                     inout standard_metadata_t smeta) {
    register<bit<1>>(4096) bloom_1;
    apply {
        // Write address derived from the source MAC, read address from the
        // destination MAC -- independent, so the RAM has two real ports.
        if (hdr.eth.etype == 16w0x0800) {
            bloom_1.write((bit<32>)hdr.eth.src[31:0], hdr.eth.dst[0:0]);
        }
        bloom_1.read(meta.v1, (bit<32>)hdr.eth.dst[31:0]);
    }
}

control MyDeparser(packet_out b, in headers hdr, inout metadata meta,
                   inout standard_metadata_t smeta) {
    apply { b.emit(hdr.eth); }
}

XilinxPipeline(MyParser(), MyProcessing(), MyDeparser()) main;
