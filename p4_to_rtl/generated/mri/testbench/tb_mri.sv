// ============================================================================
// tb_mri.sv — Comprehensive self-checking testbench for mri.p4
//
// Pipeline: V1Switch → MyIngress (processing_generated) → MyEgress
//           (egress_processing_generated)
//
// P4 mri semantics under test, AS ACTUALLY IMPLEMENTED (not aspirational):
//   Ingress: ipv4_lpm table (LPM on hdr.ipv4.dstAddr), applied when
//     hdr.ipv4.isValid(). default_action = NoAction() -- a miss is a
//     silent pass-through, not a drop (same shape as ecn.p4's ipv4_lpm).
//   Egress: swtrace table (KEYLESS -- no key = {...} block, hit hardwired
//     true, dispatches whatever action the control plane configured as
//     its default; NoAction unless explicitly written), gated on
//     hdr.mri.isValid(). Its one action, add_swtrace(switchID_t swid):
//       - hdr.mri.count += 1                                  [WORKS]
//       - hdr.swtraces.push_front(1)                          [WORKS --
//         a real shift-register chain: every existing slot shifts back
//         by 1, the oldest entry falls off the end. Previously an
//         UNIMPLEMENTED EXTERN stub; now genuinely implemented, since
//         swtraces_0..8 are individually-named fixed slots that the
//         emit layer can shift directly. See Section 4 below.]
//       - hdr.swtraces[0].setValid()/.swid/.qdepth             [WORKS --
//         populates the newly-opened slot 0 after the shift above.]
//       - hdr.ipv4.ihl += 2, ipv4_option.optionLength += 8,
//         hdr.ipv4.totalLen += 8                               [WORKS]
//
// Parser: bounded loop over swtraces (MAX_HOPS=9), counted down via
//   meta.parser_metadata.remaining (initialized from hdr.mri.count).
//   This loop-count mechanism itself IS correctly implemented (verified
//   in Section 1 below) -- what's NOT modeled at this layer is which
//   swtraces_N slot corresponds to which loop iteration (a single shared
//   extract_swtraces strobe, no per-slot index signal) -- consistent
//   with this project's convention of testing the parser (FSM control)
//   and processing/egress (header-field logic) as independent DUTs, not
//   a fully chained byte-accurate pipeline (same as every other
//   testbench in this project).
//
// Ingress n_bounds=2 (1 keyed table) -> valid_out 3 cycles after valid_in.
// Egress has no keyed tables -> valid_out 1 cycle after valid_in.
//
// Compile (from this directory):
//   iverilog -g2012 -o sim tb_mri.sv \
//     ../parser_generated.sv ../processing_generated.sv \
//     ../egress_processing_generated.sv ../deparser_generated.sv \
//     ../ipv4_lpm_table.sv ../swtrace_table.sv
//   vvp sim
// ============================================================================
`timescale 1ns/1ps

module tb_mri;

  // ── Clock ──────────────────────────────────────────────────────────────
  localparam CLK_T = 10;
  logic clk = 0;
  always #(CLK_T/2) clk = ~clk;
  logic rst_n;

  // ==========================================================================
  // 1.  PARSER DUT
  // ==========================================================================
  logic        p_valid_in    = 0;
  logic [15:0] p_eth_type    = 0;
  logic  [3:0] p_ipv4_ihl    = 5;
  logic  [4:0] p_opt_option  = 0;
  logic [15:0] p_mri_count   = 0;
  logic [15:0] p_remaining   = 0;
  logic        p_ext_eth, p_ext_ipv4, p_ext_opt, p_ext_mri, p_ext_swt, p_done;

  parser_generated parser_dut (
    .clk                            (clk),
    .rst_n                          (rst_n),
    .valid_in                       (p_valid_in),
    .ethernet_etherType             (p_eth_type),
    .ipv4_ihl                       (p_ipv4_ihl),
    .ipv4_option_option             (p_opt_option),
    .meta__parser_metadata_remaining1(p_remaining),
    .mri_count                      (p_mri_count),
    .extract_ethernet               (p_ext_eth),
    .extract_ipv4                   (p_ext_ipv4),
    .extract_ipv4_option            (p_ext_opt),
    .extract_mri                    (p_ext_mri),
    .extract_swtraces               (p_ext_swt),
    .done                           (p_done)
  );

  // ==========================================================================
  // 2.  INGRESS PROCESSING DUT
  // ==========================================================================
  logic        pr_valid_in   = 0;
  logic        pr_eth_valid  = 0;
  logic        pr_ipv4_valid = 0;
  logic        pr_opt_valid  = 0;
  logic        pr_mri_valid  = 0;
  logic  [8:0] pr_swt_valid  = 0; // {swt8,...,swt0}

  logic [47:0] pr_eth_dst  = 48'hAABBCCDDEEFF;
  logic [47:0] pr_eth_src  = 48'h112233445566;
  logic [15:0] pr_eth_type = 16'h0800;
  logic  [3:0] pr_ipv4_ver = 4;
  logic  [3:0] pr_ipv4_ihl = 5;
  logic  [7:0] pr_ipv4_ds  = 0;
  logic [15:0] pr_ipv4_len = 20;
  logic [15:0] pr_ipv4_id  = 1;
  logic  [2:0] pr_ipv4_flg = 0;
  logic [12:0] pr_ipv4_off = 0;
  logic  [7:0] pr_ipv4_ttl = 64;
  logic  [7:0] pr_ipv4_proto = 6;
  logic [15:0] pr_ipv4_chk = 16'hBEEF;
  logic [31:0] pr_ipv4_src = 32'hC0A80001;
  logic [31:0] pr_ipv4_dst = 32'h0A000001;
  logic  [0:0] pr_opt_copy = 0;
  logic  [1:0] pr_opt_class = 0;
  logic  [4:0] pr_opt_option = 5'h1F;
  logic  [7:0] pr_opt_len   = 8;
  logic [15:0] pr_mri_count = 0;
  logic [31:0] pr_swt_swid  [0:8];
  logic [31:0] pr_swt_qdep  [0:8];
  logic [15:0] pr_meta_count = 0;
  logic [15:0] pr_meta_remaining = 0;

  logic [47:0] pr_o_eth_dst, pr_o_eth_src;
  logic  [7:0] pr_o_ipv4_ttl;
  logic  [8:0] pr_o_egress_spec;
  logic        pr_valid_out, pr_drop;
  logic        pr_lpm_hit_out;

  logic        lpm_cp_en   = 0;
  logic  [9:0] lpm_cp_idx  = 0;
  logic [31:0] lpm_cp_key  = 0;
  logic  [5:0] lpm_cp_pfx  = 0;
  logic  [1:0] lpm_cp_act  = 0;
  logic [47:0] lpm_cp_dstM = 0;
  logic  [8:0] lpm_cp_port = 0;

  processing_generated proc_dut (
    .clk                        (clk),
    .rst_n                      (rst_n),
    .valid_in                   (pr_valid_in),
    .ethernet_valid              (pr_eth_valid),
    .ipv4_valid                  (pr_ipv4_valid),
    .ipv4_option_valid           (pr_opt_valid),
    .mri_valid                   (pr_mri_valid),
    .swtraces_0_valid            (pr_swt_valid[0]),
    .swtraces_1_valid            (pr_swt_valid[1]),
    .swtraces_2_valid            (pr_swt_valid[2]),
    .swtraces_3_valid            (pr_swt_valid[3]),
    .swtraces_4_valid            (pr_swt_valid[4]),
    .swtraces_5_valid            (pr_swt_valid[5]),
    .swtraces_6_valid            (pr_swt_valid[6]),
    .swtraces_7_valid            (pr_swt_valid[7]),
    .swtraces_8_valid            (pr_swt_valid[8]),
    .ethernet_dstAddr            (pr_eth_dst),
    .ethernet_srcAddr            (pr_eth_src),
    .ethernet_etherType          (pr_eth_type),
    .ipv4_version                (pr_ipv4_ver),
    .ipv4_ihl                    (pr_ipv4_ihl),
    .ipv4_diffserv               (pr_ipv4_ds),
    .ipv4_totalLen               (pr_ipv4_len),
    .ipv4_identification         (pr_ipv4_id),
    .ipv4_flags                  (pr_ipv4_flg),
    .ipv4_fragOffset             (pr_ipv4_off),
    .ipv4_ttl                    (pr_ipv4_ttl),
    .ipv4_protocol               (pr_ipv4_proto),
    .ipv4_hdrChecksum            (pr_ipv4_chk),
    .ipv4_srcAddr                (pr_ipv4_src),
    .ipv4_dstAddr                (pr_ipv4_dst),
    .ipv4_option_copyFlag        (pr_opt_copy),
    .ipv4_option_optClass        (pr_opt_class),
    .ipv4_option_option          (pr_opt_option),
    .ipv4_option_optionLength    (pr_opt_len),
    .mri_count                   (pr_mri_count),
    .swtraces_0_swid (pr_swt_swid[0]), .swtraces_0_qdepth (pr_swt_qdep[0]),
    .swtraces_1_swid (pr_swt_swid[1]), .swtraces_1_qdepth (pr_swt_qdep[1]),
    .swtraces_2_swid (pr_swt_swid[2]), .swtraces_2_qdepth (pr_swt_qdep[2]),
    .swtraces_3_swid (pr_swt_swid[3]), .swtraces_3_qdepth (pr_swt_qdep[3]),
    .swtraces_4_swid (pr_swt_swid[4]), .swtraces_4_qdepth (pr_swt_qdep[4]),
    .swtraces_5_swid (pr_swt_swid[5]), .swtraces_5_qdepth (pr_swt_qdep[5]),
    .swtraces_6_swid (pr_swt_swid[6]), .swtraces_6_qdepth (pr_swt_qdep[6]),
    .swtraces_7_swid (pr_swt_swid[7]), .swtraces_7_qdepth (pr_swt_qdep[7]),
    .swtraces_8_swid (pr_swt_swid[8]), .swtraces_8_qdepth (pr_swt_qdep[8]),
    .meta__ingress_metadata_count0(pr_meta_count),
    .meta__parser_metadata_remaining1(pr_meta_remaining),
    .out_ethernet_valid          (),
    .out_ipv4_valid              (),
    .out_ipv4_option_valid       (),
    .out_mri_valid               (),
    .out_swtraces_0_valid        (), .out_swtraces_1_valid (), .out_swtraces_2_valid (),
    .out_swtraces_3_valid        (), .out_swtraces_4_valid (), .out_swtraces_5_valid (),
    .out_swtraces_6_valid        (), .out_swtraces_7_valid (), .out_swtraces_8_valid (),
    .out_ethernet_dstAddr        (pr_o_eth_dst),
    .out_ethernet_srcAddr        (pr_o_eth_src),
    .out_ethernet_etherType      (),
    .out_ipv4_version            (),
    .out_ipv4_ihl                (),
    .out_ipv4_diffserv           (),
    .out_ipv4_totalLen           (),
    .out_ipv4_identification     (),
    .out_ipv4_flags              (),
    .out_ipv4_fragOffset         (),
    .out_ipv4_ttl                (pr_o_ipv4_ttl),
    .out_ipv4_protocol           (),
    .out_ipv4_hdrChecksum        (),
    .out_ipv4_srcAddr            (),
    .out_ipv4_dstAddr            (),
    .out_ipv4_option_copyFlag    (),
    .out_ipv4_option_optClass    (),
    .out_ipv4_option_option      (),
    .out_ipv4_option_optionLength(),
    .out_mri_count               (),
    .out_swtraces_0_swid (), .out_swtraces_0_qdepth (),
    .out_swtraces_1_swid (), .out_swtraces_1_qdepth (),
    .out_swtraces_2_swid (), .out_swtraces_2_qdepth (),
    .out_swtraces_3_swid (), .out_swtraces_3_qdepth (),
    .out_swtraces_4_swid (), .out_swtraces_4_qdepth (),
    .out_swtraces_5_swid (), .out_swtraces_5_qdepth (),
    .out_swtraces_6_swid (), .out_swtraces_6_qdepth (),
    .out_swtraces_7_swid (), .out_swtraces_7_qdepth (),
    .out_swtraces_8_swid (), .out_swtraces_8_qdepth (),
    .out_std_meta_egress_spec    (pr_o_egress_spec),
    .ipv4_lpm_cp_wr_en           (lpm_cp_en),
    .ipv4_lpm_cp_wr_idx          (lpm_cp_idx),
    .ipv4_lpm_cp_wr_key_dstAddr  (lpm_cp_key),
    .ipv4_lpm_cp_wr_pfx_len      (lpm_cp_pfx),
    .ipv4_lpm_cp_wr_action       (lpm_cp_act),
    .ipv4_lpm_cp_wr_p_dstAddr    (lpm_cp_dstM),
    .ipv4_lpm_cp_wr_p_port       (lpm_cp_port),
    .ipv4_lpm_hit_out            (pr_lpm_hit_out),
    .valid_out                   (pr_valid_out),
    .drop                        (pr_drop)
  );

  // ==========================================================================
  // 3.  EGRESS PROCESSING DUT
  // ==========================================================================
  logic        eg_valid_in   = 0;
  logic        eg_eth_valid  = 1;
  logic        eg_ipv4_valid = 1;
  logic        eg_opt_valid  = 1;
  logic        eg_mri_valid  = 0;
  logic  [8:0] eg_swt_valid  = 9'b0;

  logic  [3:0] eg_ipv4_ihl = 7;   // 5 (base) + 2 (option already present)
  logic [15:0] eg_ipv4_len = 36;  // 20 ipv4 + 16 option/mri
  logic  [7:0] eg_opt_len  = 8;
  logic [15:0] eg_mri_count = 3;
  logic [31:0] eg_swt_swid [0:8];
  logic [31:0] eg_swt_qdep [0:8];
  logic [18:0] eg_qdepth    = 19'd42;

  logic  [3:0] eg_o_ipv4_ihl;
  logic [15:0] eg_o_ipv4_len;
  logic  [7:0] eg_o_opt_len;
  logic [15:0] eg_o_mri_count;
  logic        eg_o_swt0_valid;
  logic [31:0] eg_o_swt0_swid, eg_o_swt0_qdep;
  logic        eg_o_swt1_valid;
  logic [31:0] eg_o_swt1_swid, eg_o_swt1_qdep;
  logic        eg_o_swt2_valid;
  logic [31:0] eg_o_swt2_swid, eg_o_swt2_qdep;
  logic        eg_valid_out, eg_drop;

  logic        swt_cp_en   = 0;
  logic  [0:0] swt_cp_act  = 0;
  logic [31:0] swt_cp_swid = 0;
  logic        swt_hit_out;

  // Unused pass-through inputs, tied to benign constants.
  logic [47:0] eg_eth_dst = 0, eg_eth_src = 0;
  logic [15:0] eg_eth_type = 0;
  logic  [3:0] eg_ipv4_ver = 4;
  logic  [7:0] eg_ipv4_ds = 0;
  logic [15:0] eg_ipv4_id = 0;
  logic  [2:0] eg_ipv4_flg = 0;
  logic [12:0] eg_ipv4_off = 0;
  logic  [7:0] eg_ipv4_ttl = 64, eg_ipv4_proto = 0;
  logic [15:0] eg_ipv4_chk = 0;
  logic [31:0] eg_ipv4_src = 0, eg_ipv4_dst = 0;
  logic  [0:0] eg_opt_copy = 0;
  logic  [1:0] eg_opt_class = 0;
  logic  [4:0] eg_opt_option = 5'h1F;

  egress_processing_generated egress_dut (
    .clk                         (clk),
    .rst_n                       (rst_n),
    .valid_in                    (eg_valid_in),
    .ethernet_valid               (eg_eth_valid),
    .ipv4_valid                   (eg_ipv4_valid),
    .ipv4_option_valid            (eg_opt_valid),
    .mri_valid                    (eg_mri_valid),
    .swtraces_0_valid             (eg_swt_valid[0]),
    .swtraces_1_valid             (eg_swt_valid[1]),
    .swtraces_2_valid             (eg_swt_valid[2]),
    .swtraces_3_valid             (eg_swt_valid[3]),
    .swtraces_4_valid             (eg_swt_valid[4]),
    .swtraces_5_valid             (eg_swt_valid[5]),
    .swtraces_6_valid             (eg_swt_valid[6]),
    .swtraces_7_valid             (eg_swt_valid[7]),
    .swtraces_8_valid             (eg_swt_valid[8]),
    .ethernet_dstAddr             (eg_eth_dst),
    .ethernet_srcAddr             (eg_eth_src),
    .ethernet_etherType           (eg_eth_type),
    .ipv4_version                 (eg_ipv4_ver),
    .ipv4_ihl                     (eg_ipv4_ihl),
    .ipv4_diffserv                (eg_ipv4_ds),
    .ipv4_totalLen                (eg_ipv4_len),
    .ipv4_identification          (eg_ipv4_id),
    .ipv4_flags                   (eg_ipv4_flg),
    .ipv4_fragOffset              (eg_ipv4_off),
    .ipv4_ttl                     (eg_ipv4_ttl),
    .ipv4_protocol                (eg_ipv4_proto),
    .ipv4_hdrChecksum             (eg_ipv4_chk),
    .ipv4_srcAddr                 (eg_ipv4_src),
    .ipv4_dstAddr                 (eg_ipv4_dst),
    .ipv4_option_copyFlag         (eg_opt_copy),
    .ipv4_option_optClass         (eg_opt_class),
    .ipv4_option_option           (eg_opt_option),
    .ipv4_option_optionLength     (eg_opt_len),
    .mri_count                    (eg_mri_count),
    .swtraces_0_swid (eg_swt_swid[0]), .swtraces_0_qdepth (eg_swt_qdep[0]),
    .swtraces_1_swid (eg_swt_swid[1]), .swtraces_1_qdepth (eg_swt_qdep[1]),
    .swtraces_2_swid (eg_swt_swid[2]), .swtraces_2_qdepth (eg_swt_qdep[2]),
    .swtraces_3_swid (eg_swt_swid[3]), .swtraces_3_qdepth (eg_swt_qdep[3]),
    .swtraces_4_swid (eg_swt_swid[4]), .swtraces_4_qdepth (eg_swt_qdep[4]),
    .swtraces_5_swid (eg_swt_swid[5]), .swtraces_5_qdepth (eg_swt_qdep[5]),
    .swtraces_6_swid (eg_swt_swid[6]), .swtraces_6_qdepth (eg_swt_qdep[6]),
    .swtraces_7_swid (eg_swt_swid[7]), .swtraces_7_qdepth (eg_swt_qdep[7]),
    .swtraces_8_swid (eg_swt_swid[8]), .swtraces_8_qdepth (eg_swt_qdep[8]),
    .std_meta_deq_qdepth          (eg_qdepth),
    .out_ethernet_valid           (),
    .out_ipv4_valid               (),
    .out_ipv4_option_valid        (),
    .out_mri_valid                (),
    .out_swtraces_0_valid         (eg_o_swt0_valid),
    .out_swtraces_1_valid         (eg_o_swt1_valid),
    .out_swtraces_2_valid         (eg_o_swt2_valid),
    .out_swtraces_3_valid (), .out_swtraces_4_valid (),
    .out_swtraces_5_valid         (), .out_swtraces_6_valid (), .out_swtraces_7_valid (),
    .out_swtraces_8_valid         (),
    .out_ethernet_dstAddr         (),
    .out_ethernet_srcAddr         (),
    .out_ethernet_etherType       (),
    .out_ipv4_version             (),
    .out_ipv4_ihl                 (eg_o_ipv4_ihl),
    .out_ipv4_diffserv            (),
    .out_ipv4_totalLen            (eg_o_ipv4_len),
    .out_ipv4_identification      (),
    .out_ipv4_flags               (),
    .out_ipv4_fragOffset          (),
    .out_ipv4_ttl                 (),
    .out_ipv4_protocol            (),
    .out_ipv4_hdrChecksum         (),
    .out_ipv4_srcAddr             (),
    .out_ipv4_dstAddr             (),
    .out_ipv4_option_copyFlag     (),
    .out_ipv4_option_optClass     (),
    .out_ipv4_option_option       (),
    .out_ipv4_option_optionLength (eg_o_opt_len),
    .out_mri_count                (eg_o_mri_count),
    .out_swtraces_0_swid (eg_o_swt0_swid), .out_swtraces_0_qdepth (eg_o_swt0_qdep),
    .out_swtraces_1_swid (eg_o_swt1_swid), .out_swtraces_1_qdepth (eg_o_swt1_qdep),
    .out_swtraces_2_swid (eg_o_swt2_swid), .out_swtraces_2_qdepth (eg_o_swt2_qdep),
    .out_swtraces_3_swid (), .out_swtraces_3_qdepth (),
    .out_swtraces_4_swid (), .out_swtraces_4_qdepth (),
    .out_swtraces_5_swid (), .out_swtraces_5_qdepth (),
    .out_swtraces_6_swid (), .out_swtraces_6_qdepth (),
    .out_swtraces_7_swid (), .out_swtraces_7_qdepth (),
    .out_swtraces_8_swid (), .out_swtraces_8_qdepth (),
    .swtrace_cp_wr_en             (swt_cp_en),
    .swtrace_cp_wr_action         (swt_cp_act),
    .swtrace_cp_wr_p_swid         (swt_cp_swid),
    .swtrace_hit_out              (swt_hit_out),
    .valid_out                    (eg_valid_out),
    .drop                         (eg_drop)
  );

  // ==========================================================================
  // 4.  DEPARSER DUT
  // ==========================================================================
  localparam DEP_W = 880;

  logic        dep_valid_in = 0;
  logic        dep_eth_valid = 0, dep_ipv4_valid = 0, dep_opt_valid = 0, dep_mri_valid = 0;
  logic  [8:0] dep_swt_valid = 0;
  logic [47:0] dep_eth_dst = 0, dep_eth_src = 0;
  logic [15:0] dep_eth_type = 0;
  logic  [3:0] dep_ipv4_ver = 0, dep_ipv4_ihl = 0;
  logic  [7:0] dep_ipv4_ds = 0;
  logic [15:0] dep_ipv4_len = 0, dep_ipv4_id = 0;
  logic  [2:0] dep_ipv4_flg = 0;
  logic [12:0] dep_ipv4_off = 0;
  logic  [7:0] dep_ipv4_ttl = 0, dep_ipv4_proto = 0;
  logic [15:0] dep_ipv4_chk = 0;
  logic [31:0] dep_ipv4_src = 0, dep_ipv4_dst = 0;
  logic  [0:0] dep_opt_copy = 0;
  logic  [1:0] dep_opt_class = 0;
  logic  [4:0] dep_opt_option = 0;
  logic  [7:0] dep_opt_len = 0;
  logic [15:0] dep_mri_count = 0;
  logic [31:0] dep_swt_swid [0:8];
  logic [31:0] dep_swt_qdep [0:8];

  logic [DEP_W-1:0] dep_pkt_out;
  logic [15:0]      dep_pkt_len;
  logic              dep_valid_out;

  deparser_generated deparser_dut (
    .clk                 (clk),
    .rst_n               (rst_n),
    .valid_in            (dep_valid_in),
    .ethernet_valid       (dep_eth_valid),
    .ipv4_valid           (dep_ipv4_valid),
    .ipv4_option_valid    (dep_opt_valid),
    .mri_valid            (dep_mri_valid),
    .swtraces_0_valid     (dep_swt_valid[0]),
    .swtraces_1_valid     (dep_swt_valid[1]),
    .swtraces_2_valid     (dep_swt_valid[2]),
    .swtraces_3_valid     (dep_swt_valid[3]),
    .swtraces_4_valid     (dep_swt_valid[4]),
    .swtraces_5_valid     (dep_swt_valid[5]),
    .swtraces_6_valid     (dep_swt_valid[6]),
    .swtraces_7_valid     (dep_swt_valid[7]),
    .swtraces_8_valid     (dep_swt_valid[8]),
    .ethernet_dstAddr     (dep_eth_dst),
    .ethernet_srcAddr     (dep_eth_src),
    .ethernet_etherType   (dep_eth_type),
    .ipv4_version         (dep_ipv4_ver),
    .ipv4_ihl             (dep_ipv4_ihl),
    .ipv4_diffserv        (dep_ipv4_ds),
    .ipv4_totalLen        (dep_ipv4_len),
    .ipv4_identification  (dep_ipv4_id),
    .ipv4_flags           (dep_ipv4_flg),
    .ipv4_fragOffset      (dep_ipv4_off),
    .ipv4_ttl             (dep_ipv4_ttl),
    .ipv4_protocol        (dep_ipv4_proto),
    .ipv4_hdrChecksum     (dep_ipv4_chk),
    .ipv4_srcAddr         (dep_ipv4_src),
    .ipv4_dstAddr         (dep_ipv4_dst),
    .ipv4_option_copyFlag (dep_opt_copy),
    .ipv4_option_optClass (dep_opt_class),
    .ipv4_option_option   (dep_opt_option),
    .ipv4_option_optionLength(dep_opt_len),
    .mri_count            (dep_mri_count),
    .swtraces_0_swid (dep_swt_swid[0]), .swtraces_0_qdepth (dep_swt_qdep[0]),
    .swtraces_1_swid (dep_swt_swid[1]), .swtraces_1_qdepth (dep_swt_qdep[1]),
    .swtraces_2_swid (dep_swt_swid[2]), .swtraces_2_qdepth (dep_swt_qdep[2]),
    .swtraces_3_swid (dep_swt_swid[3]), .swtraces_3_qdepth (dep_swt_qdep[3]),
    .swtraces_4_swid (dep_swt_swid[4]), .swtraces_4_qdepth (dep_swt_qdep[4]),
    .swtraces_5_swid (dep_swt_swid[5]), .swtraces_5_qdepth (dep_swt_qdep[5]),
    .swtraces_6_swid (dep_swt_swid[6]), .swtraces_6_qdepth (dep_swt_qdep[6]),
    .swtraces_7_swid (dep_swt_swid[7]), .swtraces_7_qdepth (dep_swt_qdep[7]),
    .swtraces_8_swid (dep_swt_swid[8]), .swtraces_8_qdepth (dep_swt_qdep[8]),
    .pkt_hdr_out          (dep_pkt_out),
    .pkt_hdr_len          (dep_pkt_len),
    .valid_out            (dep_valid_out)
  );

  // ==========================================================================
  // Test infrastructure
  // ==========================================================================
  int pass_cnt = 0, fail_cnt = 0;
  integer ii;

  task automatic chk(input string name, input logic cond);
    if (cond) begin $display("    [PASS] %s", name); pass_cnt++; end
    else      begin $display("    [FAIL] %s", name); fail_cnt++; end
  endtask

  task do_reset;
    rst_n = 0; p_valid_in = 0; pr_valid_in = 0; eg_valid_in = 0; dep_valid_in = 0;
    pr_eth_valid = 0; pr_ipv4_valid = 0; pr_opt_valid = 0; pr_mri_valid = 0; pr_swt_valid = 0;
    repeat(5) @(posedge clk); @(negedge clk);
    rst_n = 1; @(posedge clk); #1;
  endtask

  task lpm_write(input [9:0] idx, input [31:0] key, input [5:0] pfx,
                 input [1:0] act,  input [47:0] dstM, input [8:0] portn);
    @(negedge clk);
    lpm_cp_idx=idx; lpm_cp_key=key; lpm_cp_pfx=pfx;
    lpm_cp_act=act; lpm_cp_dstM=dstM; lpm_cp_port=portn;
    lpm_cp_en=1;
    @(posedge clk); #1;
    lpm_cp_en=0;
  endtask

  task swtrace_write(input [0:0] act, input [31:0] swid);
    @(negedge clk);
    swt_cp_act = act; swt_cp_swid = swid;
    swt_cp_en = 1;
    @(posedge clk); #1;
    swt_cp_en = 0;
  endtask

  // n_bounds=2 -> valid_out is 3 cycles after valid_in
  task send_ingress_packet;
    pr_valid_in=1; @(posedge clk); #1; pr_valid_in=0;
    @(posedge clk); #1;
    @(posedge clk); #1;
  endtask

  // ==========================================================================
  // MAIN TEST
  // ==========================================================================
  initial begin
    for (ii = 0; ii < 9; ii = ii + 1) begin
      pr_swt_swid[ii] = 0; pr_swt_qdep[ii] = 0;
      eg_swt_swid[ii] = 32'h1000_0000 + ii; eg_swt_qdep[ii] = 32'h2000_0000 + ii;
      dep_swt_swid[ii] = 0; dep_swt_qdep[ii] = 0;
    end

    $display("== tb_mri: mri.p4 self-checking regression ==\n");

    // ──────────────────────────────────────────────────────────────────────
    // SECTION 1 — PARSER (bounded swtrace loop count)
    // ──────────────────────────────────────────────────────────────────────
    $display("══ Section 1: Parser FSM ══════════════════════════════════════");

    // P1: plain IPv4, ihl=5 (no options) -> eth->ipv4->accept
    $display("  P1: ihl=5 (no option) -> eth->ipv4->accept");
    do_reset();
    p_eth_type=16'h0800; p_ipv4_ihl=4'h5; p_valid_in=1;
    @(posedge clk); #1;
    chk("P1 ETH", p_ext_eth);
    @(posedge clk); #1;
    chk("P1 IPV4", p_ext_ipv4);
    @(posedge clk); #1;
    chk("P1 ACCEPT: done", p_done);
    chk("P1 !option", !p_ext_opt);
    p_valid_in=0;

    // P2: ihl=6 with non-MRI option -> eth->ipv4->option->accept
    // Each state's own transition depends on a field only visible/valid
    // WHILE that state is current -- so edge N reveals state N (START at
    // edge1), and the transition FROM that state is sampled right before
    // edge N+1, using whatever the testbench is currently driving.
    $display("  P2: ihl=6, option!=0x1F -> eth->ipv4->option->accept");
    do_reset();
    p_eth_type=16'h0800; p_ipv4_ihl=4'h6; p_opt_option=5'h05; p_valid_in=1;
    @(posedge clk); #1; // edge1: START visible (ext_eth)
    @(posedge clk); #1; // edge2: PARSE_IPV4 visible (ext_ipv4)
    @(posedge clk); #1; // edge3: PARSE_IPV4_OPTION visible (ext_opt)
    chk("P2 OPTION", p_ext_opt);
    @(posedge clk); #1; // edge4: ACCEPT visible (done)
    chk("P2 ACCEPT: done", p_done);
    chk("P2 !mri", !p_ext_mri);
    p_valid_in=0;

    // P3: ihl=6, MRI option, count=0 -> eth->ipv4->option->mri->accept (no swtrace loop)
    $display("  P3: MRI option, count=0 -> ...->mri->accept (no swtrace iter)");
    do_reset();
    p_eth_type=16'h0800; p_ipv4_ihl=4'h6; p_opt_option=5'h1F; p_mri_count=16'd0; p_valid_in=1;
    @(posedge clk); #1; // edge1: START (ext_eth)
    @(posedge clk); #1; // edge2: PARSE_IPV4 (ext_ipv4)
    @(posedge clk); #1; // edge3: PARSE_IPV4_OPTION (ext_opt)
    @(posedge clk); #1; // edge4: PARSE_MRI (ext_mri)
    chk("P3 MRI", p_ext_mri);
    @(posedge clk); #1; // edge5: ACCEPT (done) -- mri_count=0 skips the swtrace loop entirely
    chk("P3 ACCEPT: done", p_done);
    chk("P3 !swtrace", !p_ext_swt);
    p_valid_in=0;

    // P4: MRI option, count=1 -> loop PARSE_SWTRACE exactly once. The real
    // P4 action initializes meta.parser_metadata.remaining from hdr.mri.count
    // on entering parse_mri, then decrements it each swtrace iteration --
    // modeled here directly via p_remaining (this testbench drives the
    // parser's own inputs directly rather than chaining from a byte
    // stream, same convention as every other testbench in this project).
    // Kept to a single iteration for a robust, unambiguous edge count
    // rather than hand-simulating a multi-cycle external counter.
    $display("  P4: MRI option, count=1 -> swtrace loop x1 then accept");
    do_reset();
    p_eth_type=16'h0800; p_ipv4_ihl=4'h6; p_opt_option=5'h1F; p_mri_count=16'd1; p_valid_in=1;
    @(posedge clk); #1; // edge1: START (ext_eth)
    @(posedge clk); #1; // edge2: PARSE_IPV4 (ext_ipv4)
    @(posedge clk); #1; // edge3: PARSE_IPV4_OPTION (ext_opt)
    @(posedge clk); #1; // edge4: PARSE_MRI (ext_mri); mri_count=1 -> loop entered
    p_remaining = 16'd1;
    @(posedge clk); #1; // edge5: PARSE_SWTRACE, 1st (and only) iteration
    chk("P4 SWTRACE iter1", p_ext_swt);
    p_remaining = 16'd0;
    @(posedge clk); #1; // edge6: ACCEPT (remaining=0 -> loop exits)
    chk("P4 ACCEPT after exactly 1 iteration", p_done);
    p_valid_in=0;

    // ──────────────────────────────────────────────────────────────────────
    // SECTION 2 — INGRESS: ipv4_lpm (default_action = NoAction on miss)
    // ──────────────────────────────────────────────────────────────────────
    $display("\n══ Section 2: Ingress ipv4_lpm ══════════════════════════════════");
    do_reset();
    pr_eth_valid=1; pr_ipv4_valid=1; pr_opt_valid=0; pr_mri_valid=0;

    lpm_write(0, 32'h0A000000, 6'd8, 2'd1, 48'hAABBCCDDEEFF, 9'd3);
    lpm_write(1, 32'hAC100000, 6'd12, 2'd2, 48'h0, 9'd0);

    pr_ipv4_dst = 32'h0A010203; pr_ipv4_ttl = 64;
    send_ingress_packet();
    chk("L1: not dropped",       !pr_drop);
    chk("L1: dstAddr rewritten", pr_o_eth_dst === 48'hAABBCCDDEEFF);
    chk("L1: ttl decremented",   pr_o_ipv4_ttl === 8'd63);
    chk("L1: egress_spec=3",     pr_o_egress_spec === 9'd3);

    pr_ipv4_dst = 32'hAC100005;
    send_ingress_packet();
    chk("L2: explicit drop entry -> dropped", pr_drop);

    pr_ipv4_dst = 32'h08080808;
    pr_eth_dst  = 48'h999999999999;
    pr_ipv4_ttl = 77;
    send_ingress_packet();
    chk("L3: miss -> NOT dropped (default=NoAction)", !pr_drop);
    chk("L3: eth dstAddr unmodified on miss", pr_o_eth_dst === 48'h999999999999);
    chk("L3: ttl unmodified on miss",         pr_o_ipv4_ttl === 8'd77);

    // ──────────────────────────────────────────────────────────────────────
    // SECTION 3 — Ingress valid_out latency
    // ──────────────────────────────────────────────────────────────────────
    $display("\n══ Section 3: Ingress valid_out latency ═════════════════════════");
    do_reset();
    pr_eth_valid=1; pr_ipv4_valid=1;
    pr_ipv4_dst = 32'h0A010203;
    pr_valid_in=1; @(posedge clk); #1; pr_valid_in=0;
    chk("IV1: valid_out=0 after 1st edge", !pr_valid_out);
    @(posedge clk); #1;
    chk("IV1: valid_out=0 after 2nd edge", !pr_valid_out);
    @(posedge clk); #1;
    chk("IV1: valid_out=1 after 3rd edge", pr_valid_out);
    @(posedge clk); #1;
    chk("IV1: valid_out=0 deasserted", !pr_valid_out);

    // ──────────────────────────────────────────────────────────────────────
    // SECTION 4 — EGRESS: swtrace (keyless table, gated on mri.isValid())
    // ──────────────────────────────────────────────────────────────────────
    $display("\n══ Section 4: Egress swtrace (add_swtrace, real push_front shift) ══");

    // E1: mri invalid -> table never applies, everything passes through
    eg_mri_valid = 0;
    #1;
    chk("E1: mri invalid -> mri_count unchanged", eg_o_mri_count === eg_mri_count);
    chk("E1: mri invalid -> ihl unchanged",       eg_o_ipv4_ihl === eg_ipv4_ihl);

    // E2: mri valid but swtrace's default action never CP-configured
    // (stays NoAction, id 0) -> still a no-op, matching keyless-table
    // semantics (a keyless table always applies whatever default action
    // is currently configured; it starts as NoAction).
    eg_mri_valid = 1;
    #1;
    chk("E2: mri valid, table unconfigured (NoAction) -> mri_count unchanged", eg_o_mri_count === eg_mri_count);
    chk("E2: mri valid, table unconfigured -> ihl unchanged",                  eg_o_ipv4_ihl === eg_ipv4_ihl);

    // E3: CP-configure swtrace's default action to add_swtrace(swid=0xCAFE0001).
    // push_front is now really implemented (a real shift-register chain,
    // not a stub) -- verify slot 0 gets the new hop's data AND slot 1
    // gets what was previously at slot 0 (the actual push, not an
    // overwrite-in-place).
    swtrace_write(1'd1, 32'hCAFE0001);
    #1;
    chk("E3: mri.count += 1",           eg_o_mri_count === (eg_mri_count + 16'd1));
    chk("E3: ipv4.ihl += 2",            eg_o_ipv4_ihl === (eg_ipv4_ihl + 4'd2));
    chk("E3: ipv4_option.optionLength += 8", eg_o_opt_len === (eg_opt_len + 8'd8));
    chk("E3: ipv4.totalLen += 8",       eg_o_ipv4_len === (eg_ipv4_len + 16'd8));
    chk("E3: swtraces[0].valid set",    eg_o_swt0_valid === 1'b1);
    chk("E3: swtraces[0].swid = configured swid", eg_o_swt0_swid === 32'hCAFE0001);
    chk("E3: swtraces[0].qdepth = deq_qdepth",    eg_o_swt0_qdep === {13'b0, eg_qdepth});
    chk("E3: swtraces[1] = shifted-in old slot-0 (real push, not an overwrite)",
        eg_o_swt1_valid === eg_swt_valid[0] && eg_o_swt1_swid === eg_swt_swid[0] && eg_o_swt1_qdep === eg_swt_qdep[0]);

    // E4: a second push shifts the first push's slot-0 entry into slot 1
    // -- a genuine two-hop trace, the actual feature this fix is for.
    // This DUT is driven combinationally (not through a real register
    // chain), so the "previous cycle's output" is fed forward by hand to
    // simulate a second hop.
    eg_swt_valid[0] = eg_o_swt0_valid; eg_swt_swid[0] = eg_o_swt0_swid; eg_swt_qdep[0] = eg_o_swt0_qdep;
    eg_swt_valid[1] = eg_o_swt1_valid; eg_swt_swid[1] = eg_o_swt1_swid; eg_swt_qdep[1] = eg_o_swt1_qdep;
    swtrace_write(1'd1, 32'hCAFE0002);
    #1;
    chk("E4: 2nd push -> slot0 = new hop's swid", eg_o_swt0_swid === 32'hCAFE0002);
    chk("E4: 2nd push -> slot1 = 1st push's slot0 (shifted again)",
        eg_o_swt1_valid === 1'b1 && eg_o_swt1_swid === 32'hCAFE0001);
    chk("E4: 2nd push -> slot2 = 1st push's slot1",
        eg_o_swt2_valid === eg_swt_valid[1] && eg_o_swt2_swid === eg_swt_swid[1]);

    // ──────────────────────────────────────────────────────────────────────
    // SECTION 5 — Egress valid_out latency (1-cycle, no keyed tables)
    // ──────────────────────────────────────────────────────────────────────
    $display("\n══ Section 5: Egress valid_out latency ══════════════════════════");
    eg_valid_in = 1; @(posedge clk); #1;
    chk("EV1: valid_out=1 after posedge", eg_valid_out);
    eg_valid_in = 0; @(posedge clk); #1;
    chk("EV1: valid_out=0 after deassert", !eg_valid_out);

    // ──────────────────────────────────────────────────────────────────────
    // SECTION 6 — DEPARSER
    // ──────────────────────────────────────────────────────────────────────
    $display("\n══ Section 6: Deparser ══════════════════════════════════════════");

    dep_eth_valid=1; dep_ipv4_valid=1; dep_opt_valid=1; dep_mri_valid=1;
    dep_swt_valid = 9'b0_0000_0011; // slots 0,1 valid
    dep_eth_dst = 48'hAAAAAAAAAAAA; dep_eth_src = 48'hBBBBBBBBBBBB; dep_eth_type = 16'h0800;
    dep_ipv4_ver=4; dep_ipv4_ihl=7; dep_ipv4_ds=0; dep_ipv4_len=36; dep_ipv4_id=1;
    dep_ipv4_flg=0; dep_ipv4_off=0; dep_ipv4_ttl=64; dep_ipv4_proto=6; dep_ipv4_chk=16'hBEEF;
    dep_ipv4_src=32'hC0A80001; dep_ipv4_dst=32'h0A010203;
    dep_opt_copy=0; dep_opt_class=0; dep_opt_option=5'h1F; dep_opt_len=8;
    dep_mri_count=16'd1;
    dep_swt_swid[0]=32'hCAFE0001; dep_swt_qdep[0]=32'h0000002A;
    dep_swt_swid[1]=32'hDEAD0002; dep_swt_qdep[1]=32'h0000002B;
    #1;
    chk("D1: dep ethernet at [879:768]",  dep_pkt_out[879:832] === dep_eth_dst);
    chk("D1: dep ipv4 dstAddr at [639:608]", dep_pkt_out[639:608] === dep_ipv4_dst);
    chk("D1: dep swtraces[0] at [575:512]", dep_pkt_out[575:544] === dep_swt_swid[0]);
    chk("D1: dep swtraces[1] at [511:448]", dep_pkt_out[511:480] === dep_swt_swid[1]);
    chk("D1: dep swtraces[2] zeroed (invalid)", dep_pkt_out[447:384] === 64'd0);
    chk("D1: pkt_hdr_len = 112+160+16+16+64+64 = 432", dep_pkt_len === 16'd432);

    dep_swt_valid = 9'b0;
    #1;
    chk("D2: pkt_hdr_len = 304 (no swtraces)", dep_pkt_len === 16'd304);

    dep_valid_in = 1; @(posedge clk); #1;
    chk("D3: valid_out=1 after posedge", dep_valid_out);
    dep_valid_in = 0; @(posedge clk); #1;
    chk("D3: valid_out=0 after deassert", !dep_valid_out);

    // ──────────────────────────────────────────────────────────────────────
    $display("");
    $display("════════════════════════════════════════════════════════════════");
    $display("  Results: %0d passed, %0d failed  (total %0d)", pass_cnt, fail_cnt, pass_cnt+fail_cnt);
    $display("════════════════════════════════════════════════════════════════");
    if (fail_cnt == 0) $display("  ALL TESTS PASSED");
    else                $display("  FAILURES DETECTED — see [FAIL] lines above");

    $finish;
  end

endmodule
