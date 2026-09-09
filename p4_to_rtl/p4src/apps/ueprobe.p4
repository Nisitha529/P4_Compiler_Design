// ============================================================================
// ueprobe.p4 -- regression fixture for xsa.p4's UserExtern escape hatch.
//
// UserExtern is the ONLY mechanism the XilinxPipeline architecture provides for
// stateful or multi-cycle logic (it deliberately has no `register`, no meter,
// no stateful ALU), so this is the fixture for the one part of that contract
// the compiler owns and a user cannot fix from inside their own RTL: honouring
// fixed_latency_in_cycles by holding the ENTIRE rest of the packet context --
// every header field, metadata shadow, local and valid bit -- in step for
// exactly that many cycles.
//
// Two instances with DIFFERENT latencies, chained, so the pipeline has to
// absorb 3 cycles and then 1 more, and so the second one's input expression
// has to be taken from a mid-pipeline stage rather than stage 0.
//
// The results are left in METADATA, which also keeps this a live test of the
// metadata output ports (before those existed the values were dead and
// synthesis deleted the logic feeding them).
//
// See generated/ueprobe/testbench/tb_ueprobe.sv for how this is checked: the
// generated placeholder bodies are the identity delayed by the declared
// latency, so `out_meta_res == out_eth_dst[15:0]` holds for every packet iff
// the value that went THROUGH the extern and the value that went AROUND it
// took the same number of cycles.
// ============================================================================
#include <core.p4>
#include "xsa.p4"
header eth_t { bit<48> dst; bit<48> src; bit<16> etype; }
struct headers  { eth_t eth; }
struct metadata { bit<16> res; bit<8> res2; }
parser MyParser(packet_in b, out headers hdr, inout metadata meta,
                inout standard_metadata_t smeta) {
    state start { b.extract(hdr.eth); transition accept; }
}
control MyProcessing(inout headers hdr, inout metadata meta,
                     inout standard_metadata_t smeta) {
    UserExtern<bit<48>, bit<16>>(3) my_lookup;
    UserExtern<bit<16>, bit<8>>(1)  my_classify;
    apply {
        my_lookup.apply(hdr.eth.dst, meta.res);
        my_classify.apply(hdr.eth.etype, meta.res2);
    }
}
control MyDeparser(packet_out b, in headers hdr, inout metadata meta,
                   inout standard_metadata_t smeta) {
    apply { b.emit(hdr.eth); }
}
XilinxPipeline(MyParser(), MyProcessing(), MyDeparser()) main;
