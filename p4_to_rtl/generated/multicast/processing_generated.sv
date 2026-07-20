module processing_generated (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        valid_in,

  // Header valid flags
  input  logic        ethernet_valid,

  // Header field inputs
  input  logic [47:0] ethernet_dstAddr,
  input  logic [47:0] ethernet_srcAddr,
  input  logic [15:0] ethernet_etherType,

  // Header valid flag outputs (may be modified by setValid/setInvalid)
  output logic        out_ethernet_valid,

  // Header field outputs (pass-through, optionally modified)
  output logic [47:0] out_ethernet_dstAddr,
  output logic [47:0] out_ethernet_srcAddr,
  output logic [15:0] out_ethernet_etherType,

  // Standard metadata outputs
  output logic [8:0] out_std_meta_egress_spec,
  output logic [15:0] out_std_meta_mcast_grp,

  // Control-plane write ports for table instances
  input  logic        mac_lookup_cp_wr_en,
  input  logic [9:0] mac_lookup_cp_wr_idx,
  input  logic [47:0] mac_lookup_cp_wr_key_dstAddr,
  input  logic [1:0] mac_lookup_cp_wr_action,
  input  logic [8:0] mac_lookup_cp_wr_p_port,

  // Table hit outputs
  output logic        mac_lookup_hit_out,

  output logic        valid_out,
  output logic        drop
);

  // Pipeline-stage forwarding registers (one set per exact-match
  // table boundary in the chain)
  logic valid_s1;
  logic out_ethernet_valid_s1;
  logic ethernet_valid_s1;
  logic [47:0] out_ethernet_dstAddr_s1;
  logic [47:0] ethernet_dstAddr_s1;
  logic [47:0] out_ethernet_srcAddr_s1;
  logic [47:0] ethernet_srcAddr_s1;
  logic [15:0] out_ethernet_etherType_s1;
  logic [15:0] ethernet_etherType_s1;
  logic [8:0] out_std_meta_egress_spec_s1;
  logic [15:0] out_std_meta_mcast_grp_s1;
  logic drop_s1;
  logic __stage_cond_0_r;

  // Pool-A (out_*/drop) working copies -- every stage except the
  // last, which drives the real output ports directly
  logic out_ethernet_valid__st0;
  logic [47:0] out_ethernet_dstAddr__st0;
  logic [47:0] out_ethernet_srcAddr__st0;
  logic [15:0] out_ethernet_etherType__st0;
  logic [8:0] out_std_meta_egress_spec__st0;
  logic [15:0] out_std_meta_mcast_grp__st0;
  logic drop__st0;

  // Pool-B (locals/meta shadow/raw hdr+std_meta reads) working
  // copies -- every stage except the first, which reads live inputs
  logic ethernet_valid__st1;
  logic [47:0] ethernet_dstAddr__st1;
  logic [47:0] ethernet_srcAddr__st1;
  logic [15:0] ethernet_etherType__st1;

  // Table lookup result wires
  logic        mac_lookup_hit;
  logic [1:0] mac_lookup_act_id;
  logic [8:0] mac_lookup_p_port;

  // Table module instantiations
  mac_lookup_table #(.DEPTH(1024)) u_mac_lookup (
    .clk    (clk),
    .rst_n  (rst_n),
    .lkp_dstAddr    (ethernet_dstAddr),
    .hit       (mac_lookup_hit),
    .action_id (mac_lookup_act_id),
    .p_port  (mac_lookup_p_port),
    .cp_wr_en  (mac_lookup_cp_wr_en),
    .cp_wr_idx (mac_lookup_cp_wr_idx),
    .cp_wr_key_dstAddr (mac_lookup_cp_wr_key_dstAddr),
    .cp_wr_action (mac_lookup_cp_wr_action),
    .cp_wr_p_port (mac_lookup_cp_wr_p_port)
  );

  // Table hit outputs
  assign mac_lookup_hit_out = mac_lookup_hit;

  // ---- Pipeline stage 0 (combinational, feeds the first exact-match table boundary) ----
  always_comb begin
    drop__st0 = 0;

    // Standard metadata defaults
    out_std_meta_egress_spec__st0 = 9'b0;
    out_std_meta_mcast_grp__st0 = 16'b0;

    // Header valid flag pass-through defaults
    out_ethernet_valid__st0 = ethernet_valid;

    // Header field pass-through defaults
    out_ethernet_dstAddr__st0 = ethernet_dstAddr;
    out_ethernet_srcAddr__st0 = ethernet_srcAddr;
    out_ethernet_etherType__st0 = ethernet_etherType;

    // apply block (stage 0 of 1)
    if (ethernet_valid) begin
    end
  end

  // Forward stage-0 state into stage-1 registers (1-cycle
  // boundary — matches the exact-match table's registered latency)
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      valid_s1 <= 1'b0;
    end else begin
      valid_s1 <= valid_in;
      drop_s1 <= drop__st0;
      out_ethernet_valid_s1 <= out_ethernet_valid__st0;
      ethernet_valid_s1 <= ethernet_valid;
      out_ethernet_dstAddr_s1 <= out_ethernet_dstAddr__st0;
      ethernet_dstAddr_s1 <= ethernet_dstAddr;
      out_ethernet_srcAddr_s1 <= out_ethernet_srcAddr__st0;
      ethernet_srcAddr_s1 <= ethernet_srcAddr;
      out_ethernet_etherType_s1 <= out_ethernet_etherType__st0;
      ethernet_etherType_s1 <= ethernet_etherType;
      out_std_meta_egress_spec_s1 <= out_std_meta_egress_spec__st0;
      out_std_meta_mcast_grp_s1 <= out_std_meta_mcast_grp__st0;
      __stage_cond_0_r <= (ethernet_valid);
    end
  end

  // ---- Pipeline stage 1 (registered 1 cycle(s) after stage 0) ----
  always_comb begin
    drop = drop_s1;
    out_ethernet_valid = out_ethernet_valid_s1;
    ethernet_valid__st1 = ethernet_valid_s1;
    out_ethernet_dstAddr = out_ethernet_dstAddr_s1;
    ethernet_dstAddr__st1 = ethernet_dstAddr_s1;
    out_ethernet_srcAddr = out_ethernet_srcAddr_s1;
    ethernet_srcAddr__st1 = ethernet_srcAddr_s1;
    out_ethernet_etherType = out_ethernet_etherType_s1;
    ethernet_etherType__st1 = ethernet_etherType_s1;
    out_std_meta_egress_spec = out_std_meta_egress_spec_s1;
    out_std_meta_mcast_grp = out_std_meta_mcast_grp_s1;

    // apply block (stage 1 of 1)
    if (__stage_cond_0_r) begin
      // mac_lookup.apply()
      if (mac_lookup_hit) begin
        unique case (mac_lookup_act_id)
          2'd0: ; // NoAction
          2'd1: begin // multicast
            out_std_meta_mcast_grp = 'h0001;
          end
          2'd2: begin // mac_forward
            out_std_meta_egress_spec = mac_lookup_p_port;
          end
          2'd3: begin // drop
            drop = 1;
          end
          default: ; // default = multicast
        endcase
      end else begin // multicast on miss
        out_std_meta_mcast_grp = 'h0001;
      end
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) valid_out <= 0;
    else        valid_out <= valid_s1;
  end

endmodule
