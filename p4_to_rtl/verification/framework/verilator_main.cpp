// verilator_main.cpp -- harness for the coverage build of a generated design.
//
// Verilator's own --main does everything this does EXCEPT write the coverage
// database: in 5.006 the generated main has no VerilatedCov call, so a
// --coverage build runs and then throws the measurement away. The event loop
// below is Verilator 5.006's own generated loop, copied deliberately so the
// --timing semantics stay exactly what that version expects, with the coverage
// write added at the end.
//
// The model's class is fixed as Vdut by passing --prefix Vdut, so this one
// file serves every app rather than needing a per-app include.
#include <memory>

#include "verilated.h"
#include "verilated_cov.h"

#include "Vdut.h"

int main(int argc, char** argv, char**) {
    Verilated::debug(0);
    const std::unique_ptr<VerilatedContext> contextp{new VerilatedContext};
    contextp->commandArgs(argc, argv);     // carries the +plusargs through

    const std::unique_ptr<Vdut> topp{new Vdut{contextp.get()}};

    while (!contextp->gotFinish()) {
        topp->eval();
        if (!topp->eventsPending()) break;
        contextp->time(topp->nextTimeSlot());
    }
    topp->final();

    // The point of this file. +cov_out=<path> keeps each app's database
    // separate; without it they would overwrite one another in a sweep.
    const char* out = "coverage.dat";
    std::string buf;
    if (contextp->commandArgsPlusMatch("cov_out=")[0] != '\0') {
        buf = contextp->commandArgsPlusMatch("cov_out=");
        const size_t eq = buf.find('=');
        if (eq != std::string::npos) {
            buf = buf.substr(eq + 1);
            out = buf.c_str();
        }
    }
    contextp->coveragep()->write(out);
    return 0;
}
