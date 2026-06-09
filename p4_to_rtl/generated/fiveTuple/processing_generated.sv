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
  input  logic [4:0] FiveTuple_cp_wr_idx,
  input  logic [31:0] FiveTuple_cp_wr_key_src,
  input  logic [31:0] FiveTuple_cp_wr_key_dst,
  input  logic [7:0] FiveTuple_cp_wr_key_protocol,
  input  logic [31:0] FiveTuple_cp_wr_key_table_key_sport,
  input  logic [31:0] FiveTuple_cp_wr_key_table_key_dport,
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

  // Table lookup result wires
  logic        FiveTuple_hit;
  logic [0:0] FiveTuple_act_id;
  logic [12:0] FiveTuple_p_counter_index;
  logic [2:0] FiveTuple_p_pcp;
  logic [0:0] FiveTuple_p_cfi;
  logic [11:0] FiveTuple_p_vid;

  // Table module instantiations
  FiveTuple_table #(.DEPTH(32)) u_FiveTuple (
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

  always_comb begin
    drop = 0;
    hit = 1'b0;
    table_key_dport = 16'b0;
    table_key_sport = 16'b0;

    // Header valid flag pass-through defaults
    out_eth_valid = eth_valid;
    out_new_vlan_valid = new_vlan_valid;
    out_vlan_valid = vlan_valid;
    out_ipv4_valid = ipv4_valid;
    out_ipv4opt_valid = ipv4opt_valid;
    out_tcp_valid = tcp_valid;
    out_tcpopt_valid = tcpopt_valid;
    out_udp_valid = udp_valid;

    // Header field pass-through defaults
    out_eth_dmac = eth_dmac;
    out_eth_smac = eth_smac;
    out_eth_type = eth_type;
    out_new_vlan_pcp = new_vlan_pcp;
    out_new_vlan_cfi = new_vlan_cfi;
    out_new_vlan_vid = new_vlan_vid;
    out_new_vlan_tpid = new_vlan_tpid;
    out_vlan_pcp = vlan_pcp;
    out_vlan_cfi = vlan_cfi;
    out_vlan_vid = vlan_vid;
    out_vlan_tpid = vlan_tpid;
    out_ipv4_version = ipv4_version;
    out_ipv4_hdr_len = ipv4_hdr_len;
    out_ipv4_tos = ipv4_tos;
    out_ipv4_length = ipv4_length;
    out_ipv4_id = ipv4_id;
    out_ipv4_flags = ipv4_flags;
    out_ipv4_offset = ipv4_offset;
    out_ipv4_ttl = ipv4_ttl;
    out_ipv4_protocol = ipv4_protocol;
    out_ipv4_hdr_chk = ipv4_hdr_chk;
    out_ipv4_src = ipv4_src;
    out_ipv4_dst = ipv4_dst;
    out_ipv4opt_options = ipv4opt_options;
    out_tcp_src_port = tcp_src_port;
    out_tcp_dst_port = tcp_dst_port;
    out_tcp_seqNum = tcp_seqNum;
    out_tcp_ackNum = tcp_ackNum;
    out_tcp_dataOffset = tcp_dataOffset;
    out_tcp_resv = tcp_resv;
    out_tcp_flags = tcp_flags;
    out_tcp_window = tcp_window;
    out_tcp_checksum = tcp_checksum;
    out_tcp_urgPtr = tcp_urgPtr;
    out_tcpopt_options = tcpopt_options;
    out_udp_src_port = udp_src_port;
    out_udp_dst_port = udp_dst_port;
    out_udp_length = udp_length;
    out_udp_checksum = udp_checksum;

    // apply block
    if (udp_valid) begin
      table_key_sport = udp_src_port;
      table_key_dport = udp_dst_port;
      // FiveTuple.apply()
      if (FiveTuple_hit) begin
        unique case (FiveTuple_act_id)
          1'd0: ; // NoAction
          1'd1: begin // InsertVLAN
            out_new_vlan_pcp = FiveTuple_p_pcp;
            out_new_vlan_cfi = FiveTuple_p_cfi;
            out_new_vlan_vid = FiveTuple_p_vid;
            out_new_vlan_tpid = eth_type;
            out_new_vlan_valid = 1'b1;
            /* UNIMPLEMENTED EXTERN: PacketCounter.count(counter_index) */
            /* UNIMPLEMENTED EXTERN: ByteCounter.count(counter_index) */
          end
          default: ; // default = NoAction
        endcase
      end
    end
    else begin
      if (tcp_valid) begin
        table_key_sport = tcp_src_port;
        table_key_dport = tcp_dst_port;
        // FiveTuple.apply()
        if (FiveTuple_hit) begin
          unique case (FiveTuple_act_id)
            1'd0: ; // NoAction
            1'd1: begin // InsertVLAN
              out_new_vlan_pcp = FiveTuple_p_pcp;
              out_new_vlan_cfi = FiveTuple_p_cfi;
              out_new_vlan_vid = FiveTuple_p_vid;
              out_new_vlan_tpid = eth_type;
              out_new_vlan_valid = 1'b1;
              /* UNIMPLEMENTED EXTERN: PacketCounter.count(counter_index) */
              /* UNIMPLEMENTED EXTERN: ByteCounter.count(counter_index) */
            end
            default: ; // default = NoAction
          endcase
        end
      end
    end
    if (hit) begin
      if (vlan_valid) begin
        out_eth_type = 16'h88A8;
      end
      else begin
        out_eth_type = 16'h8100;
      end
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) valid_out <= 0;
    else        valid_out <= valid_in;
  end

endmodule
