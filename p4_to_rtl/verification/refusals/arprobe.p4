// arprobe.p4 -- a program the compiler MUST REFUSE.
//
// Not an application: a negative test. `switch (t.apply().action_run)` used to
// be accepted and silently produce an INERT control block -- the table was
// instantiated and never applied, no switch arm ran, egress_port was only ever
// assigned its default, and the compiler reported success. A design that
// forwards nothing and drops nothing, compiled "successfully", is the worst
// failure mode this compiler has.
//
// It now exits 2 with a message naming the construct. This file is what keeps
// that true: scripts/check_refusals.sh compiles it and requires the refusal.
// It lives OUTSIDE p4src/apps/ so the ordinary build sweep does not try to
// compile it as an application.
//
// If support is added later (p4test keeps the switch and lifts each arm into a
// hidden table, and emit_processing already dispatches per action id), this
// file moves to p4src/apps/ and becomes a positive test instead.
#include <core.p4>
#include "p4rtl.p4"
header eth_t { bit<48> dst; bit<48> src; bit<16> etype; }
struct headers  { eth_t eth; }
struct metadata { bit<16> tag; }
parser MyParser(packet_in b, out headers hdr, inout metadata meta,
                inout standard_metadata_t smeta) {
    state start { b.extract(hdr.eth); transition accept; }
}
control MyIngress(inout headers hdr, inout metadata meta,
                  inout standard_metadata_t smeta) {
    action a_one() { meta.tag = 16w0x1111; }
    action a_two() { meta.tag = 16w0x2222; }
    table t {
        key = { hdr.eth.etype : exact; }
        actions = { a_one; a_two; NoAction; }
        size = 16;
        default_action = NoAction();
    }
    apply {
        // The construct under test. Each arm must reach the RTL.
        switch (t.apply().action_run) {
            a_one: { smeta.egress_port = 1; }
            a_two: { smeta.egress_port = 2; }
            default: { smeta.drop = 1; }
        }
    }
}
control MyEgress(inout headers hdr, inout metadata meta,
                 inout standard_metadata_t smeta) { apply { } }
control MyDeparser(packet_out b, in headers hdr, inout metadata meta,
                   inout standard_metadata_t smeta) { apply { b.emit(hdr.eth); } }
P4RtlPipeline(MyParser(), MyIngress(), MyEgress(), MyDeparser()) main;
