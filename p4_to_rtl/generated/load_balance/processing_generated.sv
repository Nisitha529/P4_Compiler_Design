module processing_generated (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        valid_in,

  // Header valid flags
  input  logic        ethernet_valid,
  input  logic        ipv4_valid,
  input  logic        tcp_valid,

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
  input  logic [2:0] tcp_res,
  input  logic [2:0] tcp_ecn,
  input  logic [5:0] tcp_ctrl,
  input  logic [15:0] tcp_window,
  input  logic [15:0] tcp_checksum,
  input  logic [15:0] tcp_urgentPtr,

  // Metadata inputs
  input  logic [13:0] meta_ecmp_select,

  // Header valid flag outputs (may be modified by setValid/setInvalid)
  output logic        out_ethernet_valid,
  output logic        out_ipv4_valid,
  output logic        out_tcp_valid,

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
  output logic [2:0] out_tcp_res,
  output logic [2:0] out_tcp_ecn,
  output logic [5:0] out_tcp_ctrl,
  output logic [15:0] out_tcp_window,
  output logic [15:0] out_tcp_checksum,
  output logic [15:0] out_tcp_urgentPtr,

  // Standard metadata outputs
  output logic [8:0] out_std_meta_egress_spec,

  // Metadata outputs (final value after the last stage)
  output logic [13:0] out_meta_ecmp_select,

  // Control-plane write ports for table instances
  input  logic        ecmp_group_cp_wr_en,
  input  logic [7:0] ecmp_group_cp_wr_idx,
  input  logic [31:0] ecmp_group_cp_wr_key_dstAddr,
  input  logic [5:0] ecmp_group_cp_wr_pfx_len,
  input  logic [1:0] ecmp_group_cp_wr_action,
  input  logic [15:0] ecmp_group_cp_wr_p_ecmp_base,
  input  logic [31:0] ecmp_group_cp_wr_p_ecmp_count,
  input  logic        ecmp_nhop_cp_wr_en,
  input  logic [0:0] ecmp_nhop_cp_wr_idx,
  input  logic [31:0] ecmp_nhop_cp_wr_key_ecmp_select,
  input  logic [1:0] ecmp_nhop_cp_wr_action,
  input  logic [47:0] ecmp_nhop_cp_wr_p_nhop_dmac,
  input  logic [31:0] ecmp_nhop_cp_wr_p_nhop_ipv4,
  input  logic [8:0] ecmp_nhop_cp_wr_p_port,

  // Table hit outputs
  output logic        ecmp_group_hit_out,
  output logic        ecmp_nhop_hit_out,

  output logic        valid_out,
  output logic        drop
);

  logic [1:0] _padding_0;
  logic [31:0] tmp;
  logic [31:0] tmp_0;
  logic [7:0] tmp_1;
  logic [15:0] tmp_2;
  logic [15:0] tmp_3;

  // Metadata shadow locals (writable copies of metadata inputs)
  logic [13:0] meta_ecmp_select_w;

  // Pipeline-stage forwarding registers (one set per exact-match
  // table boundary in the chain)
  logic valid_s1;
  logic out_ethernet_valid_s1;
  logic ethernet_valid_s1;
  logic out_ipv4_valid_s1;
  logic ipv4_valid_s1;
  logic out_tcp_valid_s1;
  logic tcp_valid_s1;
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
  logic [2:0] out_tcp_res_s1;
  logic [2:0] tcp_res_s1;
  logic [2:0] out_tcp_ecn_s1;
  logic [2:0] tcp_ecn_s1;
  logic [5:0] out_tcp_ctrl_s1;
  logic [5:0] tcp_ctrl_s1;
  logic [15:0] out_tcp_window_s1;
  logic [15:0] tcp_window_s1;
  logic [15:0] out_tcp_checksum_s1;
  logic [15:0] tcp_checksum_s1;
  logic [15:0] out_tcp_urgentPtr_s1;
  logic [15:0] tcp_urgentPtr_s1;
  logic [13:0] meta_ecmp_select_w_s1;
  logic [1:0] _padding_0_s1;
  logic [31:0] tmp_s1;
  logic [31:0] tmp_0_s1;
  logic [7:0] tmp_1_s1;
  logic [15:0] tmp_2_s1;
  logic [15:0] tmp_3_s1;
  logic [8:0] out_std_meta_egress_spec_s1;
  logic drop_s1;
  logic __stage_cond_0_r;
  logic valid_s2;
  logic out_ethernet_valid_s2;
  logic ethernet_valid_s2;
  logic out_ipv4_valid_s2;
  logic ipv4_valid_s2;
  logic out_tcp_valid_s2;
  logic tcp_valid_s2;
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
  logic [2:0] out_tcp_res_s2;
  logic [2:0] tcp_res_s2;
  logic [2:0] out_tcp_ecn_s2;
  logic [2:0] tcp_ecn_s2;
  logic [5:0] out_tcp_ctrl_s2;
  logic [5:0] tcp_ctrl_s2;
  logic [15:0] out_tcp_window_s2;
  logic [15:0] tcp_window_s2;
  logic [15:0] out_tcp_checksum_s2;
  logic [15:0] tcp_checksum_s2;
  logic [15:0] out_tcp_urgentPtr_s2;
  logic [15:0] tcp_urgentPtr_s2;
  logic [13:0] meta_ecmp_select_w_s2;
  logic [1:0] _padding_0_s2;
  logic [31:0] tmp_s2;
  logic [31:0] tmp_0_s2;
  logic [7:0] tmp_1_s2;
  logic [15:0] tmp_2_s2;
  logic [15:0] tmp_3_s2;
  logic [8:0] out_std_meta_egress_spec_s2;
  logic drop_s2;
  logic valid_s3;
  logic out_ethernet_valid_s3;
  logic ethernet_valid_s3;
  logic out_ipv4_valid_s3;
  logic ipv4_valid_s3;
  logic out_tcp_valid_s3;
  logic tcp_valid_s3;
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
  logic [2:0] out_tcp_res_s3;
  logic [2:0] tcp_res_s3;
  logic [2:0] out_tcp_ecn_s3;
  logic [2:0] tcp_ecn_s3;
  logic [5:0] out_tcp_ctrl_s3;
  logic [5:0] tcp_ctrl_s3;
  logic [15:0] out_tcp_window_s3;
  logic [15:0] tcp_window_s3;
  logic [15:0] out_tcp_checksum_s3;
  logic [15:0] tcp_checksum_s3;
  logic [15:0] out_tcp_urgentPtr_s3;
  logic [15:0] tcp_urgentPtr_s3;
  logic [13:0] meta_ecmp_select_w_s3;
  logic [1:0] _padding_0_s3;
  logic [31:0] tmp_s3;
  logic [31:0] tmp_0_s3;
  logic [7:0] tmp_1_s3;
  logic [15:0] tmp_2_s3;
  logic [15:0] tmp_3_s3;
  logic [8:0] out_std_meta_egress_spec_s3;
  logic drop_s3;
  logic __stage_cond_1_r;
  logic valid_s4;
  logic out_ethernet_valid_s4;
  logic ethernet_valid_s4;
  logic out_ipv4_valid_s4;
  logic ipv4_valid_s4;
  logic out_tcp_valid_s4;
  logic tcp_valid_s4;
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
  logic [2:0] out_tcp_res_s4;
  logic [2:0] tcp_res_s4;
  logic [2:0] out_tcp_ecn_s4;
  logic [2:0] tcp_ecn_s4;
  logic [5:0] out_tcp_ctrl_s4;
  logic [5:0] tcp_ctrl_s4;
  logic [15:0] out_tcp_window_s4;
  logic [15:0] tcp_window_s4;
  logic [15:0] out_tcp_checksum_s4;
  logic [15:0] tcp_checksum_s4;
  logic [15:0] out_tcp_urgentPtr_s4;
  logic [15:0] tcp_urgentPtr_s4;
  logic [13:0] meta_ecmp_select_w_s4;
  logic [1:0] _padding_0_s4;
  logic [31:0] tmp_s4;
  logic [31:0] tmp_0_s4;
  logic [7:0] tmp_1_s4;
  logic [15:0] tmp_2_s4;
  logic [15:0] tmp_3_s4;
  logic [8:0] out_std_meta_egress_spec_s4;
  logic drop_s4;

  // Pool-A (out_*/drop) working copies -- every stage except the
  // last, which drives the real output ports directly
  logic out_ethernet_valid__st0;
  logic out_ipv4_valid__st0;
  logic out_tcp_valid__st0;
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
  logic [2:0] out_tcp_res__st0;
  logic [2:0] out_tcp_ecn__st0;
  logic [5:0] out_tcp_ctrl__st0;
  logic [15:0] out_tcp_window__st0;
  logic [15:0] out_tcp_checksum__st0;
  logic [15:0] out_tcp_urgentPtr__st0;
  logic [8:0] out_std_meta_egress_spec__st0;
  logic drop__st0;
  logic out_ethernet_valid__st1;
  logic out_ipv4_valid__st1;
  logic out_tcp_valid__st1;
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
  logic [2:0] out_tcp_res__st1;
  logic [2:0] out_tcp_ecn__st1;
  logic [5:0] out_tcp_ctrl__st1;
  logic [15:0] out_tcp_window__st1;
  logic [15:0] out_tcp_checksum__st1;
  logic [15:0] out_tcp_urgentPtr__st1;
  logic [8:0] out_std_meta_egress_spec__st1;
  logic drop__st1;
  logic out_ethernet_valid__st2;
  logic out_ipv4_valid__st2;
  logic out_tcp_valid__st2;
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
  logic [2:0] out_tcp_res__st2;
  logic [2:0] out_tcp_ecn__st2;
  logic [5:0] out_tcp_ctrl__st2;
  logic [15:0] out_tcp_window__st2;
  logic [15:0] out_tcp_checksum__st2;
  logic [15:0] out_tcp_urgentPtr__st2;
  logic [8:0] out_std_meta_egress_spec__st2;
  logic drop__st2;
  logic out_ethernet_valid__st3;
  logic out_ipv4_valid__st3;
  logic out_tcp_valid__st3;
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
  logic [2:0] out_tcp_res__st3;
  logic [2:0] out_tcp_ecn__st3;
  logic [5:0] out_tcp_ctrl__st3;
  logic [15:0] out_tcp_window__st3;
  logic [15:0] out_tcp_checksum__st3;
  logic [15:0] out_tcp_urgentPtr__st3;
  logic [8:0] out_std_meta_egress_spec__st3;
  logic drop__st3;

  // Pool-B (locals/meta shadow/raw hdr+std_meta reads) working
  // copies -- every stage except the first, which reads live inputs
  logic [1:0] _padding_0__st1;
  logic [31:0] tmp__st1;
  logic [31:0] tmp_0__st1;
  logic [7:0] tmp_1__st1;
  logic [15:0] tmp_2__st1;
  logic [15:0] tmp_3__st1;
  logic [13:0] meta_ecmp_select_w__st1;
  logic ethernet_valid__st1;
  logic ipv4_valid__st1;
  logic tcp_valid__st1;
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
  logic [2:0] tcp_res__st1;
  logic [2:0] tcp_ecn__st1;
  logic [5:0] tcp_ctrl__st1;
  logic [15:0] tcp_window__st1;
  logic [15:0] tcp_checksum__st1;
  logic [15:0] tcp_urgentPtr__st1;
  logic [1:0] _padding_0__st2;
  logic [31:0] tmp__st2;
  logic [31:0] tmp_0__st2;
  logic [7:0] tmp_1__st2;
  logic [15:0] tmp_2__st2;
  logic [15:0] tmp_3__st2;
  logic [13:0] meta_ecmp_select_w__st2;
  logic ethernet_valid__st2;
  logic ipv4_valid__st2;
  logic tcp_valid__st2;
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
  logic [2:0] tcp_res__st2;
  logic [2:0] tcp_ecn__st2;
  logic [5:0] tcp_ctrl__st2;
  logic [15:0] tcp_window__st2;
  logic [15:0] tcp_checksum__st2;
  logic [15:0] tcp_urgentPtr__st2;
  logic [1:0] _padding_0__st3;
  logic [31:0] tmp__st3;
  logic [31:0] tmp_0__st3;
  logic [7:0] tmp_1__st3;
  logic [15:0] tmp_2__st3;
  logic [15:0] tmp_3__st3;
  logic [13:0] meta_ecmp_select_w__st3;
  logic ethernet_valid__st3;
  logic ipv4_valid__st3;
  logic tcp_valid__st3;
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
  logic [2:0] tcp_res__st3;
  logic [2:0] tcp_ecn__st3;
  logic [5:0] tcp_ctrl__st3;
  logic [15:0] tcp_window__st3;
  logic [15:0] tcp_checksum__st3;
  logic [15:0] tcp_urgentPtr__st3;
  logic [1:0] _padding_0__st4;
  logic [31:0] tmp__st4;
  logic [31:0] tmp_0__st4;
  logic [7:0] tmp_1__st4;
  logic [15:0] tmp_2__st4;
  logic [15:0] tmp_3__st4;
  logic [13:0] meta_ecmp_select_w__st4;
  logic ethernet_valid__st4;
  logic ipv4_valid__st4;
  logic tcp_valid__st4;
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
  logic [2:0] tcp_res__st4;
  logic [2:0] tcp_ecn__st4;
  logic [5:0] tcp_ctrl__st4;
  logic [15:0] tcp_window__st4;
  logic [15:0] tcp_checksum__st4;
  logic [15:0] tcp_urgentPtr__st4;

  // Table lookup result wires
  logic        ecmp_group_hit;
  logic [1:0] ecmp_group_act_id;
  logic [15:0] ecmp_group_p_ecmp_base;
  logic [31:0] ecmp_group_p_ecmp_count;
  logic        ecmp_nhop_hit;
  logic [1:0] ecmp_nhop_act_id;
  logic [47:0] ecmp_nhop_p_nhop_dmac;
  logic [31:0] ecmp_nhop_p_nhop_ipv4;
  logic [8:0] ecmp_nhop_p_port;

  // Table module instantiations
  ecmp_group_table #(.DEPTH(256)) u_ecmp_group (
    .clk    (clk),
    .rst_n  (rst_n),
    .lkp_dstAddr    (ipv4_dstAddr),
    .hit       (ecmp_group_hit),
    .action_id (ecmp_group_act_id),
    .p_ecmp_base  (ecmp_group_p_ecmp_base),
    .p_ecmp_count  (ecmp_group_p_ecmp_count),
    .cp_wr_en  (ecmp_group_cp_wr_en),
    .cp_wr_idx (ecmp_group_cp_wr_idx),
    .cp_wr_key_dstAddr (ecmp_group_cp_wr_key_dstAddr),
    .cp_wr_pfx_len (ecmp_group_cp_wr_pfx_len),
    .cp_wr_action (ecmp_group_cp_wr_action),
    .cp_wr_p_ecmp_base (ecmp_group_cp_wr_p_ecmp_base),
    .cp_wr_p_ecmp_count (ecmp_group_cp_wr_p_ecmp_count)
  );

  ecmp_nhop_table #(.DEPTH(2)) u_ecmp_nhop (
    .clk    (clk),
    .rst_n  (rst_n),
    .lkp_ecmp_select    (metadata_ecmp_select),
    .hit       (ecmp_nhop_hit),
    .action_id (ecmp_nhop_act_id),
    .p_nhop_dmac  (ecmp_nhop_p_nhop_dmac),
    .p_nhop_ipv4  (ecmp_nhop_p_nhop_ipv4),
    .p_port  (ecmp_nhop_p_port),
    .cp_wr_en  (ecmp_nhop_cp_wr_en),
    .cp_wr_idx (ecmp_nhop_cp_wr_idx),
    .cp_wr_key_ecmp_select (ecmp_nhop_cp_wr_key_ecmp_select),
    .cp_wr_action (ecmp_nhop_cp_wr_action),
    .cp_wr_p_nhop_dmac (ecmp_nhop_cp_wr_p_nhop_dmac),
    .cp_wr_p_nhop_ipv4 (ecmp_nhop_cp_wr_p_nhop_ipv4),
    .cp_wr_p_port (ecmp_nhop_cp_wr_p_port)
  );

  // Table hit outputs
  assign ecmp_group_hit_out = ecmp_group_hit;
  assign ecmp_nhop_hit_out = ecmp_nhop_hit;

  // Metadata outputs (final value after the last stage)
  assign out_meta_ecmp_select = meta_ecmp_select_w__st4;

  // ---- Pipeline stage 0 (combinational, feeds the first exact-match table boundary) ----
  always_comb begin
    drop__st0 = 0;
    _padding_0 = 2'b0;
    tmp = 32'b0;
    tmp_0 = 32'b0;
    tmp_1 = 8'b0;
    tmp_2 = 16'b0;
    tmp_3 = 16'b0;

    // Metadata shadow defaults (init from inputs)
    meta_ecmp_select_w = meta_ecmp_select;

    // Standard metadata defaults
    out_std_meta_egress_spec__st0 = 9'b0;

    // Header valid flag pass-through defaults
    out_ethernet_valid__st0 = ethernet_valid;
    out_ipv4_valid__st0 = ipv4_valid;
    out_tcp_valid__st0 = tcp_valid;

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
    out_tcp_res__st0 = tcp_res;
    out_tcp_ecn__st0 = tcp_ecn;
    out_tcp_ctrl__st0 = tcp_ctrl;
    out_tcp_window__st0 = tcp_window;
    out_tcp_checksum__st0 = tcp_checksum;
    out_tcp_urgentPtr__st0 = tcp_urgentPtr;

    // apply block (stage 0 of 4)
    if ((ipv4_valid && (ipv4_ttl > 'h00))) begin
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
      tmp_s1 <= tmp;
      tmp_0_s1 <= tmp_0;
      tmp_1_s1 <= tmp_1;
      tmp_2_s1 <= tmp_2;
      tmp_3_s1 <= tmp_3;
      meta_ecmp_select_w_s1 <= meta_ecmp_select_w;
      out_ethernet_valid_s1 <= out_ethernet_valid__st0;
      ethernet_valid_s1 <= ethernet_valid;
      out_ipv4_valid_s1 <= out_ipv4_valid__st0;
      ipv4_valid_s1 <= ipv4_valid;
      out_tcp_valid_s1 <= out_tcp_valid__st0;
      tcp_valid_s1 <= tcp_valid;
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
      out_tcp_res_s1 <= out_tcp_res__st0;
      tcp_res_s1 <= tcp_res;
      out_tcp_ecn_s1 <= out_tcp_ecn__st0;
      tcp_ecn_s1 <= tcp_ecn;
      out_tcp_ctrl_s1 <= out_tcp_ctrl__st0;
      tcp_ctrl_s1 <= tcp_ctrl;
      out_tcp_window_s1 <= out_tcp_window__st0;
      tcp_window_s1 <= tcp_window;
      out_tcp_checksum_s1 <= out_tcp_checksum__st0;
      tcp_checksum_s1 <= tcp_checksum;
      out_tcp_urgentPtr_s1 <= out_tcp_urgentPtr__st0;
      tcp_urgentPtr_s1 <= tcp_urgentPtr;
      out_std_meta_egress_spec_s1 <= out_std_meta_egress_spec__st0;
      __stage_cond_0_r <= ((ipv4_valid && (ipv4_ttl > 'h00)));
    end
  end

  // ---- Pipeline stage 1 (registered 1 cycle(s) after stage 0) ----
  always_comb begin
    drop__st1 = drop_s1;
    _padding_0__st1 = _padding_0_s1;
    tmp__st1 = tmp_s1;
    tmp_0__st1 = tmp_0_s1;
    tmp_1__st1 = tmp_1_s1;
    tmp_2__st1 = tmp_2_s1;
    tmp_3__st1 = tmp_3_s1;
    meta_ecmp_select_w__st1 = meta_ecmp_select_w_s1;
    out_ethernet_valid__st1 = out_ethernet_valid_s1;
    ethernet_valid__st1 = ethernet_valid_s1;
    out_ipv4_valid__st1 = out_ipv4_valid_s1;
    ipv4_valid__st1 = ipv4_valid_s1;
    out_tcp_valid__st1 = out_tcp_valid_s1;
    tcp_valid__st1 = tcp_valid_s1;
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
    out_tcp_res__st1 = out_tcp_res_s1;
    tcp_res__st1 = tcp_res_s1;
    out_tcp_ecn__st1 = out_tcp_ecn_s1;
    tcp_ecn__st1 = tcp_ecn_s1;
    out_tcp_ctrl__st1 = out_tcp_ctrl_s1;
    tcp_ctrl__st1 = tcp_ctrl_s1;
    out_tcp_window__st1 = out_tcp_window_s1;
    tcp_window__st1 = tcp_window_s1;
    out_tcp_checksum__st1 = out_tcp_checksum_s1;
    tcp_checksum__st1 = tcp_checksum_s1;
    out_tcp_urgentPtr__st1 = out_tcp_urgentPtr_s1;
    tcp_urgentPtr__st1 = tcp_urgentPtr_s1;
    out_std_meta_egress_spec__st1 = out_std_meta_egress_spec_s1;
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
      tmp_s2 <= tmp__st1;
      tmp_0_s2 <= tmp_0__st1;
      tmp_1_s2 <= tmp_1__st1;
      tmp_2_s2 <= tmp_2__st1;
      tmp_3_s2 <= tmp_3__st1;
      meta_ecmp_select_w_s2 <= meta_ecmp_select_w__st1;
      out_ethernet_valid_s2 <= out_ethernet_valid__st1;
      ethernet_valid_s2 <= ethernet_valid__st1;
      out_ipv4_valid_s2 <= out_ipv4_valid__st1;
      ipv4_valid_s2 <= ipv4_valid__st1;
      out_tcp_valid_s2 <= out_tcp_valid__st1;
      tcp_valid_s2 <= tcp_valid__st1;
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
      out_tcp_res_s2 <= out_tcp_res__st1;
      tcp_res_s2 <= tcp_res__st1;
      out_tcp_ecn_s2 <= out_tcp_ecn__st1;
      tcp_ecn_s2 <= tcp_ecn__st1;
      out_tcp_ctrl_s2 <= out_tcp_ctrl__st1;
      tcp_ctrl_s2 <= tcp_ctrl__st1;
      out_tcp_window_s2 <= out_tcp_window__st1;
      tcp_window_s2 <= tcp_window__st1;
      out_tcp_checksum_s2 <= out_tcp_checksum__st1;
      tcp_checksum_s2 <= tcp_checksum__st1;
      out_tcp_urgentPtr_s2 <= out_tcp_urgentPtr__st1;
      tcp_urgentPtr_s2 <= tcp_urgentPtr__st1;
      out_std_meta_egress_spec_s2 <= out_std_meta_egress_spec__st1;
    end
  end

  // ---- Pipeline stage 2 (registered 2 cycle(s) after stage 0) ----
  always_comb begin
    drop__st2 = drop_s2;
    _padding_0__st2 = _padding_0_s2;
    tmp__st2 = tmp_s2;
    tmp_0__st2 = tmp_0_s2;
    tmp_1__st2 = tmp_1_s2;
    tmp_2__st2 = tmp_2_s2;
    tmp_3__st2 = tmp_3_s2;
    meta_ecmp_select_w__st2 = meta_ecmp_select_w_s2;
    out_ethernet_valid__st2 = out_ethernet_valid_s2;
    ethernet_valid__st2 = ethernet_valid_s2;
    out_ipv4_valid__st2 = out_ipv4_valid_s2;
    ipv4_valid__st2 = ipv4_valid_s2;
    out_tcp_valid__st2 = out_tcp_valid_s2;
    tcp_valid__st2 = tcp_valid_s2;
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
    out_tcp_res__st2 = out_tcp_res_s2;
    tcp_res__st2 = tcp_res_s2;
    out_tcp_ecn__st2 = out_tcp_ecn_s2;
    tcp_ecn__st2 = tcp_ecn_s2;
    out_tcp_ctrl__st2 = out_tcp_ctrl_s2;
    tcp_ctrl__st2 = tcp_ctrl_s2;
    out_tcp_window__st2 = out_tcp_window_s2;
    tcp_window__st2 = tcp_window_s2;
    out_tcp_checksum__st2 = out_tcp_checksum_s2;
    tcp_checksum__st2 = tcp_checksum_s2;
    out_tcp_urgentPtr__st2 = out_tcp_urgentPtr_s2;
    tcp_urgentPtr__st2 = tcp_urgentPtr_s2;
    out_std_meta_egress_spec__st2 = out_std_meta_egress_spec_s2;

    // apply block (stage 2 of 4)
    if (__stage_cond_0_r) begin
      // ecmp_group.apply()
      if (ecmp_group_hit) begin
        unique case (ecmp_group_act_id)
          2'd0: ; // NoAction
          2'd1: begin // drop__st2
            drop__st2 = 1;
          end
          2'd2: begin // set_ecmp_select
            tmp__st2 = ipv4_srcAddr__st2;
            tmp_0__st2 = ipv4_dstAddr__st2;
            tmp_1__st2 = ipv4_protocol__st2;
            tmp_2__st2 = tcp_srcPort__st2;
            tmp_3__st2 = tcp_dstPort__st2;
            // hash() stub — XOR-based behavioral approximation
            meta_ecmp_select_w__st2 = (tmp__st2 ^ tmp_0__st2 ^ tmp_1__st2 ^ tmp_2__st2 ^ tmp_3__st2) & 12'hFFF;
          end
          default: ; // default = NoAction
        endcase
      end
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
      tmp_s3 <= tmp__st2;
      tmp_0_s3 <= tmp_0__st2;
      tmp_1_s3 <= tmp_1__st2;
      tmp_2_s3 <= tmp_2__st2;
      tmp_3_s3 <= tmp_3__st2;
      meta_ecmp_select_w_s3 <= meta_ecmp_select_w__st2;
      out_ethernet_valid_s3 <= out_ethernet_valid__st2;
      ethernet_valid_s3 <= ethernet_valid__st2;
      out_ipv4_valid_s3 <= out_ipv4_valid__st2;
      ipv4_valid_s3 <= ipv4_valid__st2;
      out_tcp_valid_s3 <= out_tcp_valid__st2;
      tcp_valid_s3 <= tcp_valid__st2;
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
      out_tcp_res_s3 <= out_tcp_res__st2;
      tcp_res_s3 <= tcp_res__st2;
      out_tcp_ecn_s3 <= out_tcp_ecn__st2;
      tcp_ecn_s3 <= tcp_ecn__st2;
      out_tcp_ctrl_s3 <= out_tcp_ctrl__st2;
      tcp_ctrl_s3 <= tcp_ctrl__st2;
      out_tcp_window_s3 <= out_tcp_window__st2;
      tcp_window_s3 <= tcp_window__st2;
      out_tcp_checksum_s3 <= out_tcp_checksum__st2;
      tcp_checksum_s3 <= tcp_checksum__st2;
      out_tcp_urgentPtr_s3 <= out_tcp_urgentPtr__st2;
      tcp_urgentPtr_s3 <= tcp_urgentPtr__st2;
      out_std_meta_egress_spec_s3 <= out_std_meta_egress_spec__st2;
      __stage_cond_1_r <= (__stage_cond_0_r);
    end
  end

  // ---- Pipeline stage 3 (registered 3 cycle(s) after stage 0) ----
  always_comb begin
    drop__st3 = drop_s3;
    _padding_0__st3 = _padding_0_s3;
    tmp__st3 = tmp_s3;
    tmp_0__st3 = tmp_0_s3;
    tmp_1__st3 = tmp_1_s3;
    tmp_2__st3 = tmp_2_s3;
    tmp_3__st3 = tmp_3_s3;
    meta_ecmp_select_w__st3 = meta_ecmp_select_w_s3;
    out_ethernet_valid__st3 = out_ethernet_valid_s3;
    ethernet_valid__st3 = ethernet_valid_s3;
    out_ipv4_valid__st3 = out_ipv4_valid_s3;
    ipv4_valid__st3 = ipv4_valid_s3;
    out_tcp_valid__st3 = out_tcp_valid_s3;
    tcp_valid__st3 = tcp_valid_s3;
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
    out_tcp_res__st3 = out_tcp_res_s3;
    tcp_res__st3 = tcp_res_s3;
    out_tcp_ecn__st3 = out_tcp_ecn_s3;
    tcp_ecn__st3 = tcp_ecn_s3;
    out_tcp_ctrl__st3 = out_tcp_ctrl_s3;
    tcp_ctrl__st3 = tcp_ctrl_s3;
    out_tcp_window__st3 = out_tcp_window_s3;
    tcp_window__st3 = tcp_window_s3;
    out_tcp_checksum__st3 = out_tcp_checksum_s3;
    tcp_checksum__st3 = tcp_checksum_s3;
    out_tcp_urgentPtr__st3 = out_tcp_urgentPtr_s3;
    tcp_urgentPtr__st3 = tcp_urgentPtr_s3;
    out_std_meta_egress_spec__st3 = out_std_meta_egress_spec_s3;
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
      tmp_s4 <= tmp__st3;
      tmp_0_s4 <= tmp_0__st3;
      tmp_1_s4 <= tmp_1__st3;
      tmp_2_s4 <= tmp_2__st3;
      tmp_3_s4 <= tmp_3__st3;
      meta_ecmp_select_w_s4 <= meta_ecmp_select_w__st3;
      out_ethernet_valid_s4 <= out_ethernet_valid__st3;
      ethernet_valid_s4 <= ethernet_valid__st3;
      out_ipv4_valid_s4 <= out_ipv4_valid__st3;
      ipv4_valid_s4 <= ipv4_valid__st3;
      out_tcp_valid_s4 <= out_tcp_valid__st3;
      tcp_valid_s4 <= tcp_valid__st3;
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
      out_tcp_res_s4 <= out_tcp_res__st3;
      tcp_res_s4 <= tcp_res__st3;
      out_tcp_ecn_s4 <= out_tcp_ecn__st3;
      tcp_ecn_s4 <= tcp_ecn__st3;
      out_tcp_ctrl_s4 <= out_tcp_ctrl__st3;
      tcp_ctrl_s4 <= tcp_ctrl__st3;
      out_tcp_window_s4 <= out_tcp_window__st3;
      tcp_window_s4 <= tcp_window__st3;
      out_tcp_checksum_s4 <= out_tcp_checksum__st3;
      tcp_checksum_s4 <= tcp_checksum__st3;
      out_tcp_urgentPtr_s4 <= out_tcp_urgentPtr__st3;
      tcp_urgentPtr_s4 <= tcp_urgentPtr__st3;
      out_std_meta_egress_spec_s4 <= out_std_meta_egress_spec__st3;
    end
  end

  // ---- Pipeline stage 4 (registered 4 cycle(s) after stage 0) ----
  always_comb begin
    drop = drop_s4;
    _padding_0__st4 = _padding_0_s4;
    tmp__st4 = tmp_s4;
    tmp_0__st4 = tmp_0_s4;
    tmp_1__st4 = tmp_1_s4;
    tmp_2__st4 = tmp_2_s4;
    tmp_3__st4 = tmp_3_s4;
    meta_ecmp_select_w__st4 = meta_ecmp_select_w_s4;
    out_ethernet_valid = out_ethernet_valid_s4;
    ethernet_valid__st4 = ethernet_valid_s4;
    out_ipv4_valid = out_ipv4_valid_s4;
    ipv4_valid__st4 = ipv4_valid_s4;
    out_tcp_valid = out_tcp_valid_s4;
    tcp_valid__st4 = tcp_valid_s4;
    out_ethernet_dstAddr = out_ethernet_dstAddr_s4;
    ethernet_dstAddr__st4 = ethernet_dstAddr_s4;
    out_ethernet_srcAddr = out_ethernet_srcAddr_s4;
    ethernet_srcAddr__st4 = ethernet_srcAddr_s4;
    out_ethernet_etherType = out_ethernet_etherType_s4;
    ethernet_etherType__st4 = ethernet_etherType_s4;
    out_ipv4_version = out_ipv4_version_s4;
    ipv4_version__st4 = ipv4_version_s4;
    out_ipv4_ihl = out_ipv4_ihl_s4;
    ipv4_ihl__st4 = ipv4_ihl_s4;
    out_ipv4_diffserv = out_ipv4_diffserv_s4;
    ipv4_diffserv__st4 = ipv4_diffserv_s4;
    out_ipv4_totalLen = out_ipv4_totalLen_s4;
    ipv4_totalLen__st4 = ipv4_totalLen_s4;
    out_ipv4_identification = out_ipv4_identification_s4;
    ipv4_identification__st4 = ipv4_identification_s4;
    out_ipv4_flags = out_ipv4_flags_s4;
    ipv4_flags__st4 = ipv4_flags_s4;
    out_ipv4_fragOffset = out_ipv4_fragOffset_s4;
    ipv4_fragOffset__st4 = ipv4_fragOffset_s4;
    out_ipv4_ttl = out_ipv4_ttl_s4;
    ipv4_ttl__st4 = ipv4_ttl_s4;
    out_ipv4_protocol = out_ipv4_protocol_s4;
    ipv4_protocol__st4 = ipv4_protocol_s4;
    out_ipv4_hdrChecksum = out_ipv4_hdrChecksum_s4;
    ipv4_hdrChecksum__st4 = ipv4_hdrChecksum_s4;
    out_ipv4_srcAddr = out_ipv4_srcAddr_s4;
    ipv4_srcAddr__st4 = ipv4_srcAddr_s4;
    out_ipv4_dstAddr = out_ipv4_dstAddr_s4;
    ipv4_dstAddr__st4 = ipv4_dstAddr_s4;
    out_tcp_srcPort = out_tcp_srcPort_s4;
    tcp_srcPort__st4 = tcp_srcPort_s4;
    out_tcp_dstPort = out_tcp_dstPort_s4;
    tcp_dstPort__st4 = tcp_dstPort_s4;
    out_tcp_seqNo = out_tcp_seqNo_s4;
    tcp_seqNo__st4 = tcp_seqNo_s4;
    out_tcp_ackNo = out_tcp_ackNo_s4;
    tcp_ackNo__st4 = tcp_ackNo_s4;
    out_tcp_dataOffset = out_tcp_dataOffset_s4;
    tcp_dataOffset__st4 = tcp_dataOffset_s4;
    out_tcp_res = out_tcp_res_s4;
    tcp_res__st4 = tcp_res_s4;
    out_tcp_ecn = out_tcp_ecn_s4;
    tcp_ecn__st4 = tcp_ecn_s4;
    out_tcp_ctrl = out_tcp_ctrl_s4;
    tcp_ctrl__st4 = tcp_ctrl_s4;
    out_tcp_window = out_tcp_window_s4;
    tcp_window__st4 = tcp_window_s4;
    out_tcp_checksum = out_tcp_checksum_s4;
    tcp_checksum__st4 = tcp_checksum_s4;
    out_tcp_urgentPtr = out_tcp_urgentPtr_s4;
    tcp_urgentPtr__st4 = tcp_urgentPtr_s4;
    out_std_meta_egress_spec = out_std_meta_egress_spec_s4;

    // apply block (stage 4 of 4)
    if (__stage_cond_1_r) begin
      // ecmp_nhop.apply()
      if (ecmp_nhop_hit) begin
        unique case (ecmp_nhop_act_id)
          2'd0: ; // NoAction
          2'd1: begin // drop
            drop = 1;
          end
          2'd2: begin // set_nhop
            out_ethernet_dstAddr = ecmp_nhop_p_nhop_dmac;
            out_ipv4_dstAddr = ecmp_nhop_p_nhop_ipv4;
            out_std_meta_egress_spec = ecmp_nhop_p_port;
            out_ipv4_ttl = ((ipv4_ttl__st4 + 'hFF) & 'hFF);
          end
          default: ; // default = NoAction
        endcase
      end
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) valid_out <= 0;
    else        valid_out <= valid_s4;
  end

endmodule
