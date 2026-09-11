// ============================================================================
// smprobe.p4 -- regression fixture for the ARCHITECTURE-DRIVEN standard
// metadata model.
//
// xsa.p4's standard_metadata_t is {drop, ingress_timestamp, parsed_bytes,
// parser_error} and shares only `drop` with v1model's. The compiler used to
// carry a hardcoded v1model width table and default anything it did not
// recognise to 9 bits, so all three of the fields this app touches were
// silently wrong:
//   * ingress_timestamp  bit<64> -> emitted as [8:0]  (55 bits silently lost)
//   * parsed_bytes       bit<16> -> emitted as [8:0]
//   * parser_error       error   -> emitted as [8:0], and `error.NoError`
//                                   reached the RTL verbatim, failing
//                                   elaboration ("Unable to bind ... error.NoError")
// and none of the three was driven at the top level at all.
//
// Widths now come from the architecture's own struct as it appears in the
// p4test MidEnd dump, so this fixture exercises a field of EACH kind the model
// has to handle: a wide bit<> (64), a narrow bit<> (16), and the `error` enum
// type (whose width is derived from the error-value count).
//
// The testbench drives a 64-bit timestamp with high bits set precisely so that
// a regression to the old 9-bit default cannot pass.
// ============================================================================
#include <core.p4>
#include "xsa.p4"
header eth_t { bit<48> dst; bit<48> src; bit<16> etype; }
struct headers  { eth_t eth; }
struct metadata { bit<64> ts; bit<16> nbytes; }
parser MyParser(packet_in b, out headers hdr, inout metadata meta,
                inout standard_metadata_t smeta) {
    state start { b.extract(hdr.eth); transition accept; }
}
control MyProcessing(inout headers hdr, inout metadata meta,
                     inout standard_metadata_t smeta) {
    apply {
        meta.ts     = smeta.ingress_timestamp;
        meta.nbytes = smeta.parsed_bytes;
        if (smeta.parser_error != error.NoError) { smeta.drop = 1; }
    }
}
control MyDeparser(packet_out b, in headers hdr, inout metadata meta,
                   inout standard_metadata_t smeta) { apply { b.emit(hdr.eth); } }
XilinxPipeline(MyParser(), MyProcessing(), MyDeparser()) main;
