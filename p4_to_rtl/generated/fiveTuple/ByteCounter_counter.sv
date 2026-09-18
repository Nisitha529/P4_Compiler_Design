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

  always_ff @(posedge clk) begin
    if (byte_clearing) begin
      byte_mem[byte_clr_idx] <= 64'd0;
      if (byte_clr_idx == DEPTH-1) begin
        byte_clearing <= 1'b0;
      end else begin
        byte_clr_idx <= byte_clr_idx + 1'b1;
      end
      byte_a_v <= 1'b0; byte_b_v <= 1'b0;
    end else begin
      // stage A
      byte_a_v   <= incr_fire && incr_req;
      byte_a_idx <= incr_idx;
      byte_a_len  <= pkt_byte_len;
      byte_mem_q <= byte_mem[incr_idx];
      // stage B
      byte_b_v <= byte_a_v;
      if (byte_a_v) begin
        byte_mem[byte_a_idx] <= byte_nxt;
        byte_b_idx <= byte_a_idx;
        byte_b_new <= byte_nxt;
      end
    end
  end

  // Control-plane query, read-only: a read-only variant of exact-match
  // tables' own CP query pipeline (emit_table.py) -- registered port-B
  // read, sticky result held until the next query, no key-tag compare
  // (direct-indexed, not hashed) and no delete branch.
  logic q_pend_valid;
  logic [12:0] q_pend_addr;
  logic [63:0] q_rd_byte;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      q_pend_valid <= 1'b0;
    end else if (cp_query_en && !q_pend_valid && !(byte_clearing)) begin
      q_pend_valid <= 1'b1;
      q_pend_addr  <= cp_query_idx;
      q_rd_byte   <= byte_mem[cp_query_idx];
    end else begin
      q_pend_valid <= 1'b0;
    end
  end
  assign cp_query_busy = q_pend_valid;

  // Sticky result: held until the next query, so a polling driver can
  // check !cp_query_busy then read at leisure, no single-cycle window.
  logic [63:0] q_byte_r;
  always_ff @(posedge clk) begin
    if (q_pend_valid) begin
      q_byte_r <= q_rd_byte;
    end
  end
  assign cp_query_byte_value = q_byte_r;

endmodule
