module egress_processing_generated (
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

  // Standard metadata inputs (table key sources)
  input  logic [47:0] std_meta_egress_global_timestamp,
  input  logic [8:0] std_meta_egress_port,
  input  logic [31:0] std_meta_packet_length,

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

  // Control-plane write ports for table instances
  input  logic        swid_cp_wr_en,
  input  logic [0:0] swid_cp_wr_action,
  input  logic [6:0] swid_cp_wr_p_swid,

  // Table hit outputs
  output logic        swid_hit_out,

  output logic        valid_out,
  output logic        drop
);

  logic [15:0] byte_cnt_0;
  logic [15:0] tmp;
  logic [15:0] tmp_0;
  logic [15:0] tmp_1;
  logic [15:0] tmp_2;
  logic [15:0] tmp_3;

  // Metadata shadow locals (writable copies of metadata inputs)
  logic [7:0] meta__egress_spec0_w;
  logic [7:0] meta__parser_metadata_remaining1_w;

  // update_checksum -> ipv4.hdrChecksum
  wire [143:0] chk0_concat = {out_ipv4_version, out_ipv4_ihl, out_ipv4_diffserv, out_ipv4_totalLen, out_ipv4_identification, out_ipv4_flags, out_ipv4_fragOffset, out_ipv4_ttl, out_ipv4_protocol, out_ipv4_srcAddr, out_ipv4_dstAddr};
  wire [31:0] chk0_sum   = {16'd0, chk0_concat[143:128]} + {16'd0, chk0_concat[127:112]} + {16'd0, chk0_concat[111:96]} + {16'd0, chk0_concat[95:80]} + {16'd0, chk0_concat[79:64]} + {16'd0, chk0_concat[63:48]} + {16'd0, chk0_concat[47:32]} + {16'd0, chk0_concat[31:16]} + {16'd0, chk0_concat[15:0]};
  wire [16:0] chk0_fold1 = chk0_sum[15:0] + chk0_sum[31:16];
  wire [16:0] chk0_fold2 = {15'd0, chk0_fold1[16]} + {1'b0, chk0_fold1[15:0]};
  wire [15:0] chk0_value = ~chk0_fold2[15:0];

  // Table lookup result wires
  logic        swid_hit;
  logic [0:0] swid_act_id;
  logic [6:0] swid_p_swid;

  // Table module instantiations
  swid_table u_swid (
    .clk    (clk),
    .rst_n  (rst_n),
    .hit       (swid_hit),
    .action_id (swid_act_id),
    .p_swid  (swid_p_swid),
    .cp_wr_en  (swid_cp_wr_en),
    .cp_wr_action (swid_cp_wr_action),
    .cp_wr_p_swid (swid_cp_wr_p_swid)
  );

  // Table hit outputs
  assign swid_hit_out = swid_hit;

  // ---- Pipeline stage 0 ----
  always_comb begin
    drop = 0;
    byte_cnt_0 = 16'b0;
    tmp = 16'b0;
    tmp_0 = 16'b0;
    tmp_1 = 16'b0;
    tmp_2 = 16'b0;
    tmp_3 = 16'b0;

    // Metadata shadow defaults (init from inputs)
    meta__egress_spec0_w = meta__egress_spec0;
    meta__parser_metadata_remaining1_w = meta__parser_metadata_remaining1;

    // Header valid flag pass-through defaults
    out_ethernet_valid = ethernet_valid;
    out_ipv4_valid = ipv4_valid;
    out_probe_valid = probe_valid;
    out_probe_data_0_valid = probe_data_0_valid;
    out_probe_data_1_valid = probe_data_1_valid;
    out_probe_data_2_valid = probe_data_2_valid;
    out_probe_data_3_valid = probe_data_3_valid;
    out_probe_data_4_valid = probe_data_4_valid;
    out_probe_data_5_valid = probe_data_5_valid;
    out_probe_data_6_valid = probe_data_6_valid;
    out_probe_data_7_valid = probe_data_7_valid;
    out_probe_data_8_valid = probe_data_8_valid;
    out_probe_data_9_valid = probe_data_9_valid;
    out_probe_fwd_0_valid = probe_fwd_0_valid;
    out_probe_fwd_1_valid = probe_fwd_1_valid;
    out_probe_fwd_2_valid = probe_fwd_2_valid;
    out_probe_fwd_3_valid = probe_fwd_3_valid;
    out_probe_fwd_4_valid = probe_fwd_4_valid;
    out_probe_fwd_5_valid = probe_fwd_5_valid;
    out_probe_fwd_6_valid = probe_fwd_6_valid;
    out_probe_fwd_7_valid = probe_fwd_7_valid;
    out_probe_fwd_8_valid = probe_fwd_8_valid;
    out_probe_fwd_9_valid = probe_fwd_9_valid;

    // Header field pass-through defaults
    out_ethernet_dstAddr = ethernet_dstAddr;
    out_ethernet_srcAddr = ethernet_srcAddr;
    out_ethernet_etherType = ethernet_etherType;
    out_ipv4_version = ipv4_version;
    out_ipv4_ihl = ipv4_ihl;
    out_ipv4_diffserv = ipv4_diffserv;
    out_ipv4_totalLen = ipv4_totalLen;
    out_ipv4_identification = ipv4_identification;
    out_ipv4_flags = ipv4_flags;
    out_ipv4_fragOffset = ipv4_fragOffset;
    out_ipv4_ttl = ipv4_ttl;
    out_ipv4_protocol = ipv4_protocol;
    out_ipv4_hdrChecksum = ipv4_hdrChecksum;
    out_ipv4_srcAddr = ipv4_srcAddr;
    out_ipv4_dstAddr = ipv4_dstAddr;
    out_probe_hop_cnt = probe_hop_cnt;
    out_probe_data_0_bos = probe_data_0_bos;
    out_probe_data_0_swid = probe_data_0_swid;
    out_probe_data_0_port = probe_data_0_port;
    out_probe_data_0_byte_cnt = probe_data_0_byte_cnt;
    out_probe_data_0_last_time = probe_data_0_last_time;
    out_probe_data_0_cur_time = probe_data_0_cur_time;
    out_probe_data_1_bos = probe_data_1_bos;
    out_probe_data_1_swid = probe_data_1_swid;
    out_probe_data_1_port = probe_data_1_port;
    out_probe_data_1_byte_cnt = probe_data_1_byte_cnt;
    out_probe_data_1_last_time = probe_data_1_last_time;
    out_probe_data_1_cur_time = probe_data_1_cur_time;
    out_probe_data_2_bos = probe_data_2_bos;
    out_probe_data_2_swid = probe_data_2_swid;
    out_probe_data_2_port = probe_data_2_port;
    out_probe_data_2_byte_cnt = probe_data_2_byte_cnt;
    out_probe_data_2_last_time = probe_data_2_last_time;
    out_probe_data_2_cur_time = probe_data_2_cur_time;
    out_probe_data_3_bos = probe_data_3_bos;
    out_probe_data_3_swid = probe_data_3_swid;
    out_probe_data_3_port = probe_data_3_port;
    out_probe_data_3_byte_cnt = probe_data_3_byte_cnt;
    out_probe_data_3_last_time = probe_data_3_last_time;
    out_probe_data_3_cur_time = probe_data_3_cur_time;
    out_probe_data_4_bos = probe_data_4_bos;
    out_probe_data_4_swid = probe_data_4_swid;
    out_probe_data_4_port = probe_data_4_port;
    out_probe_data_4_byte_cnt = probe_data_4_byte_cnt;
    out_probe_data_4_last_time = probe_data_4_last_time;
    out_probe_data_4_cur_time = probe_data_4_cur_time;
    out_probe_data_5_bos = probe_data_5_bos;
    out_probe_data_5_swid = probe_data_5_swid;
    out_probe_data_5_port = probe_data_5_port;
    out_probe_data_5_byte_cnt = probe_data_5_byte_cnt;
    out_probe_data_5_last_time = probe_data_5_last_time;
    out_probe_data_5_cur_time = probe_data_5_cur_time;
    out_probe_data_6_bos = probe_data_6_bos;
    out_probe_data_6_swid = probe_data_6_swid;
    out_probe_data_6_port = probe_data_6_port;
    out_probe_data_6_byte_cnt = probe_data_6_byte_cnt;
    out_probe_data_6_last_time = probe_data_6_last_time;
    out_probe_data_6_cur_time = probe_data_6_cur_time;
    out_probe_data_7_bos = probe_data_7_bos;
    out_probe_data_7_swid = probe_data_7_swid;
    out_probe_data_7_port = probe_data_7_port;
    out_probe_data_7_byte_cnt = probe_data_7_byte_cnt;
    out_probe_data_7_last_time = probe_data_7_last_time;
    out_probe_data_7_cur_time = probe_data_7_cur_time;
    out_probe_data_8_bos = probe_data_8_bos;
    out_probe_data_8_swid = probe_data_8_swid;
    out_probe_data_8_port = probe_data_8_port;
    out_probe_data_8_byte_cnt = probe_data_8_byte_cnt;
    out_probe_data_8_last_time = probe_data_8_last_time;
    out_probe_data_8_cur_time = probe_data_8_cur_time;
    out_probe_data_9_bos = probe_data_9_bos;
    out_probe_data_9_swid = probe_data_9_swid;
    out_probe_data_9_port = probe_data_9_port;
    out_probe_data_9_byte_cnt = probe_data_9_byte_cnt;
    out_probe_data_9_last_time = probe_data_9_last_time;
    out_probe_data_9_cur_time = probe_data_9_cur_time;
    out_probe_fwd_0_egress_spec = probe_fwd_0_egress_spec;
    out_probe_fwd_1_egress_spec = probe_fwd_1_egress_spec;
    out_probe_fwd_2_egress_spec = probe_fwd_2_egress_spec;
    out_probe_fwd_3_egress_spec = probe_fwd_3_egress_spec;
    out_probe_fwd_4_egress_spec = probe_fwd_4_egress_spec;
    out_probe_fwd_5_egress_spec = probe_fwd_5_egress_spec;
    out_probe_fwd_6_egress_spec = probe_fwd_6_egress_spec;
    out_probe_fwd_7_egress_spec = probe_fwd_7_egress_spec;
    out_probe_fwd_8_egress_spec = probe_fwd_8_egress_spec;
    out_probe_fwd_9_egress_spec = probe_fwd_9_egress_spec;

    // apply block
    tmp_0 = (std_meta_egress_port & 'hFFFFFFFF);
    byte_cnt_0 = byte_cnt_reg_rd_byte_cnt_0;
    byte_cnt_0 = ((byte_cnt_0 + std_meta_packet_length) & 'hFFFFFFFF);
    if (probe_valid) begin
      tmp = 'h00000000;
    end
    else begin
      tmp = byte_cnt_0;
    end
    tmp_3 = (std_meta_egress_port & 'hFFFFFFFF);
    byte_cnt_reg_wr_en   = 1'b1;
    byte_cnt_reg_wr_addr = tmp_3;
    byte_cnt_reg_wr_data = tmp;
    if (probe_valid) begin
      out_probe_data_9_valid = probe_data_8_valid;
      out_probe_data_9_bos = probe_data_8_bos;
      out_probe_data_9_swid = probe_data_8_swid;
      out_probe_data_9_port = probe_data_8_port;
      out_probe_data_9_byte_cnt = probe_data_8_byte_cnt;
      out_probe_data_9_last_time = probe_data_8_last_time;
      out_probe_data_9_cur_time = probe_data_8_cur_time;
      out_probe_data_8_valid = probe_data_7_valid;
      out_probe_data_8_bos = probe_data_7_bos;
      out_probe_data_8_swid = probe_data_7_swid;
      out_probe_data_8_port = probe_data_7_port;
      out_probe_data_8_byte_cnt = probe_data_7_byte_cnt;
      out_probe_data_8_last_time = probe_data_7_last_time;
      out_probe_data_8_cur_time = probe_data_7_cur_time;
      out_probe_data_7_valid = probe_data_6_valid;
      out_probe_data_7_bos = probe_data_6_bos;
      out_probe_data_7_swid = probe_data_6_swid;
      out_probe_data_7_port = probe_data_6_port;
      out_probe_data_7_byte_cnt = probe_data_6_byte_cnt;
      out_probe_data_7_last_time = probe_data_6_last_time;
      out_probe_data_7_cur_time = probe_data_6_cur_time;
      out_probe_data_6_valid = probe_data_5_valid;
      out_probe_data_6_bos = probe_data_5_bos;
      out_probe_data_6_swid = probe_data_5_swid;
      out_probe_data_6_port = probe_data_5_port;
      out_probe_data_6_byte_cnt = probe_data_5_byte_cnt;
      out_probe_data_6_last_time = probe_data_5_last_time;
      out_probe_data_6_cur_time = probe_data_5_cur_time;
      out_probe_data_5_valid = probe_data_4_valid;
      out_probe_data_5_bos = probe_data_4_bos;
      out_probe_data_5_swid = probe_data_4_swid;
      out_probe_data_5_port = probe_data_4_port;
      out_probe_data_5_byte_cnt = probe_data_4_byte_cnt;
      out_probe_data_5_last_time = probe_data_4_last_time;
      out_probe_data_5_cur_time = probe_data_4_cur_time;
      out_probe_data_4_valid = probe_data_3_valid;
      out_probe_data_4_bos = probe_data_3_bos;
      out_probe_data_4_swid = probe_data_3_swid;
      out_probe_data_4_port = probe_data_3_port;
      out_probe_data_4_byte_cnt = probe_data_3_byte_cnt;
      out_probe_data_4_last_time = probe_data_3_last_time;
      out_probe_data_4_cur_time = probe_data_3_cur_time;
      out_probe_data_3_valid = probe_data_2_valid;
      out_probe_data_3_bos = probe_data_2_bos;
      out_probe_data_3_swid = probe_data_2_swid;
      out_probe_data_3_port = probe_data_2_port;
      out_probe_data_3_byte_cnt = probe_data_2_byte_cnt;
      out_probe_data_3_last_time = probe_data_2_last_time;
      out_probe_data_3_cur_time = probe_data_2_cur_time;
      out_probe_data_2_valid = probe_data_1_valid;
      out_probe_data_2_bos = probe_data_1_bos;
      out_probe_data_2_swid = probe_data_1_swid;
      out_probe_data_2_port = probe_data_1_port;
      out_probe_data_2_byte_cnt = probe_data_1_byte_cnt;
      out_probe_data_2_last_time = probe_data_1_last_time;
      out_probe_data_2_cur_time = probe_data_1_cur_time;
      out_probe_data_1_valid = probe_data_0_valid;
      out_probe_data_1_bos = probe_data_0_bos;
      out_probe_data_1_swid = probe_data_0_swid;
      out_probe_data_1_port = probe_data_0_port;
      out_probe_data_1_byte_cnt = probe_data_0_byte_cnt;
      out_probe_data_1_last_time = probe_data_0_last_time;
      out_probe_data_1_cur_time = probe_data_0_cur_time;
      out_probe_data_0_valid = 1'b1;
      if ((probe_hop_cnt == 'h01)) begin
        out_probe_data_0_bos = 'h01;
      end
      else begin
        out_probe_data_0_bos = 'h00;
      end
      // swid.apply()
      if (swid_hit) begin
        unique case (swid_act_id)
          1'd0: ; // NoAction
          1'd1: begin // set_swid
            out_probe_data_0_swid = swid_p_swid;
          end
          default: ; // default = NoAction
        endcase
      end
      out_probe_data_0_port = ((std_meta_egress_port & 'h00FF) & 'hFF);
      out_probe_data_0_byte_cnt = byte_cnt_0;
      tmp_1 = (std_meta_egress_port & 'hFFFFFFFF);
      last_time_0 = last_time_reg_rd_last_time_0;
      tmp_2 = (std_meta_egress_port & 'hFFFFFFFF);
      last_time_reg_wr_en   = 1'b1;
      last_time_reg_wr_addr = tmp_2;
      last_time_reg_wr_data = std_meta_egress_global_timestamp;
      out_probe_data_0_last_time = last_time_0;
      out_probe_data_0_cur_time = std_meta_egress_global_timestamp;
    end

    // update_checksum() writes -- final stage only,
    // needs the packet's fully-resolved header state
    if (ipv4_valid) out_ipv4_hdrChecksum = chk0_value;
  end

  always_ff @(posedge clk) begin
    if (!rst_n) valid_out <= 0;
    else        valid_out <= valid_in;
  end

endmodule
