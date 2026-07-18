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
  input  logic [9:0] ipv4_lpm_cp_wr_idx,
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
  initial begin
    for (int _si = 0; _si < 4096; _si++)
      bloom_filter_1_mem[_si] = 1'b0;
    for (int _si = 0; _si < 4096; _si++)
      bloom_filter_2_mem[_si] = 1'b0;
  end

  // Register read wires (isolated via assign)
  logic [0:0] bloom_filter_1_rd_reg_val_one_0;
  assign bloom_filter_1_rd_reg_val_one_0 = bloom_filter_1_mem[reg_pos_one_0];
  logic [0:0] bloom_filter_2_rd_reg_val_two_0;
  assign bloom_filter_2_rd_reg_val_two_0 = bloom_filter_2_mem[reg_pos_two_0];

  // Table lookup result wires
  logic        ipv4_lpm_hit;
  logic [1:0] ipv4_lpm_act_id;
  logic [47:0] ipv4_lpm_p_dstAddr;
  logic [8:0] ipv4_lpm_p_port;
  logic        check_ports_hit;
  logic [0:0] check_ports_act_id;
  logic [0:0] check_ports_p_dir;

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

  always_comb begin
    drop = 0;
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
    bloom_filter_1_wr_en   = 1'b0;
    bloom_filter_1_wr_addr = '0;
    bloom_filter_1_wr_data = '0;
    bloom_filter_2_wr_en   = 1'b0;
    bloom_filter_2_wr_addr = '0;
    bloom_filter_2_wr_data = '0;

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
    out_tcp_cwr = tcp_cwr;
    out_tcp_ece = tcp_ece;
    out_tcp_urg = tcp_urg;
    out_tcp_ack = tcp_ack;
    out_tcp_psh = tcp_psh;
    out_tcp_rst = tcp_rst;
    out_tcp_syn = tcp_syn;
    out_tcp_fin = tcp_fin;
    out_tcp_window = tcp_window;
    out_tcp_checksum = tcp_checksum;
    out_tcp_urgentPtr = tcp_urgentPtr;

    // apply block
    if (ipv4_valid) begin
      // ipv4_lpm.apply()
      if (ipv4_lpm_hit) begin
        unique case (ipv4_lpm_act_id)
          2'd0: ; // NoAction
          2'd1: begin // ipv4_forward
            out_std_meta_egress_spec = ipv4_lpm_p_port;
            out_ethernet_srcAddr = ethernet_dstAddr;
            out_ethernet_dstAddr = ipv4_lpm_p_dstAddr;
            out_ipv4_ttl = ((ipv4_ttl + 'hFF) & 'hFF);
          end
          2'd2: begin // drop
            drop = 1;
          end
          default: ; // default = drop
        endcase
      end else begin // drop on miss
        drop = 1;
      end
      if (tcp_valid) begin
        direction_0 = 'h00;
        // check_ports.apply()
        if (check_ports_hit) begin
          unique case (check_ports_act_id)
            1'd0: ; // NoAction
            1'd1: begin // set_direction
              direction_0 = check_ports_p_dir;
            end
            default: ; // default = NoAction
          endcase
        end
        if ((direction_0 == 'h00)) begin
          tmp_9 = ipv4_dstAddr;
          tmp_10 = ipv4_srcAddr;
          tmp_11 = tcp_dstPort;
          tmp_12 = tcp_srcPort;
          tmp_13 = ipv4_protocol;
          // hash() stub — XOR-based behavioral approximation
          reg_pos_one_0 = (tmp_9 ^ tmp_10 ^ tmp_11 ^ tmp_12 ^ tmp_13) & 12'hFFF;
          tmp_14 = ipv4_dstAddr;
          tmp_15 = ipv4_srcAddr;
          tmp_16 = tcp_dstPort;
          tmp_17 = tcp_srcPort;
          tmp_18 = ipv4_protocol;
          // hash() stub — XOR-based behavioral approximation
          reg_pos_two_0 = (tmp_14 ^ tmp_15 ^ tmp_16 ^ tmp_17 ^ tmp_18) & 12'hFFF;
          if ((direction_0 == 'h00)) begin
            if ((tcp_syn == 'h01)) begin
              bloom_filter_1_wr_en   = 1'b1;
              bloom_filter_1_wr_addr = reg_pos_one_0;
              bloom_filter_1_wr_data = 'h01;
              bloom_filter_2_wr_en   = 1'b1;
              bloom_filter_2_wr_addr = reg_pos_two_0;
              bloom_filter_2_wr_data = 'h01;
            end
          end
          else begin
            if ((direction_0 == 'h01)) begin
              reg_val_one_0 = bloom_filter_1_rd_reg_val_one_0;
              reg_val_two_0 = bloom_filter_2_rd_reg_val_two_0;
              if (((reg_val_one_0 != 'h01) || (reg_val_two_0 != 'h01))) begin
                drop = 1;
              end
            end
          end
        end
        else begin
          tmp_9 = ipv4_dstAddr;
          tmp_10 = ipv4_srcAddr;
          tmp_11 = tcp_dstPort;
          tmp_12 = tcp_srcPort;
          tmp_13 = ipv4_protocol;
          // hash() stub — XOR-based behavioral approximation
          reg_pos_one_0 = (tmp_9 ^ tmp_10 ^ tmp_11 ^ tmp_12 ^ tmp_13) & 12'hFFF;
          tmp_14 = ipv4_dstAddr;
          tmp_15 = ipv4_srcAddr;
          tmp_16 = tcp_dstPort;
          tmp_17 = tcp_srcPort;
          tmp_18 = ipv4_protocol;
          // hash() stub — XOR-based behavioral approximation
          reg_pos_two_0 = (tmp_14 ^ tmp_15 ^ tmp_16 ^ tmp_17 ^ tmp_18) & 12'hFFF;
          if ((direction_0 == 'h00)) begin
            if ((tcp_syn == 'h01)) begin
              bloom_filter_1_wr_en   = 1'b1;
              bloom_filter_1_wr_addr = reg_pos_one_0;
              bloom_filter_1_wr_data = 'h01;
              bloom_filter_2_wr_en   = 1'b1;
              bloom_filter_2_wr_addr = reg_pos_two_0;
              bloom_filter_2_wr_data = 'h01;
            end
          end
          else begin
            if ((direction_0 == 'h01)) begin
              reg_val_one_0 = bloom_filter_1_rd_reg_val_one_0;
              reg_val_two_0 = bloom_filter_2_rd_reg_val_two_0;
              if (((reg_val_one_0 != 'h01) || (reg_val_two_0 != 'h01))) begin
                drop = 1;
              end
            end
          end
        end
      end
    end
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
    else        valid_out <= valid_in;
  end

endmodule
