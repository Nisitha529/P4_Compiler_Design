// ============================================================================
// tb_mac_lookup_table_assoc_standalone.sv -- d-way set-associative exact-match
// table correctness check (--exact-match-ways). NOT a replacement for
// tb_multicast.sv's cycle-exact functional regression suite, and does not
// edit it -- that suite is cycle-exact against the default ways=1 (direct-
// mapped) table and is unaffected by this feature (default output is
// byte-identical, verified separately). Purpose: isolate exactly the new
// code path emit_table.py's _emit_exact_match_table_assoc() adds -- real
// collision avoidance across `ways` slots per hash bucket, instead of the
// direct-mapped table's silent overwrite-on-collision -- independent of the
// rest of the pipeline. Deliberately does NOT assert an exact cycle count
// for lookups (waits a generous, budget-independent bound); DOES assert
// exact behavior around cp_wr_busy, since that gate is the load-bearing
// correctness property for back-to-back control-plane writes.
//
// Colliding-key construction: mac_lookup's key is hdr.ethernet.dstAddr (48
// bits), DEPTH=1024 -> idx_w=10, hash XOR-folds 5 10-bit chunks (bits
// [9:0],[19:10],[29:20],[39:30],[49:40], top 2 bits zero-padded). For any X
// in 0..1023, key = X*1025 (i.e. X | (X<<10)) sets chunk0=chunk1=X and
// chunks 2-4=0, so hash = X^X^0^0^0 = 0 for every such X -- all such keys
// collide into bucket 0 and are pairwise distinct. Used here with X=0..4
// (5 distinct colliding keys against a ways=4 table, to also exercise the
// genuine-overflow/wr_collision path).
//
// Run against mac_lookup_table.sv regenerated via:
//   python3 main.py multicast --exact-match-ways 4
// (NOT the committed default generated/multicast/mac_lookup_table.sv, which
// stays at ways=1 -- copy the regenerated file to a scratch location for
// this compile so the committed default is undisturbed).
//
// Compile (against the scratch-copied assoc-mode table):
//   iverilog -g2012 -o sim tb_mac_lookup_table_assoc_standalone.sv <path-to-scratch>/mac_lookup_table_assoc.sv
//   vvp sim
// ============================================================================
`timescale 1ns/1ps

module tb_mac_lookup_table_assoc_standalone;

  localparam CLK_T = 10;
  logic clk = 0;
  always #(CLK_T/2) clk = ~clk;
  logic rst_n;

  // Generous, budget-independent wait for a lookup to settle -- the real
  // latency is small and fixed (unaffected by associativity), this is
  // comfortably above it.
  localparam int WAIT_CYCLES = 8;

  logic [47:0] lkp_dstAddr;
  logic        hit;
  logic  [1:0] action_id;
  logic  [8:0] p_port;

  logic        cp_wr_en;
  logic  [9:0] cp_wr_idx = 0;
  logic [47:0] cp_wr_key_dstAddr;
  logic  [1:0] cp_wr_action;
  logic  [8:0] cp_wr_p_port;
  logic        wr_collision;
  logic        cp_wr_busy;

  mac_lookup_table #(.DEPTH(1024)) dut (
    .clk               (clk),
    .rst_n             (rst_n),
    .lkp_dstAddr       (lkp_dstAddr),
    .hit               (hit),
    .action_id         (action_id),
    .p_port            (p_port),
    .cp_wr_en          (cp_wr_en),
    .cp_wr_idx         (cp_wr_idx),
    .cp_wr_key_dstAddr (cp_wr_key_dstAddr),
    .cp_wr_action      (cp_wr_action),
    .cp_wr_p_port      (cp_wr_p_port),
    .wr_collision      (wr_collision),
    .cp_wr_busy        (cp_wr_busy)
  );

  int pass_cnt = 0, fail_cnt = 0;
  task automatic chk(input string name, input logic cond);
    if (cond) begin $display("    [PASS] %s", name); pass_cnt++; end
    else      begin $display("    [FAIL] %s", name); fail_cnt++; end
  endtask

  task do_reset;
    rst_n = 0; cp_wr_en = 0; lkp_dstAddr = 0;
    repeat(5) @(posedge clk); @(negedge clk);
    rst_n = 1; @(posedge clk); #1;
  endtask

  // Normal, well-behaved write: waits for cp_wr_busy to clear before
  // returning, so callers never violate the busy gate by accident. Also
  // reports whether wr_collision was ever seen while this write was in
  // flight (a single-cycle pulse aligned with the commit cycle, sampled
  // on every edge of the busy window so it can't be missed).
  logic last_write_saw_collision;
  task automatic cp_write(input [47:0] key, input [1:0] act, input [8:0] portn);
    @(negedge clk);
    cp_wr_key_dstAddr = key;
    cp_wr_action      = act;
    cp_wr_p_port      = portn;
    cp_wr_en          = 1;
    last_write_saw_collision = 0;
    @(posedge clk); #1;
    cp_wr_en = 0;
    while (cp_wr_busy) begin
      if (wr_collision) last_write_saw_collision = 1;
      @(posedge clk); #1;
    end
    if (wr_collision) last_write_saw_collision = 1;
  endtask

  // Deliberately violates the busy gate: asserts cp_wr_en on the very next
  // edge without waiting for any prior write to finish. Used only by the
  // busy-gate test.
  task automatic cp_write_no_wait(input [47:0] key, input [1:0] act, input [8:0] portn);
    @(negedge clk);
    cp_wr_key_dstAddr = key;
    cp_wr_action      = act;
    cp_wr_p_port      = portn;
    cp_wr_en          = 1;
    @(posedge clk); #1;
    cp_wr_en = 0;
  endtask

  task automatic do_lookup(input [47:0] key);
    lkp_dstAddr = key;
    repeat (WAIT_CYCLES) @(posedge clk);
    #1;
  endtask

  // Colliding-key construction: X*1025 for X in 0..1023 all hash to bucket 0.
  function automatic [47:0] ckey(input int x);
    ckey = 48'(x) * 48'd1025;
  endfunction

  initial begin
    $display("== tb_mac_lookup_table_assoc_standalone: --exact-match-ways=4 regression ==\n");

    // ────────────────────────────────────────────────────────────────────
    // T1 -- 4 distinct colliding keys, all landing in the same bucket,
    // each in its own way, all independently and correctly readable.
    // ────────────────────────────────────────────────────────────────────
    $display("══ T1: 4 colliding keys, distinct ways ═══════════════════════════");
    do_reset();
    cp_write(ckey(0), 2'd1, 9'd10);  // action=multicast, port used as an opaque tag here
    cp_write(ckey(1), 2'd1, 9'd11);
    cp_write(ckey(2), 2'd1, 9'd12);
    cp_write(ckey(3), 2'd1, 9'd13);

    do_lookup(ckey(0));
    chk("T1: key0 hit", hit);
    chk("T1: key0 port=10", p_port === 9'd10);
    do_lookup(ckey(1));
    chk("T1: key1 hit", hit);
    chk("T1: key1 port=11", p_port === 9'd11);
    do_lookup(ckey(2));
    chk("T1: key2 hit", hit);
    chk("T1: key2 port=12", p_port === 9'd12);
    do_lookup(ckey(3));
    chk("T1: key3 hit", hit);
    chk("T1: key3 port=13", p_port === 9'd13);

    // ────────────────────────────────────────────────────────────────────
    // T2 -- re-writing an already-stored key updates its own way in place,
    // doesn't consume a new way. Verified two ways: the other 3 ways'
    // entries are untouched, and (in T3 below) the bucket is still "full"
    // at exactly 4 distinct keys, not 5.
    // ────────────────────────────────────────────────────────────────────
    $display("\n══ T2: update-in-place (re-write an existing key) ════════════════");
    cp_write(ckey(0), 2'd2, 9'd99);  // key0's action/port changed
    do_lookup(ckey(0));
    chk("T2: key0 updated action=2", action_id === 2'd2);
    chk("T2: key0 updated port=99", p_port === 9'd99);
    do_lookup(ckey(1));
    chk("T2: key1 untouched port=11", p_port === 9'd11);
    do_lookup(ckey(2));
    chk("T2: key2 untouched port=12", p_port === 9'd12);
    do_lookup(ckey(3));
    chk("T2: key3 untouched port=13", p_port === 9'd13);

    // ────────────────────────────────────────────────────────────────────
    // T3 -- genuine overflow: a 5th distinct colliding key, with all 4
    // ways already occupied by DIFFERENT keys, must pulse wr_collision on
    // its commit cycle and still land somewhere (way 0 fallback) rather
    // than silently vanishing.
    // ────────────────────────────────────────────────────────────────────
    $display("\n══ T3: 5th colliding key -> genuine collision ════════════════════");
    cp_write(ckey(4), 2'd1, 9'd14);
    chk("T3: wr_collision pulsed during the overflow write", last_write_saw_collision);

    do_lookup(ckey(4));
    chk("T3: key4 now hit (landed in way 0)", hit);
    chk("T3: key4 port=14", p_port === 9'd14);
    do_lookup(ckey(0));
    chk("T3: key0 now a MISS (way 0 was overwritten)", !hit);
    chk("T3: key0 miss -> default action_id=1 (multicast)", action_id === 2'd1);
    do_lookup(ckey(1));
    chk("T3: key1 still hit (way 1 untouched)", hit);
    chk("T3: key1 still port=11", p_port === 9'd11);

    // ────────────────────────────────────────────────────────────────────
    // T4 -- busy-gate: a second cp_wr_en asserted while the first write is
    // still in flight (cp_wr_busy high) must be ignored, not corrupt the
    // in-flight write.
    // ────────────────────────────────────────────────────────────────────
    $display("\n══ T4: busy-gate rejects an overlapping write ═════════════════════");
    do_reset();
    cp_write_no_wait(ckey(10), 2'd1, 9'd50);   // accepted (not busy yet)
    chk("T4: busy asserted right after accept", cp_wr_busy);
    cp_write_no_wait(ckey(11), 2'd1, 9'd51);   // violates the gate -- must be dropped
    while (cp_wr_busy) @(posedge clk);
    #1;

    do_lookup(ckey(10));
    chk("T4: first write (key10) committed correctly", hit && p_port === 9'd50);
    do_lookup(ckey(11));
    chk("T4: second write (key11) was ignored -> miss", !hit);

    // ────────────────────────────────────────────────────────────────────
    $display("");
    $display("════════════════════════════════════════════════════════════════");
    $display("  Results: %0d passed, %0d failed  (total %0d)", pass_cnt, fail_cnt, pass_cnt+fail_cnt);
    $display("════════════════════════════════════════════════════════════════");
    if (fail_cnt == 0) $display("  ALL TESTS PASSED");
    else                $display("  FAILURES DETECTED — see [FAIL] lines above");

    $finish;
  end

endmodule
