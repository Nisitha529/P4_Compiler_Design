module processing_generated (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        valid_in,

  // Header valid flags
  input  logic        packet_in_valid,
  input  logic        packet_out_valid,
  input  logic        ethernet_valid,
  input  logic        ipv4_valid,

  // Header field inputs
  input  logic [15:0] packet_in_input_port,
  input  logic [7:0] packet_in_punt_reason,
  input  logic [7:0] packet_in_opcode,
  input  logic [7:0] packet_out_opcode,
  input  logic [7:0] packet_out_reserved1,
  input  logic [31:0] packet_out_operand0,
  input  logic [47:0] ethernet_dstAddr,
  input  logic [47:0] ethernet_srcAddr,
  input  logic [15:0] ethernet_etherType,
  input  logic [3:0] ipv4_version,
  input  logic [3:0] ipv4_ihl,
  input  logic [7:0] ipv4_diffserv,
  input  logic [15:0] ipv4_totalLen,
  input  logic [15:0] ipv4_identification,
  input  logic [2:0] ipv4_flags,
  input  logic [12:0] ipv4_fragOffset,
  input  logic [7:0] ipv4_ttl,
  input  logic [7:0] ipv4_protocol,
  input  logic [15:0] ipv4_hdrChecksum,
  input  logic [31:0] ipv4_srcAddr,
  input  logic [31:0] ipv4_dstAddr,

  // Metadata inputs
  input  logic [8:0] meta_ingress_port,
  input  logic [7:0] meta_punt_reason,
  input  logic [7:0] meta_opcode,

  // Standard metadata inputs (table key sources)
  input  logic [8:0] std_meta_ingress_port,

  // Header valid flag outputs (may be modified by setValid/setInvalid)
  output logic        out_packet_in_valid,
  output logic        out_packet_out_valid,
  output logic        out_ethernet_valid,
  output logic        out_ipv4_valid,

  // Header field outputs (pass-through, optionally modified)
  output logic [15:0] out_packet_in_input_port,
  output logic [7:0] out_packet_in_punt_reason,
  output logic [7:0] out_packet_in_opcode,
  output logic [7:0] out_packet_out_opcode,
  output logic [7:0] out_packet_out_reserved1,
  output logic [31:0] out_packet_out_operand0,
  output logic [47:0] out_ethernet_dstAddr,
  output logic [47:0] out_ethernet_srcAddr,
  output logic [15:0] out_ethernet_etherType,
  output logic [3:0] out_ipv4_version,
  output logic [3:0] out_ipv4_ihl,
  output logic [7:0] out_ipv4_diffserv,
  output logic [15:0] out_ipv4_totalLen,
  output logic [15:0] out_ipv4_identification,
  output logic [2:0] out_ipv4_flags,
  output logic [12:0] out_ipv4_fragOffset,
  output logic [7:0] out_ipv4_ttl,
  output logic [7:0] out_ipv4_protocol,
  output logic [15:0] out_ipv4_hdrChecksum,
  output logic [31:0] out_ipv4_srcAddr,
  output logic [31:0] out_ipv4_dstAddr,

  // Standard metadata outputs
  output logic [8:0] out_std_meta_egress_spec,

  // Control-plane write ports for table instances
  input  logic        switch_0_table_cp_wr_en,
  input  logic [0:0] switch_0_table_cp_wr_idx,
  input  logic [7:0] switch_0_table_cp_wr_key_switch_0_key,
  input  logic [1:0] switch_0_table_cp_wr_action,
  input  logic        flow_cache_cp_wr_en,
  input  logic [15:0] flow_cache_cp_wr_idx,
  input  logic [7:0] flow_cache_cp_wr_key_protocol,
  input  logic [31:0] flow_cache_cp_wr_key_srcAddr,
  input  logic [31:0] flow_cache_cp_wr_key_dstAddr,
  input  logic [1:0] flow_cache_cp_wr_action,
  input  logic [8:0] flow_cache_cp_wr_p_port,
  input  logic [0:0] flow_cache_cp_wr_p_decrement_ttl,
  input  logic [5:0] flow_cache_cp_wr_p_new_dscp,
  input  logic [47:0] flow_cache_cp_wr_p_dst_eth_addr,

  // Table hit outputs
  output logic        switch_0_table_hit_out,
  output logic        flow_cache_hit_out,

  output logic        valid_out,
  output logic        drop
);

  logic [6:0] _padding_0;
  logic [7:0] switch_0_key;
  logic [7:0] tmp;
  logic [31:0] tmp_0;
  logic [31:0] tmp_1;

  // Metadata shadow locals (writable copies of metadata inputs)
  logic [8:0] meta_ingress_port_w;
  logic [7:0] meta_punt_reason_w;
  logic [7:0] meta_opcode_w;

  // Pipeline-stage forwarding registers (one set per exact-match
  // table boundary in the chain)
  logic valid_s1;
  logic out_packet_in_valid_s1;
  logic packet_in_valid_s1;
  logic out_packet_out_valid_s1;
  logic packet_out_valid_s1;
  logic out_ethernet_valid_s1;
  logic ethernet_valid_s1;
  logic out_ipv4_valid_s1;
  logic ipv4_valid_s1;
  logic [15:0] out_packet_in_input_port_s1;
  logic [15:0] packet_in_input_port_s1;
  logic [7:0] out_packet_in_punt_reason_s1;
  logic [7:0] packet_in_punt_reason_s1;
  logic [7:0] out_packet_in_opcode_s1;
  logic [7:0] packet_in_opcode_s1;
  logic [7:0] out_packet_out_opcode_s1;
  logic [7:0] packet_out_opcode_s1;
  logic [7:0] out_packet_out_reserved1_s1;
  logic [7:0] packet_out_reserved1_s1;
  logic [31:0] out_packet_out_operand0_s1;
  logic [31:0] packet_out_operand0_s1;
  logic [47:0] out_ethernet_dstAddr_s1;
  logic [47:0] ethernet_dstAddr_s1;
  logic [47:0] out_ethernet_srcAddr_s1;
  logic [47:0] ethernet_srcAddr_s1;
  logic [15:0] out_ethernet_etherType_s1;
  logic [15:0] ethernet_etherType_s1;
  logic [3:0] out_ipv4_version_s1;
  logic [3:0] ipv4_version_s1;
  logic [3:0] out_ipv4_ihl_s1;
  logic [3:0] ipv4_ihl_s1;
  logic [7:0] out_ipv4_diffserv_s1;
  logic [7:0] ipv4_diffserv_s1;
  logic [15:0] out_ipv4_totalLen_s1;
  logic [15:0] ipv4_totalLen_s1;
  logic [15:0] out_ipv4_identification_s1;
  logic [15:0] ipv4_identification_s1;
  logic [2:0] out_ipv4_flags_s1;
  logic [2:0] ipv4_flags_s1;
  logic [12:0] out_ipv4_fragOffset_s1;
  logic [12:0] ipv4_fragOffset_s1;
  logic [7:0] out_ipv4_ttl_s1;
  logic [7:0] ipv4_ttl_s1;
  logic [7:0] out_ipv4_protocol_s1;
  logic [7:0] ipv4_protocol_s1;
  logic [15:0] out_ipv4_hdrChecksum_s1;
  logic [15:0] ipv4_hdrChecksum_s1;
  logic [31:0] out_ipv4_srcAddr_s1;
  logic [31:0] ipv4_srcAddr_s1;
  logic [31:0] out_ipv4_dstAddr_s1;
  logic [31:0] ipv4_dstAddr_s1;
  logic [8:0] meta_ingress_port_w_s1;
  logic [7:0] meta_punt_reason_w_s1;
  logic [7:0] meta_opcode_w_s1;
  logic [6:0] _padding_0_s1;
  logic [7:0] switch_0_key_s1;
  logic [7:0] tmp_s1;
  logic [31:0] tmp_0_s1;
  logic [31:0] tmp_1_s1;
  logic [8:0] out_std_meta_egress_spec_s1;
  logic [8:0] std_meta_ingress_port_s1;
  logic drop_s1;
  logic __stage_cond_0_r;
  logic valid_s2;
  logic out_packet_in_valid_s2;
  logic packet_in_valid_s2;
  logic out_packet_out_valid_s2;
  logic packet_out_valid_s2;
  logic out_ethernet_valid_s2;
  logic ethernet_valid_s2;
  logic out_ipv4_valid_s2;
  logic ipv4_valid_s2;
  logic [15:0] out_packet_in_input_port_s2;
  logic [15:0] packet_in_input_port_s2;
  logic [7:0] out_packet_in_punt_reason_s2;
  logic [7:0] packet_in_punt_reason_s2;
  logic [7:0] out_packet_in_opcode_s2;
  logic [7:0] packet_in_opcode_s2;
  logic [7:0] out_packet_out_opcode_s2;
  logic [7:0] packet_out_opcode_s2;
  logic [7:0] out_packet_out_reserved1_s2;
  logic [7:0] packet_out_reserved1_s2;
  logic [31:0] out_packet_out_operand0_s2;
  logic [31:0] packet_out_operand0_s2;
  logic [47:0] out_ethernet_dstAddr_s2;
  logic [47:0] ethernet_dstAddr_s2;
  logic [47:0] out_ethernet_srcAddr_s2;
  logic [47:0] ethernet_srcAddr_s2;
  logic [15:0] out_ethernet_etherType_s2;
  logic [15:0] ethernet_etherType_s2;
  logic [3:0] out_ipv4_version_s2;
  logic [3:0] ipv4_version_s2;
  logic [3:0] out_ipv4_ihl_s2;
  logic [3:0] ipv4_ihl_s2;
  logic [7:0] out_ipv4_diffserv_s2;
  logic [7:0] ipv4_diffserv_s2;
  logic [15:0] out_ipv4_totalLen_s2;
  logic [15:0] ipv4_totalLen_s2;
  logic [15:0] out_ipv4_identification_s2;
  logic [15:0] ipv4_identification_s2;
  logic [2:0] out_ipv4_flags_s2;
  logic [2:0] ipv4_flags_s2;
  logic [12:0] out_ipv4_fragOffset_s2;
  logic [12:0] ipv4_fragOffset_s2;
  logic [7:0] out_ipv4_ttl_s2;
  logic [7:0] ipv4_ttl_s2;
  logic [7:0] out_ipv4_protocol_s2;
  logic [7:0] ipv4_protocol_s2;
  logic [15:0] out_ipv4_hdrChecksum_s2;
  logic [15:0] ipv4_hdrChecksum_s2;
  logic [31:0] out_ipv4_srcAddr_s2;
  logic [31:0] ipv4_srcAddr_s2;
  logic [31:0] out_ipv4_dstAddr_s2;
  logic [31:0] ipv4_dstAddr_s2;
  logic [8:0] meta_ingress_port_w_s2;
  logic [7:0] meta_punt_reason_w_s2;
  logic [7:0] meta_opcode_w_s2;
  logic [6:0] _padding_0_s2;
  logic [7:0] switch_0_key_s2;
  logic [7:0] tmp_s2;
  logic [31:0] tmp_0_s2;
  logic [31:0] tmp_1_s2;
  logic [8:0] out_std_meta_egress_spec_s2;
  logic [8:0] std_meta_ingress_port_s2;
  logic drop_s2;

  // Pool-A (out_*/drop) working copies -- every stage except the
  // last, which drives the real output ports directly
  logic out_packet_in_valid__st0;
  logic out_packet_out_valid__st0;
  logic out_ethernet_valid__st0;
  logic out_ipv4_valid__st0;
  logic [15:0] out_packet_in_input_port__st0;
  logic [7:0] out_packet_in_punt_reason__st0;
  logic [7:0] out_packet_in_opcode__st0;
  logic [7:0] out_packet_out_opcode__st0;
  logic [7:0] out_packet_out_reserved1__st0;
  logic [31:0] out_packet_out_operand0__st0;
  logic [47:0] out_ethernet_dstAddr__st0;
  logic [47:0] out_ethernet_srcAddr__st0;
  logic [15:0] out_ethernet_etherType__st0;
  logic [3:0] out_ipv4_version__st0;
  logic [3:0] out_ipv4_ihl__st0;
  logic [7:0] out_ipv4_diffserv__st0;
  logic [15:0] out_ipv4_totalLen__st0;
  logic [15:0] out_ipv4_identification__st0;
  logic [2:0] out_ipv4_flags__st0;
  logic [12:0] out_ipv4_fragOffset__st0;
  logic [7:0] out_ipv4_ttl__st0;
  logic [7:0] out_ipv4_protocol__st0;
  logic [15:0] out_ipv4_hdrChecksum__st0;
  logic [31:0] out_ipv4_srcAddr__st0;
  logic [31:0] out_ipv4_dstAddr__st0;
  logic [8:0] out_std_meta_egress_spec__st0;
  logic drop__st0;
  logic out_packet_in_valid__st1;
  logic out_packet_out_valid__st1;
  logic out_ethernet_valid__st1;
  logic out_ipv4_valid__st1;
  logic [15:0] out_packet_in_input_port__st1;
  logic [7:0] out_packet_in_punt_reason__st1;
  logic [7:0] out_packet_in_opcode__st1;
  logic [7:0] out_packet_out_opcode__st1;
  logic [7:0] out_packet_out_reserved1__st1;
  logic [31:0] out_packet_out_operand0__st1;
  logic [47:0] out_ethernet_dstAddr__st1;
  logic [47:0] out_ethernet_srcAddr__st1;
  logic [15:0] out_ethernet_etherType__st1;
  logic [3:0] out_ipv4_version__st1;
  logic [3:0] out_ipv4_ihl__st1;
  logic [7:0] out_ipv4_diffserv__st1;
  logic [15:0] out_ipv4_totalLen__st1;
  logic [15:0] out_ipv4_identification__st1;
  logic [2:0] out_ipv4_flags__st1;
  logic [12:0] out_ipv4_fragOffset__st1;
  logic [7:0] out_ipv4_ttl__st1;
  logic [7:0] out_ipv4_protocol__st1;
  logic [15:0] out_ipv4_hdrChecksum__st1;
  logic [31:0] out_ipv4_srcAddr__st1;
  logic [31:0] out_ipv4_dstAddr__st1;
  logic [8:0] out_std_meta_egress_spec__st1;
  logic drop__st1;

  // Pool-B (locals/meta shadow/raw hdr+std_meta reads) working
  // copies -- every stage except the first, which reads live inputs
  logic [6:0] _padding_0__st1;
  logic [7:0] switch_0_key__st1;
  logic [7:0] tmp__st1;
  logic [31:0] tmp_0__st1;
  logic [31:0] tmp_1__st1;
  logic [8:0] meta_ingress_port_w__st1;
  logic [7:0] meta_punt_reason_w__st1;
  logic [7:0] meta_opcode_w__st1;
  logic packet_in_valid__st1;
  logic packet_out_valid__st1;
  logic ethernet_valid__st1;
  logic ipv4_valid__st1;
  logic [15:0] packet_in_input_port__st1;
  logic [7:0] packet_in_punt_reason__st1;
  logic [7:0] packet_in_opcode__st1;
  logic [7:0] packet_out_opcode__st1;
  logic [7:0] packet_out_reserved1__st1;
  logic [31:0] packet_out_operand0__st1;
  logic [47:0] ethernet_dstAddr__st1;
  logic [47:0] ethernet_srcAddr__st1;
  logic [15:0] ethernet_etherType__st1;
  logic [3:0] ipv4_version__st1;
  logic [3:0] ipv4_ihl__st1;
  logic [7:0] ipv4_diffserv__st1;
  logic [15:0] ipv4_totalLen__st1;
  logic [15:0] ipv4_identification__st1;
  logic [2:0] ipv4_flags__st1;
  logic [12:0] ipv4_fragOffset__st1;
  logic [7:0] ipv4_ttl__st1;
  logic [7:0] ipv4_protocol__st1;
  logic [15:0] ipv4_hdrChecksum__st1;
  logic [31:0] ipv4_srcAddr__st1;
  logic [31:0] ipv4_dstAddr__st1;
  logic [8:0] std_meta_ingress_port__st1;
  logic [6:0] _padding_0__st2;
  logic [7:0] switch_0_key__st2;
  logic [7:0] tmp__st2;
  logic [31:0] tmp_0__st2;
  logic [31:0] tmp_1__st2;
  logic [8:0] meta_ingress_port_w__st2;
  logic [7:0] meta_punt_reason_w__st2;
  logic [7:0] meta_opcode_w__st2;
  logic packet_in_valid__st2;
  logic packet_out_valid__st2;
  logic ethernet_valid__st2;
  logic ipv4_valid__st2;
  logic [15:0] packet_in_input_port__st2;
  logic [7:0] packet_in_punt_reason__st2;
  logic [7:0] packet_in_opcode__st2;
  logic [7:0] packet_out_opcode__st2;
  logic [7:0] packet_out_reserved1__st2;
  logic [31:0] packet_out_operand0__st2;
  logic [47:0] ethernet_dstAddr__st2;
  logic [47:0] ethernet_srcAddr__st2;
  logic [15:0] ethernet_etherType__st2;
  logic [3:0] ipv4_version__st2;
  logic [3:0] ipv4_ihl__st2;
  logic [7:0] ipv4_diffserv__st2;
  logic [15:0] ipv4_totalLen__st2;
  logic [15:0] ipv4_identification__st2;
  logic [2:0] ipv4_flags__st2;
  logic [12:0] ipv4_fragOffset__st2;
  logic [7:0] ipv4_ttl__st2;
  logic [7:0] ipv4_protocol__st2;
  logic [15:0] ipv4_hdrChecksum__st2;
  logic [31:0] ipv4_srcAddr__st2;
  logic [31:0] ipv4_dstAddr__st2;
  logic [8:0] std_meta_ingress_port__st2;

  // Table lookup result wires
  logic        switch_0_table_hit;
  logic [1:0] switch_0_table_act_id;
  logic        flow_cache_hit;
  logic [1:0] flow_cache_act_id;
  logic [8:0] flow_cache_p_port;
  logic [0:0] flow_cache_p_decrement_ttl;
  logic [5:0] flow_cache_p_new_dscp;
  logic [47:0] flow_cache_p_dst_eth_addr;

  // Table module instantiations
  switch_0_table_table #(.DEPTH(1)) u_switch_0_table (
    .clk    (clk),
    .rst_n  (rst_n),
    .lkp_switch_0_key    (switch_0_key),
    .hit       (switch_0_table_hit),
    .action_id (switch_0_table_act_id),
    .cp_wr_en  (switch_0_table_cp_wr_en),
    .cp_wr_idx (switch_0_table_cp_wr_idx),
    .cp_wr_key_switch_0_key (switch_0_table_cp_wr_key_switch_0_key),
    .cp_wr_action (switch_0_table_cp_wr_action)
  );

  flow_cache_table #(.DEPTH(65536)) u_flow_cache (
    .clk    (clk),
    .rst_n  (rst_n),
    .lkp_protocol    (ipv4_protocol),
    .lkp_srcAddr    (ipv4_srcAddr),
    .lkp_dstAddr    (ipv4_dstAddr),
    .hit       (flow_cache_hit),
    .action_id (flow_cache_act_id),
    .p_port  (flow_cache_p_port),
    .p_decrement_ttl  (flow_cache_p_decrement_ttl),
    .p_new_dscp  (flow_cache_p_new_dscp),
    .p_dst_eth_addr  (flow_cache_p_dst_eth_addr),
    .cp_wr_en  (flow_cache_cp_wr_en),
    .cp_wr_idx (flow_cache_cp_wr_idx),
    .cp_wr_key_protocol (flow_cache_cp_wr_key_protocol),
    .cp_wr_key_srcAddr (flow_cache_cp_wr_key_srcAddr),
    .cp_wr_key_dstAddr (flow_cache_cp_wr_key_dstAddr),
    .cp_wr_action (flow_cache_cp_wr_action),
    .cp_wr_p_port (flow_cache_cp_wr_p_port),
    .cp_wr_p_decrement_ttl (flow_cache_cp_wr_p_decrement_ttl),
    .cp_wr_p_new_dscp (flow_cache_cp_wr_p_new_dscp),
    .cp_wr_p_dst_eth_addr (flow_cache_cp_wr_p_dst_eth_addr)
  );

  // Table hit outputs
  assign switch_0_table_hit_out = switch_0_table_hit;
  assign flow_cache_hit_out = flow_cache_hit;

  // ---- Pipeline stage 0 (combinational, feeds the first exact-match table boundary) ----
  always_comb begin
    drop__st0 = 0;
    _padding_0 = 7'b0;
    switch_0_key = 8'b0;
    tmp = 8'b0;
    tmp_0 = 32'b0;
    tmp_1 = 32'b0;

    // Metadata shadow defaults (init from inputs)
    meta_ingress_port_w = meta_ingress_port;
    meta_punt_reason_w = meta_punt_reason;
    meta_opcode_w = meta_opcode;

    // Standard metadata defaults
    out_std_meta_egress_spec__st0 = 9'b0;

    // Header valid flag pass-through defaults
    out_packet_in_valid__st0 = packet_in_valid;
    out_packet_out_valid__st0 = packet_out_valid;
    out_ethernet_valid__st0 = ethernet_valid;
    out_ipv4_valid__st0 = ipv4_valid;

    // Header field pass-through defaults
    out_packet_in_input_port__st0 = packet_in_input_port;
    out_packet_in_punt_reason__st0 = packet_in_punt_reason;
    out_packet_in_opcode__st0 = packet_in_opcode;
    out_packet_out_opcode__st0 = packet_out_opcode;
    out_packet_out_reserved1__st0 = packet_out_reserved1;
    out_packet_out_operand0__st0 = packet_out_operand0;
    out_ethernet_dstAddr__st0 = ethernet_dstAddr;
    out_ethernet_srcAddr__st0 = ethernet_srcAddr;
    out_ethernet_etherType__st0 = ethernet_etherType;
    out_ipv4_version__st0 = ipv4_version;
    out_ipv4_ihl__st0 = ipv4_ihl;
    out_ipv4_diffserv__st0 = ipv4_diffserv;
    out_ipv4_totalLen__st0 = ipv4_totalLen;
    out_ipv4_identification__st0 = ipv4_identification;
    out_ipv4_flags__st0 = ipv4_flags;
    out_ipv4_fragOffset__st0 = ipv4_fragOffset;
    out_ipv4_ttl__st0 = ipv4_ttl;
    out_ipv4_protocol__st0 = ipv4_protocol;
    out_ipv4_hdrChecksum__st0 = ipv4_hdrChecksum;
    out_ipv4_srcAddr__st0 = ipv4_srcAddr;
    out_ipv4_dstAddr__st0 = ipv4_dstAddr;

    // apply block (stage 0 of 2)
    if (packet_out_valid) begin
      tmp_0 = ((ipv4_dstAddr & 'h3F) & 'hFFFFFFFF);
      /* UNIMPLEMENTED EXTERN: _bmv2_count(0, tmp_0) */
      switch_0_key = packet_out_opcode;
    end
    else begin
      if (ipv4_valid) begin
        // flow_cache.apply()
        if (flow_cache_hit) begin
          unique case (flow_cache_act_id)
            2'd0: ; // NoAction
            2'd1: begin // cached_action
              out_std_meta_egress_spec__st0 = flow_cache_p_port;
              if ((flow_cache_p_decrement_ttl == 'h01)) begin
                tmp = ((ipv4_ttl < 'h01) ? 8'd0 : (ipv4_ttl - 'h01));
              end
              else begin
                tmp = ipv4_ttl;
              end
              out_ipv4_ttl__st0 = tmp;
              out_ipv4_diffserv__st0 = ((ipv4_diffserv & 'h03) | ((((flow_cache_p_new_dscp & 'hFF) << 'h2) & 'hFF) & 'hFC));
              out_ethernet_dstAddr__st0 = flow_cache_p_dst_eth_addr;
            end
            2'd2: begin // drop_packet
              drop__st0 = 1;
            end
            2'd3: begin // flow_unknown
              /* UNIMPLEMENTED EXTERN: _bmv2_clone_ingress_pkt_to_egress('h00000039, 'h1) */
              meta_ingress_port_w = std_meta_ingress_port;
              meta_punt_reason_w = 'h01;
              meta_opcode_w = 'h00;
              drop__st0 = 1;
            end
            default: ; // default = flow_unknown
          endcase
        end else begin // flow_unknown on miss
          /* UNIMPLEMENTED EXTERN: _bmv2_clone_ingress_pkt_to_egress('h00000039, 'h1) */
          meta_ingress_port_w = std_meta_ingress_port;
          meta_punt_reason_w = 'h01;
          meta_opcode_w = 'h00;
          drop__st0 = 1;
        end
      end
      else begin
        drop__st0 = 1;
      end
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
      _padding_0_s1 <= _padding_0;
      switch_0_key_s1 <= switch_0_key;
      tmp_s1 <= tmp;
      tmp_0_s1 <= tmp_0;
      tmp_1_s1 <= tmp_1;
      meta_ingress_port_w_s1 <= meta_ingress_port_w;
      meta_punt_reason_w_s1 <= meta_punt_reason_w;
      meta_opcode_w_s1 <= meta_opcode_w;
      out_packet_in_valid_s1 <= out_packet_in_valid__st0;
      packet_in_valid_s1 <= packet_in_valid;
      out_packet_out_valid_s1 <= out_packet_out_valid__st0;
      packet_out_valid_s1 <= packet_out_valid;
      out_ethernet_valid_s1 <= out_ethernet_valid__st0;
      ethernet_valid_s1 <= ethernet_valid;
      out_ipv4_valid_s1 <= out_ipv4_valid__st0;
      ipv4_valid_s1 <= ipv4_valid;
      out_packet_in_input_port_s1 <= out_packet_in_input_port__st0;
      packet_in_input_port_s1 <= packet_in_input_port;
      out_packet_in_punt_reason_s1 <= out_packet_in_punt_reason__st0;
      packet_in_punt_reason_s1 <= packet_in_punt_reason;
      out_packet_in_opcode_s1 <= out_packet_in_opcode__st0;
      packet_in_opcode_s1 <= packet_in_opcode;
      out_packet_out_opcode_s1 <= out_packet_out_opcode__st0;
      packet_out_opcode_s1 <= packet_out_opcode;
      out_packet_out_reserved1_s1 <= out_packet_out_reserved1__st0;
      packet_out_reserved1_s1 <= packet_out_reserved1;
      out_packet_out_operand0_s1 <= out_packet_out_operand0__st0;
      packet_out_operand0_s1 <= packet_out_operand0;
      out_ethernet_dstAddr_s1 <= out_ethernet_dstAddr__st0;
      ethernet_dstAddr_s1 <= ethernet_dstAddr;
      out_ethernet_srcAddr_s1 <= out_ethernet_srcAddr__st0;
      ethernet_srcAddr_s1 <= ethernet_srcAddr;
      out_ethernet_etherType_s1 <= out_ethernet_etherType__st0;
      ethernet_etherType_s1 <= ethernet_etherType;
      out_ipv4_version_s1 <= out_ipv4_version__st0;
      ipv4_version_s1 <= ipv4_version;
      out_ipv4_ihl_s1 <= out_ipv4_ihl__st0;
      ipv4_ihl_s1 <= ipv4_ihl;
      out_ipv4_diffserv_s1 <= out_ipv4_diffserv__st0;
      ipv4_diffserv_s1 <= ipv4_diffserv;
      out_ipv4_totalLen_s1 <= out_ipv4_totalLen__st0;
      ipv4_totalLen_s1 <= ipv4_totalLen;
      out_ipv4_identification_s1 <= out_ipv4_identification__st0;
      ipv4_identification_s1 <= ipv4_identification;
      out_ipv4_flags_s1 <= out_ipv4_flags__st0;
      ipv4_flags_s1 <= ipv4_flags;
      out_ipv4_fragOffset_s1 <= out_ipv4_fragOffset__st0;
      ipv4_fragOffset_s1 <= ipv4_fragOffset;
      out_ipv4_ttl_s1 <= out_ipv4_ttl__st0;
      ipv4_ttl_s1 <= ipv4_ttl;
      out_ipv4_protocol_s1 <= out_ipv4_protocol__st0;
      ipv4_protocol_s1 <= ipv4_protocol;
      out_ipv4_hdrChecksum_s1 <= out_ipv4_hdrChecksum__st0;
      ipv4_hdrChecksum_s1 <= ipv4_hdrChecksum;
      out_ipv4_srcAddr_s1 <= out_ipv4_srcAddr__st0;
      ipv4_srcAddr_s1 <= ipv4_srcAddr;
      out_ipv4_dstAddr_s1 <= out_ipv4_dstAddr__st0;
      ipv4_dstAddr_s1 <= ipv4_dstAddr;
      out_std_meta_egress_spec_s1 <= out_std_meta_egress_spec__st0;
      std_meta_ingress_port_s1 <= std_meta_ingress_port;
      __stage_cond_0_r <= (packet_out_valid);
    end
  end

  // ---- Pipeline stage 1 (registered 1 cycle(s) after stage 0) ----
  always_comb begin
    drop__st1 = drop_s1;
    _padding_0__st1 = _padding_0_s1;
    switch_0_key__st1 = switch_0_key_s1;
    tmp__st1 = tmp_s1;
    tmp_0__st1 = tmp_0_s1;
    tmp_1__st1 = tmp_1_s1;
    meta_ingress_port_w__st1 = meta_ingress_port_w_s1;
    meta_punt_reason_w__st1 = meta_punt_reason_w_s1;
    meta_opcode_w__st1 = meta_opcode_w_s1;
    out_packet_in_valid__st1 = out_packet_in_valid_s1;
    packet_in_valid__st1 = packet_in_valid_s1;
    out_packet_out_valid__st1 = out_packet_out_valid_s1;
    packet_out_valid__st1 = packet_out_valid_s1;
    out_ethernet_valid__st1 = out_ethernet_valid_s1;
    ethernet_valid__st1 = ethernet_valid_s1;
    out_ipv4_valid__st1 = out_ipv4_valid_s1;
    ipv4_valid__st1 = ipv4_valid_s1;
    out_packet_in_input_port__st1 = out_packet_in_input_port_s1;
    packet_in_input_port__st1 = packet_in_input_port_s1;
    out_packet_in_punt_reason__st1 = out_packet_in_punt_reason_s1;
    packet_in_punt_reason__st1 = packet_in_punt_reason_s1;
    out_packet_in_opcode__st1 = out_packet_in_opcode_s1;
    packet_in_opcode__st1 = packet_in_opcode_s1;
    out_packet_out_opcode__st1 = out_packet_out_opcode_s1;
    packet_out_opcode__st1 = packet_out_opcode_s1;
    out_packet_out_reserved1__st1 = out_packet_out_reserved1_s1;
    packet_out_reserved1__st1 = packet_out_reserved1_s1;
    out_packet_out_operand0__st1 = out_packet_out_operand0_s1;
    packet_out_operand0__st1 = packet_out_operand0_s1;
    out_ethernet_dstAddr__st1 = out_ethernet_dstAddr_s1;
    ethernet_dstAddr__st1 = ethernet_dstAddr_s1;
    out_ethernet_srcAddr__st1 = out_ethernet_srcAddr_s1;
    ethernet_srcAddr__st1 = ethernet_srcAddr_s1;
    out_ethernet_etherType__st1 = out_ethernet_etherType_s1;
    ethernet_etherType__st1 = ethernet_etherType_s1;
    out_ipv4_version__st1 = out_ipv4_version_s1;
    ipv4_version__st1 = ipv4_version_s1;
    out_ipv4_ihl__st1 = out_ipv4_ihl_s1;
    ipv4_ihl__st1 = ipv4_ihl_s1;
    out_ipv4_diffserv__st1 = out_ipv4_diffserv_s1;
    ipv4_diffserv__st1 = ipv4_diffserv_s1;
    out_ipv4_totalLen__st1 = out_ipv4_totalLen_s1;
    ipv4_totalLen__st1 = ipv4_totalLen_s1;
    out_ipv4_identification__st1 = out_ipv4_identification_s1;
    ipv4_identification__st1 = ipv4_identification_s1;
    out_ipv4_flags__st1 = out_ipv4_flags_s1;
    ipv4_flags__st1 = ipv4_flags_s1;
    out_ipv4_fragOffset__st1 = out_ipv4_fragOffset_s1;
    ipv4_fragOffset__st1 = ipv4_fragOffset_s1;
    out_ipv4_ttl__st1 = out_ipv4_ttl_s1;
    ipv4_ttl__st1 = ipv4_ttl_s1;
    out_ipv4_protocol__st1 = out_ipv4_protocol_s1;
    ipv4_protocol__st1 = ipv4_protocol_s1;
    out_ipv4_hdrChecksum__st1 = out_ipv4_hdrChecksum_s1;
    ipv4_hdrChecksum__st1 = ipv4_hdrChecksum_s1;
    out_ipv4_srcAddr__st1 = out_ipv4_srcAddr_s1;
    ipv4_srcAddr__st1 = ipv4_srcAddr_s1;
    out_ipv4_dstAddr__st1 = out_ipv4_dstAddr_s1;
    ipv4_dstAddr__st1 = ipv4_dstAddr_s1;
    out_std_meta_egress_spec__st1 = out_std_meta_egress_spec_s1;
    std_meta_ingress_port__st1 = std_meta_ingress_port_s1;
  end

  // Forward stage-1 state into stage-2 registers (1-cycle
  // boundary — matches the exact-match table's registered latency)
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      valid_s2 <= 1'b0;
    end else begin
      valid_s2 <= valid_s1;
      drop_s2 <= drop__st1;
      _padding_0_s2 <= _padding_0__st1;
      switch_0_key_s2 <= switch_0_key__st1;
      tmp_s2 <= tmp__st1;
      tmp_0_s2 <= tmp_0__st1;
      tmp_1_s2 <= tmp_1__st1;
      meta_ingress_port_w_s2 <= meta_ingress_port_w__st1;
      meta_punt_reason_w_s2 <= meta_punt_reason_w__st1;
      meta_opcode_w_s2 <= meta_opcode_w__st1;
      out_packet_in_valid_s2 <= out_packet_in_valid__st1;
      packet_in_valid_s2 <= packet_in_valid__st1;
      out_packet_out_valid_s2 <= out_packet_out_valid__st1;
      packet_out_valid_s2 <= packet_out_valid__st1;
      out_ethernet_valid_s2 <= out_ethernet_valid__st1;
      ethernet_valid_s2 <= ethernet_valid__st1;
      out_ipv4_valid_s2 <= out_ipv4_valid__st1;
      ipv4_valid_s2 <= ipv4_valid__st1;
      out_packet_in_input_port_s2 <= out_packet_in_input_port__st1;
      packet_in_input_port_s2 <= packet_in_input_port__st1;
      out_packet_in_punt_reason_s2 <= out_packet_in_punt_reason__st1;
      packet_in_punt_reason_s2 <= packet_in_punt_reason__st1;
      out_packet_in_opcode_s2 <= out_packet_in_opcode__st1;
      packet_in_opcode_s2 <= packet_in_opcode__st1;
      out_packet_out_opcode_s2 <= out_packet_out_opcode__st1;
      packet_out_opcode_s2 <= packet_out_opcode__st1;
      out_packet_out_reserved1_s2 <= out_packet_out_reserved1__st1;
      packet_out_reserved1_s2 <= packet_out_reserved1__st1;
      out_packet_out_operand0_s2 <= out_packet_out_operand0__st1;
      packet_out_operand0_s2 <= packet_out_operand0__st1;
      out_ethernet_dstAddr_s2 <= out_ethernet_dstAddr__st1;
      ethernet_dstAddr_s2 <= ethernet_dstAddr__st1;
      out_ethernet_srcAddr_s2 <= out_ethernet_srcAddr__st1;
      ethernet_srcAddr_s2 <= ethernet_srcAddr__st1;
      out_ethernet_etherType_s2 <= out_ethernet_etherType__st1;
      ethernet_etherType_s2 <= ethernet_etherType__st1;
      out_ipv4_version_s2 <= out_ipv4_version__st1;
      ipv4_version_s2 <= ipv4_version__st1;
      out_ipv4_ihl_s2 <= out_ipv4_ihl__st1;
      ipv4_ihl_s2 <= ipv4_ihl__st1;
      out_ipv4_diffserv_s2 <= out_ipv4_diffserv__st1;
      ipv4_diffserv_s2 <= ipv4_diffserv__st1;
      out_ipv4_totalLen_s2 <= out_ipv4_totalLen__st1;
      ipv4_totalLen_s2 <= ipv4_totalLen__st1;
      out_ipv4_identification_s2 <= out_ipv4_identification__st1;
      ipv4_identification_s2 <= ipv4_identification__st1;
      out_ipv4_flags_s2 <= out_ipv4_flags__st1;
      ipv4_flags_s2 <= ipv4_flags__st1;
      out_ipv4_fragOffset_s2 <= out_ipv4_fragOffset__st1;
      ipv4_fragOffset_s2 <= ipv4_fragOffset__st1;
      out_ipv4_ttl_s2 <= out_ipv4_ttl__st1;
      ipv4_ttl_s2 <= ipv4_ttl__st1;
      out_ipv4_protocol_s2 <= out_ipv4_protocol__st1;
      ipv4_protocol_s2 <= ipv4_protocol__st1;
      out_ipv4_hdrChecksum_s2 <= out_ipv4_hdrChecksum__st1;
      ipv4_hdrChecksum_s2 <= ipv4_hdrChecksum__st1;
      out_ipv4_srcAddr_s2 <= out_ipv4_srcAddr__st1;
      ipv4_srcAddr_s2 <= ipv4_srcAddr__st1;
      out_ipv4_dstAddr_s2 <= out_ipv4_dstAddr__st1;
      ipv4_dstAddr_s2 <= ipv4_dstAddr__st1;
      out_std_meta_egress_spec_s2 <= out_std_meta_egress_spec__st1;
      std_meta_ingress_port_s2 <= std_meta_ingress_port__st1;
    end
  end

  // ---- Pipeline stage 2 (registered 2 cycle(s) after stage 0) ----
  always_comb begin
    drop = drop_s2;
    _padding_0__st2 = _padding_0_s2;
    switch_0_key__st2 = switch_0_key_s2;
    tmp__st2 = tmp_s2;
    tmp_0__st2 = tmp_0_s2;
    tmp_1__st2 = tmp_1_s2;
    meta_ingress_port_w__st2 = meta_ingress_port_w_s2;
    meta_punt_reason_w__st2 = meta_punt_reason_w_s2;
    meta_opcode_w__st2 = meta_opcode_w_s2;
    out_packet_in_valid = out_packet_in_valid_s2;
    packet_in_valid__st2 = packet_in_valid_s2;
    out_packet_out_valid = out_packet_out_valid_s2;
    packet_out_valid__st2 = packet_out_valid_s2;
    out_ethernet_valid = out_ethernet_valid_s2;
    ethernet_valid__st2 = ethernet_valid_s2;
    out_ipv4_valid = out_ipv4_valid_s2;
    ipv4_valid__st2 = ipv4_valid_s2;
    out_packet_in_input_port = out_packet_in_input_port_s2;
    packet_in_input_port__st2 = packet_in_input_port_s2;
    out_packet_in_punt_reason = out_packet_in_punt_reason_s2;
    packet_in_punt_reason__st2 = packet_in_punt_reason_s2;
    out_packet_in_opcode = out_packet_in_opcode_s2;
    packet_in_opcode__st2 = packet_in_opcode_s2;
    out_packet_out_opcode = out_packet_out_opcode_s2;
    packet_out_opcode__st2 = packet_out_opcode_s2;
    out_packet_out_reserved1 = out_packet_out_reserved1_s2;
    packet_out_reserved1__st2 = packet_out_reserved1_s2;
    out_packet_out_operand0 = out_packet_out_operand0_s2;
    packet_out_operand0__st2 = packet_out_operand0_s2;
    out_ethernet_dstAddr = out_ethernet_dstAddr_s2;
    ethernet_dstAddr__st2 = ethernet_dstAddr_s2;
    out_ethernet_srcAddr = out_ethernet_srcAddr_s2;
    ethernet_srcAddr__st2 = ethernet_srcAddr_s2;
    out_ethernet_etherType = out_ethernet_etherType_s2;
    ethernet_etherType__st2 = ethernet_etherType_s2;
    out_ipv4_version = out_ipv4_version_s2;
    ipv4_version__st2 = ipv4_version_s2;
    out_ipv4_ihl = out_ipv4_ihl_s2;
    ipv4_ihl__st2 = ipv4_ihl_s2;
    out_ipv4_diffserv = out_ipv4_diffserv_s2;
    ipv4_diffserv__st2 = ipv4_diffserv_s2;
    out_ipv4_totalLen = out_ipv4_totalLen_s2;
    ipv4_totalLen__st2 = ipv4_totalLen_s2;
    out_ipv4_identification = out_ipv4_identification_s2;
    ipv4_identification__st2 = ipv4_identification_s2;
    out_ipv4_flags = out_ipv4_flags_s2;
    ipv4_flags__st2 = ipv4_flags_s2;
    out_ipv4_fragOffset = out_ipv4_fragOffset_s2;
    ipv4_fragOffset__st2 = ipv4_fragOffset_s2;
    out_ipv4_ttl = out_ipv4_ttl_s2;
    ipv4_ttl__st2 = ipv4_ttl_s2;
    out_ipv4_protocol = out_ipv4_protocol_s2;
    ipv4_protocol__st2 = ipv4_protocol_s2;
    out_ipv4_hdrChecksum = out_ipv4_hdrChecksum_s2;
    ipv4_hdrChecksum__st2 = ipv4_hdrChecksum_s2;
    out_ipv4_srcAddr = out_ipv4_srcAddr_s2;
    ipv4_srcAddr__st2 = ipv4_srcAddr_s2;
    out_ipv4_dstAddr = out_ipv4_dstAddr_s2;
    ipv4_dstAddr__st2 = ipv4_dstAddr_s2;
    out_std_meta_egress_spec = out_std_meta_egress_spec_s2;
    std_meta_ingress_port__st2 = std_meta_ingress_port_s2;

    // apply block (stage 2 of 2)
    if (__stage_cond_0_r) begin
      // switch_0_table.apply()
      if (switch_0_table_hit) begin
        unique case (switch_0_table_act_id)
          2'd0: ; // NoAction
          2'd1: begin // switch_0_case
          end
          2'd2: begin // switch_0_case_0
          end
          default: ; // default = switch_0_case_0
        endcase
      end else begin // switch_0_case_0 on miss
      end
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) valid_out <= 0;
    else        valid_out <= valid_s2;
  end

endmodule
