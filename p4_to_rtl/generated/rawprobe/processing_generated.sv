module processing_generated (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        valid_in,

  // Header valid flags
  input  logic        eth_valid,

  // Header field inputs
  input  logic [47:0] eth_dst,
  input  logic [47:0] eth_src,
  input  logic [15:0] eth_etype,

  // Metadata inputs
  input  logic [31:0] meta_prev,
  input  logic [15:0] meta_idx,

  // Header valid flag outputs (may be modified by setValid/setInvalid)
  output logic        out_eth_valid,

  // Header field outputs (pass-through, optionally modified)
  output logic [47:0] out_eth_dst,
  output logic [47:0] out_eth_src,
  output logic [15:0] out_eth_etype,

  // Standard metadata outputs
  output logic [8:0] out_std_meta_egress_port,

  // Metadata outputs (final value after the last stage)
  output logic [31:0] out_meta_prev,
  output logic [15:0] out_meta_idx,

  // Control-plane write ports for table instances
  input  logic        fwd_cp_wr_en,
  input  logic [3:0] fwd_cp_wr_idx,
  input  logic [15:0] fwd_cp_wr_key_etype,
  input  logic [0:0] fwd_cp_wr_action,
  input  logic [8:0] fwd_cp_wr_p_p,

  // Table hit outputs
  output logic        fwd_hit_out,

  // Control-plane query/delete ports (plain exact-match tables)
  input  logic        fwd_cp_query_en,
  input  logic        fwd_cp_query_del,
  input  logic [15:0] fwd_cp_query_key_etype,
  output logic        fwd_cp_query_busy,
  output logic        fwd_cp_query_hit,
  output logic [0:0] fwd_cp_query_action_id,
  output logic [8:0] fwd_cp_query_p_p,

  output logic        out_valid,   // aligned with out_*/drop -- see note
  output logic        valid_out,
  output logic        drop
);

  // Metadata shadow locals (writable copies of metadata inputs)
  logic [31:0] meta_prev_w;
  logic [15:0] meta_idx_w;

  // Pipeline-stage forwarding registers (one set per exact-match
  // table boundary in the chain)
  logic valid_s1;
  logic out_eth_valid_s1;
  logic eth_valid_s1;
  logic [47:0] out_eth_dst_s1;
  logic [47:0] eth_dst_s1;
  logic [47:0] out_eth_src_s1;
  logic [47:0] eth_src_s1;
  logic [15:0] out_eth_etype_s1;
  logic [15:0] eth_etype_s1;
  logic [31:0] meta_prev_w_s1;
  logic [15:0] meta_idx_w_s1;
  logic [8:0] out_std_meta_egress_port_s1;
  logic drop_s1;
  logic valid_s2;
  logic out_eth_valid_s2;
  logic eth_valid_s2;
  logic [47:0] out_eth_dst_s2;
  logic [47:0] eth_dst_s2;
  logic [47:0] out_eth_src_s2;
  logic [47:0] eth_src_s2;
  logic [15:0] out_eth_etype_s2;
  logic [15:0] eth_etype_s2;
  logic [31:0] meta_prev_w_s2;
  logic [15:0] meta_idx_w_s2;
  logic [8:0] out_std_meta_egress_port_s2;
  logic drop_s2;

  // Pool-A (out_*/drop) working copies -- every stage except the
  // last, which drives the real output ports directly
  logic out_eth_valid__st0;
  logic [47:0] out_eth_dst__st0;
  logic [47:0] out_eth_src__st0;
  logic [15:0] out_eth_etype__st0;
  logic [8:0] out_std_meta_egress_port__st0;
  logic drop__st0;
  logic out_eth_valid__st1;
  logic [47:0] out_eth_dst__st1;
  logic [47:0] out_eth_src__st1;
  logic [15:0] out_eth_etype__st1;
  logic [8:0] out_std_meta_egress_port__st1;
  logic drop__st1;

  // Pool-B (locals/meta shadow/raw hdr+std_meta reads) working
  // copies -- every stage except the first, which reads live inputs
  logic [31:0] meta_prev_w__st1;
  logic [15:0] meta_idx_w__st1;
  logic eth_valid__st1;
  logic [47:0] eth_dst__st1;
  logic [47:0] eth_src__st1;
  logic [15:0] eth_etype__st1;
  logic [31:0] meta_prev_w__st2;
  logic [15:0] meta_idx_w__st2;
  logic eth_valid__st2;
  logic [47:0] eth_dst__st2;
  logic [47:0] eth_src__st2;
  logic [15:0] eth_etype__st2;

  // last_ts: declared index type is bit<16> but the array has 1024 entries -- indices wrap mod 1024
  // last_ts: register<bit<32>>(1024)
  logic [31:0] last_ts_mem [0:1023];
  logic        last_ts_wr_en;
  logic [9:0] last_ts_wr_addr;
  logic [31:0] last_ts_wr_data;

  // Zero all register memories at simulation start
  // synthesis translate_off
  initial begin
    for (int _si = 0; _si < 1024; _si++)
      last_ts_mem[_si] = 32'b0;
  end
  // synthesis translate_on

  // Register read wires (isolated via assign)
  logic [31:0] last_ts_rd_meta_prev;
  wire [9:0] last_ts_rd_addr_meta_prev = eth_etype;   // truncated to 1024 entries, as the write address is
  assign last_ts_rd_meta_prev = last_ts_mem[last_ts_rd_addr_meta_prev];

  // Table lookup result wires
  logic        fwd_hit;
  logic [0:0] fwd_act_id;
  logic [8:0] fwd_p_p;

  // Table module instantiations
  fwd_table #(.DEPTH(16)) u_fwd (
    .clk    (clk),
    .rst_n  (rst_n),
    .lkp_etype    (eth_etype),
    .hit       (fwd_hit),
    .action_id (fwd_act_id),
    .p_p  (fwd_p_p),
    .cp_wr_en  (fwd_cp_wr_en),
    .cp_wr_idx (fwd_cp_wr_idx),
    .cp_wr_key_etype (fwd_cp_wr_key_etype),
    .cp_wr_action (fwd_cp_wr_action),
    .cp_wr_p_p (fwd_cp_wr_p_p),
    .cp_query_en  (fwd_cp_query_en),
    .cp_query_del (fwd_cp_query_del),
    .cp_query_key_etype (fwd_cp_query_key_etype),
    .cp_query_busy (fwd_cp_query_busy),
    .cp_query_hit  (fwd_cp_query_hit),
    .cp_query_action_id (fwd_cp_query_action_id),
    .cp_query_p_p (fwd_cp_query_p_p)
  );

  // Table hit outputs
  assign fwd_hit_out = fwd_hit;

  // Metadata outputs (final value after the last stage)
  assign out_meta_prev = meta_prev_w__st2;
  assign out_meta_idx = meta_idx_w__st2;

  // ---- Pipeline stage 0 (combinational, feeds the first exact-match table boundary) ----
  always_comb begin
    drop__st0 = 0;

    // Metadata shadow defaults (init from inputs)
    meta_prev_w = meta_prev;
    meta_idx_w = meta_idx;

    // Standard metadata defaults
    out_std_meta_egress_port__st0 = 9'b0;

    // Header valid flag pass-through defaults
    out_eth_valid__st0 = eth_valid;

    // Header field pass-through defaults
    out_eth_dst__st0 = eth_dst;
    out_eth_src__st0 = eth_src;
    out_eth_etype__st0 = eth_etype;

    // apply block (stage 0 of 2)
    meta_idx_w = eth_etype;
    meta_prev_w = last_ts_rd_meta_prev;
  end

  // Forward stage-0 state into stage-1 registers (1-cycle
  // boundary — matches the exact-match table's registered latency)
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      valid_s1 <= 1'b0;
    end else begin
      valid_s1 <= valid_in;
      drop_s1 <= drop__st0;
      meta_prev_w_s1 <= meta_prev_w;
      meta_idx_w_s1 <= meta_idx_w;
      out_eth_valid_s1 <= out_eth_valid__st0;
      eth_valid_s1 <= eth_valid;
      out_eth_dst_s1 <= out_eth_dst__st0;
      eth_dst_s1 <= eth_dst;
      out_eth_src_s1 <= out_eth_src__st0;
      eth_src_s1 <= eth_src;
      out_eth_etype_s1 <= out_eth_etype__st0;
      eth_etype_s1 <= eth_etype;
      out_std_meta_egress_port_s1 <= out_std_meta_egress_port__st0;
    end
  end

  // ---- Pipeline stage 1 (registered 1 cycle(s) after stage 0) ----
  always_comb begin
    drop__st1 = drop_s1;
    meta_prev_w__st1 = meta_prev_w_s1;
    meta_idx_w__st1 = meta_idx_w_s1;
    out_eth_valid__st1 = out_eth_valid_s1;
    eth_valid__st1 = eth_valid_s1;
    out_eth_dst__st1 = out_eth_dst_s1;
    eth_dst__st1 = eth_dst_s1;
    out_eth_src__st1 = out_eth_src_s1;
    eth_src__st1 = eth_src_s1;
    out_eth_etype__st1 = out_eth_etype_s1;
    eth_etype__st1 = eth_etype_s1;
    out_std_meta_egress_port__st1 = out_std_meta_egress_port_s1;
  end

  // Forward stage-1 state into stage-2 registers (1-cycle
  // boundary — matches the exact-match table's registered latency)
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      valid_s2 <= 1'b0;
    end else begin
      valid_s2 <= valid_s1;
      drop_s2 <= drop__st1;
      meta_prev_w_s2 <= meta_prev_w__st1;
      meta_idx_w_s2 <= meta_idx_w__st1;
      out_eth_valid_s2 <= out_eth_valid__st1;
      eth_valid_s2 <= eth_valid__st1;
      out_eth_dst_s2 <= out_eth_dst__st1;
      eth_dst_s2 <= eth_dst__st1;
      out_eth_src_s2 <= out_eth_src__st1;
      eth_src_s2 <= eth_src__st1;
      out_eth_etype_s2 <= out_eth_etype__st1;
      eth_etype_s2 <= eth_etype__st1;
      out_std_meta_egress_port_s2 <= out_std_meta_egress_port__st1;
    end
  end

  // ---- Pipeline stage 2 (registered 2 cycle(s) after stage 0) ----
  always_comb begin
    drop = drop_s2;
    meta_prev_w__st2 = meta_prev_w_s2;
    meta_idx_w__st2 = meta_idx_w_s2;
    last_ts_wr_en   = 1'b0;
    last_ts_wr_addr = '0;
    last_ts_wr_data = '0;
    out_eth_valid = out_eth_valid_s2;
    eth_valid__st2 = eth_valid_s2;
    out_eth_dst = out_eth_dst_s2;
    eth_dst__st2 = eth_dst_s2;
    out_eth_src = out_eth_src_s2;
    eth_src__st2 = eth_src_s2;
    out_eth_etype = out_eth_etype_s2;
    eth_etype__st2 = eth_etype_s2;
    out_std_meta_egress_port = out_std_meta_egress_port_s2;

    // apply block (stage 2 of 2)
    // fwd.apply()
    if (fwd_hit) begin
      unique case (fwd_act_id)
        1'd0: ; // NoAction
        1'd1: begin // set_port
          out_std_meta_egress_port = fwd_p_p;
        end
        default: ; // default = NoAction
      endcase
    end
    last_ts_wr_en   = 1'b1;
    last_ts_wr_addr = eth_etype__st2;
    last_ts_wr_data = meta_prev_w__st2 + 32'd1;
  end

  // Register write-back (initialized via initial block above)
  // The write is qualified with the pipeline valid of the stage the
  // write statement lives in. `<reg>_wr_en` alone only says "the
  // program reaches a .write() here": it is combinational from that
  // stage's registers, which HOLD after a packet drains, so without
  // the valid it stays asserted and rewrites the same address every
  // idle cycle. Invisible for a write of a constant (a Bloom filter
  // setting a bit to 1 is idempotent), corrupting for any
  // read-modify-write: the value is re-accumulated once per cycle.
  always_ff @(posedge clk) begin
    if (last_ts_wr_en && valid_s2)
      last_ts_mem[last_ts_wr_addr] <= last_ts_wr_data;
  end

  always_ff @(posedge clk) begin
    if (!rst_n) valid_out <= 0;
    else        valid_out <= valid_s2;
  end
  assign out_valid = valid_s2;

endmodule
