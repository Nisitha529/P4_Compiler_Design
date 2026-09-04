module send_frame_table #(
  parameter int DEPTH = 16
) (
  input  logic clk,
  input  logic rst_n,

  // Lookup key (combinational)
  input  logic [8:0] lkp_egress_port,

  // Lookup result (registered — 1 cycle after lkp_* is presented)
  output logic        hit,
  output logic [1:0] action_id,
  output logic [47:0] p_smac,

  // Control-plane write port (synchronous)
  input  logic        cp_wr_en,
  input  logic [3:0] cp_wr_idx,  // unused: exact-match tables self-address via hash(key)
  input  logic [8:0] cp_wr_key_egress_port,
  input  logic [1:0] cp_wr_action,
  input  logic [47:0] cp_wr_p_smac,

  // Control-plane query/delete port (synchronous, 2-cycle staged --
  // shares the write port's memory access, time-multiplexed, rather
  // than adding a 3rd BRAM port). cp_query_del=0: read-only lookup by
  // key. cp_query_del=1: lookup, and if found, delete it. Results are
  // sticky (held until the next query) so a polling driver can check
  // !cp_query_busy then read at leisure, no single-cycle window.
  input  logic        cp_query_en,
  input  logic        cp_query_del,
  input  logic [8:0] cp_query_key_egress_port,
  output logic        cp_query_busy,
  output logic        cp_query_hit,
  output logic [1:0] cp_query_action_id,
  output logic [47:0] cp_query_p_smac
);

  // Entry storage (synthesizes to block RAM)
  logic        mem_valid  [0:DEPTH-1];
  logic [8:0] mem_key_egress_port[0:DEPTH-1];
  logic [1:0] mem_action[0:DEPTH-1];
  logic [47:0] mem_p_smac[0:DEPTH-1];

  integer _i;
  `ifndef SYNTHESIS
  // synthesis translate_off
  initial begin
    for (_i = 0; _i < DEPTH; _i = _i + 1)
      mem_valid[_i] = 1'b0;
  end
  // synthesis translate_on
  `endif

  // XOR-fold hash: 9-bit key -> 4-bit BRAM address
  function automatic logic [3:0] hash_key(input logic [11:0] k);
    logic [3:0] h;
    integer c;
    begin
      h = '0;
      for (c = 0; c < 3; c = c + 1)
        h = h ^ k[c*4 +: 4];
      hash_key = h;
    end
  endfunction

  logic [11:0] wr_key_concat;
  assign wr_key_concat = {3'd0, cp_wr_key_egress_port};
  logic [3:0] wr_addr;
  assign wr_addr = hash_key(wr_key_concat);

  logic [11:0] lkp_key_concat;
  assign lkp_key_concat = {3'd0, lkp_egress_port};
  logic [3:0] lkp_addr;
  assign lkp_addr = hash_key(lkp_key_concat);

  logic [11:0] q_key_concat;
  assign q_key_concat = {3'd0, cp_query_key_egress_port};
  logic [3:0] q_addr;
  assign q_addr = hash_key(q_key_concat);

  // Control-plane query/delete pipeline, stage 1: latch the request
  // and issue a registered port-B read at q_addr to see what's there.
  // Gated on !q_pend_valid (a new query is only accepted once the
  // previous one has resolved) and !cp_wr_en (never start a query the
  // same cycle a plain write is committing).
  logic q_pend_valid, q_pend_del;
  logic [3:0] q_pend_addr;
  logic [8:0] q_pend_key_egress_port;
  logic q_rd_valid;
  logic [8:0] q_rd_key_egress_port;
  logic [1:0] q_rd_action;
  logic [47:0] q_rd_p_smac;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      q_pend_valid <= 1'b0;
    end else if (cp_query_en && !q_pend_valid && !cp_wr_en && !clearing) begin
      q_pend_valid <= 1'b1;
      q_pend_del   <= cp_query_del;
      q_pend_addr  <= q_addr;
      q_pend_key_egress_port <= cp_query_key_egress_port;
      q_rd_valid   <= mem_valid[q_addr];
      q_rd_key_egress_port <= mem_key_egress_port[q_addr];
      q_rd_action  <= mem_action[q_addr];
      q_rd_p_smac <= mem_p_smac[q_addr];
    end else begin
      q_pend_valid <= 1'b0;
    end
  end
  assign cp_query_busy = q_pend_valid;

  // Stage 2: resolve against the now-valid read (fires the cycle
  // right after accept, since stage 1's own else-branch clears
  // q_pend_valid one cycle later -- same timing relationship the
  // write path already has between its own accept and commit).
  logic q_match; assign q_match = q_rd_valid && (q_rd_key_egress_port == q_pend_key_egress_port);

  logic        q_hit_r;
  logic [1:0] q_action_id_r;
  logic [47:0] q_p_smac_r;
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      q_hit_r       <= 1'b0;
      q_action_id_r <= 2'd0;
      q_p_smac_r <= 48'd0;
    end else if (q_pend_valid) begin
      q_hit_r       <= q_match;
      q_action_id_r <= q_match ? q_rd_action : 2'd0;
      q_p_smac_r <= q_match ? q_rd_p_smac : 48'd0;
    end
  end
  assign cp_query_hit = q_hit_r;
  assign cp_query_action_id = q_action_id_r;
  assign cp_query_p_smac = q_p_smac_r;

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
  logic [3:0] clr_idx = '0;

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
      mem_key_egress_port[wr_addr] <= cp_wr_key_egress_port;
      mem_action[wr_addr] <= cp_wr_action;
      mem_p_smac[wr_addr] <= cp_wr_p_smac;
    end else if (q_pend_valid && q_pend_del && q_match) begin
      mem_valid[q_pend_addr] <= 1'b0;
    end
  end

  // Registered BRAM read + tag-compare stage (1-cycle lookup latency)
  logic        valid_r;
  logic [8:0] key_r_egress_port;
  logic [8:0] mem_key_r_egress_port;
  logic [1:0] action_id_r;
  logic [47:0] p_r_smac;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      valid_r <= 1'b0;
    end else begin
      valid_r     <= clearing ? 1'b0 : mem_valid[lkp_addr];
      key_r_egress_port     <= lkp_egress_port;
      mem_key_r_egress_port <= mem_key_egress_port[lkp_addr];
      action_id_r <= mem_action[lkp_addr];
      p_r_smac <= mem_p_smac[lkp_addr];
    end
  end

  logic hit_c; assign hit_c = valid_r && (mem_key_r_egress_port == key_r_egress_port);
  logic [1:0] action_id_c;
  assign action_id_c = hit_c ? action_id_r : 2'd0;
  logic [47:0] p_smac_c;
  assign p_smac_c = hit_c ? p_r_smac : 48'b0;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      hit <= 1'b0;
    end else begin
      hit <= hit_c;
      action_id <= action_id_c;
      p_smac <= p_smac_c;
    end
  end

  // Action ID encoding:
  //   0 = NoAction
  //   1 = rewrite_mac
  //   2 = drop_pkt

endmodule
