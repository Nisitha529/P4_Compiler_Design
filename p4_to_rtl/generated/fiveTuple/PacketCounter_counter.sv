module PacketCounter_counter #(
  parameter int DEPTH = 8192
) (
  input  logic clk,
  input  logic rst_n,

  // Increment request: ONE cycle per packet, everything valid together.
  // incr_fire pulses when the shell releases a packet's slot (its byte
  // length is final by then); incr_req says whether this packet's
  // .count() ran, incr_idx which entry. The old two-phase commit/done
  // interface held a single pending request and a 2-cycle RMW, and
  // LOST a count when releases came 2 cycles apart (measured: 33 of 34
  // back-to-back minimum packets). This path accepts one request per
  // cycle -- see the pipelined RMW below.
  input  logic              incr_fire,
  input  logic              incr_req,
  input  logic [12:0] incr_idx,

  // Control-plane query (read-only -- counters aren't operator-settable,
  // only queryable; no delete/write port exists).
  input  logic              cp_query_en,
  input  logic [12:0] cp_query_idx,
  output logic              cp_query_busy,
  output logic [63:0]       cp_query_pkt_value
);

  // ── Control-plane query state ─────────────────────────────────────────
  logic q_pend_valid;
  logic q_rd_fired;    // the shared-port read actually went through
  logic [12:0] q_pend_addr;
  logic [63:0] q_rd_pkt;

  // pkt sub-counter: 64-bit value per index, real
  // block-RAM-safe registered read-modify-write (never a bare
  // combinational `assign` read -- Quartus does not infer BRAM for that
  // shape).
  logic [63:0] pkt_mem [0:DEPTH-1];

  // Power-on clear: real Cyclone IV BRAM content is unspecified at
  // power-up (an initial block does not reach synthesis -- see the
  // identical rationale for exact-match tables' mem_valid clear FSM
  // in emit_table.py). Walks every address once before any real
  // increment or query is trusted. An increment/query issued during
  // this window is silently not applied that cycle -- accepted as a
  // low-probability startup-only edge case, same tolerance already
  // established for tables' own clear FSM.
  logic pkt_clearing = 1'b1;
  logic [12:0] pkt_clr_idx = '0;

  logic              pkt_a_v;
  logic [12:0] pkt_a_idx;
  logic [63:0]       pkt_mem_q;
  logic              pkt_b_v;
  logic [12:0] pkt_b_idx;
  logic [63:0]       pkt_b_new;
  wire  [63:0]       pkt_cur = (pkt_b_v && pkt_b_idx == pkt_a_idx) ? pkt_b_new : pkt_mem_q;
  wire  [63:0]       pkt_nxt = pkt_cur + 64'd1;

  // The pipeline registers: no memory access here.
  always_ff @(posedge clk) begin
    if (pkt_clearing) begin
      if (pkt_clr_idx == DEPTH-1) pkt_clearing <= 1'b0;
      else                          pkt_clr_idx <= pkt_clr_idx + 1'b1;
      pkt_a_v <= 1'b0; pkt_b_v <= 1'b0;
    end else begin
      // stage A
      pkt_a_v   <= incr_fire && incr_req;
      pkt_a_idx <= incr_idx;
      // stage B
      pkt_b_v <= pkt_a_v;
      if (pkt_a_v) begin
        pkt_b_idx <= pkt_a_idx;
        pkt_b_new <= pkt_nxt;
      end
    end
  end

  // Port A: bidirectional -- the clear sweep and the increment
  // write-back, or else the control-plane query read.
  wire pkt_wr = pkt_clearing || pkt_a_v;
  wire [63:0] pkt_wr_data = pkt_clearing ? 64'd0 : pkt_nxt;
  logic [12:0] pkt_pa_addr;
  always_comb begin
    if      (pkt_clearing) pkt_pa_addr = pkt_clr_idx;
    else if (pkt_a_v)      pkt_pa_addr = pkt_a_idx;
    else                     pkt_pa_addr = q_pend_addr;
  end
  always_ff @(posedge clk) begin
    if (pkt_wr) begin
      pkt_mem[pkt_pa_addr] <= pkt_wr_data;
      q_rd_pkt               <= pkt_wr_data;
    end else begin
      q_rd_pkt               <= pkt_mem[pkt_pa_addr];
    end
  end

  // Port B: the read-modify-write read. NO reset -- a reset on a
  // memory's read-output register blocks true-dual-port inference
  // (measured; see emit_table.py). Unused while clearing, because
  // pkt_a_v is held low then.
  always_ff @(posedge clk) pkt_mem_q <= pkt_mem[incr_idx];

  // Control-plane query, read-only: counters are queryable but not
  // operator-settable, so there is no write or delete path. Unlike the
  // exact-match tables, this read does NOT get a port of its own -- the
  // increment path needs a concurrent read AND write on every cycle it
  // is active, which is both ports of a block RAM -- so it borrows the
  // write port on a cycle with nothing to write. That is what keeps this
  // memory to ONE copy; a port of its own cost a duplicate of every
  // counter (measured on fiveTuple: 128 M9K blocks instead of 64).
  wire q_can_read = q_pend_valid && !(pkt_wr);
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      q_pend_valid <= 1'b0;
      q_rd_fired   <= 1'b0;
    end else begin
      // One cycle behind q_can_read: that is when q_rd_* holds the data.
      q_rd_fired <= q_can_read;
      if (cp_query_en && !q_pend_valid && !(pkt_clearing)) begin
        q_pend_valid <= 1'b1;
        q_pend_addr  <= cp_query_idx;
      end else if (q_rd_fired) begin
        q_pend_valid <= 1'b0;
      end
    end
  end
  assign cp_query_busy = q_pend_valid;

  // Sticky result: held until the next query, so a polling driver can
  // check !cp_query_busy then read at leisure, no single-cycle window.
  logic [63:0] q_pkt_r;
  always_ff @(posedge clk) begin
    if (q_rd_fired) begin
      q_pkt_r <= q_rd_pkt;
    end
  end
  assign cp_query_pkt_value = q_pkt_r;

endmodule
