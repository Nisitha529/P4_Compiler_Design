// ============================================================================
// xsa_ext.p4 -- project-local extension overlay for xsa.p4.
//
// xsa.p4 is AMD/Xilinx's architecture definition and is treated as read-only
// here. It supplies UserExtern, Counter, Checksum and InternetChecksum, but
// NOT `register` -- so a stateful XSA application (the firewall's bloom
// filters, any flow-state table) has nothing to declare its state with.
//
// This overlay adds `register<T>` with the same signature v1model uses, so an
// app ported from v1model keeps its register call sites verbatim. The compiler
// already understands that shape on the p4test frontend
// (ingest_p4ir.py `-- Register externs`, emit_processing.py's register
// memories), so no compiler change is needed to consume it -- only this
// declaration, which p4test verifies and type-checks like any other extern.
//
// Use it in place of `#include "xsa.p4"`.
// ============================================================================
#include "xsa.p4"

extern register<T> {
    register(bit<32> size);
    void read(out T result, in bit<32> index);
    void write(in bit<32> index, in T value);
}
