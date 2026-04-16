// minimal working P4 program

parser ParserImpl(packet_in packet) {
    state start {
        transition accept;
    }
}

control IngressImpl() {
    apply { }
}

control EgressImpl() {
    apply { }
}

control DeparserImpl(packet_out packet) {
    apply { }
}

V1Switch(
    ParserImpl(),
    IngressImpl(),
    EgressImpl(),
    DeparserImpl()
) main;