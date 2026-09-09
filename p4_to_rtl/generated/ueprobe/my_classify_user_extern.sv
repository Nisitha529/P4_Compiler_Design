// ============================================================================
// my_classify_user_extern.sv
//
//   UserExtern<bit<16>, bit<8>>(1) my_classify;
//
// PLACEHOLDER — REPLACE THE BODY WITH YOUR OWN LOGIC.
//
// This file was generated once and will NOT be regenerated or overwritten:
// once you edit it, it is your source file. Delete it to get a fresh
// placeholder back.
//
// THE CONTRACT YOU MUST KEEP
//   `result` must correspond to the `data_in` presented exactly 1 clock
//   cycle earlier — no more, no less, every cycle, with no back-pressure
//   and no variable latency. processing_generated does not inspect this
//   module: it presents data_in, then holds the entire rest of the packet
//   context (headers, metadata, locals, valid) in step for 1 cycle and
//   reads `result` on the far side. If your block takes a different number of
//   cycles, change fixed_latency_in_cycles in the P4 source and recompile —
//   do not absorb the difference here, because the packet context around you
//   will not move with it.
//
//   `valid_in` marks a real packet in the presented cycle. It is provided so
//   stateful blocks only update on real traffic; a purely combinational or
//   feed-forward block may ignore it. Note that `result` is read on the
//   1-cycle boundary regardless of valid_in.
//
// THE PLACEHOLDER BEHAVIOUR
//   A 1-deep shift register: the identity function, delayed by the
//   declared latency, then truncated from 16 to 8 bits.
//   It is latency-correct, so the generated pipeline elaborates, simulates and
//   synthesizes as-is — it simply does not compute anything useful yet.
// ============================================================================
`timescale 1ns/1ps

module my_classify (
  input  logic                clk,
  input  logic                rst_n,
  input  logic                valid_in,
  input  logic [15:0] data_in,
  output logic [7:0] result
);

  logic [15:0] my_classify_pipe [0:0];

  integer _i;
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      for (_i = 0; _i < 1; _i = _i + 1)
        my_classify_pipe[_i] <= 16'b0;
    end else begin
      my_classify_pipe[0] <= data_in;
    end
  end

  assign result = my_classify_pipe[0][7:0];

endmodule
