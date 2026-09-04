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
  input  logic [8:0] meta_egress_port,

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

  // Control-plane write ports for table instances
  input  logic        ecmp_group_cp_wr_en,
  input  logic [5:0] ecmp_group_cp_wr_idx,
  input  logic [31:0] ecmp_group_cp_wr_key_dstAddr,
  input  logic [5:0] ecmp_group_cp_wr_pfx_len,
  input  logic [1:0] ecmp_group_cp_wr_action,
  input  logic [13:0] ecmp_group_cp_wr_p_ecmp_base,
  input  logic [15:0] ecmp_group_cp_wr_p_ecmp_mask,
  input  logic        ecmp_nhop_cp_wr_en,
  input  logic [3:0] ecmp_nhop_cp_wr_idx,
  input  logic [13:0] ecmp_nhop_cp_wr_key_ecmp_select,
  input  logic [1:0] ecmp_nhop_cp_wr_action,
  input  logic [47:0] ecmp_nhop_cp_wr_p_nhop_dmac,
  input  logic [31:0] ecmp_nhop_cp_wr_p_nhop_ipv4,
  input  logic [8:0] ecmp_nhop_cp_wr_p_port,
  input  logic        send_frame_cp_wr_en,
  input  logic [3:0] send_frame_cp_wr_idx,
  input  logic [8:0] send_frame_cp_wr_key_egress_port,
  input  logic [1:0] send_frame_cp_wr_action,
  input  logic [47:0] send_frame_cp_wr_p_smac,

  // Table hit outputs
  output logic        ecmp_group_hit_out,
  output logic        ecmp_nhop_hit_out,
  output logic        send_frame_hit_out,

  // Control-plane query/delete ports (plain exact-match tables)
  input  logic        ecmp_nhop_cp_query_en,
  input  logic        ecmp_nhop_cp_query_del,
  input  logic [13:0] ecmp_nhop_cp_query_key_ecmp_select,
  output logic        ecmp_nhop_cp_query_busy,
  output logic        ecmp_nhop_cp_query_hit,
  output logic [1:0] ecmp_nhop_cp_query_action_id,
  output logic [47:0] ecmp_nhop_cp_query_p_nhop_dmac,
  output logic [31:0] ecmp_nhop_cp_query_p_nhop_ipv4,
  output logic [8:0] ecmp_nhop_cp_query_p_port,
  input  logic        send_frame_cp_query_en,
  input  logic        send_frame_cp_query_del,
  input  logic [8:0] send_frame_cp_query_key_egress_port,
  output logic        send_frame_cp_query_busy,
  output logic        send_frame_cp_query_hit,
  output logic [1:0] send_frame_cp_query_action_id,
  output logic [47:0] send_frame_cp_query_p_smac,

  output logic        valid_out,
  output logic        drop
);

  logic [15:0] ecmp_hash_val;

  // Metadata shadow locals (writable copies of metadata inputs)
  logic [13:0] meta_ecmp_select_w;
  logic [8:0] meta_egress_port_w;

  // ecmp_hash: Checksum<H>(HashAlgorithm_t.CRC16) over 104 bits -> 16 bits
  function automatic logic [15:0] ecmp_hash_hash(input logic [103:0] d);
    ecmp_hash_hash = {(^(d & 104'hD53FF3DFFD0FFFD7FFF3FFFDFF)), (^(d & 104'hEA9FF9EFFE87FFEBFFF9FFFE7F)), (^(d & 104'h20F00FA802CC0022000F8002C0)), (^(d & 104'h10F80754016600118007400160)), (^(d & 104'h08FC03AA00338008C003A00030)), (^(d & 104'h04FE015580194004E001500018)), (^(d & 104'h02FF802AC00C2002F00028000C)), (^(d & 104'h817F4015600610017800140006)), (^(d & 104'hC03FA00A300388003C000A0003)), (^(d & 104'hE01F5005980144001E00058001)), (^(d & 104'hF00FA802CC0022000F8002C000)), (^(d & 104'hF8075401660011800740016000)), (^(d & 104'hFC03AA00338008C003A0003000)), (^(d & 104'hFE015580194004E00150001800)), (^(d & 104'hFF802AC00C2002F00028000C00)), (^(d & 104'hAA7FE6BFFB1FFEAFFFE7FFFBFF))};
  endfunction

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
  logic [8:0] meta_egress_port_w_s1;
  logic [15:0] ecmp_hash_val_s1;
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
  logic [8:0] meta_egress_port_w_s2;
  logic [15:0] ecmp_hash_val_s2;
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
  logic [8:0] meta_egress_port_w_s3;
  logic [15:0] ecmp_hash_val_s3;
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
  logic [8:0] meta_egress_port_w_s4;
  logic [15:0] ecmp_hash_val_s4;
  logic drop_s4;
  logic valid_s5;
  logic out_ethernet_valid_s5;
  logic ethernet_valid_s5;
  logic out_ipv4_valid_s5;
  logic ipv4_valid_s5;
  logic out_tcp_valid_s5;
  logic tcp_valid_s5;
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
  logic [2:0] out_tcp_res_s5;
  logic [2:0] tcp_res_s5;
  logic [2:0] out_tcp_ecn_s5;
  logic [2:0] tcp_ecn_s5;
  logic [5:0] out_tcp_ctrl_s5;
  logic [5:0] tcp_ctrl_s5;
  logic [15:0] out_tcp_window_s5;
  logic [15:0] tcp_window_s5;
  logic [15:0] out_tcp_checksum_s5;
  logic [15:0] tcp_checksum_s5;
  logic [15:0] out_tcp_urgentPtr_s5;
  logic [15:0] tcp_urgentPtr_s5;
  logic [13:0] meta_ecmp_select_w_s5;
  logic [8:0] meta_egress_port_w_s5;
  logic [15:0] ecmp_hash_val_s5;
  logic drop_s5;
  logic __stage_cond_4_r;
  logic __stage_cond_3_r;
  logic valid_s6;
  logic out_ethernet_valid_s6;
  logic ethernet_valid_s6;
  logic out_ipv4_valid_s6;
  logic ipv4_valid_s6;
  logic out_tcp_valid_s6;
  logic tcp_valid_s6;
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
  logic [2:0] out_tcp_res_s6;
  logic [2:0] tcp_res_s6;
  logic [2:0] out_tcp_ecn_s6;
  logic [2:0] tcp_ecn_s6;
  logic [5:0] out_tcp_ctrl_s6;
  logic [5:0] tcp_ctrl_s6;
  logic [15:0] out_tcp_window_s6;
  logic [15:0] tcp_window_s6;
  logic [15:0] out_tcp_checksum_s6;
  logic [15:0] tcp_checksum_s6;
  logic [15:0] out_tcp_urgentPtr_s6;
  logic [15:0] tcp_urgentPtr_s6;
  logic [13:0] meta_ecmp_select_w_s6;
  logic [8:0] meta_egress_port_w_s6;
  logic [15:0] ecmp_hash_val_s6;
  logic drop_s6;

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
  logic drop__st3;
  logic out_ethernet_valid__st4;
  logic out_ipv4_valid__st4;
  logic out_tcp_valid__st4;
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
  logic [2:0] out_tcp_res__st4;
  logic [2:0] out_tcp_ecn__st4;
  logic [5:0] out_tcp_ctrl__st4;
  logic [15:0] out_tcp_window__st4;
  logic [15:0] out_tcp_checksum__st4;
  logic [15:0] out_tcp_urgentPtr__st4;
  logic drop__st4;
  logic out_ethernet_valid__st5;
  logic out_ipv4_valid__st5;
  logic out_tcp_valid__st5;
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
  logic [2:0] out_tcp_res__st5;
  logic [2:0] out_tcp_ecn__st5;
  logic [5:0] out_tcp_ctrl__st5;
  logic [15:0] out_tcp_window__st5;
  logic [15:0] out_tcp_checksum__st5;
  logic [15:0] out_tcp_urgentPtr__st5;
  logic drop__st5;

  // Pool-B (locals/meta shadow/raw hdr+std_meta reads) working
  // copies -- every stage except the first, which reads live inputs
  logic [15:0] ecmp_hash_val__st1;
  logic [13:0] meta_ecmp_select_w__st1;
  logic [8:0] meta_egress_port_w__st1;
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
  logic [15:0] ecmp_hash_val__st2;
  logic [13:0] meta_ecmp_select_w__st2;
  logic [8:0] meta_egress_port_w__st2;
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
  logic [15:0] ecmp_hash_val__st3;
  logic [13:0] meta_ecmp_select_w__st3;
  logic [8:0] meta_egress_port_w__st3;
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
  logic [15:0] ecmp_hash_val__st4;
  logic [13:0] meta_ecmp_select_w__st4;
  logic [8:0] meta_egress_port_w__st4;
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
  logic [15:0] ecmp_hash_val__st5;
  logic [13:0] meta_ecmp_select_w__st5;
  logic [8:0] meta_egress_port_w__st5;
  logic ethernet_valid__st5;
  logic ipv4_valid__st5;
  logic tcp_valid__st5;
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
  logic [2:0] tcp_res__st5;
  logic [2:0] tcp_ecn__st5;
  logic [5:0] tcp_ctrl__st5;
  logic [15:0] tcp_window__st5;
  logic [15:0] tcp_checksum__st5;
  logic [15:0] tcp_urgentPtr__st5;
  logic [15:0] ecmp_hash_val__st6;
  logic [13:0] meta_ecmp_select_w__st6;
  logic [8:0] meta_egress_port_w__st6;
  logic ethernet_valid__st6;
  logic ipv4_valid__st6;
  logic tcp_valid__st6;
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
  logic [2:0] tcp_res__st6;
  logic [2:0] tcp_ecn__st6;
  logic [5:0] tcp_ctrl__st6;
  logic [15:0] tcp_window__st6;
  logic [15:0] tcp_checksum__st6;
  logic [15:0] tcp_urgentPtr__st6;

  // Table lookup result wires
  logic        ecmp_group_hit;
  logic [1:0] ecmp_group_act_id;
  logic [13:0] ecmp_group_p_ecmp_base;
  logic [15:0] ecmp_group_p_ecmp_mask;
  logic        ecmp_nhop_hit;
  logic [1:0] ecmp_nhop_act_id;
  logic [47:0] ecmp_nhop_p_nhop_dmac;
  logic [31:0] ecmp_nhop_p_nhop_ipv4;
  logic [8:0] ecmp_nhop_p_port;
  logic        send_frame_hit;
  logic [1:0] send_frame_act_id;
  logic [47:0] send_frame_p_smac;

  // Table module instantiations
  ecmp_group_table #(.DEPTH(64)) u_ecmp_group (
    .clk    (clk),
    .rst_n  (rst_n),
    .lkp_dstAddr    (ipv4_dstAddr),
    .hit       (ecmp_group_hit),
    .action_id (ecmp_group_act_id),
    .p_ecmp_base  (ecmp_group_p_ecmp_base),
    .p_ecmp_mask  (ecmp_group_p_ecmp_mask),
    .cp_wr_en  (ecmp_group_cp_wr_en),
    .cp_wr_idx (ecmp_group_cp_wr_idx),
    .cp_wr_key_dstAddr (ecmp_group_cp_wr_key_dstAddr),
    .cp_wr_pfx_len (ecmp_group_cp_wr_pfx_len),
    .cp_wr_action (ecmp_group_cp_wr_action),
    .cp_wr_p_ecmp_base (ecmp_group_cp_wr_p_ecmp_base),
    .cp_wr_p_ecmp_mask (ecmp_group_cp_wr_p_ecmp_mask)
  );

  ecmp_nhop_table #(.DEPTH(16)) u_ecmp_nhop (
    .clk    (clk),
    .rst_n  (rst_n),
    .lkp_ecmp_select    (meta_ecmp_select_w__st2),
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
    .cp_wr_p_port (ecmp_nhop_cp_wr_p_port),
    .cp_query_en  (ecmp_nhop_cp_query_en),
    .cp_query_del (ecmp_nhop_cp_query_del),
    .cp_query_key_ecmp_select (ecmp_nhop_cp_query_key_ecmp_select),
    .cp_query_busy (ecmp_nhop_cp_query_busy),
    .cp_query_hit  (ecmp_nhop_cp_query_hit),
    .cp_query_action_id (ecmp_nhop_cp_query_action_id),
    .cp_query_p_nhop_dmac (ecmp_nhop_cp_query_p_nhop_dmac),
    .cp_query_p_nhop_ipv4 (ecmp_nhop_cp_query_p_nhop_ipv4),
    .cp_query_p_port (ecmp_nhop_cp_query_p_port)
  );

  send_frame_table #(.DEPTH(16)) u_send_frame (
    .clk    (clk),
    .rst_n  (rst_n),
    .lkp_egress_port    (meta_egress_port_w__st4),
    .hit       (send_frame_hit),
    .action_id (send_frame_act_id),
    .p_smac  (send_frame_p_smac),
    .cp_wr_en  (send_frame_cp_wr_en),
    .cp_wr_idx (send_frame_cp_wr_idx),
    .cp_wr_key_egress_port (send_frame_cp_wr_key_egress_port),
    .cp_wr_action (send_frame_cp_wr_action),
    .cp_wr_p_smac (send_frame_cp_wr_p_smac),
    .cp_query_en  (send_frame_cp_query_en),
    .cp_query_del (send_frame_cp_query_del),
    .cp_query_key_egress_port (send_frame_cp_query_key_egress_port),
    .cp_query_busy (send_frame_cp_query_busy),
    .cp_query_hit  (send_frame_cp_query_hit),
    .cp_query_action_id (send_frame_cp_query_action_id),
    .cp_query_p_smac (send_frame_cp_query_p_smac)
  );

  // Table hit outputs
  assign ecmp_group_hit_out = ecmp_group_hit;
  assign ecmp_nhop_hit_out = ecmp_nhop_hit;
  assign send_frame_hit_out = send_frame_hit;

  // ---- Pipeline stage 0 (combinational, feeds the first exact-match table boundary) ----
  always_comb begin
    drop__st0 = 0;
    ecmp_hash_val = 16'b0;

    // Metadata shadow defaults (init from inputs)
    meta_ecmp_select_w = meta_ecmp_select;
    meta_egress_port_w = meta_egress_port;

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

    // apply block (stage 0 of 6)
    if (ipv4_valid && ipv4_ttl > 8'd0) begin
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
      ecmp_hash_val_s1 <= ecmp_hash_val;
      meta_ecmp_select_w_s1 <= meta_ecmp_select_w;
      meta_egress_port_w_s1 <= meta_egress_port_w;
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
      __stage_cond_0_r <= (ipv4_valid && ipv4_ttl > 8'd0);
    end
  end

  // ---- Pipeline stage 1 (registered 1 cycle(s) after stage 0) ----
  always_comb begin
    drop__st1 = drop_s1;
    ecmp_hash_val__st1 = ecmp_hash_val_s1;
    meta_ecmp_select_w__st1 = meta_ecmp_select_w_s1;
    meta_egress_port_w__st1 = meta_egress_port_w_s1;
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
  end

  // Forward stage-1 state into stage-2 registers (1-cycle
  // boundary — matches the exact-match table's registered latency)
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      valid_s2 <= 1'b0;
    end else begin
      valid_s2 <= valid_s1;
      drop_s2 <= drop__st1;
      ecmp_hash_val_s2 <= ecmp_hash_val__st1;
      meta_ecmp_select_w_s2 <= meta_ecmp_select_w__st1;
      meta_egress_port_w_s2 <= meta_egress_port_w__st1;
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
    end
  end

  // ---- Pipeline stage 2 (registered 2 cycle(s) after stage 0) ----
  always_comb begin
    drop__st2 = drop_s2;
    ecmp_hash_val__st2 = ecmp_hash_val_s2;
    meta_ecmp_select_w__st2 = meta_ecmp_select_w_s2;
    meta_egress_port_w__st2 = meta_egress_port_w_s2;
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

    // apply block (stage 2 of 6)
    if (__stage_cond_0_r) begin
      if (ecmp_group_hit) begin
        // ecmp_group.apply()
        if (ecmp_group_hit) begin
          unique case (ecmp_group_act_id)
            2'd0: ; // NoAction
            2'd1: begin // set_ecmp_select
              ecmp_hash_val__st2 = ecmp_hash_hash({ipv4_srcAddr__st2, ipv4_dstAddr__st2, ipv4_protocol__st2, tcp_srcPort__st2, tcp_dstPort__st2});
              meta_ecmp_select_w__st2 = ecmp_group_p_ecmp_base + 14'(ecmp_hash_val__st2 & ecmp_group_p_ecmp_mask);
            end
            2'd2: begin // drop_pkt
              drop__st2 = 1'd1;
            end
            default: ; // default = NoAction
          endcase
        end
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
      ecmp_hash_val_s3 <= ecmp_hash_val__st2;
      meta_ecmp_select_w_s3 <= meta_ecmp_select_w__st2;
      meta_egress_port_w_s3 <= meta_egress_port_w__st2;
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
      __stage_cond_2_r <= (__stage_cond_0_r);
      __stage_cond_1_r <= (ecmp_group_hit);
    end
  end

  // ---- Pipeline stage 3 (registered 3 cycle(s) after stage 0) ----
  always_comb begin
    drop__st3 = drop_s3;
    ecmp_hash_val__st3 = ecmp_hash_val_s3;
    meta_ecmp_select_w__st3 = meta_ecmp_select_w_s3;
    meta_egress_port_w__st3 = meta_egress_port_w_s3;
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
  end

  // Forward stage-3 state into stage-4 registers (1-cycle
  // boundary — matches the exact-match table's registered latency)
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      valid_s4 <= 1'b0;
    end else begin
      valid_s4 <= valid_s3;
      drop_s4 <= drop__st3;
      ecmp_hash_val_s4 <= ecmp_hash_val__st3;
      meta_ecmp_select_w_s4 <= meta_ecmp_select_w__st3;
      meta_egress_port_w_s4 <= meta_egress_port_w__st3;
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
    end
  end

  // ---- Pipeline stage 4 (registered 4 cycle(s) after stage 0) ----
  always_comb begin
    drop__st4 = drop_s4;
    ecmp_hash_val__st4 = ecmp_hash_val_s4;
    meta_ecmp_select_w__st4 = meta_ecmp_select_w_s4;
    meta_egress_port_w__st4 = meta_egress_port_w_s4;
    out_ethernet_valid__st4 = out_ethernet_valid_s4;
    ethernet_valid__st4 = ethernet_valid_s4;
    out_ipv4_valid__st4 = out_ipv4_valid_s4;
    ipv4_valid__st4 = ipv4_valid_s4;
    out_tcp_valid__st4 = out_tcp_valid_s4;
    tcp_valid__st4 = tcp_valid_s4;
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
    out_tcp_res__st4 = out_tcp_res_s4;
    tcp_res__st4 = tcp_res_s4;
    out_tcp_ecn__st4 = out_tcp_ecn_s4;
    tcp_ecn__st4 = tcp_ecn_s4;
    out_tcp_ctrl__st4 = out_tcp_ctrl_s4;
    tcp_ctrl__st4 = tcp_ctrl_s4;
    out_tcp_window__st4 = out_tcp_window_s4;
    tcp_window__st4 = tcp_window_s4;
    out_tcp_checksum__st4 = out_tcp_checksum_s4;
    tcp_checksum__st4 = tcp_checksum_s4;
    out_tcp_urgentPtr__st4 = out_tcp_urgentPtr_s4;
    tcp_urgentPtr__st4 = tcp_urgentPtr_s4;

    // apply block (stage 4 of 6)
    if (__stage_cond_2_r) begin
      if (__stage_cond_1_r) begin
        // ecmp_nhop.apply()
        if (ecmp_nhop_hit) begin
          unique case (ecmp_nhop_act_id)
            2'd0: ; // NoAction
            2'd1: begin // set_nhop
              out_ethernet_dstAddr__st4 = ecmp_nhop_p_nhop_dmac;
              out_ipv4_dstAddr__st4 = ecmp_nhop_p_nhop_ipv4;
              meta_egress_port_w__st4 = ecmp_nhop_p_port;
              out_ipv4_ttl__st4 = ipv4_ttl__st4 + 8'd255;
            end
            2'd2: begin // drop_pkt
              drop__st4 = 1'd1;
            end
            default: ; // default = NoAction
          endcase
        end
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
      ecmp_hash_val_s5 <= ecmp_hash_val__st4;
      meta_ecmp_select_w_s5 <= meta_ecmp_select_w__st4;
      meta_egress_port_w_s5 <= meta_egress_port_w__st4;
      out_ethernet_valid_s5 <= out_ethernet_valid__st4;
      ethernet_valid_s5 <= ethernet_valid__st4;
      out_ipv4_valid_s5 <= out_ipv4_valid__st4;
      ipv4_valid_s5 <= ipv4_valid__st4;
      out_tcp_valid_s5 <= out_tcp_valid__st4;
      tcp_valid_s5 <= tcp_valid__st4;
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
      out_tcp_res_s5 <= out_tcp_res__st4;
      tcp_res_s5 <= tcp_res__st4;
      out_tcp_ecn_s5 <= out_tcp_ecn__st4;
      tcp_ecn_s5 <= tcp_ecn__st4;
      out_tcp_ctrl_s5 <= out_tcp_ctrl__st4;
      tcp_ctrl_s5 <= tcp_ctrl__st4;
      out_tcp_window_s5 <= out_tcp_window__st4;
      tcp_window_s5 <= tcp_window__st4;
      out_tcp_checksum_s5 <= out_tcp_checksum__st4;
      tcp_checksum_s5 <= tcp_checksum__st4;
      out_tcp_urgentPtr_s5 <= out_tcp_urgentPtr__st4;
      tcp_urgentPtr_s5 <= tcp_urgentPtr__st4;
      __stage_cond_4_r <= (__stage_cond_2_r);
      __stage_cond_3_r <= (__stage_cond_1_r);
    end
  end

  // ---- Pipeline stage 5 (registered 5 cycle(s) after stage 0) ----
  always_comb begin
    drop__st5 = drop_s5;
    ecmp_hash_val__st5 = ecmp_hash_val_s5;
    meta_ecmp_select_w__st5 = meta_ecmp_select_w_s5;
    meta_egress_port_w__st5 = meta_egress_port_w_s5;
    out_ethernet_valid__st5 = out_ethernet_valid_s5;
    ethernet_valid__st5 = ethernet_valid_s5;
    out_ipv4_valid__st5 = out_ipv4_valid_s5;
    ipv4_valid__st5 = ipv4_valid_s5;
    out_tcp_valid__st5 = out_tcp_valid_s5;
    tcp_valid__st5 = tcp_valid_s5;
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
    out_tcp_res__st5 = out_tcp_res_s5;
    tcp_res__st5 = tcp_res_s5;
    out_tcp_ecn__st5 = out_tcp_ecn_s5;
    tcp_ecn__st5 = tcp_ecn_s5;
    out_tcp_ctrl__st5 = out_tcp_ctrl_s5;
    tcp_ctrl__st5 = tcp_ctrl_s5;
    out_tcp_window__st5 = out_tcp_window_s5;
    tcp_window__st5 = tcp_window_s5;
    out_tcp_checksum__st5 = out_tcp_checksum_s5;
    tcp_checksum__st5 = tcp_checksum_s5;
    out_tcp_urgentPtr__st5 = out_tcp_urgentPtr_s5;
    tcp_urgentPtr__st5 = tcp_urgentPtr_s5;
  end

  // Forward stage-5 state into stage-6 registers (1-cycle
  // boundary — matches the exact-match table's registered latency)
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      valid_s6 <= 1'b0;
    end else begin
      valid_s6 <= valid_s5;
      drop_s6 <= drop__st5;
      ecmp_hash_val_s6 <= ecmp_hash_val__st5;
      meta_ecmp_select_w_s6 <= meta_ecmp_select_w__st5;
      meta_egress_port_w_s6 <= meta_egress_port_w__st5;
      out_ethernet_valid_s6 <= out_ethernet_valid__st5;
      ethernet_valid_s6 <= ethernet_valid__st5;
      out_ipv4_valid_s6 <= out_ipv4_valid__st5;
      ipv4_valid_s6 <= ipv4_valid__st5;
      out_tcp_valid_s6 <= out_tcp_valid__st5;
      tcp_valid_s6 <= tcp_valid__st5;
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
      out_tcp_res_s6 <= out_tcp_res__st5;
      tcp_res_s6 <= tcp_res__st5;
      out_tcp_ecn_s6 <= out_tcp_ecn__st5;
      tcp_ecn_s6 <= tcp_ecn__st5;
      out_tcp_ctrl_s6 <= out_tcp_ctrl__st5;
      tcp_ctrl_s6 <= tcp_ctrl__st5;
      out_tcp_window_s6 <= out_tcp_window__st5;
      tcp_window_s6 <= tcp_window__st5;
      out_tcp_checksum_s6 <= out_tcp_checksum__st5;
      tcp_checksum_s6 <= tcp_checksum__st5;
      out_tcp_urgentPtr_s6 <= out_tcp_urgentPtr__st5;
      tcp_urgentPtr_s6 <= tcp_urgentPtr__st5;
    end
  end

  // ---- Pipeline stage 6 (registered 6 cycle(s) after stage 0) ----
  always_comb begin
    drop = drop_s6;
    ecmp_hash_val__st6 = ecmp_hash_val_s6;
    meta_ecmp_select_w__st6 = meta_ecmp_select_w_s6;
    meta_egress_port_w__st6 = meta_egress_port_w_s6;
    out_ethernet_valid = out_ethernet_valid_s6;
    ethernet_valid__st6 = ethernet_valid_s6;
    out_ipv4_valid = out_ipv4_valid_s6;
    ipv4_valid__st6 = ipv4_valid_s6;
    out_tcp_valid = out_tcp_valid_s6;
    tcp_valid__st6 = tcp_valid_s6;
    out_ethernet_dstAddr = out_ethernet_dstAddr_s6;
    ethernet_dstAddr__st6 = ethernet_dstAddr_s6;
    out_ethernet_srcAddr = out_ethernet_srcAddr_s6;
    ethernet_srcAddr__st6 = ethernet_srcAddr_s6;
    out_ethernet_etherType = out_ethernet_etherType_s6;
    ethernet_etherType__st6 = ethernet_etherType_s6;
    out_ipv4_version = out_ipv4_version_s6;
    ipv4_version__st6 = ipv4_version_s6;
    out_ipv4_ihl = out_ipv4_ihl_s6;
    ipv4_ihl__st6 = ipv4_ihl_s6;
    out_ipv4_diffserv = out_ipv4_diffserv_s6;
    ipv4_diffserv__st6 = ipv4_diffserv_s6;
    out_ipv4_totalLen = out_ipv4_totalLen_s6;
    ipv4_totalLen__st6 = ipv4_totalLen_s6;
    out_ipv4_identification = out_ipv4_identification_s6;
    ipv4_identification__st6 = ipv4_identification_s6;
    out_ipv4_flags = out_ipv4_flags_s6;
    ipv4_flags__st6 = ipv4_flags_s6;
    out_ipv4_fragOffset = out_ipv4_fragOffset_s6;
    ipv4_fragOffset__st6 = ipv4_fragOffset_s6;
    out_ipv4_ttl = out_ipv4_ttl_s6;
    ipv4_ttl__st6 = ipv4_ttl_s6;
    out_ipv4_protocol = out_ipv4_protocol_s6;
    ipv4_protocol__st6 = ipv4_protocol_s6;
    out_ipv4_hdrChecksum = out_ipv4_hdrChecksum_s6;
    ipv4_hdrChecksum__st6 = ipv4_hdrChecksum_s6;
    out_ipv4_srcAddr = out_ipv4_srcAddr_s6;
    ipv4_srcAddr__st6 = ipv4_srcAddr_s6;
    out_ipv4_dstAddr = out_ipv4_dstAddr_s6;
    ipv4_dstAddr__st6 = ipv4_dstAddr_s6;
    out_tcp_srcPort = out_tcp_srcPort_s6;
    tcp_srcPort__st6 = tcp_srcPort_s6;
    out_tcp_dstPort = out_tcp_dstPort_s6;
    tcp_dstPort__st6 = tcp_dstPort_s6;
    out_tcp_seqNo = out_tcp_seqNo_s6;
    tcp_seqNo__st6 = tcp_seqNo_s6;
    out_tcp_ackNo = out_tcp_ackNo_s6;
    tcp_ackNo__st6 = tcp_ackNo_s6;
    out_tcp_dataOffset = out_tcp_dataOffset_s6;
    tcp_dataOffset__st6 = tcp_dataOffset_s6;
    out_tcp_res = out_tcp_res_s6;
    tcp_res__st6 = tcp_res_s6;
    out_tcp_ecn = out_tcp_ecn_s6;
    tcp_ecn__st6 = tcp_ecn_s6;
    out_tcp_ctrl = out_tcp_ctrl_s6;
    tcp_ctrl__st6 = tcp_ctrl_s6;
    out_tcp_window = out_tcp_window_s6;
    tcp_window__st6 = tcp_window_s6;
    out_tcp_checksum = out_tcp_checksum_s6;
    tcp_checksum__st6 = tcp_checksum_s6;
    out_tcp_urgentPtr = out_tcp_urgentPtr_s6;
    tcp_urgentPtr__st6 = tcp_urgentPtr_s6;

    // apply block (stage 6 of 6)
    if (__stage_cond_4_r) begin
      if (__stage_cond_3_r) begin
        // send_frame.apply()
        if (send_frame_hit) begin
          unique case (send_frame_act_id)
            2'd0: ; // NoAction
            2'd1: begin // rewrite_mac
              out_ethernet_srcAddr = send_frame_p_smac;
            end
            2'd2: begin // drop_pkt
              drop = 1'd1;
            end
            default: ; // default = NoAction
          endcase
        end
      end
    end
    // ipv4_ck_0.clear -- real value computed via checksum wires above
    // ipv4_ck_0.add -- real value computed via checksum wires above
    // ipv4_ck_0.get -- real value computed via checksum wires above

    // update_checksum() writes -- final stage only,
    // needs the packet's fully-resolved header state
    if (1'b1) out_ipv4_hdrChecksum = chk0_value;
  end

  always_ff @(posedge clk) begin
    if (!rst_n) valid_out <= 0;
    else        valid_out <= valid_s6;
  end

endmodule
