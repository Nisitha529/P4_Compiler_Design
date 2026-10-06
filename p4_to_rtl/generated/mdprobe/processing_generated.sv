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
  input  logic [7:0] meta_colour,
  input  logic [15:0] meta_midx,

  // Header valid flag outputs (may be modified by setValid/setInvalid)
  output logic        out_eth_valid,

  // Header field outputs (pass-through, optionally modified)
  output logic [47:0] out_eth_dst,
  output logic [47:0] out_eth_src,
  output logic [15:0] out_eth_etype,

  // Standard metadata outputs
  output logic [8:0] out_std_meta_egress_port,

  // Metadata outputs (final value after the last stage)
  output logic [7:0] out_meta_colour,
  output logic [15:0] out_meta_midx,

  // Control-plane write ports for table instances
  input  logic        fwd_cp_wr_en,
  input  logic [3:0] fwd_cp_wr_idx,
  input  logic [47:0] fwd_cp_wr_key_dst,
  input  logic [0:0] fwd_cp_wr_action,
  input  logic [8:0] fwd_cp_wr_p_p,

  // Table hit outputs
  output logic        fwd_hit_out,

  // Control-plane query/delete ports (plain exact-match tables)
  input  logic        fwd_cp_query_en,
  input  logic        fwd_cp_query_del,
  input  logic [47:0] fwd_cp_query_key_dst,
  output logic        fwd_cp_query_busy,
  output logic        fwd_cp_query_hit,
  output logic [0:0] fwd_cp_query_action_id,
  output logic [8:0] fwd_cp_query_p_p,

  // Meter rate knobs (AXI4-Lite programmable, per INSTANCE not per index)
  input  logic  [4:0] rate_limit_cp_rate_shift,
  input  logic [15:0] rate_limit_cp_burst,

  // Digest pushes (the FIFO the control plane drains lives in the shell)
  output logic        seen_src_push,
  output logic [47:0] seen_src_data,

  output logic        out_valid,   // aligned with out_*/drop -- see note
  output logic        valid_out,
  output logic        drop
);

  logic [0:0] c;
  logic [7:0] tmp;

  // Metadata shadow locals (writable copies of metadata inputs)
  logic [7:0] meta_colour_w;
  logic [15:0] meta_midx_w;

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
  logic [7:0] meta_colour_w_s1;
  logic [15:0] meta_midx_w_s1;
  logic [0:0] c_s1;
  logic [7:0] tmp_s1;
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
  logic [7:0] meta_colour_w_s2;
  logic [15:0] meta_midx_w_s2;
  logic [0:0] c_s2;
  logic [7:0] tmp_s2;
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
  logic [0:0] c__st1;
  logic [7:0] tmp__st1;
  logic [7:0] meta_colour_w__st1;
  logic [15:0] meta_midx_w__st1;
  logic eth_valid__st1;
  logic [47:0] eth_dst__st1;
  logic [47:0] eth_src__st1;
  logic [15:0] eth_etype__st1;
  logic [0:0] c__st2;
  logic [7:0] tmp__st2;
  logic [7:0] meta_colour_w__st2;
  logic [15:0] meta_midx_w__st2;
  logic eth_valid__st2;
  logic [47:0] eth_dst__st2;
  logic [47:0] eth_src__st2;
  logic [15:0] eth_etype__st2;

  // ── Meter debit buckets ───────────────────────────────────────────────
  // rate_limit: Meter<bit<10>>(1024)
  logic [15:0] rate_limit_debt [0:1023];
  logic [31:0] rate_limit_ts   [0:1023];
  logic        rate_limit_exec_en;
  logic [9:0] rate_limit_exec_idx;
  logic        rate_limit_colour;   // 0 = GREEN, 1 = RED
  // One free-running clock for every meter in this control.
  logic [31:0] meter_now;
  always_ff @(posedge clk) meter_now <= !rst_n ? 32'd0 : meter_now + 32'd1;
  // synthesis translate_off
  initial begin
    for (int _mi = 0; _mi < 1024; _mi++) begin
      rate_limit_debt[_mi] = 16'd0;
      rate_limit_ts  [_mi] = 32'd0;
    end
  end
  // synthesis translate_on
  wire [15:0] rate_limit_debt_rd = rate_limit_debt[rate_limit_exec_idx];
  wire [31:0] rate_limit_ts_rd   = rate_limit_ts  [rate_limit_exec_idx];
  wire [31:0] rate_limit_elapsed = meter_now - rate_limit_ts_rd;
  wire [31:0] rate_limit_decay   = rate_limit_elapsed >> rate_limit_cp_rate_shift;
  wire [15:0] rate_limit_debt_now = ({16'd0, rate_limit_debt_rd} > rate_limit_decay)
                             ? (rate_limit_debt_rd - rate_limit_decay[15:0])
                             : 16'd0;
  assign      rate_limit_colour  = !(rate_limit_debt_now < rate_limit_cp_burst);

  // ── Digest push outputs ──────────────────────────────────────────────
  // The call site drives the _c pair combinationally; the PORT is a
  // registered one-cycle pulse, captured at the stage the pack() is in.
  // Both halves of that matter. The gate is needed because _push_c is
  // combinational from stage registers that HOLD after a packet drains,
  // so ungated it pushes the same entry every idle cycle. Capturing at
  // the pack's OWN stage is needed because the data it packs is that
  // stage's view of the packet -- gating on the module's out_valid
  // instead samples it stages too late, which read back as all zeros.
  // seen_src: 48 bits per entry, packed in stage 0
  logic        seen_src_push_c;
  logic [47:0] seen_src_data_c;
  always_ff @(posedge clk) begin
    if (!rst_n) seen_src_push <= 1'b0;
    else begin
      seen_src_push <= seen_src_push_c && valid_in;
      if (seen_src_push_c && valid_in) seen_src_data <= seen_src_data_c;
    end
  end

  // Table lookup result wires
  logic        fwd_hit;
  logic [0:0] fwd_act_id;
  logic [8:0] fwd_p_p;

  // Table module instantiations
  fwd_table #(.DEPTH(16)) u_fwd (
    .clk    (clk),
    .rst_n  (rst_n),
    .lkp_dst    (eth_dst),
    .hit       (fwd_hit),
    .action_id (fwd_act_id),
    .p_p  (fwd_p_p),
    .cp_wr_en  (fwd_cp_wr_en),
    .cp_wr_idx (fwd_cp_wr_idx),
    .cp_wr_key_dst (fwd_cp_wr_key_dst),
    .cp_wr_action (fwd_cp_wr_action),
    .cp_wr_p_p (fwd_cp_wr_p_p),
    .cp_query_en  (fwd_cp_query_en),
    .cp_query_del (fwd_cp_query_del),
    .cp_query_key_dst (fwd_cp_query_key_dst),
    .cp_query_busy (fwd_cp_query_busy),
    .cp_query_hit  (fwd_cp_query_hit),
    .cp_query_action_id (fwd_cp_query_action_id),
    .cp_query_p_p (fwd_cp_query_p_p)
  );

  // Table hit outputs
  assign fwd_hit_out = fwd_hit;

  // Metadata outputs (final value after the last stage)
  assign out_meta_colour = meta_colour_w__st2;
  assign out_meta_midx = meta_midx_w__st2;

  // ---- Pipeline stage 0 (combinational, feeds the first exact-match table boundary) ----
  always_comb begin
    drop__st0 = 0;
    c = 1'b0;
    tmp = 8'b0;

    // Metadata shadow defaults (init from inputs)
    meta_colour_w = meta_colour;
    meta_midx_w = meta_midx;
    rate_limit_exec_en  = 1'b0;
    rate_limit_exec_idx = '0;
    seen_src_push_c = 1'b0;
    seen_src_data_c = '0;

    // Standard metadata defaults
    out_std_meta_egress_port__st0 = 9'b0;

    // Header valid flag pass-through defaults
    out_eth_valid__st0 = eth_valid;

    // Header field pass-through defaults
    out_eth_dst__st0 = eth_dst;
    out_eth_src__st0 = eth_src;
    out_eth_etype__st0 = eth_etype;

    // apply block (stage 0 of 2)
    rate_limit_exec_en  = 1'b1;
    rate_limit_exec_idx = 10'(eth_etype);
    c = rate_limit_colour;
    if (c == 1'b1) begin
      tmp = 8'd1;
    end
    else begin
      tmp = 8'd0;
    end
    meta_colour_w = tmp;
    meta_midx_w = eth_etype;
    if (c == 1'b1) begin
      drop__st0 = 1'd1;
    end
    seen_src_push_c = 1'b1;
    seen_src_data_c = eth_src;
  end

  // Forward stage-0 state into stage-1 registers (1-cycle
  // boundary — matches the exact-match table's registered latency)
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      valid_s1 <= 1'b0;
    end else begin
      valid_s1 <= valid_in;
      drop_s1 <= drop__st0;
      c_s1 <= c;
      tmp_s1 <= tmp;
      meta_colour_w_s1 <= meta_colour_w;
      meta_midx_w_s1 <= meta_midx_w;
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
    c__st1 = c_s1;
    tmp__st1 = tmp_s1;
    meta_colour_w__st1 = meta_colour_w_s1;
    meta_midx_w__st1 = meta_midx_w_s1;
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
      c_s2 <= c__st1;
      tmp_s2 <= tmp__st1;
      meta_colour_w_s2 <= meta_colour_w__st1;
      meta_midx_w_s2 <= meta_midx_w__st1;
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
    c__st2 = c_s2;
    tmp__st2 = tmp_s2;
    meta_colour_w__st2 = meta_colour_w_s2;
    meta_midx_w__st2 = meta_midx_w_s2;
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
        1'd1: begin // pass_through
          out_std_meta_egress_port = fwd_p_p;
        end
        default: ; // default = NoAction
      endcase
    end
  end

  always_ff @(posedge clk) begin
    if (rate_limit_exec_en && valid_in) begin
      rate_limit_debt[rate_limit_exec_idx] <= rate_limit_colour
                                 ? rate_limit_debt_now
                                 : (rate_limit_debt_now + 16'd1);
      rate_limit_ts  [rate_limit_exec_idx] <= meter_now;
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) valid_out <= 0;
    else        valid_out <= valid_s2;
  end
  assign out_valid = valid_s2;

endmodule
