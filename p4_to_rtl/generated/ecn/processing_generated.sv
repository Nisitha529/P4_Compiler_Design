module processing_generated (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        valid_in,

  // Header valid flags
  input  logic        ethernet_valid,
  input  logic        ipv4_valid,

  // Header field inputs
  input  logic [47:0] ethernet_dstAddr,
  input  logic [47:0] ethernet_srcAddr,
  input  logic [15:0] ethernet_etherType,
  input  logic [3:0] ipv4_version,
  input  logic [3:0] ipv4_ihl,
  input  logic [5:0] ipv4_diffserv,
  input  logic [1:0] ipv4_ecn,
  input  logic [15:0] ipv4_totalLen,
  input  logic [15:0] ipv4_identification,
  input  logic [2:0] ipv4_flags,
  input  logic [12:0] ipv4_fragOffset,
  input  logic [7:0] ipv4_ttl,
  input  logic [7:0] ipv4_protocol,
  input  logic [15:0] ipv4_hdrChecksum,
  input  logic [31:0] ipv4_srcAddr,
  input  logic [31:0] ipv4_dstAddr,

  // Header valid flag outputs (may be modified by setValid/setInvalid)
  output logic        out_ethernet_valid,
  output logic        out_ipv4_valid,

  // Header field outputs (pass-through, optionally modified)
  output logic [47:0] out_ethernet_dstAddr,
  output logic [47:0] out_ethernet_srcAddr,
  output logic [15:0] out_ethernet_etherType,
  output logic [3:0] out_ipv4_version,
  output logic [3:0] out_ipv4_ihl,
  output logic [5:0] out_ipv4_diffserv,
  output logic [1:0] out_ipv4_ecn,
  output logic [15:0] out_ipv4_totalLen,
  output logic [15:0] out_ipv4_identification,
  output logic [2:0] out_ipv4_flags,
  output logic [12:0] out_ipv4_fragOffset,
  output logic [7:0] out_ipv4_ttl,
  output logic [7:0] out_ipv4_protocol,
  output logic [15:0] out_ipv4_hdrChecksum,
  output logic [31:0] out_ipv4_srcAddr,
  output logic [31:0] out_ipv4_dstAddr,

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

  // Pipeline-stage forwarding registers (one set per exact-match
  // table boundary in the chain)
  logic valid_s1;
  logic out_ethernet_valid_s1;
  logic ethernet_valid_s1;
  logic out_ipv4_valid_s1;
  logic ipv4_valid_s1;
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
  logic [5:0] out_ipv4_diffserv_s1;
  logic [5:0] ipv4_diffserv_s1;
  logic [1:0] out_ipv4_ecn_s1;
  logic [1:0] ipv4_ecn_s1;
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
  logic [8:0] out_std_meta_egress_spec_s1;
  logic drop_s1;
  logic __stage_cond_0_r;
  logic valid_s2;
  logic out_ethernet_valid_s2;
  logic ethernet_valid_s2;
  logic out_ipv4_valid_s2;
  logic ipv4_valid_s2;
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
  logic [5:0] out_ipv4_diffserv_s2;
  logic [5:0] ipv4_diffserv_s2;
  logic [1:0] out_ipv4_ecn_s2;
  logic [1:0] ipv4_ecn_s2;
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
  logic [8:0] out_std_meta_egress_spec_s2;
  logic drop_s2;

  // Pool-A (out_*/drop) working copies -- every stage except the
  // last, which drives the real output ports directly
  logic out_ethernet_valid__st0;
  logic out_ipv4_valid__st0;
  logic [47:0] out_ethernet_dstAddr__st0;
  logic [47:0] out_ethernet_srcAddr__st0;
  logic [15:0] out_ethernet_etherType__st0;
  logic [3:0] out_ipv4_version__st0;
  logic [3:0] out_ipv4_ihl__st0;
  logic [5:0] out_ipv4_diffserv__st0;
  logic [1:0] out_ipv4_ecn__st0;
  logic [15:0] out_ipv4_totalLen__st0;
  logic [15:0] out_ipv4_identification__st0;
  logic [2:0] out_ipv4_flags__st0;
  logic [12:0] out_ipv4_fragOffset__st0;
  logic [7:0] out_ipv4_ttl__st0;
  logic [7:0] out_ipv4_protocol__st0;
  logic [15:0] out_ipv4_hdrChecksum__st0;
  logic [31:0] out_ipv4_srcAddr__st0;
  logic [31:0] out_ipv4_dstAddr__st0;
  logic [8:0] out_std_meta_egress_spec__st0;
  logic drop__st0;
  logic out_ethernet_valid__st1;
  logic out_ipv4_valid__st1;
  logic [47:0] out_ethernet_dstAddr__st1;
  logic [47:0] out_ethernet_srcAddr__st1;
  logic [15:0] out_ethernet_etherType__st1;
  logic [3:0] out_ipv4_version__st1;
  logic [3:0] out_ipv4_ihl__st1;
  logic [5:0] out_ipv4_diffserv__st1;
  logic [1:0] out_ipv4_ecn__st1;
  logic [15:0] out_ipv4_totalLen__st1;
  logic [15:0] out_ipv4_identification__st1;
  logic [2:0] out_ipv4_flags__st1;
  logic [12:0] out_ipv4_fragOffset__st1;
  logic [7:0] out_ipv4_ttl__st1;
  logic [7:0] out_ipv4_protocol__st1;
  logic [15:0] out_ipv4_hdrChecksum__st1;
  logic [31:0] out_ipv4_srcAddr__st1;
  logic [31:0] out_ipv4_dstAddr__st1;
  logic [8:0] out_std_meta_egress_spec__st1;
  logic drop__st1;

  // Pool-B (locals/meta shadow/raw hdr+std_meta reads) working
  // copies -- every stage except the first, which reads live inputs
  logic ethernet_valid__st1;
  logic ipv4_valid__st1;
  logic [47:0] ethernet_dstAddr__st1;
  logic [47:0] ethernet_srcAddr__st1;
  logic [15:0] ethernet_etherType__st1;
  logic [3:0] ipv4_version__st1;
  logic [3:0] ipv4_ihl__st1;
  logic [5:0] ipv4_diffserv__st1;
  logic [1:0] ipv4_ecn__st1;
  logic [15:0] ipv4_totalLen__st1;
  logic [15:0] ipv4_identification__st1;
  logic [2:0] ipv4_flags__st1;
  logic [12:0] ipv4_fragOffset__st1;
  logic [7:0] ipv4_ttl__st1;
  logic [7:0] ipv4_protocol__st1;
  logic [15:0] ipv4_hdrChecksum__st1;
  logic [31:0] ipv4_srcAddr__st1;
  logic [31:0] ipv4_dstAddr__st1;
  logic ethernet_valid__st2;
  logic ipv4_valid__st2;
  logic [47:0] ethernet_dstAddr__st2;
  logic [47:0] ethernet_srcAddr__st2;
  logic [15:0] ethernet_etherType__st2;
  logic [3:0] ipv4_version__st2;
  logic [3:0] ipv4_ihl__st2;
  logic [5:0] ipv4_diffserv__st2;
  logic [1:0] ipv4_ecn__st2;
  logic [15:0] ipv4_totalLen__st2;
  logic [15:0] ipv4_identification__st2;
  logic [2:0] ipv4_flags__st2;
  logic [12:0] ipv4_fragOffset__st2;
  logic [7:0] ipv4_ttl__st2;
  logic [7:0] ipv4_protocol__st2;
  logic [15:0] ipv4_hdrChecksum__st2;
  logic [31:0] ipv4_srcAddr__st2;
  logic [31:0] ipv4_dstAddr__st2;

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

    // Standard metadata defaults
    out_std_meta_egress_spec__st0 = 9'b0;

    // Header valid flag pass-through defaults
    out_ethernet_valid__st0 = ethernet_valid;
    out_ipv4_valid__st0 = ipv4_valid;

    // Header field pass-through defaults
    out_ethernet_dstAddr__st0 = ethernet_dstAddr;
    out_ethernet_srcAddr__st0 = ethernet_srcAddr;
    out_ethernet_etherType__st0 = ethernet_etherType;
    out_ipv4_version__st0 = ipv4_version;
    out_ipv4_ihl__st0 = ipv4_ihl;
    out_ipv4_diffserv__st0 = ipv4_diffserv;
    out_ipv4_ecn__st0 = ipv4_ecn;
    out_ipv4_totalLen__st0 = ipv4_totalLen;
    out_ipv4_identification__st0 = ipv4_identification;
    out_ipv4_flags__st0 = ipv4_flags;
    out_ipv4_fragOffset__st0 = ipv4_fragOffset;
    out_ipv4_ttl__st0 = ipv4_ttl;
    out_ipv4_protocol__st0 = ipv4_protocol;
    out_ipv4_hdrChecksum__st0 = ipv4_hdrChecksum;
    out_ipv4_srcAddr__st0 = ipv4_srcAddr;
    out_ipv4_dstAddr__st0 = ipv4_dstAddr;

    // apply block (stage 0 of 2)
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
      out_ethernet_valid_s1 <= out_ethernet_valid__st0;
      ethernet_valid_s1 <= ethernet_valid;
      out_ipv4_valid_s1 <= out_ipv4_valid__st0;
      ipv4_valid_s1 <= ipv4_valid;
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
      out_ipv4_ecn_s1 <= out_ipv4_ecn__st0;
      ipv4_ecn_s1 <= ipv4_ecn;
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
      out_std_meta_egress_spec_s1 <= out_std_meta_egress_spec__st0;
      __stage_cond_0_r <= (ipv4_valid);
    end
  end

  // ---- Pipeline stage 1 (registered 1 cycle(s) after stage 0) ----
  always_comb begin
    drop__st1 = drop_s1;
    out_ethernet_valid__st1 = out_ethernet_valid_s1;
    ethernet_valid__st1 = ethernet_valid_s1;
    out_ipv4_valid__st1 = out_ipv4_valid_s1;
    ipv4_valid__st1 = ipv4_valid_s1;
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
    out_ipv4_ecn__st1 = out_ipv4_ecn_s1;
    ipv4_ecn__st1 = ipv4_ecn_s1;
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
      out_ethernet_valid_s2 <= out_ethernet_valid__st1;
      ethernet_valid_s2 <= ethernet_valid__st1;
      out_ipv4_valid_s2 <= out_ipv4_valid__st1;
      ipv4_valid_s2 <= ipv4_valid__st1;
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
      out_ipv4_ecn_s2 <= out_ipv4_ecn__st1;
      ipv4_ecn_s2 <= ipv4_ecn__st1;
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
      out_std_meta_egress_spec_s2 <= out_std_meta_egress_spec__st1;
    end
  end

  // ---- Pipeline stage 2 (registered 2 cycle(s) after stage 0) ----
  always_comb begin
    drop = drop_s2;
    out_ethernet_valid = out_ethernet_valid_s2;
    ethernet_valid__st2 = ethernet_valid_s2;
    out_ipv4_valid = out_ipv4_valid_s2;
    ipv4_valid__st2 = ipv4_valid_s2;
    out_ethernet_dstAddr = out_ethernet_dstAddr_s2;
    ethernet_dstAddr__st2 = ethernet_dstAddr_s2;
    out_ethernet_srcAddr = out_ethernet_srcAddr_s2;
    ethernet_srcAddr__st2 = ethernet_srcAddr_s2;
    out_ethernet_etherType = out_ethernet_etherType_s2;
    ethernet_etherType__st2 = ethernet_etherType_s2;
    out_ipv4_version = out_ipv4_version_s2;
    ipv4_version__st2 = ipv4_version_s2;
    out_ipv4_ihl = out_ipv4_ihl_s2;
    ipv4_ihl__st2 = ipv4_ihl_s2;
    out_ipv4_diffserv = out_ipv4_diffserv_s2;
    ipv4_diffserv__st2 = ipv4_diffserv_s2;
    out_ipv4_ecn = out_ipv4_ecn_s2;
    ipv4_ecn__st2 = ipv4_ecn_s2;
    out_ipv4_totalLen = out_ipv4_totalLen_s2;
    ipv4_totalLen__st2 = ipv4_totalLen_s2;
    out_ipv4_identification = out_ipv4_identification_s2;
    ipv4_identification__st2 = ipv4_identification_s2;
    out_ipv4_flags = out_ipv4_flags_s2;
    ipv4_flags__st2 = ipv4_flags_s2;
    out_ipv4_fragOffset = out_ipv4_fragOffset_s2;
    ipv4_fragOffset__st2 = ipv4_fragOffset_s2;
    out_ipv4_ttl = out_ipv4_ttl_s2;
    ipv4_ttl__st2 = ipv4_ttl_s2;
    out_ipv4_protocol = out_ipv4_protocol_s2;
    ipv4_protocol__st2 = ipv4_protocol_s2;
    out_ipv4_hdrChecksum = out_ipv4_hdrChecksum_s2;
    ipv4_hdrChecksum__st2 = ipv4_hdrChecksum_s2;
    out_ipv4_srcAddr = out_ipv4_srcAddr_s2;
    ipv4_srcAddr__st2 = ipv4_srcAddr_s2;
    out_ipv4_dstAddr = out_ipv4_dstAddr_s2;
    ipv4_dstAddr__st2 = ipv4_dstAddr_s2;
    out_std_meta_egress_spec = out_std_meta_egress_spec_s2;

    // apply block (stage 2 of 2)
    if (__stage_cond_0_r) begin
      // ipv4_lpm.apply()
      if (ipv4_lpm_hit) begin
        unique case (ipv4_lpm_act_id)
          2'd0: ; // NoAction
          2'd1: begin // ipv4_forward
            out_std_meta_egress_spec = ipv4_lpm_p_port;
            out_ethernet_srcAddr = ethernet_dstAddr__st2;
            out_ethernet_dstAddr = ipv4_lpm_p_dstAddr;
            out_ipv4_ttl = ((ipv4_ttl__st2 + 'hFF) & 'hFF);
          end
          2'd2: begin // drop
            drop = 1;
          end
          default: ; // default = NoAction
        endcase
      end
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) valid_out <= 0;
    else        valid_out <= valid_s2;
  end

endmodule
