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

  output logic        valid_out,
  output logic        drop
);

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

  always_comb begin
    drop = 0;

    // Standard metadata defaults
    out_std_meta_egress_spec = 9'b0;

    // pass-through defaults
    out_ethernet_dstAddr = ethernet_dstAddr;
    out_ethernet_srcAddr = ethernet_srcAddr;
    out_ethernet_etherType = ethernet_etherType;
    out_ipv4_version = ipv4_version;
    out_ipv4_ihl = ipv4_ihl;
    out_ipv4_diffserv = ipv4_diffserv;
    out_ipv4_ecn = ipv4_ecn;
    out_ipv4_totalLen = ipv4_totalLen;
    out_ipv4_identification = ipv4_identification;
    out_ipv4_flags = ipv4_flags;
    out_ipv4_fragOffset = ipv4_fragOffset;
    out_ipv4_ttl = ipv4_ttl;
    out_ipv4_protocol = ipv4_protocol;
    out_ipv4_hdrChecksum = ipv4_hdrChecksum;
    out_ipv4_srcAddr = ipv4_srcAddr;
    out_ipv4_dstAddr = ipv4_dstAddr;

    // apply block
    if (ipv4_valid) begin
      if (ipv4_protocol == 8'd17) begin
        // expedited_forwarding()
        out_ipv4_diffserv = 46;
      end
      else begin
        if (ipv4_protocol == 8'd6) begin
          // voice_admit()
          out_ipv4_diffserv = 44;
        end
      end
      // ipv4_lpm.apply()
      if (ipv4_lpm_hit) begin
        unique case (ipv4_lpm_act_id)
          2'd0: ; // NoAction
          2'd1: begin // ipv4_forward
            out_std_meta_egress_spec = ipv4_lpm_p_port;
            out_ethernet_srcAddr = ethernet_dstAddr;
            out_ethernet_dstAddr = ipv4_lpm_p_dstAddr;
            out_ipv4_ttl = ipv4_ttl - 1;
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
    else        valid_out <= valid_in;
  end

endmodule
