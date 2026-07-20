module processing_generated (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        valid_in,

  // Header valid flags
  input  logic        ethernet_valid,
  input  logic        ipv4_valid,
  input  logic        probe_valid,
  input  logic        probe_data_0_valid,
  input  logic        probe_data_1_valid,
  input  logic        probe_data_2_valid,
  input  logic        probe_data_3_valid,
  input  logic        probe_data_4_valid,
  input  logic        probe_data_5_valid,
  input  logic        probe_data_6_valid,
  input  logic        probe_data_7_valid,
  input  logic        probe_data_8_valid,
  input  logic        probe_data_9_valid,
  input  logic        probe_fwd_0_valid,
  input  logic        probe_fwd_1_valid,
  input  logic        probe_fwd_2_valid,
  input  logic        probe_fwd_3_valid,
  input  logic        probe_fwd_4_valid,
  input  logic        probe_fwd_5_valid,
  input  logic        probe_fwd_6_valid,
  input  logic        probe_fwd_7_valid,
  input  logic        probe_fwd_8_valid,
  input  logic        probe_fwd_9_valid,

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
  input  logic [7:0] probe_hop_cnt,
  input  logic [0:0] probe_data_0_bos,
  input  logic [6:0] probe_data_0_swid,
  input  logic [7:0] probe_data_0_port,
  input  logic [31:0] probe_data_0_byte_cnt,
  input  logic [47:0] probe_data_0_last_time,
  input  logic [47:0] probe_data_0_cur_time,
  input  logic [0:0] probe_data_1_bos,
  input  logic [6:0] probe_data_1_swid,
  input  logic [7:0] probe_data_1_port,
  input  logic [31:0] probe_data_1_byte_cnt,
  input  logic [47:0] probe_data_1_last_time,
  input  logic [47:0] probe_data_1_cur_time,
  input  logic [0:0] probe_data_2_bos,
  input  logic [6:0] probe_data_2_swid,
  input  logic [7:0] probe_data_2_port,
  input  logic [31:0] probe_data_2_byte_cnt,
  input  logic [47:0] probe_data_2_last_time,
  input  logic [47:0] probe_data_2_cur_time,
  input  logic [0:0] probe_data_3_bos,
  input  logic [6:0] probe_data_3_swid,
  input  logic [7:0] probe_data_3_port,
  input  logic [31:0] probe_data_3_byte_cnt,
  input  logic [47:0] probe_data_3_last_time,
  input  logic [47:0] probe_data_3_cur_time,
  input  logic [0:0] probe_data_4_bos,
  input  logic [6:0] probe_data_4_swid,
  input  logic [7:0] probe_data_4_port,
  input  logic [31:0] probe_data_4_byte_cnt,
  input  logic [47:0] probe_data_4_last_time,
  input  logic [47:0] probe_data_4_cur_time,
  input  logic [0:0] probe_data_5_bos,
  input  logic [6:0] probe_data_5_swid,
  input  logic [7:0] probe_data_5_port,
  input  logic [31:0] probe_data_5_byte_cnt,
  input  logic [47:0] probe_data_5_last_time,
  input  logic [47:0] probe_data_5_cur_time,
  input  logic [0:0] probe_data_6_bos,
  input  logic [6:0] probe_data_6_swid,
  input  logic [7:0] probe_data_6_port,
  input  logic [31:0] probe_data_6_byte_cnt,
  input  logic [47:0] probe_data_6_last_time,
  input  logic [47:0] probe_data_6_cur_time,
  input  logic [0:0] probe_data_7_bos,
  input  logic [6:0] probe_data_7_swid,
  input  logic [7:0] probe_data_7_port,
  input  logic [31:0] probe_data_7_byte_cnt,
  input  logic [47:0] probe_data_7_last_time,
  input  logic [47:0] probe_data_7_cur_time,
  input  logic [0:0] probe_data_8_bos,
  input  logic [6:0] probe_data_8_swid,
  input  logic [7:0] probe_data_8_port,
  input  logic [31:0] probe_data_8_byte_cnt,
  input  logic [47:0] probe_data_8_last_time,
  input  logic [47:0] probe_data_8_cur_time,
  input  logic [0:0] probe_data_9_bos,
  input  logic [6:0] probe_data_9_swid,
  input  logic [7:0] probe_data_9_port,
  input  logic [31:0] probe_data_9_byte_cnt,
  input  logic [47:0] probe_data_9_last_time,
  input  logic [47:0] probe_data_9_cur_time,
  input  logic [7:0] probe_fwd_0_egress_spec,
  input  logic [7:0] probe_fwd_1_egress_spec,
  input  logic [7:0] probe_fwd_2_egress_spec,
  input  logic [7:0] probe_fwd_3_egress_spec,
  input  logic [7:0] probe_fwd_4_egress_spec,
  input  logic [7:0] probe_fwd_5_egress_spec,
  input  logic [7:0] probe_fwd_6_egress_spec,
  input  logic [7:0] probe_fwd_7_egress_spec,
  input  logic [7:0] probe_fwd_8_egress_spec,
  input  logic [7:0] probe_fwd_9_egress_spec,

  // Metadata inputs
  input  logic [7:0] meta__egress_spec0,
  input  logic [7:0] meta__parser_metadata_remaining1,

  // Header valid flag outputs (may be modified by setValid/setInvalid)
  output logic        out_ethernet_valid,
  output logic        out_ipv4_valid,
  output logic        out_probe_valid,
  output logic        out_probe_data_0_valid,
  output logic        out_probe_data_1_valid,
  output logic        out_probe_data_2_valid,
  output logic        out_probe_data_3_valid,
  output logic        out_probe_data_4_valid,
  output logic        out_probe_data_5_valid,
  output logic        out_probe_data_6_valid,
  output logic        out_probe_data_7_valid,
  output logic        out_probe_data_8_valid,
  output logic        out_probe_data_9_valid,
  output logic        out_probe_fwd_0_valid,
  output logic        out_probe_fwd_1_valid,
  output logic        out_probe_fwd_2_valid,
  output logic        out_probe_fwd_3_valid,
  output logic        out_probe_fwd_4_valid,
  output logic        out_probe_fwd_5_valid,
  output logic        out_probe_fwd_6_valid,
  output logic        out_probe_fwd_7_valid,
  output logic        out_probe_fwd_8_valid,
  output logic        out_probe_fwd_9_valid,

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
  output logic [7:0] out_probe_hop_cnt,
  output logic [0:0] out_probe_data_0_bos,
  output logic [6:0] out_probe_data_0_swid,
  output logic [7:0] out_probe_data_0_port,
  output logic [31:0] out_probe_data_0_byte_cnt,
  output logic [47:0] out_probe_data_0_last_time,
  output logic [47:0] out_probe_data_0_cur_time,
  output logic [0:0] out_probe_data_1_bos,
  output logic [6:0] out_probe_data_1_swid,
  output logic [7:0] out_probe_data_1_port,
  output logic [31:0] out_probe_data_1_byte_cnt,
  output logic [47:0] out_probe_data_1_last_time,
  output logic [47:0] out_probe_data_1_cur_time,
  output logic [0:0] out_probe_data_2_bos,
  output logic [6:0] out_probe_data_2_swid,
  output logic [7:0] out_probe_data_2_port,
  output logic [31:0] out_probe_data_2_byte_cnt,
  output logic [47:0] out_probe_data_2_last_time,
  output logic [47:0] out_probe_data_2_cur_time,
  output logic [0:0] out_probe_data_3_bos,
  output logic [6:0] out_probe_data_3_swid,
  output logic [7:0] out_probe_data_3_port,
  output logic [31:0] out_probe_data_3_byte_cnt,
  output logic [47:0] out_probe_data_3_last_time,
  output logic [47:0] out_probe_data_3_cur_time,
  output logic [0:0] out_probe_data_4_bos,
  output logic [6:0] out_probe_data_4_swid,
  output logic [7:0] out_probe_data_4_port,
  output logic [31:0] out_probe_data_4_byte_cnt,
  output logic [47:0] out_probe_data_4_last_time,
  output logic [47:0] out_probe_data_4_cur_time,
  output logic [0:0] out_probe_data_5_bos,
  output logic [6:0] out_probe_data_5_swid,
  output logic [7:0] out_probe_data_5_port,
  output logic [31:0] out_probe_data_5_byte_cnt,
  output logic [47:0] out_probe_data_5_last_time,
  output logic [47:0] out_probe_data_5_cur_time,
  output logic [0:0] out_probe_data_6_bos,
  output logic [6:0] out_probe_data_6_swid,
  output logic [7:0] out_probe_data_6_port,
  output logic [31:0] out_probe_data_6_byte_cnt,
  output logic [47:0] out_probe_data_6_last_time,
  output logic [47:0] out_probe_data_6_cur_time,
  output logic [0:0] out_probe_data_7_bos,
  output logic [6:0] out_probe_data_7_swid,
  output logic [7:0] out_probe_data_7_port,
  output logic [31:0] out_probe_data_7_byte_cnt,
  output logic [47:0] out_probe_data_7_last_time,
  output logic [47:0] out_probe_data_7_cur_time,
  output logic [0:0] out_probe_data_8_bos,
  output logic [6:0] out_probe_data_8_swid,
  output logic [7:0] out_probe_data_8_port,
  output logic [31:0] out_probe_data_8_byte_cnt,
  output logic [47:0] out_probe_data_8_last_time,
  output logic [47:0] out_probe_data_8_cur_time,
  output logic [0:0] out_probe_data_9_bos,
  output logic [6:0] out_probe_data_9_swid,
  output logic [7:0] out_probe_data_9_port,
  output logic [31:0] out_probe_data_9_byte_cnt,
  output logic [47:0] out_probe_data_9_last_time,
  output logic [47:0] out_probe_data_9_cur_time,
  output logic [7:0] out_probe_fwd_0_egress_spec,
  output logic [7:0] out_probe_fwd_1_egress_spec,
  output logic [7:0] out_probe_fwd_2_egress_spec,
  output logic [7:0] out_probe_fwd_3_egress_spec,
  output logic [7:0] out_probe_fwd_4_egress_spec,
  output logic [7:0] out_probe_fwd_5_egress_spec,
  output logic [7:0] out_probe_fwd_6_egress_spec,
  output logic [7:0] out_probe_fwd_7_egress_spec,
  output logic [7:0] out_probe_fwd_8_egress_spec,
  output logic [7:0] out_probe_fwd_9_egress_spec,

  // Standard metadata outputs
  output logic [8:0] out_std_meta_egress_spec,

  // Control-plane write ports for table instances
  input  logic        ipv4_lpm_cp_wr_en,
  input  logic [9:0] ipv4_lpm_cp_wr_idx,
  input  logic [31:0] ipv4_lpm_cp_wr_key_dstAddr,
  input  logic [5:0] ipv4_lpm_cp_wr_pfx_len,
  input  logic [1:0] ipv4_lpm_cp_wr_action,
  input  logic [47:0] ipv4_lpm_cp_wr_p_dstAddr,
  input  logic [8:0] ipv4_lpm_cp_wr_p_port,

  // Table hit outputs
  output logic        ipv4_lpm_hit_out,

  output logic        valid_out,
  output logic        drop
);

  logic [31:0] byte_cnt_0;
  logic [47:0] last_time_0;
  logic [31:0] tmp;
  logic [31:0] tmp_0;
  logic [31:0] tmp_1;
  logic [31:0] tmp_2;
  logic [31:0] tmp_3;

  // Metadata shadow locals (writable copies of metadata inputs)
  logic [7:0] meta__egress_spec0_w;
  logic [7:0] meta__parser_metadata_remaining1_w;

  // Pipeline-stage forwarding registers (one set per exact-match
  // table boundary in the chain)
  logic valid_s1;
  logic out_ethernet_valid_s1;
  logic ethernet_valid_s1;
  logic out_ipv4_valid_s1;
  logic ipv4_valid_s1;
  logic out_probe_valid_s1;
  logic probe_valid_s1;
  logic out_probe_data_0_valid_s1;
  logic probe_data_0_valid_s1;
  logic out_probe_data_1_valid_s1;
  logic probe_data_1_valid_s1;
  logic out_probe_data_2_valid_s1;
  logic probe_data_2_valid_s1;
  logic out_probe_data_3_valid_s1;
  logic probe_data_3_valid_s1;
  logic out_probe_data_4_valid_s1;
  logic probe_data_4_valid_s1;
  logic out_probe_data_5_valid_s1;
  logic probe_data_5_valid_s1;
  logic out_probe_data_6_valid_s1;
  logic probe_data_6_valid_s1;
  logic out_probe_data_7_valid_s1;
  logic probe_data_7_valid_s1;
  logic out_probe_data_8_valid_s1;
  logic probe_data_8_valid_s1;
  logic out_probe_data_9_valid_s1;
  logic probe_data_9_valid_s1;
  logic out_probe_fwd_0_valid_s1;
  logic probe_fwd_0_valid_s1;
  logic out_probe_fwd_1_valid_s1;
  logic probe_fwd_1_valid_s1;
  logic out_probe_fwd_2_valid_s1;
  logic probe_fwd_2_valid_s1;
  logic out_probe_fwd_3_valid_s1;
  logic probe_fwd_3_valid_s1;
  logic out_probe_fwd_4_valid_s1;
  logic probe_fwd_4_valid_s1;
  logic out_probe_fwd_5_valid_s1;
  logic probe_fwd_5_valid_s1;
  logic out_probe_fwd_6_valid_s1;
  logic probe_fwd_6_valid_s1;
  logic out_probe_fwd_7_valid_s1;
  logic probe_fwd_7_valid_s1;
  logic out_probe_fwd_8_valid_s1;
  logic probe_fwd_8_valid_s1;
  logic out_probe_fwd_9_valid_s1;
  logic probe_fwd_9_valid_s1;
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
  logic [7:0] out_probe_hop_cnt_s1;
  logic [7:0] probe_hop_cnt_s1;
  logic [0:0] out_probe_data_0_bos_s1;
  logic [0:0] probe_data_0_bos_s1;
  logic [6:0] out_probe_data_0_swid_s1;
  logic [6:0] probe_data_0_swid_s1;
  logic [7:0] out_probe_data_0_port_s1;
  logic [7:0] probe_data_0_port_s1;
  logic [31:0] out_probe_data_0_byte_cnt_s1;
  logic [31:0] probe_data_0_byte_cnt_s1;
  logic [47:0] out_probe_data_0_last_time_s1;
  logic [47:0] probe_data_0_last_time_s1;
  logic [47:0] out_probe_data_0_cur_time_s1;
  logic [47:0] probe_data_0_cur_time_s1;
  logic [0:0] out_probe_data_1_bos_s1;
  logic [0:0] probe_data_1_bos_s1;
  logic [6:0] out_probe_data_1_swid_s1;
  logic [6:0] probe_data_1_swid_s1;
  logic [7:0] out_probe_data_1_port_s1;
  logic [7:0] probe_data_1_port_s1;
  logic [31:0] out_probe_data_1_byte_cnt_s1;
  logic [31:0] probe_data_1_byte_cnt_s1;
  logic [47:0] out_probe_data_1_last_time_s1;
  logic [47:0] probe_data_1_last_time_s1;
  logic [47:0] out_probe_data_1_cur_time_s1;
  logic [47:0] probe_data_1_cur_time_s1;
  logic [0:0] out_probe_data_2_bos_s1;
  logic [0:0] probe_data_2_bos_s1;
  logic [6:0] out_probe_data_2_swid_s1;
  logic [6:0] probe_data_2_swid_s1;
  logic [7:0] out_probe_data_2_port_s1;
  logic [7:0] probe_data_2_port_s1;
  logic [31:0] out_probe_data_2_byte_cnt_s1;
  logic [31:0] probe_data_2_byte_cnt_s1;
  logic [47:0] out_probe_data_2_last_time_s1;
  logic [47:0] probe_data_2_last_time_s1;
  logic [47:0] out_probe_data_2_cur_time_s1;
  logic [47:0] probe_data_2_cur_time_s1;
  logic [0:0] out_probe_data_3_bos_s1;
  logic [0:0] probe_data_3_bos_s1;
  logic [6:0] out_probe_data_3_swid_s1;
  logic [6:0] probe_data_3_swid_s1;
  logic [7:0] out_probe_data_3_port_s1;
  logic [7:0] probe_data_3_port_s1;
  logic [31:0] out_probe_data_3_byte_cnt_s1;
  logic [31:0] probe_data_3_byte_cnt_s1;
  logic [47:0] out_probe_data_3_last_time_s1;
  logic [47:0] probe_data_3_last_time_s1;
  logic [47:0] out_probe_data_3_cur_time_s1;
  logic [47:0] probe_data_3_cur_time_s1;
  logic [0:0] out_probe_data_4_bos_s1;
  logic [0:0] probe_data_4_bos_s1;
  logic [6:0] out_probe_data_4_swid_s1;
  logic [6:0] probe_data_4_swid_s1;
  logic [7:0] out_probe_data_4_port_s1;
  logic [7:0] probe_data_4_port_s1;
  logic [31:0] out_probe_data_4_byte_cnt_s1;
  logic [31:0] probe_data_4_byte_cnt_s1;
  logic [47:0] out_probe_data_4_last_time_s1;
  logic [47:0] probe_data_4_last_time_s1;
  logic [47:0] out_probe_data_4_cur_time_s1;
  logic [47:0] probe_data_4_cur_time_s1;
  logic [0:0] out_probe_data_5_bos_s1;
  logic [0:0] probe_data_5_bos_s1;
  logic [6:0] out_probe_data_5_swid_s1;
  logic [6:0] probe_data_5_swid_s1;
  logic [7:0] out_probe_data_5_port_s1;
  logic [7:0] probe_data_5_port_s1;
  logic [31:0] out_probe_data_5_byte_cnt_s1;
  logic [31:0] probe_data_5_byte_cnt_s1;
  logic [47:0] out_probe_data_5_last_time_s1;
  logic [47:0] probe_data_5_last_time_s1;
  logic [47:0] out_probe_data_5_cur_time_s1;
  logic [47:0] probe_data_5_cur_time_s1;
  logic [0:0] out_probe_data_6_bos_s1;
  logic [0:0] probe_data_6_bos_s1;
  logic [6:0] out_probe_data_6_swid_s1;
  logic [6:0] probe_data_6_swid_s1;
  logic [7:0] out_probe_data_6_port_s1;
  logic [7:0] probe_data_6_port_s1;
  logic [31:0] out_probe_data_6_byte_cnt_s1;
  logic [31:0] probe_data_6_byte_cnt_s1;
  logic [47:0] out_probe_data_6_last_time_s1;
  logic [47:0] probe_data_6_last_time_s1;
  logic [47:0] out_probe_data_6_cur_time_s1;
  logic [47:0] probe_data_6_cur_time_s1;
  logic [0:0] out_probe_data_7_bos_s1;
  logic [0:0] probe_data_7_bos_s1;
  logic [6:0] out_probe_data_7_swid_s1;
  logic [6:0] probe_data_7_swid_s1;
  logic [7:0] out_probe_data_7_port_s1;
  logic [7:0] probe_data_7_port_s1;
  logic [31:0] out_probe_data_7_byte_cnt_s1;
  logic [31:0] probe_data_7_byte_cnt_s1;
  logic [47:0] out_probe_data_7_last_time_s1;
  logic [47:0] probe_data_7_last_time_s1;
  logic [47:0] out_probe_data_7_cur_time_s1;
  logic [47:0] probe_data_7_cur_time_s1;
  logic [0:0] out_probe_data_8_bos_s1;
  logic [0:0] probe_data_8_bos_s1;
  logic [6:0] out_probe_data_8_swid_s1;
  logic [6:0] probe_data_8_swid_s1;
  logic [7:0] out_probe_data_8_port_s1;
  logic [7:0] probe_data_8_port_s1;
  logic [31:0] out_probe_data_8_byte_cnt_s1;
  logic [31:0] probe_data_8_byte_cnt_s1;
  logic [47:0] out_probe_data_8_last_time_s1;
  logic [47:0] probe_data_8_last_time_s1;
  logic [47:0] out_probe_data_8_cur_time_s1;
  logic [47:0] probe_data_8_cur_time_s1;
  logic [0:0] out_probe_data_9_bos_s1;
  logic [0:0] probe_data_9_bos_s1;
  logic [6:0] out_probe_data_9_swid_s1;
  logic [6:0] probe_data_9_swid_s1;
  logic [7:0] out_probe_data_9_port_s1;
  logic [7:0] probe_data_9_port_s1;
  logic [31:0] out_probe_data_9_byte_cnt_s1;
  logic [31:0] probe_data_9_byte_cnt_s1;
  logic [47:0] out_probe_data_9_last_time_s1;
  logic [47:0] probe_data_9_last_time_s1;
  logic [47:0] out_probe_data_9_cur_time_s1;
  logic [47:0] probe_data_9_cur_time_s1;
  logic [7:0] out_probe_fwd_0_egress_spec_s1;
  logic [7:0] probe_fwd_0_egress_spec_s1;
  logic [7:0] out_probe_fwd_1_egress_spec_s1;
  logic [7:0] probe_fwd_1_egress_spec_s1;
  logic [7:0] out_probe_fwd_2_egress_spec_s1;
  logic [7:0] probe_fwd_2_egress_spec_s1;
  logic [7:0] out_probe_fwd_3_egress_spec_s1;
  logic [7:0] probe_fwd_3_egress_spec_s1;
  logic [7:0] out_probe_fwd_4_egress_spec_s1;
  logic [7:0] probe_fwd_4_egress_spec_s1;
  logic [7:0] out_probe_fwd_5_egress_spec_s1;
  logic [7:0] probe_fwd_5_egress_spec_s1;
  logic [7:0] out_probe_fwd_6_egress_spec_s1;
  logic [7:0] probe_fwd_6_egress_spec_s1;
  logic [7:0] out_probe_fwd_7_egress_spec_s1;
  logic [7:0] probe_fwd_7_egress_spec_s1;
  logic [7:0] out_probe_fwd_8_egress_spec_s1;
  logic [7:0] probe_fwd_8_egress_spec_s1;
  logic [7:0] out_probe_fwd_9_egress_spec_s1;
  logic [7:0] probe_fwd_9_egress_spec_s1;
  logic [7:0] meta__egress_spec0_w_s1;
  logic [7:0] meta__parser_metadata_remaining1_w_s1;
  logic [31:0] byte_cnt_0_s1;
  logic [47:0] last_time_0_s1;
  logic [31:0] tmp_s1;
  logic [31:0] tmp_0_s1;
  logic [31:0] tmp_1_s1;
  logic [31:0] tmp_2_s1;
  logic [31:0] tmp_3_s1;
  logic [8:0] out_std_meta_egress_spec_s1;
  logic drop_s1;
  logic __stage_cond_0_r;

  // Pool-A (out_*/drop) working copies -- every stage except the
  // last, which drives the real output ports directly
  logic out_ethernet_valid__st0;
  logic out_ipv4_valid__st0;
  logic out_probe_valid__st0;
  logic out_probe_data_0_valid__st0;
  logic out_probe_data_1_valid__st0;
  logic out_probe_data_2_valid__st0;
  logic out_probe_data_3_valid__st0;
  logic out_probe_data_4_valid__st0;
  logic out_probe_data_5_valid__st0;
  logic out_probe_data_6_valid__st0;
  logic out_probe_data_7_valid__st0;
  logic out_probe_data_8_valid__st0;
  logic out_probe_data_9_valid__st0;
  logic out_probe_fwd_0_valid__st0;
  logic out_probe_fwd_1_valid__st0;
  logic out_probe_fwd_2_valid__st0;
  logic out_probe_fwd_3_valid__st0;
  logic out_probe_fwd_4_valid__st0;
  logic out_probe_fwd_5_valid__st0;
  logic out_probe_fwd_6_valid__st0;
  logic out_probe_fwd_7_valid__st0;
  logic out_probe_fwd_8_valid__st0;
  logic out_probe_fwd_9_valid__st0;
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
  logic [7:0] out_probe_hop_cnt__st0;
  logic [0:0] out_probe_data_0_bos__st0;
  logic [6:0] out_probe_data_0_swid__st0;
  logic [7:0] out_probe_data_0_port__st0;
  logic [31:0] out_probe_data_0_byte_cnt__st0;
  logic [47:0] out_probe_data_0_last_time__st0;
  logic [47:0] out_probe_data_0_cur_time__st0;
  logic [0:0] out_probe_data_1_bos__st0;
  logic [6:0] out_probe_data_1_swid__st0;
  logic [7:0] out_probe_data_1_port__st0;
  logic [31:0] out_probe_data_1_byte_cnt__st0;
  logic [47:0] out_probe_data_1_last_time__st0;
  logic [47:0] out_probe_data_1_cur_time__st0;
  logic [0:0] out_probe_data_2_bos__st0;
  logic [6:0] out_probe_data_2_swid__st0;
  logic [7:0] out_probe_data_2_port__st0;
  logic [31:0] out_probe_data_2_byte_cnt__st0;
  logic [47:0] out_probe_data_2_last_time__st0;
  logic [47:0] out_probe_data_2_cur_time__st0;
  logic [0:0] out_probe_data_3_bos__st0;
  logic [6:0] out_probe_data_3_swid__st0;
  logic [7:0] out_probe_data_3_port__st0;
  logic [31:0] out_probe_data_3_byte_cnt__st0;
  logic [47:0] out_probe_data_3_last_time__st0;
  logic [47:0] out_probe_data_3_cur_time__st0;
  logic [0:0] out_probe_data_4_bos__st0;
  logic [6:0] out_probe_data_4_swid__st0;
  logic [7:0] out_probe_data_4_port__st0;
  logic [31:0] out_probe_data_4_byte_cnt__st0;
  logic [47:0] out_probe_data_4_last_time__st0;
  logic [47:0] out_probe_data_4_cur_time__st0;
  logic [0:0] out_probe_data_5_bos__st0;
  logic [6:0] out_probe_data_5_swid__st0;
  logic [7:0] out_probe_data_5_port__st0;
  logic [31:0] out_probe_data_5_byte_cnt__st0;
  logic [47:0] out_probe_data_5_last_time__st0;
  logic [47:0] out_probe_data_5_cur_time__st0;
  logic [0:0] out_probe_data_6_bos__st0;
  logic [6:0] out_probe_data_6_swid__st0;
  logic [7:0] out_probe_data_6_port__st0;
  logic [31:0] out_probe_data_6_byte_cnt__st0;
  logic [47:0] out_probe_data_6_last_time__st0;
  logic [47:0] out_probe_data_6_cur_time__st0;
  logic [0:0] out_probe_data_7_bos__st0;
  logic [6:0] out_probe_data_7_swid__st0;
  logic [7:0] out_probe_data_7_port__st0;
  logic [31:0] out_probe_data_7_byte_cnt__st0;
  logic [47:0] out_probe_data_7_last_time__st0;
  logic [47:0] out_probe_data_7_cur_time__st0;
  logic [0:0] out_probe_data_8_bos__st0;
  logic [6:0] out_probe_data_8_swid__st0;
  logic [7:0] out_probe_data_8_port__st0;
  logic [31:0] out_probe_data_8_byte_cnt__st0;
  logic [47:0] out_probe_data_8_last_time__st0;
  logic [47:0] out_probe_data_8_cur_time__st0;
  logic [0:0] out_probe_data_9_bos__st0;
  logic [6:0] out_probe_data_9_swid__st0;
  logic [7:0] out_probe_data_9_port__st0;
  logic [31:0] out_probe_data_9_byte_cnt__st0;
  logic [47:0] out_probe_data_9_last_time__st0;
  logic [47:0] out_probe_data_9_cur_time__st0;
  logic [7:0] out_probe_fwd_0_egress_spec__st0;
  logic [7:0] out_probe_fwd_1_egress_spec__st0;
  logic [7:0] out_probe_fwd_2_egress_spec__st0;
  logic [7:0] out_probe_fwd_3_egress_spec__st0;
  logic [7:0] out_probe_fwd_4_egress_spec__st0;
  logic [7:0] out_probe_fwd_5_egress_spec__st0;
  logic [7:0] out_probe_fwd_6_egress_spec__st0;
  logic [7:0] out_probe_fwd_7_egress_spec__st0;
  logic [7:0] out_probe_fwd_8_egress_spec__st0;
  logic [7:0] out_probe_fwd_9_egress_spec__st0;
  logic [8:0] out_std_meta_egress_spec__st0;
  logic drop__st0;

  // Pool-B (locals/meta shadow/raw hdr+std_meta reads) working
  // copies -- every stage except the first, which reads live inputs
  logic [31:0] byte_cnt_0__st1;
  logic [47:0] last_time_0__st1;
  logic [31:0] tmp__st1;
  logic [31:0] tmp_0__st1;
  logic [31:0] tmp_1__st1;
  logic [31:0] tmp_2__st1;
  logic [31:0] tmp_3__st1;
  logic [7:0] meta__egress_spec0_w__st1;
  logic [7:0] meta__parser_metadata_remaining1_w__st1;
  logic ethernet_valid__st1;
  logic ipv4_valid__st1;
  logic probe_valid__st1;
  logic probe_data_0_valid__st1;
  logic probe_data_1_valid__st1;
  logic probe_data_2_valid__st1;
  logic probe_data_3_valid__st1;
  logic probe_data_4_valid__st1;
  logic probe_data_5_valid__st1;
  logic probe_data_6_valid__st1;
  logic probe_data_7_valid__st1;
  logic probe_data_8_valid__st1;
  logic probe_data_9_valid__st1;
  logic probe_fwd_0_valid__st1;
  logic probe_fwd_1_valid__st1;
  logic probe_fwd_2_valid__st1;
  logic probe_fwd_3_valid__st1;
  logic probe_fwd_4_valid__st1;
  logic probe_fwd_5_valid__st1;
  logic probe_fwd_6_valid__st1;
  logic probe_fwd_7_valid__st1;
  logic probe_fwd_8_valid__st1;
  logic probe_fwd_9_valid__st1;
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
  logic [7:0] probe_hop_cnt__st1;
  logic [0:0] probe_data_0_bos__st1;
  logic [6:0] probe_data_0_swid__st1;
  logic [7:0] probe_data_0_port__st1;
  logic [31:0] probe_data_0_byte_cnt__st1;
  logic [47:0] probe_data_0_last_time__st1;
  logic [47:0] probe_data_0_cur_time__st1;
  logic [0:0] probe_data_1_bos__st1;
  logic [6:0] probe_data_1_swid__st1;
  logic [7:0] probe_data_1_port__st1;
  logic [31:0] probe_data_1_byte_cnt__st1;
  logic [47:0] probe_data_1_last_time__st1;
  logic [47:0] probe_data_1_cur_time__st1;
  logic [0:0] probe_data_2_bos__st1;
  logic [6:0] probe_data_2_swid__st1;
  logic [7:0] probe_data_2_port__st1;
  logic [31:0] probe_data_2_byte_cnt__st1;
  logic [47:0] probe_data_2_last_time__st1;
  logic [47:0] probe_data_2_cur_time__st1;
  logic [0:0] probe_data_3_bos__st1;
  logic [6:0] probe_data_3_swid__st1;
  logic [7:0] probe_data_3_port__st1;
  logic [31:0] probe_data_3_byte_cnt__st1;
  logic [47:0] probe_data_3_last_time__st1;
  logic [47:0] probe_data_3_cur_time__st1;
  logic [0:0] probe_data_4_bos__st1;
  logic [6:0] probe_data_4_swid__st1;
  logic [7:0] probe_data_4_port__st1;
  logic [31:0] probe_data_4_byte_cnt__st1;
  logic [47:0] probe_data_4_last_time__st1;
  logic [47:0] probe_data_4_cur_time__st1;
  logic [0:0] probe_data_5_bos__st1;
  logic [6:0] probe_data_5_swid__st1;
  logic [7:0] probe_data_5_port__st1;
  logic [31:0] probe_data_5_byte_cnt__st1;
  logic [47:0] probe_data_5_last_time__st1;
  logic [47:0] probe_data_5_cur_time__st1;
  logic [0:0] probe_data_6_bos__st1;
  logic [6:0] probe_data_6_swid__st1;
  logic [7:0] probe_data_6_port__st1;
  logic [31:0] probe_data_6_byte_cnt__st1;
  logic [47:0] probe_data_6_last_time__st1;
  logic [47:0] probe_data_6_cur_time__st1;
  logic [0:0] probe_data_7_bos__st1;
  logic [6:0] probe_data_7_swid__st1;
  logic [7:0] probe_data_7_port__st1;
  logic [31:0] probe_data_7_byte_cnt__st1;
  logic [47:0] probe_data_7_last_time__st1;
  logic [47:0] probe_data_7_cur_time__st1;
  logic [0:0] probe_data_8_bos__st1;
  logic [6:0] probe_data_8_swid__st1;
  logic [7:0] probe_data_8_port__st1;
  logic [31:0] probe_data_8_byte_cnt__st1;
  logic [47:0] probe_data_8_last_time__st1;
  logic [47:0] probe_data_8_cur_time__st1;
  logic [0:0] probe_data_9_bos__st1;
  logic [6:0] probe_data_9_swid__st1;
  logic [7:0] probe_data_9_port__st1;
  logic [31:0] probe_data_9_byte_cnt__st1;
  logic [47:0] probe_data_9_last_time__st1;
  logic [47:0] probe_data_9_cur_time__st1;
  logic [7:0] probe_fwd_0_egress_spec__st1;
  logic [7:0] probe_fwd_1_egress_spec__st1;
  logic [7:0] probe_fwd_2_egress_spec__st1;
  logic [7:0] probe_fwd_3_egress_spec__st1;
  logic [7:0] probe_fwd_4_egress_spec__st1;
  logic [7:0] probe_fwd_5_egress_spec__st1;
  logic [7:0] probe_fwd_6_egress_spec__st1;
  logic [7:0] probe_fwd_7_egress_spec__st1;
  logic [7:0] probe_fwd_8_egress_spec__st1;
  logic [7:0] probe_fwd_9_egress_spec__st1;

  // byte_cnt_reg: register<bit<32>>(8)
  logic [31:0] byte_cnt_reg_mem [0:7];
  logic        byte_cnt_reg_wr_en;
  logic [2:0] byte_cnt_reg_wr_addr;
  logic [31:0] byte_cnt_reg_wr_data;
  // last_time_reg: register<bit<48>>(8)
  logic [47:0] last_time_reg_mem [0:7];
  logic        last_time_reg_wr_en;
  logic [2:0] last_time_reg_wr_addr;
  logic [47:0] last_time_reg_wr_data;

  // Zero all register memories at simulation start
  initial begin
    for (int _si = 0; _si < 8; _si++)
      byte_cnt_reg_mem[_si] = 32'b0;
    for (int _si = 0; _si < 8; _si++)
      last_time_reg_mem[_si] = 48'b0;
  end

  // Table lookup result wires
  logic        ipv4_lpm_hit;
  logic [1:0] ipv4_lpm_act_id;
  logic [47:0] ipv4_lpm_p_dstAddr;
  logic [8:0] ipv4_lpm_p_port;

  // Table module instantiations
  ipv4_lpm_table #(.DEPTH(1024)) u_ipv4_lpm (
    .clk    (clk),
    .rst_n  (rst_n),
    .lkp_dstAddr    (ipv4_dstAddr),
    .hit       (ipv4_lpm_hit),
    .action_id (ipv4_lpm_act_id),
    .p_dstAddr  (ipv4_lpm_p_dstAddr),
    .p_port  (ipv4_lpm_p_port),
    .cp_wr_en  (ipv4_lpm_cp_wr_en),
    .cp_wr_idx (ipv4_lpm_cp_wr_idx),
    .cp_wr_key_dstAddr (ipv4_lpm_cp_wr_key_dstAddr),
    .cp_wr_pfx_len (ipv4_lpm_cp_wr_pfx_len),
    .cp_wr_action (ipv4_lpm_cp_wr_action),
    .cp_wr_p_dstAddr (ipv4_lpm_cp_wr_p_dstAddr),
    .cp_wr_p_port (ipv4_lpm_cp_wr_p_port)
  );

  // Table hit outputs
  assign ipv4_lpm_hit_out = ipv4_lpm_hit;

  // ---- Pipeline stage 0 (combinational, feeds the first exact-match table boundary) ----
  always_comb begin
    drop__st0 = 0;
    byte_cnt_0 = 32'b0;
    last_time_0 = 48'b0;
    tmp = 32'b0;
    tmp_0 = 32'b0;
    tmp_1 = 32'b0;
    tmp_2 = 32'b0;
    tmp_3 = 32'b0;

    // Metadata shadow defaults (init from inputs)
    meta__egress_spec0_w = meta__egress_spec0;
    meta__parser_metadata_remaining1_w = meta__parser_metadata_remaining1;
    byte_cnt_reg_wr_en   = 1'b0;
    byte_cnt_reg_wr_addr = '0;
    byte_cnt_reg_wr_data = '0;
    last_time_reg_wr_en   = 1'b0;
    last_time_reg_wr_addr = '0;
    last_time_reg_wr_data = '0;

    // Standard metadata defaults
    out_std_meta_egress_spec__st0 = 9'b0;

    // Header valid flag pass-through defaults
    out_ethernet_valid__st0 = ethernet_valid;
    out_ipv4_valid__st0 = ipv4_valid;
    out_probe_valid__st0 = probe_valid;
    out_probe_data_0_valid__st0 = probe_data_0_valid;
    out_probe_data_1_valid__st0 = probe_data_1_valid;
    out_probe_data_2_valid__st0 = probe_data_2_valid;
    out_probe_data_3_valid__st0 = probe_data_3_valid;
    out_probe_data_4_valid__st0 = probe_data_4_valid;
    out_probe_data_5_valid__st0 = probe_data_5_valid;
    out_probe_data_6_valid__st0 = probe_data_6_valid;
    out_probe_data_7_valid__st0 = probe_data_7_valid;
    out_probe_data_8_valid__st0 = probe_data_8_valid;
    out_probe_data_9_valid__st0 = probe_data_9_valid;
    out_probe_fwd_0_valid__st0 = probe_fwd_0_valid;
    out_probe_fwd_1_valid__st0 = probe_fwd_1_valid;
    out_probe_fwd_2_valid__st0 = probe_fwd_2_valid;
    out_probe_fwd_3_valid__st0 = probe_fwd_3_valid;
    out_probe_fwd_4_valid__st0 = probe_fwd_4_valid;
    out_probe_fwd_5_valid__st0 = probe_fwd_5_valid;
    out_probe_fwd_6_valid__st0 = probe_fwd_6_valid;
    out_probe_fwd_7_valid__st0 = probe_fwd_7_valid;
    out_probe_fwd_8_valid__st0 = probe_fwd_8_valid;
    out_probe_fwd_9_valid__st0 = probe_fwd_9_valid;

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
    out_probe_hop_cnt__st0 = probe_hop_cnt;
    out_probe_data_0_bos__st0 = probe_data_0_bos;
    out_probe_data_0_swid__st0 = probe_data_0_swid;
    out_probe_data_0_port__st0 = probe_data_0_port;
    out_probe_data_0_byte_cnt__st0 = probe_data_0_byte_cnt;
    out_probe_data_0_last_time__st0 = probe_data_0_last_time;
    out_probe_data_0_cur_time__st0 = probe_data_0_cur_time;
    out_probe_data_1_bos__st0 = probe_data_1_bos;
    out_probe_data_1_swid__st0 = probe_data_1_swid;
    out_probe_data_1_port__st0 = probe_data_1_port;
    out_probe_data_1_byte_cnt__st0 = probe_data_1_byte_cnt;
    out_probe_data_1_last_time__st0 = probe_data_1_last_time;
    out_probe_data_1_cur_time__st0 = probe_data_1_cur_time;
    out_probe_data_2_bos__st0 = probe_data_2_bos;
    out_probe_data_2_swid__st0 = probe_data_2_swid;
    out_probe_data_2_port__st0 = probe_data_2_port;
    out_probe_data_2_byte_cnt__st0 = probe_data_2_byte_cnt;
    out_probe_data_2_last_time__st0 = probe_data_2_last_time;
    out_probe_data_2_cur_time__st0 = probe_data_2_cur_time;
    out_probe_data_3_bos__st0 = probe_data_3_bos;
    out_probe_data_3_swid__st0 = probe_data_3_swid;
    out_probe_data_3_port__st0 = probe_data_3_port;
    out_probe_data_3_byte_cnt__st0 = probe_data_3_byte_cnt;
    out_probe_data_3_last_time__st0 = probe_data_3_last_time;
    out_probe_data_3_cur_time__st0 = probe_data_3_cur_time;
    out_probe_data_4_bos__st0 = probe_data_4_bos;
    out_probe_data_4_swid__st0 = probe_data_4_swid;
    out_probe_data_4_port__st0 = probe_data_4_port;
    out_probe_data_4_byte_cnt__st0 = probe_data_4_byte_cnt;
    out_probe_data_4_last_time__st0 = probe_data_4_last_time;
    out_probe_data_4_cur_time__st0 = probe_data_4_cur_time;
    out_probe_data_5_bos__st0 = probe_data_5_bos;
    out_probe_data_5_swid__st0 = probe_data_5_swid;
    out_probe_data_5_port__st0 = probe_data_5_port;
    out_probe_data_5_byte_cnt__st0 = probe_data_5_byte_cnt;
    out_probe_data_5_last_time__st0 = probe_data_5_last_time;
    out_probe_data_5_cur_time__st0 = probe_data_5_cur_time;
    out_probe_data_6_bos__st0 = probe_data_6_bos;
    out_probe_data_6_swid__st0 = probe_data_6_swid;
    out_probe_data_6_port__st0 = probe_data_6_port;
    out_probe_data_6_byte_cnt__st0 = probe_data_6_byte_cnt;
    out_probe_data_6_last_time__st0 = probe_data_6_last_time;
    out_probe_data_6_cur_time__st0 = probe_data_6_cur_time;
    out_probe_data_7_bos__st0 = probe_data_7_bos;
    out_probe_data_7_swid__st0 = probe_data_7_swid;
    out_probe_data_7_port__st0 = probe_data_7_port;
    out_probe_data_7_byte_cnt__st0 = probe_data_7_byte_cnt;
    out_probe_data_7_last_time__st0 = probe_data_7_last_time;
    out_probe_data_7_cur_time__st0 = probe_data_7_cur_time;
    out_probe_data_8_bos__st0 = probe_data_8_bos;
    out_probe_data_8_swid__st0 = probe_data_8_swid;
    out_probe_data_8_port__st0 = probe_data_8_port;
    out_probe_data_8_byte_cnt__st0 = probe_data_8_byte_cnt;
    out_probe_data_8_last_time__st0 = probe_data_8_last_time;
    out_probe_data_8_cur_time__st0 = probe_data_8_cur_time;
    out_probe_data_9_bos__st0 = probe_data_9_bos;
    out_probe_data_9_swid__st0 = probe_data_9_swid;
    out_probe_data_9_port__st0 = probe_data_9_port;
    out_probe_data_9_byte_cnt__st0 = probe_data_9_byte_cnt;
    out_probe_data_9_last_time__st0 = probe_data_9_last_time;
    out_probe_data_9_cur_time__st0 = probe_data_9_cur_time;
    out_probe_fwd_0_egress_spec__st0 = probe_fwd_0_egress_spec;
    out_probe_fwd_1_egress_spec__st0 = probe_fwd_1_egress_spec;
    out_probe_fwd_2_egress_spec__st0 = probe_fwd_2_egress_spec;
    out_probe_fwd_3_egress_spec__st0 = probe_fwd_3_egress_spec;
    out_probe_fwd_4_egress_spec__st0 = probe_fwd_4_egress_spec;
    out_probe_fwd_5_egress_spec__st0 = probe_fwd_5_egress_spec;
    out_probe_fwd_6_egress_spec__st0 = probe_fwd_6_egress_spec;
    out_probe_fwd_7_egress_spec__st0 = probe_fwd_7_egress_spec;
    out_probe_fwd_8_egress_spec__st0 = probe_fwd_8_egress_spec;
    out_probe_fwd_9_egress_spec__st0 = probe_fwd_9_egress_spec;

    // apply block (stage 0 of 1)
    if (ipv4_valid) begin
    end
    else begin
      if (probe_valid) begin
        out_std_meta_egress_spec__st0 = (meta__egress_spec0_w & 'h01FF);
        out_probe_hop_cnt__st0 = ((probe_hop_cnt + 'h01) & 'hFF);
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
      byte_cnt_0_s1 <= byte_cnt_0;
      last_time_0_s1 <= last_time_0;
      tmp_s1 <= tmp;
      tmp_0_s1 <= tmp_0;
      tmp_1_s1 <= tmp_1;
      tmp_2_s1 <= tmp_2;
      tmp_3_s1 <= tmp_3;
      meta__egress_spec0_w_s1 <= meta__egress_spec0_w;
      meta__parser_metadata_remaining1_w_s1 <= meta__parser_metadata_remaining1_w;
      out_ethernet_valid_s1 <= out_ethernet_valid__st0;
      ethernet_valid_s1 <= ethernet_valid;
      out_ipv4_valid_s1 <= out_ipv4_valid__st0;
      ipv4_valid_s1 <= ipv4_valid;
      out_probe_valid_s1 <= out_probe_valid__st0;
      probe_valid_s1 <= probe_valid;
      out_probe_data_0_valid_s1 <= out_probe_data_0_valid__st0;
      probe_data_0_valid_s1 <= probe_data_0_valid;
      out_probe_data_1_valid_s1 <= out_probe_data_1_valid__st0;
      probe_data_1_valid_s1 <= probe_data_1_valid;
      out_probe_data_2_valid_s1 <= out_probe_data_2_valid__st0;
      probe_data_2_valid_s1 <= probe_data_2_valid;
      out_probe_data_3_valid_s1 <= out_probe_data_3_valid__st0;
      probe_data_3_valid_s1 <= probe_data_3_valid;
      out_probe_data_4_valid_s1 <= out_probe_data_4_valid__st0;
      probe_data_4_valid_s1 <= probe_data_4_valid;
      out_probe_data_5_valid_s1 <= out_probe_data_5_valid__st0;
      probe_data_5_valid_s1 <= probe_data_5_valid;
      out_probe_data_6_valid_s1 <= out_probe_data_6_valid__st0;
      probe_data_6_valid_s1 <= probe_data_6_valid;
      out_probe_data_7_valid_s1 <= out_probe_data_7_valid__st0;
      probe_data_7_valid_s1 <= probe_data_7_valid;
      out_probe_data_8_valid_s1 <= out_probe_data_8_valid__st0;
      probe_data_8_valid_s1 <= probe_data_8_valid;
      out_probe_data_9_valid_s1 <= out_probe_data_9_valid__st0;
      probe_data_9_valid_s1 <= probe_data_9_valid;
      out_probe_fwd_0_valid_s1 <= out_probe_fwd_0_valid__st0;
      probe_fwd_0_valid_s1 <= probe_fwd_0_valid;
      out_probe_fwd_1_valid_s1 <= out_probe_fwd_1_valid__st0;
      probe_fwd_1_valid_s1 <= probe_fwd_1_valid;
      out_probe_fwd_2_valid_s1 <= out_probe_fwd_2_valid__st0;
      probe_fwd_2_valid_s1 <= probe_fwd_2_valid;
      out_probe_fwd_3_valid_s1 <= out_probe_fwd_3_valid__st0;
      probe_fwd_3_valid_s1 <= probe_fwd_3_valid;
      out_probe_fwd_4_valid_s1 <= out_probe_fwd_4_valid__st0;
      probe_fwd_4_valid_s1 <= probe_fwd_4_valid;
      out_probe_fwd_5_valid_s1 <= out_probe_fwd_5_valid__st0;
      probe_fwd_5_valid_s1 <= probe_fwd_5_valid;
      out_probe_fwd_6_valid_s1 <= out_probe_fwd_6_valid__st0;
      probe_fwd_6_valid_s1 <= probe_fwd_6_valid;
      out_probe_fwd_7_valid_s1 <= out_probe_fwd_7_valid__st0;
      probe_fwd_7_valid_s1 <= probe_fwd_7_valid;
      out_probe_fwd_8_valid_s1 <= out_probe_fwd_8_valid__st0;
      probe_fwd_8_valid_s1 <= probe_fwd_8_valid;
      out_probe_fwd_9_valid_s1 <= out_probe_fwd_9_valid__st0;
      probe_fwd_9_valid_s1 <= probe_fwd_9_valid;
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
      out_probe_hop_cnt_s1 <= out_probe_hop_cnt__st0;
      probe_hop_cnt_s1 <= probe_hop_cnt;
      out_probe_data_0_bos_s1 <= out_probe_data_0_bos__st0;
      probe_data_0_bos_s1 <= probe_data_0_bos;
      out_probe_data_0_swid_s1 <= out_probe_data_0_swid__st0;
      probe_data_0_swid_s1 <= probe_data_0_swid;
      out_probe_data_0_port_s1 <= out_probe_data_0_port__st0;
      probe_data_0_port_s1 <= probe_data_0_port;
      out_probe_data_0_byte_cnt_s1 <= out_probe_data_0_byte_cnt__st0;
      probe_data_0_byte_cnt_s1 <= probe_data_0_byte_cnt;
      out_probe_data_0_last_time_s1 <= out_probe_data_0_last_time__st0;
      probe_data_0_last_time_s1 <= probe_data_0_last_time;
      out_probe_data_0_cur_time_s1 <= out_probe_data_0_cur_time__st0;
      probe_data_0_cur_time_s1 <= probe_data_0_cur_time;
      out_probe_data_1_bos_s1 <= out_probe_data_1_bos__st0;
      probe_data_1_bos_s1 <= probe_data_1_bos;
      out_probe_data_1_swid_s1 <= out_probe_data_1_swid__st0;
      probe_data_1_swid_s1 <= probe_data_1_swid;
      out_probe_data_1_port_s1 <= out_probe_data_1_port__st0;
      probe_data_1_port_s1 <= probe_data_1_port;
      out_probe_data_1_byte_cnt_s1 <= out_probe_data_1_byte_cnt__st0;
      probe_data_1_byte_cnt_s1 <= probe_data_1_byte_cnt;
      out_probe_data_1_last_time_s1 <= out_probe_data_1_last_time__st0;
      probe_data_1_last_time_s1 <= probe_data_1_last_time;
      out_probe_data_1_cur_time_s1 <= out_probe_data_1_cur_time__st0;
      probe_data_1_cur_time_s1 <= probe_data_1_cur_time;
      out_probe_data_2_bos_s1 <= out_probe_data_2_bos__st0;
      probe_data_2_bos_s1 <= probe_data_2_bos;
      out_probe_data_2_swid_s1 <= out_probe_data_2_swid__st0;
      probe_data_2_swid_s1 <= probe_data_2_swid;
      out_probe_data_2_port_s1 <= out_probe_data_2_port__st0;
      probe_data_2_port_s1 <= probe_data_2_port;
      out_probe_data_2_byte_cnt_s1 <= out_probe_data_2_byte_cnt__st0;
      probe_data_2_byte_cnt_s1 <= probe_data_2_byte_cnt;
      out_probe_data_2_last_time_s1 <= out_probe_data_2_last_time__st0;
      probe_data_2_last_time_s1 <= probe_data_2_last_time;
      out_probe_data_2_cur_time_s1 <= out_probe_data_2_cur_time__st0;
      probe_data_2_cur_time_s1 <= probe_data_2_cur_time;
      out_probe_data_3_bos_s1 <= out_probe_data_3_bos__st0;
      probe_data_3_bos_s1 <= probe_data_3_bos;
      out_probe_data_3_swid_s1 <= out_probe_data_3_swid__st0;
      probe_data_3_swid_s1 <= probe_data_3_swid;
      out_probe_data_3_port_s1 <= out_probe_data_3_port__st0;
      probe_data_3_port_s1 <= probe_data_3_port;
      out_probe_data_3_byte_cnt_s1 <= out_probe_data_3_byte_cnt__st0;
      probe_data_3_byte_cnt_s1 <= probe_data_3_byte_cnt;
      out_probe_data_3_last_time_s1 <= out_probe_data_3_last_time__st0;
      probe_data_3_last_time_s1 <= probe_data_3_last_time;
      out_probe_data_3_cur_time_s1 <= out_probe_data_3_cur_time__st0;
      probe_data_3_cur_time_s1 <= probe_data_3_cur_time;
      out_probe_data_4_bos_s1 <= out_probe_data_4_bos__st0;
      probe_data_4_bos_s1 <= probe_data_4_bos;
      out_probe_data_4_swid_s1 <= out_probe_data_4_swid__st0;
      probe_data_4_swid_s1 <= probe_data_4_swid;
      out_probe_data_4_port_s1 <= out_probe_data_4_port__st0;
      probe_data_4_port_s1 <= probe_data_4_port;
      out_probe_data_4_byte_cnt_s1 <= out_probe_data_4_byte_cnt__st0;
      probe_data_4_byte_cnt_s1 <= probe_data_4_byte_cnt;
      out_probe_data_4_last_time_s1 <= out_probe_data_4_last_time__st0;
      probe_data_4_last_time_s1 <= probe_data_4_last_time;
      out_probe_data_4_cur_time_s1 <= out_probe_data_4_cur_time__st0;
      probe_data_4_cur_time_s1 <= probe_data_4_cur_time;
      out_probe_data_5_bos_s1 <= out_probe_data_5_bos__st0;
      probe_data_5_bos_s1 <= probe_data_5_bos;
      out_probe_data_5_swid_s1 <= out_probe_data_5_swid__st0;
      probe_data_5_swid_s1 <= probe_data_5_swid;
      out_probe_data_5_port_s1 <= out_probe_data_5_port__st0;
      probe_data_5_port_s1 <= probe_data_5_port;
      out_probe_data_5_byte_cnt_s1 <= out_probe_data_5_byte_cnt__st0;
      probe_data_5_byte_cnt_s1 <= probe_data_5_byte_cnt;
      out_probe_data_5_last_time_s1 <= out_probe_data_5_last_time__st0;
      probe_data_5_last_time_s1 <= probe_data_5_last_time;
      out_probe_data_5_cur_time_s1 <= out_probe_data_5_cur_time__st0;
      probe_data_5_cur_time_s1 <= probe_data_5_cur_time;
      out_probe_data_6_bos_s1 <= out_probe_data_6_bos__st0;
      probe_data_6_bos_s1 <= probe_data_6_bos;
      out_probe_data_6_swid_s1 <= out_probe_data_6_swid__st0;
      probe_data_6_swid_s1 <= probe_data_6_swid;
      out_probe_data_6_port_s1 <= out_probe_data_6_port__st0;
      probe_data_6_port_s1 <= probe_data_6_port;
      out_probe_data_6_byte_cnt_s1 <= out_probe_data_6_byte_cnt__st0;
      probe_data_6_byte_cnt_s1 <= probe_data_6_byte_cnt;
      out_probe_data_6_last_time_s1 <= out_probe_data_6_last_time__st0;
      probe_data_6_last_time_s1 <= probe_data_6_last_time;
      out_probe_data_6_cur_time_s1 <= out_probe_data_6_cur_time__st0;
      probe_data_6_cur_time_s1 <= probe_data_6_cur_time;
      out_probe_data_7_bos_s1 <= out_probe_data_7_bos__st0;
      probe_data_7_bos_s1 <= probe_data_7_bos;
      out_probe_data_7_swid_s1 <= out_probe_data_7_swid__st0;
      probe_data_7_swid_s1 <= probe_data_7_swid;
      out_probe_data_7_port_s1 <= out_probe_data_7_port__st0;
      probe_data_7_port_s1 <= probe_data_7_port;
      out_probe_data_7_byte_cnt_s1 <= out_probe_data_7_byte_cnt__st0;
      probe_data_7_byte_cnt_s1 <= probe_data_7_byte_cnt;
      out_probe_data_7_last_time_s1 <= out_probe_data_7_last_time__st0;
      probe_data_7_last_time_s1 <= probe_data_7_last_time;
      out_probe_data_7_cur_time_s1 <= out_probe_data_7_cur_time__st0;
      probe_data_7_cur_time_s1 <= probe_data_7_cur_time;
      out_probe_data_8_bos_s1 <= out_probe_data_8_bos__st0;
      probe_data_8_bos_s1 <= probe_data_8_bos;
      out_probe_data_8_swid_s1 <= out_probe_data_8_swid__st0;
      probe_data_8_swid_s1 <= probe_data_8_swid;
      out_probe_data_8_port_s1 <= out_probe_data_8_port__st0;
      probe_data_8_port_s1 <= probe_data_8_port;
      out_probe_data_8_byte_cnt_s1 <= out_probe_data_8_byte_cnt__st0;
      probe_data_8_byte_cnt_s1 <= probe_data_8_byte_cnt;
      out_probe_data_8_last_time_s1 <= out_probe_data_8_last_time__st0;
      probe_data_8_last_time_s1 <= probe_data_8_last_time;
      out_probe_data_8_cur_time_s1 <= out_probe_data_8_cur_time__st0;
      probe_data_8_cur_time_s1 <= probe_data_8_cur_time;
      out_probe_data_9_bos_s1 <= out_probe_data_9_bos__st0;
      probe_data_9_bos_s1 <= probe_data_9_bos;
      out_probe_data_9_swid_s1 <= out_probe_data_9_swid__st0;
      probe_data_9_swid_s1 <= probe_data_9_swid;
      out_probe_data_9_port_s1 <= out_probe_data_9_port__st0;
      probe_data_9_port_s1 <= probe_data_9_port;
      out_probe_data_9_byte_cnt_s1 <= out_probe_data_9_byte_cnt__st0;
      probe_data_9_byte_cnt_s1 <= probe_data_9_byte_cnt;
      out_probe_data_9_last_time_s1 <= out_probe_data_9_last_time__st0;
      probe_data_9_last_time_s1 <= probe_data_9_last_time;
      out_probe_data_9_cur_time_s1 <= out_probe_data_9_cur_time__st0;
      probe_data_9_cur_time_s1 <= probe_data_9_cur_time;
      out_probe_fwd_0_egress_spec_s1 <= out_probe_fwd_0_egress_spec__st0;
      probe_fwd_0_egress_spec_s1 <= probe_fwd_0_egress_spec;
      out_probe_fwd_1_egress_spec_s1 <= out_probe_fwd_1_egress_spec__st0;
      probe_fwd_1_egress_spec_s1 <= probe_fwd_1_egress_spec;
      out_probe_fwd_2_egress_spec_s1 <= out_probe_fwd_2_egress_spec__st0;
      probe_fwd_2_egress_spec_s1 <= probe_fwd_2_egress_spec;
      out_probe_fwd_3_egress_spec_s1 <= out_probe_fwd_3_egress_spec__st0;
      probe_fwd_3_egress_spec_s1 <= probe_fwd_3_egress_spec;
      out_probe_fwd_4_egress_spec_s1 <= out_probe_fwd_4_egress_spec__st0;
      probe_fwd_4_egress_spec_s1 <= probe_fwd_4_egress_spec;
      out_probe_fwd_5_egress_spec_s1 <= out_probe_fwd_5_egress_spec__st0;
      probe_fwd_5_egress_spec_s1 <= probe_fwd_5_egress_spec;
      out_probe_fwd_6_egress_spec_s1 <= out_probe_fwd_6_egress_spec__st0;
      probe_fwd_6_egress_spec_s1 <= probe_fwd_6_egress_spec;
      out_probe_fwd_7_egress_spec_s1 <= out_probe_fwd_7_egress_spec__st0;
      probe_fwd_7_egress_spec_s1 <= probe_fwd_7_egress_spec;
      out_probe_fwd_8_egress_spec_s1 <= out_probe_fwd_8_egress_spec__st0;
      probe_fwd_8_egress_spec_s1 <= probe_fwd_8_egress_spec;
      out_probe_fwd_9_egress_spec_s1 <= out_probe_fwd_9_egress_spec__st0;
      probe_fwd_9_egress_spec_s1 <= probe_fwd_9_egress_spec;
      out_std_meta_egress_spec_s1 <= out_std_meta_egress_spec__st0;
      __stage_cond_0_r <= (ipv4_valid);
    end
  end

  // ---- Pipeline stage 1 (registered 1 cycle(s) after stage 0) ----
  always_comb begin
    drop = drop_s1;
    byte_cnt_0__st1 = byte_cnt_0_s1;
    last_time_0__st1 = last_time_0_s1;
    tmp__st1 = tmp_s1;
    tmp_0__st1 = tmp_0_s1;
    tmp_1__st1 = tmp_1_s1;
    tmp_2__st1 = tmp_2_s1;
    tmp_3__st1 = tmp_3_s1;
    meta__egress_spec0_w__st1 = meta__egress_spec0_w_s1;
    meta__parser_metadata_remaining1_w__st1 = meta__parser_metadata_remaining1_w_s1;
    out_ethernet_valid = out_ethernet_valid_s1;
    ethernet_valid__st1 = ethernet_valid_s1;
    out_ipv4_valid = out_ipv4_valid_s1;
    ipv4_valid__st1 = ipv4_valid_s1;
    out_probe_valid = out_probe_valid_s1;
    probe_valid__st1 = probe_valid_s1;
    out_probe_data_0_valid = out_probe_data_0_valid_s1;
    probe_data_0_valid__st1 = probe_data_0_valid_s1;
    out_probe_data_1_valid = out_probe_data_1_valid_s1;
    probe_data_1_valid__st1 = probe_data_1_valid_s1;
    out_probe_data_2_valid = out_probe_data_2_valid_s1;
    probe_data_2_valid__st1 = probe_data_2_valid_s1;
    out_probe_data_3_valid = out_probe_data_3_valid_s1;
    probe_data_3_valid__st1 = probe_data_3_valid_s1;
    out_probe_data_4_valid = out_probe_data_4_valid_s1;
    probe_data_4_valid__st1 = probe_data_4_valid_s1;
    out_probe_data_5_valid = out_probe_data_5_valid_s1;
    probe_data_5_valid__st1 = probe_data_5_valid_s1;
    out_probe_data_6_valid = out_probe_data_6_valid_s1;
    probe_data_6_valid__st1 = probe_data_6_valid_s1;
    out_probe_data_7_valid = out_probe_data_7_valid_s1;
    probe_data_7_valid__st1 = probe_data_7_valid_s1;
    out_probe_data_8_valid = out_probe_data_8_valid_s1;
    probe_data_8_valid__st1 = probe_data_8_valid_s1;
    out_probe_data_9_valid = out_probe_data_9_valid_s1;
    probe_data_9_valid__st1 = probe_data_9_valid_s1;
    out_probe_fwd_0_valid = out_probe_fwd_0_valid_s1;
    probe_fwd_0_valid__st1 = probe_fwd_0_valid_s1;
    out_probe_fwd_1_valid = out_probe_fwd_1_valid_s1;
    probe_fwd_1_valid__st1 = probe_fwd_1_valid_s1;
    out_probe_fwd_2_valid = out_probe_fwd_2_valid_s1;
    probe_fwd_2_valid__st1 = probe_fwd_2_valid_s1;
    out_probe_fwd_3_valid = out_probe_fwd_3_valid_s1;
    probe_fwd_3_valid__st1 = probe_fwd_3_valid_s1;
    out_probe_fwd_4_valid = out_probe_fwd_4_valid_s1;
    probe_fwd_4_valid__st1 = probe_fwd_4_valid_s1;
    out_probe_fwd_5_valid = out_probe_fwd_5_valid_s1;
    probe_fwd_5_valid__st1 = probe_fwd_5_valid_s1;
    out_probe_fwd_6_valid = out_probe_fwd_6_valid_s1;
    probe_fwd_6_valid__st1 = probe_fwd_6_valid_s1;
    out_probe_fwd_7_valid = out_probe_fwd_7_valid_s1;
    probe_fwd_7_valid__st1 = probe_fwd_7_valid_s1;
    out_probe_fwd_8_valid = out_probe_fwd_8_valid_s1;
    probe_fwd_8_valid__st1 = probe_fwd_8_valid_s1;
    out_probe_fwd_9_valid = out_probe_fwd_9_valid_s1;
    probe_fwd_9_valid__st1 = probe_fwd_9_valid_s1;
    out_ethernet_dstAddr = out_ethernet_dstAddr_s1;
    ethernet_dstAddr__st1 = ethernet_dstAddr_s1;
    out_ethernet_srcAddr = out_ethernet_srcAddr_s1;
    ethernet_srcAddr__st1 = ethernet_srcAddr_s1;
    out_ethernet_etherType = out_ethernet_etherType_s1;
    ethernet_etherType__st1 = ethernet_etherType_s1;
    out_ipv4_version = out_ipv4_version_s1;
    ipv4_version__st1 = ipv4_version_s1;
    out_ipv4_ihl = out_ipv4_ihl_s1;
    ipv4_ihl__st1 = ipv4_ihl_s1;
    out_ipv4_diffserv = out_ipv4_diffserv_s1;
    ipv4_diffserv__st1 = ipv4_diffserv_s1;
    out_ipv4_totalLen = out_ipv4_totalLen_s1;
    ipv4_totalLen__st1 = ipv4_totalLen_s1;
    out_ipv4_identification = out_ipv4_identification_s1;
    ipv4_identification__st1 = ipv4_identification_s1;
    out_ipv4_flags = out_ipv4_flags_s1;
    ipv4_flags__st1 = ipv4_flags_s1;
    out_ipv4_fragOffset = out_ipv4_fragOffset_s1;
    ipv4_fragOffset__st1 = ipv4_fragOffset_s1;
    out_ipv4_ttl = out_ipv4_ttl_s1;
    ipv4_ttl__st1 = ipv4_ttl_s1;
    out_ipv4_protocol = out_ipv4_protocol_s1;
    ipv4_protocol__st1 = ipv4_protocol_s1;
    out_ipv4_hdrChecksum = out_ipv4_hdrChecksum_s1;
    ipv4_hdrChecksum__st1 = ipv4_hdrChecksum_s1;
    out_ipv4_srcAddr = out_ipv4_srcAddr_s1;
    ipv4_srcAddr__st1 = ipv4_srcAddr_s1;
    out_ipv4_dstAddr = out_ipv4_dstAddr_s1;
    ipv4_dstAddr__st1 = ipv4_dstAddr_s1;
    out_probe_hop_cnt = out_probe_hop_cnt_s1;
    probe_hop_cnt__st1 = probe_hop_cnt_s1;
    out_probe_data_0_bos = out_probe_data_0_bos_s1;
    probe_data_0_bos__st1 = probe_data_0_bos_s1;
    out_probe_data_0_swid = out_probe_data_0_swid_s1;
    probe_data_0_swid__st1 = probe_data_0_swid_s1;
    out_probe_data_0_port = out_probe_data_0_port_s1;
    probe_data_0_port__st1 = probe_data_0_port_s1;
    out_probe_data_0_byte_cnt = out_probe_data_0_byte_cnt_s1;
    probe_data_0_byte_cnt__st1 = probe_data_0_byte_cnt_s1;
    out_probe_data_0_last_time = out_probe_data_0_last_time_s1;
    probe_data_0_last_time__st1 = probe_data_0_last_time_s1;
    out_probe_data_0_cur_time = out_probe_data_0_cur_time_s1;
    probe_data_0_cur_time__st1 = probe_data_0_cur_time_s1;
    out_probe_data_1_bos = out_probe_data_1_bos_s1;
    probe_data_1_bos__st1 = probe_data_1_bos_s1;
    out_probe_data_1_swid = out_probe_data_1_swid_s1;
    probe_data_1_swid__st1 = probe_data_1_swid_s1;
    out_probe_data_1_port = out_probe_data_1_port_s1;
    probe_data_1_port__st1 = probe_data_1_port_s1;
    out_probe_data_1_byte_cnt = out_probe_data_1_byte_cnt_s1;
    probe_data_1_byte_cnt__st1 = probe_data_1_byte_cnt_s1;
    out_probe_data_1_last_time = out_probe_data_1_last_time_s1;
    probe_data_1_last_time__st1 = probe_data_1_last_time_s1;
    out_probe_data_1_cur_time = out_probe_data_1_cur_time_s1;
    probe_data_1_cur_time__st1 = probe_data_1_cur_time_s1;
    out_probe_data_2_bos = out_probe_data_2_bos_s1;
    probe_data_2_bos__st1 = probe_data_2_bos_s1;
    out_probe_data_2_swid = out_probe_data_2_swid_s1;
    probe_data_2_swid__st1 = probe_data_2_swid_s1;
    out_probe_data_2_port = out_probe_data_2_port_s1;
    probe_data_2_port__st1 = probe_data_2_port_s1;
    out_probe_data_2_byte_cnt = out_probe_data_2_byte_cnt_s1;
    probe_data_2_byte_cnt__st1 = probe_data_2_byte_cnt_s1;
    out_probe_data_2_last_time = out_probe_data_2_last_time_s1;
    probe_data_2_last_time__st1 = probe_data_2_last_time_s1;
    out_probe_data_2_cur_time = out_probe_data_2_cur_time_s1;
    probe_data_2_cur_time__st1 = probe_data_2_cur_time_s1;
    out_probe_data_3_bos = out_probe_data_3_bos_s1;
    probe_data_3_bos__st1 = probe_data_3_bos_s1;
    out_probe_data_3_swid = out_probe_data_3_swid_s1;
    probe_data_3_swid__st1 = probe_data_3_swid_s1;
    out_probe_data_3_port = out_probe_data_3_port_s1;
    probe_data_3_port__st1 = probe_data_3_port_s1;
    out_probe_data_3_byte_cnt = out_probe_data_3_byte_cnt_s1;
    probe_data_3_byte_cnt__st1 = probe_data_3_byte_cnt_s1;
    out_probe_data_3_last_time = out_probe_data_3_last_time_s1;
    probe_data_3_last_time__st1 = probe_data_3_last_time_s1;
    out_probe_data_3_cur_time = out_probe_data_3_cur_time_s1;
    probe_data_3_cur_time__st1 = probe_data_3_cur_time_s1;
    out_probe_data_4_bos = out_probe_data_4_bos_s1;
    probe_data_4_bos__st1 = probe_data_4_bos_s1;
    out_probe_data_4_swid = out_probe_data_4_swid_s1;
    probe_data_4_swid__st1 = probe_data_4_swid_s1;
    out_probe_data_4_port = out_probe_data_4_port_s1;
    probe_data_4_port__st1 = probe_data_4_port_s1;
    out_probe_data_4_byte_cnt = out_probe_data_4_byte_cnt_s1;
    probe_data_4_byte_cnt__st1 = probe_data_4_byte_cnt_s1;
    out_probe_data_4_last_time = out_probe_data_4_last_time_s1;
    probe_data_4_last_time__st1 = probe_data_4_last_time_s1;
    out_probe_data_4_cur_time = out_probe_data_4_cur_time_s1;
    probe_data_4_cur_time__st1 = probe_data_4_cur_time_s1;
    out_probe_data_5_bos = out_probe_data_5_bos_s1;
    probe_data_5_bos__st1 = probe_data_5_bos_s1;
    out_probe_data_5_swid = out_probe_data_5_swid_s1;
    probe_data_5_swid__st1 = probe_data_5_swid_s1;
    out_probe_data_5_port = out_probe_data_5_port_s1;
    probe_data_5_port__st1 = probe_data_5_port_s1;
    out_probe_data_5_byte_cnt = out_probe_data_5_byte_cnt_s1;
    probe_data_5_byte_cnt__st1 = probe_data_5_byte_cnt_s1;
    out_probe_data_5_last_time = out_probe_data_5_last_time_s1;
    probe_data_5_last_time__st1 = probe_data_5_last_time_s1;
    out_probe_data_5_cur_time = out_probe_data_5_cur_time_s1;
    probe_data_5_cur_time__st1 = probe_data_5_cur_time_s1;
    out_probe_data_6_bos = out_probe_data_6_bos_s1;
    probe_data_6_bos__st1 = probe_data_6_bos_s1;
    out_probe_data_6_swid = out_probe_data_6_swid_s1;
    probe_data_6_swid__st1 = probe_data_6_swid_s1;
    out_probe_data_6_port = out_probe_data_6_port_s1;
    probe_data_6_port__st1 = probe_data_6_port_s1;
    out_probe_data_6_byte_cnt = out_probe_data_6_byte_cnt_s1;
    probe_data_6_byte_cnt__st1 = probe_data_6_byte_cnt_s1;
    out_probe_data_6_last_time = out_probe_data_6_last_time_s1;
    probe_data_6_last_time__st1 = probe_data_6_last_time_s1;
    out_probe_data_6_cur_time = out_probe_data_6_cur_time_s1;
    probe_data_6_cur_time__st1 = probe_data_6_cur_time_s1;
    out_probe_data_7_bos = out_probe_data_7_bos_s1;
    probe_data_7_bos__st1 = probe_data_7_bos_s1;
    out_probe_data_7_swid = out_probe_data_7_swid_s1;
    probe_data_7_swid__st1 = probe_data_7_swid_s1;
    out_probe_data_7_port = out_probe_data_7_port_s1;
    probe_data_7_port__st1 = probe_data_7_port_s1;
    out_probe_data_7_byte_cnt = out_probe_data_7_byte_cnt_s1;
    probe_data_7_byte_cnt__st1 = probe_data_7_byte_cnt_s1;
    out_probe_data_7_last_time = out_probe_data_7_last_time_s1;
    probe_data_7_last_time__st1 = probe_data_7_last_time_s1;
    out_probe_data_7_cur_time = out_probe_data_7_cur_time_s1;
    probe_data_7_cur_time__st1 = probe_data_7_cur_time_s1;
    out_probe_data_8_bos = out_probe_data_8_bos_s1;
    probe_data_8_bos__st1 = probe_data_8_bos_s1;
    out_probe_data_8_swid = out_probe_data_8_swid_s1;
    probe_data_8_swid__st1 = probe_data_8_swid_s1;
    out_probe_data_8_port = out_probe_data_8_port_s1;
    probe_data_8_port__st1 = probe_data_8_port_s1;
    out_probe_data_8_byte_cnt = out_probe_data_8_byte_cnt_s1;
    probe_data_8_byte_cnt__st1 = probe_data_8_byte_cnt_s1;
    out_probe_data_8_last_time = out_probe_data_8_last_time_s1;
    probe_data_8_last_time__st1 = probe_data_8_last_time_s1;
    out_probe_data_8_cur_time = out_probe_data_8_cur_time_s1;
    probe_data_8_cur_time__st1 = probe_data_8_cur_time_s1;
    out_probe_data_9_bos = out_probe_data_9_bos_s1;
    probe_data_9_bos__st1 = probe_data_9_bos_s1;
    out_probe_data_9_swid = out_probe_data_9_swid_s1;
    probe_data_9_swid__st1 = probe_data_9_swid_s1;
    out_probe_data_9_port = out_probe_data_9_port_s1;
    probe_data_9_port__st1 = probe_data_9_port_s1;
    out_probe_data_9_byte_cnt = out_probe_data_9_byte_cnt_s1;
    probe_data_9_byte_cnt__st1 = probe_data_9_byte_cnt_s1;
    out_probe_data_9_last_time = out_probe_data_9_last_time_s1;
    probe_data_9_last_time__st1 = probe_data_9_last_time_s1;
    out_probe_data_9_cur_time = out_probe_data_9_cur_time_s1;
    probe_data_9_cur_time__st1 = probe_data_9_cur_time_s1;
    out_probe_fwd_0_egress_spec = out_probe_fwd_0_egress_spec_s1;
    probe_fwd_0_egress_spec__st1 = probe_fwd_0_egress_spec_s1;
    out_probe_fwd_1_egress_spec = out_probe_fwd_1_egress_spec_s1;
    probe_fwd_1_egress_spec__st1 = probe_fwd_1_egress_spec_s1;
    out_probe_fwd_2_egress_spec = out_probe_fwd_2_egress_spec_s1;
    probe_fwd_2_egress_spec__st1 = probe_fwd_2_egress_spec_s1;
    out_probe_fwd_3_egress_spec = out_probe_fwd_3_egress_spec_s1;
    probe_fwd_3_egress_spec__st1 = probe_fwd_3_egress_spec_s1;
    out_probe_fwd_4_egress_spec = out_probe_fwd_4_egress_spec_s1;
    probe_fwd_4_egress_spec__st1 = probe_fwd_4_egress_spec_s1;
    out_probe_fwd_5_egress_spec = out_probe_fwd_5_egress_spec_s1;
    probe_fwd_5_egress_spec__st1 = probe_fwd_5_egress_spec_s1;
    out_probe_fwd_6_egress_spec = out_probe_fwd_6_egress_spec_s1;
    probe_fwd_6_egress_spec__st1 = probe_fwd_6_egress_spec_s1;
    out_probe_fwd_7_egress_spec = out_probe_fwd_7_egress_spec_s1;
    probe_fwd_7_egress_spec__st1 = probe_fwd_7_egress_spec_s1;
    out_probe_fwd_8_egress_spec = out_probe_fwd_8_egress_spec_s1;
    probe_fwd_8_egress_spec__st1 = probe_fwd_8_egress_spec_s1;
    out_probe_fwd_9_egress_spec = out_probe_fwd_9_egress_spec_s1;
    probe_fwd_9_egress_spec__st1 = probe_fwd_9_egress_spec_s1;
    out_std_meta_egress_spec = out_std_meta_egress_spec_s1;

    // apply block (stage 1 of 1)
    if (__stage_cond_0_r) begin
      // ipv4_lpm.apply()
      if (ipv4_lpm_hit) begin
        unique case (ipv4_lpm_act_id)
          2'd0: ; // NoAction
          2'd1: begin // ipv4_forward
            out_std_meta_egress_spec = ipv4_lpm_p_port;
            out_ethernet_srcAddr = ethernet_dstAddr__st1;
            out_ethernet_dstAddr = ipv4_lpm_p_dstAddr;
            out_ipv4_ttl = ((ipv4_ttl__st1 + 'hFF) & 'hFF);
          end
          2'd2: begin // drop
            drop = 1;
          end
          default: ; // default = drop
        endcase
      end else begin // drop on miss
        drop = 1;
      end
    end
  end

  // Register write-back (initialized via initial block above)
  always_ff @(posedge clk) begin
    if (byte_cnt_reg_wr_en)
      byte_cnt_reg_mem[byte_cnt_reg_wr_addr] <= byte_cnt_reg_wr_data;
  end
  always_ff @(posedge clk) begin
    if (last_time_reg_wr_en)
      last_time_reg_mem[last_time_reg_wr_addr] <= last_time_reg_wr_data;
  end

  always_ff @(posedge clk) begin
    if (!rst_n) valid_out <= 0;
    else        valid_out <= valid_s1;
  end

endmodule
