module processing_generated (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        valid_in,

  // Header valid flags
  input  logic        eth_valid,
  input  logic        new_vlan_valid,
  input  logic        vlan_valid,
  input  logic        ipv4_valid,
  input  logic        ipv4opt_valid,
  input  logic        tcp_valid,
  input  logic        tcpopt_valid,
  input  logic        udp_valid,

  // Header field inputs
  input  logic [47:0] eth_dmac,
  input  logic [47:0] eth_smac,
  input  logic [15:0] eth_type,
  input  logic [2:0] new_vlan_pcp,
  input  logic [0:0] new_vlan_cfi,
  input  logic [11:0] new_vlan_vid,
  input  logic [15:0] new_vlan_tpid,
  input  logic [2:0] vlan_pcp,
  input  logic [0:0] vlan_cfi,
  input  logic [11:0] vlan_vid,
  input  logic [15:0] vlan_tpid,
  input  logic [3:0] ipv4_version,
  input  logic [3:0] ipv4_hdr_len,
  input  logic [7:0] ipv4_tos,
  input  logic [15:0] ipv4_length,
  input  logic [15:0] ipv4_id,
  input  logic [2:0] ipv4_flags,
  input  logic [12:0] ipv4_offset,
  input  logic [7:0] ipv4_ttl,
  input  logic [7:0] ipv4_protocol,
  input  logic [15:0] ipv4_hdr_chk,
  input  logic [31:0] ipv4_src,
  input  logic [31:0] ipv4_dst,
  input  logic [319:0] ipv4opt_options,
  input  logic [15:0] tcp_src_port,
  input  logic [15:0] tcp_dst_port,
  input  logic [31:0] tcp_seqNum,
  input  logic [31:0] tcp_ackNum,
  input  logic [3:0] tcp_dataOffset,
  input  logic [5:0] tcp_resv,
  input  logic [5:0] tcp_flags,
  input  logic [15:0] tcp_window,
  input  logic [15:0] tcp_checksum,
  input  logic [15:0] tcp_urgPtr,
  input  logic [319:0] tcpopt_options,
  input  logic [15:0] udp_src_port,
  input  logic [15:0] udp_dst_port,
  input  logic [15:0] udp_length,
  input  logic [15:0] udp_checksum,

  // Header valid flag outputs (may be modified by setValid/setInvalid)
  output logic        out_eth_valid,
  output logic        out_new_vlan_valid,
  output logic        out_vlan_valid,
  output logic        out_ipv4_valid,
  output logic        out_ipv4opt_valid,
  output logic        out_tcp_valid,
  output logic        out_tcpopt_valid,
  output logic        out_udp_valid,

  // Header field outputs (pass-through, optionally modified)
  output logic [47:0] out_eth_dmac,
  output logic [47:0] out_eth_smac,
  output logic [15:0] out_eth_type,
  output logic [2:0] out_new_vlan_pcp,
  output logic [0:0] out_new_vlan_cfi,
  output logic [11:0] out_new_vlan_vid,
  output logic [15:0] out_new_vlan_tpid,
  output logic [2:0] out_vlan_pcp,
  output logic [0:0] out_vlan_cfi,
  output logic [11:0] out_vlan_vid,
  output logic [15:0] out_vlan_tpid,
  output logic [3:0] out_ipv4_version,
  output logic [3:0] out_ipv4_hdr_len,
  output logic [7:0] out_ipv4_tos,
  output logic [15:0] out_ipv4_length,
  output logic [15:0] out_ipv4_id,
  output logic [2:0] out_ipv4_flags,
  output logic [12:0] out_ipv4_offset,
  output logic [7:0] out_ipv4_ttl,
  output logic [7:0] out_ipv4_protocol,
  output logic [15:0] out_ipv4_hdr_chk,
  output logic [31:0] out_ipv4_src,
  output logic [31:0] out_ipv4_dst,
  output logic [319:0] out_ipv4opt_options,
  output logic [15:0] out_tcp_src_port,
  output logic [15:0] out_tcp_dst_port,
  output logic [31:0] out_tcp_seqNum,
  output logic [31:0] out_tcp_ackNum,
  output logic [3:0] out_tcp_dataOffset,
  output logic [5:0] out_tcp_resv,
  output logic [5:0] out_tcp_flags,
  output logic [15:0] out_tcp_window,
  output logic [15:0] out_tcp_checksum,
  output logic [15:0] out_tcp_urgPtr,
  output logic [319:0] out_tcpopt_options,
  output logic [15:0] out_udp_src_port,
  output logic [15:0] out_udp_dst_port,
  output logic [15:0] out_udp_length,
  output logic [15:0] out_udp_checksum,

  // Control-plane write ports for table instances
  input  logic        FiveTuple_cp_wr_en,
  input  logic [12:0] FiveTuple_cp_wr_idx,
  input  logic [31:0] FiveTuple_cp_wr_key_src,
  input  logic [31:0] FiveTuple_cp_wr_key_dst,
  input  logic [7:0] FiveTuple_cp_wr_key_protocol,
  input  logic [15:0] FiveTuple_cp_wr_key_table_key_sport,
  input  logic [15:0] FiveTuple_cp_wr_key_table_key_dport,
  input  logic [0:0] FiveTuple_cp_wr_action,
  input  logic [12:0] FiveTuple_cp_wr_p_counter_index,
  input  logic [2:0] FiveTuple_cp_wr_p_pcp,
  input  logic [0:0] FiveTuple_cp_wr_p_cfi,
  input  logic [11:0] FiveTuple_cp_wr_p_vid,

  // Table hit outputs
  output logic        FiveTuple_hit_out,

  output logic        valid_out,
  output logic        drop
);

  logic [0:0] hit;
  logic [15:0] table_key_dport;
  logic [15:0] table_key_sport;

  // Pipeline-stage forwarding registers (one set per exact-match
  // table boundary in the chain)
  logic valid_s1;
  logic out_eth_valid_s1;
  logic eth_valid_s1;
  logic out_new_vlan_valid_s1;
  logic new_vlan_valid_s1;
  logic out_vlan_valid_s1;
  logic vlan_valid_s1;
  logic out_ipv4_valid_s1;
  logic ipv4_valid_s1;
  logic out_ipv4opt_valid_s1;
  logic ipv4opt_valid_s1;
  logic out_tcp_valid_s1;
  logic tcp_valid_s1;
  logic out_tcpopt_valid_s1;
  logic tcpopt_valid_s1;
  logic out_udp_valid_s1;
  logic udp_valid_s1;
  logic [47:0] out_eth_dmac_s1;
  logic [47:0] eth_dmac_s1;
  logic [47:0] out_eth_smac_s1;
  logic [47:0] eth_smac_s1;
  logic [15:0] out_eth_type_s1;
  logic [15:0] eth_type_s1;
  logic [2:0] out_new_vlan_pcp_s1;
  logic [2:0] new_vlan_pcp_s1;
  logic [0:0] out_new_vlan_cfi_s1;
  logic [0:0] new_vlan_cfi_s1;
  logic [11:0] out_new_vlan_vid_s1;
  logic [11:0] new_vlan_vid_s1;
  logic [15:0] out_new_vlan_tpid_s1;
  logic [15:0] new_vlan_tpid_s1;
  logic [2:0] out_vlan_pcp_s1;
  logic [2:0] vlan_pcp_s1;
  logic [0:0] out_vlan_cfi_s1;
  logic [0:0] vlan_cfi_s1;
  logic [11:0] out_vlan_vid_s1;
  logic [11:0] vlan_vid_s1;
  logic [15:0] out_vlan_tpid_s1;
  logic [15:0] vlan_tpid_s1;
  logic [3:0] out_ipv4_version_s1;
  logic [3:0] ipv4_version_s1;
  logic [3:0] out_ipv4_hdr_len_s1;
  logic [3:0] ipv4_hdr_len_s1;
  logic [7:0] out_ipv4_tos_s1;
  logic [7:0] ipv4_tos_s1;
  logic [15:0] out_ipv4_length_s1;
  logic [15:0] ipv4_length_s1;
  logic [15:0] out_ipv4_id_s1;
  logic [15:0] ipv4_id_s1;
  logic [2:0] out_ipv4_flags_s1;
  logic [2:0] ipv4_flags_s1;
  logic [12:0] out_ipv4_offset_s1;
  logic [12:0] ipv4_offset_s1;
  logic [7:0] out_ipv4_ttl_s1;
  logic [7:0] ipv4_ttl_s1;
  logic [7:0] out_ipv4_protocol_s1;
  logic [7:0] ipv4_protocol_s1;
  logic [15:0] out_ipv4_hdr_chk_s1;
  logic [15:0] ipv4_hdr_chk_s1;
  logic [31:0] out_ipv4_src_s1;
  logic [31:0] ipv4_src_s1;
  logic [31:0] out_ipv4_dst_s1;
  logic [31:0] ipv4_dst_s1;
  logic [319:0] out_ipv4opt_options_s1;
  logic [319:0] ipv4opt_options_s1;
  logic [15:0] out_tcp_src_port_s1;
  logic [15:0] tcp_src_port_s1;
  logic [15:0] out_tcp_dst_port_s1;
  logic [15:0] tcp_dst_port_s1;
  logic [31:0] out_tcp_seqNum_s1;
  logic [31:0] tcp_seqNum_s1;
  logic [31:0] out_tcp_ackNum_s1;
  logic [31:0] tcp_ackNum_s1;
  logic [3:0] out_tcp_dataOffset_s1;
  logic [3:0] tcp_dataOffset_s1;
  logic [5:0] out_tcp_resv_s1;
  logic [5:0] tcp_resv_s1;
  logic [5:0] out_tcp_flags_s1;
  logic [5:0] tcp_flags_s1;
  logic [15:0] out_tcp_window_s1;
  logic [15:0] tcp_window_s1;
  logic [15:0] out_tcp_checksum_s1;
  logic [15:0] tcp_checksum_s1;
  logic [15:0] out_tcp_urgPtr_s1;
  logic [15:0] tcp_urgPtr_s1;
  logic [319:0] out_tcpopt_options_s1;
  logic [319:0] tcpopt_options_s1;
  logic [15:0] out_udp_src_port_s1;
  logic [15:0] udp_src_port_s1;
  logic [15:0] out_udp_dst_port_s1;
  logic [15:0] udp_dst_port_s1;
  logic [15:0] out_udp_length_s1;
  logic [15:0] udp_length_s1;
  logic [15:0] out_udp_checksum_s1;
  logic [15:0] udp_checksum_s1;
  logic [0:0] hit_s1;
  logic [15:0] table_key_dport_s1;
  logic [15:0] table_key_sport_s1;
  logic drop_s1;
  logic __stage_cond_1_r;
  logic __stage_cond_0_r;

  // Pool-A (out_*/drop) working copies -- every stage except the
  // last, which drives the real output ports directly
  logic out_eth_valid__st0;
  logic out_new_vlan_valid__st0;
  logic out_vlan_valid__st0;
  logic out_ipv4_valid__st0;
  logic out_ipv4opt_valid__st0;
  logic out_tcp_valid__st0;
  logic out_tcpopt_valid__st0;
  logic out_udp_valid__st0;
  logic [47:0] out_eth_dmac__st0;
  logic [47:0] out_eth_smac__st0;
  logic [15:0] out_eth_type__st0;
  logic [2:0] out_new_vlan_pcp__st0;
  logic [0:0] out_new_vlan_cfi__st0;
  logic [11:0] out_new_vlan_vid__st0;
  logic [15:0] out_new_vlan_tpid__st0;
  logic [2:0] out_vlan_pcp__st0;
  logic [0:0] out_vlan_cfi__st0;
  logic [11:0] out_vlan_vid__st0;
  logic [15:0] out_vlan_tpid__st0;
  logic [3:0] out_ipv4_version__st0;
  logic [3:0] out_ipv4_hdr_len__st0;
  logic [7:0] out_ipv4_tos__st0;
  logic [15:0] out_ipv4_length__st0;
  logic [15:0] out_ipv4_id__st0;
  logic [2:0] out_ipv4_flags__st0;
  logic [12:0] out_ipv4_offset__st0;
  logic [7:0] out_ipv4_ttl__st0;
  logic [7:0] out_ipv4_protocol__st0;
  logic [15:0] out_ipv4_hdr_chk__st0;
  logic [31:0] out_ipv4_src__st0;
  logic [31:0] out_ipv4_dst__st0;
  logic [319:0] out_ipv4opt_options__st0;
  logic [15:0] out_tcp_src_port__st0;
  logic [15:0] out_tcp_dst_port__st0;
  logic [31:0] out_tcp_seqNum__st0;
  logic [31:0] out_tcp_ackNum__st0;
  logic [3:0] out_tcp_dataOffset__st0;
  logic [5:0] out_tcp_resv__st0;
  logic [5:0] out_tcp_flags__st0;
  logic [15:0] out_tcp_window__st0;
  logic [15:0] out_tcp_checksum__st0;
  logic [15:0] out_tcp_urgPtr__st0;
  logic [319:0] out_tcpopt_options__st0;
  logic [15:0] out_udp_src_port__st0;
  logic [15:0] out_udp_dst_port__st0;
  logic [15:0] out_udp_length__st0;
  logic [15:0] out_udp_checksum__st0;
  logic drop__st0;

  // Pool-B (locals/meta shadow/raw hdr+std_meta reads) working
  // copies -- every stage except the first, which reads live inputs
  logic [0:0] hit__st1;
  logic [15:0] table_key_dport__st1;
  logic [15:0] table_key_sport__st1;
  logic eth_valid__st1;
  logic new_vlan_valid__st1;
  logic vlan_valid__st1;
  logic ipv4_valid__st1;
  logic ipv4opt_valid__st1;
  logic tcp_valid__st1;
  logic tcpopt_valid__st1;
  logic udp_valid__st1;
  logic [47:0] eth_dmac__st1;
  logic [47:0] eth_smac__st1;
  logic [15:0] eth_type__st1;
  logic [2:0] new_vlan_pcp__st1;
  logic [0:0] new_vlan_cfi__st1;
  logic [11:0] new_vlan_vid__st1;
  logic [15:0] new_vlan_tpid__st1;
  logic [2:0] vlan_pcp__st1;
  logic [0:0] vlan_cfi__st1;
  logic [11:0] vlan_vid__st1;
  logic [15:0] vlan_tpid__st1;
  logic [3:0] ipv4_version__st1;
  logic [3:0] ipv4_hdr_len__st1;
  logic [7:0] ipv4_tos__st1;
  logic [15:0] ipv4_length__st1;
  logic [15:0] ipv4_id__st1;
  logic [2:0] ipv4_flags__st1;
  logic [12:0] ipv4_offset__st1;
  logic [7:0] ipv4_ttl__st1;
  logic [7:0] ipv4_protocol__st1;
  logic [15:0] ipv4_hdr_chk__st1;
  logic [31:0] ipv4_src__st1;
  logic [31:0] ipv4_dst__st1;
  logic [319:0] ipv4opt_options__st1;
  logic [15:0] tcp_src_port__st1;
  logic [15:0] tcp_dst_port__st1;
  logic [31:0] tcp_seqNum__st1;
  logic [31:0] tcp_ackNum__st1;
  logic [3:0] tcp_dataOffset__st1;
  logic [5:0] tcp_resv__st1;
  logic [5:0] tcp_flags__st1;
  logic [15:0] tcp_window__st1;
  logic [15:0] tcp_checksum__st1;
  logic [15:0] tcp_urgPtr__st1;
  logic [319:0] tcpopt_options__st1;
  logic [15:0] udp_src_port__st1;
  logic [15:0] udp_dst_port__st1;
  logic [15:0] udp_length__st1;
  logic [15:0] udp_checksum__st1;

  // Table lookup result wires
  logic        FiveTuple_hit;
  logic [0:0] FiveTuple_act_id;
  logic [12:0] FiveTuple_p_counter_index;
  logic [2:0] FiveTuple_p_pcp;
  logic [0:0] FiveTuple_p_cfi;
  logic [11:0] FiveTuple_p_vid;

  // Table module instantiations
  FiveTuple_table #(.DEPTH(8192)) u_FiveTuple (
    .clk    (clk),
    .rst_n  (rst_n),
    .lkp_src    (ipv4_src),
    .lkp_dst    (ipv4_dst),
    .lkp_protocol    (ipv4_protocol),
    .lkp_table_key_sport    (table_key_sport),
    .lkp_table_key_dport    (table_key_dport),
    .hit       (FiveTuple_hit),
    .action_id (FiveTuple_act_id),
    .p_counter_index  (FiveTuple_p_counter_index),
    .p_pcp  (FiveTuple_p_pcp),
    .p_cfi  (FiveTuple_p_cfi),
    .p_vid  (FiveTuple_p_vid),
    .cp_wr_en  (FiveTuple_cp_wr_en),
    .cp_wr_idx (FiveTuple_cp_wr_idx),
    .cp_wr_key_src (FiveTuple_cp_wr_key_src),
    .cp_wr_key_dst (FiveTuple_cp_wr_key_dst),
    .cp_wr_key_protocol (FiveTuple_cp_wr_key_protocol),
    .cp_wr_key_table_key_sport (FiveTuple_cp_wr_key_table_key_sport),
    .cp_wr_key_table_key_dport (FiveTuple_cp_wr_key_table_key_dport),
    .cp_wr_action (FiveTuple_cp_wr_action),
    .cp_wr_p_counter_index (FiveTuple_cp_wr_p_counter_index),
    .cp_wr_p_pcp (FiveTuple_cp_wr_p_pcp),
    .cp_wr_p_cfi (FiveTuple_cp_wr_p_cfi),
    .cp_wr_p_vid (FiveTuple_cp_wr_p_vid)
  );

  // Table hit outputs
  assign FiveTuple_hit_out = FiveTuple_hit;

  // ---- Pipeline stage 0 (combinational, feeds the first exact-match table boundary) ----
  always_comb begin
    drop__st0 = 0;
    hit = 1'b0;
    table_key_dport = 16'b0;
    table_key_sport = 16'b0;

    // Header valid flag pass-through defaults
    out_eth_valid__st0 = eth_valid;
    out_new_vlan_valid__st0 = new_vlan_valid;
    out_vlan_valid__st0 = vlan_valid;
    out_ipv4_valid__st0 = ipv4_valid;
    out_ipv4opt_valid__st0 = ipv4opt_valid;
    out_tcp_valid__st0 = tcp_valid;
    out_tcpopt_valid__st0 = tcpopt_valid;
    out_udp_valid__st0 = udp_valid;

    // Header field pass-through defaults
    out_eth_dmac__st0 = eth_dmac;
    out_eth_smac__st0 = eth_smac;
    out_eth_type__st0 = eth_type;
    out_new_vlan_pcp__st0 = new_vlan_pcp;
    out_new_vlan_cfi__st0 = new_vlan_cfi;
    out_new_vlan_vid__st0 = new_vlan_vid;
    out_new_vlan_tpid__st0 = new_vlan_tpid;
    out_vlan_pcp__st0 = vlan_pcp;
    out_vlan_cfi__st0 = vlan_cfi;
    out_vlan_vid__st0 = vlan_vid;
    out_vlan_tpid__st0 = vlan_tpid;
    out_ipv4_version__st0 = ipv4_version;
    out_ipv4_hdr_len__st0 = ipv4_hdr_len;
    out_ipv4_tos__st0 = ipv4_tos;
    out_ipv4_length__st0 = ipv4_length;
    out_ipv4_id__st0 = ipv4_id;
    out_ipv4_flags__st0 = ipv4_flags;
    out_ipv4_offset__st0 = ipv4_offset;
    out_ipv4_ttl__st0 = ipv4_ttl;
    out_ipv4_protocol__st0 = ipv4_protocol;
    out_ipv4_hdr_chk__st0 = ipv4_hdr_chk;
    out_ipv4_src__st0 = ipv4_src;
    out_ipv4_dst__st0 = ipv4_dst;
    out_ipv4opt_options__st0 = ipv4opt_options;
    out_tcp_src_port__st0 = tcp_src_port;
    out_tcp_dst_port__st0 = tcp_dst_port;
    out_tcp_seqNum__st0 = tcp_seqNum;
    out_tcp_ackNum__st0 = tcp_ackNum;
    out_tcp_dataOffset__st0 = tcp_dataOffset;
    out_tcp_resv__st0 = tcp_resv;
    out_tcp_flags__st0 = tcp_flags;
    out_tcp_window__st0 = tcp_window;
    out_tcp_checksum__st0 = tcp_checksum;
    out_tcp_urgPtr__st0 = tcp_urgPtr;
    out_tcpopt_options__st0 = tcpopt_options;
    out_udp_src_port__st0 = udp_src_port;
    out_udp_dst_port__st0 = udp_dst_port;
    out_udp_length__st0 = udp_length;
    out_udp_checksum__st0 = udp_checksum;

    // apply block (stage 0 of 1)
    hit = 1'b0;
    if (udp_valid) begin
      table_key_sport = udp_src_port;
      table_key_dport = udp_dst_port;
    end
    else begin
      if (tcp_valid) begin
        table_key_sport = tcp_src_port;
        table_key_dport = tcp_dst_port;
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
      hit_s1 <= hit;
      table_key_dport_s1 <= table_key_dport;
      table_key_sport_s1 <= table_key_sport;
      out_eth_valid_s1 <= out_eth_valid__st0;
      eth_valid_s1 <= eth_valid;
      out_new_vlan_valid_s1 <= out_new_vlan_valid__st0;
      new_vlan_valid_s1 <= new_vlan_valid;
      out_vlan_valid_s1 <= out_vlan_valid__st0;
      vlan_valid_s1 <= vlan_valid;
      out_ipv4_valid_s1 <= out_ipv4_valid__st0;
      ipv4_valid_s1 <= ipv4_valid;
      out_ipv4opt_valid_s1 <= out_ipv4opt_valid__st0;
      ipv4opt_valid_s1 <= ipv4opt_valid;
      out_tcp_valid_s1 <= out_tcp_valid__st0;
      tcp_valid_s1 <= tcp_valid;
      out_tcpopt_valid_s1 <= out_tcpopt_valid__st0;
      tcpopt_valid_s1 <= tcpopt_valid;
      out_udp_valid_s1 <= out_udp_valid__st0;
      udp_valid_s1 <= udp_valid;
      out_eth_dmac_s1 <= out_eth_dmac__st0;
      eth_dmac_s1 <= eth_dmac;
      out_eth_smac_s1 <= out_eth_smac__st0;
      eth_smac_s1 <= eth_smac;
      out_eth_type_s1 <= out_eth_type__st0;
      eth_type_s1 <= eth_type;
      out_new_vlan_pcp_s1 <= out_new_vlan_pcp__st0;
      new_vlan_pcp_s1 <= new_vlan_pcp;
      out_new_vlan_cfi_s1 <= out_new_vlan_cfi__st0;
      new_vlan_cfi_s1 <= new_vlan_cfi;
      out_new_vlan_vid_s1 <= out_new_vlan_vid__st0;
      new_vlan_vid_s1 <= new_vlan_vid;
      out_new_vlan_tpid_s1 <= out_new_vlan_tpid__st0;
      new_vlan_tpid_s1 <= new_vlan_tpid;
      out_vlan_pcp_s1 <= out_vlan_pcp__st0;
      vlan_pcp_s1 <= vlan_pcp;
      out_vlan_cfi_s1 <= out_vlan_cfi__st0;
      vlan_cfi_s1 <= vlan_cfi;
      out_vlan_vid_s1 <= out_vlan_vid__st0;
      vlan_vid_s1 <= vlan_vid;
      out_vlan_tpid_s1 <= out_vlan_tpid__st0;
      vlan_tpid_s1 <= vlan_tpid;
      out_ipv4_version_s1 <= out_ipv4_version__st0;
      ipv4_version_s1 <= ipv4_version;
      out_ipv4_hdr_len_s1 <= out_ipv4_hdr_len__st0;
      ipv4_hdr_len_s1 <= ipv4_hdr_len;
      out_ipv4_tos_s1 <= out_ipv4_tos__st0;
      ipv4_tos_s1 <= ipv4_tos;
      out_ipv4_length_s1 <= out_ipv4_length__st0;
      ipv4_length_s1 <= ipv4_length;
      out_ipv4_id_s1 <= out_ipv4_id__st0;
      ipv4_id_s1 <= ipv4_id;
      out_ipv4_flags_s1 <= out_ipv4_flags__st0;
      ipv4_flags_s1 <= ipv4_flags;
      out_ipv4_offset_s1 <= out_ipv4_offset__st0;
      ipv4_offset_s1 <= ipv4_offset;
      out_ipv4_ttl_s1 <= out_ipv4_ttl__st0;
      ipv4_ttl_s1 <= ipv4_ttl;
      out_ipv4_protocol_s1 <= out_ipv4_protocol__st0;
      ipv4_protocol_s1 <= ipv4_protocol;
      out_ipv4_hdr_chk_s1 <= out_ipv4_hdr_chk__st0;
      ipv4_hdr_chk_s1 <= ipv4_hdr_chk;
      out_ipv4_src_s1 <= out_ipv4_src__st0;
      ipv4_src_s1 <= ipv4_src;
      out_ipv4_dst_s1 <= out_ipv4_dst__st0;
      ipv4_dst_s1 <= ipv4_dst;
      out_ipv4opt_options_s1 <= out_ipv4opt_options__st0;
      ipv4opt_options_s1 <= ipv4opt_options;
      out_tcp_src_port_s1 <= out_tcp_src_port__st0;
      tcp_src_port_s1 <= tcp_src_port;
      out_tcp_dst_port_s1 <= out_tcp_dst_port__st0;
      tcp_dst_port_s1 <= tcp_dst_port;
      out_tcp_seqNum_s1 <= out_tcp_seqNum__st0;
      tcp_seqNum_s1 <= tcp_seqNum;
      out_tcp_ackNum_s1 <= out_tcp_ackNum__st0;
      tcp_ackNum_s1 <= tcp_ackNum;
      out_tcp_dataOffset_s1 <= out_tcp_dataOffset__st0;
      tcp_dataOffset_s1 <= tcp_dataOffset;
      out_tcp_resv_s1 <= out_tcp_resv__st0;
      tcp_resv_s1 <= tcp_resv;
      out_tcp_flags_s1 <= out_tcp_flags__st0;
      tcp_flags_s1 <= tcp_flags;
      out_tcp_window_s1 <= out_tcp_window__st0;
      tcp_window_s1 <= tcp_window;
      out_tcp_checksum_s1 <= out_tcp_checksum__st0;
      tcp_checksum_s1 <= tcp_checksum;
      out_tcp_urgPtr_s1 <= out_tcp_urgPtr__st0;
      tcp_urgPtr_s1 <= tcp_urgPtr;
      out_tcpopt_options_s1 <= out_tcpopt_options__st0;
      tcpopt_options_s1 <= tcpopt_options;
      out_udp_src_port_s1 <= out_udp_src_port__st0;
      udp_src_port_s1 <= udp_src_port;
      out_udp_dst_port_s1 <= out_udp_dst_port__st0;
      udp_dst_port_s1 <= udp_dst_port;
      out_udp_length_s1 <= out_udp_length__st0;
      udp_length_s1 <= udp_length;
      out_udp_checksum_s1 <= out_udp_checksum__st0;
      udp_checksum_s1 <= udp_checksum;
      __stage_cond_1_r <= (udp_valid);
      __stage_cond_0_r <= (tcp_valid);
    end
  end

  // ---- Pipeline stage 1 (registered 1 cycle(s) after stage 0) ----
  always_comb begin
    drop = drop_s1;
    hit__st1 = hit_s1;
    table_key_dport__st1 = table_key_dport_s1;
    table_key_sport__st1 = table_key_sport_s1;
    out_eth_valid = out_eth_valid_s1;
    eth_valid__st1 = eth_valid_s1;
    out_new_vlan_valid = out_new_vlan_valid_s1;
    new_vlan_valid__st1 = new_vlan_valid_s1;
    out_vlan_valid = out_vlan_valid_s1;
    vlan_valid__st1 = vlan_valid_s1;
    out_ipv4_valid = out_ipv4_valid_s1;
    ipv4_valid__st1 = ipv4_valid_s1;
    out_ipv4opt_valid = out_ipv4opt_valid_s1;
    ipv4opt_valid__st1 = ipv4opt_valid_s1;
    out_tcp_valid = out_tcp_valid_s1;
    tcp_valid__st1 = tcp_valid_s1;
    out_tcpopt_valid = out_tcpopt_valid_s1;
    tcpopt_valid__st1 = tcpopt_valid_s1;
    out_udp_valid = out_udp_valid_s1;
    udp_valid__st1 = udp_valid_s1;
    out_eth_dmac = out_eth_dmac_s1;
    eth_dmac__st1 = eth_dmac_s1;
    out_eth_smac = out_eth_smac_s1;
    eth_smac__st1 = eth_smac_s1;
    out_eth_type = out_eth_type_s1;
    eth_type__st1 = eth_type_s1;
    out_new_vlan_pcp = out_new_vlan_pcp_s1;
    new_vlan_pcp__st1 = new_vlan_pcp_s1;
    out_new_vlan_cfi = out_new_vlan_cfi_s1;
    new_vlan_cfi__st1 = new_vlan_cfi_s1;
    out_new_vlan_vid = out_new_vlan_vid_s1;
    new_vlan_vid__st1 = new_vlan_vid_s1;
    out_new_vlan_tpid = out_new_vlan_tpid_s1;
    new_vlan_tpid__st1 = new_vlan_tpid_s1;
    out_vlan_pcp = out_vlan_pcp_s1;
    vlan_pcp__st1 = vlan_pcp_s1;
    out_vlan_cfi = out_vlan_cfi_s1;
    vlan_cfi__st1 = vlan_cfi_s1;
    out_vlan_vid = out_vlan_vid_s1;
    vlan_vid__st1 = vlan_vid_s1;
    out_vlan_tpid = out_vlan_tpid_s1;
    vlan_tpid__st1 = vlan_tpid_s1;
    out_ipv4_version = out_ipv4_version_s1;
    ipv4_version__st1 = ipv4_version_s1;
    out_ipv4_hdr_len = out_ipv4_hdr_len_s1;
    ipv4_hdr_len__st1 = ipv4_hdr_len_s1;
    out_ipv4_tos = out_ipv4_tos_s1;
    ipv4_tos__st1 = ipv4_tos_s1;
    out_ipv4_length = out_ipv4_length_s1;
    ipv4_length__st1 = ipv4_length_s1;
    out_ipv4_id = out_ipv4_id_s1;
    ipv4_id__st1 = ipv4_id_s1;
    out_ipv4_flags = out_ipv4_flags_s1;
    ipv4_flags__st1 = ipv4_flags_s1;
    out_ipv4_offset = out_ipv4_offset_s1;
    ipv4_offset__st1 = ipv4_offset_s1;
    out_ipv4_ttl = out_ipv4_ttl_s1;
    ipv4_ttl__st1 = ipv4_ttl_s1;
    out_ipv4_protocol = out_ipv4_protocol_s1;
    ipv4_protocol__st1 = ipv4_protocol_s1;
    out_ipv4_hdr_chk = out_ipv4_hdr_chk_s1;
    ipv4_hdr_chk__st1 = ipv4_hdr_chk_s1;
    out_ipv4_src = out_ipv4_src_s1;
    ipv4_src__st1 = ipv4_src_s1;
    out_ipv4_dst = out_ipv4_dst_s1;
    ipv4_dst__st1 = ipv4_dst_s1;
    out_ipv4opt_options = out_ipv4opt_options_s1;
    ipv4opt_options__st1 = ipv4opt_options_s1;
    out_tcp_src_port = out_tcp_src_port_s1;
    tcp_src_port__st1 = tcp_src_port_s1;
    out_tcp_dst_port = out_tcp_dst_port_s1;
    tcp_dst_port__st1 = tcp_dst_port_s1;
    out_tcp_seqNum = out_tcp_seqNum_s1;
    tcp_seqNum__st1 = tcp_seqNum_s1;
    out_tcp_ackNum = out_tcp_ackNum_s1;
    tcp_ackNum__st1 = tcp_ackNum_s1;
    out_tcp_dataOffset = out_tcp_dataOffset_s1;
    tcp_dataOffset__st1 = tcp_dataOffset_s1;
    out_tcp_resv = out_tcp_resv_s1;
    tcp_resv__st1 = tcp_resv_s1;
    out_tcp_flags = out_tcp_flags_s1;
    tcp_flags__st1 = tcp_flags_s1;
    out_tcp_window = out_tcp_window_s1;
    tcp_window__st1 = tcp_window_s1;
    out_tcp_checksum = out_tcp_checksum_s1;
    tcp_checksum__st1 = tcp_checksum_s1;
    out_tcp_urgPtr = out_tcp_urgPtr_s1;
    tcp_urgPtr__st1 = tcp_urgPtr_s1;
    out_tcpopt_options = out_tcpopt_options_s1;
    tcpopt_options__st1 = tcpopt_options_s1;
    out_udp_src_port = out_udp_src_port_s1;
    udp_src_port__st1 = udp_src_port_s1;
    out_udp_dst_port = out_udp_dst_port_s1;
    udp_dst_port__st1 = udp_dst_port_s1;
    out_udp_length = out_udp_length_s1;
    udp_length__st1 = udp_length_s1;
    out_udp_checksum = out_udp_checksum_s1;
    udp_checksum__st1 = udp_checksum_s1;

    // apply block (stage 1 of 1)
    if (__stage_cond_1_r) begin
      if (FiveTuple_hit) begin
        // FiveTuple.apply()
        if (FiveTuple_hit) begin
          unique case (FiveTuple_act_id)
            1'd0: ; // NoAction
            1'd1: begin // InsertVLAN
              out_new_vlan_valid = 1'b1;
              out_new_vlan_pcp = FiveTuple_p_pcp;
              out_new_vlan_cfi = FiveTuple_p_cfi;
              out_new_vlan_vid = FiveTuple_p_vid;
              out_new_vlan_tpid = eth_type__st1;
              /* UNIMPLEMENTED EXTERN: PacketCounter.count(counter_index) */
              /* UNIMPLEMENTED EXTERN: ByteCounter.count(counter_index) */
            end
            default: ; // default = NoAction
          endcase
        end
        hit__st1 = 1'b1;
      end
      else begin
        hit__st1 = 1'b0;
      end
    end
    else begin
      if (__stage_cond_0_r) begin
        if (FiveTuple_hit) begin
          // FiveTuple.apply()
          if (FiveTuple_hit) begin
            unique case (FiveTuple_act_id)
              1'd0: ; // NoAction
              1'd1: begin // InsertVLAN
                out_new_vlan_valid = 1'b1;
                out_new_vlan_pcp = FiveTuple_p_pcp;
                out_new_vlan_cfi = FiveTuple_p_cfi;
                out_new_vlan_vid = FiveTuple_p_vid;
                out_new_vlan_tpid = eth_type__st1;
                /* UNIMPLEMENTED EXTERN: PacketCounter.count(counter_index) */
                /* UNIMPLEMENTED EXTERN: ByteCounter.count(counter_index) */
              end
              default: ; // default = NoAction
            endcase
          end
          hit__st1 = 1'b1;
        end
        else begin
          hit__st1 = 1'b0;
        end
      end
    end
    if (hit__st1) begin
      if (vlan_valid__st1) begin
        out_eth_type = 16'h88A8;
      end
      else begin
        out_eth_type = 16'h8100;
      end
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) valid_out <= 0;
    else        valid_out <= valid_s1;
  end

endmodule
