module processing_generated (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        valid_in,

  // Header valid flags
  input  logic        ethernet_valid,
  input  logic        ipv4_valid,
  input  logic        tcp_valid,
  input  logic        udp_valid,
  input  logic        mpls_0_valid,
  input  logic        mpls_1_valid,
  input  logic        mpls_2_valid,

  // Header field inputs
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
  input  logic [15:0] tcp_srcPort,
  input  logic [15:0] tcp_dstPort,
  input  logic [31:0] tcp_seqNo,
  input  logic [31:0] tcp_ackNo,
  input  logic [3:0] tcp_dataOffset,
  input  logic [3:0] tcp_reserved,
  input  logic [7:0] tcp_flags,
  input  logic [15:0] tcp_window,
  input  logic [15:0] tcp_checksum,
  input  logic [15:0] tcp_urgentPtr,
  input  logic [15:0] udp_srcPort,
  input  logic [15:0] udp_dstPort,
  input  logic [15:0] udp_length,
  input  logic [15:0] udp_checksum,
  input  logic [19:0] mpls_0_label,
  input  logic [2:0] mpls_0_tc,
  input  logic [0:0] mpls_0_bos,
  input  logic [7:0] mpls_0_ttl,
  input  logic [19:0] mpls_1_label,
  input  logic [2:0] mpls_1_tc,
  input  logic [0:0] mpls_1_bos,
  input  logic [7:0] mpls_1_ttl,
  input  logic [19:0] mpls_2_label,
  input  logic [2:0] mpls_2_tc,
  input  logic [0:0] mpls_2_bos,
  input  logic [7:0] mpls_2_ttl,

  // Metadata inputs
  input  logic [8:0] meta_ingress_port,
  input  logic [8:0] meta_egress_port,
  input  logic [31:0] meta_packet_length,
  input  logic [2:0] meta_priority,
  input  logic [15:0] meta_mcast_grp,
  input  logic [15:0] meta_egress_rid,
  input  logic [0:0] meta_checksum_error,
  input  logic [31:0] meta_enq_timestamp,
  input  logic [18:0] meta_enq_qdepth,
  input  logic [31:0] meta_deq_timedelta,
  input  logic [18:0] meta_deq_qdepth,
  input  logic [47:0] meta_ingress_global_timestamp,
  input  logic [47:0] meta_egress_global_timestamp,
  input  logic [7:0] meta_ttl,
  input  logic [31:0] meta_next_hop,
  input  logic [15:0] meta_mpls_label_swap,
  input  logic [0:0] meta_drop,
  input  logic [0:0] meta_ecmp_select,

  // Standard metadata inputs (table key sources)
  input  logic [8:0] std_meta_ingress_port,

  // Header valid flag outputs (may be modified by setValid/setInvalid)
  output logic        out_ethernet_valid,
  output logic        out_ipv4_valid,
  output logic        out_tcp_valid,
  output logic        out_udp_valid,
  output logic        out_mpls_0_valid,
  output logic        out_mpls_1_valid,
  output logic        out_mpls_2_valid,

  // Header field outputs (pass-through, optionally modified)
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
  output logic [15:0] out_tcp_srcPort,
  output logic [15:0] out_tcp_dstPort,
  output logic [31:0] out_tcp_seqNo,
  output logic [31:0] out_tcp_ackNo,
  output logic [3:0] out_tcp_dataOffset,
  output logic [3:0] out_tcp_reserved,
  output logic [7:0] out_tcp_flags,
  output logic [15:0] out_tcp_window,
  output logic [15:0] out_tcp_checksum,
  output logic [15:0] out_tcp_urgentPtr,
  output logic [15:0] out_udp_srcPort,
  output logic [15:0] out_udp_dstPort,
  output logic [15:0] out_udp_length,
  output logic [15:0] out_udp_checksum,
  output logic [19:0] out_mpls_0_label,
  output logic [2:0] out_mpls_0_tc,
  output logic [0:0] out_mpls_0_bos,
  output logic [7:0] out_mpls_0_ttl,
  output logic [19:0] out_mpls_1_label,
  output logic [2:0] out_mpls_1_tc,
  output logic [0:0] out_mpls_1_bos,
  output logic [7:0] out_mpls_1_ttl,
  output logic [19:0] out_mpls_2_label,
  output logic [2:0] out_mpls_2_tc,
  output logic [0:0] out_mpls_2_bos,
  output logic [7:0] out_mpls_2_ttl,

  // Standard metadata outputs
  output logic [8:0] out_std_meta_egress_port,

  // Metadata outputs (final value after the last stage)
  output logic [8:0] out_meta_ingress_port,
  output logic [8:0] out_meta_egress_port,
  output logic [31:0] out_meta_packet_length,
  output logic [2:0] out_meta_priority,
  output logic [15:0] out_meta_mcast_grp,
  output logic [15:0] out_meta_egress_rid,
  output logic [0:0] out_meta_checksum_error,
  output logic [31:0] out_meta_enq_timestamp,
  output logic [18:0] out_meta_enq_qdepth,
  output logic [31:0] out_meta_deq_timedelta,
  output logic [18:0] out_meta_deq_qdepth,
  output logic [47:0] out_meta_ingress_global_timestamp,
  output logic [47:0] out_meta_egress_global_timestamp,
  output logic [7:0] out_meta_ttl,
  output logic [31:0] out_meta_next_hop,
  output logic [15:0] out_meta_mpls_label_swap,
  output logic [0:0] out_meta_drop,
  output logic [0:0] out_meta_ecmp_select,

  // Control-plane write ports for table instances
  input  logic        port_policy_cp_wr_en,
  input  logic [5:0] port_policy_cp_wr_idx,
  input  logic [8:0] port_policy_cp_wr_key_ingress_port,
  input  logic [0:0] port_policy_cp_wr_action,
  input  logic [8:0] port_policy_cp_wr_p_egress_port,
  input  logic        mpls_swap_cp_wr_en,
  input  logic [8:0] mpls_swap_cp_wr_idx,
  input  logic [19:0] mpls_swap_cp_wr_key_key_0,
  input  logic [1:0] mpls_swap_cp_wr_action,
  input  logic [19:0] mpls_swap_cp_wr_p_new_label,
  input  logic [19:0] mpls_swap_cp_wr_p_label,
  input  logic        qos_policy_cp_wr_en,
  input  logic [7:0] qos_policy_cp_wr_idx,
  input  logic [7:0] qos_policy_cp_wr_key_diffserv,
  input  logic [7:0] qos_policy_cp_wr_key_flags,
  input  logic [7:0] qos_policy_cp_wr_mask_diffserv,
  input  logic [7:0] qos_policy_cp_wr_mask_flags,
  input  logic [0:0] qos_policy_cp_wr_action,
  input  logic [2:0] qos_policy_cp_wr_p_prio,
  input  logic        ipv4_route_cp_wr_en,
  input  logic [9:0] ipv4_route_cp_wr_idx,
  input  logic [31:0] ipv4_route_cp_wr_key_dstAddr,
  input  logic [5:0] ipv4_route_cp_wr_pfx_len,
  input  logic [1:0] ipv4_route_cp_wr_action,
  input  logic [31:0] ipv4_route_cp_wr_p_next_hop,
  input  logic        ecmp_group_cp_wr_en,
  input  logic [0:0] ecmp_group_cp_wr_action,

  // Table hit outputs
  output logic        port_policy_hit_out,
  output logic        mpls_swap_hit_out,
  output logic        qos_policy_hit_out,
  output logic        ipv4_route_hit_out,
  output logic        ecmp_group_hit_out,

  output logic        valid_out,
  output logic        drop
);

  logic [5:0] _padding_0;
  logic [19:0] key_0;
  logic [31:0] tmp;
  logic [31:0] tmp_0;
  logic [31:0] tmp_1;

  // Metadata shadow locals (writable copies of metadata inputs)
  logic [8:0] meta_ingress_port_w;
  logic [8:0] meta_egress_port_w;
  logic [31:0] meta_packet_length_w;
  logic [2:0] meta_priority_w;
  logic [15:0] meta_mcast_grp_w;
  logic [15:0] meta_egress_rid_w;
  logic [0:0] meta_checksum_error_w;
  logic [31:0] meta_enq_timestamp_w;
  logic [18:0] meta_enq_qdepth_w;
  logic [31:0] meta_deq_timedelta_w;
  logic [18:0] meta_deq_qdepth_w;
  logic [47:0] meta_ingress_global_timestamp_w;
  logic [47:0] meta_egress_global_timestamp_w;
  logic [7:0] meta_ttl_w;
  logic [31:0] meta_next_hop_w;
  logic [15:0] meta_mpls_label_swap_w;
  logic [0:0] meta_drop_w;
  logic [0:0] meta_ecmp_select_w;

  // Pipeline-stage forwarding registers (one set per exact-match
  // table boundary in the chain)
  logic valid_s1;
  logic out_ethernet_valid_s1;
  logic ethernet_valid_s1;
  logic out_ipv4_valid_s1;
  logic ipv4_valid_s1;
  logic out_tcp_valid_s1;
  logic tcp_valid_s1;
  logic out_udp_valid_s1;
  logic udp_valid_s1;
  logic out_mpls_0_valid_s1;
  logic mpls_0_valid_s1;
  logic out_mpls_1_valid_s1;
  logic mpls_1_valid_s1;
  logic out_mpls_2_valid_s1;
  logic mpls_2_valid_s1;
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
  logic [15:0] out_tcp_srcPort_s1;
  logic [15:0] tcp_srcPort_s1;
  logic [15:0] out_tcp_dstPort_s1;
  logic [15:0] tcp_dstPort_s1;
  logic [31:0] out_tcp_seqNo_s1;
  logic [31:0] tcp_seqNo_s1;
  logic [31:0] out_tcp_ackNo_s1;
  logic [31:0] tcp_ackNo_s1;
  logic [3:0] out_tcp_dataOffset_s1;
  logic [3:0] tcp_dataOffset_s1;
  logic [3:0] out_tcp_reserved_s1;
  logic [3:0] tcp_reserved_s1;
  logic [7:0] out_tcp_flags_s1;
  logic [7:0] tcp_flags_s1;
  logic [15:0] out_tcp_window_s1;
  logic [15:0] tcp_window_s1;
  logic [15:0] out_tcp_checksum_s1;
  logic [15:0] tcp_checksum_s1;
  logic [15:0] out_tcp_urgentPtr_s1;
  logic [15:0] tcp_urgentPtr_s1;
  logic [15:0] out_udp_srcPort_s1;
  logic [15:0] udp_srcPort_s1;
  logic [15:0] out_udp_dstPort_s1;
  logic [15:0] udp_dstPort_s1;
  logic [15:0] out_udp_length_s1;
  logic [15:0] udp_length_s1;
  logic [15:0] out_udp_checksum_s1;
  logic [15:0] udp_checksum_s1;
  logic [19:0] out_mpls_0_label_s1;
  logic [19:0] mpls_0_label_s1;
  logic [2:0] out_mpls_0_tc_s1;
  logic [2:0] mpls_0_tc_s1;
  logic [0:0] out_mpls_0_bos_s1;
  logic [0:0] mpls_0_bos_s1;
  logic [7:0] out_mpls_0_ttl_s1;
  logic [7:0] mpls_0_ttl_s1;
  logic [19:0] out_mpls_1_label_s1;
  logic [19:0] mpls_1_label_s1;
  logic [2:0] out_mpls_1_tc_s1;
  logic [2:0] mpls_1_tc_s1;
  logic [0:0] out_mpls_1_bos_s1;
  logic [0:0] mpls_1_bos_s1;
  logic [7:0] out_mpls_1_ttl_s1;
  logic [7:0] mpls_1_ttl_s1;
  logic [19:0] out_mpls_2_label_s1;
  logic [19:0] mpls_2_label_s1;
  logic [2:0] out_mpls_2_tc_s1;
  logic [2:0] mpls_2_tc_s1;
  logic [0:0] out_mpls_2_bos_s1;
  logic [0:0] mpls_2_bos_s1;
  logic [7:0] out_mpls_2_ttl_s1;
  logic [7:0] mpls_2_ttl_s1;
  logic [8:0] meta_ingress_port_w_s1;
  logic [8:0] meta_egress_port_w_s1;
  logic [31:0] meta_packet_length_w_s1;
  logic [2:0] meta_priority_w_s1;
  logic [15:0] meta_mcast_grp_w_s1;
  logic [15:0] meta_egress_rid_w_s1;
  logic [0:0] meta_checksum_error_w_s1;
  logic [31:0] meta_enq_timestamp_w_s1;
  logic [18:0] meta_enq_qdepth_w_s1;
  logic [31:0] meta_deq_timedelta_w_s1;
  logic [18:0] meta_deq_qdepth_w_s1;
  logic [47:0] meta_ingress_global_timestamp_w_s1;
  logic [47:0] meta_egress_global_timestamp_w_s1;
  logic [7:0] meta_ttl_w_s1;
  logic [31:0] meta_next_hop_w_s1;
  logic [15:0] meta_mpls_label_swap_w_s1;
  logic [0:0] meta_drop_w_s1;
  logic [0:0] meta_ecmp_select_w_s1;
  logic [5:0] _padding_0_s1;
  logic [19:0] key_0_s1;
  logic [31:0] tmp_s1;
  logic [31:0] tmp_0_s1;
  logic [31:0] tmp_1_s1;
  logic [8:0] out_std_meta_egress_port_s1;
  logic [8:0] std_meta_ingress_port_s1;
  logic drop_s1;
  logic valid_s2;
  logic out_ethernet_valid_s2;
  logic ethernet_valid_s2;
  logic out_ipv4_valid_s2;
  logic ipv4_valid_s2;
  logic out_tcp_valid_s2;
  logic tcp_valid_s2;
  logic out_udp_valid_s2;
  logic udp_valid_s2;
  logic out_mpls_0_valid_s2;
  logic mpls_0_valid_s2;
  logic out_mpls_1_valid_s2;
  logic mpls_1_valid_s2;
  logic out_mpls_2_valid_s2;
  logic mpls_2_valid_s2;
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
  logic [15:0] out_tcp_srcPort_s2;
  logic [15:0] tcp_srcPort_s2;
  logic [15:0] out_tcp_dstPort_s2;
  logic [15:0] tcp_dstPort_s2;
  logic [31:0] out_tcp_seqNo_s2;
  logic [31:0] tcp_seqNo_s2;
  logic [31:0] out_tcp_ackNo_s2;
  logic [31:0] tcp_ackNo_s2;
  logic [3:0] out_tcp_dataOffset_s2;
  logic [3:0] tcp_dataOffset_s2;
  logic [3:0] out_tcp_reserved_s2;
  logic [3:0] tcp_reserved_s2;
  logic [7:0] out_tcp_flags_s2;
  logic [7:0] tcp_flags_s2;
  logic [15:0] out_tcp_window_s2;
  logic [15:0] tcp_window_s2;
  logic [15:0] out_tcp_checksum_s2;
  logic [15:0] tcp_checksum_s2;
  logic [15:0] out_tcp_urgentPtr_s2;
  logic [15:0] tcp_urgentPtr_s2;
  logic [15:0] out_udp_srcPort_s2;
  logic [15:0] udp_srcPort_s2;
  logic [15:0] out_udp_dstPort_s2;
  logic [15:0] udp_dstPort_s2;
  logic [15:0] out_udp_length_s2;
  logic [15:0] udp_length_s2;
  logic [15:0] out_udp_checksum_s2;
  logic [15:0] udp_checksum_s2;
  logic [19:0] out_mpls_0_label_s2;
  logic [19:0] mpls_0_label_s2;
  logic [2:0] out_mpls_0_tc_s2;
  logic [2:0] mpls_0_tc_s2;
  logic [0:0] out_mpls_0_bos_s2;
  logic [0:0] mpls_0_bos_s2;
  logic [7:0] out_mpls_0_ttl_s2;
  logic [7:0] mpls_0_ttl_s2;
  logic [19:0] out_mpls_1_label_s2;
  logic [19:0] mpls_1_label_s2;
  logic [2:0] out_mpls_1_tc_s2;
  logic [2:0] mpls_1_tc_s2;
  logic [0:0] out_mpls_1_bos_s2;
  logic [0:0] mpls_1_bos_s2;
  logic [7:0] out_mpls_1_ttl_s2;
  logic [7:0] mpls_1_ttl_s2;
  logic [19:0] out_mpls_2_label_s2;
  logic [19:0] mpls_2_label_s2;
  logic [2:0] out_mpls_2_tc_s2;
  logic [2:0] mpls_2_tc_s2;
  logic [0:0] out_mpls_2_bos_s2;
  logic [0:0] mpls_2_bos_s2;
  logic [7:0] out_mpls_2_ttl_s2;
  logic [7:0] mpls_2_ttl_s2;
  logic [8:0] meta_ingress_port_w_s2;
  logic [8:0] meta_egress_port_w_s2;
  logic [31:0] meta_packet_length_w_s2;
  logic [2:0] meta_priority_w_s2;
  logic [15:0] meta_mcast_grp_w_s2;
  logic [15:0] meta_egress_rid_w_s2;
  logic [0:0] meta_checksum_error_w_s2;
  logic [31:0] meta_enq_timestamp_w_s2;
  logic [18:0] meta_enq_qdepth_w_s2;
  logic [31:0] meta_deq_timedelta_w_s2;
  logic [18:0] meta_deq_qdepth_w_s2;
  logic [47:0] meta_ingress_global_timestamp_w_s2;
  logic [47:0] meta_egress_global_timestamp_w_s2;
  logic [7:0] meta_ttl_w_s2;
  logic [31:0] meta_next_hop_w_s2;
  logic [15:0] meta_mpls_label_swap_w_s2;
  logic [0:0] meta_drop_w_s2;
  logic [0:0] meta_ecmp_select_w_s2;
  logic [5:0] _padding_0_s2;
  logic [19:0] key_0_s2;
  logic [31:0] tmp_s2;
  logic [31:0] tmp_0_s2;
  logic [31:0] tmp_1_s2;
  logic [8:0] out_std_meta_egress_port_s2;
  logic [8:0] std_meta_ingress_port_s2;
  logic drop_s2;
  logic valid_s3;
  logic out_ethernet_valid_s3;
  logic ethernet_valid_s3;
  logic out_ipv4_valid_s3;
  logic ipv4_valid_s3;
  logic out_tcp_valid_s3;
  logic tcp_valid_s3;
  logic out_udp_valid_s3;
  logic udp_valid_s3;
  logic out_mpls_0_valid_s3;
  logic mpls_0_valid_s3;
  logic out_mpls_1_valid_s3;
  logic mpls_1_valid_s3;
  logic out_mpls_2_valid_s3;
  logic mpls_2_valid_s3;
  logic [47:0] out_ethernet_dstAddr_s3;
  logic [47:0] ethernet_dstAddr_s3;
  logic [47:0] out_ethernet_srcAddr_s3;
  logic [47:0] ethernet_srcAddr_s3;
  logic [15:0] out_ethernet_etherType_s3;
  logic [15:0] ethernet_etherType_s3;
  logic [3:0] out_ipv4_version_s3;
  logic [3:0] ipv4_version_s3;
  logic [3:0] out_ipv4_ihl_s3;
  logic [3:0] ipv4_ihl_s3;
  logic [7:0] out_ipv4_diffserv_s3;
  logic [7:0] ipv4_diffserv_s3;
  logic [15:0] out_ipv4_totalLen_s3;
  logic [15:0] ipv4_totalLen_s3;
  logic [15:0] out_ipv4_identification_s3;
  logic [15:0] ipv4_identification_s3;
  logic [2:0] out_ipv4_flags_s3;
  logic [2:0] ipv4_flags_s3;
  logic [12:0] out_ipv4_fragOffset_s3;
  logic [12:0] ipv4_fragOffset_s3;
  logic [7:0] out_ipv4_ttl_s3;
  logic [7:0] ipv4_ttl_s3;
  logic [7:0] out_ipv4_protocol_s3;
  logic [7:0] ipv4_protocol_s3;
  logic [15:0] out_ipv4_hdrChecksum_s3;
  logic [15:0] ipv4_hdrChecksum_s3;
  logic [31:0] out_ipv4_srcAddr_s3;
  logic [31:0] ipv4_srcAddr_s3;
  logic [31:0] out_ipv4_dstAddr_s3;
  logic [31:0] ipv4_dstAddr_s3;
  logic [15:0] out_tcp_srcPort_s3;
  logic [15:0] tcp_srcPort_s3;
  logic [15:0] out_tcp_dstPort_s3;
  logic [15:0] tcp_dstPort_s3;
  logic [31:0] out_tcp_seqNo_s3;
  logic [31:0] tcp_seqNo_s3;
  logic [31:0] out_tcp_ackNo_s3;
  logic [31:0] tcp_ackNo_s3;
  logic [3:0] out_tcp_dataOffset_s3;
  logic [3:0] tcp_dataOffset_s3;
  logic [3:0] out_tcp_reserved_s3;
  logic [3:0] tcp_reserved_s3;
  logic [7:0] out_tcp_flags_s3;
  logic [7:0] tcp_flags_s3;
  logic [15:0] out_tcp_window_s3;
  logic [15:0] tcp_window_s3;
  logic [15:0] out_tcp_checksum_s3;
  logic [15:0] tcp_checksum_s3;
  logic [15:0] out_tcp_urgentPtr_s3;
  logic [15:0] tcp_urgentPtr_s3;
  logic [15:0] out_udp_srcPort_s3;
  logic [15:0] udp_srcPort_s3;
  logic [15:0] out_udp_dstPort_s3;
  logic [15:0] udp_dstPort_s3;
  logic [15:0] out_udp_length_s3;
  logic [15:0] udp_length_s3;
  logic [15:0] out_udp_checksum_s3;
  logic [15:0] udp_checksum_s3;
  logic [19:0] out_mpls_0_label_s3;
  logic [19:0] mpls_0_label_s3;
  logic [2:0] out_mpls_0_tc_s3;
  logic [2:0] mpls_0_tc_s3;
  logic [0:0] out_mpls_0_bos_s3;
  logic [0:0] mpls_0_bos_s3;
  logic [7:0] out_mpls_0_ttl_s3;
  logic [7:0] mpls_0_ttl_s3;
  logic [19:0] out_mpls_1_label_s3;
  logic [19:0] mpls_1_label_s3;
  logic [2:0] out_mpls_1_tc_s3;
  logic [2:0] mpls_1_tc_s3;
  logic [0:0] out_mpls_1_bos_s3;
  logic [0:0] mpls_1_bos_s3;
  logic [7:0] out_mpls_1_ttl_s3;
  logic [7:0] mpls_1_ttl_s3;
  logic [19:0] out_mpls_2_label_s3;
  logic [19:0] mpls_2_label_s3;
  logic [2:0] out_mpls_2_tc_s3;
  logic [2:0] mpls_2_tc_s3;
  logic [0:0] out_mpls_2_bos_s3;
  logic [0:0] mpls_2_bos_s3;
  logic [7:0] out_mpls_2_ttl_s3;
  logic [7:0] mpls_2_ttl_s3;
  logic [8:0] meta_ingress_port_w_s3;
  logic [8:0] meta_egress_port_w_s3;
  logic [31:0] meta_packet_length_w_s3;
  logic [2:0] meta_priority_w_s3;
  logic [15:0] meta_mcast_grp_w_s3;
  logic [15:0] meta_egress_rid_w_s3;
  logic [0:0] meta_checksum_error_w_s3;
  logic [31:0] meta_enq_timestamp_w_s3;
  logic [18:0] meta_enq_qdepth_w_s3;
  logic [31:0] meta_deq_timedelta_w_s3;
  logic [18:0] meta_deq_qdepth_w_s3;
  logic [47:0] meta_ingress_global_timestamp_w_s3;
  logic [47:0] meta_egress_global_timestamp_w_s3;
  logic [7:0] meta_ttl_w_s3;
  logic [31:0] meta_next_hop_w_s3;
  logic [15:0] meta_mpls_label_swap_w_s3;
  logic [0:0] meta_drop_w_s3;
  logic [0:0] meta_ecmp_select_w_s3;
  logic [5:0] _padding_0_s3;
  logic [19:0] key_0_s3;
  logic [31:0] tmp_s3;
  logic [31:0] tmp_0_s3;
  logic [31:0] tmp_1_s3;
  logic [8:0] out_std_meta_egress_port_s3;
  logic [8:0] std_meta_ingress_port_s3;
  logic drop_s3;
  logic __stage_cond_0_r;
  logic valid_s4;
  logic out_ethernet_valid_s4;
  logic ethernet_valid_s4;
  logic out_ipv4_valid_s4;
  logic ipv4_valid_s4;
  logic out_tcp_valid_s4;
  logic tcp_valid_s4;
  logic out_udp_valid_s4;
  logic udp_valid_s4;
  logic out_mpls_0_valid_s4;
  logic mpls_0_valid_s4;
  logic out_mpls_1_valid_s4;
  logic mpls_1_valid_s4;
  logic out_mpls_2_valid_s4;
  logic mpls_2_valid_s4;
  logic [47:0] out_ethernet_dstAddr_s4;
  logic [47:0] ethernet_dstAddr_s4;
  logic [47:0] out_ethernet_srcAddr_s4;
  logic [47:0] ethernet_srcAddr_s4;
  logic [15:0] out_ethernet_etherType_s4;
  logic [15:0] ethernet_etherType_s4;
  logic [3:0] out_ipv4_version_s4;
  logic [3:0] ipv4_version_s4;
  logic [3:0] out_ipv4_ihl_s4;
  logic [3:0] ipv4_ihl_s4;
  logic [7:0] out_ipv4_diffserv_s4;
  logic [7:0] ipv4_diffserv_s4;
  logic [15:0] out_ipv4_totalLen_s4;
  logic [15:0] ipv4_totalLen_s4;
  logic [15:0] out_ipv4_identification_s4;
  logic [15:0] ipv4_identification_s4;
  logic [2:0] out_ipv4_flags_s4;
  logic [2:0] ipv4_flags_s4;
  logic [12:0] out_ipv4_fragOffset_s4;
  logic [12:0] ipv4_fragOffset_s4;
  logic [7:0] out_ipv4_ttl_s4;
  logic [7:0] ipv4_ttl_s4;
  logic [7:0] out_ipv4_protocol_s4;
  logic [7:0] ipv4_protocol_s4;
  logic [15:0] out_ipv4_hdrChecksum_s4;
  logic [15:0] ipv4_hdrChecksum_s4;
  logic [31:0] out_ipv4_srcAddr_s4;
  logic [31:0] ipv4_srcAddr_s4;
  logic [31:0] out_ipv4_dstAddr_s4;
  logic [31:0] ipv4_dstAddr_s4;
  logic [15:0] out_tcp_srcPort_s4;
  logic [15:0] tcp_srcPort_s4;
  logic [15:0] out_tcp_dstPort_s4;
  logic [15:0] tcp_dstPort_s4;
  logic [31:0] out_tcp_seqNo_s4;
  logic [31:0] tcp_seqNo_s4;
  logic [31:0] out_tcp_ackNo_s4;
  logic [31:0] tcp_ackNo_s4;
  logic [3:0] out_tcp_dataOffset_s4;
  logic [3:0] tcp_dataOffset_s4;
  logic [3:0] out_tcp_reserved_s4;
  logic [3:0] tcp_reserved_s4;
  logic [7:0] out_tcp_flags_s4;
  logic [7:0] tcp_flags_s4;
  logic [15:0] out_tcp_window_s4;
  logic [15:0] tcp_window_s4;
  logic [15:0] out_tcp_checksum_s4;
  logic [15:0] tcp_checksum_s4;
  logic [15:0] out_tcp_urgentPtr_s4;
  logic [15:0] tcp_urgentPtr_s4;
  logic [15:0] out_udp_srcPort_s4;
  logic [15:0] udp_srcPort_s4;
  logic [15:0] out_udp_dstPort_s4;
  logic [15:0] udp_dstPort_s4;
  logic [15:0] out_udp_length_s4;
  logic [15:0] udp_length_s4;
  logic [15:0] out_udp_checksum_s4;
  logic [15:0] udp_checksum_s4;
  logic [19:0] out_mpls_0_label_s4;
  logic [19:0] mpls_0_label_s4;
  logic [2:0] out_mpls_0_tc_s4;
  logic [2:0] mpls_0_tc_s4;
  logic [0:0] out_mpls_0_bos_s4;
  logic [0:0] mpls_0_bos_s4;
  logic [7:0] out_mpls_0_ttl_s4;
  logic [7:0] mpls_0_ttl_s4;
  logic [19:0] out_mpls_1_label_s4;
  logic [19:0] mpls_1_label_s4;
  logic [2:0] out_mpls_1_tc_s4;
  logic [2:0] mpls_1_tc_s4;
  logic [0:0] out_mpls_1_bos_s4;
  logic [0:0] mpls_1_bos_s4;
  logic [7:0] out_mpls_1_ttl_s4;
  logic [7:0] mpls_1_ttl_s4;
  logic [19:0] out_mpls_2_label_s4;
  logic [19:0] mpls_2_label_s4;
  logic [2:0] out_mpls_2_tc_s4;
  logic [2:0] mpls_2_tc_s4;
  logic [0:0] out_mpls_2_bos_s4;
  logic [0:0] mpls_2_bos_s4;
  logic [7:0] out_mpls_2_ttl_s4;
  logic [7:0] mpls_2_ttl_s4;
  logic [8:0] meta_ingress_port_w_s4;
  logic [8:0] meta_egress_port_w_s4;
  logic [31:0] meta_packet_length_w_s4;
  logic [2:0] meta_priority_w_s4;
  logic [15:0] meta_mcast_grp_w_s4;
  logic [15:0] meta_egress_rid_w_s4;
  logic [0:0] meta_checksum_error_w_s4;
  logic [31:0] meta_enq_timestamp_w_s4;
  logic [18:0] meta_enq_qdepth_w_s4;
  logic [31:0] meta_deq_timedelta_w_s4;
  logic [18:0] meta_deq_qdepth_w_s4;
  logic [47:0] meta_ingress_global_timestamp_w_s4;
  logic [47:0] meta_egress_global_timestamp_w_s4;
  logic [7:0] meta_ttl_w_s4;
  logic [31:0] meta_next_hop_w_s4;
  logic [15:0] meta_mpls_label_swap_w_s4;
  logic [0:0] meta_drop_w_s4;
  logic [0:0] meta_ecmp_select_w_s4;
  logic [5:0] _padding_0_s4;
  logic [19:0] key_0_s4;
  logic [31:0] tmp_s4;
  logic [31:0] tmp_0_s4;
  logic [31:0] tmp_1_s4;
  logic [8:0] out_std_meta_egress_port_s4;
  logic [8:0] std_meta_ingress_port_s4;
  logic drop_s4;
  logic valid_s5;
  logic out_ethernet_valid_s5;
  logic ethernet_valid_s5;
  logic out_ipv4_valid_s5;
  logic ipv4_valid_s5;
  logic out_tcp_valid_s5;
  logic tcp_valid_s5;
  logic out_udp_valid_s5;
  logic udp_valid_s5;
  logic out_mpls_0_valid_s5;
  logic mpls_0_valid_s5;
  logic out_mpls_1_valid_s5;
  logic mpls_1_valid_s5;
  logic out_mpls_2_valid_s5;
  logic mpls_2_valid_s5;
  logic [47:0] out_ethernet_dstAddr_s5;
  logic [47:0] ethernet_dstAddr_s5;
  logic [47:0] out_ethernet_srcAddr_s5;
  logic [47:0] ethernet_srcAddr_s5;
  logic [15:0] out_ethernet_etherType_s5;
  logic [15:0] ethernet_etherType_s5;
  logic [3:0] out_ipv4_version_s5;
  logic [3:0] ipv4_version_s5;
  logic [3:0] out_ipv4_ihl_s5;
  logic [3:0] ipv4_ihl_s5;
  logic [7:0] out_ipv4_diffserv_s5;
  logic [7:0] ipv4_diffserv_s5;
  logic [15:0] out_ipv4_totalLen_s5;
  logic [15:0] ipv4_totalLen_s5;
  logic [15:0] out_ipv4_identification_s5;
  logic [15:0] ipv4_identification_s5;
  logic [2:0] out_ipv4_flags_s5;
  logic [2:0] ipv4_flags_s5;
  logic [12:0] out_ipv4_fragOffset_s5;
  logic [12:0] ipv4_fragOffset_s5;
  logic [7:0] out_ipv4_ttl_s5;
  logic [7:0] ipv4_ttl_s5;
  logic [7:0] out_ipv4_protocol_s5;
  logic [7:0] ipv4_protocol_s5;
  logic [15:0] out_ipv4_hdrChecksum_s5;
  logic [15:0] ipv4_hdrChecksum_s5;
  logic [31:0] out_ipv4_srcAddr_s5;
  logic [31:0] ipv4_srcAddr_s5;
  logic [31:0] out_ipv4_dstAddr_s5;
  logic [31:0] ipv4_dstAddr_s5;
  logic [15:0] out_tcp_srcPort_s5;
  logic [15:0] tcp_srcPort_s5;
  logic [15:0] out_tcp_dstPort_s5;
  logic [15:0] tcp_dstPort_s5;
  logic [31:0] out_tcp_seqNo_s5;
  logic [31:0] tcp_seqNo_s5;
  logic [31:0] out_tcp_ackNo_s5;
  logic [31:0] tcp_ackNo_s5;
  logic [3:0] out_tcp_dataOffset_s5;
  logic [3:0] tcp_dataOffset_s5;
  logic [3:0] out_tcp_reserved_s5;
  logic [3:0] tcp_reserved_s5;
  logic [7:0] out_tcp_flags_s5;
  logic [7:0] tcp_flags_s5;
  logic [15:0] out_tcp_window_s5;
  logic [15:0] tcp_window_s5;
  logic [15:0] out_tcp_checksum_s5;
  logic [15:0] tcp_checksum_s5;
  logic [15:0] out_tcp_urgentPtr_s5;
  logic [15:0] tcp_urgentPtr_s5;
  logic [15:0] out_udp_srcPort_s5;
  logic [15:0] udp_srcPort_s5;
  logic [15:0] out_udp_dstPort_s5;
  logic [15:0] udp_dstPort_s5;
  logic [15:0] out_udp_length_s5;
  logic [15:0] udp_length_s5;
  logic [15:0] out_udp_checksum_s5;
  logic [15:0] udp_checksum_s5;
  logic [19:0] out_mpls_0_label_s5;
  logic [19:0] mpls_0_label_s5;
  logic [2:0] out_mpls_0_tc_s5;
  logic [2:0] mpls_0_tc_s5;
  logic [0:0] out_mpls_0_bos_s5;
  logic [0:0] mpls_0_bos_s5;
  logic [7:0] out_mpls_0_ttl_s5;
  logic [7:0] mpls_0_ttl_s5;
  logic [19:0] out_mpls_1_label_s5;
  logic [19:0] mpls_1_label_s5;
  logic [2:0] out_mpls_1_tc_s5;
  logic [2:0] mpls_1_tc_s5;
  logic [0:0] out_mpls_1_bos_s5;
  logic [0:0] mpls_1_bos_s5;
  logic [7:0] out_mpls_1_ttl_s5;
  logic [7:0] mpls_1_ttl_s5;
  logic [19:0] out_mpls_2_label_s5;
  logic [19:0] mpls_2_label_s5;
  logic [2:0] out_mpls_2_tc_s5;
  logic [2:0] mpls_2_tc_s5;
  logic [0:0] out_mpls_2_bos_s5;
  logic [0:0] mpls_2_bos_s5;
  logic [7:0] out_mpls_2_ttl_s5;
  logic [7:0] mpls_2_ttl_s5;
  logic [8:0] meta_ingress_port_w_s5;
  logic [8:0] meta_egress_port_w_s5;
  logic [31:0] meta_packet_length_w_s5;
  logic [2:0] meta_priority_w_s5;
  logic [15:0] meta_mcast_grp_w_s5;
  logic [15:0] meta_egress_rid_w_s5;
  logic [0:0] meta_checksum_error_w_s5;
  logic [31:0] meta_enq_timestamp_w_s5;
  logic [18:0] meta_enq_qdepth_w_s5;
  logic [31:0] meta_deq_timedelta_w_s5;
  logic [18:0] meta_deq_qdepth_w_s5;
  logic [47:0] meta_ingress_global_timestamp_w_s5;
  logic [47:0] meta_egress_global_timestamp_w_s5;
  logic [7:0] meta_ttl_w_s5;
  logic [31:0] meta_next_hop_w_s5;
  logic [15:0] meta_mpls_label_swap_w_s5;
  logic [0:0] meta_drop_w_s5;
  logic [0:0] meta_ecmp_select_w_s5;
  logic [5:0] _padding_0_s5;
  logic [19:0] key_0_s5;
  logic [31:0] tmp_s5;
  logic [31:0] tmp_0_s5;
  logic [31:0] tmp_1_s5;
  logic [8:0] out_std_meta_egress_port_s5;
  logic [8:0] std_meta_ingress_port_s5;
  logic drop_s5;
  logic __stage_cond_2_r;
  logic __stage_cond_1_r;
  logic valid_s6;
  logic out_ethernet_valid_s6;
  logic ethernet_valid_s6;
  logic out_ipv4_valid_s6;
  logic ipv4_valid_s6;
  logic out_tcp_valid_s6;
  logic tcp_valid_s6;
  logic out_udp_valid_s6;
  logic udp_valid_s6;
  logic out_mpls_0_valid_s6;
  logic mpls_0_valid_s6;
  logic out_mpls_1_valid_s6;
  logic mpls_1_valid_s6;
  logic out_mpls_2_valid_s6;
  logic mpls_2_valid_s6;
  logic [47:0] out_ethernet_dstAddr_s6;
  logic [47:0] ethernet_dstAddr_s6;
  logic [47:0] out_ethernet_srcAddr_s6;
  logic [47:0] ethernet_srcAddr_s6;
  logic [15:0] out_ethernet_etherType_s6;
  logic [15:0] ethernet_etherType_s6;
  logic [3:0] out_ipv4_version_s6;
  logic [3:0] ipv4_version_s6;
  logic [3:0] out_ipv4_ihl_s6;
  logic [3:0] ipv4_ihl_s6;
  logic [7:0] out_ipv4_diffserv_s6;
  logic [7:0] ipv4_diffserv_s6;
  logic [15:0] out_ipv4_totalLen_s6;
  logic [15:0] ipv4_totalLen_s6;
  logic [15:0] out_ipv4_identification_s6;
  logic [15:0] ipv4_identification_s6;
  logic [2:0] out_ipv4_flags_s6;
  logic [2:0] ipv4_flags_s6;
  logic [12:0] out_ipv4_fragOffset_s6;
  logic [12:0] ipv4_fragOffset_s6;
  logic [7:0] out_ipv4_ttl_s6;
  logic [7:0] ipv4_ttl_s6;
  logic [7:0] out_ipv4_protocol_s6;
  logic [7:0] ipv4_protocol_s6;
  logic [15:0] out_ipv4_hdrChecksum_s6;
  logic [15:0] ipv4_hdrChecksum_s6;
  logic [31:0] out_ipv4_srcAddr_s6;
  logic [31:0] ipv4_srcAddr_s6;
  logic [31:0] out_ipv4_dstAddr_s6;
  logic [31:0] ipv4_dstAddr_s6;
  logic [15:0] out_tcp_srcPort_s6;
  logic [15:0] tcp_srcPort_s6;
  logic [15:0] out_tcp_dstPort_s6;
  logic [15:0] tcp_dstPort_s6;
  logic [31:0] out_tcp_seqNo_s6;
  logic [31:0] tcp_seqNo_s6;
  logic [31:0] out_tcp_ackNo_s6;
  logic [31:0] tcp_ackNo_s6;
  logic [3:0] out_tcp_dataOffset_s6;
  logic [3:0] tcp_dataOffset_s6;
  logic [3:0] out_tcp_reserved_s6;
  logic [3:0] tcp_reserved_s6;
  logic [7:0] out_tcp_flags_s6;
  logic [7:0] tcp_flags_s6;
  logic [15:0] out_tcp_window_s6;
  logic [15:0] tcp_window_s6;
  logic [15:0] out_tcp_checksum_s6;
  logic [15:0] tcp_checksum_s6;
  logic [15:0] out_tcp_urgentPtr_s6;
  logic [15:0] tcp_urgentPtr_s6;
  logic [15:0] out_udp_srcPort_s6;
  logic [15:0] udp_srcPort_s6;
  logic [15:0] out_udp_dstPort_s6;
  logic [15:0] udp_dstPort_s6;
  logic [15:0] out_udp_length_s6;
  logic [15:0] udp_length_s6;
  logic [15:0] out_udp_checksum_s6;
  logic [15:0] udp_checksum_s6;
  logic [19:0] out_mpls_0_label_s6;
  logic [19:0] mpls_0_label_s6;
  logic [2:0] out_mpls_0_tc_s6;
  logic [2:0] mpls_0_tc_s6;
  logic [0:0] out_mpls_0_bos_s6;
  logic [0:0] mpls_0_bos_s6;
  logic [7:0] out_mpls_0_ttl_s6;
  logic [7:0] mpls_0_ttl_s6;
  logic [19:0] out_mpls_1_label_s6;
  logic [19:0] mpls_1_label_s6;
  logic [2:0] out_mpls_1_tc_s6;
  logic [2:0] mpls_1_tc_s6;
  logic [0:0] out_mpls_1_bos_s6;
  logic [0:0] mpls_1_bos_s6;
  logic [7:0] out_mpls_1_ttl_s6;
  logic [7:0] mpls_1_ttl_s6;
  logic [19:0] out_mpls_2_label_s6;
  logic [19:0] mpls_2_label_s6;
  logic [2:0] out_mpls_2_tc_s6;
  logic [2:0] mpls_2_tc_s6;
  logic [0:0] out_mpls_2_bos_s6;
  logic [0:0] mpls_2_bos_s6;
  logic [7:0] out_mpls_2_ttl_s6;
  logic [7:0] mpls_2_ttl_s6;
  logic [8:0] meta_ingress_port_w_s6;
  logic [8:0] meta_egress_port_w_s6;
  logic [31:0] meta_packet_length_w_s6;
  logic [2:0] meta_priority_w_s6;
  logic [15:0] meta_mcast_grp_w_s6;
  logic [15:0] meta_egress_rid_w_s6;
  logic [0:0] meta_checksum_error_w_s6;
  logic [31:0] meta_enq_timestamp_w_s6;
  logic [18:0] meta_enq_qdepth_w_s6;
  logic [31:0] meta_deq_timedelta_w_s6;
  logic [18:0] meta_deq_qdepth_w_s6;
  logic [47:0] meta_ingress_global_timestamp_w_s6;
  logic [47:0] meta_egress_global_timestamp_w_s6;
  logic [7:0] meta_ttl_w_s6;
  logic [31:0] meta_next_hop_w_s6;
  logic [15:0] meta_mpls_label_swap_w_s6;
  logic [0:0] meta_drop_w_s6;
  logic [0:0] meta_ecmp_select_w_s6;
  logic [5:0] _padding_0_s6;
  logic [19:0] key_0_s6;
  logic [31:0] tmp_s6;
  logic [31:0] tmp_0_s6;
  logic [31:0] tmp_1_s6;
  logic [8:0] out_std_meta_egress_port_s6;
  logic [8:0] std_meta_ingress_port_s6;
  logic drop_s6;
  logic valid_s7;
  logic out_ethernet_valid_s7;
  logic ethernet_valid_s7;
  logic out_ipv4_valid_s7;
  logic ipv4_valid_s7;
  logic out_tcp_valid_s7;
  logic tcp_valid_s7;
  logic out_udp_valid_s7;
  logic udp_valid_s7;
  logic out_mpls_0_valid_s7;
  logic mpls_0_valid_s7;
  logic out_mpls_1_valid_s7;
  logic mpls_1_valid_s7;
  logic out_mpls_2_valid_s7;
  logic mpls_2_valid_s7;
  logic [47:0] out_ethernet_dstAddr_s7;
  logic [47:0] ethernet_dstAddr_s7;
  logic [47:0] out_ethernet_srcAddr_s7;
  logic [47:0] ethernet_srcAddr_s7;
  logic [15:0] out_ethernet_etherType_s7;
  logic [15:0] ethernet_etherType_s7;
  logic [3:0] out_ipv4_version_s7;
  logic [3:0] ipv4_version_s7;
  logic [3:0] out_ipv4_ihl_s7;
  logic [3:0] ipv4_ihl_s7;
  logic [7:0] out_ipv4_diffserv_s7;
  logic [7:0] ipv4_diffserv_s7;
  logic [15:0] out_ipv4_totalLen_s7;
  logic [15:0] ipv4_totalLen_s7;
  logic [15:0] out_ipv4_identification_s7;
  logic [15:0] ipv4_identification_s7;
  logic [2:0] out_ipv4_flags_s7;
  logic [2:0] ipv4_flags_s7;
  logic [12:0] out_ipv4_fragOffset_s7;
  logic [12:0] ipv4_fragOffset_s7;
  logic [7:0] out_ipv4_ttl_s7;
  logic [7:0] ipv4_ttl_s7;
  logic [7:0] out_ipv4_protocol_s7;
  logic [7:0] ipv4_protocol_s7;
  logic [15:0] out_ipv4_hdrChecksum_s7;
  logic [15:0] ipv4_hdrChecksum_s7;
  logic [31:0] out_ipv4_srcAddr_s7;
  logic [31:0] ipv4_srcAddr_s7;
  logic [31:0] out_ipv4_dstAddr_s7;
  logic [31:0] ipv4_dstAddr_s7;
  logic [15:0] out_tcp_srcPort_s7;
  logic [15:0] tcp_srcPort_s7;
  logic [15:0] out_tcp_dstPort_s7;
  logic [15:0] tcp_dstPort_s7;
  logic [31:0] out_tcp_seqNo_s7;
  logic [31:0] tcp_seqNo_s7;
  logic [31:0] out_tcp_ackNo_s7;
  logic [31:0] tcp_ackNo_s7;
  logic [3:0] out_tcp_dataOffset_s7;
  logic [3:0] tcp_dataOffset_s7;
  logic [3:0] out_tcp_reserved_s7;
  logic [3:0] tcp_reserved_s7;
  logic [7:0] out_tcp_flags_s7;
  logic [7:0] tcp_flags_s7;
  logic [15:0] out_tcp_window_s7;
  logic [15:0] tcp_window_s7;
  logic [15:0] out_tcp_checksum_s7;
  logic [15:0] tcp_checksum_s7;
  logic [15:0] out_tcp_urgentPtr_s7;
  logic [15:0] tcp_urgentPtr_s7;
  logic [15:0] out_udp_srcPort_s7;
  logic [15:0] udp_srcPort_s7;
  logic [15:0] out_udp_dstPort_s7;
  logic [15:0] udp_dstPort_s7;
  logic [15:0] out_udp_length_s7;
  logic [15:0] udp_length_s7;
  logic [15:0] out_udp_checksum_s7;
  logic [15:0] udp_checksum_s7;
  logic [19:0] out_mpls_0_label_s7;
  logic [19:0] mpls_0_label_s7;
  logic [2:0] out_mpls_0_tc_s7;
  logic [2:0] mpls_0_tc_s7;
  logic [0:0] out_mpls_0_bos_s7;
  logic [0:0] mpls_0_bos_s7;
  logic [7:0] out_mpls_0_ttl_s7;
  logic [7:0] mpls_0_ttl_s7;
  logic [19:0] out_mpls_1_label_s7;
  logic [19:0] mpls_1_label_s7;
  logic [2:0] out_mpls_1_tc_s7;
  logic [2:0] mpls_1_tc_s7;
  logic [0:0] out_mpls_1_bos_s7;
  logic [0:0] mpls_1_bos_s7;
  logic [7:0] out_mpls_1_ttl_s7;
  logic [7:0] mpls_1_ttl_s7;
  logic [19:0] out_mpls_2_label_s7;
  logic [19:0] mpls_2_label_s7;
  logic [2:0] out_mpls_2_tc_s7;
  logic [2:0] mpls_2_tc_s7;
  logic [0:0] out_mpls_2_bos_s7;
  logic [0:0] mpls_2_bos_s7;
  logic [7:0] out_mpls_2_ttl_s7;
  logic [7:0] mpls_2_ttl_s7;
  logic [8:0] meta_ingress_port_w_s7;
  logic [8:0] meta_egress_port_w_s7;
  logic [31:0] meta_packet_length_w_s7;
  logic [2:0] meta_priority_w_s7;
  logic [15:0] meta_mcast_grp_w_s7;
  logic [15:0] meta_egress_rid_w_s7;
  logic [0:0] meta_checksum_error_w_s7;
  logic [31:0] meta_enq_timestamp_w_s7;
  logic [18:0] meta_enq_qdepth_w_s7;
  logic [31:0] meta_deq_timedelta_w_s7;
  logic [18:0] meta_deq_qdepth_w_s7;
  logic [47:0] meta_ingress_global_timestamp_w_s7;
  logic [47:0] meta_egress_global_timestamp_w_s7;
  logic [7:0] meta_ttl_w_s7;
  logic [31:0] meta_next_hop_w_s7;
  logic [15:0] meta_mpls_label_swap_w_s7;
  logic [0:0] meta_drop_w_s7;
  logic [0:0] meta_ecmp_select_w_s7;
  logic [5:0] _padding_0_s7;
  logic [19:0] key_0_s7;
  logic [31:0] tmp_s7;
  logic [31:0] tmp_0_s7;
  logic [31:0] tmp_1_s7;
  logic [8:0] out_std_meta_egress_port_s7;
  logic [8:0] std_meta_ingress_port_s7;
  logic drop_s7;
  logic __stage_cond_3_r;
  logic valid_s8;
  logic out_ethernet_valid_s8;
  logic ethernet_valid_s8;
  logic out_ipv4_valid_s8;
  logic ipv4_valid_s8;
  logic out_tcp_valid_s8;
  logic tcp_valid_s8;
  logic out_udp_valid_s8;
  logic udp_valid_s8;
  logic out_mpls_0_valid_s8;
  logic mpls_0_valid_s8;
  logic out_mpls_1_valid_s8;
  logic mpls_1_valid_s8;
  logic out_mpls_2_valid_s8;
  logic mpls_2_valid_s8;
  logic [47:0] out_ethernet_dstAddr_s8;
  logic [47:0] ethernet_dstAddr_s8;
  logic [47:0] out_ethernet_srcAddr_s8;
  logic [47:0] ethernet_srcAddr_s8;
  logic [15:0] out_ethernet_etherType_s8;
  logic [15:0] ethernet_etherType_s8;
  logic [3:0] out_ipv4_version_s8;
  logic [3:0] ipv4_version_s8;
  logic [3:0] out_ipv4_ihl_s8;
  logic [3:0] ipv4_ihl_s8;
  logic [7:0] out_ipv4_diffserv_s8;
  logic [7:0] ipv4_diffserv_s8;
  logic [15:0] out_ipv4_totalLen_s8;
  logic [15:0] ipv4_totalLen_s8;
  logic [15:0] out_ipv4_identification_s8;
  logic [15:0] ipv4_identification_s8;
  logic [2:0] out_ipv4_flags_s8;
  logic [2:0] ipv4_flags_s8;
  logic [12:0] out_ipv4_fragOffset_s8;
  logic [12:0] ipv4_fragOffset_s8;
  logic [7:0] out_ipv4_ttl_s8;
  logic [7:0] ipv4_ttl_s8;
  logic [7:0] out_ipv4_protocol_s8;
  logic [7:0] ipv4_protocol_s8;
  logic [15:0] out_ipv4_hdrChecksum_s8;
  logic [15:0] ipv4_hdrChecksum_s8;
  logic [31:0] out_ipv4_srcAddr_s8;
  logic [31:0] ipv4_srcAddr_s8;
  logic [31:0] out_ipv4_dstAddr_s8;
  logic [31:0] ipv4_dstAddr_s8;
  logic [15:0] out_tcp_srcPort_s8;
  logic [15:0] tcp_srcPort_s8;
  logic [15:0] out_tcp_dstPort_s8;
  logic [15:0] tcp_dstPort_s8;
  logic [31:0] out_tcp_seqNo_s8;
  logic [31:0] tcp_seqNo_s8;
  logic [31:0] out_tcp_ackNo_s8;
  logic [31:0] tcp_ackNo_s8;
  logic [3:0] out_tcp_dataOffset_s8;
  logic [3:0] tcp_dataOffset_s8;
  logic [3:0] out_tcp_reserved_s8;
  logic [3:0] tcp_reserved_s8;
  logic [7:0] out_tcp_flags_s8;
  logic [7:0] tcp_flags_s8;
  logic [15:0] out_tcp_window_s8;
  logic [15:0] tcp_window_s8;
  logic [15:0] out_tcp_checksum_s8;
  logic [15:0] tcp_checksum_s8;
  logic [15:0] out_tcp_urgentPtr_s8;
  logic [15:0] tcp_urgentPtr_s8;
  logic [15:0] out_udp_srcPort_s8;
  logic [15:0] udp_srcPort_s8;
  logic [15:0] out_udp_dstPort_s8;
  logic [15:0] udp_dstPort_s8;
  logic [15:0] out_udp_length_s8;
  logic [15:0] udp_length_s8;
  logic [15:0] out_udp_checksum_s8;
  logic [15:0] udp_checksum_s8;
  logic [19:0] out_mpls_0_label_s8;
  logic [19:0] mpls_0_label_s8;
  logic [2:0] out_mpls_0_tc_s8;
  logic [2:0] mpls_0_tc_s8;
  logic [0:0] out_mpls_0_bos_s8;
  logic [0:0] mpls_0_bos_s8;
  logic [7:0] out_mpls_0_ttl_s8;
  logic [7:0] mpls_0_ttl_s8;
  logic [19:0] out_mpls_1_label_s8;
  logic [19:0] mpls_1_label_s8;
  logic [2:0] out_mpls_1_tc_s8;
  logic [2:0] mpls_1_tc_s8;
  logic [0:0] out_mpls_1_bos_s8;
  logic [0:0] mpls_1_bos_s8;
  logic [7:0] out_mpls_1_ttl_s8;
  logic [7:0] mpls_1_ttl_s8;
  logic [19:0] out_mpls_2_label_s8;
  logic [19:0] mpls_2_label_s8;
  logic [2:0] out_mpls_2_tc_s8;
  logic [2:0] mpls_2_tc_s8;
  logic [0:0] out_mpls_2_bos_s8;
  logic [0:0] mpls_2_bos_s8;
  logic [7:0] out_mpls_2_ttl_s8;
  logic [7:0] mpls_2_ttl_s8;
  logic [8:0] meta_ingress_port_w_s8;
  logic [8:0] meta_egress_port_w_s8;
  logic [31:0] meta_packet_length_w_s8;
  logic [2:0] meta_priority_w_s8;
  logic [15:0] meta_mcast_grp_w_s8;
  logic [15:0] meta_egress_rid_w_s8;
  logic [0:0] meta_checksum_error_w_s8;
  logic [31:0] meta_enq_timestamp_w_s8;
  logic [18:0] meta_enq_qdepth_w_s8;
  logic [31:0] meta_deq_timedelta_w_s8;
  logic [18:0] meta_deq_qdepth_w_s8;
  logic [47:0] meta_ingress_global_timestamp_w_s8;
  logic [47:0] meta_egress_global_timestamp_w_s8;
  logic [7:0] meta_ttl_w_s8;
  logic [31:0] meta_next_hop_w_s8;
  logic [15:0] meta_mpls_label_swap_w_s8;
  logic [0:0] meta_drop_w_s8;
  logic [0:0] meta_ecmp_select_w_s8;
  logic [5:0] _padding_0_s8;
  logic [19:0] key_0_s8;
  logic [31:0] tmp_s8;
  logic [31:0] tmp_0_s8;
  logic [31:0] tmp_1_s8;
  logic [8:0] out_std_meta_egress_port_s8;
  logic [8:0] std_meta_ingress_port_s8;
  logic drop_s8;

  // Pool-A (out_*/drop) working copies -- every stage except the
  // last, which drives the real output ports directly
  logic out_ethernet_valid__st0;
  logic out_ipv4_valid__st0;
  logic out_tcp_valid__st0;
  logic out_udp_valid__st0;
  logic out_mpls_0_valid__st0;
  logic out_mpls_1_valid__st0;
  logic out_mpls_2_valid__st0;
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
  logic [15:0] out_tcp_srcPort__st0;
  logic [15:0] out_tcp_dstPort__st0;
  logic [31:0] out_tcp_seqNo__st0;
  logic [31:0] out_tcp_ackNo__st0;
  logic [3:0] out_tcp_dataOffset__st0;
  logic [3:0] out_tcp_reserved__st0;
  logic [7:0] out_tcp_flags__st0;
  logic [15:0] out_tcp_window__st0;
  logic [15:0] out_tcp_checksum__st0;
  logic [15:0] out_tcp_urgentPtr__st0;
  logic [15:0] out_udp_srcPort__st0;
  logic [15:0] out_udp_dstPort__st0;
  logic [15:0] out_udp_length__st0;
  logic [15:0] out_udp_checksum__st0;
  logic [19:0] out_mpls_0_label__st0;
  logic [2:0] out_mpls_0_tc__st0;
  logic [0:0] out_mpls_0_bos__st0;
  logic [7:0] out_mpls_0_ttl__st0;
  logic [19:0] out_mpls_1_label__st0;
  logic [2:0] out_mpls_1_tc__st0;
  logic [0:0] out_mpls_1_bos__st0;
  logic [7:0] out_mpls_1_ttl__st0;
  logic [19:0] out_mpls_2_label__st0;
  logic [2:0] out_mpls_2_tc__st0;
  logic [0:0] out_mpls_2_bos__st0;
  logic [7:0] out_mpls_2_ttl__st0;
  logic [8:0] out_std_meta_egress_port__st0;
  logic drop__st0;
  logic out_ethernet_valid__st1;
  logic out_ipv4_valid__st1;
  logic out_tcp_valid__st1;
  logic out_udp_valid__st1;
  logic out_mpls_0_valid__st1;
  logic out_mpls_1_valid__st1;
  logic out_mpls_2_valid__st1;
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
  logic [15:0] out_tcp_srcPort__st1;
  logic [15:0] out_tcp_dstPort__st1;
  logic [31:0] out_tcp_seqNo__st1;
  logic [31:0] out_tcp_ackNo__st1;
  logic [3:0] out_tcp_dataOffset__st1;
  logic [3:0] out_tcp_reserved__st1;
  logic [7:0] out_tcp_flags__st1;
  logic [15:0] out_tcp_window__st1;
  logic [15:0] out_tcp_checksum__st1;
  logic [15:0] out_tcp_urgentPtr__st1;
  logic [15:0] out_udp_srcPort__st1;
  logic [15:0] out_udp_dstPort__st1;
  logic [15:0] out_udp_length__st1;
  logic [15:0] out_udp_checksum__st1;
  logic [19:0] out_mpls_0_label__st1;
  logic [2:0] out_mpls_0_tc__st1;
  logic [0:0] out_mpls_0_bos__st1;
  logic [7:0] out_mpls_0_ttl__st1;
  logic [19:0] out_mpls_1_label__st1;
  logic [2:0] out_mpls_1_tc__st1;
  logic [0:0] out_mpls_1_bos__st1;
  logic [7:0] out_mpls_1_ttl__st1;
  logic [19:0] out_mpls_2_label__st1;
  logic [2:0] out_mpls_2_tc__st1;
  logic [0:0] out_mpls_2_bos__st1;
  logic [7:0] out_mpls_2_ttl__st1;
  logic [8:0] out_std_meta_egress_port__st1;
  logic drop__st1;
  logic out_ethernet_valid__st2;
  logic out_ipv4_valid__st2;
  logic out_tcp_valid__st2;
  logic out_udp_valid__st2;
  logic out_mpls_0_valid__st2;
  logic out_mpls_1_valid__st2;
  logic out_mpls_2_valid__st2;
  logic [47:0] out_ethernet_dstAddr__st2;
  logic [47:0] out_ethernet_srcAddr__st2;
  logic [15:0] out_ethernet_etherType__st2;
  logic [3:0] out_ipv4_version__st2;
  logic [3:0] out_ipv4_ihl__st2;
  logic [7:0] out_ipv4_diffserv__st2;
  logic [15:0] out_ipv4_totalLen__st2;
  logic [15:0] out_ipv4_identification__st2;
  logic [2:0] out_ipv4_flags__st2;
  logic [12:0] out_ipv4_fragOffset__st2;
  logic [7:0] out_ipv4_ttl__st2;
  logic [7:0] out_ipv4_protocol__st2;
  logic [15:0] out_ipv4_hdrChecksum__st2;
  logic [31:0] out_ipv4_srcAddr__st2;
  logic [31:0] out_ipv4_dstAddr__st2;
  logic [15:0] out_tcp_srcPort__st2;
  logic [15:0] out_tcp_dstPort__st2;
  logic [31:0] out_tcp_seqNo__st2;
  logic [31:0] out_tcp_ackNo__st2;
  logic [3:0] out_tcp_dataOffset__st2;
  logic [3:0] out_tcp_reserved__st2;
  logic [7:0] out_tcp_flags__st2;
  logic [15:0] out_tcp_window__st2;
  logic [15:0] out_tcp_checksum__st2;
  logic [15:0] out_tcp_urgentPtr__st2;
  logic [15:0] out_udp_srcPort__st2;
  logic [15:0] out_udp_dstPort__st2;
  logic [15:0] out_udp_length__st2;
  logic [15:0] out_udp_checksum__st2;
  logic [19:0] out_mpls_0_label__st2;
  logic [2:0] out_mpls_0_tc__st2;
  logic [0:0] out_mpls_0_bos__st2;
  logic [7:0] out_mpls_0_ttl__st2;
  logic [19:0] out_mpls_1_label__st2;
  logic [2:0] out_mpls_1_tc__st2;
  logic [0:0] out_mpls_1_bos__st2;
  logic [7:0] out_mpls_1_ttl__st2;
  logic [19:0] out_mpls_2_label__st2;
  logic [2:0] out_mpls_2_tc__st2;
  logic [0:0] out_mpls_2_bos__st2;
  logic [7:0] out_mpls_2_ttl__st2;
  logic [8:0] out_std_meta_egress_port__st2;
  logic drop__st2;
  logic out_ethernet_valid__st3;
  logic out_ipv4_valid__st3;
  logic out_tcp_valid__st3;
  logic out_udp_valid__st3;
  logic out_mpls_0_valid__st3;
  logic out_mpls_1_valid__st3;
  logic out_mpls_2_valid__st3;
  logic [47:0] out_ethernet_dstAddr__st3;
  logic [47:0] out_ethernet_srcAddr__st3;
  logic [15:0] out_ethernet_etherType__st3;
  logic [3:0] out_ipv4_version__st3;
  logic [3:0] out_ipv4_ihl__st3;
  logic [7:0] out_ipv4_diffserv__st3;
  logic [15:0] out_ipv4_totalLen__st3;
  logic [15:0] out_ipv4_identification__st3;
  logic [2:0] out_ipv4_flags__st3;
  logic [12:0] out_ipv4_fragOffset__st3;
  logic [7:0] out_ipv4_ttl__st3;
  logic [7:0] out_ipv4_protocol__st3;
  logic [15:0] out_ipv4_hdrChecksum__st3;
  logic [31:0] out_ipv4_srcAddr__st3;
  logic [31:0] out_ipv4_dstAddr__st3;
  logic [15:0] out_tcp_srcPort__st3;
  logic [15:0] out_tcp_dstPort__st3;
  logic [31:0] out_tcp_seqNo__st3;
  logic [31:0] out_tcp_ackNo__st3;
  logic [3:0] out_tcp_dataOffset__st3;
  logic [3:0] out_tcp_reserved__st3;
  logic [7:0] out_tcp_flags__st3;
  logic [15:0] out_tcp_window__st3;
  logic [15:0] out_tcp_checksum__st3;
  logic [15:0] out_tcp_urgentPtr__st3;
  logic [15:0] out_udp_srcPort__st3;
  logic [15:0] out_udp_dstPort__st3;
  logic [15:0] out_udp_length__st3;
  logic [15:0] out_udp_checksum__st3;
  logic [19:0] out_mpls_0_label__st3;
  logic [2:0] out_mpls_0_tc__st3;
  logic [0:0] out_mpls_0_bos__st3;
  logic [7:0] out_mpls_0_ttl__st3;
  logic [19:0] out_mpls_1_label__st3;
  logic [2:0] out_mpls_1_tc__st3;
  logic [0:0] out_mpls_1_bos__st3;
  logic [7:0] out_mpls_1_ttl__st3;
  logic [19:0] out_mpls_2_label__st3;
  logic [2:0] out_mpls_2_tc__st3;
  logic [0:0] out_mpls_2_bos__st3;
  logic [7:0] out_mpls_2_ttl__st3;
  logic [8:0] out_std_meta_egress_port__st3;
  logic drop__st3;
  logic out_ethernet_valid__st4;
  logic out_ipv4_valid__st4;
  logic out_tcp_valid__st4;
  logic out_udp_valid__st4;
  logic out_mpls_0_valid__st4;
  logic out_mpls_1_valid__st4;
  logic out_mpls_2_valid__st4;
  logic [47:0] out_ethernet_dstAddr__st4;
  logic [47:0] out_ethernet_srcAddr__st4;
  logic [15:0] out_ethernet_etherType__st4;
  logic [3:0] out_ipv4_version__st4;
  logic [3:0] out_ipv4_ihl__st4;
  logic [7:0] out_ipv4_diffserv__st4;
  logic [15:0] out_ipv4_totalLen__st4;
  logic [15:0] out_ipv4_identification__st4;
  logic [2:0] out_ipv4_flags__st4;
  logic [12:0] out_ipv4_fragOffset__st4;
  logic [7:0] out_ipv4_ttl__st4;
  logic [7:0] out_ipv4_protocol__st4;
  logic [15:0] out_ipv4_hdrChecksum__st4;
  logic [31:0] out_ipv4_srcAddr__st4;
  logic [31:0] out_ipv4_dstAddr__st4;
  logic [15:0] out_tcp_srcPort__st4;
  logic [15:0] out_tcp_dstPort__st4;
  logic [31:0] out_tcp_seqNo__st4;
  logic [31:0] out_tcp_ackNo__st4;
  logic [3:0] out_tcp_dataOffset__st4;
  logic [3:0] out_tcp_reserved__st4;
  logic [7:0] out_tcp_flags__st4;
  logic [15:0] out_tcp_window__st4;
  logic [15:0] out_tcp_checksum__st4;
  logic [15:0] out_tcp_urgentPtr__st4;
  logic [15:0] out_udp_srcPort__st4;
  logic [15:0] out_udp_dstPort__st4;
  logic [15:0] out_udp_length__st4;
  logic [15:0] out_udp_checksum__st4;
  logic [19:0] out_mpls_0_label__st4;
  logic [2:0] out_mpls_0_tc__st4;
  logic [0:0] out_mpls_0_bos__st4;
  logic [7:0] out_mpls_0_ttl__st4;
  logic [19:0] out_mpls_1_label__st4;
  logic [2:0] out_mpls_1_tc__st4;
  logic [0:0] out_mpls_1_bos__st4;
  logic [7:0] out_mpls_1_ttl__st4;
  logic [19:0] out_mpls_2_label__st4;
  logic [2:0] out_mpls_2_tc__st4;
  logic [0:0] out_mpls_2_bos__st4;
  logic [7:0] out_mpls_2_ttl__st4;
  logic [8:0] out_std_meta_egress_port__st4;
  logic drop__st4;
  logic out_ethernet_valid__st5;
  logic out_ipv4_valid__st5;
  logic out_tcp_valid__st5;
  logic out_udp_valid__st5;
  logic out_mpls_0_valid__st5;
  logic out_mpls_1_valid__st5;
  logic out_mpls_2_valid__st5;
  logic [47:0] out_ethernet_dstAddr__st5;
  logic [47:0] out_ethernet_srcAddr__st5;
  logic [15:0] out_ethernet_etherType__st5;
  logic [3:0] out_ipv4_version__st5;
  logic [3:0] out_ipv4_ihl__st5;
  logic [7:0] out_ipv4_diffserv__st5;
  logic [15:0] out_ipv4_totalLen__st5;
  logic [15:0] out_ipv4_identification__st5;
  logic [2:0] out_ipv4_flags__st5;
  logic [12:0] out_ipv4_fragOffset__st5;
  logic [7:0] out_ipv4_ttl__st5;
  logic [7:0] out_ipv4_protocol__st5;
  logic [15:0] out_ipv4_hdrChecksum__st5;
  logic [31:0] out_ipv4_srcAddr__st5;
  logic [31:0] out_ipv4_dstAddr__st5;
  logic [15:0] out_tcp_srcPort__st5;
  logic [15:0] out_tcp_dstPort__st5;
  logic [31:0] out_tcp_seqNo__st5;
  logic [31:0] out_tcp_ackNo__st5;
  logic [3:0] out_tcp_dataOffset__st5;
  logic [3:0] out_tcp_reserved__st5;
  logic [7:0] out_tcp_flags__st5;
  logic [15:0] out_tcp_window__st5;
  logic [15:0] out_tcp_checksum__st5;
  logic [15:0] out_tcp_urgentPtr__st5;
  logic [15:0] out_udp_srcPort__st5;
  logic [15:0] out_udp_dstPort__st5;
  logic [15:0] out_udp_length__st5;
  logic [15:0] out_udp_checksum__st5;
  logic [19:0] out_mpls_0_label__st5;
  logic [2:0] out_mpls_0_tc__st5;
  logic [0:0] out_mpls_0_bos__st5;
  logic [7:0] out_mpls_0_ttl__st5;
  logic [19:0] out_mpls_1_label__st5;
  logic [2:0] out_mpls_1_tc__st5;
  logic [0:0] out_mpls_1_bos__st5;
  logic [7:0] out_mpls_1_ttl__st5;
  logic [19:0] out_mpls_2_label__st5;
  logic [2:0] out_mpls_2_tc__st5;
  logic [0:0] out_mpls_2_bos__st5;
  logic [7:0] out_mpls_2_ttl__st5;
  logic [8:0] out_std_meta_egress_port__st5;
  logic drop__st5;
  logic out_ethernet_valid__st6;
  logic out_ipv4_valid__st6;
  logic out_tcp_valid__st6;
  logic out_udp_valid__st6;
  logic out_mpls_0_valid__st6;
  logic out_mpls_1_valid__st6;
  logic out_mpls_2_valid__st6;
  logic [47:0] out_ethernet_dstAddr__st6;
  logic [47:0] out_ethernet_srcAddr__st6;
  logic [15:0] out_ethernet_etherType__st6;
  logic [3:0] out_ipv4_version__st6;
  logic [3:0] out_ipv4_ihl__st6;
  logic [7:0] out_ipv4_diffserv__st6;
  logic [15:0] out_ipv4_totalLen__st6;
  logic [15:0] out_ipv4_identification__st6;
  logic [2:0] out_ipv4_flags__st6;
  logic [12:0] out_ipv4_fragOffset__st6;
  logic [7:0] out_ipv4_ttl__st6;
  logic [7:0] out_ipv4_protocol__st6;
  logic [15:0] out_ipv4_hdrChecksum__st6;
  logic [31:0] out_ipv4_srcAddr__st6;
  logic [31:0] out_ipv4_dstAddr__st6;
  logic [15:0] out_tcp_srcPort__st6;
  logic [15:0] out_tcp_dstPort__st6;
  logic [31:0] out_tcp_seqNo__st6;
  logic [31:0] out_tcp_ackNo__st6;
  logic [3:0] out_tcp_dataOffset__st6;
  logic [3:0] out_tcp_reserved__st6;
  logic [7:0] out_tcp_flags__st6;
  logic [15:0] out_tcp_window__st6;
  logic [15:0] out_tcp_checksum__st6;
  logic [15:0] out_tcp_urgentPtr__st6;
  logic [15:0] out_udp_srcPort__st6;
  logic [15:0] out_udp_dstPort__st6;
  logic [15:0] out_udp_length__st6;
  logic [15:0] out_udp_checksum__st6;
  logic [19:0] out_mpls_0_label__st6;
  logic [2:0] out_mpls_0_tc__st6;
  logic [0:0] out_mpls_0_bos__st6;
  logic [7:0] out_mpls_0_ttl__st6;
  logic [19:0] out_mpls_1_label__st6;
  logic [2:0] out_mpls_1_tc__st6;
  logic [0:0] out_mpls_1_bos__st6;
  logic [7:0] out_mpls_1_ttl__st6;
  logic [19:0] out_mpls_2_label__st6;
  logic [2:0] out_mpls_2_tc__st6;
  logic [0:0] out_mpls_2_bos__st6;
  logic [7:0] out_mpls_2_ttl__st6;
  logic [8:0] out_std_meta_egress_port__st6;
  logic drop__st6;
  logic out_ethernet_valid__st7;
  logic out_ipv4_valid__st7;
  logic out_tcp_valid__st7;
  logic out_udp_valid__st7;
  logic out_mpls_0_valid__st7;
  logic out_mpls_1_valid__st7;
  logic out_mpls_2_valid__st7;
  logic [47:0] out_ethernet_dstAddr__st7;
  logic [47:0] out_ethernet_srcAddr__st7;
  logic [15:0] out_ethernet_etherType__st7;
  logic [3:0] out_ipv4_version__st7;
  logic [3:0] out_ipv4_ihl__st7;
  logic [7:0] out_ipv4_diffserv__st7;
  logic [15:0] out_ipv4_totalLen__st7;
  logic [15:0] out_ipv4_identification__st7;
  logic [2:0] out_ipv4_flags__st7;
  logic [12:0] out_ipv4_fragOffset__st7;
  logic [7:0] out_ipv4_ttl__st7;
  logic [7:0] out_ipv4_protocol__st7;
  logic [15:0] out_ipv4_hdrChecksum__st7;
  logic [31:0] out_ipv4_srcAddr__st7;
  logic [31:0] out_ipv4_dstAddr__st7;
  logic [15:0] out_tcp_srcPort__st7;
  logic [15:0] out_tcp_dstPort__st7;
  logic [31:0] out_tcp_seqNo__st7;
  logic [31:0] out_tcp_ackNo__st7;
  logic [3:0] out_tcp_dataOffset__st7;
  logic [3:0] out_tcp_reserved__st7;
  logic [7:0] out_tcp_flags__st7;
  logic [15:0] out_tcp_window__st7;
  logic [15:0] out_tcp_checksum__st7;
  logic [15:0] out_tcp_urgentPtr__st7;
  logic [15:0] out_udp_srcPort__st7;
  logic [15:0] out_udp_dstPort__st7;
  logic [15:0] out_udp_length__st7;
  logic [15:0] out_udp_checksum__st7;
  logic [19:0] out_mpls_0_label__st7;
  logic [2:0] out_mpls_0_tc__st7;
  logic [0:0] out_mpls_0_bos__st7;
  logic [7:0] out_mpls_0_ttl__st7;
  logic [19:0] out_mpls_1_label__st7;
  logic [2:0] out_mpls_1_tc__st7;
  logic [0:0] out_mpls_1_bos__st7;
  logic [7:0] out_mpls_1_ttl__st7;
  logic [19:0] out_mpls_2_label__st7;
  logic [2:0] out_mpls_2_tc__st7;
  logic [0:0] out_mpls_2_bos__st7;
  logic [7:0] out_mpls_2_ttl__st7;
  logic [8:0] out_std_meta_egress_port__st7;
  logic drop__st7;

  // Pool-B (locals/meta shadow/raw hdr+std_meta reads) working
  // copies -- every stage except the first, which reads live inputs
  logic [5:0] _padding_0__st1;
  logic [19:0] key_0__st1;
  logic [31:0] tmp__st1;
  logic [31:0] tmp_0__st1;
  logic [31:0] tmp_1__st1;
  logic [8:0] meta_ingress_port_w__st1;
  logic [8:0] meta_egress_port_w__st1;
  logic [31:0] meta_packet_length_w__st1;
  logic [2:0] meta_priority_w__st1;
  logic [15:0] meta_mcast_grp_w__st1;
  logic [15:0] meta_egress_rid_w__st1;
  logic [0:0] meta_checksum_error_w__st1;
  logic [31:0] meta_enq_timestamp_w__st1;
  logic [18:0] meta_enq_qdepth_w__st1;
  logic [31:0] meta_deq_timedelta_w__st1;
  logic [18:0] meta_deq_qdepth_w__st1;
  logic [47:0] meta_ingress_global_timestamp_w__st1;
  logic [47:0] meta_egress_global_timestamp_w__st1;
  logic [7:0] meta_ttl_w__st1;
  logic [31:0] meta_next_hop_w__st1;
  logic [15:0] meta_mpls_label_swap_w__st1;
  logic [0:0] meta_drop_w__st1;
  logic [0:0] meta_ecmp_select_w__st1;
  logic ethernet_valid__st1;
  logic ipv4_valid__st1;
  logic tcp_valid__st1;
  logic udp_valid__st1;
  logic mpls_0_valid__st1;
  logic mpls_1_valid__st1;
  logic mpls_2_valid__st1;
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
  logic [15:0] tcp_srcPort__st1;
  logic [15:0] tcp_dstPort__st1;
  logic [31:0] tcp_seqNo__st1;
  logic [31:0] tcp_ackNo__st1;
  logic [3:0] tcp_dataOffset__st1;
  logic [3:0] tcp_reserved__st1;
  logic [7:0] tcp_flags__st1;
  logic [15:0] tcp_window__st1;
  logic [15:0] tcp_checksum__st1;
  logic [15:0] tcp_urgentPtr__st1;
  logic [15:0] udp_srcPort__st1;
  logic [15:0] udp_dstPort__st1;
  logic [15:0] udp_length__st1;
  logic [15:0] udp_checksum__st1;
  logic [19:0] mpls_0_label__st1;
  logic [2:0] mpls_0_tc__st1;
  logic [0:0] mpls_0_bos__st1;
  logic [7:0] mpls_0_ttl__st1;
  logic [19:0] mpls_1_label__st1;
  logic [2:0] mpls_1_tc__st1;
  logic [0:0] mpls_1_bos__st1;
  logic [7:0] mpls_1_ttl__st1;
  logic [19:0] mpls_2_label__st1;
  logic [2:0] mpls_2_tc__st1;
  logic [0:0] mpls_2_bos__st1;
  logic [7:0] mpls_2_ttl__st1;
  logic [8:0] std_meta_ingress_port__st1;
  logic [5:0] _padding_0__st2;
  logic [19:0] key_0__st2;
  logic [31:0] tmp__st2;
  logic [31:0] tmp_0__st2;
  logic [31:0] tmp_1__st2;
  logic [8:0] meta_ingress_port_w__st2;
  logic [8:0] meta_egress_port_w__st2;
  logic [31:0] meta_packet_length_w__st2;
  logic [2:0] meta_priority_w__st2;
  logic [15:0] meta_mcast_grp_w__st2;
  logic [15:0] meta_egress_rid_w__st2;
  logic [0:0] meta_checksum_error_w__st2;
  logic [31:0] meta_enq_timestamp_w__st2;
  logic [18:0] meta_enq_qdepth_w__st2;
  logic [31:0] meta_deq_timedelta_w__st2;
  logic [18:0] meta_deq_qdepth_w__st2;
  logic [47:0] meta_ingress_global_timestamp_w__st2;
  logic [47:0] meta_egress_global_timestamp_w__st2;
  logic [7:0] meta_ttl_w__st2;
  logic [31:0] meta_next_hop_w__st2;
  logic [15:0] meta_mpls_label_swap_w__st2;
  logic [0:0] meta_drop_w__st2;
  logic [0:0] meta_ecmp_select_w__st2;
  logic ethernet_valid__st2;
  logic ipv4_valid__st2;
  logic tcp_valid__st2;
  logic udp_valid__st2;
  logic mpls_0_valid__st2;
  logic mpls_1_valid__st2;
  logic mpls_2_valid__st2;
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
  logic [15:0] tcp_srcPort__st2;
  logic [15:0] tcp_dstPort__st2;
  logic [31:0] tcp_seqNo__st2;
  logic [31:0] tcp_ackNo__st2;
  logic [3:0] tcp_dataOffset__st2;
  logic [3:0] tcp_reserved__st2;
  logic [7:0] tcp_flags__st2;
  logic [15:0] tcp_window__st2;
  logic [15:0] tcp_checksum__st2;
  logic [15:0] tcp_urgentPtr__st2;
  logic [15:0] udp_srcPort__st2;
  logic [15:0] udp_dstPort__st2;
  logic [15:0] udp_length__st2;
  logic [15:0] udp_checksum__st2;
  logic [19:0] mpls_0_label__st2;
  logic [2:0] mpls_0_tc__st2;
  logic [0:0] mpls_0_bos__st2;
  logic [7:0] mpls_0_ttl__st2;
  logic [19:0] mpls_1_label__st2;
  logic [2:0] mpls_1_tc__st2;
  logic [0:0] mpls_1_bos__st2;
  logic [7:0] mpls_1_ttl__st2;
  logic [19:0] mpls_2_label__st2;
  logic [2:0] mpls_2_tc__st2;
  logic [0:0] mpls_2_bos__st2;
  logic [7:0] mpls_2_ttl__st2;
  logic [8:0] std_meta_ingress_port__st2;
  logic [5:0] _padding_0__st3;
  logic [19:0] key_0__st3;
  logic [31:0] tmp__st3;
  logic [31:0] tmp_0__st3;
  logic [31:0] tmp_1__st3;
  logic [8:0] meta_ingress_port_w__st3;
  logic [8:0] meta_egress_port_w__st3;
  logic [31:0] meta_packet_length_w__st3;
  logic [2:0] meta_priority_w__st3;
  logic [15:0] meta_mcast_grp_w__st3;
  logic [15:0] meta_egress_rid_w__st3;
  logic [0:0] meta_checksum_error_w__st3;
  logic [31:0] meta_enq_timestamp_w__st3;
  logic [18:0] meta_enq_qdepth_w__st3;
  logic [31:0] meta_deq_timedelta_w__st3;
  logic [18:0] meta_deq_qdepth_w__st3;
  logic [47:0] meta_ingress_global_timestamp_w__st3;
  logic [47:0] meta_egress_global_timestamp_w__st3;
  logic [7:0] meta_ttl_w__st3;
  logic [31:0] meta_next_hop_w__st3;
  logic [15:0] meta_mpls_label_swap_w__st3;
  logic [0:0] meta_drop_w__st3;
  logic [0:0] meta_ecmp_select_w__st3;
  logic ethernet_valid__st3;
  logic ipv4_valid__st3;
  logic tcp_valid__st3;
  logic udp_valid__st3;
  logic mpls_0_valid__st3;
  logic mpls_1_valid__st3;
  logic mpls_2_valid__st3;
  logic [47:0] ethernet_dstAddr__st3;
  logic [47:0] ethernet_srcAddr__st3;
  logic [15:0] ethernet_etherType__st3;
  logic [3:0] ipv4_version__st3;
  logic [3:0] ipv4_ihl__st3;
  logic [7:0] ipv4_diffserv__st3;
  logic [15:0] ipv4_totalLen__st3;
  logic [15:0] ipv4_identification__st3;
  logic [2:0] ipv4_flags__st3;
  logic [12:0] ipv4_fragOffset__st3;
  logic [7:0] ipv4_ttl__st3;
  logic [7:0] ipv4_protocol__st3;
  logic [15:0] ipv4_hdrChecksum__st3;
  logic [31:0] ipv4_srcAddr__st3;
  logic [31:0] ipv4_dstAddr__st3;
  logic [15:0] tcp_srcPort__st3;
  logic [15:0] tcp_dstPort__st3;
  logic [31:0] tcp_seqNo__st3;
  logic [31:0] tcp_ackNo__st3;
  logic [3:0] tcp_dataOffset__st3;
  logic [3:0] tcp_reserved__st3;
  logic [7:0] tcp_flags__st3;
  logic [15:0] tcp_window__st3;
  logic [15:0] tcp_checksum__st3;
  logic [15:0] tcp_urgentPtr__st3;
  logic [15:0] udp_srcPort__st3;
  logic [15:0] udp_dstPort__st3;
  logic [15:0] udp_length__st3;
  logic [15:0] udp_checksum__st3;
  logic [19:0] mpls_0_label__st3;
  logic [2:0] mpls_0_tc__st3;
  logic [0:0] mpls_0_bos__st3;
  logic [7:0] mpls_0_ttl__st3;
  logic [19:0] mpls_1_label__st3;
  logic [2:0] mpls_1_tc__st3;
  logic [0:0] mpls_1_bos__st3;
  logic [7:0] mpls_1_ttl__st3;
  logic [19:0] mpls_2_label__st3;
  logic [2:0] mpls_2_tc__st3;
  logic [0:0] mpls_2_bos__st3;
  logic [7:0] mpls_2_ttl__st3;
  logic [8:0] std_meta_ingress_port__st3;
  logic [5:0] _padding_0__st4;
  logic [19:0] key_0__st4;
  logic [31:0] tmp__st4;
  logic [31:0] tmp_0__st4;
  logic [31:0] tmp_1__st4;
  logic [8:0] meta_ingress_port_w__st4;
  logic [8:0] meta_egress_port_w__st4;
  logic [31:0] meta_packet_length_w__st4;
  logic [2:0] meta_priority_w__st4;
  logic [15:0] meta_mcast_grp_w__st4;
  logic [15:0] meta_egress_rid_w__st4;
  logic [0:0] meta_checksum_error_w__st4;
  logic [31:0] meta_enq_timestamp_w__st4;
  logic [18:0] meta_enq_qdepth_w__st4;
  logic [31:0] meta_deq_timedelta_w__st4;
  logic [18:0] meta_deq_qdepth_w__st4;
  logic [47:0] meta_ingress_global_timestamp_w__st4;
  logic [47:0] meta_egress_global_timestamp_w__st4;
  logic [7:0] meta_ttl_w__st4;
  logic [31:0] meta_next_hop_w__st4;
  logic [15:0] meta_mpls_label_swap_w__st4;
  logic [0:0] meta_drop_w__st4;
  logic [0:0] meta_ecmp_select_w__st4;
  logic ethernet_valid__st4;
  logic ipv4_valid__st4;
  logic tcp_valid__st4;
  logic udp_valid__st4;
  logic mpls_0_valid__st4;
  logic mpls_1_valid__st4;
  logic mpls_2_valid__st4;
  logic [47:0] ethernet_dstAddr__st4;
  logic [47:0] ethernet_srcAddr__st4;
  logic [15:0] ethernet_etherType__st4;
  logic [3:0] ipv4_version__st4;
  logic [3:0] ipv4_ihl__st4;
  logic [7:0] ipv4_diffserv__st4;
  logic [15:0] ipv4_totalLen__st4;
  logic [15:0] ipv4_identification__st4;
  logic [2:0] ipv4_flags__st4;
  logic [12:0] ipv4_fragOffset__st4;
  logic [7:0] ipv4_ttl__st4;
  logic [7:0] ipv4_protocol__st4;
  logic [15:0] ipv4_hdrChecksum__st4;
  logic [31:0] ipv4_srcAddr__st4;
  logic [31:0] ipv4_dstAddr__st4;
  logic [15:0] tcp_srcPort__st4;
  logic [15:0] tcp_dstPort__st4;
  logic [31:0] tcp_seqNo__st4;
  logic [31:0] tcp_ackNo__st4;
  logic [3:0] tcp_dataOffset__st4;
  logic [3:0] tcp_reserved__st4;
  logic [7:0] tcp_flags__st4;
  logic [15:0] tcp_window__st4;
  logic [15:0] tcp_checksum__st4;
  logic [15:0] tcp_urgentPtr__st4;
  logic [15:0] udp_srcPort__st4;
  logic [15:0] udp_dstPort__st4;
  logic [15:0] udp_length__st4;
  logic [15:0] udp_checksum__st4;
  logic [19:0] mpls_0_label__st4;
  logic [2:0] mpls_0_tc__st4;
  logic [0:0] mpls_0_bos__st4;
  logic [7:0] mpls_0_ttl__st4;
  logic [19:0] mpls_1_label__st4;
  logic [2:0] mpls_1_tc__st4;
  logic [0:0] mpls_1_bos__st4;
  logic [7:0] mpls_1_ttl__st4;
  logic [19:0] mpls_2_label__st4;
  logic [2:0] mpls_2_tc__st4;
  logic [0:0] mpls_2_bos__st4;
  logic [7:0] mpls_2_ttl__st4;
  logic [8:0] std_meta_ingress_port__st4;
  logic [5:0] _padding_0__st5;
  logic [19:0] key_0__st5;
  logic [31:0] tmp__st5;
  logic [31:0] tmp_0__st5;
  logic [31:0] tmp_1__st5;
  logic [8:0] meta_ingress_port_w__st5;
  logic [8:0] meta_egress_port_w__st5;
  logic [31:0] meta_packet_length_w__st5;
  logic [2:0] meta_priority_w__st5;
  logic [15:0] meta_mcast_grp_w__st5;
  logic [15:0] meta_egress_rid_w__st5;
  logic [0:0] meta_checksum_error_w__st5;
  logic [31:0] meta_enq_timestamp_w__st5;
  logic [18:0] meta_enq_qdepth_w__st5;
  logic [31:0] meta_deq_timedelta_w__st5;
  logic [18:0] meta_deq_qdepth_w__st5;
  logic [47:0] meta_ingress_global_timestamp_w__st5;
  logic [47:0] meta_egress_global_timestamp_w__st5;
  logic [7:0] meta_ttl_w__st5;
  logic [31:0] meta_next_hop_w__st5;
  logic [15:0] meta_mpls_label_swap_w__st5;
  logic [0:0] meta_drop_w__st5;
  logic [0:0] meta_ecmp_select_w__st5;
  logic ethernet_valid__st5;
  logic ipv4_valid__st5;
  logic tcp_valid__st5;
  logic udp_valid__st5;
  logic mpls_0_valid__st5;
  logic mpls_1_valid__st5;
  logic mpls_2_valid__st5;
  logic [47:0] ethernet_dstAddr__st5;
  logic [47:0] ethernet_srcAddr__st5;
  logic [15:0] ethernet_etherType__st5;
  logic [3:0] ipv4_version__st5;
  logic [3:0] ipv4_ihl__st5;
  logic [7:0] ipv4_diffserv__st5;
  logic [15:0] ipv4_totalLen__st5;
  logic [15:0] ipv4_identification__st5;
  logic [2:0] ipv4_flags__st5;
  logic [12:0] ipv4_fragOffset__st5;
  logic [7:0] ipv4_ttl__st5;
  logic [7:0] ipv4_protocol__st5;
  logic [15:0] ipv4_hdrChecksum__st5;
  logic [31:0] ipv4_srcAddr__st5;
  logic [31:0] ipv4_dstAddr__st5;
  logic [15:0] tcp_srcPort__st5;
  logic [15:0] tcp_dstPort__st5;
  logic [31:0] tcp_seqNo__st5;
  logic [31:0] tcp_ackNo__st5;
  logic [3:0] tcp_dataOffset__st5;
  logic [3:0] tcp_reserved__st5;
  logic [7:0] tcp_flags__st5;
  logic [15:0] tcp_window__st5;
  logic [15:0] tcp_checksum__st5;
  logic [15:0] tcp_urgentPtr__st5;
  logic [15:0] udp_srcPort__st5;
  logic [15:0] udp_dstPort__st5;
  logic [15:0] udp_length__st5;
  logic [15:0] udp_checksum__st5;
  logic [19:0] mpls_0_label__st5;
  logic [2:0] mpls_0_tc__st5;
  logic [0:0] mpls_0_bos__st5;
  logic [7:0] mpls_0_ttl__st5;
  logic [19:0] mpls_1_label__st5;
  logic [2:0] mpls_1_tc__st5;
  logic [0:0] mpls_1_bos__st5;
  logic [7:0] mpls_1_ttl__st5;
  logic [19:0] mpls_2_label__st5;
  logic [2:0] mpls_2_tc__st5;
  logic [0:0] mpls_2_bos__st5;
  logic [7:0] mpls_2_ttl__st5;
  logic [8:0] std_meta_ingress_port__st5;
  logic [5:0] _padding_0__st6;
  logic [19:0] key_0__st6;
  logic [31:0] tmp__st6;
  logic [31:0] tmp_0__st6;
  logic [31:0] tmp_1__st6;
  logic [8:0] meta_ingress_port_w__st6;
  logic [8:0] meta_egress_port_w__st6;
  logic [31:0] meta_packet_length_w__st6;
  logic [2:0] meta_priority_w__st6;
  logic [15:0] meta_mcast_grp_w__st6;
  logic [15:0] meta_egress_rid_w__st6;
  logic [0:0] meta_checksum_error_w__st6;
  logic [31:0] meta_enq_timestamp_w__st6;
  logic [18:0] meta_enq_qdepth_w__st6;
  logic [31:0] meta_deq_timedelta_w__st6;
  logic [18:0] meta_deq_qdepth_w__st6;
  logic [47:0] meta_ingress_global_timestamp_w__st6;
  logic [47:0] meta_egress_global_timestamp_w__st6;
  logic [7:0] meta_ttl_w__st6;
  logic [31:0] meta_next_hop_w__st6;
  logic [15:0] meta_mpls_label_swap_w__st6;
  logic [0:0] meta_drop_w__st6;
  logic [0:0] meta_ecmp_select_w__st6;
  logic ethernet_valid__st6;
  logic ipv4_valid__st6;
  logic tcp_valid__st6;
  logic udp_valid__st6;
  logic mpls_0_valid__st6;
  logic mpls_1_valid__st6;
  logic mpls_2_valid__st6;
  logic [47:0] ethernet_dstAddr__st6;
  logic [47:0] ethernet_srcAddr__st6;
  logic [15:0] ethernet_etherType__st6;
  logic [3:0] ipv4_version__st6;
  logic [3:0] ipv4_ihl__st6;
  logic [7:0] ipv4_diffserv__st6;
  logic [15:0] ipv4_totalLen__st6;
  logic [15:0] ipv4_identification__st6;
  logic [2:0] ipv4_flags__st6;
  logic [12:0] ipv4_fragOffset__st6;
  logic [7:0] ipv4_ttl__st6;
  logic [7:0] ipv4_protocol__st6;
  logic [15:0] ipv4_hdrChecksum__st6;
  logic [31:0] ipv4_srcAddr__st6;
  logic [31:0] ipv4_dstAddr__st6;
  logic [15:0] tcp_srcPort__st6;
  logic [15:0] tcp_dstPort__st6;
  logic [31:0] tcp_seqNo__st6;
  logic [31:0] tcp_ackNo__st6;
  logic [3:0] tcp_dataOffset__st6;
  logic [3:0] tcp_reserved__st6;
  logic [7:0] tcp_flags__st6;
  logic [15:0] tcp_window__st6;
  logic [15:0] tcp_checksum__st6;
  logic [15:0] tcp_urgentPtr__st6;
  logic [15:0] udp_srcPort__st6;
  logic [15:0] udp_dstPort__st6;
  logic [15:0] udp_length__st6;
  logic [15:0] udp_checksum__st6;
  logic [19:0] mpls_0_label__st6;
  logic [2:0] mpls_0_tc__st6;
  logic [0:0] mpls_0_bos__st6;
  logic [7:0] mpls_0_ttl__st6;
  logic [19:0] mpls_1_label__st6;
  logic [2:0] mpls_1_tc__st6;
  logic [0:0] mpls_1_bos__st6;
  logic [7:0] mpls_1_ttl__st6;
  logic [19:0] mpls_2_label__st6;
  logic [2:0] mpls_2_tc__st6;
  logic [0:0] mpls_2_bos__st6;
  logic [7:0] mpls_2_ttl__st6;
  logic [8:0] std_meta_ingress_port__st6;
  logic [5:0] _padding_0__st7;
  logic [19:0] key_0__st7;
  logic [31:0] tmp__st7;
  logic [31:0] tmp_0__st7;
  logic [31:0] tmp_1__st7;
  logic [8:0] meta_ingress_port_w__st7;
  logic [8:0] meta_egress_port_w__st7;
  logic [31:0] meta_packet_length_w__st7;
  logic [2:0] meta_priority_w__st7;
  logic [15:0] meta_mcast_grp_w__st7;
  logic [15:0] meta_egress_rid_w__st7;
  logic [0:0] meta_checksum_error_w__st7;
  logic [31:0] meta_enq_timestamp_w__st7;
  logic [18:0] meta_enq_qdepth_w__st7;
  logic [31:0] meta_deq_timedelta_w__st7;
  logic [18:0] meta_deq_qdepth_w__st7;
  logic [47:0] meta_ingress_global_timestamp_w__st7;
  logic [47:0] meta_egress_global_timestamp_w__st7;
  logic [7:0] meta_ttl_w__st7;
  logic [31:0] meta_next_hop_w__st7;
  logic [15:0] meta_mpls_label_swap_w__st7;
  logic [0:0] meta_drop_w__st7;
  logic [0:0] meta_ecmp_select_w__st7;
  logic ethernet_valid__st7;
  logic ipv4_valid__st7;
  logic tcp_valid__st7;
  logic udp_valid__st7;
  logic mpls_0_valid__st7;
  logic mpls_1_valid__st7;
  logic mpls_2_valid__st7;
  logic [47:0] ethernet_dstAddr__st7;
  logic [47:0] ethernet_srcAddr__st7;
  logic [15:0] ethernet_etherType__st7;
  logic [3:0] ipv4_version__st7;
  logic [3:0] ipv4_ihl__st7;
  logic [7:0] ipv4_diffserv__st7;
  logic [15:0] ipv4_totalLen__st7;
  logic [15:0] ipv4_identification__st7;
  logic [2:0] ipv4_flags__st7;
  logic [12:0] ipv4_fragOffset__st7;
  logic [7:0] ipv4_ttl__st7;
  logic [7:0] ipv4_protocol__st7;
  logic [15:0] ipv4_hdrChecksum__st7;
  logic [31:0] ipv4_srcAddr__st7;
  logic [31:0] ipv4_dstAddr__st7;
  logic [15:0] tcp_srcPort__st7;
  logic [15:0] tcp_dstPort__st7;
  logic [31:0] tcp_seqNo__st7;
  logic [31:0] tcp_ackNo__st7;
  logic [3:0] tcp_dataOffset__st7;
  logic [3:0] tcp_reserved__st7;
  logic [7:0] tcp_flags__st7;
  logic [15:0] tcp_window__st7;
  logic [15:0] tcp_checksum__st7;
  logic [15:0] tcp_urgentPtr__st7;
  logic [15:0] udp_srcPort__st7;
  logic [15:0] udp_dstPort__st7;
  logic [15:0] udp_length__st7;
  logic [15:0] udp_checksum__st7;
  logic [19:0] mpls_0_label__st7;
  logic [2:0] mpls_0_tc__st7;
  logic [0:0] mpls_0_bos__st7;
  logic [7:0] mpls_0_ttl__st7;
  logic [19:0] mpls_1_label__st7;
  logic [2:0] mpls_1_tc__st7;
  logic [0:0] mpls_1_bos__st7;
  logic [7:0] mpls_1_ttl__st7;
  logic [19:0] mpls_2_label__st7;
  logic [2:0] mpls_2_tc__st7;
  logic [0:0] mpls_2_bos__st7;
  logic [7:0] mpls_2_ttl__st7;
  logic [8:0] std_meta_ingress_port__st7;
  logic [5:0] _padding_0__st8;
  logic [19:0] key_0__st8;
  logic [31:0] tmp__st8;
  logic [31:0] tmp_0__st8;
  logic [31:0] tmp_1__st8;
  logic [8:0] meta_ingress_port_w__st8;
  logic [8:0] meta_egress_port_w__st8;
  logic [31:0] meta_packet_length_w__st8;
  logic [2:0] meta_priority_w__st8;
  logic [15:0] meta_mcast_grp_w__st8;
  logic [15:0] meta_egress_rid_w__st8;
  logic [0:0] meta_checksum_error_w__st8;
  logic [31:0] meta_enq_timestamp_w__st8;
  logic [18:0] meta_enq_qdepth_w__st8;
  logic [31:0] meta_deq_timedelta_w__st8;
  logic [18:0] meta_deq_qdepth_w__st8;
  logic [47:0] meta_ingress_global_timestamp_w__st8;
  logic [47:0] meta_egress_global_timestamp_w__st8;
  logic [7:0] meta_ttl_w__st8;
  logic [31:0] meta_next_hop_w__st8;
  logic [15:0] meta_mpls_label_swap_w__st8;
  logic [0:0] meta_drop_w__st8;
  logic [0:0] meta_ecmp_select_w__st8;
  logic ethernet_valid__st8;
  logic ipv4_valid__st8;
  logic tcp_valid__st8;
  logic udp_valid__st8;
  logic mpls_0_valid__st8;
  logic mpls_1_valid__st8;
  logic mpls_2_valid__st8;
  logic [47:0] ethernet_dstAddr__st8;
  logic [47:0] ethernet_srcAddr__st8;
  logic [15:0] ethernet_etherType__st8;
  logic [3:0] ipv4_version__st8;
  logic [3:0] ipv4_ihl__st8;
  logic [7:0] ipv4_diffserv__st8;
  logic [15:0] ipv4_totalLen__st8;
  logic [15:0] ipv4_identification__st8;
  logic [2:0] ipv4_flags__st8;
  logic [12:0] ipv4_fragOffset__st8;
  logic [7:0] ipv4_ttl__st8;
  logic [7:0] ipv4_protocol__st8;
  logic [15:0] ipv4_hdrChecksum__st8;
  logic [31:0] ipv4_srcAddr__st8;
  logic [31:0] ipv4_dstAddr__st8;
  logic [15:0] tcp_srcPort__st8;
  logic [15:0] tcp_dstPort__st8;
  logic [31:0] tcp_seqNo__st8;
  logic [31:0] tcp_ackNo__st8;
  logic [3:0] tcp_dataOffset__st8;
  logic [3:0] tcp_reserved__st8;
  logic [7:0] tcp_flags__st8;
  logic [15:0] tcp_window__st8;
  logic [15:0] tcp_checksum__st8;
  logic [15:0] tcp_urgentPtr__st8;
  logic [15:0] udp_srcPort__st8;
  logic [15:0] udp_dstPort__st8;
  logic [15:0] udp_length__st8;
  logic [15:0] udp_checksum__st8;
  logic [19:0] mpls_0_label__st8;
  logic [2:0] mpls_0_tc__st8;
  logic [0:0] mpls_0_bos__st8;
  logic [7:0] mpls_0_ttl__st8;
  logic [19:0] mpls_1_label__st8;
  logic [2:0] mpls_1_tc__st8;
  logic [0:0] mpls_1_bos__st8;
  logic [7:0] mpls_1_ttl__st8;
  logic [19:0] mpls_2_label__st8;
  logic [2:0] mpls_2_tc__st8;
  logic [0:0] mpls_2_bos__st8;
  logic [7:0] mpls_2_ttl__st8;
  logic [8:0] std_meta_ingress_port__st8;

  // conn_state: register<bit<8>>(1024)
  logic [7:0] conn_state_mem [0:1023];
  logic        conn_state_wr_en;
  logic [9:0] conn_state_wr_addr;
  logic [7:0] conn_state_wr_data;

  // Zero all register memories at simulation start
  // synthesis translate_off
  initial begin
    for (int _si = 0; _si < 1024; _si++)
      conn_state_mem[_si] = 8'b0;
  end
  // synthesis translate_on

  // Register read wires (isolated via assign)
  logic [7:0] conn_state_rd_meta_ttl;
  assign conn_state_rd_meta_ttl = conn_state_mem[tmp__st2];

  // Table lookup result wires
  logic        port_policy_hit;
  logic [0:0] port_policy_act_id;
  logic [8:0] port_policy_p_egress_port;
  logic        mpls_swap_hit;
  logic [1:0] mpls_swap_act_id;
  logic [19:0] mpls_swap_p_new_label;
  logic [19:0] mpls_swap_p_label;
  logic        qos_policy_hit;
  logic [0:0] qos_policy_act_id;
  logic [2:0] qos_policy_p_prio;
  logic        ipv4_route_hit;
  logic [1:0] ipv4_route_act_id;
  logic [31:0] ipv4_route_p_next_hop;
  logic        ecmp_group_hit;
  logic [0:0] ecmp_group_act_id;

  // Table module instantiations
  port_policy_table #(.DEPTH(64)) u_port_policy (
    .clk    (clk),
    .rst_n  (rst_n),
    .lkp_ingress_port    (std_meta_ingress_port),
    .hit       (port_policy_hit),
    .action_id (port_policy_act_id),
    .p_egress_port  (port_policy_p_egress_port),
    .cp_wr_en  (port_policy_cp_wr_en),
    .cp_wr_idx (port_policy_cp_wr_idx),
    .cp_wr_key_ingress_port (port_policy_cp_wr_key_ingress_port),
    .cp_wr_action (port_policy_cp_wr_action),
    .cp_wr_p_egress_port (port_policy_cp_wr_p_egress_port)
  );

  mpls_swap_table #(.DEPTH(512)) u_mpls_swap (
    .clk    (clk),
    .rst_n  (rst_n),
    .lkp_key_0    (key_0),
    .hit       (mpls_swap_hit),
    .action_id (mpls_swap_act_id),
    .p_new_label  (mpls_swap_p_new_label),
    .p_label  (mpls_swap_p_label),
    .cp_wr_en  (mpls_swap_cp_wr_en),
    .cp_wr_idx (mpls_swap_cp_wr_idx),
    .cp_wr_key_key_0 (mpls_swap_cp_wr_key_key_0),
    .cp_wr_action (mpls_swap_cp_wr_action),
    .cp_wr_p_new_label (mpls_swap_cp_wr_p_new_label),
    .cp_wr_p_label (mpls_swap_cp_wr_p_label)
  );

  qos_policy_table #(.DEPTH(256)) u_qos_policy (
    .clk    (clk),
    .rst_n  (rst_n),
    .lkp_diffserv    (ipv4_diffserv),
    .lkp_flags    (tcp_flags),
    .hit       (qos_policy_hit),
    .action_id (qos_policy_act_id),
    .p_prio  (qos_policy_p_prio),
    .cp_wr_en  (qos_policy_cp_wr_en),
    .cp_wr_idx (qos_policy_cp_wr_idx),
    .cp_wr_key_diffserv (qos_policy_cp_wr_key_diffserv),
    .cp_wr_key_flags (qos_policy_cp_wr_key_flags),
    .cp_wr_mask_diffserv (qos_policy_cp_wr_mask_diffserv),
    .cp_wr_mask_flags (qos_policy_cp_wr_mask_flags),
    .cp_wr_action (qos_policy_cp_wr_action),
    .cp_wr_p_prio (qos_policy_cp_wr_p_prio)
  );

  ipv4_route_table #(.DEPTH(1024)) u_ipv4_route (
    .clk    (clk),
    .rst_n  (rst_n),
    .lkp_dstAddr    (ipv4_dstAddr),
    .hit       (ipv4_route_hit),
    .action_id (ipv4_route_act_id),
    .p_next_hop  (ipv4_route_p_next_hop),
    .cp_wr_en  (ipv4_route_cp_wr_en),
    .cp_wr_idx (ipv4_route_cp_wr_idx),
    .cp_wr_key_dstAddr (ipv4_route_cp_wr_key_dstAddr),
    .cp_wr_pfx_len (ipv4_route_cp_wr_pfx_len),
    .cp_wr_action (ipv4_route_cp_wr_action),
    .cp_wr_p_next_hop (ipv4_route_cp_wr_p_next_hop)
  );

  ecmp_group_table u_ecmp_group (
    .clk    (clk),
    .rst_n  (rst_n),
    .hit       (ecmp_group_hit),
    .action_id (ecmp_group_act_id),
    .cp_wr_en  (ecmp_group_cp_wr_en),
    .cp_wr_action (ecmp_group_cp_wr_action)
  );

  // Table hit outputs
  assign port_policy_hit_out = port_policy_hit;
  assign mpls_swap_hit_out = mpls_swap_hit;
  assign qos_policy_hit_out = qos_policy_hit;
  assign ipv4_route_hit_out = ipv4_route_hit;
  assign ecmp_group_hit_out = ecmp_group_hit;

  // Metadata outputs (final value after the last stage)
  assign out_meta_ingress_port = meta_ingress_port_w__st8;
  assign out_meta_egress_port = meta_egress_port_w__st8;
  assign out_meta_packet_length = meta_packet_length_w__st8;
  assign out_meta_priority = meta_priority_w__st8;
  assign out_meta_mcast_grp = meta_mcast_grp_w__st8;
  assign out_meta_egress_rid = meta_egress_rid_w__st8;
  assign out_meta_checksum_error = meta_checksum_error_w__st8;
  assign out_meta_enq_timestamp = meta_enq_timestamp_w__st8;
  assign out_meta_enq_qdepth = meta_enq_qdepth_w__st8;
  assign out_meta_deq_timedelta = meta_deq_timedelta_w__st8;
  assign out_meta_deq_qdepth = meta_deq_qdepth_w__st8;
  assign out_meta_ingress_global_timestamp = meta_ingress_global_timestamp_w__st8;
  assign out_meta_egress_global_timestamp = meta_egress_global_timestamp_w__st8;
  assign out_meta_ttl = meta_ttl_w__st8;
  assign out_meta_next_hop = meta_next_hop_w__st8;
  assign out_meta_mpls_label_swap = meta_mpls_label_swap_w__st8;
  assign out_meta_drop = meta_drop_w__st8;
  assign out_meta_ecmp_select = meta_ecmp_select_w__st8;

  // ---- Pipeline stage 0 (combinational, feeds the first exact-match table boundary) ----
  always_comb begin
    drop__st0 = 0;
    _padding_0 = 6'b0;
    key_0 = 20'b0;
    tmp = 32'b0;
    tmp_0 = 32'b0;
    tmp_1 = 32'b0;

    // Metadata shadow defaults (init from inputs)
    meta_ingress_port_w = meta_ingress_port;
    meta_egress_port_w = meta_egress_port;
    meta_packet_length_w = meta_packet_length;
    meta_priority_w = meta_priority;
    meta_mcast_grp_w = meta_mcast_grp;
    meta_egress_rid_w = meta_egress_rid;
    meta_checksum_error_w = meta_checksum_error;
    meta_enq_timestamp_w = meta_enq_timestamp;
    meta_enq_qdepth_w = meta_enq_qdepth;
    meta_deq_timedelta_w = meta_deq_timedelta;
    meta_deq_qdepth_w = meta_deq_qdepth;
    meta_ingress_global_timestamp_w = meta_ingress_global_timestamp;
    meta_egress_global_timestamp_w = meta_egress_global_timestamp;
    meta_ttl_w = meta_ttl;
    meta_next_hop_w = meta_next_hop;
    meta_mpls_label_swap_w = meta_mpls_label_swap;
    meta_drop_w = meta_drop;
    meta_ecmp_select_w = meta_ecmp_select;
    conn_state_wr_en   = 1'b0;
    conn_state_wr_addr = '0;
    conn_state_wr_data = '0;

    // Standard metadata defaults
    out_std_meta_egress_port__st0 = 9'b0;

    // Header valid flag pass-through defaults
    out_ethernet_valid__st0 = ethernet_valid;
    out_ipv4_valid__st0 = ipv4_valid;
    out_tcp_valid__st0 = tcp_valid;
    out_udp_valid__st0 = udp_valid;
    out_mpls_0_valid__st0 = mpls_0_valid;
    out_mpls_1_valid__st0 = mpls_1_valid;
    out_mpls_2_valid__st0 = mpls_2_valid;

    // Header field pass-through defaults
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
    out_tcp_srcPort__st0 = tcp_srcPort;
    out_tcp_dstPort__st0 = tcp_dstPort;
    out_tcp_seqNo__st0 = tcp_seqNo;
    out_tcp_ackNo__st0 = tcp_ackNo;
    out_tcp_dataOffset__st0 = tcp_dataOffset;
    out_tcp_reserved__st0 = tcp_reserved;
    out_tcp_flags__st0 = tcp_flags;
    out_tcp_window__st0 = tcp_window;
    out_tcp_checksum__st0 = tcp_checksum;
    out_tcp_urgentPtr__st0 = tcp_urgentPtr;
    out_udp_srcPort__st0 = udp_srcPort;
    out_udp_dstPort__st0 = udp_dstPort;
    out_udp_length__st0 = udp_length;
    out_udp_checksum__st0 = udp_checksum;
    out_mpls_0_label__st0 = mpls_0_label;
    out_mpls_0_tc__st0 = mpls_0_tc;
    out_mpls_0_bos__st0 = mpls_0_bos;
    out_mpls_0_ttl__st0 = mpls_0_ttl;
    out_mpls_1_label__st0 = mpls_1_label;
    out_mpls_1_tc__st0 = mpls_1_tc;
    out_mpls_1_bos__st0 = mpls_1_bos;
    out_mpls_1_ttl__st0 = mpls_1_ttl;
    out_mpls_2_label__st0 = mpls_2_label;
    out_mpls_2_tc__st0 = mpls_2_tc;
    out_mpls_2_bos__st0 = mpls_2_bos;
    out_mpls_2_ttl__st0 = mpls_2_ttl;
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
      key_0_s1 <= key_0;
      tmp_s1 <= tmp;
      tmp_0_s1 <= tmp_0;
      tmp_1_s1 <= tmp_1;
      meta_ingress_port_w_s1 <= meta_ingress_port_w;
      meta_egress_port_w_s1 <= meta_egress_port_w;
      meta_packet_length_w_s1 <= meta_packet_length_w;
      meta_priority_w_s1 <= meta_priority_w;
      meta_mcast_grp_w_s1 <= meta_mcast_grp_w;
      meta_egress_rid_w_s1 <= meta_egress_rid_w;
      meta_checksum_error_w_s1 <= meta_checksum_error_w;
      meta_enq_timestamp_w_s1 <= meta_enq_timestamp_w;
      meta_enq_qdepth_w_s1 <= meta_enq_qdepth_w;
      meta_deq_timedelta_w_s1 <= meta_deq_timedelta_w;
      meta_deq_qdepth_w_s1 <= meta_deq_qdepth_w;
      meta_ingress_global_timestamp_w_s1 <= meta_ingress_global_timestamp_w;
      meta_egress_global_timestamp_w_s1 <= meta_egress_global_timestamp_w;
      meta_ttl_w_s1 <= meta_ttl_w;
      meta_next_hop_w_s1 <= meta_next_hop_w;
      meta_mpls_label_swap_w_s1 <= meta_mpls_label_swap_w;
      meta_drop_w_s1 <= meta_drop_w;
      meta_ecmp_select_w_s1 <= meta_ecmp_select_w;
      out_ethernet_valid_s1 <= out_ethernet_valid__st0;
      ethernet_valid_s1 <= ethernet_valid;
      out_ipv4_valid_s1 <= out_ipv4_valid__st0;
      ipv4_valid_s1 <= ipv4_valid;
      out_tcp_valid_s1 <= out_tcp_valid__st0;
      tcp_valid_s1 <= tcp_valid;
      out_udp_valid_s1 <= out_udp_valid__st0;
      udp_valid_s1 <= udp_valid;
      out_mpls_0_valid_s1 <= out_mpls_0_valid__st0;
      mpls_0_valid_s1 <= mpls_0_valid;
      out_mpls_1_valid_s1 <= out_mpls_1_valid__st0;
      mpls_1_valid_s1 <= mpls_1_valid;
      out_mpls_2_valid_s1 <= out_mpls_2_valid__st0;
      mpls_2_valid_s1 <= mpls_2_valid;
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
      out_tcp_srcPort_s1 <= out_tcp_srcPort__st0;
      tcp_srcPort_s1 <= tcp_srcPort;
      out_tcp_dstPort_s1 <= out_tcp_dstPort__st0;
      tcp_dstPort_s1 <= tcp_dstPort;
      out_tcp_seqNo_s1 <= out_tcp_seqNo__st0;
      tcp_seqNo_s1 <= tcp_seqNo;
      out_tcp_ackNo_s1 <= out_tcp_ackNo__st0;
      tcp_ackNo_s1 <= tcp_ackNo;
      out_tcp_dataOffset_s1 <= out_tcp_dataOffset__st0;
      tcp_dataOffset_s1 <= tcp_dataOffset;
      out_tcp_reserved_s1 <= out_tcp_reserved__st0;
      tcp_reserved_s1 <= tcp_reserved;
      out_tcp_flags_s1 <= out_tcp_flags__st0;
      tcp_flags_s1 <= tcp_flags;
      out_tcp_window_s1 <= out_tcp_window__st0;
      tcp_window_s1 <= tcp_window;
      out_tcp_checksum_s1 <= out_tcp_checksum__st0;
      tcp_checksum_s1 <= tcp_checksum;
      out_tcp_urgentPtr_s1 <= out_tcp_urgentPtr__st0;
      tcp_urgentPtr_s1 <= tcp_urgentPtr;
      out_udp_srcPort_s1 <= out_udp_srcPort__st0;
      udp_srcPort_s1 <= udp_srcPort;
      out_udp_dstPort_s1 <= out_udp_dstPort__st0;
      udp_dstPort_s1 <= udp_dstPort;
      out_udp_length_s1 <= out_udp_length__st0;
      udp_length_s1 <= udp_length;
      out_udp_checksum_s1 <= out_udp_checksum__st0;
      udp_checksum_s1 <= udp_checksum;
      out_mpls_0_label_s1 <= out_mpls_0_label__st0;
      mpls_0_label_s1 <= mpls_0_label;
      out_mpls_0_tc_s1 <= out_mpls_0_tc__st0;
      mpls_0_tc_s1 <= mpls_0_tc;
      out_mpls_0_bos_s1 <= out_mpls_0_bos__st0;
      mpls_0_bos_s1 <= mpls_0_bos;
      out_mpls_0_ttl_s1 <= out_mpls_0_ttl__st0;
      mpls_0_ttl_s1 <= mpls_0_ttl;
      out_mpls_1_label_s1 <= out_mpls_1_label__st0;
      mpls_1_label_s1 <= mpls_1_label;
      out_mpls_1_tc_s1 <= out_mpls_1_tc__st0;
      mpls_1_tc_s1 <= mpls_1_tc;
      out_mpls_1_bos_s1 <= out_mpls_1_bos__st0;
      mpls_1_bos_s1 <= mpls_1_bos;
      out_mpls_1_ttl_s1 <= out_mpls_1_ttl__st0;
      mpls_1_ttl_s1 <= mpls_1_ttl;
      out_mpls_2_label_s1 <= out_mpls_2_label__st0;
      mpls_2_label_s1 <= mpls_2_label;
      out_mpls_2_tc_s1 <= out_mpls_2_tc__st0;
      mpls_2_tc_s1 <= mpls_2_tc;
      out_mpls_2_bos_s1 <= out_mpls_2_bos__st0;
      mpls_2_bos_s1 <= mpls_2_bos;
      out_mpls_2_ttl_s1 <= out_mpls_2_ttl__st0;
      mpls_2_ttl_s1 <= mpls_2_ttl;
      out_std_meta_egress_port_s1 <= out_std_meta_egress_port__st0;
      std_meta_ingress_port_s1 <= std_meta_ingress_port;
    end
  end

  // ---- Pipeline stage 1 (registered 1 cycle(s) after stage 0) ----
  always_comb begin
    drop__st1 = drop_s1;
    _padding_0__st1 = _padding_0_s1;
    key_0__st1 = key_0_s1;
    tmp__st1 = tmp_s1;
    tmp_0__st1 = tmp_0_s1;
    tmp_1__st1 = tmp_1_s1;
    meta_ingress_port_w__st1 = meta_ingress_port_w_s1;
    meta_egress_port_w__st1 = meta_egress_port_w_s1;
    meta_packet_length_w__st1 = meta_packet_length_w_s1;
    meta_priority_w__st1 = meta_priority_w_s1;
    meta_mcast_grp_w__st1 = meta_mcast_grp_w_s1;
    meta_egress_rid_w__st1 = meta_egress_rid_w_s1;
    meta_checksum_error_w__st1 = meta_checksum_error_w_s1;
    meta_enq_timestamp_w__st1 = meta_enq_timestamp_w_s1;
    meta_enq_qdepth_w__st1 = meta_enq_qdepth_w_s1;
    meta_deq_timedelta_w__st1 = meta_deq_timedelta_w_s1;
    meta_deq_qdepth_w__st1 = meta_deq_qdepth_w_s1;
    meta_ingress_global_timestamp_w__st1 = meta_ingress_global_timestamp_w_s1;
    meta_egress_global_timestamp_w__st1 = meta_egress_global_timestamp_w_s1;
    meta_ttl_w__st1 = meta_ttl_w_s1;
    meta_next_hop_w__st1 = meta_next_hop_w_s1;
    meta_mpls_label_swap_w__st1 = meta_mpls_label_swap_w_s1;
    meta_drop_w__st1 = meta_drop_w_s1;
    meta_ecmp_select_w__st1 = meta_ecmp_select_w_s1;
    out_ethernet_valid__st1 = out_ethernet_valid_s1;
    ethernet_valid__st1 = ethernet_valid_s1;
    out_ipv4_valid__st1 = out_ipv4_valid_s1;
    ipv4_valid__st1 = ipv4_valid_s1;
    out_tcp_valid__st1 = out_tcp_valid_s1;
    tcp_valid__st1 = tcp_valid_s1;
    out_udp_valid__st1 = out_udp_valid_s1;
    udp_valid__st1 = udp_valid_s1;
    out_mpls_0_valid__st1 = out_mpls_0_valid_s1;
    mpls_0_valid__st1 = mpls_0_valid_s1;
    out_mpls_1_valid__st1 = out_mpls_1_valid_s1;
    mpls_1_valid__st1 = mpls_1_valid_s1;
    out_mpls_2_valid__st1 = out_mpls_2_valid_s1;
    mpls_2_valid__st1 = mpls_2_valid_s1;
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
    out_tcp_srcPort__st1 = out_tcp_srcPort_s1;
    tcp_srcPort__st1 = tcp_srcPort_s1;
    out_tcp_dstPort__st1 = out_tcp_dstPort_s1;
    tcp_dstPort__st1 = tcp_dstPort_s1;
    out_tcp_seqNo__st1 = out_tcp_seqNo_s1;
    tcp_seqNo__st1 = tcp_seqNo_s1;
    out_tcp_ackNo__st1 = out_tcp_ackNo_s1;
    tcp_ackNo__st1 = tcp_ackNo_s1;
    out_tcp_dataOffset__st1 = out_tcp_dataOffset_s1;
    tcp_dataOffset__st1 = tcp_dataOffset_s1;
    out_tcp_reserved__st1 = out_tcp_reserved_s1;
    tcp_reserved__st1 = tcp_reserved_s1;
    out_tcp_flags__st1 = out_tcp_flags_s1;
    tcp_flags__st1 = tcp_flags_s1;
    out_tcp_window__st1 = out_tcp_window_s1;
    tcp_window__st1 = tcp_window_s1;
    out_tcp_checksum__st1 = out_tcp_checksum_s1;
    tcp_checksum__st1 = tcp_checksum_s1;
    out_tcp_urgentPtr__st1 = out_tcp_urgentPtr_s1;
    tcp_urgentPtr__st1 = tcp_urgentPtr_s1;
    out_udp_srcPort__st1 = out_udp_srcPort_s1;
    udp_srcPort__st1 = udp_srcPort_s1;
    out_udp_dstPort__st1 = out_udp_dstPort_s1;
    udp_dstPort__st1 = udp_dstPort_s1;
    out_udp_length__st1 = out_udp_length_s1;
    udp_length__st1 = udp_length_s1;
    out_udp_checksum__st1 = out_udp_checksum_s1;
    udp_checksum__st1 = udp_checksum_s1;
    out_mpls_0_label__st1 = out_mpls_0_label_s1;
    mpls_0_label__st1 = mpls_0_label_s1;
    out_mpls_0_tc__st1 = out_mpls_0_tc_s1;
    mpls_0_tc__st1 = mpls_0_tc_s1;
    out_mpls_0_bos__st1 = out_mpls_0_bos_s1;
    mpls_0_bos__st1 = mpls_0_bos_s1;
    out_mpls_0_ttl__st1 = out_mpls_0_ttl_s1;
    mpls_0_ttl__st1 = mpls_0_ttl_s1;
    out_mpls_1_label__st1 = out_mpls_1_label_s1;
    mpls_1_label__st1 = mpls_1_label_s1;
    out_mpls_1_tc__st1 = out_mpls_1_tc_s1;
    mpls_1_tc__st1 = mpls_1_tc_s1;
    out_mpls_1_bos__st1 = out_mpls_1_bos_s1;
    mpls_1_bos__st1 = mpls_1_bos_s1;
    out_mpls_1_ttl__st1 = out_mpls_1_ttl_s1;
    mpls_1_ttl__st1 = mpls_1_ttl_s1;
    out_mpls_2_label__st1 = out_mpls_2_label_s1;
    mpls_2_label__st1 = mpls_2_label_s1;
    out_mpls_2_tc__st1 = out_mpls_2_tc_s1;
    mpls_2_tc__st1 = mpls_2_tc_s1;
    out_mpls_2_bos__st1 = out_mpls_2_bos_s1;
    mpls_2_bos__st1 = mpls_2_bos_s1;
    out_mpls_2_ttl__st1 = out_mpls_2_ttl_s1;
    mpls_2_ttl__st1 = mpls_2_ttl_s1;
    out_std_meta_egress_port__st1 = out_std_meta_egress_port_s1;
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
      key_0_s2 <= key_0__st1;
      tmp_s2 <= tmp__st1;
      tmp_0_s2 <= tmp_0__st1;
      tmp_1_s2 <= tmp_1__st1;
      meta_ingress_port_w_s2 <= meta_ingress_port_w__st1;
      meta_egress_port_w_s2 <= meta_egress_port_w__st1;
      meta_packet_length_w_s2 <= meta_packet_length_w__st1;
      meta_priority_w_s2 <= meta_priority_w__st1;
      meta_mcast_grp_w_s2 <= meta_mcast_grp_w__st1;
      meta_egress_rid_w_s2 <= meta_egress_rid_w__st1;
      meta_checksum_error_w_s2 <= meta_checksum_error_w__st1;
      meta_enq_timestamp_w_s2 <= meta_enq_timestamp_w__st1;
      meta_enq_qdepth_w_s2 <= meta_enq_qdepth_w__st1;
      meta_deq_timedelta_w_s2 <= meta_deq_timedelta_w__st1;
      meta_deq_qdepth_w_s2 <= meta_deq_qdepth_w__st1;
      meta_ingress_global_timestamp_w_s2 <= meta_ingress_global_timestamp_w__st1;
      meta_egress_global_timestamp_w_s2 <= meta_egress_global_timestamp_w__st1;
      meta_ttl_w_s2 <= meta_ttl_w__st1;
      meta_next_hop_w_s2 <= meta_next_hop_w__st1;
      meta_mpls_label_swap_w_s2 <= meta_mpls_label_swap_w__st1;
      meta_drop_w_s2 <= meta_drop_w__st1;
      meta_ecmp_select_w_s2 <= meta_ecmp_select_w__st1;
      out_ethernet_valid_s2 <= out_ethernet_valid__st1;
      ethernet_valid_s2 <= ethernet_valid__st1;
      out_ipv4_valid_s2 <= out_ipv4_valid__st1;
      ipv4_valid_s2 <= ipv4_valid__st1;
      out_tcp_valid_s2 <= out_tcp_valid__st1;
      tcp_valid_s2 <= tcp_valid__st1;
      out_udp_valid_s2 <= out_udp_valid__st1;
      udp_valid_s2 <= udp_valid__st1;
      out_mpls_0_valid_s2 <= out_mpls_0_valid__st1;
      mpls_0_valid_s2 <= mpls_0_valid__st1;
      out_mpls_1_valid_s2 <= out_mpls_1_valid__st1;
      mpls_1_valid_s2 <= mpls_1_valid__st1;
      out_mpls_2_valid_s2 <= out_mpls_2_valid__st1;
      mpls_2_valid_s2 <= mpls_2_valid__st1;
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
      out_tcp_srcPort_s2 <= out_tcp_srcPort__st1;
      tcp_srcPort_s2 <= tcp_srcPort__st1;
      out_tcp_dstPort_s2 <= out_tcp_dstPort__st1;
      tcp_dstPort_s2 <= tcp_dstPort__st1;
      out_tcp_seqNo_s2 <= out_tcp_seqNo__st1;
      tcp_seqNo_s2 <= tcp_seqNo__st1;
      out_tcp_ackNo_s2 <= out_tcp_ackNo__st1;
      tcp_ackNo_s2 <= tcp_ackNo__st1;
      out_tcp_dataOffset_s2 <= out_tcp_dataOffset__st1;
      tcp_dataOffset_s2 <= tcp_dataOffset__st1;
      out_tcp_reserved_s2 <= out_tcp_reserved__st1;
      tcp_reserved_s2 <= tcp_reserved__st1;
      out_tcp_flags_s2 <= out_tcp_flags__st1;
      tcp_flags_s2 <= tcp_flags__st1;
      out_tcp_window_s2 <= out_tcp_window__st1;
      tcp_window_s2 <= tcp_window__st1;
      out_tcp_checksum_s2 <= out_tcp_checksum__st1;
      tcp_checksum_s2 <= tcp_checksum__st1;
      out_tcp_urgentPtr_s2 <= out_tcp_urgentPtr__st1;
      tcp_urgentPtr_s2 <= tcp_urgentPtr__st1;
      out_udp_srcPort_s2 <= out_udp_srcPort__st1;
      udp_srcPort_s2 <= udp_srcPort__st1;
      out_udp_dstPort_s2 <= out_udp_dstPort__st1;
      udp_dstPort_s2 <= udp_dstPort__st1;
      out_udp_length_s2 <= out_udp_length__st1;
      udp_length_s2 <= udp_length__st1;
      out_udp_checksum_s2 <= out_udp_checksum__st1;
      udp_checksum_s2 <= udp_checksum__st1;
      out_mpls_0_label_s2 <= out_mpls_0_label__st1;
      mpls_0_label_s2 <= mpls_0_label__st1;
      out_mpls_0_tc_s2 <= out_mpls_0_tc__st1;
      mpls_0_tc_s2 <= mpls_0_tc__st1;
      out_mpls_0_bos_s2 <= out_mpls_0_bos__st1;
      mpls_0_bos_s2 <= mpls_0_bos__st1;
      out_mpls_0_ttl_s2 <= out_mpls_0_ttl__st1;
      mpls_0_ttl_s2 <= mpls_0_ttl__st1;
      out_mpls_1_label_s2 <= out_mpls_1_label__st1;
      mpls_1_label_s2 <= mpls_1_label__st1;
      out_mpls_1_tc_s2 <= out_mpls_1_tc__st1;
      mpls_1_tc_s2 <= mpls_1_tc__st1;
      out_mpls_1_bos_s2 <= out_mpls_1_bos__st1;
      mpls_1_bos_s2 <= mpls_1_bos__st1;
      out_mpls_1_ttl_s2 <= out_mpls_1_ttl__st1;
      mpls_1_ttl_s2 <= mpls_1_ttl__st1;
      out_mpls_2_label_s2 <= out_mpls_2_label__st1;
      mpls_2_label_s2 <= mpls_2_label__st1;
      out_mpls_2_tc_s2 <= out_mpls_2_tc__st1;
      mpls_2_tc_s2 <= mpls_2_tc__st1;
      out_mpls_2_bos_s2 <= out_mpls_2_bos__st1;
      mpls_2_bos_s2 <= mpls_2_bos__st1;
      out_mpls_2_ttl_s2 <= out_mpls_2_ttl__st1;
      mpls_2_ttl_s2 <= mpls_2_ttl__st1;
      out_std_meta_egress_port_s2 <= out_std_meta_egress_port__st1;
      std_meta_ingress_port_s2 <= std_meta_ingress_port__st1;
    end
  end

  // ---- Pipeline stage 2 (registered 2 cycle(s) after stage 0) ----
  always_comb begin
    drop__st2 = drop_s2;
    _padding_0__st2 = _padding_0_s2;
    key_0__st2 = key_0_s2;
    tmp__st2 = tmp_s2;
    tmp_0__st2 = tmp_0_s2;
    tmp_1__st2 = tmp_1_s2;
    meta_ingress_port_w__st2 = meta_ingress_port_w_s2;
    meta_egress_port_w__st2 = meta_egress_port_w_s2;
    meta_packet_length_w__st2 = meta_packet_length_w_s2;
    meta_priority_w__st2 = meta_priority_w_s2;
    meta_mcast_grp_w__st2 = meta_mcast_grp_w_s2;
    meta_egress_rid_w__st2 = meta_egress_rid_w_s2;
    meta_checksum_error_w__st2 = meta_checksum_error_w_s2;
    meta_enq_timestamp_w__st2 = meta_enq_timestamp_w_s2;
    meta_enq_qdepth_w__st2 = meta_enq_qdepth_w_s2;
    meta_deq_timedelta_w__st2 = meta_deq_timedelta_w_s2;
    meta_deq_qdepth_w__st2 = meta_deq_qdepth_w_s2;
    meta_ingress_global_timestamp_w__st2 = meta_ingress_global_timestamp_w_s2;
    meta_egress_global_timestamp_w__st2 = meta_egress_global_timestamp_w_s2;
    meta_ttl_w__st2 = meta_ttl_w_s2;
    meta_next_hop_w__st2 = meta_next_hop_w_s2;
    meta_mpls_label_swap_w__st2 = meta_mpls_label_swap_w_s2;
    meta_drop_w__st2 = meta_drop_w_s2;
    meta_ecmp_select_w__st2 = meta_ecmp_select_w_s2;
    out_ethernet_valid__st2 = out_ethernet_valid_s2;
    ethernet_valid__st2 = ethernet_valid_s2;
    out_ipv4_valid__st2 = out_ipv4_valid_s2;
    ipv4_valid__st2 = ipv4_valid_s2;
    out_tcp_valid__st2 = out_tcp_valid_s2;
    tcp_valid__st2 = tcp_valid_s2;
    out_udp_valid__st2 = out_udp_valid_s2;
    udp_valid__st2 = udp_valid_s2;
    out_mpls_0_valid__st2 = out_mpls_0_valid_s2;
    mpls_0_valid__st2 = mpls_0_valid_s2;
    out_mpls_1_valid__st2 = out_mpls_1_valid_s2;
    mpls_1_valid__st2 = mpls_1_valid_s2;
    out_mpls_2_valid__st2 = out_mpls_2_valid_s2;
    mpls_2_valid__st2 = mpls_2_valid_s2;
    out_ethernet_dstAddr__st2 = out_ethernet_dstAddr_s2;
    ethernet_dstAddr__st2 = ethernet_dstAddr_s2;
    out_ethernet_srcAddr__st2 = out_ethernet_srcAddr_s2;
    ethernet_srcAddr__st2 = ethernet_srcAddr_s2;
    out_ethernet_etherType__st2 = out_ethernet_etherType_s2;
    ethernet_etherType__st2 = ethernet_etherType_s2;
    out_ipv4_version__st2 = out_ipv4_version_s2;
    ipv4_version__st2 = ipv4_version_s2;
    out_ipv4_ihl__st2 = out_ipv4_ihl_s2;
    ipv4_ihl__st2 = ipv4_ihl_s2;
    out_ipv4_diffserv__st2 = out_ipv4_diffserv_s2;
    ipv4_diffserv__st2 = ipv4_diffserv_s2;
    out_ipv4_totalLen__st2 = out_ipv4_totalLen_s2;
    ipv4_totalLen__st2 = ipv4_totalLen_s2;
    out_ipv4_identification__st2 = out_ipv4_identification_s2;
    ipv4_identification__st2 = ipv4_identification_s2;
    out_ipv4_flags__st2 = out_ipv4_flags_s2;
    ipv4_flags__st2 = ipv4_flags_s2;
    out_ipv4_fragOffset__st2 = out_ipv4_fragOffset_s2;
    ipv4_fragOffset__st2 = ipv4_fragOffset_s2;
    out_ipv4_ttl__st2 = out_ipv4_ttl_s2;
    ipv4_ttl__st2 = ipv4_ttl_s2;
    out_ipv4_protocol__st2 = out_ipv4_protocol_s2;
    ipv4_protocol__st2 = ipv4_protocol_s2;
    out_ipv4_hdrChecksum__st2 = out_ipv4_hdrChecksum_s2;
    ipv4_hdrChecksum__st2 = ipv4_hdrChecksum_s2;
    out_ipv4_srcAddr__st2 = out_ipv4_srcAddr_s2;
    ipv4_srcAddr__st2 = ipv4_srcAddr_s2;
    out_ipv4_dstAddr__st2 = out_ipv4_dstAddr_s2;
    ipv4_dstAddr__st2 = ipv4_dstAddr_s2;
    out_tcp_srcPort__st2 = out_tcp_srcPort_s2;
    tcp_srcPort__st2 = tcp_srcPort_s2;
    out_tcp_dstPort__st2 = out_tcp_dstPort_s2;
    tcp_dstPort__st2 = tcp_dstPort_s2;
    out_tcp_seqNo__st2 = out_tcp_seqNo_s2;
    tcp_seqNo__st2 = tcp_seqNo_s2;
    out_tcp_ackNo__st2 = out_tcp_ackNo_s2;
    tcp_ackNo__st2 = tcp_ackNo_s2;
    out_tcp_dataOffset__st2 = out_tcp_dataOffset_s2;
    tcp_dataOffset__st2 = tcp_dataOffset_s2;
    out_tcp_reserved__st2 = out_tcp_reserved_s2;
    tcp_reserved__st2 = tcp_reserved_s2;
    out_tcp_flags__st2 = out_tcp_flags_s2;
    tcp_flags__st2 = tcp_flags_s2;
    out_tcp_window__st2 = out_tcp_window_s2;
    tcp_window__st2 = tcp_window_s2;
    out_tcp_checksum__st2 = out_tcp_checksum_s2;
    tcp_checksum__st2 = tcp_checksum_s2;
    out_tcp_urgentPtr__st2 = out_tcp_urgentPtr_s2;
    tcp_urgentPtr__st2 = tcp_urgentPtr_s2;
    out_udp_srcPort__st2 = out_udp_srcPort_s2;
    udp_srcPort__st2 = udp_srcPort_s2;
    out_udp_dstPort__st2 = out_udp_dstPort_s2;
    udp_dstPort__st2 = udp_dstPort_s2;
    out_udp_length__st2 = out_udp_length_s2;
    udp_length__st2 = udp_length_s2;
    out_udp_checksum__st2 = out_udp_checksum_s2;
    udp_checksum__st2 = udp_checksum_s2;
    out_mpls_0_label__st2 = out_mpls_0_label_s2;
    mpls_0_label__st2 = mpls_0_label_s2;
    out_mpls_0_tc__st2 = out_mpls_0_tc_s2;
    mpls_0_tc__st2 = mpls_0_tc_s2;
    out_mpls_0_bos__st2 = out_mpls_0_bos_s2;
    mpls_0_bos__st2 = mpls_0_bos_s2;
    out_mpls_0_ttl__st2 = out_mpls_0_ttl_s2;
    mpls_0_ttl__st2 = mpls_0_ttl_s2;
    out_mpls_1_label__st2 = out_mpls_1_label_s2;
    mpls_1_label__st2 = mpls_1_label_s2;
    out_mpls_1_tc__st2 = out_mpls_1_tc_s2;
    mpls_1_tc__st2 = mpls_1_tc_s2;
    out_mpls_1_bos__st2 = out_mpls_1_bos_s2;
    mpls_1_bos__st2 = mpls_1_bos_s2;
    out_mpls_1_ttl__st2 = out_mpls_1_ttl_s2;
    mpls_1_ttl__st2 = mpls_1_ttl_s2;
    out_mpls_2_label__st2 = out_mpls_2_label_s2;
    mpls_2_label__st2 = mpls_2_label_s2;
    out_mpls_2_tc__st2 = out_mpls_2_tc_s2;
    mpls_2_tc__st2 = mpls_2_tc_s2;
    out_mpls_2_bos__st2 = out_mpls_2_bos_s2;
    mpls_2_bos__st2 = mpls_2_bos_s2;
    out_mpls_2_ttl__st2 = out_mpls_2_ttl_s2;
    mpls_2_ttl__st2 = mpls_2_ttl_s2;
    out_std_meta_egress_port__st2 = out_std_meta_egress_port_s2;
    std_meta_ingress_port__st2 = std_meta_ingress_port_s2;

    // apply block (stage 2 of 8)
    // port_policy.apply()
    if (port_policy_hit) begin
      unique case (port_policy_act_id)
        1'd0: ; // NoAction
        1'd1: begin // set_egress_port
          out_std_meta_egress_port__st2 = port_policy_p_egress_port;
        end
        default: ; // default = NoAction
      endcase
    end
    if (tcp_valid__st2) begin
      tmp__st2 = (((tcp_srcPort__st2 & 'hFFFFFFFF) ^ (tcp_dstPort__st2 & 'hFFFFFFFF)) & 'h000003FF);
      meta_ttl_w__st2 = conn_state_rd_meta_ttl;
      if ((meta_ttl_w__st2 == 'h01)) begin
        meta_priority_w__st2 = 'h01;
      end
    end
    if (mpls_0_valid__st2) begin
      key_0__st2 = mpls_0_label__st2;
    end
  end

  // Forward stage-2 state into stage-3 registers (1-cycle
  // boundary — matches the exact-match table's registered latency)
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      valid_s3 <= 1'b0;
    end else begin
      valid_s3 <= valid_s2;
      drop_s3 <= drop__st2;
      _padding_0_s3 <= _padding_0__st2;
      key_0_s3 <= key_0__st2;
      tmp_s3 <= tmp__st2;
      tmp_0_s3 <= tmp_0__st2;
      tmp_1_s3 <= tmp_1__st2;
      meta_ingress_port_w_s3 <= meta_ingress_port_w__st2;
      meta_egress_port_w_s3 <= meta_egress_port_w__st2;
      meta_packet_length_w_s3 <= meta_packet_length_w__st2;
      meta_priority_w_s3 <= meta_priority_w__st2;
      meta_mcast_grp_w_s3 <= meta_mcast_grp_w__st2;
      meta_egress_rid_w_s3 <= meta_egress_rid_w__st2;
      meta_checksum_error_w_s3 <= meta_checksum_error_w__st2;
      meta_enq_timestamp_w_s3 <= meta_enq_timestamp_w__st2;
      meta_enq_qdepth_w_s3 <= meta_enq_qdepth_w__st2;
      meta_deq_timedelta_w_s3 <= meta_deq_timedelta_w__st2;
      meta_deq_qdepth_w_s3 <= meta_deq_qdepth_w__st2;
      meta_ingress_global_timestamp_w_s3 <= meta_ingress_global_timestamp_w__st2;
      meta_egress_global_timestamp_w_s3 <= meta_egress_global_timestamp_w__st2;
      meta_ttl_w_s3 <= meta_ttl_w__st2;
      meta_next_hop_w_s3 <= meta_next_hop_w__st2;
      meta_mpls_label_swap_w_s3 <= meta_mpls_label_swap_w__st2;
      meta_drop_w_s3 <= meta_drop_w__st2;
      meta_ecmp_select_w_s3 <= meta_ecmp_select_w__st2;
      out_ethernet_valid_s3 <= out_ethernet_valid__st2;
      ethernet_valid_s3 <= ethernet_valid__st2;
      out_ipv4_valid_s3 <= out_ipv4_valid__st2;
      ipv4_valid_s3 <= ipv4_valid__st2;
      out_tcp_valid_s3 <= out_tcp_valid__st2;
      tcp_valid_s3 <= tcp_valid__st2;
      out_udp_valid_s3 <= out_udp_valid__st2;
      udp_valid_s3 <= udp_valid__st2;
      out_mpls_0_valid_s3 <= out_mpls_0_valid__st2;
      mpls_0_valid_s3 <= mpls_0_valid__st2;
      out_mpls_1_valid_s3 <= out_mpls_1_valid__st2;
      mpls_1_valid_s3 <= mpls_1_valid__st2;
      out_mpls_2_valid_s3 <= out_mpls_2_valid__st2;
      mpls_2_valid_s3 <= mpls_2_valid__st2;
      out_ethernet_dstAddr_s3 <= out_ethernet_dstAddr__st2;
      ethernet_dstAddr_s3 <= ethernet_dstAddr__st2;
      out_ethernet_srcAddr_s3 <= out_ethernet_srcAddr__st2;
      ethernet_srcAddr_s3 <= ethernet_srcAddr__st2;
      out_ethernet_etherType_s3 <= out_ethernet_etherType__st2;
      ethernet_etherType_s3 <= ethernet_etherType__st2;
      out_ipv4_version_s3 <= out_ipv4_version__st2;
      ipv4_version_s3 <= ipv4_version__st2;
      out_ipv4_ihl_s3 <= out_ipv4_ihl__st2;
      ipv4_ihl_s3 <= ipv4_ihl__st2;
      out_ipv4_diffserv_s3 <= out_ipv4_diffserv__st2;
      ipv4_diffserv_s3 <= ipv4_diffserv__st2;
      out_ipv4_totalLen_s3 <= out_ipv4_totalLen__st2;
      ipv4_totalLen_s3 <= ipv4_totalLen__st2;
      out_ipv4_identification_s3 <= out_ipv4_identification__st2;
      ipv4_identification_s3 <= ipv4_identification__st2;
      out_ipv4_flags_s3 <= out_ipv4_flags__st2;
      ipv4_flags_s3 <= ipv4_flags__st2;
      out_ipv4_fragOffset_s3 <= out_ipv4_fragOffset__st2;
      ipv4_fragOffset_s3 <= ipv4_fragOffset__st2;
      out_ipv4_ttl_s3 <= out_ipv4_ttl__st2;
      ipv4_ttl_s3 <= ipv4_ttl__st2;
      out_ipv4_protocol_s3 <= out_ipv4_protocol__st2;
      ipv4_protocol_s3 <= ipv4_protocol__st2;
      out_ipv4_hdrChecksum_s3 <= out_ipv4_hdrChecksum__st2;
      ipv4_hdrChecksum_s3 <= ipv4_hdrChecksum__st2;
      out_ipv4_srcAddr_s3 <= out_ipv4_srcAddr__st2;
      ipv4_srcAddr_s3 <= ipv4_srcAddr__st2;
      out_ipv4_dstAddr_s3 <= out_ipv4_dstAddr__st2;
      ipv4_dstAddr_s3 <= ipv4_dstAddr__st2;
      out_tcp_srcPort_s3 <= out_tcp_srcPort__st2;
      tcp_srcPort_s3 <= tcp_srcPort__st2;
      out_tcp_dstPort_s3 <= out_tcp_dstPort__st2;
      tcp_dstPort_s3 <= tcp_dstPort__st2;
      out_tcp_seqNo_s3 <= out_tcp_seqNo__st2;
      tcp_seqNo_s3 <= tcp_seqNo__st2;
      out_tcp_ackNo_s3 <= out_tcp_ackNo__st2;
      tcp_ackNo_s3 <= tcp_ackNo__st2;
      out_tcp_dataOffset_s3 <= out_tcp_dataOffset__st2;
      tcp_dataOffset_s3 <= tcp_dataOffset__st2;
      out_tcp_reserved_s3 <= out_tcp_reserved__st2;
      tcp_reserved_s3 <= tcp_reserved__st2;
      out_tcp_flags_s3 <= out_tcp_flags__st2;
      tcp_flags_s3 <= tcp_flags__st2;
      out_tcp_window_s3 <= out_tcp_window__st2;
      tcp_window_s3 <= tcp_window__st2;
      out_tcp_checksum_s3 <= out_tcp_checksum__st2;
      tcp_checksum_s3 <= tcp_checksum__st2;
      out_tcp_urgentPtr_s3 <= out_tcp_urgentPtr__st2;
      tcp_urgentPtr_s3 <= tcp_urgentPtr__st2;
      out_udp_srcPort_s3 <= out_udp_srcPort__st2;
      udp_srcPort_s3 <= udp_srcPort__st2;
      out_udp_dstPort_s3 <= out_udp_dstPort__st2;
      udp_dstPort_s3 <= udp_dstPort__st2;
      out_udp_length_s3 <= out_udp_length__st2;
      udp_length_s3 <= udp_length__st2;
      out_udp_checksum_s3 <= out_udp_checksum__st2;
      udp_checksum_s3 <= udp_checksum__st2;
      out_mpls_0_label_s3 <= out_mpls_0_label__st2;
      mpls_0_label_s3 <= mpls_0_label__st2;
      out_mpls_0_tc_s3 <= out_mpls_0_tc__st2;
      mpls_0_tc_s3 <= mpls_0_tc__st2;
      out_mpls_0_bos_s3 <= out_mpls_0_bos__st2;
      mpls_0_bos_s3 <= mpls_0_bos__st2;
      out_mpls_0_ttl_s3 <= out_mpls_0_ttl__st2;
      mpls_0_ttl_s3 <= mpls_0_ttl__st2;
      out_mpls_1_label_s3 <= out_mpls_1_label__st2;
      mpls_1_label_s3 <= mpls_1_label__st2;
      out_mpls_1_tc_s3 <= out_mpls_1_tc__st2;
      mpls_1_tc_s3 <= mpls_1_tc__st2;
      out_mpls_1_bos_s3 <= out_mpls_1_bos__st2;
      mpls_1_bos_s3 <= mpls_1_bos__st2;
      out_mpls_1_ttl_s3 <= out_mpls_1_ttl__st2;
      mpls_1_ttl_s3 <= mpls_1_ttl__st2;
      out_mpls_2_label_s3 <= out_mpls_2_label__st2;
      mpls_2_label_s3 <= mpls_2_label__st2;
      out_mpls_2_tc_s3 <= out_mpls_2_tc__st2;
      mpls_2_tc_s3 <= mpls_2_tc__st2;
      out_mpls_2_bos_s3 <= out_mpls_2_bos__st2;
      mpls_2_bos_s3 <= mpls_2_bos__st2;
      out_mpls_2_ttl_s3 <= out_mpls_2_ttl__st2;
      mpls_2_ttl_s3 <= mpls_2_ttl__st2;
      out_std_meta_egress_port_s3 <= out_std_meta_egress_port__st2;
      std_meta_ingress_port_s3 <= std_meta_ingress_port__st2;
      __stage_cond_0_r <= (mpls_0_valid__st2);
    end
  end

  // ---- Pipeline stage 3 (registered 3 cycle(s) after stage 0) ----
  always_comb begin
    drop__st3 = drop_s3;
    _padding_0__st3 = _padding_0_s3;
    key_0__st3 = key_0_s3;
    tmp__st3 = tmp_s3;
    tmp_0__st3 = tmp_0_s3;
    tmp_1__st3 = tmp_1_s3;
    meta_ingress_port_w__st3 = meta_ingress_port_w_s3;
    meta_egress_port_w__st3 = meta_egress_port_w_s3;
    meta_packet_length_w__st3 = meta_packet_length_w_s3;
    meta_priority_w__st3 = meta_priority_w_s3;
    meta_mcast_grp_w__st3 = meta_mcast_grp_w_s3;
    meta_egress_rid_w__st3 = meta_egress_rid_w_s3;
    meta_checksum_error_w__st3 = meta_checksum_error_w_s3;
    meta_enq_timestamp_w__st3 = meta_enq_timestamp_w_s3;
    meta_enq_qdepth_w__st3 = meta_enq_qdepth_w_s3;
    meta_deq_timedelta_w__st3 = meta_deq_timedelta_w_s3;
    meta_deq_qdepth_w__st3 = meta_deq_qdepth_w_s3;
    meta_ingress_global_timestamp_w__st3 = meta_ingress_global_timestamp_w_s3;
    meta_egress_global_timestamp_w__st3 = meta_egress_global_timestamp_w_s3;
    meta_ttl_w__st3 = meta_ttl_w_s3;
    meta_next_hop_w__st3 = meta_next_hop_w_s3;
    meta_mpls_label_swap_w__st3 = meta_mpls_label_swap_w_s3;
    meta_drop_w__st3 = meta_drop_w_s3;
    meta_ecmp_select_w__st3 = meta_ecmp_select_w_s3;
    out_ethernet_valid__st3 = out_ethernet_valid_s3;
    ethernet_valid__st3 = ethernet_valid_s3;
    out_ipv4_valid__st3 = out_ipv4_valid_s3;
    ipv4_valid__st3 = ipv4_valid_s3;
    out_tcp_valid__st3 = out_tcp_valid_s3;
    tcp_valid__st3 = tcp_valid_s3;
    out_udp_valid__st3 = out_udp_valid_s3;
    udp_valid__st3 = udp_valid_s3;
    out_mpls_0_valid__st3 = out_mpls_0_valid_s3;
    mpls_0_valid__st3 = mpls_0_valid_s3;
    out_mpls_1_valid__st3 = out_mpls_1_valid_s3;
    mpls_1_valid__st3 = mpls_1_valid_s3;
    out_mpls_2_valid__st3 = out_mpls_2_valid_s3;
    mpls_2_valid__st3 = mpls_2_valid_s3;
    out_ethernet_dstAddr__st3 = out_ethernet_dstAddr_s3;
    ethernet_dstAddr__st3 = ethernet_dstAddr_s3;
    out_ethernet_srcAddr__st3 = out_ethernet_srcAddr_s3;
    ethernet_srcAddr__st3 = ethernet_srcAddr_s3;
    out_ethernet_etherType__st3 = out_ethernet_etherType_s3;
    ethernet_etherType__st3 = ethernet_etherType_s3;
    out_ipv4_version__st3 = out_ipv4_version_s3;
    ipv4_version__st3 = ipv4_version_s3;
    out_ipv4_ihl__st3 = out_ipv4_ihl_s3;
    ipv4_ihl__st3 = ipv4_ihl_s3;
    out_ipv4_diffserv__st3 = out_ipv4_diffserv_s3;
    ipv4_diffserv__st3 = ipv4_diffserv_s3;
    out_ipv4_totalLen__st3 = out_ipv4_totalLen_s3;
    ipv4_totalLen__st3 = ipv4_totalLen_s3;
    out_ipv4_identification__st3 = out_ipv4_identification_s3;
    ipv4_identification__st3 = ipv4_identification_s3;
    out_ipv4_flags__st3 = out_ipv4_flags_s3;
    ipv4_flags__st3 = ipv4_flags_s3;
    out_ipv4_fragOffset__st3 = out_ipv4_fragOffset_s3;
    ipv4_fragOffset__st3 = ipv4_fragOffset_s3;
    out_ipv4_ttl__st3 = out_ipv4_ttl_s3;
    ipv4_ttl__st3 = ipv4_ttl_s3;
    out_ipv4_protocol__st3 = out_ipv4_protocol_s3;
    ipv4_protocol__st3 = ipv4_protocol_s3;
    out_ipv4_hdrChecksum__st3 = out_ipv4_hdrChecksum_s3;
    ipv4_hdrChecksum__st3 = ipv4_hdrChecksum_s3;
    out_ipv4_srcAddr__st3 = out_ipv4_srcAddr_s3;
    ipv4_srcAddr__st3 = ipv4_srcAddr_s3;
    out_ipv4_dstAddr__st3 = out_ipv4_dstAddr_s3;
    ipv4_dstAddr__st3 = ipv4_dstAddr_s3;
    out_tcp_srcPort__st3 = out_tcp_srcPort_s3;
    tcp_srcPort__st3 = tcp_srcPort_s3;
    out_tcp_dstPort__st3 = out_tcp_dstPort_s3;
    tcp_dstPort__st3 = tcp_dstPort_s3;
    out_tcp_seqNo__st3 = out_tcp_seqNo_s3;
    tcp_seqNo__st3 = tcp_seqNo_s3;
    out_tcp_ackNo__st3 = out_tcp_ackNo_s3;
    tcp_ackNo__st3 = tcp_ackNo_s3;
    out_tcp_dataOffset__st3 = out_tcp_dataOffset_s3;
    tcp_dataOffset__st3 = tcp_dataOffset_s3;
    out_tcp_reserved__st3 = out_tcp_reserved_s3;
    tcp_reserved__st3 = tcp_reserved_s3;
    out_tcp_flags__st3 = out_tcp_flags_s3;
    tcp_flags__st3 = tcp_flags_s3;
    out_tcp_window__st3 = out_tcp_window_s3;
    tcp_window__st3 = tcp_window_s3;
    out_tcp_checksum__st3 = out_tcp_checksum_s3;
    tcp_checksum__st3 = tcp_checksum_s3;
    out_tcp_urgentPtr__st3 = out_tcp_urgentPtr_s3;
    tcp_urgentPtr__st3 = tcp_urgentPtr_s3;
    out_udp_srcPort__st3 = out_udp_srcPort_s3;
    udp_srcPort__st3 = udp_srcPort_s3;
    out_udp_dstPort__st3 = out_udp_dstPort_s3;
    udp_dstPort__st3 = udp_dstPort_s3;
    out_udp_length__st3 = out_udp_length_s3;
    udp_length__st3 = udp_length_s3;
    out_udp_checksum__st3 = out_udp_checksum_s3;
    udp_checksum__st3 = udp_checksum_s3;
    out_mpls_0_label__st3 = out_mpls_0_label_s3;
    mpls_0_label__st3 = mpls_0_label_s3;
    out_mpls_0_tc__st3 = out_mpls_0_tc_s3;
    mpls_0_tc__st3 = mpls_0_tc_s3;
    out_mpls_0_bos__st3 = out_mpls_0_bos_s3;
    mpls_0_bos__st3 = mpls_0_bos_s3;
    out_mpls_0_ttl__st3 = out_mpls_0_ttl_s3;
    mpls_0_ttl__st3 = mpls_0_ttl_s3;
    out_mpls_1_label__st3 = out_mpls_1_label_s3;
    mpls_1_label__st3 = mpls_1_label_s3;
    out_mpls_1_tc__st3 = out_mpls_1_tc_s3;
    mpls_1_tc__st3 = mpls_1_tc_s3;
    out_mpls_1_bos__st3 = out_mpls_1_bos_s3;
    mpls_1_bos__st3 = mpls_1_bos_s3;
    out_mpls_1_ttl__st3 = out_mpls_1_ttl_s3;
    mpls_1_ttl__st3 = mpls_1_ttl_s3;
    out_mpls_2_label__st3 = out_mpls_2_label_s3;
    mpls_2_label__st3 = mpls_2_label_s3;
    out_mpls_2_tc__st3 = out_mpls_2_tc_s3;
    mpls_2_tc__st3 = mpls_2_tc_s3;
    out_mpls_2_bos__st3 = out_mpls_2_bos_s3;
    mpls_2_bos__st3 = mpls_2_bos_s3;
    out_mpls_2_ttl__st3 = out_mpls_2_ttl_s3;
    mpls_2_ttl__st3 = mpls_2_ttl_s3;
    out_std_meta_egress_port__st3 = out_std_meta_egress_port_s3;
    std_meta_ingress_port__st3 = std_meta_ingress_port_s3;
  end

  // Forward stage-3 state into stage-4 registers (1-cycle
  // boundary — matches the exact-match table's registered latency)
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      valid_s4 <= 1'b0;
    end else begin
      valid_s4 <= valid_s3;
      drop_s4 <= drop__st3;
      _padding_0_s4 <= _padding_0__st3;
      key_0_s4 <= key_0__st3;
      tmp_s4 <= tmp__st3;
      tmp_0_s4 <= tmp_0__st3;
      tmp_1_s4 <= tmp_1__st3;
      meta_ingress_port_w_s4 <= meta_ingress_port_w__st3;
      meta_egress_port_w_s4 <= meta_egress_port_w__st3;
      meta_packet_length_w_s4 <= meta_packet_length_w__st3;
      meta_priority_w_s4 <= meta_priority_w__st3;
      meta_mcast_grp_w_s4 <= meta_mcast_grp_w__st3;
      meta_egress_rid_w_s4 <= meta_egress_rid_w__st3;
      meta_checksum_error_w_s4 <= meta_checksum_error_w__st3;
      meta_enq_timestamp_w_s4 <= meta_enq_timestamp_w__st3;
      meta_enq_qdepth_w_s4 <= meta_enq_qdepth_w__st3;
      meta_deq_timedelta_w_s4 <= meta_deq_timedelta_w__st3;
      meta_deq_qdepth_w_s4 <= meta_deq_qdepth_w__st3;
      meta_ingress_global_timestamp_w_s4 <= meta_ingress_global_timestamp_w__st3;
      meta_egress_global_timestamp_w_s4 <= meta_egress_global_timestamp_w__st3;
      meta_ttl_w_s4 <= meta_ttl_w__st3;
      meta_next_hop_w_s4 <= meta_next_hop_w__st3;
      meta_mpls_label_swap_w_s4 <= meta_mpls_label_swap_w__st3;
      meta_drop_w_s4 <= meta_drop_w__st3;
      meta_ecmp_select_w_s4 <= meta_ecmp_select_w__st3;
      out_ethernet_valid_s4 <= out_ethernet_valid__st3;
      ethernet_valid_s4 <= ethernet_valid__st3;
      out_ipv4_valid_s4 <= out_ipv4_valid__st3;
      ipv4_valid_s4 <= ipv4_valid__st3;
      out_tcp_valid_s4 <= out_tcp_valid__st3;
      tcp_valid_s4 <= tcp_valid__st3;
      out_udp_valid_s4 <= out_udp_valid__st3;
      udp_valid_s4 <= udp_valid__st3;
      out_mpls_0_valid_s4 <= out_mpls_0_valid__st3;
      mpls_0_valid_s4 <= mpls_0_valid__st3;
      out_mpls_1_valid_s4 <= out_mpls_1_valid__st3;
      mpls_1_valid_s4 <= mpls_1_valid__st3;
      out_mpls_2_valid_s4 <= out_mpls_2_valid__st3;
      mpls_2_valid_s4 <= mpls_2_valid__st3;
      out_ethernet_dstAddr_s4 <= out_ethernet_dstAddr__st3;
      ethernet_dstAddr_s4 <= ethernet_dstAddr__st3;
      out_ethernet_srcAddr_s4 <= out_ethernet_srcAddr__st3;
      ethernet_srcAddr_s4 <= ethernet_srcAddr__st3;
      out_ethernet_etherType_s4 <= out_ethernet_etherType__st3;
      ethernet_etherType_s4 <= ethernet_etherType__st3;
      out_ipv4_version_s4 <= out_ipv4_version__st3;
      ipv4_version_s4 <= ipv4_version__st3;
      out_ipv4_ihl_s4 <= out_ipv4_ihl__st3;
      ipv4_ihl_s4 <= ipv4_ihl__st3;
      out_ipv4_diffserv_s4 <= out_ipv4_diffserv__st3;
      ipv4_diffserv_s4 <= ipv4_diffserv__st3;
      out_ipv4_totalLen_s4 <= out_ipv4_totalLen__st3;
      ipv4_totalLen_s4 <= ipv4_totalLen__st3;
      out_ipv4_identification_s4 <= out_ipv4_identification__st3;
      ipv4_identification_s4 <= ipv4_identification__st3;
      out_ipv4_flags_s4 <= out_ipv4_flags__st3;
      ipv4_flags_s4 <= ipv4_flags__st3;
      out_ipv4_fragOffset_s4 <= out_ipv4_fragOffset__st3;
      ipv4_fragOffset_s4 <= ipv4_fragOffset__st3;
      out_ipv4_ttl_s4 <= out_ipv4_ttl__st3;
      ipv4_ttl_s4 <= ipv4_ttl__st3;
      out_ipv4_protocol_s4 <= out_ipv4_protocol__st3;
      ipv4_protocol_s4 <= ipv4_protocol__st3;
      out_ipv4_hdrChecksum_s4 <= out_ipv4_hdrChecksum__st3;
      ipv4_hdrChecksum_s4 <= ipv4_hdrChecksum__st3;
      out_ipv4_srcAddr_s4 <= out_ipv4_srcAddr__st3;
      ipv4_srcAddr_s4 <= ipv4_srcAddr__st3;
      out_ipv4_dstAddr_s4 <= out_ipv4_dstAddr__st3;
      ipv4_dstAddr_s4 <= ipv4_dstAddr__st3;
      out_tcp_srcPort_s4 <= out_tcp_srcPort__st3;
      tcp_srcPort_s4 <= tcp_srcPort__st3;
      out_tcp_dstPort_s4 <= out_tcp_dstPort__st3;
      tcp_dstPort_s4 <= tcp_dstPort__st3;
      out_tcp_seqNo_s4 <= out_tcp_seqNo__st3;
      tcp_seqNo_s4 <= tcp_seqNo__st3;
      out_tcp_ackNo_s4 <= out_tcp_ackNo__st3;
      tcp_ackNo_s4 <= tcp_ackNo__st3;
      out_tcp_dataOffset_s4 <= out_tcp_dataOffset__st3;
      tcp_dataOffset_s4 <= tcp_dataOffset__st3;
      out_tcp_reserved_s4 <= out_tcp_reserved__st3;
      tcp_reserved_s4 <= tcp_reserved__st3;
      out_tcp_flags_s4 <= out_tcp_flags__st3;
      tcp_flags_s4 <= tcp_flags__st3;
      out_tcp_window_s4 <= out_tcp_window__st3;
      tcp_window_s4 <= tcp_window__st3;
      out_tcp_checksum_s4 <= out_tcp_checksum__st3;
      tcp_checksum_s4 <= tcp_checksum__st3;
      out_tcp_urgentPtr_s4 <= out_tcp_urgentPtr__st3;
      tcp_urgentPtr_s4 <= tcp_urgentPtr__st3;
      out_udp_srcPort_s4 <= out_udp_srcPort__st3;
      udp_srcPort_s4 <= udp_srcPort__st3;
      out_udp_dstPort_s4 <= out_udp_dstPort__st3;
      udp_dstPort_s4 <= udp_dstPort__st3;
      out_udp_length_s4 <= out_udp_length__st3;
      udp_length_s4 <= udp_length__st3;
      out_udp_checksum_s4 <= out_udp_checksum__st3;
      udp_checksum_s4 <= udp_checksum__st3;
      out_mpls_0_label_s4 <= out_mpls_0_label__st3;
      mpls_0_label_s4 <= mpls_0_label__st3;
      out_mpls_0_tc_s4 <= out_mpls_0_tc__st3;
      mpls_0_tc_s4 <= mpls_0_tc__st3;
      out_mpls_0_bos_s4 <= out_mpls_0_bos__st3;
      mpls_0_bos_s4 <= mpls_0_bos__st3;
      out_mpls_0_ttl_s4 <= out_mpls_0_ttl__st3;
      mpls_0_ttl_s4 <= mpls_0_ttl__st3;
      out_mpls_1_label_s4 <= out_mpls_1_label__st3;
      mpls_1_label_s4 <= mpls_1_label__st3;
      out_mpls_1_tc_s4 <= out_mpls_1_tc__st3;
      mpls_1_tc_s4 <= mpls_1_tc__st3;
      out_mpls_1_bos_s4 <= out_mpls_1_bos__st3;
      mpls_1_bos_s4 <= mpls_1_bos__st3;
      out_mpls_1_ttl_s4 <= out_mpls_1_ttl__st3;
      mpls_1_ttl_s4 <= mpls_1_ttl__st3;
      out_mpls_2_label_s4 <= out_mpls_2_label__st3;
      mpls_2_label_s4 <= mpls_2_label__st3;
      out_mpls_2_tc_s4 <= out_mpls_2_tc__st3;
      mpls_2_tc_s4 <= mpls_2_tc__st3;
      out_mpls_2_bos_s4 <= out_mpls_2_bos__st3;
      mpls_2_bos_s4 <= mpls_2_bos__st3;
      out_mpls_2_ttl_s4 <= out_mpls_2_ttl__st3;
      mpls_2_ttl_s4 <= mpls_2_ttl__st3;
      out_std_meta_egress_port_s4 <= out_std_meta_egress_port__st3;
      std_meta_ingress_port_s4 <= std_meta_ingress_port__st3;
    end
  end

  // ---- Pipeline stage 4 (registered 4 cycle(s) after stage 0) ----
  always_comb begin
    drop__st4 = drop_s4;
    _padding_0__st4 = _padding_0_s4;
    key_0__st4 = key_0_s4;
    tmp__st4 = tmp_s4;
    tmp_0__st4 = tmp_0_s4;
    tmp_1__st4 = tmp_1_s4;
    meta_ingress_port_w__st4 = meta_ingress_port_w_s4;
    meta_egress_port_w__st4 = meta_egress_port_w_s4;
    meta_packet_length_w__st4 = meta_packet_length_w_s4;
    meta_priority_w__st4 = meta_priority_w_s4;
    meta_mcast_grp_w__st4 = meta_mcast_grp_w_s4;
    meta_egress_rid_w__st4 = meta_egress_rid_w_s4;
    meta_checksum_error_w__st4 = meta_checksum_error_w_s4;
    meta_enq_timestamp_w__st4 = meta_enq_timestamp_w_s4;
    meta_enq_qdepth_w__st4 = meta_enq_qdepth_w_s4;
    meta_deq_timedelta_w__st4 = meta_deq_timedelta_w_s4;
    meta_deq_qdepth_w__st4 = meta_deq_qdepth_w_s4;
    meta_ingress_global_timestamp_w__st4 = meta_ingress_global_timestamp_w_s4;
    meta_egress_global_timestamp_w__st4 = meta_egress_global_timestamp_w_s4;
    meta_ttl_w__st4 = meta_ttl_w_s4;
    meta_next_hop_w__st4 = meta_next_hop_w_s4;
    meta_mpls_label_swap_w__st4 = meta_mpls_label_swap_w_s4;
    meta_drop_w__st4 = meta_drop_w_s4;
    meta_ecmp_select_w__st4 = meta_ecmp_select_w_s4;
    out_ethernet_valid__st4 = out_ethernet_valid_s4;
    ethernet_valid__st4 = ethernet_valid_s4;
    out_ipv4_valid__st4 = out_ipv4_valid_s4;
    ipv4_valid__st4 = ipv4_valid_s4;
    out_tcp_valid__st4 = out_tcp_valid_s4;
    tcp_valid__st4 = tcp_valid_s4;
    out_udp_valid__st4 = out_udp_valid_s4;
    udp_valid__st4 = udp_valid_s4;
    out_mpls_0_valid__st4 = out_mpls_0_valid_s4;
    mpls_0_valid__st4 = mpls_0_valid_s4;
    out_mpls_1_valid__st4 = out_mpls_1_valid_s4;
    mpls_1_valid__st4 = mpls_1_valid_s4;
    out_mpls_2_valid__st4 = out_mpls_2_valid_s4;
    mpls_2_valid__st4 = mpls_2_valid_s4;
    out_ethernet_dstAddr__st4 = out_ethernet_dstAddr_s4;
    ethernet_dstAddr__st4 = ethernet_dstAddr_s4;
    out_ethernet_srcAddr__st4 = out_ethernet_srcAddr_s4;
    ethernet_srcAddr__st4 = ethernet_srcAddr_s4;
    out_ethernet_etherType__st4 = out_ethernet_etherType_s4;
    ethernet_etherType__st4 = ethernet_etherType_s4;
    out_ipv4_version__st4 = out_ipv4_version_s4;
    ipv4_version__st4 = ipv4_version_s4;
    out_ipv4_ihl__st4 = out_ipv4_ihl_s4;
    ipv4_ihl__st4 = ipv4_ihl_s4;
    out_ipv4_diffserv__st4 = out_ipv4_diffserv_s4;
    ipv4_diffserv__st4 = ipv4_diffserv_s4;
    out_ipv4_totalLen__st4 = out_ipv4_totalLen_s4;
    ipv4_totalLen__st4 = ipv4_totalLen_s4;
    out_ipv4_identification__st4 = out_ipv4_identification_s4;
    ipv4_identification__st4 = ipv4_identification_s4;
    out_ipv4_flags__st4 = out_ipv4_flags_s4;
    ipv4_flags__st4 = ipv4_flags_s4;
    out_ipv4_fragOffset__st4 = out_ipv4_fragOffset_s4;
    ipv4_fragOffset__st4 = ipv4_fragOffset_s4;
    out_ipv4_ttl__st4 = out_ipv4_ttl_s4;
    ipv4_ttl__st4 = ipv4_ttl_s4;
    out_ipv4_protocol__st4 = out_ipv4_protocol_s4;
    ipv4_protocol__st4 = ipv4_protocol_s4;
    out_ipv4_hdrChecksum__st4 = out_ipv4_hdrChecksum_s4;
    ipv4_hdrChecksum__st4 = ipv4_hdrChecksum_s4;
    out_ipv4_srcAddr__st4 = out_ipv4_srcAddr_s4;
    ipv4_srcAddr__st4 = ipv4_srcAddr_s4;
    out_ipv4_dstAddr__st4 = out_ipv4_dstAddr_s4;
    ipv4_dstAddr__st4 = ipv4_dstAddr_s4;
    out_tcp_srcPort__st4 = out_tcp_srcPort_s4;
    tcp_srcPort__st4 = tcp_srcPort_s4;
    out_tcp_dstPort__st4 = out_tcp_dstPort_s4;
    tcp_dstPort__st4 = tcp_dstPort_s4;
    out_tcp_seqNo__st4 = out_tcp_seqNo_s4;
    tcp_seqNo__st4 = tcp_seqNo_s4;
    out_tcp_ackNo__st4 = out_tcp_ackNo_s4;
    tcp_ackNo__st4 = tcp_ackNo_s4;
    out_tcp_dataOffset__st4 = out_tcp_dataOffset_s4;
    tcp_dataOffset__st4 = tcp_dataOffset_s4;
    out_tcp_reserved__st4 = out_tcp_reserved_s4;
    tcp_reserved__st4 = tcp_reserved_s4;
    out_tcp_flags__st4 = out_tcp_flags_s4;
    tcp_flags__st4 = tcp_flags_s4;
    out_tcp_window__st4 = out_tcp_window_s4;
    tcp_window__st4 = tcp_window_s4;
    out_tcp_checksum__st4 = out_tcp_checksum_s4;
    tcp_checksum__st4 = tcp_checksum_s4;
    out_tcp_urgentPtr__st4 = out_tcp_urgentPtr_s4;
    tcp_urgentPtr__st4 = tcp_urgentPtr_s4;
    out_udp_srcPort__st4 = out_udp_srcPort_s4;
    udp_srcPort__st4 = udp_srcPort_s4;
    out_udp_dstPort__st4 = out_udp_dstPort_s4;
    udp_dstPort__st4 = udp_dstPort_s4;
    out_udp_length__st4 = out_udp_length_s4;
    udp_length__st4 = udp_length_s4;
    out_udp_checksum__st4 = out_udp_checksum_s4;
    udp_checksum__st4 = udp_checksum_s4;
    out_mpls_0_label__st4 = out_mpls_0_label_s4;
    mpls_0_label__st4 = mpls_0_label_s4;
    out_mpls_0_tc__st4 = out_mpls_0_tc_s4;
    mpls_0_tc__st4 = mpls_0_tc_s4;
    out_mpls_0_bos__st4 = out_mpls_0_bos_s4;
    mpls_0_bos__st4 = mpls_0_bos_s4;
    out_mpls_0_ttl__st4 = out_mpls_0_ttl_s4;
    mpls_0_ttl__st4 = mpls_0_ttl_s4;
    out_mpls_1_label__st4 = out_mpls_1_label_s4;
    mpls_1_label__st4 = mpls_1_label_s4;
    out_mpls_1_tc__st4 = out_mpls_1_tc_s4;
    mpls_1_tc__st4 = mpls_1_tc_s4;
    out_mpls_1_bos__st4 = out_mpls_1_bos_s4;
    mpls_1_bos__st4 = mpls_1_bos_s4;
    out_mpls_1_ttl__st4 = out_mpls_1_ttl_s4;
    mpls_1_ttl__st4 = mpls_1_ttl_s4;
    out_mpls_2_label__st4 = out_mpls_2_label_s4;
    mpls_2_label__st4 = mpls_2_label_s4;
    out_mpls_2_tc__st4 = out_mpls_2_tc_s4;
    mpls_2_tc__st4 = mpls_2_tc_s4;
    out_mpls_2_bos__st4 = out_mpls_2_bos_s4;
    mpls_2_bos__st4 = mpls_2_bos_s4;
    out_mpls_2_ttl__st4 = out_mpls_2_ttl_s4;
    mpls_2_ttl__st4 = mpls_2_ttl_s4;
    out_std_meta_egress_port__st4 = out_std_meta_egress_port_s4;
    std_meta_ingress_port__st4 = std_meta_ingress_port_s4;

    // apply block (stage 4 of 8)
    if (__stage_cond_0_r) begin
      // mpls_swap.apply()
      if (mpls_swap_hit) begin
        unique case (mpls_swap_act_id)
          2'd0: ; // NoAction
          2'd1: begin // swap_label
            out_mpls_0_label__st4 = mpls_swap_p_new_label;
          end
          2'd2: begin // push_mpls
            out_mpls_2_valid__st4 = mpls_1_valid__st4;
            out_mpls_2_label__st4 = mpls_1_label__st4;
            out_mpls_2_tc__st4 = mpls_1_tc__st4;
            out_mpls_2_bos__st4 = mpls_1_bos__st4;
            out_mpls_2_ttl__st4 = mpls_1_ttl__st4;
            out_mpls_1_valid__st4 = mpls_0_valid__st4;
            out_mpls_1_label__st4 = mpls_0_label__st4;
            out_mpls_1_tc__st4 = mpls_0_tc__st4;
            out_mpls_1_bos__st4 = mpls_0_bos__st4;
            out_mpls_1_ttl__st4 = mpls_0_ttl__st4;
            out_mpls_0_label__st4 = mpls_swap_p_label;
            out_mpls_0_bos__st4 = 'h00;
            out_mpls_0_ttl__st4 = 'h40;
            out_ethernet_etherType__st4 = 'h8847;
          end
          2'd3: begin // pop_mpls
            /* UNIMPLEMENTED EXTERN: _bmv2_pop(0, 'h1) */
          end
          default: ; // default = NoAction
        endcase
      end
      if ((mpls_0_bos__st4 == 'h01)) begin
        /* UNIMPLEMENTED EXTERN: _bmv2_pop(0, 'h1) */
      end
    end
    if (ipv4_valid__st4) begin
      if (tcp_valid__st4) begin
      end
    end
  end

  // Forward stage-4 state into stage-5 registers (1-cycle
  // boundary — matches the exact-match table's registered latency)
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      valid_s5 <= 1'b0;
    end else begin
      valid_s5 <= valid_s4;
      drop_s5 <= drop__st4;
      _padding_0_s5 <= _padding_0__st4;
      key_0_s5 <= key_0__st4;
      tmp_s5 <= tmp__st4;
      tmp_0_s5 <= tmp_0__st4;
      tmp_1_s5 <= tmp_1__st4;
      meta_ingress_port_w_s5 <= meta_ingress_port_w__st4;
      meta_egress_port_w_s5 <= meta_egress_port_w__st4;
      meta_packet_length_w_s5 <= meta_packet_length_w__st4;
      meta_priority_w_s5 <= meta_priority_w__st4;
      meta_mcast_grp_w_s5 <= meta_mcast_grp_w__st4;
      meta_egress_rid_w_s5 <= meta_egress_rid_w__st4;
      meta_checksum_error_w_s5 <= meta_checksum_error_w__st4;
      meta_enq_timestamp_w_s5 <= meta_enq_timestamp_w__st4;
      meta_enq_qdepth_w_s5 <= meta_enq_qdepth_w__st4;
      meta_deq_timedelta_w_s5 <= meta_deq_timedelta_w__st4;
      meta_deq_qdepth_w_s5 <= meta_deq_qdepth_w__st4;
      meta_ingress_global_timestamp_w_s5 <= meta_ingress_global_timestamp_w__st4;
      meta_egress_global_timestamp_w_s5 <= meta_egress_global_timestamp_w__st4;
      meta_ttl_w_s5 <= meta_ttl_w__st4;
      meta_next_hop_w_s5 <= meta_next_hop_w__st4;
      meta_mpls_label_swap_w_s5 <= meta_mpls_label_swap_w__st4;
      meta_drop_w_s5 <= meta_drop_w__st4;
      meta_ecmp_select_w_s5 <= meta_ecmp_select_w__st4;
      out_ethernet_valid_s5 <= out_ethernet_valid__st4;
      ethernet_valid_s5 <= ethernet_valid__st4;
      out_ipv4_valid_s5 <= out_ipv4_valid__st4;
      ipv4_valid_s5 <= ipv4_valid__st4;
      out_tcp_valid_s5 <= out_tcp_valid__st4;
      tcp_valid_s5 <= tcp_valid__st4;
      out_udp_valid_s5 <= out_udp_valid__st4;
      udp_valid_s5 <= udp_valid__st4;
      out_mpls_0_valid_s5 <= out_mpls_0_valid__st4;
      mpls_0_valid_s5 <= mpls_0_valid__st4;
      out_mpls_1_valid_s5 <= out_mpls_1_valid__st4;
      mpls_1_valid_s5 <= mpls_1_valid__st4;
      out_mpls_2_valid_s5 <= out_mpls_2_valid__st4;
      mpls_2_valid_s5 <= mpls_2_valid__st4;
      out_ethernet_dstAddr_s5 <= out_ethernet_dstAddr__st4;
      ethernet_dstAddr_s5 <= ethernet_dstAddr__st4;
      out_ethernet_srcAddr_s5 <= out_ethernet_srcAddr__st4;
      ethernet_srcAddr_s5 <= ethernet_srcAddr__st4;
      out_ethernet_etherType_s5 <= out_ethernet_etherType__st4;
      ethernet_etherType_s5 <= ethernet_etherType__st4;
      out_ipv4_version_s5 <= out_ipv4_version__st4;
      ipv4_version_s5 <= ipv4_version__st4;
      out_ipv4_ihl_s5 <= out_ipv4_ihl__st4;
      ipv4_ihl_s5 <= ipv4_ihl__st4;
      out_ipv4_diffserv_s5 <= out_ipv4_diffserv__st4;
      ipv4_diffserv_s5 <= ipv4_diffserv__st4;
      out_ipv4_totalLen_s5 <= out_ipv4_totalLen__st4;
      ipv4_totalLen_s5 <= ipv4_totalLen__st4;
      out_ipv4_identification_s5 <= out_ipv4_identification__st4;
      ipv4_identification_s5 <= ipv4_identification__st4;
      out_ipv4_flags_s5 <= out_ipv4_flags__st4;
      ipv4_flags_s5 <= ipv4_flags__st4;
      out_ipv4_fragOffset_s5 <= out_ipv4_fragOffset__st4;
      ipv4_fragOffset_s5 <= ipv4_fragOffset__st4;
      out_ipv4_ttl_s5 <= out_ipv4_ttl__st4;
      ipv4_ttl_s5 <= ipv4_ttl__st4;
      out_ipv4_protocol_s5 <= out_ipv4_protocol__st4;
      ipv4_protocol_s5 <= ipv4_protocol__st4;
      out_ipv4_hdrChecksum_s5 <= out_ipv4_hdrChecksum__st4;
      ipv4_hdrChecksum_s5 <= ipv4_hdrChecksum__st4;
      out_ipv4_srcAddr_s5 <= out_ipv4_srcAddr__st4;
      ipv4_srcAddr_s5 <= ipv4_srcAddr__st4;
      out_ipv4_dstAddr_s5 <= out_ipv4_dstAddr__st4;
      ipv4_dstAddr_s5 <= ipv4_dstAddr__st4;
      out_tcp_srcPort_s5 <= out_tcp_srcPort__st4;
      tcp_srcPort_s5 <= tcp_srcPort__st4;
      out_tcp_dstPort_s5 <= out_tcp_dstPort__st4;
      tcp_dstPort_s5 <= tcp_dstPort__st4;
      out_tcp_seqNo_s5 <= out_tcp_seqNo__st4;
      tcp_seqNo_s5 <= tcp_seqNo__st4;
      out_tcp_ackNo_s5 <= out_tcp_ackNo__st4;
      tcp_ackNo_s5 <= tcp_ackNo__st4;
      out_tcp_dataOffset_s5 <= out_tcp_dataOffset__st4;
      tcp_dataOffset_s5 <= tcp_dataOffset__st4;
      out_tcp_reserved_s5 <= out_tcp_reserved__st4;
      tcp_reserved_s5 <= tcp_reserved__st4;
      out_tcp_flags_s5 <= out_tcp_flags__st4;
      tcp_flags_s5 <= tcp_flags__st4;
      out_tcp_window_s5 <= out_tcp_window__st4;
      tcp_window_s5 <= tcp_window__st4;
      out_tcp_checksum_s5 <= out_tcp_checksum__st4;
      tcp_checksum_s5 <= tcp_checksum__st4;
      out_tcp_urgentPtr_s5 <= out_tcp_urgentPtr__st4;
      tcp_urgentPtr_s5 <= tcp_urgentPtr__st4;
      out_udp_srcPort_s5 <= out_udp_srcPort__st4;
      udp_srcPort_s5 <= udp_srcPort__st4;
      out_udp_dstPort_s5 <= out_udp_dstPort__st4;
      udp_dstPort_s5 <= udp_dstPort__st4;
      out_udp_length_s5 <= out_udp_length__st4;
      udp_length_s5 <= udp_length__st4;
      out_udp_checksum_s5 <= out_udp_checksum__st4;
      udp_checksum_s5 <= udp_checksum__st4;
      out_mpls_0_label_s5 <= out_mpls_0_label__st4;
      mpls_0_label_s5 <= mpls_0_label__st4;
      out_mpls_0_tc_s5 <= out_mpls_0_tc__st4;
      mpls_0_tc_s5 <= mpls_0_tc__st4;
      out_mpls_0_bos_s5 <= out_mpls_0_bos__st4;
      mpls_0_bos_s5 <= mpls_0_bos__st4;
      out_mpls_0_ttl_s5 <= out_mpls_0_ttl__st4;
      mpls_0_ttl_s5 <= mpls_0_ttl__st4;
      out_mpls_1_label_s5 <= out_mpls_1_label__st4;
      mpls_1_label_s5 <= mpls_1_label__st4;
      out_mpls_1_tc_s5 <= out_mpls_1_tc__st4;
      mpls_1_tc_s5 <= mpls_1_tc__st4;
      out_mpls_1_bos_s5 <= out_mpls_1_bos__st4;
      mpls_1_bos_s5 <= mpls_1_bos__st4;
      out_mpls_1_ttl_s5 <= out_mpls_1_ttl__st4;
      mpls_1_ttl_s5 <= mpls_1_ttl__st4;
      out_mpls_2_label_s5 <= out_mpls_2_label__st4;
      mpls_2_label_s5 <= mpls_2_label__st4;
      out_mpls_2_tc_s5 <= out_mpls_2_tc__st4;
      mpls_2_tc_s5 <= mpls_2_tc__st4;
      out_mpls_2_bos_s5 <= out_mpls_2_bos__st4;
      mpls_2_bos_s5 <= mpls_2_bos__st4;
      out_mpls_2_ttl_s5 <= out_mpls_2_ttl__st4;
      mpls_2_ttl_s5 <= mpls_2_ttl__st4;
      out_std_meta_egress_port_s5 <= out_std_meta_egress_port__st4;
      std_meta_ingress_port_s5 <= std_meta_ingress_port__st4;
      __stage_cond_2_r <= (ipv4_valid__st4);
      __stage_cond_1_r <= (tcp_valid__st4);
    end
  end

  // ---- Pipeline stage 5 (registered 5 cycle(s) after stage 0) ----
  always_comb begin
    drop__st5 = drop_s5;
    _padding_0__st5 = _padding_0_s5;
    key_0__st5 = key_0_s5;
    tmp__st5 = tmp_s5;
    tmp_0__st5 = tmp_0_s5;
    tmp_1__st5 = tmp_1_s5;
    meta_ingress_port_w__st5 = meta_ingress_port_w_s5;
    meta_egress_port_w__st5 = meta_egress_port_w_s5;
    meta_packet_length_w__st5 = meta_packet_length_w_s5;
    meta_priority_w__st5 = meta_priority_w_s5;
    meta_mcast_grp_w__st5 = meta_mcast_grp_w_s5;
    meta_egress_rid_w__st5 = meta_egress_rid_w_s5;
    meta_checksum_error_w__st5 = meta_checksum_error_w_s5;
    meta_enq_timestamp_w__st5 = meta_enq_timestamp_w_s5;
    meta_enq_qdepth_w__st5 = meta_enq_qdepth_w_s5;
    meta_deq_timedelta_w__st5 = meta_deq_timedelta_w_s5;
    meta_deq_qdepth_w__st5 = meta_deq_qdepth_w_s5;
    meta_ingress_global_timestamp_w__st5 = meta_ingress_global_timestamp_w_s5;
    meta_egress_global_timestamp_w__st5 = meta_egress_global_timestamp_w_s5;
    meta_ttl_w__st5 = meta_ttl_w_s5;
    meta_next_hop_w__st5 = meta_next_hop_w_s5;
    meta_mpls_label_swap_w__st5 = meta_mpls_label_swap_w_s5;
    meta_drop_w__st5 = meta_drop_w_s5;
    meta_ecmp_select_w__st5 = meta_ecmp_select_w_s5;
    out_ethernet_valid__st5 = out_ethernet_valid_s5;
    ethernet_valid__st5 = ethernet_valid_s5;
    out_ipv4_valid__st5 = out_ipv4_valid_s5;
    ipv4_valid__st5 = ipv4_valid_s5;
    out_tcp_valid__st5 = out_tcp_valid_s5;
    tcp_valid__st5 = tcp_valid_s5;
    out_udp_valid__st5 = out_udp_valid_s5;
    udp_valid__st5 = udp_valid_s5;
    out_mpls_0_valid__st5 = out_mpls_0_valid_s5;
    mpls_0_valid__st5 = mpls_0_valid_s5;
    out_mpls_1_valid__st5 = out_mpls_1_valid_s5;
    mpls_1_valid__st5 = mpls_1_valid_s5;
    out_mpls_2_valid__st5 = out_mpls_2_valid_s5;
    mpls_2_valid__st5 = mpls_2_valid_s5;
    out_ethernet_dstAddr__st5 = out_ethernet_dstAddr_s5;
    ethernet_dstAddr__st5 = ethernet_dstAddr_s5;
    out_ethernet_srcAddr__st5 = out_ethernet_srcAddr_s5;
    ethernet_srcAddr__st5 = ethernet_srcAddr_s5;
    out_ethernet_etherType__st5 = out_ethernet_etherType_s5;
    ethernet_etherType__st5 = ethernet_etherType_s5;
    out_ipv4_version__st5 = out_ipv4_version_s5;
    ipv4_version__st5 = ipv4_version_s5;
    out_ipv4_ihl__st5 = out_ipv4_ihl_s5;
    ipv4_ihl__st5 = ipv4_ihl_s5;
    out_ipv4_diffserv__st5 = out_ipv4_diffserv_s5;
    ipv4_diffserv__st5 = ipv4_diffserv_s5;
    out_ipv4_totalLen__st5 = out_ipv4_totalLen_s5;
    ipv4_totalLen__st5 = ipv4_totalLen_s5;
    out_ipv4_identification__st5 = out_ipv4_identification_s5;
    ipv4_identification__st5 = ipv4_identification_s5;
    out_ipv4_flags__st5 = out_ipv4_flags_s5;
    ipv4_flags__st5 = ipv4_flags_s5;
    out_ipv4_fragOffset__st5 = out_ipv4_fragOffset_s5;
    ipv4_fragOffset__st5 = ipv4_fragOffset_s5;
    out_ipv4_ttl__st5 = out_ipv4_ttl_s5;
    ipv4_ttl__st5 = ipv4_ttl_s5;
    out_ipv4_protocol__st5 = out_ipv4_protocol_s5;
    ipv4_protocol__st5 = ipv4_protocol_s5;
    out_ipv4_hdrChecksum__st5 = out_ipv4_hdrChecksum_s5;
    ipv4_hdrChecksum__st5 = ipv4_hdrChecksum_s5;
    out_ipv4_srcAddr__st5 = out_ipv4_srcAddr_s5;
    ipv4_srcAddr__st5 = ipv4_srcAddr_s5;
    out_ipv4_dstAddr__st5 = out_ipv4_dstAddr_s5;
    ipv4_dstAddr__st5 = ipv4_dstAddr_s5;
    out_tcp_srcPort__st5 = out_tcp_srcPort_s5;
    tcp_srcPort__st5 = tcp_srcPort_s5;
    out_tcp_dstPort__st5 = out_tcp_dstPort_s5;
    tcp_dstPort__st5 = tcp_dstPort_s5;
    out_tcp_seqNo__st5 = out_tcp_seqNo_s5;
    tcp_seqNo__st5 = tcp_seqNo_s5;
    out_tcp_ackNo__st5 = out_tcp_ackNo_s5;
    tcp_ackNo__st5 = tcp_ackNo_s5;
    out_tcp_dataOffset__st5 = out_tcp_dataOffset_s5;
    tcp_dataOffset__st5 = tcp_dataOffset_s5;
    out_tcp_reserved__st5 = out_tcp_reserved_s5;
    tcp_reserved__st5 = tcp_reserved_s5;
    out_tcp_flags__st5 = out_tcp_flags_s5;
    tcp_flags__st5 = tcp_flags_s5;
    out_tcp_window__st5 = out_tcp_window_s5;
    tcp_window__st5 = tcp_window_s5;
    out_tcp_checksum__st5 = out_tcp_checksum_s5;
    tcp_checksum__st5 = tcp_checksum_s5;
    out_tcp_urgentPtr__st5 = out_tcp_urgentPtr_s5;
    tcp_urgentPtr__st5 = tcp_urgentPtr_s5;
    out_udp_srcPort__st5 = out_udp_srcPort_s5;
    udp_srcPort__st5 = udp_srcPort_s5;
    out_udp_dstPort__st5 = out_udp_dstPort_s5;
    udp_dstPort__st5 = udp_dstPort_s5;
    out_udp_length__st5 = out_udp_length_s5;
    udp_length__st5 = udp_length_s5;
    out_udp_checksum__st5 = out_udp_checksum_s5;
    udp_checksum__st5 = udp_checksum_s5;
    out_mpls_0_label__st5 = out_mpls_0_label_s5;
    mpls_0_label__st5 = mpls_0_label_s5;
    out_mpls_0_tc__st5 = out_mpls_0_tc_s5;
    mpls_0_tc__st5 = mpls_0_tc_s5;
    out_mpls_0_bos__st5 = out_mpls_0_bos_s5;
    mpls_0_bos__st5 = mpls_0_bos_s5;
    out_mpls_0_ttl__st5 = out_mpls_0_ttl_s5;
    mpls_0_ttl__st5 = mpls_0_ttl_s5;
    out_mpls_1_label__st5 = out_mpls_1_label_s5;
    mpls_1_label__st5 = mpls_1_label_s5;
    out_mpls_1_tc__st5 = out_mpls_1_tc_s5;
    mpls_1_tc__st5 = mpls_1_tc_s5;
    out_mpls_1_bos__st5 = out_mpls_1_bos_s5;
    mpls_1_bos__st5 = mpls_1_bos_s5;
    out_mpls_1_ttl__st5 = out_mpls_1_ttl_s5;
    mpls_1_ttl__st5 = mpls_1_ttl_s5;
    out_mpls_2_label__st5 = out_mpls_2_label_s5;
    mpls_2_label__st5 = mpls_2_label_s5;
    out_mpls_2_tc__st5 = out_mpls_2_tc_s5;
    mpls_2_tc__st5 = mpls_2_tc_s5;
    out_mpls_2_bos__st5 = out_mpls_2_bos_s5;
    mpls_2_bos__st5 = mpls_2_bos_s5;
    out_mpls_2_ttl__st5 = out_mpls_2_ttl_s5;
    mpls_2_ttl__st5 = mpls_2_ttl_s5;
    out_std_meta_egress_port__st5 = out_std_meta_egress_port_s5;
    std_meta_ingress_port__st5 = std_meta_ingress_port_s5;
  end

  // Forward stage-5 state into stage-6 registers (1-cycle
  // boundary — matches the exact-match table's registered latency)
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      valid_s6 <= 1'b0;
    end else begin
      valid_s6 <= valid_s5;
      drop_s6 <= drop__st5;
      _padding_0_s6 <= _padding_0__st5;
      key_0_s6 <= key_0__st5;
      tmp_s6 <= tmp__st5;
      tmp_0_s6 <= tmp_0__st5;
      tmp_1_s6 <= tmp_1__st5;
      meta_ingress_port_w_s6 <= meta_ingress_port_w__st5;
      meta_egress_port_w_s6 <= meta_egress_port_w__st5;
      meta_packet_length_w_s6 <= meta_packet_length_w__st5;
      meta_priority_w_s6 <= meta_priority_w__st5;
      meta_mcast_grp_w_s6 <= meta_mcast_grp_w__st5;
      meta_egress_rid_w_s6 <= meta_egress_rid_w__st5;
      meta_checksum_error_w_s6 <= meta_checksum_error_w__st5;
      meta_enq_timestamp_w_s6 <= meta_enq_timestamp_w__st5;
      meta_enq_qdepth_w_s6 <= meta_enq_qdepth_w__st5;
      meta_deq_timedelta_w_s6 <= meta_deq_timedelta_w__st5;
      meta_deq_qdepth_w_s6 <= meta_deq_qdepth_w__st5;
      meta_ingress_global_timestamp_w_s6 <= meta_ingress_global_timestamp_w__st5;
      meta_egress_global_timestamp_w_s6 <= meta_egress_global_timestamp_w__st5;
      meta_ttl_w_s6 <= meta_ttl_w__st5;
      meta_next_hop_w_s6 <= meta_next_hop_w__st5;
      meta_mpls_label_swap_w_s6 <= meta_mpls_label_swap_w__st5;
      meta_drop_w_s6 <= meta_drop_w__st5;
      meta_ecmp_select_w_s6 <= meta_ecmp_select_w__st5;
      out_ethernet_valid_s6 <= out_ethernet_valid__st5;
      ethernet_valid_s6 <= ethernet_valid__st5;
      out_ipv4_valid_s6 <= out_ipv4_valid__st5;
      ipv4_valid_s6 <= ipv4_valid__st5;
      out_tcp_valid_s6 <= out_tcp_valid__st5;
      tcp_valid_s6 <= tcp_valid__st5;
      out_udp_valid_s6 <= out_udp_valid__st5;
      udp_valid_s6 <= udp_valid__st5;
      out_mpls_0_valid_s6 <= out_mpls_0_valid__st5;
      mpls_0_valid_s6 <= mpls_0_valid__st5;
      out_mpls_1_valid_s6 <= out_mpls_1_valid__st5;
      mpls_1_valid_s6 <= mpls_1_valid__st5;
      out_mpls_2_valid_s6 <= out_mpls_2_valid__st5;
      mpls_2_valid_s6 <= mpls_2_valid__st5;
      out_ethernet_dstAddr_s6 <= out_ethernet_dstAddr__st5;
      ethernet_dstAddr_s6 <= ethernet_dstAddr__st5;
      out_ethernet_srcAddr_s6 <= out_ethernet_srcAddr__st5;
      ethernet_srcAddr_s6 <= ethernet_srcAddr__st5;
      out_ethernet_etherType_s6 <= out_ethernet_etherType__st5;
      ethernet_etherType_s6 <= ethernet_etherType__st5;
      out_ipv4_version_s6 <= out_ipv4_version__st5;
      ipv4_version_s6 <= ipv4_version__st5;
      out_ipv4_ihl_s6 <= out_ipv4_ihl__st5;
      ipv4_ihl_s6 <= ipv4_ihl__st5;
      out_ipv4_diffserv_s6 <= out_ipv4_diffserv__st5;
      ipv4_diffserv_s6 <= ipv4_diffserv__st5;
      out_ipv4_totalLen_s6 <= out_ipv4_totalLen__st5;
      ipv4_totalLen_s6 <= ipv4_totalLen__st5;
      out_ipv4_identification_s6 <= out_ipv4_identification__st5;
      ipv4_identification_s6 <= ipv4_identification__st5;
      out_ipv4_flags_s6 <= out_ipv4_flags__st5;
      ipv4_flags_s6 <= ipv4_flags__st5;
      out_ipv4_fragOffset_s6 <= out_ipv4_fragOffset__st5;
      ipv4_fragOffset_s6 <= ipv4_fragOffset__st5;
      out_ipv4_ttl_s6 <= out_ipv4_ttl__st5;
      ipv4_ttl_s6 <= ipv4_ttl__st5;
      out_ipv4_protocol_s6 <= out_ipv4_protocol__st5;
      ipv4_protocol_s6 <= ipv4_protocol__st5;
      out_ipv4_hdrChecksum_s6 <= out_ipv4_hdrChecksum__st5;
      ipv4_hdrChecksum_s6 <= ipv4_hdrChecksum__st5;
      out_ipv4_srcAddr_s6 <= out_ipv4_srcAddr__st5;
      ipv4_srcAddr_s6 <= ipv4_srcAddr__st5;
      out_ipv4_dstAddr_s6 <= out_ipv4_dstAddr__st5;
      ipv4_dstAddr_s6 <= ipv4_dstAddr__st5;
      out_tcp_srcPort_s6 <= out_tcp_srcPort__st5;
      tcp_srcPort_s6 <= tcp_srcPort__st5;
      out_tcp_dstPort_s6 <= out_tcp_dstPort__st5;
      tcp_dstPort_s6 <= tcp_dstPort__st5;
      out_tcp_seqNo_s6 <= out_tcp_seqNo__st5;
      tcp_seqNo_s6 <= tcp_seqNo__st5;
      out_tcp_ackNo_s6 <= out_tcp_ackNo__st5;
      tcp_ackNo_s6 <= tcp_ackNo__st5;
      out_tcp_dataOffset_s6 <= out_tcp_dataOffset__st5;
      tcp_dataOffset_s6 <= tcp_dataOffset__st5;
      out_tcp_reserved_s6 <= out_tcp_reserved__st5;
      tcp_reserved_s6 <= tcp_reserved__st5;
      out_tcp_flags_s6 <= out_tcp_flags__st5;
      tcp_flags_s6 <= tcp_flags__st5;
      out_tcp_window_s6 <= out_tcp_window__st5;
      tcp_window_s6 <= tcp_window__st5;
      out_tcp_checksum_s6 <= out_tcp_checksum__st5;
      tcp_checksum_s6 <= tcp_checksum__st5;
      out_tcp_urgentPtr_s6 <= out_tcp_urgentPtr__st5;
      tcp_urgentPtr_s6 <= tcp_urgentPtr__st5;
      out_udp_srcPort_s6 <= out_udp_srcPort__st5;
      udp_srcPort_s6 <= udp_srcPort__st5;
      out_udp_dstPort_s6 <= out_udp_dstPort__st5;
      udp_dstPort_s6 <= udp_dstPort__st5;
      out_udp_length_s6 <= out_udp_length__st5;
      udp_length_s6 <= udp_length__st5;
      out_udp_checksum_s6 <= out_udp_checksum__st5;
      udp_checksum_s6 <= udp_checksum__st5;
      out_mpls_0_label_s6 <= out_mpls_0_label__st5;
      mpls_0_label_s6 <= mpls_0_label__st5;
      out_mpls_0_tc_s6 <= out_mpls_0_tc__st5;
      mpls_0_tc_s6 <= mpls_0_tc__st5;
      out_mpls_0_bos_s6 <= out_mpls_0_bos__st5;
      mpls_0_bos_s6 <= mpls_0_bos__st5;
      out_mpls_0_ttl_s6 <= out_mpls_0_ttl__st5;
      mpls_0_ttl_s6 <= mpls_0_ttl__st5;
      out_mpls_1_label_s6 <= out_mpls_1_label__st5;
      mpls_1_label_s6 <= mpls_1_label__st5;
      out_mpls_1_tc_s6 <= out_mpls_1_tc__st5;
      mpls_1_tc_s6 <= mpls_1_tc__st5;
      out_mpls_1_bos_s6 <= out_mpls_1_bos__st5;
      mpls_1_bos_s6 <= mpls_1_bos__st5;
      out_mpls_1_ttl_s6 <= out_mpls_1_ttl__st5;
      mpls_1_ttl_s6 <= mpls_1_ttl__st5;
      out_mpls_2_label_s6 <= out_mpls_2_label__st5;
      mpls_2_label_s6 <= mpls_2_label__st5;
      out_mpls_2_tc_s6 <= out_mpls_2_tc__st5;
      mpls_2_tc_s6 <= mpls_2_tc__st5;
      out_mpls_2_bos_s6 <= out_mpls_2_bos__st5;
      mpls_2_bos_s6 <= mpls_2_bos__st5;
      out_mpls_2_ttl_s6 <= out_mpls_2_ttl__st5;
      mpls_2_ttl_s6 <= mpls_2_ttl__st5;
      out_std_meta_egress_port_s6 <= out_std_meta_egress_port__st5;
      std_meta_ingress_port_s6 <= std_meta_ingress_port__st5;
    end
  end

  // ---- Pipeline stage 6 (registered 6 cycle(s) after stage 0) ----
  always_comb begin
    drop__st6 = drop_s6;
    _padding_0__st6 = _padding_0_s6;
    key_0__st6 = key_0_s6;
    tmp__st6 = tmp_s6;
    tmp_0__st6 = tmp_0_s6;
    tmp_1__st6 = tmp_1_s6;
    meta_ingress_port_w__st6 = meta_ingress_port_w_s6;
    meta_egress_port_w__st6 = meta_egress_port_w_s6;
    meta_packet_length_w__st6 = meta_packet_length_w_s6;
    meta_priority_w__st6 = meta_priority_w_s6;
    meta_mcast_grp_w__st6 = meta_mcast_grp_w_s6;
    meta_egress_rid_w__st6 = meta_egress_rid_w_s6;
    meta_checksum_error_w__st6 = meta_checksum_error_w_s6;
    meta_enq_timestamp_w__st6 = meta_enq_timestamp_w_s6;
    meta_enq_qdepth_w__st6 = meta_enq_qdepth_w_s6;
    meta_deq_timedelta_w__st6 = meta_deq_timedelta_w_s6;
    meta_deq_qdepth_w__st6 = meta_deq_qdepth_w_s6;
    meta_ingress_global_timestamp_w__st6 = meta_ingress_global_timestamp_w_s6;
    meta_egress_global_timestamp_w__st6 = meta_egress_global_timestamp_w_s6;
    meta_ttl_w__st6 = meta_ttl_w_s6;
    meta_next_hop_w__st6 = meta_next_hop_w_s6;
    meta_mpls_label_swap_w__st6 = meta_mpls_label_swap_w_s6;
    meta_drop_w__st6 = meta_drop_w_s6;
    meta_ecmp_select_w__st6 = meta_ecmp_select_w_s6;
    out_ethernet_valid__st6 = out_ethernet_valid_s6;
    ethernet_valid__st6 = ethernet_valid_s6;
    out_ipv4_valid__st6 = out_ipv4_valid_s6;
    ipv4_valid__st6 = ipv4_valid_s6;
    out_tcp_valid__st6 = out_tcp_valid_s6;
    tcp_valid__st6 = tcp_valid_s6;
    out_udp_valid__st6 = out_udp_valid_s6;
    udp_valid__st6 = udp_valid_s6;
    out_mpls_0_valid__st6 = out_mpls_0_valid_s6;
    mpls_0_valid__st6 = mpls_0_valid_s6;
    out_mpls_1_valid__st6 = out_mpls_1_valid_s6;
    mpls_1_valid__st6 = mpls_1_valid_s6;
    out_mpls_2_valid__st6 = out_mpls_2_valid_s6;
    mpls_2_valid__st6 = mpls_2_valid_s6;
    out_ethernet_dstAddr__st6 = out_ethernet_dstAddr_s6;
    ethernet_dstAddr__st6 = ethernet_dstAddr_s6;
    out_ethernet_srcAddr__st6 = out_ethernet_srcAddr_s6;
    ethernet_srcAddr__st6 = ethernet_srcAddr_s6;
    out_ethernet_etherType__st6 = out_ethernet_etherType_s6;
    ethernet_etherType__st6 = ethernet_etherType_s6;
    out_ipv4_version__st6 = out_ipv4_version_s6;
    ipv4_version__st6 = ipv4_version_s6;
    out_ipv4_ihl__st6 = out_ipv4_ihl_s6;
    ipv4_ihl__st6 = ipv4_ihl_s6;
    out_ipv4_diffserv__st6 = out_ipv4_diffserv_s6;
    ipv4_diffserv__st6 = ipv4_diffserv_s6;
    out_ipv4_totalLen__st6 = out_ipv4_totalLen_s6;
    ipv4_totalLen__st6 = ipv4_totalLen_s6;
    out_ipv4_identification__st6 = out_ipv4_identification_s6;
    ipv4_identification__st6 = ipv4_identification_s6;
    out_ipv4_flags__st6 = out_ipv4_flags_s6;
    ipv4_flags__st6 = ipv4_flags_s6;
    out_ipv4_fragOffset__st6 = out_ipv4_fragOffset_s6;
    ipv4_fragOffset__st6 = ipv4_fragOffset_s6;
    out_ipv4_ttl__st6 = out_ipv4_ttl_s6;
    ipv4_ttl__st6 = ipv4_ttl_s6;
    out_ipv4_protocol__st6 = out_ipv4_protocol_s6;
    ipv4_protocol__st6 = ipv4_protocol_s6;
    out_ipv4_hdrChecksum__st6 = out_ipv4_hdrChecksum_s6;
    ipv4_hdrChecksum__st6 = ipv4_hdrChecksum_s6;
    out_ipv4_srcAddr__st6 = out_ipv4_srcAddr_s6;
    ipv4_srcAddr__st6 = ipv4_srcAddr_s6;
    out_ipv4_dstAddr__st6 = out_ipv4_dstAddr_s6;
    ipv4_dstAddr__st6 = ipv4_dstAddr_s6;
    out_tcp_srcPort__st6 = out_tcp_srcPort_s6;
    tcp_srcPort__st6 = tcp_srcPort_s6;
    out_tcp_dstPort__st6 = out_tcp_dstPort_s6;
    tcp_dstPort__st6 = tcp_dstPort_s6;
    out_tcp_seqNo__st6 = out_tcp_seqNo_s6;
    tcp_seqNo__st6 = tcp_seqNo_s6;
    out_tcp_ackNo__st6 = out_tcp_ackNo_s6;
    tcp_ackNo__st6 = tcp_ackNo_s6;
    out_tcp_dataOffset__st6 = out_tcp_dataOffset_s6;
    tcp_dataOffset__st6 = tcp_dataOffset_s6;
    out_tcp_reserved__st6 = out_tcp_reserved_s6;
    tcp_reserved__st6 = tcp_reserved_s6;
    out_tcp_flags__st6 = out_tcp_flags_s6;
    tcp_flags__st6 = tcp_flags_s6;
    out_tcp_window__st6 = out_tcp_window_s6;
    tcp_window__st6 = tcp_window_s6;
    out_tcp_checksum__st6 = out_tcp_checksum_s6;
    tcp_checksum__st6 = tcp_checksum_s6;
    out_tcp_urgentPtr__st6 = out_tcp_urgentPtr_s6;
    tcp_urgentPtr__st6 = tcp_urgentPtr_s6;
    out_udp_srcPort__st6 = out_udp_srcPort_s6;
    udp_srcPort__st6 = udp_srcPort_s6;
    out_udp_dstPort__st6 = out_udp_dstPort_s6;
    udp_dstPort__st6 = udp_dstPort_s6;
    out_udp_length__st6 = out_udp_length_s6;
    udp_length__st6 = udp_length_s6;
    out_udp_checksum__st6 = out_udp_checksum_s6;
    udp_checksum__st6 = udp_checksum_s6;
    out_mpls_0_label__st6 = out_mpls_0_label_s6;
    mpls_0_label__st6 = mpls_0_label_s6;
    out_mpls_0_tc__st6 = out_mpls_0_tc_s6;
    mpls_0_tc__st6 = mpls_0_tc_s6;
    out_mpls_0_bos__st6 = out_mpls_0_bos_s6;
    mpls_0_bos__st6 = mpls_0_bos_s6;
    out_mpls_0_ttl__st6 = out_mpls_0_ttl_s6;
    mpls_0_ttl__st6 = mpls_0_ttl_s6;
    out_mpls_1_label__st6 = out_mpls_1_label_s6;
    mpls_1_label__st6 = mpls_1_label_s6;
    out_mpls_1_tc__st6 = out_mpls_1_tc_s6;
    mpls_1_tc__st6 = mpls_1_tc_s6;
    out_mpls_1_bos__st6 = out_mpls_1_bos_s6;
    mpls_1_bos__st6 = mpls_1_bos_s6;
    out_mpls_1_ttl__st6 = out_mpls_1_ttl_s6;
    mpls_1_ttl__st6 = mpls_1_ttl_s6;
    out_mpls_2_label__st6 = out_mpls_2_label_s6;
    mpls_2_label__st6 = mpls_2_label_s6;
    out_mpls_2_tc__st6 = out_mpls_2_tc_s6;
    mpls_2_tc__st6 = mpls_2_tc_s6;
    out_mpls_2_bos__st6 = out_mpls_2_bos_s6;
    mpls_2_bos__st6 = mpls_2_bos_s6;
    out_mpls_2_ttl__st6 = out_mpls_2_ttl_s6;
    mpls_2_ttl__st6 = mpls_2_ttl_s6;
    out_std_meta_egress_port__st6 = out_std_meta_egress_port_s6;
    std_meta_ingress_port__st6 = std_meta_ingress_port_s6;

    // apply block (stage 6 of 8)
    if (__stage_cond_2_r) begin
      if (__stage_cond_1_r) begin
        // qos_policy.apply()
        if (qos_policy_hit) begin
          unique case (qos_policy_act_id)
            1'd0: ; // NoAction
            1'd1: begin // set_priority
              meta_priority_w__st6 = qos_policy_p_prio;
            end
            default: ; // default = NoAction
          endcase
        end
      end
    end
  end

  // Forward stage-6 state into stage-7 registers (1-cycle
  // boundary — matches the exact-match table's registered latency)
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      valid_s7 <= 1'b0;
    end else begin
      valid_s7 <= valid_s6;
      drop_s7 <= drop__st6;
      _padding_0_s7 <= _padding_0__st6;
      key_0_s7 <= key_0__st6;
      tmp_s7 <= tmp__st6;
      tmp_0_s7 <= tmp_0__st6;
      tmp_1_s7 <= tmp_1__st6;
      meta_ingress_port_w_s7 <= meta_ingress_port_w__st6;
      meta_egress_port_w_s7 <= meta_egress_port_w__st6;
      meta_packet_length_w_s7 <= meta_packet_length_w__st6;
      meta_priority_w_s7 <= meta_priority_w__st6;
      meta_mcast_grp_w_s7 <= meta_mcast_grp_w__st6;
      meta_egress_rid_w_s7 <= meta_egress_rid_w__st6;
      meta_checksum_error_w_s7 <= meta_checksum_error_w__st6;
      meta_enq_timestamp_w_s7 <= meta_enq_timestamp_w__st6;
      meta_enq_qdepth_w_s7 <= meta_enq_qdepth_w__st6;
      meta_deq_timedelta_w_s7 <= meta_deq_timedelta_w__st6;
      meta_deq_qdepth_w_s7 <= meta_deq_qdepth_w__st6;
      meta_ingress_global_timestamp_w_s7 <= meta_ingress_global_timestamp_w__st6;
      meta_egress_global_timestamp_w_s7 <= meta_egress_global_timestamp_w__st6;
      meta_ttl_w_s7 <= meta_ttl_w__st6;
      meta_next_hop_w_s7 <= meta_next_hop_w__st6;
      meta_mpls_label_swap_w_s7 <= meta_mpls_label_swap_w__st6;
      meta_drop_w_s7 <= meta_drop_w__st6;
      meta_ecmp_select_w_s7 <= meta_ecmp_select_w__st6;
      out_ethernet_valid_s7 <= out_ethernet_valid__st6;
      ethernet_valid_s7 <= ethernet_valid__st6;
      out_ipv4_valid_s7 <= out_ipv4_valid__st6;
      ipv4_valid_s7 <= ipv4_valid__st6;
      out_tcp_valid_s7 <= out_tcp_valid__st6;
      tcp_valid_s7 <= tcp_valid__st6;
      out_udp_valid_s7 <= out_udp_valid__st6;
      udp_valid_s7 <= udp_valid__st6;
      out_mpls_0_valid_s7 <= out_mpls_0_valid__st6;
      mpls_0_valid_s7 <= mpls_0_valid__st6;
      out_mpls_1_valid_s7 <= out_mpls_1_valid__st6;
      mpls_1_valid_s7 <= mpls_1_valid__st6;
      out_mpls_2_valid_s7 <= out_mpls_2_valid__st6;
      mpls_2_valid_s7 <= mpls_2_valid__st6;
      out_ethernet_dstAddr_s7 <= out_ethernet_dstAddr__st6;
      ethernet_dstAddr_s7 <= ethernet_dstAddr__st6;
      out_ethernet_srcAddr_s7 <= out_ethernet_srcAddr__st6;
      ethernet_srcAddr_s7 <= ethernet_srcAddr__st6;
      out_ethernet_etherType_s7 <= out_ethernet_etherType__st6;
      ethernet_etherType_s7 <= ethernet_etherType__st6;
      out_ipv4_version_s7 <= out_ipv4_version__st6;
      ipv4_version_s7 <= ipv4_version__st6;
      out_ipv4_ihl_s7 <= out_ipv4_ihl__st6;
      ipv4_ihl_s7 <= ipv4_ihl__st6;
      out_ipv4_diffserv_s7 <= out_ipv4_diffserv__st6;
      ipv4_diffserv_s7 <= ipv4_diffserv__st6;
      out_ipv4_totalLen_s7 <= out_ipv4_totalLen__st6;
      ipv4_totalLen_s7 <= ipv4_totalLen__st6;
      out_ipv4_identification_s7 <= out_ipv4_identification__st6;
      ipv4_identification_s7 <= ipv4_identification__st6;
      out_ipv4_flags_s7 <= out_ipv4_flags__st6;
      ipv4_flags_s7 <= ipv4_flags__st6;
      out_ipv4_fragOffset_s7 <= out_ipv4_fragOffset__st6;
      ipv4_fragOffset_s7 <= ipv4_fragOffset__st6;
      out_ipv4_ttl_s7 <= out_ipv4_ttl__st6;
      ipv4_ttl_s7 <= ipv4_ttl__st6;
      out_ipv4_protocol_s7 <= out_ipv4_protocol__st6;
      ipv4_protocol_s7 <= ipv4_protocol__st6;
      out_ipv4_hdrChecksum_s7 <= out_ipv4_hdrChecksum__st6;
      ipv4_hdrChecksum_s7 <= ipv4_hdrChecksum__st6;
      out_ipv4_srcAddr_s7 <= out_ipv4_srcAddr__st6;
      ipv4_srcAddr_s7 <= ipv4_srcAddr__st6;
      out_ipv4_dstAddr_s7 <= out_ipv4_dstAddr__st6;
      ipv4_dstAddr_s7 <= ipv4_dstAddr__st6;
      out_tcp_srcPort_s7 <= out_tcp_srcPort__st6;
      tcp_srcPort_s7 <= tcp_srcPort__st6;
      out_tcp_dstPort_s7 <= out_tcp_dstPort__st6;
      tcp_dstPort_s7 <= tcp_dstPort__st6;
      out_tcp_seqNo_s7 <= out_tcp_seqNo__st6;
      tcp_seqNo_s7 <= tcp_seqNo__st6;
      out_tcp_ackNo_s7 <= out_tcp_ackNo__st6;
      tcp_ackNo_s7 <= tcp_ackNo__st6;
      out_tcp_dataOffset_s7 <= out_tcp_dataOffset__st6;
      tcp_dataOffset_s7 <= tcp_dataOffset__st6;
      out_tcp_reserved_s7 <= out_tcp_reserved__st6;
      tcp_reserved_s7 <= tcp_reserved__st6;
      out_tcp_flags_s7 <= out_tcp_flags__st6;
      tcp_flags_s7 <= tcp_flags__st6;
      out_tcp_window_s7 <= out_tcp_window__st6;
      tcp_window_s7 <= tcp_window__st6;
      out_tcp_checksum_s7 <= out_tcp_checksum__st6;
      tcp_checksum_s7 <= tcp_checksum__st6;
      out_tcp_urgentPtr_s7 <= out_tcp_urgentPtr__st6;
      tcp_urgentPtr_s7 <= tcp_urgentPtr__st6;
      out_udp_srcPort_s7 <= out_udp_srcPort__st6;
      udp_srcPort_s7 <= udp_srcPort__st6;
      out_udp_dstPort_s7 <= out_udp_dstPort__st6;
      udp_dstPort_s7 <= udp_dstPort__st6;
      out_udp_length_s7 <= out_udp_length__st6;
      udp_length_s7 <= udp_length__st6;
      out_udp_checksum_s7 <= out_udp_checksum__st6;
      udp_checksum_s7 <= udp_checksum__st6;
      out_mpls_0_label_s7 <= out_mpls_0_label__st6;
      mpls_0_label_s7 <= mpls_0_label__st6;
      out_mpls_0_tc_s7 <= out_mpls_0_tc__st6;
      mpls_0_tc_s7 <= mpls_0_tc__st6;
      out_mpls_0_bos_s7 <= out_mpls_0_bos__st6;
      mpls_0_bos_s7 <= mpls_0_bos__st6;
      out_mpls_0_ttl_s7 <= out_mpls_0_ttl__st6;
      mpls_0_ttl_s7 <= mpls_0_ttl__st6;
      out_mpls_1_label_s7 <= out_mpls_1_label__st6;
      mpls_1_label_s7 <= mpls_1_label__st6;
      out_mpls_1_tc_s7 <= out_mpls_1_tc__st6;
      mpls_1_tc_s7 <= mpls_1_tc__st6;
      out_mpls_1_bos_s7 <= out_mpls_1_bos__st6;
      mpls_1_bos_s7 <= mpls_1_bos__st6;
      out_mpls_1_ttl_s7 <= out_mpls_1_ttl__st6;
      mpls_1_ttl_s7 <= mpls_1_ttl__st6;
      out_mpls_2_label_s7 <= out_mpls_2_label__st6;
      mpls_2_label_s7 <= mpls_2_label__st6;
      out_mpls_2_tc_s7 <= out_mpls_2_tc__st6;
      mpls_2_tc_s7 <= mpls_2_tc__st6;
      out_mpls_2_bos_s7 <= out_mpls_2_bos__st6;
      mpls_2_bos_s7 <= mpls_2_bos__st6;
      out_mpls_2_ttl_s7 <= out_mpls_2_ttl__st6;
      mpls_2_ttl_s7 <= mpls_2_ttl__st6;
      out_std_meta_egress_port_s7 <= out_std_meta_egress_port__st6;
      std_meta_ingress_port_s7 <= std_meta_ingress_port__st6;
      __stage_cond_3_r <= (__stage_cond_2_r);
    end
  end

  // ---- Pipeline stage 7 (registered 7 cycle(s) after stage 0) ----
  always_comb begin
    drop__st7 = drop_s7;
    _padding_0__st7 = _padding_0_s7;
    key_0__st7 = key_0_s7;
    tmp__st7 = tmp_s7;
    tmp_0__st7 = tmp_0_s7;
    tmp_1__st7 = tmp_1_s7;
    meta_ingress_port_w__st7 = meta_ingress_port_w_s7;
    meta_egress_port_w__st7 = meta_egress_port_w_s7;
    meta_packet_length_w__st7 = meta_packet_length_w_s7;
    meta_priority_w__st7 = meta_priority_w_s7;
    meta_mcast_grp_w__st7 = meta_mcast_grp_w_s7;
    meta_egress_rid_w__st7 = meta_egress_rid_w_s7;
    meta_checksum_error_w__st7 = meta_checksum_error_w_s7;
    meta_enq_timestamp_w__st7 = meta_enq_timestamp_w_s7;
    meta_enq_qdepth_w__st7 = meta_enq_qdepth_w_s7;
    meta_deq_timedelta_w__st7 = meta_deq_timedelta_w_s7;
    meta_deq_qdepth_w__st7 = meta_deq_qdepth_w_s7;
    meta_ingress_global_timestamp_w__st7 = meta_ingress_global_timestamp_w_s7;
    meta_egress_global_timestamp_w__st7 = meta_egress_global_timestamp_w_s7;
    meta_ttl_w__st7 = meta_ttl_w_s7;
    meta_next_hop_w__st7 = meta_next_hop_w_s7;
    meta_mpls_label_swap_w__st7 = meta_mpls_label_swap_w_s7;
    meta_drop_w__st7 = meta_drop_w_s7;
    meta_ecmp_select_w__st7 = meta_ecmp_select_w_s7;
    out_ethernet_valid__st7 = out_ethernet_valid_s7;
    ethernet_valid__st7 = ethernet_valid_s7;
    out_ipv4_valid__st7 = out_ipv4_valid_s7;
    ipv4_valid__st7 = ipv4_valid_s7;
    out_tcp_valid__st7 = out_tcp_valid_s7;
    tcp_valid__st7 = tcp_valid_s7;
    out_udp_valid__st7 = out_udp_valid_s7;
    udp_valid__st7 = udp_valid_s7;
    out_mpls_0_valid__st7 = out_mpls_0_valid_s7;
    mpls_0_valid__st7 = mpls_0_valid_s7;
    out_mpls_1_valid__st7 = out_mpls_1_valid_s7;
    mpls_1_valid__st7 = mpls_1_valid_s7;
    out_mpls_2_valid__st7 = out_mpls_2_valid_s7;
    mpls_2_valid__st7 = mpls_2_valid_s7;
    out_ethernet_dstAddr__st7 = out_ethernet_dstAddr_s7;
    ethernet_dstAddr__st7 = ethernet_dstAddr_s7;
    out_ethernet_srcAddr__st7 = out_ethernet_srcAddr_s7;
    ethernet_srcAddr__st7 = ethernet_srcAddr_s7;
    out_ethernet_etherType__st7 = out_ethernet_etherType_s7;
    ethernet_etherType__st7 = ethernet_etherType_s7;
    out_ipv4_version__st7 = out_ipv4_version_s7;
    ipv4_version__st7 = ipv4_version_s7;
    out_ipv4_ihl__st7 = out_ipv4_ihl_s7;
    ipv4_ihl__st7 = ipv4_ihl_s7;
    out_ipv4_diffserv__st7 = out_ipv4_diffserv_s7;
    ipv4_diffserv__st7 = ipv4_diffserv_s7;
    out_ipv4_totalLen__st7 = out_ipv4_totalLen_s7;
    ipv4_totalLen__st7 = ipv4_totalLen_s7;
    out_ipv4_identification__st7 = out_ipv4_identification_s7;
    ipv4_identification__st7 = ipv4_identification_s7;
    out_ipv4_flags__st7 = out_ipv4_flags_s7;
    ipv4_flags__st7 = ipv4_flags_s7;
    out_ipv4_fragOffset__st7 = out_ipv4_fragOffset_s7;
    ipv4_fragOffset__st7 = ipv4_fragOffset_s7;
    out_ipv4_ttl__st7 = out_ipv4_ttl_s7;
    ipv4_ttl__st7 = ipv4_ttl_s7;
    out_ipv4_protocol__st7 = out_ipv4_protocol_s7;
    ipv4_protocol__st7 = ipv4_protocol_s7;
    out_ipv4_hdrChecksum__st7 = out_ipv4_hdrChecksum_s7;
    ipv4_hdrChecksum__st7 = ipv4_hdrChecksum_s7;
    out_ipv4_srcAddr__st7 = out_ipv4_srcAddr_s7;
    ipv4_srcAddr__st7 = ipv4_srcAddr_s7;
    out_ipv4_dstAddr__st7 = out_ipv4_dstAddr_s7;
    ipv4_dstAddr__st7 = ipv4_dstAddr_s7;
    out_tcp_srcPort__st7 = out_tcp_srcPort_s7;
    tcp_srcPort__st7 = tcp_srcPort_s7;
    out_tcp_dstPort__st7 = out_tcp_dstPort_s7;
    tcp_dstPort__st7 = tcp_dstPort_s7;
    out_tcp_seqNo__st7 = out_tcp_seqNo_s7;
    tcp_seqNo__st7 = tcp_seqNo_s7;
    out_tcp_ackNo__st7 = out_tcp_ackNo_s7;
    tcp_ackNo__st7 = tcp_ackNo_s7;
    out_tcp_dataOffset__st7 = out_tcp_dataOffset_s7;
    tcp_dataOffset__st7 = tcp_dataOffset_s7;
    out_tcp_reserved__st7 = out_tcp_reserved_s7;
    tcp_reserved__st7 = tcp_reserved_s7;
    out_tcp_flags__st7 = out_tcp_flags_s7;
    tcp_flags__st7 = tcp_flags_s7;
    out_tcp_window__st7 = out_tcp_window_s7;
    tcp_window__st7 = tcp_window_s7;
    out_tcp_checksum__st7 = out_tcp_checksum_s7;
    tcp_checksum__st7 = tcp_checksum_s7;
    out_tcp_urgentPtr__st7 = out_tcp_urgentPtr_s7;
    tcp_urgentPtr__st7 = tcp_urgentPtr_s7;
    out_udp_srcPort__st7 = out_udp_srcPort_s7;
    udp_srcPort__st7 = udp_srcPort_s7;
    out_udp_dstPort__st7 = out_udp_dstPort_s7;
    udp_dstPort__st7 = udp_dstPort_s7;
    out_udp_length__st7 = out_udp_length_s7;
    udp_length__st7 = udp_length_s7;
    out_udp_checksum__st7 = out_udp_checksum_s7;
    udp_checksum__st7 = udp_checksum_s7;
    out_mpls_0_label__st7 = out_mpls_0_label_s7;
    mpls_0_label__st7 = mpls_0_label_s7;
    out_mpls_0_tc__st7 = out_mpls_0_tc_s7;
    mpls_0_tc__st7 = mpls_0_tc_s7;
    out_mpls_0_bos__st7 = out_mpls_0_bos_s7;
    mpls_0_bos__st7 = mpls_0_bos_s7;
    out_mpls_0_ttl__st7 = out_mpls_0_ttl_s7;
    mpls_0_ttl__st7 = mpls_0_ttl_s7;
    out_mpls_1_label__st7 = out_mpls_1_label_s7;
    mpls_1_label__st7 = mpls_1_label_s7;
    out_mpls_1_tc__st7 = out_mpls_1_tc_s7;
    mpls_1_tc__st7 = mpls_1_tc_s7;
    out_mpls_1_bos__st7 = out_mpls_1_bos_s7;
    mpls_1_bos__st7 = mpls_1_bos_s7;
    out_mpls_1_ttl__st7 = out_mpls_1_ttl_s7;
    mpls_1_ttl__st7 = mpls_1_ttl_s7;
    out_mpls_2_label__st7 = out_mpls_2_label_s7;
    mpls_2_label__st7 = mpls_2_label_s7;
    out_mpls_2_tc__st7 = out_mpls_2_tc_s7;
    mpls_2_tc__st7 = mpls_2_tc_s7;
    out_mpls_2_bos__st7 = out_mpls_2_bos_s7;
    mpls_2_bos__st7 = mpls_2_bos_s7;
    out_mpls_2_ttl__st7 = out_mpls_2_ttl_s7;
    mpls_2_ttl__st7 = mpls_2_ttl_s7;
    out_std_meta_egress_port__st7 = out_std_meta_egress_port_s7;
    std_meta_ingress_port__st7 = std_meta_ingress_port_s7;
  end

  // Forward stage-7 state into stage-8 registers (1-cycle
  // boundary — matches the exact-match table's registered latency)
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      valid_s8 <= 1'b0;
    end else begin
      valid_s8 <= valid_s7;
      drop_s8 <= drop__st7;
      _padding_0_s8 <= _padding_0__st7;
      key_0_s8 <= key_0__st7;
      tmp_s8 <= tmp__st7;
      tmp_0_s8 <= tmp_0__st7;
      tmp_1_s8 <= tmp_1__st7;
      meta_ingress_port_w_s8 <= meta_ingress_port_w__st7;
      meta_egress_port_w_s8 <= meta_egress_port_w__st7;
      meta_packet_length_w_s8 <= meta_packet_length_w__st7;
      meta_priority_w_s8 <= meta_priority_w__st7;
      meta_mcast_grp_w_s8 <= meta_mcast_grp_w__st7;
      meta_egress_rid_w_s8 <= meta_egress_rid_w__st7;
      meta_checksum_error_w_s8 <= meta_checksum_error_w__st7;
      meta_enq_timestamp_w_s8 <= meta_enq_timestamp_w__st7;
      meta_enq_qdepth_w_s8 <= meta_enq_qdepth_w__st7;
      meta_deq_timedelta_w_s8 <= meta_deq_timedelta_w__st7;
      meta_deq_qdepth_w_s8 <= meta_deq_qdepth_w__st7;
      meta_ingress_global_timestamp_w_s8 <= meta_ingress_global_timestamp_w__st7;
      meta_egress_global_timestamp_w_s8 <= meta_egress_global_timestamp_w__st7;
      meta_ttl_w_s8 <= meta_ttl_w__st7;
      meta_next_hop_w_s8 <= meta_next_hop_w__st7;
      meta_mpls_label_swap_w_s8 <= meta_mpls_label_swap_w__st7;
      meta_drop_w_s8 <= meta_drop_w__st7;
      meta_ecmp_select_w_s8 <= meta_ecmp_select_w__st7;
      out_ethernet_valid_s8 <= out_ethernet_valid__st7;
      ethernet_valid_s8 <= ethernet_valid__st7;
      out_ipv4_valid_s8 <= out_ipv4_valid__st7;
      ipv4_valid_s8 <= ipv4_valid__st7;
      out_tcp_valid_s8 <= out_tcp_valid__st7;
      tcp_valid_s8 <= tcp_valid__st7;
      out_udp_valid_s8 <= out_udp_valid__st7;
      udp_valid_s8 <= udp_valid__st7;
      out_mpls_0_valid_s8 <= out_mpls_0_valid__st7;
      mpls_0_valid_s8 <= mpls_0_valid__st7;
      out_mpls_1_valid_s8 <= out_mpls_1_valid__st7;
      mpls_1_valid_s8 <= mpls_1_valid__st7;
      out_mpls_2_valid_s8 <= out_mpls_2_valid__st7;
      mpls_2_valid_s8 <= mpls_2_valid__st7;
      out_ethernet_dstAddr_s8 <= out_ethernet_dstAddr__st7;
      ethernet_dstAddr_s8 <= ethernet_dstAddr__st7;
      out_ethernet_srcAddr_s8 <= out_ethernet_srcAddr__st7;
      ethernet_srcAddr_s8 <= ethernet_srcAddr__st7;
      out_ethernet_etherType_s8 <= out_ethernet_etherType__st7;
      ethernet_etherType_s8 <= ethernet_etherType__st7;
      out_ipv4_version_s8 <= out_ipv4_version__st7;
      ipv4_version_s8 <= ipv4_version__st7;
      out_ipv4_ihl_s8 <= out_ipv4_ihl__st7;
      ipv4_ihl_s8 <= ipv4_ihl__st7;
      out_ipv4_diffserv_s8 <= out_ipv4_diffserv__st7;
      ipv4_diffserv_s8 <= ipv4_diffserv__st7;
      out_ipv4_totalLen_s8 <= out_ipv4_totalLen__st7;
      ipv4_totalLen_s8 <= ipv4_totalLen__st7;
      out_ipv4_identification_s8 <= out_ipv4_identification__st7;
      ipv4_identification_s8 <= ipv4_identification__st7;
      out_ipv4_flags_s8 <= out_ipv4_flags__st7;
      ipv4_flags_s8 <= ipv4_flags__st7;
      out_ipv4_fragOffset_s8 <= out_ipv4_fragOffset__st7;
      ipv4_fragOffset_s8 <= ipv4_fragOffset__st7;
      out_ipv4_ttl_s8 <= out_ipv4_ttl__st7;
      ipv4_ttl_s8 <= ipv4_ttl__st7;
      out_ipv4_protocol_s8 <= out_ipv4_protocol__st7;
      ipv4_protocol_s8 <= ipv4_protocol__st7;
      out_ipv4_hdrChecksum_s8 <= out_ipv4_hdrChecksum__st7;
      ipv4_hdrChecksum_s8 <= ipv4_hdrChecksum__st7;
      out_ipv4_srcAddr_s8 <= out_ipv4_srcAddr__st7;
      ipv4_srcAddr_s8 <= ipv4_srcAddr__st7;
      out_ipv4_dstAddr_s8 <= out_ipv4_dstAddr__st7;
      ipv4_dstAddr_s8 <= ipv4_dstAddr__st7;
      out_tcp_srcPort_s8 <= out_tcp_srcPort__st7;
      tcp_srcPort_s8 <= tcp_srcPort__st7;
      out_tcp_dstPort_s8 <= out_tcp_dstPort__st7;
      tcp_dstPort_s8 <= tcp_dstPort__st7;
      out_tcp_seqNo_s8 <= out_tcp_seqNo__st7;
      tcp_seqNo_s8 <= tcp_seqNo__st7;
      out_tcp_ackNo_s8 <= out_tcp_ackNo__st7;
      tcp_ackNo_s8 <= tcp_ackNo__st7;
      out_tcp_dataOffset_s8 <= out_tcp_dataOffset__st7;
      tcp_dataOffset_s8 <= tcp_dataOffset__st7;
      out_tcp_reserved_s8 <= out_tcp_reserved__st7;
      tcp_reserved_s8 <= tcp_reserved__st7;
      out_tcp_flags_s8 <= out_tcp_flags__st7;
      tcp_flags_s8 <= tcp_flags__st7;
      out_tcp_window_s8 <= out_tcp_window__st7;
      tcp_window_s8 <= tcp_window__st7;
      out_tcp_checksum_s8 <= out_tcp_checksum__st7;
      tcp_checksum_s8 <= tcp_checksum__st7;
      out_tcp_urgentPtr_s8 <= out_tcp_urgentPtr__st7;
      tcp_urgentPtr_s8 <= tcp_urgentPtr__st7;
      out_udp_srcPort_s8 <= out_udp_srcPort__st7;
      udp_srcPort_s8 <= udp_srcPort__st7;
      out_udp_dstPort_s8 <= out_udp_dstPort__st7;
      udp_dstPort_s8 <= udp_dstPort__st7;
      out_udp_length_s8 <= out_udp_length__st7;
      udp_length_s8 <= udp_length__st7;
      out_udp_checksum_s8 <= out_udp_checksum__st7;
      udp_checksum_s8 <= udp_checksum__st7;
      out_mpls_0_label_s8 <= out_mpls_0_label__st7;
      mpls_0_label_s8 <= mpls_0_label__st7;
      out_mpls_0_tc_s8 <= out_mpls_0_tc__st7;
      mpls_0_tc_s8 <= mpls_0_tc__st7;
      out_mpls_0_bos_s8 <= out_mpls_0_bos__st7;
      mpls_0_bos_s8 <= mpls_0_bos__st7;
      out_mpls_0_ttl_s8 <= out_mpls_0_ttl__st7;
      mpls_0_ttl_s8 <= mpls_0_ttl__st7;
      out_mpls_1_label_s8 <= out_mpls_1_label__st7;
      mpls_1_label_s8 <= mpls_1_label__st7;
      out_mpls_1_tc_s8 <= out_mpls_1_tc__st7;
      mpls_1_tc_s8 <= mpls_1_tc__st7;
      out_mpls_1_bos_s8 <= out_mpls_1_bos__st7;
      mpls_1_bos_s8 <= mpls_1_bos__st7;
      out_mpls_1_ttl_s8 <= out_mpls_1_ttl__st7;
      mpls_1_ttl_s8 <= mpls_1_ttl__st7;
      out_mpls_2_label_s8 <= out_mpls_2_label__st7;
      mpls_2_label_s8 <= mpls_2_label__st7;
      out_mpls_2_tc_s8 <= out_mpls_2_tc__st7;
      mpls_2_tc_s8 <= mpls_2_tc__st7;
      out_mpls_2_bos_s8 <= out_mpls_2_bos__st7;
      mpls_2_bos_s8 <= mpls_2_bos__st7;
      out_mpls_2_ttl_s8 <= out_mpls_2_ttl__st7;
      mpls_2_ttl_s8 <= mpls_2_ttl__st7;
      out_std_meta_egress_port_s8 <= out_std_meta_egress_port__st7;
      std_meta_ingress_port_s8 <= std_meta_ingress_port__st7;
    end
  end

  // ---- Pipeline stage 8 (registered 8 cycle(s) after stage 0) ----
  always_comb begin
    drop = drop_s8;
    _padding_0__st8 = _padding_0_s8;
    key_0__st8 = key_0_s8;
    tmp__st8 = tmp_s8;
    tmp_0__st8 = tmp_0_s8;
    tmp_1__st8 = tmp_1_s8;
    meta_ingress_port_w__st8 = meta_ingress_port_w_s8;
    meta_egress_port_w__st8 = meta_egress_port_w_s8;
    meta_packet_length_w__st8 = meta_packet_length_w_s8;
    meta_priority_w__st8 = meta_priority_w_s8;
    meta_mcast_grp_w__st8 = meta_mcast_grp_w_s8;
    meta_egress_rid_w__st8 = meta_egress_rid_w_s8;
    meta_checksum_error_w__st8 = meta_checksum_error_w_s8;
    meta_enq_timestamp_w__st8 = meta_enq_timestamp_w_s8;
    meta_enq_qdepth_w__st8 = meta_enq_qdepth_w_s8;
    meta_deq_timedelta_w__st8 = meta_deq_timedelta_w_s8;
    meta_deq_qdepth_w__st8 = meta_deq_qdepth_w_s8;
    meta_ingress_global_timestamp_w__st8 = meta_ingress_global_timestamp_w_s8;
    meta_egress_global_timestamp_w__st8 = meta_egress_global_timestamp_w_s8;
    meta_ttl_w__st8 = meta_ttl_w_s8;
    meta_next_hop_w__st8 = meta_next_hop_w_s8;
    meta_mpls_label_swap_w__st8 = meta_mpls_label_swap_w_s8;
    meta_drop_w__st8 = meta_drop_w_s8;
    meta_ecmp_select_w__st8 = meta_ecmp_select_w_s8;
    out_ethernet_valid = out_ethernet_valid_s8;
    ethernet_valid__st8 = ethernet_valid_s8;
    out_ipv4_valid = out_ipv4_valid_s8;
    ipv4_valid__st8 = ipv4_valid_s8;
    out_tcp_valid = out_tcp_valid_s8;
    tcp_valid__st8 = tcp_valid_s8;
    out_udp_valid = out_udp_valid_s8;
    udp_valid__st8 = udp_valid_s8;
    out_mpls_0_valid = out_mpls_0_valid_s8;
    mpls_0_valid__st8 = mpls_0_valid_s8;
    out_mpls_1_valid = out_mpls_1_valid_s8;
    mpls_1_valid__st8 = mpls_1_valid_s8;
    out_mpls_2_valid = out_mpls_2_valid_s8;
    mpls_2_valid__st8 = mpls_2_valid_s8;
    out_ethernet_dstAddr = out_ethernet_dstAddr_s8;
    ethernet_dstAddr__st8 = ethernet_dstAddr_s8;
    out_ethernet_srcAddr = out_ethernet_srcAddr_s8;
    ethernet_srcAddr__st8 = ethernet_srcAddr_s8;
    out_ethernet_etherType = out_ethernet_etherType_s8;
    ethernet_etherType__st8 = ethernet_etherType_s8;
    out_ipv4_version = out_ipv4_version_s8;
    ipv4_version__st8 = ipv4_version_s8;
    out_ipv4_ihl = out_ipv4_ihl_s8;
    ipv4_ihl__st8 = ipv4_ihl_s8;
    out_ipv4_diffserv = out_ipv4_diffserv_s8;
    ipv4_diffserv__st8 = ipv4_diffserv_s8;
    out_ipv4_totalLen = out_ipv4_totalLen_s8;
    ipv4_totalLen__st8 = ipv4_totalLen_s8;
    out_ipv4_identification = out_ipv4_identification_s8;
    ipv4_identification__st8 = ipv4_identification_s8;
    out_ipv4_flags = out_ipv4_flags_s8;
    ipv4_flags__st8 = ipv4_flags_s8;
    out_ipv4_fragOffset = out_ipv4_fragOffset_s8;
    ipv4_fragOffset__st8 = ipv4_fragOffset_s8;
    out_ipv4_ttl = out_ipv4_ttl_s8;
    ipv4_ttl__st8 = ipv4_ttl_s8;
    out_ipv4_protocol = out_ipv4_protocol_s8;
    ipv4_protocol__st8 = ipv4_protocol_s8;
    out_ipv4_hdrChecksum = out_ipv4_hdrChecksum_s8;
    ipv4_hdrChecksum__st8 = ipv4_hdrChecksum_s8;
    out_ipv4_srcAddr = out_ipv4_srcAddr_s8;
    ipv4_srcAddr__st8 = ipv4_srcAddr_s8;
    out_ipv4_dstAddr = out_ipv4_dstAddr_s8;
    ipv4_dstAddr__st8 = ipv4_dstAddr_s8;
    out_tcp_srcPort = out_tcp_srcPort_s8;
    tcp_srcPort__st8 = tcp_srcPort_s8;
    out_tcp_dstPort = out_tcp_dstPort_s8;
    tcp_dstPort__st8 = tcp_dstPort_s8;
    out_tcp_seqNo = out_tcp_seqNo_s8;
    tcp_seqNo__st8 = tcp_seqNo_s8;
    out_tcp_ackNo = out_tcp_ackNo_s8;
    tcp_ackNo__st8 = tcp_ackNo_s8;
    out_tcp_dataOffset = out_tcp_dataOffset_s8;
    tcp_dataOffset__st8 = tcp_dataOffset_s8;
    out_tcp_reserved = out_tcp_reserved_s8;
    tcp_reserved__st8 = tcp_reserved_s8;
    out_tcp_flags = out_tcp_flags_s8;
    tcp_flags__st8 = tcp_flags_s8;
    out_tcp_window = out_tcp_window_s8;
    tcp_window__st8 = tcp_window_s8;
    out_tcp_checksum = out_tcp_checksum_s8;
    tcp_checksum__st8 = tcp_checksum_s8;
    out_tcp_urgentPtr = out_tcp_urgentPtr_s8;
    tcp_urgentPtr__st8 = tcp_urgentPtr_s8;
    out_udp_srcPort = out_udp_srcPort_s8;
    udp_srcPort__st8 = udp_srcPort_s8;
    out_udp_dstPort = out_udp_dstPort_s8;
    udp_dstPort__st8 = udp_dstPort_s8;
    out_udp_length = out_udp_length_s8;
    udp_length__st8 = udp_length_s8;
    out_udp_checksum = out_udp_checksum_s8;
    udp_checksum__st8 = udp_checksum_s8;
    out_mpls_0_label = out_mpls_0_label_s8;
    mpls_0_label__st8 = mpls_0_label_s8;
    out_mpls_0_tc = out_mpls_0_tc_s8;
    mpls_0_tc__st8 = mpls_0_tc_s8;
    out_mpls_0_bos = out_mpls_0_bos_s8;
    mpls_0_bos__st8 = mpls_0_bos_s8;
    out_mpls_0_ttl = out_mpls_0_ttl_s8;
    mpls_0_ttl__st8 = mpls_0_ttl_s8;
    out_mpls_1_label = out_mpls_1_label_s8;
    mpls_1_label__st8 = mpls_1_label_s8;
    out_mpls_1_tc = out_mpls_1_tc_s8;
    mpls_1_tc__st8 = mpls_1_tc_s8;
    out_mpls_1_bos = out_mpls_1_bos_s8;
    mpls_1_bos__st8 = mpls_1_bos_s8;
    out_mpls_1_ttl = out_mpls_1_ttl_s8;
    mpls_1_ttl__st8 = mpls_1_ttl_s8;
    out_mpls_2_label = out_mpls_2_label_s8;
    mpls_2_label__st8 = mpls_2_label_s8;
    out_mpls_2_tc = out_mpls_2_tc_s8;
    mpls_2_tc__st8 = mpls_2_tc_s8;
    out_mpls_2_bos = out_mpls_2_bos_s8;
    mpls_2_bos__st8 = mpls_2_bos_s8;
    out_mpls_2_ttl = out_mpls_2_ttl_s8;
    mpls_2_ttl__st8 = mpls_2_ttl_s8;
    out_std_meta_egress_port = out_std_meta_egress_port_s8;
    std_meta_ingress_port__st8 = std_meta_ingress_port_s8;

    // apply block (stage 8 of 8)
    if (__stage_cond_3_r) begin
      // ipv4_route.apply()
      if (ipv4_route_hit) begin
        unique case (ipv4_route_act_id)
          2'd0: ; // NoAction
          2'd1: begin // set_next_hop
            meta_next_hop_w__st8 = ipv4_route_p_next_hop;
          end
          2'd2: begin // decrement_ttl
            out_ipv4_ttl = ((ipv4_ttl__st8 + 'hFF) & 'hFF);
            if ((ipv4_ttl__st8 == 'h00)) begin
              meta_drop_w__st8 = 'h01;
            end
          end
          default: ; // default = NoAction
        endcase
      end
    end
    // ecmp_group.apply()
    if (ecmp_group_hit) begin
      unique case (ecmp_group_act_id)
        1'd0: ; // NoAction
        1'd1: begin // set_ecmp_hash
          tmp_0__st8 = ipv4_srcAddr__st8;
          tmp_1__st8 = ipv4_dstAddr__st8;
          // hash() stub — XOR-based behavioral approximation
          meta_ecmp_select_w__st8 = (tmp_0__st8 ^ tmp_1__st8) & 12'hFFF;
        end
        default: ; // default = set_ecmp_hash
      endcase
    end else begin // set_ecmp_hash on miss
      tmp_0__st8 = ipv4_srcAddr__st8;
      tmp_1__st8 = ipv4_dstAddr__st8;
      // hash() stub — XOR-based behavioral approximation
      meta_ecmp_select_w__st8 = (tmp_0__st8 ^ tmp_1__st8) & 12'hFFF;
    end
    if ((meta_drop_w__st8 == 'h01)) begin
      drop = 1;
    end
  end

  // Register write-back (initialized via initial block above)
  always_ff @(posedge clk) begin
    if (conn_state_wr_en)
      conn_state_mem[conn_state_wr_addr] <= conn_state_wr_data;
  end

  always_ff @(posedge clk) begin
    if (!rst_n) valid_out <= 0;
    else        valid_out <= valid_s8;
  end

endmodule
