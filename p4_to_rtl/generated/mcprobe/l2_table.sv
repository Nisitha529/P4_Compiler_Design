module l2_table #(
  parameter int DEPTH = 16
) (
  input  logic clk,
  input  logic rst_n,

  // Lookup key (combinational)
  input  logic [15:0] lkp_etype,

  // Lookup result (registered — 1 cycle after lkp_* is presented)
  output logic        hit,
  output logic [1:0] action_id,
  output logic [8:0] p_port,
  output logic [15:0] p_grp,

  // Control-plane write port (synchronous)
  input  logic        cp_wr_en,
  input  logic [3:0] cp_wr_idx,  // unused: exact-match tables self-address via hash(key)
  input  logic [15:0] cp_wr_key_etype,
  input  logic [1:0] cp_wr_action,
  input  logic [8:0] cp_wr_p_port,
  input  logic [15:0] cp_wr_p_grp,

  // Control-plane query/delete port (synchronous, 2-cycle staged --
  // shares the write port's memory access, time-multiplexed, rather
  // than adding a 3rd BRAM port). cp_query_del=0: read-only lookup by
  // key. cp_query_del=1: lookup, and if found, delete it. Results are
  // sticky (held until the next query) so a polling driver can check
  // !cp_query_busy then read at leisure, no single-cycle window.
  input  logic        cp_query_en,
  input  logic        cp_query_del,
  input  logic [15:0] cp_query_key_etype,
  output logic        cp_query_busy,
  output logic        cp_query_hit,
  output logic [1:0] cp_query_action_id,
  output logic [8:0] cp_query_p_port,
  output logic [15:0] cp_query_p_grp
);

  // Entry storage (synthesizes to block RAM)
  logic        mem_valid  [0:DEPTH-1];
  logic [15:0] mem_key_etype[0:DEPTH-1];
  logic [1:0] mem_action[0:DEPTH-1];
  logic [8:0] mem_p_port[0:DEPTH-1];
  logic [15:0] mem_p_grp[0:DEPTH-1];

  integer _i;
  `ifndef SYNTHESIS
  // synthesis translate_off
  initial begin
    for (_i = 0; _i < DEPTH; _i = _i + 1)
      mem_valid[_i] = 1'b0;
  end
  // synthesis translate_on
  `endif

  // XOR-fold hash: 16-bit key -> 4-bit BRAM address
  function automatic logic [3:0] hash_key(input logic [15:0] k);
    logic [3:0] h;
    integer c;
    begin
      h = '0;
      for (c = 0; c < 4; c = c + 1)
        h = h ^ k[c*4 +: 4];
      hash_key = h;
    end
  endfunction

  logic [15:0] wr_key_concat;
  assign wr_key_concat = {cp_wr_key_etype};
  logic [3:0] wr_addr;
  assign wr_addr = hash_key(wr_key_concat);

  logic [15:0] lkp_key_concat;
  assign lkp_key_concat = {lkp_etype};
  logic [3:0] lkp_addr;
  assign lkp_addr = hash_key(lkp_key_concat);

  logic [15:0] q_key_concat;
  assign q_key_concat = {cp_query_key_etype};
  logic [3:0] q_addr;
  assign q_addr = hash_key(q_key_concat);

  // Control-plane query/delete pipeline, stage 1: latch the request
  // and issue a registered port-B read at q_addr to see what's there.
  // Gated on !q_pend_valid (a new query is only accepted once the
  // previous one has resolved) and !cp_wr_en (never start a query the
  // same cycle a plain write is committing).
  logic q_pend_valid, q_pend_del;
  logic [3:0] q_pend_addr;
  logic [15:0] q_pend_key_etype;
  logic q_rd_valid;
  logic [15:0] q_rd_key_etype;
  logic [1:0] q_rd_action;
  logic [8:0] q_rd_p_port;
  logic [15:0] q_rd_p_grp;

  // Power-on clear state. Declared up here because the query pipeline
  // below gates on `clearing`, and xvlog will not accept a use that
  // precedes the declaration.
  logic clearing = 1'b1;
  logic [3:0] clr_idx = '0;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      q_pend_valid <= 1'b0;
    end else if (cp_query_en && !q_pend_valid && !cp_wr_en && !clearing) begin
      q_pend_valid <= 1'b1;
      q_pend_del   <= cp_query_del;
      q_pend_addr  <= q_addr;
      q_pend_key_etype <= cp_query_key_etype;
    end else begin
      q_pend_valid <= 1'b0;
    end
  end
  assign cp_query_busy = q_pend_valid;

  // Stage 2: resolve against the now-valid read (fires the cycle
  // right after accept, since stage 1's own else-branch clears
  // q_pend_valid one cycle later -- same timing relationship the
  // write path already has between its own accept and commit).
  logic q_match; assign q_match = q_rd_valid && (q_rd_key_etype == q_pend_key_etype);

  logic        q_hit_r;
  logic [1:0] q_action_id_r;
  logic [8:0] q_p_port_r;
  logic [15:0] q_p_grp_r;
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      q_hit_r       <= 1'b0;
      q_action_id_r <= 2'd0;
      q_p_port_r <= 9'd0;
      q_p_grp_r <= 16'd0;
    end else if (q_pend_valid) begin
      q_hit_r       <= q_match;
      q_action_id_r <= q_match ? q_rd_action : 2'd0;
      q_p_port_r <= q_match ? q_rd_p_port : 9'd0;
      q_p_grp_r <= q_match ? q_rd_p_grp : 16'd0;
    end
  end
  assign cp_query_hit = q_hit_r;
  assign cp_query_action_id = q_action_id_r;
  assign cp_query_p_port = q_p_port_r;
  assign cp_query_p_grp = q_p_grp_r;

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
  // -- Control-plane port (TRUE DUAL PORT, port A) -----------------------
  // This port both WRITES and READS the entry memories; the per-packet
  // lookup further down is port B and only reads. Two ports, one access
  // each per cycle, so every memory needs exactly ONE copy.
  //
  // The SHAPE is load-bearing, and was arrived at by measuring quartus_map
  // on an 8192x32 array (Cyclone IV E):
  //   * EXACTLY TWO branches, write or read. Four branches -- clear, write,
  //     delete, query-read -- defeat RAM inference completely: Quartus
  //     gives up and tries to build the array from registers ("Cannot
  //     convert all sets of registers into RAM megafunctions"). So the
  //     three WRITE conditions merge into one cp_wr with a muxed address
  //     and muxed write data.
  //   * the write branch must ALSO drive this port's read output. That is
  //     how read-during-write behaviour gets declared. Without it the port
  //     infers write-only, the query read becomes a SECOND reader, and
  //     Quartus duplicates every memory to serve it: 524,288 bits for a
  //     262,144-bit array. With it, one True Dual Port copy -- half the
  //     memory, and runtime readback is kept.
  //   * the power-on clear SWEEP is its own block below: it only moves
  //     counters, and must stay out of this template.
  //
  // A write colliding with an in-flight query/delete is dropped here rather
  // than corrupting anything; the AXI4-Lite decoder is responsible for
  // never letting that collision reach this port (cp_query_busy-gated
  // backpressure on the write channel).
  wire cp_plain_wr = cp_wr_en && !q_pend_valid;
  wire cp_del_wr   = q_pend_valid && q_pend_del && q_match;
  wire cp_wr       = clearing || cp_plain_wr || cp_del_wr;
  // Only a real entry write stores valid=1; the clear sweep and a delete
  // both store 0. The key/action/parameter memories are written on all
  // three, which is harmless: a cleared or deleted entry has valid=0, and
  // every lookup and every query gates on valid.
  wire cp_wr_valid = cp_plain_wr;
  logic [3:0] cp_addr;
  always_comb begin
    if      (clearing)     cp_addr = clr_idx;
    else if (cp_plain_wr)  cp_addr = wr_addr;
    // q_pend_addr for the WHOLE time a query is in flight, not just on the
    // delete cycle: the read branch re-reads every non-write cycle, and
    // holding the latched address keeps q_rd_* stable even if the control
    // plane moves the query key inputs underneath it.
    else if (q_pend_valid) cp_addr = q_pend_addr;
    else                   cp_addr = q_addr;
  end
  // The clear sweep: counters only, deliberately not in a RAM block.
  always_ff @(posedge clk) begin
    if (clearing) begin
      if (clr_idx == DEPTH-1) clearing <= 1'b0;
      else                    clr_idx  <= clr_idx + 1'b1;
    end
  end
  always_ff @(posedge clk) begin
    if (cp_wr) begin
      mem_valid[cp_addr] <= cp_wr_valid;
      q_rd_valid         <= cp_wr_valid;
    end else begin
      q_rd_valid         <= mem_valid[cp_addr];
    end
  end
  always_ff @(posedge clk) begin
    if (cp_wr) begin
      mem_key_etype[cp_addr] <= cp_wr_key_etype;
      q_rd_key_etype         <= cp_wr_key_etype;
    end else begin
      q_rd_key_etype         <= mem_key_etype[cp_addr];
    end
  end
  always_ff @(posedge clk) begin
    if (cp_wr) begin
      mem_action[cp_addr] <= cp_wr_action;
      q_rd_action         <= cp_wr_action;
    end else begin
      q_rd_action         <= mem_action[cp_addr];
    end
  end
  always_ff @(posedge clk) begin
    if (cp_wr) begin
      mem_p_port[cp_addr] <= cp_wr_p_port;
      q_rd_p_port         <= cp_wr_p_port;
    end else begin
      q_rd_p_port         <= mem_p_port[cp_addr];
    end
  end
  always_ff @(posedge clk) begin
    if (cp_wr) begin
      mem_p_grp[cp_addr] <= cp_wr_p_grp;
      q_rd_p_grp         <= cp_wr_p_grp;
    end else begin
      q_rd_p_grp         <= mem_p_grp[cp_addr];
    end
  end

  // Registered BRAM read + tag-compare stage (1-cycle lookup latency)
  logic        valid_r;
  logic [15:0] key_r_etype;
  logic [15:0] mem_key_r_etype;
  logic [1:0] action_id_r;
  logic [8:0] p_r_port;
  logic [15:0] p_r_grp;

  always_ff @(posedge clk) begin
    if (!rst_n) valid_r <= 1'b0;
    else        valid_r <= clearing ? 1'b0 : mem_valid[lkp_addr];
  end
  // No reset here on purpose -- see above. Garbage in these registers
  // before the first lookup is unobservable: hit is 0 until valid_r is.
  always_ff @(posedge clk) begin
    key_r_etype     <= lkp_etype;
    mem_key_r_etype <= mem_key_etype[lkp_addr];
    action_id_r <= mem_action[lkp_addr];
    p_r_port <= mem_p_port[lkp_addr];
    p_r_grp <= mem_p_grp[lkp_addr];
  end

  logic hit_c; assign hit_c = valid_r && (mem_key_r_etype == key_r_etype);
  logic [1:0] action_id_c;
  assign action_id_c = hit_c ? action_id_r : 2'd0;
  logic [8:0] p_port_c;
  assign p_port_c = hit_c ? p_r_port : 9'b0;
  logic [15:0] p_grp_c;
  assign p_grp_c = hit_c ? p_r_grp : 16'b0;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      hit <= 1'b0;
    end else begin
      hit <= hit_c;
      action_id <= action_id_c;
      p_port <= p_port_c;
      p_grp <= p_grp_c;
    end
  end

  // Action ID encoding:
  //   0 = NoAction
  //   1 = fwd
  //   2 = mcast

endmodule
