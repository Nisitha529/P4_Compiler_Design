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
  input  logic [3:0] tcp_res,
  input  logic [0:0] tcp_cwr,
  input  logic [0:0] tcp_ece,
  input  logic [0:0] tcp_urg,
  input  logic [0:0] tcp_ack,
  input  logic [0:0] tcp_psh,
  input  logic [0:0] tcp_rst,
  input  logic [0:0] tcp_syn,
  input  logic [0:0] tcp_fin,
  input  logic [15:0] tcp_window,
  input  logic [15:0] tcp_checksum,
  input  logic [15:0] tcp_urgentPtr,

  // Standard metadata inputs (table key sources)
  input  logic [8:0] std_meta_egress_spec,
  input  logic [8:0] std_meta_ingress_port,

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
  output logic [3:0] out_tcp_res,
  output logic [0:0] out_tcp_cwr,
  output logic [0:0] out_tcp_ece,
  output logic [0:0] out_tcp_urg,
  output logic [0:0] out_tcp_ack,
  output logic [0:0] out_tcp_psh,
  output logic [0:0] out_tcp_rst,
  output logic [0:0] out_tcp_syn,
  output logic [0:0] out_tcp_fin,
  output logic [15:0] out_tcp_window,
  output logic [15:0] out_tcp_checksum,
  output logic [15:0] out_tcp_urgentPtr,

  // Standard metadata outputs
  output logic [8:0] out_std_meta_egress_spec,

  // Control-plane write ports for table instances
  input  logic        ipv4_lpm_cp_wr_en,
  input  logic [7:0] ipv4_lpm_cp_wr_idx,
  input  logic [31:0] ipv4_lpm_cp_wr_key_dstAddr,
  input  logic [5:0] ipv4_lpm_cp_wr_pfx_len,
  input  logic [1:0] ipv4_lpm_cp_wr_action,
  input  logic [47:0] ipv4_lpm_cp_wr_p_dstAddr,
  input  logic [8:0] ipv4_lpm_cp_wr_p_port,
  input  logic        check_ports_cp_wr_en,
  input  logic [9:0] check_ports_cp_wr_idx,
  input  logic [8:0] check_ports_cp_wr_key_ingress_port,
  input  logic [8:0] check_ports_cp_wr_key_egress_spec,
  input  logic [0:0] check_ports_cp_wr_action,
  input  logic [0:0] check_ports_cp_wr_p_dir,

  // Table hit outputs
  output logic        ipv4_lpm_hit_out,
  output logic        check_ports_hit_out,

  output logic        valid_out,
  output logic        drop
);

  logic [4:0] _padding_0;
  logic [0:0] direction_0;
  logic [31:0] reg_pos_one_0;
  logic [31:0] reg_pos_two_0;
  logic [0:0] reg_val_one_0;
  logic [0:0] reg_val_two_0;
  logic [31:0] tmp;
  logic [31:0] tmp_0;
  logic [15:0] tmp_1;
  logic [31:0] tmp_10;
  logic [15:0] tmp_11;
  logic [15:0] tmp_12;
  logic [7:0] tmp_13;
  logic [31:0] tmp_14;
  logic [31:0] tmp_15;
  logic [15:0] tmp_16;
  logic [15:0] tmp_17;
  logic [7:0] tmp_18;
  logic [15:0] tmp_2;
  logic [7:0] tmp_3;
  logic [31:0] tmp_4;
  logic [31:0] tmp_5;
  logic [15:0] tmp_6;
  logic [15:0] tmp_7;
  logic [7:0] tmp_8;
  logic [31:0] tmp_9;

  // update_checksum -> ipv4.hdrChecksum
  wire [143:0] chk0_concat = {out_ipv4_version, out_ipv4_ihl, out_ipv4_diffserv, out_ipv4_totalLen, out_ipv4_identification, out_ipv4_flags, out_ipv4_fragOffset, out_ipv4_ttl, out_ipv4_protocol, out_ipv4_srcAddr, out_ipv4_dstAddr};
  wire [31:0] chk0_sum   = {16'd0, chk0_concat[143:128]} + {16'd0, chk0_concat[127:112]} + {16'd0, chk0_concat[111:96]} + {16'd0, chk0_concat[95:80]} + {16'd0, chk0_concat[79:64]} + {16'd0, chk0_concat[63:48]} + {16'd0, chk0_concat[47:32]} + {16'd0, chk0_concat[31:16]} + {16'd0, chk0_concat[15:0]};
  wire [16:0] chk0_fold1 = chk0_sum[15:0] + chk0_sum[31:16];
  wire [16:0] chk0_fold2 = {15'd0, chk0_fold1[16]} + {1'b0, chk0_fold1[15:0]};
  wire [15:0] chk0_value = ~chk0_fold2[15:0];

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
  logic [3:0] out_tcp_res_s1;
  logic [3:0] tcp_res_s1;
  logic [0:0] out_tcp_cwr_s1;
  logic [0:0] tcp_cwr_s1;
  logic [0:0] out_tcp_ece_s1;
  logic [0:0] tcp_ece_s1;
  logic [0:0] out_tcp_urg_s1;
  logic [0:0] tcp_urg_s1;
  logic [0:0] out_tcp_ack_s1;
  logic [0:0] tcp_ack_s1;
  logic [0:0] out_tcp_psh_s1;
  logic [0:0] tcp_psh_s1;
  logic [0:0] out_tcp_rst_s1;
  logic [0:0] tcp_rst_s1;
  logic [0:0] out_tcp_syn_s1;
  logic [0:0] tcp_syn_s1;
  logic [0:0] out_tcp_fin_s1;
  logic [0:0] tcp_fin_s1;
  logic [15:0] out_tcp_window_s1;
  logic [15:0] tcp_window_s1;
  logic [15:0] out_tcp_checksum_s1;
  logic [15:0] tcp_checksum_s1;
  logic [15:0] out_tcp_urgentPtr_s1;
  logic [15:0] tcp_urgentPtr_s1;
  logic [4:0] _padding_0_s1;
  logic [0:0] direction_0_s1;
  logic [31:0] reg_pos_one_0_s1;
  logic [31:0] reg_pos_two_0_s1;
  logic [0:0] reg_val_one_0_s1;
  logic [0:0] reg_val_two_0_s1;
  logic [31:0] tmp_s1;
  logic [31:0] tmp_0_s1;
  logic [15:0] tmp_1_s1;
  logic [31:0] tmp_10_s1;
  logic [15:0] tmp_11_s1;
  logic [15:0] tmp_12_s1;
  logic [7:0] tmp_13_s1;
  logic [31:0] tmp_14_s1;
  logic [31:0] tmp_15_s1;
  logic [15:0] tmp_16_s1;
  logic [15:0] tmp_17_s1;
  logic [7:0] tmp_18_s1;
  logic [15:0] tmp_2_s1;
  logic [7:0] tmp_3_s1;
  logic [31:0] tmp_4_s1;
  logic [31:0] tmp_5_s1;
  logic [15:0] tmp_6_s1;
  logic [15:0] tmp_7_s1;
  logic [7:0] tmp_8_s1;
  logic [31:0] tmp_9_s1;
  logic [8:0] out_std_meta_egress_spec_s1;
  logic [8:0] std_meta_egress_spec_s1;
  logic [8:0] std_meta_ingress_port_s1;
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
  logic [3:0] out_tcp_res_s2;
  logic [3:0] tcp_res_s2;
  logic [0:0] out_tcp_cwr_s2;
  logic [0:0] tcp_cwr_s2;
  logic [0:0] out_tcp_ece_s2;
  logic [0:0] tcp_ece_s2;
  logic [0:0] out_tcp_urg_s2;
  logic [0:0] tcp_urg_s2;
  logic [0:0] out_tcp_ack_s2;
  logic [0:0] tcp_ack_s2;
  logic [0:0] out_tcp_psh_s2;
  logic [0:0] tcp_psh_s2;
  logic [0:0] out_tcp_rst_s2;
  logic [0:0] tcp_rst_s2;
  logic [0:0] out_tcp_syn_s2;
  logic [0:0] tcp_syn_s2;
  logic [0:0] out_tcp_fin_s2;
  logic [0:0] tcp_fin_s2;
  logic [15:0] out_tcp_window_s2;
  logic [15:0] tcp_window_s2;
  logic [15:0] out_tcp_checksum_s2;
  logic [15:0] tcp_checksum_s2;
  logic [15:0] out_tcp_urgentPtr_s2;
  logic [15:0] tcp_urgentPtr_s2;
  logic [4:0] _padding_0_s2;
  logic [0:0] direction_0_s2;
  logic [31:0] reg_pos_one_0_s2;
  logic [31:0] reg_pos_two_0_s2;
  logic [0:0] reg_val_one_0_s2;
  logic [0:0] reg_val_two_0_s2;
  logic [31:0] tmp_s2;
  logic [31:0] tmp_0_s2;
  logic [15:0] tmp_1_s2;
  logic [31:0] tmp_10_s2;
  logic [15:0] tmp_11_s2;
  logic [15:0] tmp_12_s2;
  logic [7:0] tmp_13_s2;
  logic [31:0] tmp_14_s2;
  logic [31:0] tmp_15_s2;
  logic [15:0] tmp_16_s2;
  logic [15:0] tmp_17_s2;
  logic [7:0] tmp_18_s2;
  logic [15:0] tmp_2_s2;
  logic [7:0] tmp_3_s2;
  logic [31:0] tmp_4_s2;
  logic [31:0] tmp_5_s2;
  logic [15:0] tmp_6_s2;
  logic [15:0] tmp_7_s2;
  logic [7:0] tmp_8_s2;
  logic [31:0] tmp_9_s2;
  logic [8:0] out_std_meta_egress_spec_s2;
  logic [8:0] std_meta_egress_spec_s2;
  logic [8:0] std_meta_ingress_port_s2;
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
  logic [3:0] out_tcp_res_s3;
  logic [3:0] tcp_res_s3;
  logic [0:0] out_tcp_cwr_s3;
  logic [0:0] tcp_cwr_s3;
  logic [0:0] out_tcp_ece_s3;
  logic [0:0] tcp_ece_s3;
  logic [0:0] out_tcp_urg_s3;
  logic [0:0] tcp_urg_s3;
  logic [0:0] out_tcp_ack_s3;
  logic [0:0] tcp_ack_s3;
  logic [0:0] out_tcp_psh_s3;
  logic [0:0] tcp_psh_s3;
  logic [0:0] out_tcp_rst_s3;
  logic [0:0] tcp_rst_s3;
  logic [0:0] out_tcp_syn_s3;
  logic [0:0] tcp_syn_s3;
  logic [0:0] out_tcp_fin_s3;
  logic [0:0] tcp_fin_s3;
  logic [15:0] out_tcp_window_s3;
  logic [15:0] tcp_window_s3;
  logic [15:0] out_tcp_checksum_s3;
  logic [15:0] tcp_checksum_s3;
  logic [15:0] out_tcp_urgentPtr_s3;
  logic [15:0] tcp_urgentPtr_s3;
  logic [4:0] _padding_0_s3;
  logic [0:0] direction_0_s3;
  logic [31:0] reg_pos_one_0_s3;
  logic [31:0] reg_pos_two_0_s3;
  logic [0:0] reg_val_one_0_s3;
  logic [0:0] reg_val_two_0_s3;
  logic [31:0] tmp_s3;
  logic [31:0] tmp_0_s3;
  logic [15:0] tmp_1_s3;
  logic [31:0] tmp_10_s3;
  logic [15:0] tmp_11_s3;
  logic [15:0] tmp_12_s3;
  logic [7:0] tmp_13_s3;
  logic [31:0] tmp_14_s3;
  logic [31:0] tmp_15_s3;
  logic [15:0] tmp_16_s3;
  logic [15:0] tmp_17_s3;
  logic [7:0] tmp_18_s3;
  logic [15:0] tmp_2_s3;
  logic [7:0] tmp_3_s3;
  logic [31:0] tmp_4_s3;
  logic [31:0] tmp_5_s3;
  logic [15:0] tmp_6_s3;
  logic [15:0] tmp_7_s3;
  logic [7:0] tmp_8_s3;
  logic [31:0] tmp_9_s3;
  logic [8:0] out_std_meta_egress_spec_s3;
  logic [8:0] std_meta_egress_spec_s3;
  logic [8:0] std_meta_ingress_port_s3;
  logic drop_s3;
  logic __stage_cond_2_r;
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
  logic [3:0] out_tcp_res_s4;
  logic [3:0] tcp_res_s4;
  logic [0:0] out_tcp_cwr_s4;
  logic [0:0] tcp_cwr_s4;
  logic [0:0] out_tcp_ece_s4;
  logic [0:0] tcp_ece_s4;
  logic [0:0] out_tcp_urg_s4;
  logic [0:0] tcp_urg_s4;
  logic [0:0] out_tcp_ack_s4;
  logic [0:0] tcp_ack_s4;
  logic [0:0] out_tcp_psh_s4;
  logic [0:0] tcp_psh_s4;
  logic [0:0] out_tcp_rst_s4;
  logic [0:0] tcp_rst_s4;
  logic [0:0] out_tcp_syn_s4;
  logic [0:0] tcp_syn_s4;
  logic [0:0] out_tcp_fin_s4;
  logic [0:0] tcp_fin_s4;
  logic [15:0] out_tcp_window_s4;
  logic [15:0] tcp_window_s4;
  logic [15:0] out_tcp_checksum_s4;
  logic [15:0] tcp_checksum_s4;
  logic [15:0] out_tcp_urgentPtr_s4;
  logic [15:0] tcp_urgentPtr_s4;
  logic [4:0] _padding_0_s4;
  logic [0:0] direction_0_s4;
  logic [31:0] reg_pos_one_0_s4;
  logic [31:0] reg_pos_two_0_s4;
  logic [0:0] reg_val_one_0_s4;
  logic [0:0] reg_val_two_0_s4;
  logic [31:0] tmp_s4;
  logic [31:0] tmp_0_s4;
  logic [15:0] tmp_1_s4;
  logic [31:0] tmp_10_s4;
  logic [15:0] tmp_11_s4;
  logic [15:0] tmp_12_s4;
  logic [7:0] tmp_13_s4;
  logic [31:0] tmp_14_s4;
  logic [31:0] tmp_15_s4;
  logic [15:0] tmp_16_s4;
  logic [15:0] tmp_17_s4;
  logic [7:0] tmp_18_s4;
  logic [15:0] tmp_2_s4;
  logic [7:0] tmp_3_s4;
  logic [31:0] tmp_4_s4;
  logic [31:0] tmp_5_s4;
  logic [15:0] tmp_6_s4;
  logic [15:0] tmp_7_s4;
  logic [7:0] tmp_8_s4;
  logic [31:0] tmp_9_s4;
  logic [8:0] out_std_meta_egress_spec_s4;
  logic [8:0] std_meta_egress_spec_s4;
  logic [8:0] std_meta_ingress_port_s4;
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
  logic [3:0] out_tcp_res__st0;
  logic [0:0] out_tcp_cwr__st0;
  logic [0:0] out_tcp_ece__st0;
  logic [0:0] out_tcp_urg__st0;
  logic [0:0] out_tcp_ack__st0;
  logic [0:0] out_tcp_psh__st0;
  logic [0:0] out_tcp_rst__st0;
  logic [0:0] out_tcp_syn__st0;
  logic [0:0] out_tcp_fin__st0;
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
  logic [3:0] out_tcp_res__st1;
  logic [0:0] out_tcp_cwr__st1;
  logic [0:0] out_tcp_ece__st1;
  logic [0:0] out_tcp_urg__st1;
  logic [0:0] out_tcp_ack__st1;
  logic [0:0] out_tcp_psh__st1;
  logic [0:0] out_tcp_rst__st1;
  logic [0:0] out_tcp_syn__st1;
  logic [0:0] out_tcp_fin__st1;
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
  logic [3:0] out_tcp_res__st2;
  logic [0:0] out_tcp_cwr__st2;
  logic [0:0] out_tcp_ece__st2;
  logic [0:0] out_tcp_urg__st2;
  logic [0:0] out_tcp_ack__st2;
  logic [0:0] out_tcp_psh__st2;
  logic [0:0] out_tcp_rst__st2;
  logic [0:0] out_tcp_syn__st2;
  logic [0:0] out_tcp_fin__st2;
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
  logic [3:0] out_tcp_res__st3;
  logic [0:0] out_tcp_cwr__st3;
  logic [0:0] out_tcp_ece__st3;
  logic [0:0] out_tcp_urg__st3;
  logic [0:0] out_tcp_ack__st3;
  logic [0:0] out_tcp_psh__st3;
  logic [0:0] out_tcp_rst__st3;
  logic [0:0] out_tcp_syn__st3;
  logic [0:0] out_tcp_fin__st3;
  logic [15:0] out_tcp_window__st3;
  logic [15:0] out_tcp_checksum__st3;
  logic [15:0] out_tcp_urgentPtr__st3;
  logic [8:0] out_std_meta_egress_spec__st3;
  logic drop__st3;

  // Pool-B (locals/meta shadow/raw hdr+std_meta reads) working
  // copies -- every stage except the first, which reads live inputs
  logic [4:0] _padding_0__st1;
  logic [0:0] direction_0__st1;
  logic [31:0] reg_pos_one_0__st1;
  logic [31:0] reg_pos_two_0__st1;
  logic [0:0] reg_val_one_0__st1;
  logic [0:0] reg_val_two_0__st1;
  logic [31:0] tmp__st1;
  logic [31:0] tmp_0__st1;
  logic [15:0] tmp_1__st1;
  logic [31:0] tmp_10__st1;
  logic [15:0] tmp_11__st1;
  logic [15:0] tmp_12__st1;
  logic [7:0] tmp_13__st1;
  logic [31:0] tmp_14__st1;
  logic [31:0] tmp_15__st1;
  logic [15:0] tmp_16__st1;
  logic [15:0] tmp_17__st1;
  logic [7:0] tmp_18__st1;
  logic [15:0] tmp_2__st1;
  logic [7:0] tmp_3__st1;
  logic [31:0] tmp_4__st1;
  logic [31:0] tmp_5__st1;
  logic [15:0] tmp_6__st1;
  logic [15:0] tmp_7__st1;
  logic [7:0] tmp_8__st1;
  logic [31:0] tmp_9__st1;
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
  logic [3:0] tcp_res__st1;
  logic [0:0] tcp_cwr__st1;
  logic [0:0] tcp_ece__st1;
  logic [0:0] tcp_urg__st1;
  logic [0:0] tcp_ack__st1;
  logic [0:0] tcp_psh__st1;
  logic [0:0] tcp_rst__st1;
  logic [0:0] tcp_syn__st1;
  logic [0:0] tcp_fin__st1;
  logic [15:0] tcp_window__st1;
  logic [15:0] tcp_checksum__st1;
  logic [15:0] tcp_urgentPtr__st1;
  logic [8:0] std_meta_egress_spec__st1;
  logic [8:0] std_meta_ingress_port__st1;
  logic [4:0] _padding_0__st2;
  logic [0:0] direction_0__st2;
  logic [31:0] reg_pos_one_0__st2;
  logic [31:0] reg_pos_two_0__st2;
  logic [0:0] reg_val_one_0__st2;
  logic [0:0] reg_val_two_0__st2;
  logic [31:0] tmp__st2;
  logic [31:0] tmp_0__st2;
  logic [15:0] tmp_1__st2;
  logic [31:0] tmp_10__st2;
  logic [15:0] tmp_11__st2;
  logic [15:0] tmp_12__st2;
  logic [7:0] tmp_13__st2;
  logic [31:0] tmp_14__st2;
  logic [31:0] tmp_15__st2;
  logic [15:0] tmp_16__st2;
  logic [15:0] tmp_17__st2;
  logic [7:0] tmp_18__st2;
  logic [15:0] tmp_2__st2;
  logic [7:0] tmp_3__st2;
  logic [31:0] tmp_4__st2;
  logic [31:0] tmp_5__st2;
  logic [15:0] tmp_6__st2;
  logic [15:0] tmp_7__st2;
  logic [7:0] tmp_8__st2;
  logic [31:0] tmp_9__st2;
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
  logic [3:0] tcp_res__st2;
  logic [0:0] tcp_cwr__st2;
  logic [0:0] tcp_ece__st2;
  logic [0:0] tcp_urg__st2;
  logic [0:0] tcp_ack__st2;
  logic [0:0] tcp_psh__st2;
  logic [0:0] tcp_rst__st2;
  logic [0:0] tcp_syn__st2;
  logic [0:0] tcp_fin__st2;
  logic [15:0] tcp_window__st2;
  logic [15:0] tcp_checksum__st2;
  logic [15:0] tcp_urgentPtr__st2;
  logic [8:0] std_meta_egress_spec__st2;
  logic [8:0] std_meta_ingress_port__st2;
  logic [4:0] _padding_0__st3;
  logic [0:0] direction_0__st3;
  logic [31:0] reg_pos_one_0__st3;
  logic [31:0] reg_pos_two_0__st3;
  logic [0:0] reg_val_one_0__st3;
  logic [0:0] reg_val_two_0__st3;
  logic [31:0] tmp__st3;
  logic [31:0] tmp_0__st3;
  logic [15:0] tmp_1__st3;
  logic [31:0] tmp_10__st3;
  logic [15:0] tmp_11__st3;
  logic [15:0] tmp_12__st3;
  logic [7:0] tmp_13__st3;
  logic [31:0] tmp_14__st3;
  logic [31:0] tmp_15__st3;
  logic [15:0] tmp_16__st3;
  logic [15:0] tmp_17__st3;
  logic [7:0] tmp_18__st3;
  logic [15:0] tmp_2__st3;
  logic [7:0] tmp_3__st3;
  logic [31:0] tmp_4__st3;
  logic [31:0] tmp_5__st3;
  logic [15:0] tmp_6__st3;
  logic [15:0] tmp_7__st3;
  logic [7:0] tmp_8__st3;
  logic [31:0] tmp_9__st3;
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
  logic [3:0] tcp_res__st3;
  logic [0:0] tcp_cwr__st3;
  logic [0:0] tcp_ece__st3;
  logic [0:0] tcp_urg__st3;
  logic [0:0] tcp_ack__st3;
  logic [0:0] tcp_psh__st3;
  logic [0:0] tcp_rst__st3;
  logic [0:0] tcp_syn__st3;
  logic [0:0] tcp_fin__st3;
  logic [15:0] tcp_window__st3;
  logic [15:0] tcp_checksum__st3;
  logic [15:0] tcp_urgentPtr__st3;
  logic [8:0] std_meta_egress_spec__st3;
  logic [8:0] std_meta_ingress_port__st3;
  logic [4:0] _padding_0__st4;
  logic [0:0] direction_0__st4;
  logic [31:0] reg_pos_one_0__st4;
  logic [31:0] reg_pos_two_0__st4;
  logic [0:0] reg_val_one_0__st4;
  logic [0:0] reg_val_two_0__st4;
  logic [31:0] tmp__st4;
  logic [31:0] tmp_0__st4;
  logic [15:0] tmp_1__st4;
  logic [31:0] tmp_10__st4;
  logic [15:0] tmp_11__st4;
  logic [15:0] tmp_12__st4;
  logic [7:0] tmp_13__st4;
  logic [31:0] tmp_14__st4;
  logic [31:0] tmp_15__st4;
  logic [15:0] tmp_16__st4;
  logic [15:0] tmp_17__st4;
  logic [7:0] tmp_18__st4;
  logic [15:0] tmp_2__st4;
  logic [7:0] tmp_3__st4;
  logic [31:0] tmp_4__st4;
  logic [31:0] tmp_5__st4;
  logic [15:0] tmp_6__st4;
  logic [15:0] tmp_7__st4;
  logic [7:0] tmp_8__st4;
  logic [31:0] tmp_9__st4;
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
  logic [3:0] tcp_res__st4;
  logic [0:0] tcp_cwr__st4;
  logic [0:0] tcp_ece__st4;
  logic [0:0] tcp_urg__st4;
  logic [0:0] tcp_ack__st4;
  logic [0:0] tcp_psh__st4;
  logic [0:0] tcp_rst__st4;
  logic [0:0] tcp_syn__st4;
  logic [0:0] tcp_fin__st4;
  logic [15:0] tcp_window__st4;
  logic [15:0] tcp_checksum__st4;
  logic [15:0] tcp_urgentPtr__st4;
  logic [8:0] std_meta_egress_spec__st4;
  logic [8:0] std_meta_ingress_port__st4;

  // bloom_filter_1: register<bit<1>>(4096)
  logic [0:0] bloom_filter_1_mem [0:4095];
  logic        bloom_filter_1_wr_en;
  logic [11:0] bloom_filter_1_wr_addr;
  logic [0:0] bloom_filter_1_wr_data;
  // bloom_filter_2: register<bit<1>>(4096)
  logic [0:0] bloom_filter_2_mem [0:4095];
  logic        bloom_filter_2_wr_en;
  logic [11:0] bloom_filter_2_wr_addr;
  logic [0:0] bloom_filter_2_wr_data;

  // Zero all register memories at simulation start
  // synthesis translate_off
  initial begin
    for (int _si = 0; _si < 4096; _si++)
      bloom_filter_1_mem[_si] = 1'b0;
    for (int _si = 0; _si < 4096; _si++)
      bloom_filter_2_mem[_si] = 1'b0;
  end
  // synthesis translate_on

  // Register read wires (isolated via assign)
  logic [0:0] bloom_filter_1_rd_reg_val_one_0;
  assign bloom_filter_1_rd_reg_val_one_0 = bloom_filter_1_mem[reg_pos_one_0__st4];
  logic [0:0] bloom_filter_2_rd_reg_val_two_0;
  assign bloom_filter_2_rd_reg_val_two_0 = bloom_filter_2_mem[reg_pos_two_0__st4];

  // Table lookup result wires
  logic        ipv4_lpm_hit;
  logic [1:0] ipv4_lpm_act_id;
  logic [47:0] ipv4_lpm_p_dstAddr;
  logic [8:0] ipv4_lpm_p_port;
  logic        check_ports_hit;
  logic [0:0] check_ports_act_id;
  logic [0:0] check_ports_p_dir;

  // Table module instantiations
  ipv4_lpm_table #(.DEPTH(256)) u_ipv4_lpm (
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

  check_ports_table #(.DEPTH(1024)) u_check_ports (
    .clk    (clk),
    .rst_n  (rst_n),
    .lkp_ingress_port    (std_meta_ingress_port),
    .lkp_egress_spec    (std_meta_egress_spec),
    .hit       (check_ports_hit),
    .action_id (check_ports_act_id),
    .p_dir  (check_ports_p_dir),
    .cp_wr_en  (check_ports_cp_wr_en),
    .cp_wr_idx (check_ports_cp_wr_idx),
    .cp_wr_key_ingress_port (check_ports_cp_wr_key_ingress_port),
    .cp_wr_key_egress_spec (check_ports_cp_wr_key_egress_spec),
    .cp_wr_action (check_ports_cp_wr_action),
    .cp_wr_p_dir (check_ports_cp_wr_p_dir)
  );

  // Table hit outputs
  assign ipv4_lpm_hit_out = ipv4_lpm_hit;
  assign check_ports_hit_out = check_ports_hit;

  // ---- Pipeline stage 0 (combinational, feeds the first exact-match table boundary) ----
  always_comb begin
    drop__st0 = 0;
    _padding_0 = 5'b0;
    direction_0 = 1'b0;
    reg_pos_one_0 = 32'b0;
    reg_pos_two_0 = 32'b0;
    reg_val_one_0 = 1'b0;
    reg_val_two_0 = 1'b0;
    tmp = 32'b0;
    tmp_0 = 32'b0;
    tmp_1 = 16'b0;
    tmp_10 = 32'b0;
    tmp_11 = 16'b0;
    tmp_12 = 16'b0;
    tmp_13 = 8'b0;
    tmp_14 = 32'b0;
    tmp_15 = 32'b0;
    tmp_16 = 16'b0;
    tmp_17 = 16'b0;
    tmp_18 = 8'b0;
    tmp_2 = 16'b0;
    tmp_3 = 8'b0;
    tmp_4 = 32'b0;
    tmp_5 = 32'b0;
    tmp_6 = 16'b0;
    tmp_7 = 16'b0;
    tmp_8 = 8'b0;
    tmp_9 = 32'b0;

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
    out_tcp_cwr__st0 = tcp_cwr;
    out_tcp_ece__st0 = tcp_ece;
    out_tcp_urg__st0 = tcp_urg;
    out_tcp_ack__st0 = tcp_ack;
    out_tcp_psh__st0 = tcp_psh;
    out_tcp_rst__st0 = tcp_rst;
    out_tcp_syn__st0 = tcp_syn;
    out_tcp_fin__st0 = tcp_fin;
    out_tcp_window__st0 = tcp_window;
    out_tcp_checksum__st0 = tcp_checksum;
    out_tcp_urgentPtr__st0 = tcp_urgentPtr;

    // apply block (stage 0 of 4)
    if (ipv4_valid) begin
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
      direction_0_s1 <= direction_0;
      reg_pos_one_0_s1 <= reg_pos_one_0;
      reg_pos_two_0_s1 <= reg_pos_two_0;
      reg_val_one_0_s1 <= reg_val_one_0;
      reg_val_two_0_s1 <= reg_val_two_0;
      tmp_s1 <= tmp;
      tmp_0_s1 <= tmp_0;
      tmp_1_s1 <= tmp_1;
      tmp_10_s1 <= tmp_10;
      tmp_11_s1 <= tmp_11;
      tmp_12_s1 <= tmp_12;
      tmp_13_s1 <= tmp_13;
      tmp_14_s1 <= tmp_14;
      tmp_15_s1 <= tmp_15;
      tmp_16_s1 <= tmp_16;
      tmp_17_s1 <= tmp_17;
      tmp_18_s1 <= tmp_18;
      tmp_2_s1 <= tmp_2;
      tmp_3_s1 <= tmp_3;
      tmp_4_s1 <= tmp_4;
      tmp_5_s1 <= tmp_5;
      tmp_6_s1 <= tmp_6;
      tmp_7_s1 <= tmp_7;
      tmp_8_s1 <= tmp_8;
      tmp_9_s1 <= tmp_9;
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
      out_tcp_cwr_s1 <= out_tcp_cwr__st0;
      tcp_cwr_s1 <= tcp_cwr;
      out_tcp_ece_s1 <= out_tcp_ece__st0;
      tcp_ece_s1 <= tcp_ece;
      out_tcp_urg_s1 <= out_tcp_urg__st0;
      tcp_urg_s1 <= tcp_urg;
      out_tcp_ack_s1 <= out_tcp_ack__st0;
      tcp_ack_s1 <= tcp_ack;
      out_tcp_psh_s1 <= out_tcp_psh__st0;
      tcp_psh_s1 <= tcp_psh;
      out_tcp_rst_s1 <= out_tcp_rst__st0;
      tcp_rst_s1 <= tcp_rst;
      out_tcp_syn_s1 <= out_tcp_syn__st0;
      tcp_syn_s1 <= tcp_syn;
      out_tcp_fin_s1 <= out_tcp_fin__st0;
      tcp_fin_s1 <= tcp_fin;
      out_tcp_window_s1 <= out_tcp_window__st0;
      tcp_window_s1 <= tcp_window;
      out_tcp_checksum_s1 <= out_tcp_checksum__st0;
      tcp_checksum_s1 <= tcp_checksum;
      out_tcp_urgentPtr_s1 <= out_tcp_urgentPtr__st0;
      tcp_urgentPtr_s1 <= tcp_urgentPtr;
      out_std_meta_egress_spec_s1 <= out_std_meta_egress_spec__st0;
      std_meta_egress_spec_s1 <= std_meta_egress_spec;
      std_meta_ingress_port_s1 <= std_meta_ingress_port;
      __stage_cond_0_r <= (ipv4_valid);
    end
  end

  // ---- Pipeline stage 1 (registered 1 cycle(s) after stage 0) ----
  always_comb begin
    drop__st1 = drop_s1;
    _padding_0__st1 = _padding_0_s1;
    direction_0__st1 = direction_0_s1;
    reg_pos_one_0__st1 = reg_pos_one_0_s1;
    reg_pos_two_0__st1 = reg_pos_two_0_s1;
    reg_val_one_0__st1 = reg_val_one_0_s1;
    reg_val_two_0__st1 = reg_val_two_0_s1;
    tmp__st1 = tmp_s1;
    tmp_0__st1 = tmp_0_s1;
    tmp_1__st1 = tmp_1_s1;
    tmp_10__st1 = tmp_10_s1;
    tmp_11__st1 = tmp_11_s1;
    tmp_12__st1 = tmp_12_s1;
    tmp_13__st1 = tmp_13_s1;
    tmp_14__st1 = tmp_14_s1;
    tmp_15__st1 = tmp_15_s1;
    tmp_16__st1 = tmp_16_s1;
    tmp_17__st1 = tmp_17_s1;
    tmp_18__st1 = tmp_18_s1;
    tmp_2__st1 = tmp_2_s1;
    tmp_3__st1 = tmp_3_s1;
    tmp_4__st1 = tmp_4_s1;
    tmp_5__st1 = tmp_5_s1;
    tmp_6__st1 = tmp_6_s1;
    tmp_7__st1 = tmp_7_s1;
    tmp_8__st1 = tmp_8_s1;
    tmp_9__st1 = tmp_9_s1;
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
    out_tcp_cwr__st1 = out_tcp_cwr_s1;
    tcp_cwr__st1 = tcp_cwr_s1;
    out_tcp_ece__st1 = out_tcp_ece_s1;
    tcp_ece__st1 = tcp_ece_s1;
    out_tcp_urg__st1 = out_tcp_urg_s1;
    tcp_urg__st1 = tcp_urg_s1;
    out_tcp_ack__st1 = out_tcp_ack_s1;
    tcp_ack__st1 = tcp_ack_s1;
    out_tcp_psh__st1 = out_tcp_psh_s1;
    tcp_psh__st1 = tcp_psh_s1;
    out_tcp_rst__st1 = out_tcp_rst_s1;
    tcp_rst__st1 = tcp_rst_s1;
    out_tcp_syn__st1 = out_tcp_syn_s1;
    tcp_syn__st1 = tcp_syn_s1;
    out_tcp_fin__st1 = out_tcp_fin_s1;
    tcp_fin__st1 = tcp_fin_s1;
    out_tcp_window__st1 = out_tcp_window_s1;
    tcp_window__st1 = tcp_window_s1;
    out_tcp_checksum__st1 = out_tcp_checksum_s1;
    tcp_checksum__st1 = tcp_checksum_s1;
    out_tcp_urgentPtr__st1 = out_tcp_urgentPtr_s1;
    tcp_urgentPtr__st1 = tcp_urgentPtr_s1;
    out_std_meta_egress_spec__st1 = out_std_meta_egress_spec_s1;
    std_meta_egress_spec__st1 = std_meta_egress_spec_s1;
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
      direction_0_s2 <= direction_0__st1;
      reg_pos_one_0_s2 <= reg_pos_one_0__st1;
      reg_pos_two_0_s2 <= reg_pos_two_0__st1;
      reg_val_one_0_s2 <= reg_val_one_0__st1;
      reg_val_two_0_s2 <= reg_val_two_0__st1;
      tmp_s2 <= tmp__st1;
      tmp_0_s2 <= tmp_0__st1;
      tmp_1_s2 <= tmp_1__st1;
      tmp_10_s2 <= tmp_10__st1;
      tmp_11_s2 <= tmp_11__st1;
      tmp_12_s2 <= tmp_12__st1;
      tmp_13_s2 <= tmp_13__st1;
      tmp_14_s2 <= tmp_14__st1;
      tmp_15_s2 <= tmp_15__st1;
      tmp_16_s2 <= tmp_16__st1;
      tmp_17_s2 <= tmp_17__st1;
      tmp_18_s2 <= tmp_18__st1;
      tmp_2_s2 <= tmp_2__st1;
      tmp_3_s2 <= tmp_3__st1;
      tmp_4_s2 <= tmp_4__st1;
      tmp_5_s2 <= tmp_5__st1;
      tmp_6_s2 <= tmp_6__st1;
      tmp_7_s2 <= tmp_7__st1;
      tmp_8_s2 <= tmp_8__st1;
      tmp_9_s2 <= tmp_9__st1;
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
      out_tcp_cwr_s2 <= out_tcp_cwr__st1;
      tcp_cwr_s2 <= tcp_cwr__st1;
      out_tcp_ece_s2 <= out_tcp_ece__st1;
      tcp_ece_s2 <= tcp_ece__st1;
      out_tcp_urg_s2 <= out_tcp_urg__st1;
      tcp_urg_s2 <= tcp_urg__st1;
      out_tcp_ack_s2 <= out_tcp_ack__st1;
      tcp_ack_s2 <= tcp_ack__st1;
      out_tcp_psh_s2 <= out_tcp_psh__st1;
      tcp_psh_s2 <= tcp_psh__st1;
      out_tcp_rst_s2 <= out_tcp_rst__st1;
      tcp_rst_s2 <= tcp_rst__st1;
      out_tcp_syn_s2 <= out_tcp_syn__st1;
      tcp_syn_s2 <= tcp_syn__st1;
      out_tcp_fin_s2 <= out_tcp_fin__st1;
      tcp_fin_s2 <= tcp_fin__st1;
      out_tcp_window_s2 <= out_tcp_window__st1;
      tcp_window_s2 <= tcp_window__st1;
      out_tcp_checksum_s2 <= out_tcp_checksum__st1;
      tcp_checksum_s2 <= tcp_checksum__st1;
      out_tcp_urgentPtr_s2 <= out_tcp_urgentPtr__st1;
      tcp_urgentPtr_s2 <= tcp_urgentPtr__st1;
      out_std_meta_egress_spec_s2 <= out_std_meta_egress_spec__st1;
      std_meta_egress_spec_s2 <= std_meta_egress_spec__st1;
      std_meta_ingress_port_s2 <= std_meta_ingress_port__st1;
    end
  end

  // ---- Pipeline stage 2 (registered 2 cycle(s) after stage 0) ----
  always_comb begin
    drop__st2 = drop_s2;
    _padding_0__st2 = _padding_0_s2;
    direction_0__st2 = direction_0_s2;
    reg_pos_one_0__st2 = reg_pos_one_0_s2;
    reg_pos_two_0__st2 = reg_pos_two_0_s2;
    reg_val_one_0__st2 = reg_val_one_0_s2;
    reg_val_two_0__st2 = reg_val_two_0_s2;
    tmp__st2 = tmp_s2;
    tmp_0__st2 = tmp_0_s2;
    tmp_1__st2 = tmp_1_s2;
    tmp_10__st2 = tmp_10_s2;
    tmp_11__st2 = tmp_11_s2;
    tmp_12__st2 = tmp_12_s2;
    tmp_13__st2 = tmp_13_s2;
    tmp_14__st2 = tmp_14_s2;
    tmp_15__st2 = tmp_15_s2;
    tmp_16__st2 = tmp_16_s2;
    tmp_17__st2 = tmp_17_s2;
    tmp_18__st2 = tmp_18_s2;
    tmp_2__st2 = tmp_2_s2;
    tmp_3__st2 = tmp_3_s2;
    tmp_4__st2 = tmp_4_s2;
    tmp_5__st2 = tmp_5_s2;
    tmp_6__st2 = tmp_6_s2;
    tmp_7__st2 = tmp_7_s2;
    tmp_8__st2 = tmp_8_s2;
    tmp_9__st2 = tmp_9_s2;
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
    out_tcp_cwr__st2 = out_tcp_cwr_s2;
    tcp_cwr__st2 = tcp_cwr_s2;
    out_tcp_ece__st2 = out_tcp_ece_s2;
    tcp_ece__st2 = tcp_ece_s2;
    out_tcp_urg__st2 = out_tcp_urg_s2;
    tcp_urg__st2 = tcp_urg_s2;
    out_tcp_ack__st2 = out_tcp_ack_s2;
    tcp_ack__st2 = tcp_ack_s2;
    out_tcp_psh__st2 = out_tcp_psh_s2;
    tcp_psh__st2 = tcp_psh_s2;
    out_tcp_rst__st2 = out_tcp_rst_s2;
    tcp_rst__st2 = tcp_rst_s2;
    out_tcp_syn__st2 = out_tcp_syn_s2;
    tcp_syn__st2 = tcp_syn_s2;
    out_tcp_fin__st2 = out_tcp_fin_s2;
    tcp_fin__st2 = tcp_fin_s2;
    out_tcp_window__st2 = out_tcp_window_s2;
    tcp_window__st2 = tcp_window_s2;
    out_tcp_checksum__st2 = out_tcp_checksum_s2;
    tcp_checksum__st2 = tcp_checksum_s2;
    out_tcp_urgentPtr__st2 = out_tcp_urgentPtr_s2;
    tcp_urgentPtr__st2 = tcp_urgentPtr_s2;
    out_std_meta_egress_spec__st2 = out_std_meta_egress_spec_s2;
    std_meta_egress_spec__st2 = std_meta_egress_spec_s2;
    std_meta_ingress_port__st2 = std_meta_ingress_port_s2;

    // apply block (stage 2 of 4)
    if (__stage_cond_0_r) begin
      // ipv4_lpm.apply()
      if (ipv4_lpm_hit) begin
        unique case (ipv4_lpm_act_id)
          2'd0: ; // NoAction
          2'd1: begin // ipv4_forward
            out_std_meta_egress_spec__st2 = ipv4_lpm_p_port;
            out_ethernet_srcAddr__st2 = ethernet_dstAddr__st2;
            out_ethernet_dstAddr__st2 = ipv4_lpm_p_dstAddr;
            out_ipv4_ttl__st2 = ((ipv4_ttl__st2 + 'hFF) & 'hFF);
          end
          2'd2: begin // drop__st2
            drop__st2 = 1;
          end
          default: ; // default = drop__st2
        endcase
      end else begin // drop__st2 on miss
        drop__st2 = 1;
      end
      if (tcp_valid__st2) begin
        direction_0__st2 = 'h00;
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
      direction_0_s3 <= direction_0__st2;
      reg_pos_one_0_s3 <= reg_pos_one_0__st2;
      reg_pos_two_0_s3 <= reg_pos_two_0__st2;
      reg_val_one_0_s3 <= reg_val_one_0__st2;
      reg_val_two_0_s3 <= reg_val_two_0__st2;
      tmp_s3 <= tmp__st2;
      tmp_0_s3 <= tmp_0__st2;
      tmp_1_s3 <= tmp_1__st2;
      tmp_10_s3 <= tmp_10__st2;
      tmp_11_s3 <= tmp_11__st2;
      tmp_12_s3 <= tmp_12__st2;
      tmp_13_s3 <= tmp_13__st2;
      tmp_14_s3 <= tmp_14__st2;
      tmp_15_s3 <= tmp_15__st2;
      tmp_16_s3 <= tmp_16__st2;
      tmp_17_s3 <= tmp_17__st2;
      tmp_18_s3 <= tmp_18__st2;
      tmp_2_s3 <= tmp_2__st2;
      tmp_3_s3 <= tmp_3__st2;
      tmp_4_s3 <= tmp_4__st2;
      tmp_5_s3 <= tmp_5__st2;
      tmp_6_s3 <= tmp_6__st2;
      tmp_7_s3 <= tmp_7__st2;
      tmp_8_s3 <= tmp_8__st2;
      tmp_9_s3 <= tmp_9__st2;
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
      out_tcp_cwr_s3 <= out_tcp_cwr__st2;
      tcp_cwr_s3 <= tcp_cwr__st2;
      out_tcp_ece_s3 <= out_tcp_ece__st2;
      tcp_ece_s3 <= tcp_ece__st2;
      out_tcp_urg_s3 <= out_tcp_urg__st2;
      tcp_urg_s3 <= tcp_urg__st2;
      out_tcp_ack_s3 <= out_tcp_ack__st2;
      tcp_ack_s3 <= tcp_ack__st2;
      out_tcp_psh_s3 <= out_tcp_psh__st2;
      tcp_psh_s3 <= tcp_psh__st2;
      out_tcp_rst_s3 <= out_tcp_rst__st2;
      tcp_rst_s3 <= tcp_rst__st2;
      out_tcp_syn_s3 <= out_tcp_syn__st2;
      tcp_syn_s3 <= tcp_syn__st2;
      out_tcp_fin_s3 <= out_tcp_fin__st2;
      tcp_fin_s3 <= tcp_fin__st2;
      out_tcp_window_s3 <= out_tcp_window__st2;
      tcp_window_s3 <= tcp_window__st2;
      out_tcp_checksum_s3 <= out_tcp_checksum__st2;
      tcp_checksum_s3 <= tcp_checksum__st2;
      out_tcp_urgentPtr_s3 <= out_tcp_urgentPtr__st2;
      tcp_urgentPtr_s3 <= tcp_urgentPtr__st2;
      out_std_meta_egress_spec_s3 <= out_std_meta_egress_spec__st2;
      std_meta_egress_spec_s3 <= std_meta_egress_spec__st2;
      std_meta_ingress_port_s3 <= std_meta_ingress_port__st2;
      __stage_cond_2_r <= (__stage_cond_0_r);
      __stage_cond_1_r <= (tcp_valid__st2);
    end
  end

  // ---- Pipeline stage 3 (registered 3 cycle(s) after stage 0) ----
  always_comb begin
    drop__st3 = drop_s3;
    _padding_0__st3 = _padding_0_s3;
    direction_0__st3 = direction_0_s3;
    reg_pos_one_0__st3 = reg_pos_one_0_s3;
    reg_pos_two_0__st3 = reg_pos_two_0_s3;
    reg_val_one_0__st3 = reg_val_one_0_s3;
    reg_val_two_0__st3 = reg_val_two_0_s3;
    tmp__st3 = tmp_s3;
    tmp_0__st3 = tmp_0_s3;
    tmp_1__st3 = tmp_1_s3;
    tmp_10__st3 = tmp_10_s3;
    tmp_11__st3 = tmp_11_s3;
    tmp_12__st3 = tmp_12_s3;
    tmp_13__st3 = tmp_13_s3;
    tmp_14__st3 = tmp_14_s3;
    tmp_15__st3 = tmp_15_s3;
    tmp_16__st3 = tmp_16_s3;
    tmp_17__st3 = tmp_17_s3;
    tmp_18__st3 = tmp_18_s3;
    tmp_2__st3 = tmp_2_s3;
    tmp_3__st3 = tmp_3_s3;
    tmp_4__st3 = tmp_4_s3;
    tmp_5__st3 = tmp_5_s3;
    tmp_6__st3 = tmp_6_s3;
    tmp_7__st3 = tmp_7_s3;
    tmp_8__st3 = tmp_8_s3;
    tmp_9__st3 = tmp_9_s3;
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
    out_tcp_cwr__st3 = out_tcp_cwr_s3;
    tcp_cwr__st3 = tcp_cwr_s3;
    out_tcp_ece__st3 = out_tcp_ece_s3;
    tcp_ece__st3 = tcp_ece_s3;
    out_tcp_urg__st3 = out_tcp_urg_s3;
    tcp_urg__st3 = tcp_urg_s3;
    out_tcp_ack__st3 = out_tcp_ack_s3;
    tcp_ack__st3 = tcp_ack_s3;
    out_tcp_psh__st3 = out_tcp_psh_s3;
    tcp_psh__st3 = tcp_psh_s3;
    out_tcp_rst__st3 = out_tcp_rst_s3;
    tcp_rst__st3 = tcp_rst_s3;
    out_tcp_syn__st3 = out_tcp_syn_s3;
    tcp_syn__st3 = tcp_syn_s3;
    out_tcp_fin__st3 = out_tcp_fin_s3;
    tcp_fin__st3 = tcp_fin_s3;
    out_tcp_window__st3 = out_tcp_window_s3;
    tcp_window__st3 = tcp_window_s3;
    out_tcp_checksum__st3 = out_tcp_checksum_s3;
    tcp_checksum__st3 = tcp_checksum_s3;
    out_tcp_urgentPtr__st3 = out_tcp_urgentPtr_s3;
    tcp_urgentPtr__st3 = tcp_urgentPtr_s3;
    out_std_meta_egress_spec__st3 = out_std_meta_egress_spec_s3;
    std_meta_egress_spec__st3 = std_meta_egress_spec_s3;
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
      direction_0_s4 <= direction_0__st3;
      reg_pos_one_0_s4 <= reg_pos_one_0__st3;
      reg_pos_two_0_s4 <= reg_pos_two_0__st3;
      reg_val_one_0_s4 <= reg_val_one_0__st3;
      reg_val_two_0_s4 <= reg_val_two_0__st3;
      tmp_s4 <= tmp__st3;
      tmp_0_s4 <= tmp_0__st3;
      tmp_1_s4 <= tmp_1__st3;
      tmp_10_s4 <= tmp_10__st3;
      tmp_11_s4 <= tmp_11__st3;
      tmp_12_s4 <= tmp_12__st3;
      tmp_13_s4 <= tmp_13__st3;
      tmp_14_s4 <= tmp_14__st3;
      tmp_15_s4 <= tmp_15__st3;
      tmp_16_s4 <= tmp_16__st3;
      tmp_17_s4 <= tmp_17__st3;
      tmp_18_s4 <= tmp_18__st3;
      tmp_2_s4 <= tmp_2__st3;
      tmp_3_s4 <= tmp_3__st3;
      tmp_4_s4 <= tmp_4__st3;
      tmp_5_s4 <= tmp_5__st3;
      tmp_6_s4 <= tmp_6__st3;
      tmp_7_s4 <= tmp_7__st3;
      tmp_8_s4 <= tmp_8__st3;
      tmp_9_s4 <= tmp_9__st3;
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
      out_tcp_cwr_s4 <= out_tcp_cwr__st3;
      tcp_cwr_s4 <= tcp_cwr__st3;
      out_tcp_ece_s4 <= out_tcp_ece__st3;
      tcp_ece_s4 <= tcp_ece__st3;
      out_tcp_urg_s4 <= out_tcp_urg__st3;
      tcp_urg_s4 <= tcp_urg__st3;
      out_tcp_ack_s4 <= out_tcp_ack__st3;
      tcp_ack_s4 <= tcp_ack__st3;
      out_tcp_psh_s4 <= out_tcp_psh__st3;
      tcp_psh_s4 <= tcp_psh__st3;
      out_tcp_rst_s4 <= out_tcp_rst__st3;
      tcp_rst_s4 <= tcp_rst__st3;
      out_tcp_syn_s4 <= out_tcp_syn__st3;
      tcp_syn_s4 <= tcp_syn__st3;
      out_tcp_fin_s4 <= out_tcp_fin__st3;
      tcp_fin_s4 <= tcp_fin__st3;
      out_tcp_window_s4 <= out_tcp_window__st3;
      tcp_window_s4 <= tcp_window__st3;
      out_tcp_checksum_s4 <= out_tcp_checksum__st3;
      tcp_checksum_s4 <= tcp_checksum__st3;
      out_tcp_urgentPtr_s4 <= out_tcp_urgentPtr__st3;
      tcp_urgentPtr_s4 <= tcp_urgentPtr__st3;
      out_std_meta_egress_spec_s4 <= out_std_meta_egress_spec__st3;
      std_meta_egress_spec_s4 <= std_meta_egress_spec__st3;
      std_meta_ingress_port_s4 <= std_meta_ingress_port__st3;
    end
  end

  // ---- Pipeline stage 4 (registered 4 cycle(s) after stage 0) ----
  always_comb begin
    drop = drop_s4;
    _padding_0__st4 = _padding_0_s4;
    direction_0__st4 = direction_0_s4;
    reg_pos_one_0__st4 = reg_pos_one_0_s4;
    reg_pos_two_0__st4 = reg_pos_two_0_s4;
    reg_val_one_0__st4 = reg_val_one_0_s4;
    reg_val_two_0__st4 = reg_val_two_0_s4;
    tmp__st4 = tmp_s4;
    tmp_0__st4 = tmp_0_s4;
    tmp_1__st4 = tmp_1_s4;
    tmp_10__st4 = tmp_10_s4;
    tmp_11__st4 = tmp_11_s4;
    tmp_12__st4 = tmp_12_s4;
    tmp_13__st4 = tmp_13_s4;
    tmp_14__st4 = tmp_14_s4;
    tmp_15__st4 = tmp_15_s4;
    tmp_16__st4 = tmp_16_s4;
    tmp_17__st4 = tmp_17_s4;
    tmp_18__st4 = tmp_18_s4;
    tmp_2__st4 = tmp_2_s4;
    tmp_3__st4 = tmp_3_s4;
    tmp_4__st4 = tmp_4_s4;
    tmp_5__st4 = tmp_5_s4;
    tmp_6__st4 = tmp_6_s4;
    tmp_7__st4 = tmp_7_s4;
    tmp_8__st4 = tmp_8_s4;
    tmp_9__st4 = tmp_9_s4;
    bloom_filter_1_wr_en   = 1'b0;
    bloom_filter_1_wr_addr = '0;
    bloom_filter_1_wr_data = '0;
    bloom_filter_2_wr_en   = 1'b0;
    bloom_filter_2_wr_addr = '0;
    bloom_filter_2_wr_data = '0;
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
    out_tcp_cwr = out_tcp_cwr_s4;
    tcp_cwr__st4 = tcp_cwr_s4;
    out_tcp_ece = out_tcp_ece_s4;
    tcp_ece__st4 = tcp_ece_s4;
    out_tcp_urg = out_tcp_urg_s4;
    tcp_urg__st4 = tcp_urg_s4;
    out_tcp_ack = out_tcp_ack_s4;
    tcp_ack__st4 = tcp_ack_s4;
    out_tcp_psh = out_tcp_psh_s4;
    tcp_psh__st4 = tcp_psh_s4;
    out_tcp_rst = out_tcp_rst_s4;
    tcp_rst__st4 = tcp_rst_s4;
    out_tcp_syn = out_tcp_syn_s4;
    tcp_syn__st4 = tcp_syn_s4;
    out_tcp_fin = out_tcp_fin_s4;
    tcp_fin__st4 = tcp_fin_s4;
    out_tcp_window = out_tcp_window_s4;
    tcp_window__st4 = tcp_window_s4;
    out_tcp_checksum = out_tcp_checksum_s4;
    tcp_checksum__st4 = tcp_checksum_s4;
    out_tcp_urgentPtr = out_tcp_urgentPtr_s4;
    tcp_urgentPtr__st4 = tcp_urgentPtr_s4;
    out_std_meta_egress_spec = out_std_meta_egress_spec_s4;
    std_meta_egress_spec__st4 = std_meta_egress_spec_s4;
    std_meta_ingress_port__st4 = std_meta_ingress_port_s4;

    // apply block (stage 4 of 4)
    if (__stage_cond_2_r) begin
      if (__stage_cond_1_r) begin
        // check_ports.apply()
        if (check_ports_hit) begin
          unique case (check_ports_act_id)
            1'd0: ; // NoAction
            1'd1: begin // set_direction
              direction_0__st4 = check_ports_p_dir;
            end
            default: ; // default = NoAction
          endcase
        end
        if ((direction_0__st4 == 'h00)) begin
          tmp_9__st4 = ipv4_dstAddr__st4;
          tmp_10__st4 = ipv4_srcAddr__st4;
          tmp_11__st4 = tcp_dstPort__st4;
          tmp_12__st4 = tcp_srcPort__st4;
          tmp_13__st4 = ipv4_protocol__st4;
          // hash() stub — XOR-based behavioral approximation
          reg_pos_one_0__st4 = (tmp_9__st4 ^ tmp_10__st4 ^ tmp_11__st4 ^ tmp_12__st4 ^ tmp_13__st4) & 12'hFFF;
          tmp_14__st4 = ipv4_dstAddr__st4;
          tmp_15__st4 = ipv4_srcAddr__st4;
          tmp_16__st4 = tcp_dstPort__st4;
          tmp_17__st4 = tcp_srcPort__st4;
          tmp_18__st4 = ipv4_protocol__st4;
          // hash() stub — XOR-based behavioral approximation
          reg_pos_two_0__st4 = (tmp_14__st4 ^ tmp_15__st4 ^ tmp_16__st4 ^ tmp_17__st4 ^ tmp_18__st4) & 12'hFFF;
        end
        else begin
          tmp_9__st4 = ipv4_dstAddr__st4;
          tmp_10__st4 = ipv4_srcAddr__st4;
          tmp_11__st4 = tcp_dstPort__st4;
          tmp_12__st4 = tcp_srcPort__st4;
          tmp_13__st4 = ipv4_protocol__st4;
          // hash() stub — XOR-based behavioral approximation
          reg_pos_one_0__st4 = (tmp_9__st4 ^ tmp_10__st4 ^ tmp_11__st4 ^ tmp_12__st4 ^ tmp_13__st4) & 12'hFFF;
          tmp_14__st4 = ipv4_dstAddr__st4;
          tmp_15__st4 = ipv4_srcAddr__st4;
          tmp_16__st4 = tcp_dstPort__st4;
          tmp_17__st4 = tcp_srcPort__st4;
          tmp_18__st4 = ipv4_protocol__st4;
          // hash() stub — XOR-based behavioral approximation
          reg_pos_two_0__st4 = (tmp_14__st4 ^ tmp_15__st4 ^ tmp_16__st4 ^ tmp_17__st4 ^ tmp_18__st4) & 12'hFFF;
        end
        if ((direction_0__st4 == 'h00)) begin
          if ((tcp_syn__st4 == 'h01)) begin
            bloom_filter_1_wr_en   = 1'b1;
            bloom_filter_1_wr_addr = reg_pos_one_0__st4;
            bloom_filter_1_wr_data = 'h01;
            bloom_filter_2_wr_en   = 1'b1;
            bloom_filter_2_wr_addr = reg_pos_two_0__st4;
            bloom_filter_2_wr_data = 'h01;
          end
        end
        else begin
          if ((direction_0__st4 == 'h01)) begin
            reg_val_one_0__st4 = bloom_filter_1_rd_reg_val_one_0;
            reg_val_two_0__st4 = bloom_filter_2_rd_reg_val_two_0;
            if (((reg_val_one_0__st4 != 'h01) || (reg_val_two_0__st4 != 'h01))) begin
              drop = 1;
            end
          end
        end
      end
    end

    // update_checksum() writes -- final stage only,
    // needs the packet's fully-resolved header state
    if (ipv4_valid__st4) out_ipv4_hdrChecksum = chk0_value;
  end

  // Register write-back (initialized via initial block above)
  always_ff @(posedge clk) begin
    if (bloom_filter_1_wr_en)
      bloom_filter_1_mem[bloom_filter_1_wr_addr] <= bloom_filter_1_wr_data;
  end
  always_ff @(posedge clk) begin
    if (bloom_filter_2_wr_en)
      bloom_filter_2_mem[bloom_filter_2_wr_addr] <= bloom_filter_2_wr_data;
  end

  always_ff @(posedge clk) begin
    if (!rst_n) valid_out <= 0;
    else        valid_out <= valid_s4;
  end

endmodule
