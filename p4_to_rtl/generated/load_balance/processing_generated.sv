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

  // Control-plane write ports for table instances
  input  logic        ecmp_group_cp_wr_en,
  input  logic [9:0] ecmp_group_cp_wr_idx,
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
  ecmp_group_table #(.DEPTH(1024)) u_ecmp_group (
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

  always_comb begin
    drop = 0;
    _padding_0 = 2'b0;
    tmp = 32'b0;
    tmp_0 = 32'b0;
    tmp_1 = 8'b0;
    tmp_2 = 16'b0;
    tmp_3 = 16'b0;

    // Metadata shadow defaults (init from inputs)
    meta_ecmp_select_w = meta_ecmp_select;

    // Standard metadata defaults
    out_std_meta_egress_spec = 9'b0;

    // Header valid flag pass-through defaults
    out_ethernet_valid = ethernet_valid;
    out_ipv4_valid = ipv4_valid;
    out_tcp_valid = tcp_valid;

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
    out_tcp_srcPort = tcp_srcPort;
    out_tcp_dstPort = tcp_dstPort;
    out_tcp_seqNo = tcp_seqNo;
    out_tcp_ackNo = tcp_ackNo;
    out_tcp_dataOffset = tcp_dataOffset;
    out_tcp_res = tcp_res;
    out_tcp_ecn = tcp_ecn;
    out_tcp_ctrl = tcp_ctrl;
    out_tcp_window = tcp_window;
    out_tcp_checksum = tcp_checksum;
    out_tcp_urgentPtr = tcp_urgentPtr;

    // apply block
    if ((ipv4_valid && (ipv4_ttl > 'h00))) begin
      // ecmp_group.apply()
      if (ecmp_group_hit) begin
        unique case (ecmp_group_act_id)
          2'd0: ; // NoAction
          2'd1: begin // drop
            drop = 1;
          end
          2'd2: begin // set_ecmp_select
            tmp = ipv4_srcAddr;
            tmp_0 = ipv4_dstAddr;
            tmp_1 = ipv4_protocol;
            tmp_2 = tcp_srcPort;
            tmp_3 = tcp_dstPort;
            // hash() stub — XOR-based behavioral approximation
            meta_ecmp_select_w = (tmp ^ tmp_0 ^ tmp_1 ^ tmp_2 ^ tmp_3) & 12'hFFF;
          end
          default: ; // default = NoAction
        endcase
      end
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
            out_ipv4_ttl = ((ipv4_ttl + 'hFF) & 'hFF);
          end
          default: ; // default = NoAction
        endcase
      end
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) valid_out <= 0;
    else        valid_out <= valid_in;
  end

endmodule
