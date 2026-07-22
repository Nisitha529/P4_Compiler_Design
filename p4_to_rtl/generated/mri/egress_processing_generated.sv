module egress_processing_generated (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        valid_in,

  // Header valid flags
  input  logic        ethernet_valid,
  input  logic        ipv4_valid,
  input  logic        ipv4_option_valid,
  input  logic        mri_valid,
  input  logic        swtraces_0_valid,
  input  logic        swtraces_1_valid,
  input  logic        swtraces_2_valid,
  input  logic        swtraces_3_valid,
  input  logic        swtraces_4_valid,
  input  logic        swtraces_5_valid,
  input  logic        swtraces_6_valid,
  input  logic        swtraces_7_valid,
  input  logic        swtraces_8_valid,

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
  input  logic [0:0] ipv4_option_copyFlag,
  input  logic [1:0] ipv4_option_optClass,
  input  logic [4:0] ipv4_option_option,
  input  logic [7:0] ipv4_option_optionLength,
  input  logic [15:0] mri_count,
  input  logic [31:0] swtraces_0_swid,
  input  logic [31:0] swtraces_0_qdepth,
  input  logic [31:0] swtraces_1_swid,
  input  logic [31:0] swtraces_1_qdepth,
  input  logic [31:0] swtraces_2_swid,
  input  logic [31:0] swtraces_2_qdepth,
  input  logic [31:0] swtraces_3_swid,
  input  logic [31:0] swtraces_3_qdepth,
  input  logic [31:0] swtraces_4_swid,
  input  logic [31:0] swtraces_4_qdepth,
  input  logic [31:0] swtraces_5_swid,
  input  logic [31:0] swtraces_5_qdepth,
  input  logic [31:0] swtraces_6_swid,
  input  logic [31:0] swtraces_6_qdepth,
  input  logic [31:0] swtraces_7_swid,
  input  logic [31:0] swtraces_7_qdepth,
  input  logic [31:0] swtraces_8_swid,
  input  logic [31:0] swtraces_8_qdepth,

  // Metadata inputs
  input  logic [15:0] meta__ingress_metadata_count0,
  input  logic [15:0] meta__parser_metadata_remaining1,

  // Standard metadata inputs (table key sources)
  input  logic [18:0] std_meta_deq_qdepth,

  // Header valid flag outputs (may be modified by setValid/setInvalid)
  output logic        out_ethernet_valid,
  output logic        out_ipv4_valid,
  output logic        out_ipv4_option_valid,
  output logic        out_mri_valid,
  output logic        out_swtraces_0_valid,
  output logic        out_swtraces_1_valid,
  output logic        out_swtraces_2_valid,
  output logic        out_swtraces_3_valid,
  output logic        out_swtraces_4_valid,
  output logic        out_swtraces_5_valid,
  output logic        out_swtraces_6_valid,
  output logic        out_swtraces_7_valid,
  output logic        out_swtraces_8_valid,

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
  output logic [0:0] out_ipv4_option_copyFlag,
  output logic [1:0] out_ipv4_option_optClass,
  output logic [4:0] out_ipv4_option_option,
  output logic [7:0] out_ipv4_option_optionLength,
  output logic [15:0] out_mri_count,
  output logic [31:0] out_swtraces_0_swid,
  output logic [31:0] out_swtraces_0_qdepth,
  output logic [31:0] out_swtraces_1_swid,
  output logic [31:0] out_swtraces_1_qdepth,
  output logic [31:0] out_swtraces_2_swid,
  output logic [31:0] out_swtraces_2_qdepth,
  output logic [31:0] out_swtraces_3_swid,
  output logic [31:0] out_swtraces_3_qdepth,
  output logic [31:0] out_swtraces_4_swid,
  output logic [31:0] out_swtraces_4_qdepth,
  output logic [31:0] out_swtraces_5_swid,
  output logic [31:0] out_swtraces_5_qdepth,
  output logic [31:0] out_swtraces_6_swid,
  output logic [31:0] out_swtraces_6_qdepth,
  output logic [31:0] out_swtraces_7_swid,
  output logic [31:0] out_swtraces_7_qdepth,
  output logic [31:0] out_swtraces_8_swid,
  output logic [31:0] out_swtraces_8_qdepth,

  // Control-plane write ports for table instances
  input  logic        swtrace_cp_wr_en,
  input  logic [0:0] swtrace_cp_wr_action,
  input  logic [31:0] swtrace_cp_wr_p_swid,

  // Table hit outputs
  output logic        swtrace_hit_out,

  output logic        valid_out,
  output logic        drop
);

  // Metadata shadow locals (writable copies of metadata inputs)
  logic [15:0] meta__ingress_metadata_count0_w;
  logic [15:0] meta__parser_metadata_remaining1_w;

  // Table lookup result wires
  logic        swtrace_hit;
  logic [0:0] swtrace_act_id;
  logic [31:0] swtrace_p_swid;

  // Table module instantiations
  swtrace_table u_swtrace (
    .clk    (clk),
    .rst_n  (rst_n),
    .hit       (swtrace_hit),
    .action_id (swtrace_act_id),
    .p_swid  (swtrace_p_swid),
    .cp_wr_en  (swtrace_cp_wr_en),
    .cp_wr_action (swtrace_cp_wr_action),
    .cp_wr_p_swid (swtrace_cp_wr_p_swid)
  );

  // Table hit outputs
  assign swtrace_hit_out = swtrace_hit;

  // ---- Pipeline stage 0 ----
  always_comb begin
    drop = 0;

    // Metadata shadow defaults (init from inputs)
    meta__ingress_metadata_count0_w = meta__ingress_metadata_count0;
    meta__parser_metadata_remaining1_w = meta__parser_metadata_remaining1;

    // Header valid flag pass-through defaults
    out_ethernet_valid = ethernet_valid;
    out_ipv4_valid = ipv4_valid;
    out_ipv4_option_valid = ipv4_option_valid;
    out_mri_valid = mri_valid;
    out_swtraces_0_valid = swtraces_0_valid;
    out_swtraces_1_valid = swtraces_1_valid;
    out_swtraces_2_valid = swtraces_2_valid;
    out_swtraces_3_valid = swtraces_3_valid;
    out_swtraces_4_valid = swtraces_4_valid;
    out_swtraces_5_valid = swtraces_5_valid;
    out_swtraces_6_valid = swtraces_6_valid;
    out_swtraces_7_valid = swtraces_7_valid;
    out_swtraces_8_valid = swtraces_8_valid;

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
    out_ipv4_option_copyFlag = ipv4_option_copyFlag;
    out_ipv4_option_optClass = ipv4_option_optClass;
    out_ipv4_option_option = ipv4_option_option;
    out_ipv4_option_optionLength = ipv4_option_optionLength;
    out_mri_count = mri_count;
    out_swtraces_0_swid = swtraces_0_swid;
    out_swtraces_0_qdepth = swtraces_0_qdepth;
    out_swtraces_1_swid = swtraces_1_swid;
    out_swtraces_1_qdepth = swtraces_1_qdepth;
    out_swtraces_2_swid = swtraces_2_swid;
    out_swtraces_2_qdepth = swtraces_2_qdepth;
    out_swtraces_3_swid = swtraces_3_swid;
    out_swtraces_3_qdepth = swtraces_3_qdepth;
    out_swtraces_4_swid = swtraces_4_swid;
    out_swtraces_4_qdepth = swtraces_4_qdepth;
    out_swtraces_5_swid = swtraces_5_swid;
    out_swtraces_5_qdepth = swtraces_5_qdepth;
    out_swtraces_6_swid = swtraces_6_swid;
    out_swtraces_6_qdepth = swtraces_6_qdepth;
    out_swtraces_7_swid = swtraces_7_swid;
    out_swtraces_7_qdepth = swtraces_7_qdepth;
    out_swtraces_8_swid = swtraces_8_swid;
    out_swtraces_8_qdepth = swtraces_8_qdepth;

    // apply block
    if (mri_valid) begin
      // swtrace.apply()
      if (swtrace_hit) begin
        unique case (swtrace_act_id)
          1'd0: ; // NoAction
          1'd1: begin // add_swtrace
            out_mri_count = ((mri_count + 'h0001) & 'hFFFF);
            /* UNIMPLEMENTED EXTERN: _bmv2_push(0, 'h1) */
            out_swtraces_0_valid = 1'b1;
            out_swtraces_0_swid = swtrace_p_swid;
            out_swtraces_0_qdepth = (std_meta_deq_qdepth & 'hFFFFFFFF);
            out_ipv4_ihl = ((ipv4_ihl + 'h02) & 'h0F);
            out_ipv4_option_optionLength = ((ipv4_option_optionLength + 'h08) & 'hFF);
            out_ipv4_totalLen = ((ipv4_totalLen + 'h0008) & 'hFFFF);
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
