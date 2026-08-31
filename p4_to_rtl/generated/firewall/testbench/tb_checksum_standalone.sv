// ============================================================================
// tb_checksum_standalone.sv -- correctness check for real update_checksum()
// support (emit_processing.py's chk{i}_concat/sum/fold/value wires + the
// out_ipv4_hdrChecksum write in the last pipeline stage). Verifies the RFC
// 1071 one's-complement Internet checksum math against ground truth computed
// independently in Python (not derived from this RTL), using the same
// processing_generated DUT and port-driving idiom as the existing
// tb_firewall.sv (reset -> drive IPv4 fields -> pulse valid_in -> wait 5
// edges for this app's 5-stage pipeline to settle).
//
// Ground truth (computed in Python, RFC 1071):
//   version=4 ihl=5 diffserv=0 totalLen=0x0034 identification=0x1c46
//   flags=3'b010 fragOffset=0 ttl=64 protocol=6
//   srcAddr=0xac100a63 dstAddr=0xac100a0c
//   -> checksum = 0xb1ee
//
// Compile (from this directory):
//   iverilog -g2012 -o sim tb_checksum_standalone.sv \
//     ../processing_generated.sv ../ipv4_lpm_table.sv ../check_ports_table.sv
//   vvp sim
// ============================================================================
`timescale 1ns/1ps

module tb_checksum_standalone;

  localparam CLK_T = 10;
  logic clk = 0;
  always #(CLK_T/2) clk = ~clk;
  logic rst_n;

  logic        pr_valid_in       = 0;
  logic        pr_eth_valid      = 0;
  logic        pr_ipv4_valid     = 0;
  logic        pr_tcp_valid      = 0;

  logic [47:0] pr_eth_dst        = 48'hAABBCCDDEEFF;
  logic [47:0] pr_eth_src        = 48'h112233445566;
  logic [15:0] pr_eth_type       = 16'h0800;
  logic  [3:0] pr_ipv4_ver       = 4'd4;
  logic  [3:0] pr_ipv4_ihl       = 4'd5;
  logic  [7:0] pr_ipv4_ds        = 8'd0;
  logic [15:0] pr_ipv4_len       = 16'h0034;
  logic [15:0] pr_ipv4_id        = 16'h1c46;
  logic  [2:0] pr_ipv4_flg       = 3'b010;
  logic [12:0] pr_ipv4_off       = 13'd0;
  logic  [7:0] pr_ipv4_ttl       = 8'd64;
  logic  [7:0] pr_ipv4_proto     = 8'd6;
  logic [15:0] pr_ipv4_chk       = 16'hDEAD;  // garbage on input -- excluded
                                                // from the field list, must
                                                // be fully overwritten
  logic [31:0] pr_ipv4_src       = 32'hac100a63;
  logic [31:0] pr_ipv4_dst       = 32'hac100a0c;
  logic [15:0] pr_tcp_srcPort    = 0;
  logic [15:0] pr_tcp_dstPort    = 0;
  logic [31:0] pr_tcp_seqNo      = 0;
  logic [31:0] pr_tcp_ackNo      = 0;
  logic  [3:0] pr_tcp_dataOff    = 4'd5;
  logic  [3:0] pr_tcp_res        = 0;
  logic  [0:0] pr_tcp_cwr        = 0;
  logic  [0:0] pr_tcp_ece        = 0;
  logic  [0:0] pr_tcp_urg        = 0;
  logic  [0:0] pr_tcp_ack        = 0;
  logic  [0:0] pr_tcp_psh        = 0;
  logic  [0:0] pr_tcp_rst        = 0;
  logic  [0:0] pr_tcp_syn        = 0;
  logic  [0:0] pr_tcp_fin        = 0;
  logic [15:0] pr_tcp_window     = 0;
  logic [15:0] pr_tcp_checksum   = 0;
  logic [15:0] pr_tcp_urgPtr     = 0;

  logic  [8:0] pr_ingress_port   = 0;
  logic  [8:0] pr_egress_spec_i  = 0;

  logic [15:0] pr_o_ipv4_chk;
  logic        pr_valid_out;

  logic        lpm_cp_en = 0;   logic [3:0] lpm_cp_idx = 0;
  logic [31:0] lpm_cp_key = 0;  logic [5:0] lpm_cp_pfx = 0;
  logic  [1:0] lpm_cp_act = 0;  logic [47:0] lpm_cp_dstM = 0;
  logic  [8:0] lpm_cp_port = 0;
  logic        cp_cp_en = 0;    logic [3:0] cp_cp_idx = 0;
  logic  [8:0] cp_cp_ing = 0;   logic [8:0] cp_cp_egr = 0;
  logic  [0:0] cp_cp_act = 0;   logic [0:0] cp_cp_dir = 0;

  processing_generated proc_dut (
    .clk                               (clk),
    .rst_n                             (rst_n),
    .valid_in                          (pr_valid_in),
    .ethernet_valid                    (pr_eth_valid),
    .ipv4_valid                        (pr_ipv4_valid),
    .tcp_valid                         (pr_tcp_valid),
    .ethernet_dstAddr                  (pr_eth_dst),
    .ethernet_srcAddr                  (pr_eth_src),
    .ethernet_etherType                (pr_eth_type),
    .ipv4_version                      (pr_ipv4_ver),
    .ipv4_ihl                          (pr_ipv4_ihl),
    .ipv4_diffserv                     (pr_ipv4_ds),
    .ipv4_totalLen                     (pr_ipv4_len),
    .ipv4_identification               (pr_ipv4_id),
    .ipv4_flags                        (pr_ipv4_flg),
    .ipv4_fragOffset                   (pr_ipv4_off),
    .ipv4_ttl                          (pr_ipv4_ttl),
    .ipv4_protocol                     (pr_ipv4_proto),
    .ipv4_hdrChecksum                  (pr_ipv4_chk),
    .ipv4_srcAddr                      (pr_ipv4_src),
    .ipv4_dstAddr                      (pr_ipv4_dst),
    .tcp_srcPort                       (pr_tcp_srcPort),
    .tcp_dstPort                       (pr_tcp_dstPort),
    .tcp_seqNo                         (pr_tcp_seqNo),
    .tcp_ackNo                         (pr_tcp_ackNo),
    .tcp_dataOffset                    (pr_tcp_dataOff),
    .tcp_res                           (pr_tcp_res),
    .tcp_cwr                           (pr_tcp_cwr),
    .tcp_ece                           (pr_tcp_ece),
    .tcp_urg                           (pr_tcp_urg),
    .tcp_ack                           (pr_tcp_ack),
    .tcp_psh                           (pr_tcp_psh),
    .tcp_rst                           (pr_tcp_rst),
    .tcp_syn                           (pr_tcp_syn),
    .tcp_fin                           (pr_tcp_fin),
    .tcp_window                        (pr_tcp_window),
    .tcp_checksum                      (pr_tcp_checksum),
    .tcp_urgentPtr                     (pr_tcp_urgPtr),
    .std_meta_ingress_port             (pr_ingress_port),
    .std_meta_egress_spec              (pr_egress_spec_i),
    .out_ethernet_dstAddr              (),
    .out_ethernet_srcAddr              (),
    .out_ethernet_etherType            (),
    .out_ipv4_version                  (),
    .out_ipv4_ihl                      (),
    .out_ipv4_diffserv                 (),
    .out_ipv4_totalLen                 (),
    .out_ipv4_identification           (),
    .out_ipv4_flags                    (),
    .out_ipv4_fragOffset               (),
    .out_ipv4_ttl                      (),
    .out_ipv4_protocol                 (),
    .out_ipv4_hdrChecksum              (pr_o_ipv4_chk),
    .out_ipv4_srcAddr                  (),
    .out_ipv4_dstAddr                  (),
    .out_tcp_srcPort                   (),
    .out_tcp_dstPort                   (),
    .out_tcp_seqNo                     (),
    .out_tcp_ackNo                     (),
    .out_tcp_dataOffset                (),
    .out_tcp_res                       (),
    .out_tcp_cwr                       (),
    .out_tcp_ece                       (),
    .out_tcp_urg                       (),
    .out_tcp_ack                       (),
    .out_tcp_psh                       (),
    .out_tcp_rst                       (),
    .out_tcp_syn                       (),
    .out_tcp_fin                       (),
    .out_tcp_window                    (),
    .out_tcp_checksum                  (),
    .out_tcp_urgentPtr                 (),
    .out_std_meta_egress_spec          (),
    .ipv4_lpm_cp_wr_en                 (lpm_cp_en),
    .ipv4_lpm_cp_wr_idx                (lpm_cp_idx),
    .ipv4_lpm_cp_wr_key_dstAddr        (lpm_cp_key),
    .ipv4_lpm_cp_wr_pfx_len            (lpm_cp_pfx),
    .ipv4_lpm_cp_wr_action             (lpm_cp_act),
    .ipv4_lpm_cp_wr_p_dstAddr          (lpm_cp_dstM),
    .ipv4_lpm_cp_wr_p_port             (lpm_cp_port),
    .check_ports_cp_wr_en              (cp_cp_en),
    .check_ports_cp_wr_idx             (cp_cp_idx),
    .check_ports_cp_wr_key_ingress_port(cp_cp_ing),
    .check_ports_cp_wr_key_egress_spec (cp_cp_egr),
    .check_ports_cp_wr_action          (cp_cp_act),
    .check_ports_cp_wr_p_dir           (cp_cp_dir),
    .ipv4_lpm_hit_out                  (),
    .check_ports_hit_out               (),
    .valid_out                         (pr_valid_out),
    .drop                              ()
  );

  int pass_cnt = 0, fail_cnt = 0;
  task automatic chk(input string name, input logic cond);
    if (cond) begin $display("    [PASS] %s", name); pass_cnt++; end
    else      begin $display("    [FAIL] %s", name); fail_cnt++; end
  endtask

  task do_reset;
    rst_n = 0; pr_valid_in = 0;
    pr_eth_valid = 0; pr_ipv4_valid = 0; pr_tcp_valid = 0;
    repeat(5) @(posedge clk); @(negedge clk);
    rst_n = 1; @(posedge clk); #1;
  endtask

  // Same 5-edge wait as tb_firewall.sv's send_packet -- this app's pipeline
  // is 5 stages deep (4 exact/LPM-match table boundaries).
  task automatic send_packet;
    pr_valid_in=1; @(posedge clk); #1; pr_valid_in=0;
    @(posedge clk); #1;
    @(posedge clk); #1;
    @(posedge clk); #1;
    @(posedge clk); #1;
  endtask

  initial begin
    $display("== tb_checksum_standalone: real update_checksum() regression ==\n");
    do_reset();

    $display("== T1: valid IPv4 header -> real RFC 1071 checksum ==");
    pr_eth_valid = 1; pr_ipv4_valid = 1; pr_tcp_valid = 0;
    send_packet();
    chk("T1: out_ipv4_hdrChecksum == 0xb1ee (ground truth from Python)",
        pr_o_ipv4_chk == 16'hb1ee);
    chk("T1: checksum is NOT just the stale input pass-through (0xdead)",
        pr_o_ipv4_chk != 16'hdead);

    $display("\n== T2: different header content -> different, still-correct checksum ==");
    pr_ipv4_ttl = 8'd32;          // TTL decremented from a different starting value
    pr_ipv4_src = 32'hc0a80101;
    pr_ipv4_dst = 32'hc0a80102;
    send_packet();
    // Ground truth for this second header, independently computed the same
    // way (version=4 ihl=5 diffserv=0 totalLen=0x0034 id=0x1c46 flags=010
    // fragOffset=0 ttl=32 protocol=6 src=0xc0a80101 dst=0xc0a80102):
    chk("T2: checksum updates correctly when header content changes",
        pr_o_ipv4_chk == 16'hbb2a);

    $display("\n== T3: ipv4_valid=0 -> checksum write is skipped (condition gates it) ==");
    pr_ipv4_valid = 0;
    pr_ipv4_chk = 16'hCAFE;
    send_packet();
    chk("T3: with ipv4 invalid, out_ipv4_hdrChecksum is untouched pass-through",
        pr_o_ipv4_chk == 16'hcafe);

    $display("\n================================================================");
    $display("  Results: %0d passed, %0d failed  (total %0d)", pass_cnt, fail_cnt, pass_cnt+fail_cnt);
    $display("================================================================");
    if (fail_cnt == 0) $display("  ALL TESTS PASSED");
    else                $display("  SOME TESTS FAILED");
    $finish;
  end

endmodule
