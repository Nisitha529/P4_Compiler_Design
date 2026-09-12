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

// A program-declared error, so the fixture also covers the error-enum
// numbering: core.p4's 8 standard errors come first, so this is value 8.
error { BadEtherType }

header eth_t { bit<48> dst; bit<48> src; bit<16> etype; }
struct headers  { eth_t eth; }
struct metadata { bit<64> ts; bit<16> nbytes; }
parser MyParser(packet_in b, out headers hdr, inout metadata meta,
                inout standard_metadata_t smeta) {
    state start {
        b.extract(hdr.eth);
        // parser_error's PRODUCER. Before verify() was lowered into the top's
        // parallel extractor this could only ever reach the standalone parser
        // FSM, which no generated top instantiates -- so parser_error was
        // permanently NoError in the synthesized design.
        verify(hdr.eth.etype != 16w0xFFFF, error.BadEtherType);
        transition accept;
    }
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
