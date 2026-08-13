// ============================================================================
// tb_ecn.sv — Comprehensive self-checking testbench for ecn.p4
//
// Pipeline: V1Switch → MyIngress (processing_generated) → MyEgress
//           (egress_processing_generated)
//
// P4 ecn semantics under test:
//   Ingress: ipv4_lpm table (LPM on hdr.ipv4.dstAddr), applied when
//     hdr.ipv4.isValid(). default_action = NoAction() -- unlike firewall/
//     basic_tunnel, a MISS here is a silent pass-through, not a drop.
//   Egress: if (ecn==1 || ecn==2) && enq_qdepth>=10, mark ecn=3 (CE).
//     ECT(0)=1 and ECT(1)=2 are both markable; non-ECT (0) and already-CE
//     (3) must be left untouched regardless of qdepth.
//
// Ingress n_bounds=2 (1 keyed table) -> valid_out 3 cycles after valid_in.
// Egress has no keyed tables -> valid_out 1 cycle after valid_in (plain
// combinational apply + one output register).
//
// Compile (from this directory):
//   iverilog -g2012 -o sim tb_ecn.sv \
//     ../parser_generated.sv ../processing_generated.sv \
//     ../egress_processing_generated.sv ../deparser_generated.sv \
//     ../ipv4_lpm_table.sv
//   vvp sim
// ============================================================================
`timescale 1ns/1ps

module tb_ecn;

  // ── Clock ──────────────────────────────────────────────────────────────
  localparam CLK_T = 10;
  logic clk = 0;
  always #(CLK_T/2) clk = ~clk;
  logic rst_n;

  // ==========================================================================
  // 1.  PARSER DUT
  // ==========================================================================
  logic        p_valid_in  = 0;
  logic [15:0] p_eth_type  = 0;
  logic        p_ext_eth, p_ext_ipv4, p_done;

  parser_generated parser_dut (
    .clk               (clk),
    .rst_n             (rst_n),
    .valid_in          (p_valid_in),
    .ethernet_etherType(p_eth_type),
    .extract_ethernet  (p_ext_eth),
    .extract_ipv4      (p_ext_ipv4),
    .done              (p_done)
  );

  // ==========================================================================
  // 2.  INGRESS PROCESSING DUT
  // ==========================================================================
  logic        pr_valid_in   = 0;
  logic        pr_eth_valid  = 1;
  logic        pr_ipv4_valid = 1;

  logic [47:0] pr_eth_dst  = 48'hAABBCCDDEEFF;
  logic [47:0] pr_eth_src  = 48'h112233445566;
  logic [15:0] pr_eth_type = 16'h0800;
  logic  [3:0] pr_ipv4_ver = 4;
  logic  [3:0] pr_ipv4_ihl = 5;
  logic  [5:0] pr_ipv4_ds  = 0;
  logic  [1:0] pr_ipv4_ecn = 0;
  logic [15:0] pr_ipv4_len = 20;
  logic [15:0] pr_ipv4_id  = 1;
  logic  [2:0] pr_ipv4_flg = 0;
  logic [12:0] pr_ipv4_off = 0;
  logic  [7:0] pr_ipv4_ttl = 64;
  logic  [7:0] pr_ipv4_proto = 6;
  logic [15:0] pr_ipv4_chk = 16'hBEEF;
  logic [31:0] pr_ipv4_src = 32'hC0A80001;
  logic [31:0] pr_ipv4_dst = 32'h0A000001;

  logic [47:0] pr_o_eth_dst, pr_o_eth_src;
  logic [1:0]  pr_o_ipv4_ecn;
  logic [7:0]  pr_o_ipv4_ttl;
  logic [8:0]  pr_o_egress_spec;
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
    .clk                       (clk),
    .rst_n                     (rst_n),
    .valid_in                  (pr_valid_in),
    .ethernet_valid            (pr_eth_valid),
    .ipv4_valid                (pr_ipv4_valid),
    .ethernet_dstAddr          (pr_eth_dst),
    .ethernet_srcAddr          (pr_eth_src),
    .ethernet_etherType        (pr_eth_type),
    .ipv4_version              (pr_ipv4_ver),
    .ipv4_ihl                  (pr_ipv4_ihl),
    .ipv4_diffserv             (pr_ipv4_ds),
    .ipv4_ecn                  (pr_ipv4_ecn),
    .ipv4_totalLen             (pr_ipv4_len),
    .ipv4_identification       (pr_ipv4_id),
    .ipv4_flags                (pr_ipv4_flg),
    .ipv4_fragOffset           (pr_ipv4_off),
    .ipv4_ttl                  (pr_ipv4_ttl),
    .ipv4_protocol             (pr_ipv4_proto),
    .ipv4_hdrChecksum          (pr_ipv4_chk),
    .ipv4_srcAddr              (pr_ipv4_src),
    .ipv4_dstAddr              (pr_ipv4_dst),
    .out_ethernet_valid        (),
    .out_ipv4_valid            (),
    .out_ethernet_dstAddr      (pr_o_eth_dst),
    .out_ethernet_srcAddr      (pr_o_eth_src),
    .out_ethernet_etherType    (),
    .out_ipv4_version          (),
    .out_ipv4_ihl              (),
    .out_ipv4_diffserv         (),
    .out_ipv4_ecn              (pr_o_ipv4_ecn),
    .out_ipv4_totalLen         (),
    .out_ipv4_identification   (),
    .out_ipv4_flags            (),
    .out_ipv4_fragOffset       (),
    .out_ipv4_ttl              (pr_o_ipv4_ttl),
    .out_ipv4_protocol         (),
    .out_ipv4_hdrChecksum      (),
    .out_ipv4_srcAddr          (),
    .out_ipv4_dstAddr          (),
    .out_std_meta_egress_spec  (pr_o_egress_spec),
    .ipv4_lpm_cp_wr_en         (lpm_cp_en),
    .ipv4_lpm_cp_wr_idx        (lpm_cp_idx),
    .ipv4_lpm_cp_wr_key_dstAddr(lpm_cp_key),
    .ipv4_lpm_cp_wr_pfx_len    (lpm_cp_pfx),
    .ipv4_lpm_cp_wr_action     (lpm_cp_act),
    .ipv4_lpm_cp_wr_p_dstAddr  (lpm_cp_dstM),
    .ipv4_lpm_cp_wr_p_port     (lpm_cp_port),
    .ipv4_lpm_hit_out          (pr_lpm_hit_out),
    .valid_out                 (pr_valid_out),
    .drop                      (pr_drop)
  );

  // ==========================================================================
  // 3.  EGRESS PROCESSING DUT
  // ==========================================================================
  logic        eg_valid_in    = 0;
  logic        eg_eth_valid   = 1;
  logic        eg_ipv4_valid  = 1;
  logic [1:0]  eg_ipv4_ecn    = 0;
  logic [18:0] eg_qdepth      = 0;
  logic [1:0]  eg_o_ipv4_ecn;
  logic        eg_valid_out, eg_drop;

  // Unused pass-through inputs, tied to benign constants.
  logic [47:0] eg_eth_dst = 0, eg_eth_src = 0;
  logic [15:0] eg_eth_type = 0;
  logic  [3:0] eg_ipv4_ver = 0, eg_ipv4_ihl = 0;
  logic  [5:0] eg_ipv4_ds = 0;
  logic [15:0] eg_ipv4_len = 0, eg_ipv4_id = 0;
  logic  [2:0] eg_ipv4_flg = 0;
  logic [12:0] eg_ipv4_off = 0;
  logic  [7:0] eg_ipv4_ttl = 0, eg_ipv4_proto = 0;
  logic [15:0] eg_ipv4_chk = 0;
  logic [31:0] eg_ipv4_src = 0, eg_ipv4_dst = 0;

  egress_processing_generated egress_dut (
    .clk                    (clk),
    .rst_n                  (rst_n),
    .valid_in               (eg_valid_in),
    .ethernet_valid         (eg_eth_valid),
    .ipv4_valid             (eg_ipv4_valid),
    .ethernet_dstAddr       (eg_eth_dst),
    .ethernet_srcAddr       (eg_eth_src),
    .ethernet_etherType     (eg_eth_type),
    .ipv4_version           (eg_ipv4_ver),
    .ipv4_ihl               (eg_ipv4_ihl),
    .ipv4_diffserv          (eg_ipv4_ds),
    .ipv4_ecn               (eg_ipv4_ecn),
    .ipv4_totalLen          (eg_ipv4_len),
    .ipv4_identification    (eg_ipv4_id),
    .ipv4_flags             (eg_ipv4_flg),
    .ipv4_fragOffset        (eg_ipv4_off),
    .ipv4_ttl               (eg_ipv4_ttl),
    .ipv4_protocol          (eg_ipv4_proto),
    .ipv4_hdrChecksum       (eg_ipv4_chk),
    .ipv4_srcAddr           (eg_ipv4_src),
    .ipv4_dstAddr           (eg_ipv4_dst),
    .std_meta_enq_qdepth    (eg_qdepth),
    .out_ethernet_valid     (),
    .out_ipv4_valid         (),
    .out_ethernet_dstAddr   (),
    .out_ethernet_srcAddr   (),
    .out_ethernet_etherType (),
    .out_ipv4_version       (),
    .out_ipv4_ihl           (),
    .out_ipv4_diffserv      (),
    .out_ipv4_ecn           (eg_o_ipv4_ecn),
    .out_ipv4_totalLen      (),
    .out_ipv4_identification(),
    .out_ipv4_flags         (),
    .out_ipv4_fragOffset    (),
    .out_ipv4_ttl           (),
    .out_ipv4_protocol      (),
    .out_ipv4_hdrChecksum   (),
    .out_ipv4_srcAddr       (),
    .out_ipv4_dstAddr       (),
    .valid_out              (eg_valid_out),
    .drop                   (eg_drop)
  );

  // ==========================================================================
  // 4.  DEPARSER DUT — Ethernet(112b) + IPv4(160b) = 272b
  // ==========================================================================
  localparam DEP_W = 272;

  logic        dep_valid_in   = 0;
  logic        dep_eth_valid  = 0;
  logic        dep_ipv4_valid = 0;
  logic [47:0] dep_eth_dst = 0; logic [47:0] dep_eth_src = 0;
  logic [15:0] dep_eth_type = 0;
  logic  [3:0] dep_ipv4_ver = 0; logic  [3:0] dep_ipv4_ihl = 0;
  logic  [5:0] dep_ipv4_ds = 0;  logic  [1:0] dep_ipv4_ecn = 0;
  logic [15:0] dep_ipv4_len = 0; logic [15:0] dep_ipv4_id  = 0;
  logic  [2:0] dep_ipv4_flg = 0; logic [12:0] dep_ipv4_off = 0;
  logic  [7:0] dep_ipv4_ttl = 0; logic  [7:0] dep_ipv4_proto = 0;
  logic [15:0] dep_ipv4_chk = 0;
  logic [31:0] dep_ipv4_src = 0; logic [31:0] dep_ipv4_dst = 0;

  logic [DEP_W-1:0] dep_pkt_out;
  logic [15:0]      dep_pkt_len;
  logic              dep_valid_out;

  deparser_generated deparser_dut (
    .clk                (clk),
    .rst_n              (rst_n),
    .valid_in           (dep_valid_in),
    .ethernet_valid     (dep_eth_valid),
    .ipv4_valid         (dep_ipv4_valid),
    .ethernet_dstAddr   (dep_eth_dst),
    .ethernet_srcAddr   (dep_eth_src),
    .ethernet_etherType (dep_eth_type),
    .ipv4_version       (dep_ipv4_ver),
    .ipv4_ihl           (dep_ipv4_ihl),
    .ipv4_diffserv      (dep_ipv4_ds),
    .ipv4_ecn           (dep_ipv4_ecn),
    .ipv4_totalLen      (dep_ipv4_len),
    .ipv4_identification(dep_ipv4_id),
    .ipv4_flags         (dep_ipv4_flg),
    .ipv4_fragOffset    (dep_ipv4_off),
    .ipv4_ttl           (dep_ipv4_ttl),
    .ipv4_protocol      (dep_ipv4_proto),
    .ipv4_hdrChecksum   (dep_ipv4_chk),
    .ipv4_srcAddr       (dep_ipv4_src),
    .ipv4_dstAddr       (dep_ipv4_dst),
    .pkt_hdr_out        (dep_pkt_out),
    .pkt_hdr_len        (dep_pkt_len),
    .valid_out          (dep_valid_out)
  );

  // ==========================================================================
  // Test infrastructure
  // ==========================================================================
  int pass_cnt = 0, fail_cnt = 0;

  task automatic chk(input string name, input logic cond);
    if (cond) begin $display("    [PASS] %s", name); pass_cnt++; end
    else      begin $display("    [FAIL] %s", name); fail_cnt++; end
  endtask

  task do_reset;
    rst_n = 0; p_valid_in = 0; pr_valid_in = 0; eg_valid_in = 0; dep_valid_in = 0;
    pr_eth_valid = 0; pr_ipv4_valid = 0;
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
    $display("== tb_ecn: ecn.p4 self-checking regression ==\n");

    // ──────────────────────────────────────────────────────────────────────
    // SECTION 1 — PARSER
    // ──────────────────────────────────────────────────────────────────────
    $display("══ Section 1: Parser FSM ══════════════════════════════════════");

    $display("  P1: 0x0800 -> eth->ipv4->accept");
    do_reset();
    p_eth_type=16'h0800; p_valid_in=1;
    @(posedge clk); #1;
    chk("P1 ETH: ext_eth", p_ext_eth);
    @(posedge clk); #1;
    chk("P1 IPV4: ext_ipv4", p_ext_ipv4);
    @(posedge clk); #1;
    chk("P1 ACCEPT: done", p_done);
    p_valid_in=0;

    $display("  P2: 0x0806 (ARP) -> eth->accept");
    do_reset();
    p_eth_type=16'h0806; p_valid_in=1;
    @(posedge clk); #1; @(posedge clk); #1;
    chk("P2 ACCEPT: done", p_done);
    chk("P2 !ipv4", !p_ext_ipv4);
    p_valid_in=0;

    // ──────────────────────────────────────────────────────────────────────
    // SECTION 2 — INGRESS: ipv4_lpm (default_action = NoAction on miss)
    // ──────────────────────────────────────────────────────────────────────
    $display("\n══ Section 2: Ingress ipv4_lpm ══════════════════════════════════");
    do_reset();
    pr_eth_valid = 1; pr_ipv4_valid = 1;

    // 10.0.0.0/8 -> ipv4_forward, dstMAC=AABBCCDDEEFF, port=3
    lpm_write(0, 32'h0A000000, 6'd8, 2'd1, 48'hAABBCCDDEEFF, 9'd3);
    // 172.16.0.0/12 -> drop
    lpm_write(1, 32'hAC100000, 6'd12, 2'd2, 48'h0, 9'd0);

    // L1: hit (ipv4_forward) -> forwarded
    pr_ipv4_dst = 32'h0A010203; // 10.1.2.3
    pr_ipv4_ttl = 64;
    send_ingress_packet();
    chk("L1: not dropped",       !pr_drop);
    chk("L1: dstAddr rewritten", pr_o_eth_dst === 48'hAABBCCDDEEFF);
    chk("L1: ttl decremented",   pr_o_ipv4_ttl === 8'd63);
    chk("L1: egress_spec=3",     pr_o_egress_spec === 9'd3);

    // L2: hit (explicit drop action)
    pr_ipv4_dst = 32'hAC100005; // 172.16.0.5
    send_ingress_packet();
    chk("L2: explicit drop entry -> dropped", pr_drop);

    // L3: miss -> default_action=NoAction() -> silent pass-through, NOT dropped
    pr_ipv4_dst = 32'h08080808; // 8.8.8.8, no matching entry
    pr_eth_dst  = 48'h999999999999; // sentinel: must survive unmodified
    pr_ipv4_ttl = 77;
    send_ingress_packet();
    chk("L3: miss -> NOT dropped (default=NoAction)", !pr_drop);
    chk("L3: eth dstAddr unmodified on miss", pr_o_eth_dst === 48'h999999999999);
    chk("L3: ttl unmodified on miss",         pr_o_ipv4_ttl === 8'd77);

    // ──────────────────────────────────────────────────────────────────────
    // SECTION 3 — Ingress valid_out latency (3-cycle: 1 baseline + 2 boundary)
    // ──────────────────────────────────────────────────────────────────────
    $display("\n══ Section 3: Ingress valid_out latency ═════════════════════════");
    do_reset();
    pr_eth_valid = 1; pr_ipv4_valid = 1;
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
    // SECTION 4 — EGRESS: ECN marking
    // ──────────────────────────────────────────────────────────────────────
    $display("\n══ Section 4: Egress ECN marking ════════════════════════════════");
    do_reset();

    // E1: ECT(0)=1, qdepth below threshold -> untouched
    eg_ipv4_ecn = 2'd1; eg_qdepth = 19'd5; #1;
    chk("E1: ECT(0), qdepth<10 -> unmarked", eg_o_ipv4_ecn === 2'd1);

    // E2: ECT(0)=1, qdepth above threshold -> marked CE=3
    eg_ipv4_ecn = 2'd1; eg_qdepth = 19'd15; #1;
    chk("E2: ECT(0), qdepth>=10 -> marked CE", eg_o_ipv4_ecn === 2'd3);

    // E3: ECT(1)=2, qdepth above threshold -> marked CE=3
    eg_ipv4_ecn = 2'd2; eg_qdepth = 19'd15; #1;
    chk("E3: ECT(1), qdepth>=10 -> marked CE", eg_o_ipv4_ecn === 2'd3);

    // E4: non-ECT=0, qdepth above threshold -> must stay untouched
    eg_ipv4_ecn = 2'd0; eg_qdepth = 19'd15; #1;
    chk("E4: non-ECT, qdepth>=10 -> still unmarked", eg_o_ipv4_ecn === 2'd0);

    // E5: already CE=3, qdepth above threshold -> stays 3 (not in the ecn==1||ecn==2 gate)
    eg_ipv4_ecn = 2'd3; eg_qdepth = 19'd15; #1;
    chk("E5: already-CE, qdepth>=10 -> stays CE", eg_o_ipv4_ecn === 2'd3);

    // E6: exactly at threshold (>=10) -> marked
    eg_ipv4_ecn = 2'd1; eg_qdepth = 19'd10; #1;
    chk("E6: qdepth==10 (boundary) -> marked", eg_o_ipv4_ecn === 2'd3);

    // E7: just below threshold -> unmarked
    eg_ipv4_ecn = 2'd1; eg_qdepth = 19'd9; #1;
    chk("E7: qdepth==9 (boundary) -> unmarked", eg_o_ipv4_ecn === 2'd1);

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

    dep_eth_valid=1; dep_ipv4_valid=1;
    dep_eth_dst = 48'hAAAAAAAAAAAA; dep_eth_src = 48'hBBBBBBBBBBBB; dep_eth_type = 16'h0800;
    dep_ipv4_ver=4; dep_ipv4_ihl=5; dep_ipv4_ds=0; dep_ipv4_ecn=2'd3; dep_ipv4_len=20;
    dep_ipv4_id=1; dep_ipv4_flg=0; dep_ipv4_off=0; dep_ipv4_ttl=64; dep_ipv4_proto=6;
    dep_ipv4_chk=16'hBEEF; dep_ipv4_src=32'hC0A80001; dep_ipv4_dst=32'h0A010203;
    #1;
    chk("D1: dep ethernet at [271:160]", dep_pkt_out[271:224] === dep_eth_dst);
    chk("D1: dep ipv4 dstAddr at [31:0]", dep_pkt_out[31:0] === dep_ipv4_dst);
    chk("D1: pkt_hdr_len = 272 (112+160)", dep_pkt_len === 16'd272);

    dep_ipv4_valid = 0;
    #1;
    chk("D2: pkt_hdr_len = 112 (ethernet only)", dep_pkt_len === 16'd112);
    chk("D2: ipv4 slice zeroed", dep_pkt_out[159:0] === 160'd0);

    dep_ipv4_valid = 1;
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
