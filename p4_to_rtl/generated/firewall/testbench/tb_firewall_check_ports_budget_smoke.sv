// ============================================================================
// tb_firewall_check_ports_budget_smoke.sv -- opt-in exact-match tag-compare
// split cross-file invariant check (Phase 6, architecture-redesign effort).
// NOT a replacement for tb_firewall.sv's cycle-exact functional regression
// suite, and does not edit it. tb_check_ports_table_standalone.sv already
// isolates the table module itself; this one drives the FULL
// processing_generated pipeline (compiled from the same
// --target-freq-mhz-generated sources) to catch a drift between
// emit_table.py's actual inserted-register count and
// emit_processing.py's table_noop_stages count for check_ports specifically
// -- a drift there wouldn't crash, it would silently read hit/action_id one
// cycle too early. Deliberately does NOT assert an exact cycle count: it
// polls for valid_out within a generous, budget-independent bound.
//
// Unlike tb_firewall_budget_smoke.sv (which deliberately leaves check_ports
// unconfigured to stay scoped to the LPM path), this file configures BOTH
// ipv4_lpm and check_ports. Note: std_meta_egress_spec is wired as a plain
// input port to processing_generated, not forwarded from ipv4_forward's
// own write to standard_metadata.egress_spec (that write only reaches
// out_std_meta_egress_spec, the module's output) -- confirmed by reading
// tb_firewall.sv's own passing test suite, which always drives
// pr_egress_spec_i directly to whatever value check_ports needs to look
// up, never relying on ipv4_lpm's action to produce it. This file follows
// the same pattern. Observes {table}_hit_out directly (every table gets
// this port already) rather than unwinding firewall's full bloom-filter/
// SYN logic, which is out of scope for what this file tests.
//
// Compile (from this directory, against sources generated with
// `python3 main.py firewall --target-freq-mhz 400 --device artix7`):
//   iverilog -g2012 -o sim tb_firewall_check_ports_budget_smoke.sv \
//     ../processing_generated.sv ../ipv4_lpm_table.sv ../check_ports_table.sv
//   vvp sim
// ============================================================================
`timescale 1ns/1ps

module tb_firewall_check_ports_budget_smoke;

  localparam CLK_T = 10;
  logic clk = 0;
  always #(CLK_T/2) clk = ~clk;
  logic rst_n;

  localparam int MAX_WAIT_CYCLES = 48;

  logic        pr_valid_in       = 0;
  logic        pr_eth_valid      = 1;
  logic        pr_ipv4_valid     = 1;
  logic        pr_tcp_valid      = 1;

  logic [47:0] pr_eth_dst        = 48'hAABBCCDDEEFF;
  logic [47:0] pr_eth_src        = 48'h112233445566;
  logic [15:0] pr_eth_type       = 16'h0800;
  logic  [3:0] pr_ipv4_ver       = 4;
  logic  [3:0] pr_ipv4_ihl       = 5;
  logic  [7:0] pr_ipv4_ds        = 0;
  logic [15:0] pr_ipv4_len       = 40;
  logic [15:0] pr_ipv4_id        = 1;
  logic  [2:0] pr_ipv4_flg       = 3'b010;
  logic [12:0] pr_ipv4_off       = 0;
  logic  [7:0] pr_ipv4_ttl       = 64;
  logic  [7:0] pr_ipv4_proto     = 8'd6;
  logic [15:0] pr_ipv4_chk       = 16'hBEEF;
  logic [31:0] pr_ipv4_src       = 32'hC0A80001;
  logic [31:0] pr_ipv4_dst       = 32'hC0A80005;
  logic [15:0] pr_tcp_srcPort    = 16'h1234;
  logic [15:0] pr_tcp_dstPort    = 16'h0050;
  logic [31:0] pr_tcp_seqNo      = 0;
  logic [31:0] pr_tcp_ackNo      = 0;
  logic  [3:0] pr_tcp_dataOff    = 5;
  logic  [3:0] pr_tcp_res        = 0;
  logic  [0:0] pr_tcp_cwr        = 0;
  logic  [0:0] pr_tcp_ece        = 0;
  logic  [0:0] pr_tcp_urg        = 0;
  logic  [0:0] pr_tcp_ack        = 0;
  logic  [0:0] pr_tcp_psh        = 0;
  logic  [0:0] pr_tcp_rst        = 0;
  logic  [0:0] pr_tcp_syn        = 0;
  logic  [0:0] pr_tcp_fin        = 0;
  logic [15:0] pr_tcp_window     = 16'h7FFF;
  logic [15:0] pr_tcp_checksum   = 0;
  logic [15:0] pr_tcp_urgPtr     = 0;

  logic  [8:0] pr_ingress_port   = 0;
  logic  [8:0] pr_egress_spec_i  = 0;

  logic [47:0] pr_o_eth_dst, pr_o_eth_src;
  logic [15:0] pr_o_eth_type;
  logic  [7:0] pr_o_ipv4_ds, pr_o_ipv4_ttl, pr_o_ipv4_proto;
  logic [31:0] pr_o_ipv4_src, pr_o_ipv4_dst;
  logic  [3:0] pr_o_ipv4_ver, pr_o_ipv4_ihl;
  logic [15:0] pr_o_ipv4_len, pr_o_ipv4_id, pr_o_ipv4_chk;
  logic  [2:0] pr_o_ipv4_flg;
  logic [12:0] pr_o_ipv4_off;
  logic  [0:0] pr_o_tcp_syn, pr_o_tcp_ack, pr_o_tcp_rst, pr_o_tcp_fin;
  logic  [8:0] pr_o_egress_spec;
  logic        pr_valid_out, pr_drop;
  logic        pr_ipv4_lpm_hit_out, pr_check_ports_hit_out;

  logic        lpm_cp_en    = 0;
  logic  [3:0] lpm_cp_idx   = 0;
  logic [31:0] lpm_cp_key   = 0;
  logic  [5:0] lpm_cp_pfx   = 0;
  logic  [1:0] lpm_cp_act   = 0;
  logic [47:0] lpm_cp_dstM  = 0;
  logic  [8:0] lpm_cp_port  = 0;

  logic        cp_cp_en     = 0;
  logic  [3:0] cp_cp_idx    = 0;
  logic  [8:0] cp_cp_ing    = 0;
  logic  [8:0] cp_cp_egr    = 0;
  logic  [0:0] cp_cp_act    = 0;
  logic  [0:0] cp_cp_dir    = 0;

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
    .out_ethernet_dstAddr              (pr_o_eth_dst),
    .out_ethernet_srcAddr              (pr_o_eth_src),
    .out_ethernet_etherType            (pr_o_eth_type),
    .out_ipv4_version                  (pr_o_ipv4_ver),
    .out_ipv4_ihl                      (pr_o_ipv4_ihl),
    .out_ipv4_diffserv                 (pr_o_ipv4_ds),
    .out_ipv4_totalLen                 (pr_o_ipv4_len),
    .out_ipv4_identification           (pr_o_ipv4_id),
    .out_ipv4_flags                    (pr_o_ipv4_flg),
    .out_ipv4_fragOffset               (pr_o_ipv4_off),
    .out_ipv4_ttl                      (pr_o_ipv4_ttl),
    .out_ipv4_protocol                 (pr_o_ipv4_proto),
    .out_ipv4_hdrChecksum              (pr_o_ipv4_chk),
    .out_ipv4_srcAddr                  (pr_o_ipv4_src),
    .out_ipv4_dstAddr                  (pr_o_ipv4_dst),
    .out_tcp_srcPort                   (),
    .out_tcp_dstPort                   (),
    .out_tcp_seqNo                     (),
    .out_tcp_ackNo                     (),
    .out_tcp_dataOffset                (),
    .out_tcp_res                       (),
    .out_tcp_cwr                       (),
    .out_tcp_ece                       (),
    .out_tcp_urg                       (),
    .out_tcp_ack                       (pr_o_tcp_ack),
    .out_tcp_psh                       (),
    .out_tcp_rst                       (pr_o_tcp_rst),
    .out_tcp_syn                       (pr_o_tcp_syn),
    .out_tcp_fin                       (pr_o_tcp_fin),
    .out_tcp_window                    (),
    .out_tcp_checksum                  (),
    .out_tcp_urgentPtr                 (),
    .out_std_meta_egress_spec          (pr_o_egress_spec),
    .ipv4_lpm_hit_out                  (pr_ipv4_lpm_hit_out),
    .check_ports_hit_out               (pr_check_ports_hit_out),
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
    .valid_out                         (pr_valid_out),
    .drop                              (pr_drop)
  );

  int pass_cnt = 0, fail_cnt = 0;

  task automatic chk(input string name, input logic cond);
    if (cond) begin $display("    [PASS] %s", name); pass_cnt++; end
    else      begin $display("    [FAIL] %s", name); fail_cnt++; end
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

  task check_ports_write(input [9:0] idx, input [8:0] ing, input [8:0] egr,
                          input [0:0] dir);
    @(negedge clk);
    cp_cp_idx=idx; cp_cp_ing=ing; cp_cp_egr=egr;
    cp_cp_act=1'b1; cp_cp_dir=dir;
    cp_cp_en=1;
    @(posedge clk); #1;
    cp_cp_en=0;
  endtask

  task automatic send_and_wait(output logic seen);
    int i;
    seen = 0;
    pr_valid_in = 1; @(posedge clk); #1; pr_valid_in = 0;
    i = 0;
    while (i < MAX_WAIT_CYCLES && !seen) begin
      if (pr_valid_out) seen = 1;
      else begin
        @(posedge clk); #1;
        i = i + 1;
      end
    end
  endtask

  logic got_valid;

  initial begin
    rst_n = 0;
    repeat (5) @(posedge clk); @(negedge clk);
    rst_n = 1; @(posedge clk); #1;

    $display("== firewall check_ports budget-smoke check (opt-in tag-compare split) ==");

    // ipv4_lpm: 192.168.0.0/24 -> ipv4_forward, port=5.
    lpm_write(0, 32'hC0A80000, 6'd24, 2'd1, 48'hAABBCCDDEEFF, 9'd5);
    // check_ports: ingress_port=1, egress_spec=5 -> set_direction(dir=1).
    check_ports_write(0, 9'd1, 9'd5, 1'b1);

    // T1: matching (ingress_port, egress_spec) -> both tables hit.
    // pr_egress_spec_i drives std_meta_egress_spec directly (see file
    // header) -- set to match the check_ports entry, same pattern
    // tb_firewall.sv's own passing tests use.
    pr_ingress_port  = 9'd1;
    pr_egress_spec_i = 9'd5;
    pr_ipv4_dst = 32'hC0A80005; // inside the /24, forwarded with port=5
    send_and_wait(got_valid);
    chk("T1: valid_out seen within bound", got_valid);
    if (got_valid) begin
      chk("T1: ipv4_lpm hit", pr_ipv4_lpm_hit_out === 1'b1);
      chk("T1: check_ports hit", pr_check_ports_hit_out === 1'b1);
      chk("T1: egress_spec == 5", pr_o_egress_spec === 9'd5);
    end

    // T2: different ingress_port -> ipv4_lpm still hits (independent key),
    // but check_ports misses (its own key no longer tag-matches).
    pr_ingress_port = 9'd7;
    send_and_wait(got_valid);
    chk("T2: valid_out seen within bound", got_valid);
    if (got_valid) begin
      chk("T2: ipv4_lpm still hit", pr_ipv4_lpm_hit_out === 1'b1);
      chk("T2: check_ports miss", pr_check_ports_hit_out === 1'b0);
    end

    $display("");
    $display("========================================");
    $display("  Results: %0d passed, %0d failed (total %0d)", pass_cnt, fail_cnt, pass_cnt + fail_cnt);
    $display("========================================");
    if (fail_cnt == 0) $display("  ALL TESTS PASSED");
    else $display("  SOME TESTS FAILED");

    $finish;
  end

endmodule
