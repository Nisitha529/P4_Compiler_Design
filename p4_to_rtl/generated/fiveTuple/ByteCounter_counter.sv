module ByteCounter_counter #(
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
  input  logic [15:0] pkt_byte_len,

  // Control-plane query (read-only -- counters aren't operator-settable,
  // only queryable; no delete/write port exists).
  input  logic              cp_query_en,
  input  logic [12:0] cp_query_idx,
  output logic              cp_query_busy,
  output logic [63:0]       cp_query_byte_value
);

  // ── Control-plane query state ─────────────────────────────────────────
  logic q_pend_valid;
  logic q_rd_fired;    // the shared-port read actually went through
  logic [12:0] q_pend_addr;
  logic [63:0] q_rd_byte;

  // byte sub-counter: 64-bit value per index, real
  // block-RAM-safe registered read-modify-write (never a bare
  // combinational `assign` read -- Quartus does not infer BRAM for that
  // shape).
  logic [63:0] byte_mem [0:DEPTH-1];

  // Power-on clear: real Cyclone IV BRAM content is unspecified at
  // power-up (an initial block does not reach synthesis -- see the
  // identical rationale for exact-match tables' mem_valid clear FSM
  // in emit_table.py). Walks every address once before any real
  // increment or query is trusted. An increment/query issued during
  // this window is silently not applied that cycle -- accepted as a
  // low-probability startup-only edge case, same tolerance already
  // established for tables' own clear FSM.
  logic byte_clearing = 1'b1;
  logic [12:0] byte_clr_idx = '0;

  logic              byte_a_v;
  logic [12:0] byte_a_idx;
  logic [15:0]       byte_a_len;
  logic [63:0]       byte_mem_q;
  logic              byte_b_v;
  logic [12:0] byte_b_idx;
  logic [63:0]       byte_b_new;
  wire  [63:0]       byte_cur = (byte_b_v && byte_b_idx == byte_a_idx) ? byte_b_new : byte_mem_q;
  wire  [63:0]       byte_nxt = byte_cur + {48'd0, byte_a_len};

  // The pipeline registers: no memory access here.
  always_ff @(posedge clk) begin
    if (byte_clearing) begin
      if (byte_clr_idx == DEPTH-1) byte_clearing <= 1'b0;
      else                          byte_clr_idx <= byte_clr_idx + 1'b1;
      byte_a_v <= 1'b0; byte_b_v <= 1'b0;
    end else begin
      // stage A
      byte_a_v   <= incr_fire && incr_req;
      byte_a_idx <= incr_idx;
      byte_a_len  <= pkt_byte_len;
      // stage B
      byte_b_v <= byte_a_v;
      if (byte_a_v) begin
        byte_b_idx <= byte_a_idx;
        byte_b_new <= byte_nxt;
      end
    end
  end

  // Port A: bidirectional -- the clear sweep and the increment
  // write-back, or else the control-plane query read.
  wire byte_wr = byte_clearing || byte_a_v;
  wire [63:0] byte_wr_data = byte_clearing ? 64'd0 : byte_nxt;
  logic [12:0] byte_pa_addr;
  always_comb begin
    if      (byte_clearing) byte_pa_addr = byte_clr_idx;
    else if (byte_a_v)      byte_pa_addr = byte_a_idx;
    else                     byte_pa_addr = q_pend_addr;
  end
  always_ff @(posedge clk) begin
    if (byte_wr) begin
      byte_mem[byte_pa_addr] <= byte_wr_data;
      q_rd_byte               <= byte_wr_data;
    end else begin
      q_rd_byte               <= byte_mem[byte_pa_addr];
    end
  end

  // Port B: the read-modify-write read. NO reset -- a reset on a
  // memory's read-output register blocks true-dual-port inference
  // (measured; see emit_table.py). Unused while clearing, because
  // byte_a_v is held low then.
  always_ff @(posedge clk) byte_mem_q <= byte_mem[incr_idx];

  // Control-plane query, read-only: counters are queryable but not
  // operator-settable, so there is no write or delete path. Unlike the
  // exact-match tables, this read does NOT get a port of its own -- the
  // increment path needs a concurrent read AND write on every cycle it
  // is active, which is both ports of a block RAM -- so it borrows the
  // write port on a cycle with nothing to write. That is what keeps this
  // memory to ONE copy; a port of its own cost a duplicate of every
  // counter (measured on fiveTuple: 128 M9K blocks instead of 64).
  wire q_can_read = q_pend_valid && !(byte_wr);
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      q_pend_valid <= 1'b0;
      q_rd_fired   <= 1'b0;
    end else begin
      // One cycle behind q_can_read: that is when q_rd_* holds the data.
      q_rd_fired <= q_can_read;
      if (cp_query_en && !q_pend_valid && !(byte_clearing)) begin
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
  logic [63:0] q_byte_r;
  always_ff @(posedge clk) begin
    if (q_rd_fired) begin
      q_byte_r <= q_rd_byte;
    end
  end
  assign cp_query_byte_value = q_byte_r;

endmodule
