module ByteCounter_counter #(
  parameter int DEPTH = 8192
) (
  input  logic clk,
  input  logic rst_n,

  // Increment request, from processing_generated -- one-cycle pulse per
  // packet, raised at whatever pipeline stage the .count() action runs.
  input  logic              incr_req,
  input  logic [12:0] incr_idx,
  // pkt_commit: proc_settle&&!proc_committed -- latches the request.
  // pkt_done  : pkt_ready_to_clear -- applies the RMW, once per packet,
  //             deliberately one step later so pkt_byte_len (below) is
  //             final by the time a BYTES-type counter reads it (a
  //             cut-through packet's length is NOT yet known at
  //             pkt_commit time -- see emit_top.py's instantiation site).
  input  logic pkt_commit,
  input  logic pkt_done,
  input  logic [15:0] pkt_byte_len,

  // Control-plane query (read-only -- counters aren't operator-settable,
  // only queryable; no delete/write port exists).
  input  logic              cp_query_en,
  input  logic [12:0] cp_query_idx,
  output logic              cp_query_busy,
  output logic [63:0]       cp_query_byte_value
);

  // Decouples "request" (raised mid-packet, before length is final)
  // from "apply" (once per packet, once pkt_byte_len is final). Safe
  // with no cross-packet hazard: this pipeline is single-packet-in-
  // flight (packet N+1 cannot start until N has fully drained), so at
  // most one increment is ever pending at a time.
  logic pend_valid;
  logic [12:0] pend_idx;
  always_ff @(posedge clk) begin
    if (!rst_n) pend_valid <= 1'b0;
    else if (pkt_commit && incr_req) begin
      pend_valid <= 1'b1;
      pend_idx   <= incr_idx;
    end else if (pkt_done && pend_valid) begin
      pend_valid <= 1'b0;
    end
  end

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

  typedef enum logic { BYTE_INCR_IDLE, BYTE_INCR_APPLY } byte_incr_st_t;
  byte_incr_st_t byte_incr_st = BYTE_INCR_IDLE;
  logic [12:0] byte_incr_addr_r;
  logic [63:0] byte_rd_data;
  // pkt_byte_len is reset by the top level on the SAME edge
  // pkt_done first pulses (preparing for the next packet), but
  // APPLY (below) does not consume the delta until the FOLLOWING
  // cycle -- reading pkt_byte_len directly there would race that
  // reset and always see 0. Capture it here, on the same edge as
  // the IDLE->APPLY transition (before the top level's own reset
  // takes effect, by ordinary non-blocking-assignment semantics),
  // and use the captured copy in APPLY instead of the live port.
  logic [15:0] byte_len_captured;

  always_ff @(posedge clk) begin
    if (byte_clearing) begin
      byte_mem[byte_clr_idx] <= 64'd0;
      if (byte_clr_idx == DEPTH-1) begin
        byte_clearing <= 1'b0;
      end else begin
        byte_clr_idx <= byte_clr_idx + 1'b1;
      end
    end else begin
      case (byte_incr_st)
        BYTE_INCR_IDLE: if (pkt_done && pend_valid) begin
          byte_incr_addr_r <= pend_idx;
          byte_rd_data     <= byte_mem[pend_idx];
          byte_len_captured <= pkt_byte_len;
          byte_incr_st     <= BYTE_INCR_APPLY;
        end
        BYTE_INCR_APPLY: begin
          byte_mem[byte_incr_addr_r] <= byte_rd_data + {48'd0, byte_len_captured};
          byte_incr_st <= BYTE_INCR_IDLE;
        end
        default: ;
      endcase
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
