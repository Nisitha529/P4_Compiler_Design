module FiveTuple_table #(
  parameter int DEPTH = 8192
) (
  input  logic clk,
  input  logic rst_n,

  // Lookup key (combinational)
  input  logic [31:0] lkp_src,
  input  logic [31:0] lkp_dst,
  input  logic [7:0] lkp_protocol,
  input  logic [15:0] lkp_table_key_sport,
  input  logic [15:0] lkp_table_key_dport,

  // Lookup result (registered — 1 cycle after lkp_* is presented)
  output logic        hit,
  output logic [0:0] action_id,
  output logic [12:0] p_counter_index,
  output logic [2:0] p_pcp,
  output logic [0:0] p_cfi,
  output logic [11:0] p_vid,

  // Control-plane write port (synchronous)
  input  logic        cp_wr_en,
  input  logic [12:0] cp_wr_idx,  // unused: exact-match tables self-address via hash(key)
  input  logic [31:0] cp_wr_key_src,
  input  logic [31:0] cp_wr_key_dst,
  input  logic [7:0] cp_wr_key_protocol,
  input  logic [15:0] cp_wr_key_table_key_sport,
  input  logic [15:0] cp_wr_key_table_key_dport,
  input  logic [0:0] cp_wr_action,
  input  logic [12:0] cp_wr_p_counter_index,
  input  logic [2:0] cp_wr_p_pcp,
  input  logic [0:0] cp_wr_p_cfi,
  input  logic [11:0] cp_wr_p_vid,

  // Control-plane query/delete port (synchronous, 2-cycle staged --
  // shares the write port's memory access, time-multiplexed, rather
  // than adding a 3rd BRAM port). cp_query_del=0: read-only lookup by
  // key. cp_query_del=1: lookup, and if found, delete it. Results are
  // sticky (held until the next query) so a polling driver can check
  // !cp_query_busy then read at leisure, no single-cycle window.
  input  logic        cp_query_en,
  input  logic        cp_query_del,
  input  logic [31:0] cp_query_key_src,
  input  logic [31:0] cp_query_key_dst,
  input  logic [7:0] cp_query_key_protocol,
  input  logic [15:0] cp_query_key_table_key_sport,
  input  logic [15:0] cp_query_key_table_key_dport,
  output logic        cp_query_busy,
  output logic        cp_query_hit,
  output logic [0:0] cp_query_action_id,
  output logic [12:0] cp_query_p_counter_index,
  output logic [2:0] cp_query_p_pcp,
  output logic [0:0] cp_query_p_cfi,
  output logic [11:0] cp_query_p_vid
);

  // Entry storage (synthesizes to block RAM)
  logic        mem_valid  [0:DEPTH-1];
  logic [31:0] mem_key_src[0:DEPTH-1];
  logic [31:0] mem_key_dst[0:DEPTH-1];
  logic [7:0] mem_key_protocol[0:DEPTH-1];
  logic [15:0] mem_key_table_key_sport[0:DEPTH-1];
  logic [15:0] mem_key_table_key_dport[0:DEPTH-1];
  logic [0:0] mem_action[0:DEPTH-1];
  logic [12:0] mem_p_counter_index[0:DEPTH-1];
  logic [2:0] mem_p_pcp[0:DEPTH-1];
  logic [0:0] mem_p_cfi[0:DEPTH-1];
  logic [11:0] mem_p_vid[0:DEPTH-1];

  integer _i;
  `ifndef SYNTHESIS
  // synthesis translate_off
  initial begin
    for (_i = 0; _i < DEPTH; _i = _i + 1)
      mem_valid[_i] = 1'b0;
  end
  // synthesis translate_on
  `endif

  // XOR-fold hash: 104-bit key -> 13-bit BRAM address
  function automatic logic [12:0] hash_key(input logic [103:0] k);
    logic [12:0] h;
    integer c;
    begin
      h = '0;
      for (c = 0; c < 8; c = c + 1)
        h = h ^ k[c*13 +: 13];
      hash_key = h;
    end
  endfunction

  logic [103:0] wr_key_concat;
  assign wr_key_concat = {cp_wr_key_table_key_dport, cp_wr_key_table_key_sport, cp_wr_key_protocol, cp_wr_key_dst, cp_wr_key_src};
  logic [12:0] wr_addr;
  assign wr_addr = hash_key(wr_key_concat);

  logic [103:0] lkp_key_concat;
  assign lkp_key_concat = {lkp_table_key_dport, lkp_table_key_sport, lkp_protocol, lkp_dst, lkp_src};
  logic [12:0] lkp_addr;
  assign lkp_addr = hash_key(lkp_key_concat);

  logic [103:0] q_key_concat;
  assign q_key_concat = {cp_query_key_table_key_dport, cp_query_key_table_key_sport, cp_query_key_protocol, cp_query_key_dst, cp_query_key_src};
  logic [12:0] q_addr;
  assign q_addr = hash_key(q_key_concat);

  // Control-plane query/delete pipeline, stage 1: latch the request
  // and issue a registered port-B read at q_addr to see what's there.
  // Gated on !q_pend_valid (a new query is only accepted once the
  // previous one has resolved) and !cp_wr_en (never start a query the
  // same cycle a plain write is committing).
  logic q_pend_valid, q_pend_del;
  logic [12:0] q_pend_addr;
  logic [31:0] q_pend_key_src;
  logic [31:0] q_pend_key_dst;
  logic [7:0] q_pend_key_protocol;
  logic [15:0] q_pend_key_table_key_sport;
  logic [15:0] q_pend_key_table_key_dport;
  logic q_rd_valid;
  logic [31:0] q_rd_key_src;
  logic [31:0] q_rd_key_dst;
  logic [7:0] q_rd_key_protocol;
  logic [15:0] q_rd_key_table_key_sport;
  logic [15:0] q_rd_key_table_key_dport;
  logic [0:0] q_rd_action;
  logic [12:0] q_rd_p_counter_index;
  logic [2:0] q_rd_p_pcp;
  logic [0:0] q_rd_p_cfi;
  logic [11:0] q_rd_p_vid;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      q_pend_valid <= 1'b0;
    end else if (cp_query_en && !q_pend_valid && !cp_wr_en && !clearing) begin
      q_pend_valid <= 1'b1;
      q_pend_del   <= cp_query_del;
      q_pend_addr  <= q_addr;
      q_pend_key_src <= cp_query_key_src;
      q_pend_key_dst <= cp_query_key_dst;
      q_pend_key_protocol <= cp_query_key_protocol;
      q_pend_key_table_key_sport <= cp_query_key_table_key_sport;
      q_pend_key_table_key_dport <= cp_query_key_table_key_dport;
      q_rd_valid   <= mem_valid[q_addr];
      q_rd_key_src <= mem_key_src[q_addr];
      q_rd_key_dst <= mem_key_dst[q_addr];
      q_rd_key_protocol <= mem_key_protocol[q_addr];
      q_rd_key_table_key_sport <= mem_key_table_key_sport[q_addr];
      q_rd_key_table_key_dport <= mem_key_table_key_dport[q_addr];
      q_rd_action  <= mem_action[q_addr];
      q_rd_p_counter_index <= mem_p_counter_index[q_addr];
      q_rd_p_pcp <= mem_p_pcp[q_addr];
      q_rd_p_cfi <= mem_p_cfi[q_addr];
      q_rd_p_vid <= mem_p_vid[q_addr];
    end else begin
      q_pend_valid <= 1'b0;
    end
  end
  assign cp_query_busy = q_pend_valid;

  // Stage 2: resolve against the now-valid read (fires the cycle
  // right after accept, since stage 1's own else-branch clears
  // q_pend_valid one cycle later -- same timing relationship the
  // write path already has between its own accept and commit).
  logic q_match; assign q_match = q_rd_valid && (q_rd_key_src == q_pend_key_src) && (q_rd_key_dst == q_pend_key_dst) && (q_rd_key_protocol == q_pend_key_protocol) && (q_rd_key_table_key_sport == q_pend_key_table_key_sport) && (q_rd_key_table_key_dport == q_pend_key_table_key_dport);

  logic        q_hit_r;
  logic [0:0] q_action_id_r;
  logic [12:0] q_p_counter_index_r;
  logic [2:0] q_p_pcp_r;
  logic [0:0] q_p_cfi_r;
  logic [11:0] q_p_vid_r;
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      q_hit_r       <= 1'b0;
      q_action_id_r <= 1'd0;
      q_p_counter_index_r <= 13'd0;
      q_p_pcp_r <= 3'd0;
      q_p_cfi_r <= 1'd0;
      q_p_vid_r <= 12'd0;
    end else if (q_pend_valid) begin
      q_hit_r       <= q_match;
      q_action_id_r <= q_match ? q_rd_action : 1'd0;
      q_p_counter_index_r <= q_match ? q_rd_p_counter_index : 13'd0;
      q_p_pcp_r <= q_match ? q_rd_p_pcp : 3'd0;
      q_p_cfi_r <= q_match ? q_rd_p_cfi : 1'd0;
      q_p_vid_r <= q_match ? q_rd_p_vid : 12'd0;
    end
  end
  assign cp_query_hit = q_hit_r;
  assign cp_query_action_id = q_action_id_r;
  assign cp_query_p_counter_index = q_p_counter_index_r;
  assign cp_query_p_pcp = q_p_pcp_r;
  assign cp_query_p_cfi = q_p_cfi_r;
  assign cp_query_p_vid = q_p_vid_r;

  // Real power-on clear for mem_valid: the initial-block zero-fill above
  // is excluded from real synthesis (translate_off), so Quartus never sees
  // an init hint for this BRAM -- real Cyclone IV power-up content is
  // otherwise unspecified, which would let the table report spurious hits
  // on entries the control plane never wrote. This FSM walks every address
  // once, forcing mem_valid low, before any real write/query/lookup is
  // allowed to see memory content. Deliberately NOT gated on rst_n: table
  // entries must persist across a soft rst_n pulse (existing, tested
  // behavior -- see tb_FiveTuple_table_query_delete_standalone.sv), so this
  // has to be a genuine one-shot power-on sequence, driven purely by each
  // register's own inline initial value (a standard, synthesizable FPGA
  // idiom -- distinct from the procedural initial-BLOCK LOOP that hit
  // Quartus's 5000-iteration cap; a single register's declared reset value
  // is just its configuration-time power-up state, not an unrolled loop).
  // A write/query issued while clearing is in progress is silently
  // dropped (see cp_query_en's !clearing gate above) -- accepted as a
  // low-probability edge case, since DEPTH cycles is microseconds of real
  // wall-clock time, not something realistic control-plane software would
  // race against.
  logic clearing = 1'b1;
  logic [12:0] clr_idx = '0;

  // Synchronous write (control plane) -- extended, not duplicated, to add
  // the delete-commit branch AND the power-on clear above: this is the one
  // place mem_valid needs multiple writers, and it must stay a single
  // always_ff with if/else-if so at most one branch can ever drive the
  // array per cycle. The plain write is additionally gated !q_pend_valid so
  // a write colliding with an in-flight query/delete is dropped here rather
  // than corrupting anything -- the AXI4-Lite decoder is responsible for
  // never letting that collision reach this port in the first place (see
  // cp_query_busy-gated backpressure on the write channel).
  always_ff @(posedge clk) begin
    if (clearing) begin
      mem_valid[clr_idx] <= 1'b0;
      if (clr_idx == DEPTH-1) begin
        clearing <= 1'b0;
      end else begin
        clr_idx <= clr_idx + 1'b1;
      end
    end else if (cp_wr_en && !q_pend_valid) begin
      mem_valid[wr_addr]  <= 1'b1;
      mem_key_src[wr_addr] <= cp_wr_key_src;
      mem_key_dst[wr_addr] <= cp_wr_key_dst;
      mem_key_protocol[wr_addr] <= cp_wr_key_protocol;
      mem_key_table_key_sport[wr_addr] <= cp_wr_key_table_key_sport;
      mem_key_table_key_dport[wr_addr] <= cp_wr_key_table_key_dport;
      mem_action[wr_addr] <= cp_wr_action;
      mem_p_counter_index[wr_addr] <= cp_wr_p_counter_index;
      mem_p_pcp[wr_addr] <= cp_wr_p_pcp;
      mem_p_cfi[wr_addr] <= cp_wr_p_cfi;
      mem_p_vid[wr_addr] <= cp_wr_p_vid;
    end else if (q_pend_valid && q_pend_del && q_match) begin
      mem_valid[q_pend_addr] <= 1'b0;
    end
  end

  // Registered BRAM read + tag-compare stage (1-cycle lookup latency)
  logic        valid_r;
  logic [31:0] key_r_src;
  logic [31:0] mem_key_r_src;
  logic [31:0] key_r_dst;
  logic [31:0] mem_key_r_dst;
  logic [7:0] key_r_protocol;
  logic [7:0] mem_key_r_protocol;
  logic [15:0] key_r_table_key_sport;
  logic [15:0] mem_key_r_table_key_sport;
  logic [15:0] key_r_table_key_dport;
  logic [15:0] mem_key_r_table_key_dport;
  logic [0:0] action_id_r;
  logic [12:0] p_r_counter_index;
  logic [2:0] p_r_pcp;
  logic [0:0] p_r_cfi;
  logic [11:0] p_r_vid;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      valid_r <= 1'b0;
    end else begin
      valid_r     <= clearing ? 1'b0 : mem_valid[lkp_addr];
      key_r_src     <= lkp_src;
      mem_key_r_src <= mem_key_src[lkp_addr];
      key_r_dst     <= lkp_dst;
      mem_key_r_dst <= mem_key_dst[lkp_addr];
      key_r_protocol     <= lkp_protocol;
      mem_key_r_protocol <= mem_key_protocol[lkp_addr];
      key_r_table_key_sport     <= lkp_table_key_sport;
      mem_key_r_table_key_sport <= mem_key_table_key_sport[lkp_addr];
      key_r_table_key_dport     <= lkp_table_key_dport;
      mem_key_r_table_key_dport <= mem_key_table_key_dport[lkp_addr];
      action_id_r <= mem_action[lkp_addr];
      p_r_counter_index <= mem_p_counter_index[lkp_addr];
      p_r_pcp <= mem_p_pcp[lkp_addr];
      p_r_cfi <= mem_p_cfi[lkp_addr];
      p_r_vid <= mem_p_vid[lkp_addr];
    end
  end

  logic hit_c; assign hit_c = valid_r && (mem_key_r_src == key_r_src) && (mem_key_r_dst == key_r_dst) && (mem_key_r_protocol == key_r_protocol) && (mem_key_r_table_key_sport == key_r_table_key_sport) && (mem_key_r_table_key_dport == key_r_table_key_dport);
  logic [0:0] action_id_c;
  assign action_id_c = hit_c ? action_id_r : 1'd0;
  logic [12:0] p_counter_index_c;
  assign p_counter_index_c = hit_c ? p_r_counter_index : 13'b0;
  logic [2:0] p_pcp_c;
  assign p_pcp_c = hit_c ? p_r_pcp : 3'b0;
  logic [0:0] p_cfi_c;
  assign p_cfi_c = hit_c ? p_r_cfi : 1'b0;
  logic [11:0] p_vid_c;
  assign p_vid_c = hit_c ? p_r_vid : 12'b0;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      hit <= 1'b0;
    end else begin
      hit <= hit_c;
      action_id <= action_id_c;
      p_counter_index <= p_counter_index_c;
      p_pcp <= p_pcp_c;
      p_cfi <= p_cfi_c;
      p_vid <= p_vid_c;
    end
  end

  // Action ID encoding:
  //   0 = NoAction
  //   1 = InsertVLAN

endmodule
