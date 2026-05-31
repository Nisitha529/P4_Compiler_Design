// ============================================================================
// tb_echo.sv — Self-checking testbench for the echo.p4 pipeline
//
// Tests:
//   Section 1 — Parser FSM             (P1-P4)
//   Section 2 — Processing swap logic  (PR1-PR7)
//   Section 3 — Deparser packing       (D1-D4)
//   Section 4 — Integration            (INT1-INT2)
//
// Compile & simulate (Icarus Verilog — run from this directory):
//   iverilog -g2012 -o sim tb_echo.sv \
//     ../parser_generated.sv \
//     ../processing_generated.sv \
//     ../deparser_generated.sv
//   vvp sim
//
// Compile & simulate (ModelSim/Questa):
//   vlog -sv tb_echo.sv ../parser_generated.sv \
//            ../processing_generated.sv ../deparser_generated.sv
//   vsim -c tb_echo -do "run -all; quit"
// ============================================================================
`timescale 1ns/1ps

module tb_echo;

  // ── Clock ───────────────────────────────────────────────────────────────────
  localparam CLK_T = 10;
  logic clk = 0;
  always #(CLK_T/2) clk = ~clk;

  logic rst_n;

  // ============================================================================
  // 1. PARSER DUT
  // ============================================================================
  logic        p_valid_in    = 0;
  logic [15:0] p_eth_type    = 0;
  logic  [7:0] p_ipv4_proto  = 0;
  logic [15:0] p_vlan_tpid   = 0;
  logic        p_ext_eth, p_ext_vlan, p_ext_ipv4, p_ext_ipv4opt, p_ext_udp;
  logic        p_done;

  parser_generated parser_dut (
    .clk            (clk),
    .rst_n          (rst_n),
    .valid_in       (p_valid_in),
    .eth_type       (p_eth_type),
    .ipv4_protocol  (p_ipv4_proto),
    .vlan_last_tpid (p_vlan_tpid),
    .extract_eth    (p_ext_eth),
    .extract_vlan   (p_ext_vlan),
    .extract_ipv4   (p_ext_ipv4),
    .extract_ipv4opt(p_ext_ipv4opt),
    .extract_udp    (p_ext_udp),
    .done           (p_done)
  );

  // ============================================================================
  // 2. PROCESSING DUT
  // ============================================================================
  logic        pr_valid_in   = 0;
  logic        pr_eth_valid  = 0;
  logic        pr_ipv4_valid = 0;
  logic        pr_opt_valid  = 0;
  logic        pr_udp_valid  = 0;

  logic [47:0] pr_eth_dmac   = 0;  logic [47:0] pr_eth_smac   = 0;
  logic [15:0] pr_eth_type   = 0;
  logic  [3:0] pr_ipv4_ver   = 0;  logic  [3:0] pr_ipv4_ihl   = 0;
  logic  [7:0] pr_ipv4_tos   = 0;  logic [15:0] pr_ipv4_len   = 0;
  logic [15:0] pr_ipv4_id    = 0;  logic  [2:0] pr_ipv4_flg   = 0;
  logic [12:0] pr_ipv4_off   = 0;  logic  [7:0] pr_ipv4_ttl   = 0;
  logic  [7:0] pr_ipv4_proto = 0;  logic [15:0] pr_ipv4_chk   = 0;
  logic [31:0] pr_ipv4_src   = 0;  logic [31:0] pr_ipv4_dst   = 0;
  logic [319:0] pr_opt_data  = 0;
  logic [15:0] pr_udp_sp     = 0;  logic [15:0] pr_udp_dp     = 0;
  logic [15:0] pr_udp_len    = 0;  logic [15:0] pr_udp_csum   = 0;
  logic [15:0] pr_meta_port  = 0;

  logic [47:0] pr_o_eth_dmac,  pr_o_eth_smac;
  logic [15:0] pr_o_eth_type;
  logic  [3:0] pr_o_ipv4_ver,  pr_o_ipv4_ihl;
  logic  [7:0] pr_o_ipv4_tos;  logic [15:0] pr_o_ipv4_len;
  logic [15:0] pr_o_ipv4_id;   logic  [2:0] pr_o_ipv4_flg;
  logic [12:0] pr_o_ipv4_off;  logic  [7:0] pr_o_ipv4_ttl;
  logic  [7:0] pr_o_ipv4_proto; logic [15:0] pr_o_ipv4_chk;
  logic [31:0] pr_o_ipv4_src,  pr_o_ipv4_dst;
  logic [319:0] pr_o_opt_data;
  logic [15:0] pr_o_udp_sp, pr_o_udp_dp, pr_o_udp_len, pr_o_udp_csum;
  logic        pr_valid_out, pr_drop;

  processing_generated proc_dut (
    .clk               (clk),              .rst_n             (rst_n),
    .valid_in          (pr_valid_in),
    .eth_valid         (pr_eth_valid),     .ipv4_valid        (pr_ipv4_valid),
    .ipv4opt_valid     (pr_opt_valid),     .udp_valid         (pr_udp_valid),
    .eth_dmac          (pr_eth_dmac),      .eth_smac          (pr_eth_smac),
    .eth_type          (pr_eth_type),
    .ipv4_version      (pr_ipv4_ver),      .ipv4_hdr_len      (pr_ipv4_ihl),
    .ipv4_tos          (pr_ipv4_tos),      .ipv4_length       (pr_ipv4_len),
    .ipv4_id           (pr_ipv4_id),       .ipv4_flags        (pr_ipv4_flg),
    .ipv4_offset       (pr_ipv4_off),      .ipv4_ttl          (pr_ipv4_ttl),
    .ipv4_protocol     (pr_ipv4_proto),    .ipv4_hdr_chk      (pr_ipv4_chk),
    .ipv4_src          (pr_ipv4_src),      .ipv4_dst          (pr_ipv4_dst),
    .ipv4opt_options   (pr_opt_data),
    .udp_src_port      (pr_udp_sp),        .udp_dst_port      (pr_udp_dp),
    .udp_length        (pr_udp_len),       .udp_checksum      (pr_udp_csum),
    .meta_echo_port    (pr_meta_port),
    .out_eth_dmac      (pr_o_eth_dmac),    .out_eth_smac      (pr_o_eth_smac),
    .out_eth_type      (pr_o_eth_type),
    .out_ipv4_version  (pr_o_ipv4_ver),    .out_ipv4_hdr_len  (pr_o_ipv4_ihl),
    .out_ipv4_tos      (pr_o_ipv4_tos),    .out_ipv4_length   (pr_o_ipv4_len),
    .out_ipv4_id       (pr_o_ipv4_id),     .out_ipv4_flags    (pr_o_ipv4_flg),
    .out_ipv4_offset   (pr_o_ipv4_off),    .out_ipv4_ttl      (pr_o_ipv4_ttl),
    .out_ipv4_protocol (pr_o_ipv4_proto),  .out_ipv4_hdr_chk  (pr_o_ipv4_chk),
    .out_ipv4_src      (pr_o_ipv4_src),    .out_ipv4_dst      (pr_o_ipv4_dst),
    .out_ipv4opt_options(pr_o_opt_data),
    .out_udp_src_port  (pr_o_udp_sp),      .out_udp_dst_port  (pr_o_udp_dp),
    .out_udp_length    (pr_o_udp_len),     .out_udp_checksum  (pr_o_udp_csum),
    .valid_out         (pr_valid_out),     .drop              (pr_drop)
  );

  // ============================================================================
  // 3. DEPARSER DUT
  //
  //  pkt_hdr_out[655:0] layout (MSB = first emitted header):
  //    [655:544] eth    112b  {dmac,smac,type}
  //    [543:384] ipv4   160b  {ver,ihl,tos,len,id,flg,off,ttl,proto,chk,src,dst}
  //    [383: 64] ipv4opt 320b
  //    [ 63:  0] udp     64b  {sp,dp,len,csum}
  // ============================================================================
  localparam DMAC_HI  = 655; localparam DMAC_LO  = 608;
  localparam SMAC_HI  = 607; localparam SMAC_LO  = 560;
  localparam ETYPE_HI = 559; localparam ETYPE_LO = 544;
  localparam IPV4_HI  = 543; localparam IPV4_LO  = 384;
  localparam ISRC_HI  = 447; localparam ISRC_LO  = 416;
  localparam IDST_HI  = 415; localparam IDST_LO  = 384;
  localparam UDP_HI   = 63;  localparam UDP_LO   = 0;
  localparam USP_HI   = 63;  localparam USP_LO   = 48;
  localparam UDP_HI2  = 47;  localparam UDP_LO2  = 32;

  logic        dep_valid_in   = 0;
  logic        dep_eth_valid  = 0;
  logic        dep_ipv4_valid = 0;
  logic        dep_opt_valid  = 0;
  logic        dep_udp_valid  = 0;

  logic [47:0] dep_eth_dmac   = 0;  logic [47:0] dep_eth_smac   = 0;
  logic [15:0] dep_eth_type   = 0;
  logic  [3:0] dep_ipv4_ver   = 0;  logic  [3:0] dep_ipv4_ihl   = 0;
  logic  [7:0] dep_ipv4_tos   = 0;  logic [15:0] dep_ipv4_len   = 0;
  logic [15:0] dep_ipv4_id    = 0;  logic  [2:0] dep_ipv4_flg   = 0;
  logic [12:0] dep_ipv4_off   = 0;  logic  [7:0] dep_ipv4_ttl   = 0;
  logic  [7:0] dep_ipv4_proto = 0;  logic [15:0] dep_ipv4_chk   = 0;
  logic [31:0] dep_ipv4_src   = 0;  logic [31:0] dep_ipv4_dst   = 0;
  logic [319:0] dep_opt_data  = 0;
  logic [15:0] dep_udp_sp     = 0;  logic [15:0] dep_udp_dp     = 0;
  logic [15:0] dep_udp_len    = 0;  logic [15:0] dep_udp_csum   = 0;

  logic [655:0] dep_pkt_out;
  logic [15:0]  dep_pkt_len;
  logic         dep_valid_out;

  deparser_generated dep_dut (
    .clk            (clk),              .rst_n         (rst_n),
    .valid_in       (dep_valid_in),
    .eth_valid      (dep_eth_valid),    .ipv4_valid    (dep_ipv4_valid),
    .ipv4opt_valid  (dep_opt_valid),    .udp_valid     (dep_udp_valid),
    .eth_dmac       (dep_eth_dmac),     .eth_smac      (dep_eth_smac),
    .eth_type       (dep_eth_type),
    .ipv4_version   (dep_ipv4_ver),     .ipv4_hdr_len  (dep_ipv4_ihl),
    .ipv4_tos       (dep_ipv4_tos),     .ipv4_length   (dep_ipv4_len),
    .ipv4_id        (dep_ipv4_id),      .ipv4_flags    (dep_ipv4_flg),
    .ipv4_offset    (dep_ipv4_off),     .ipv4_ttl      (dep_ipv4_ttl),
    .ipv4_protocol  (dep_ipv4_proto),   .ipv4_hdr_chk  (dep_ipv4_chk),
    .ipv4_src       (dep_ipv4_src),     .ipv4_dst      (dep_ipv4_dst),
    .ipv4opt_options(dep_opt_data),
    .udp_src_port   (dep_udp_sp),       .udp_dst_port  (dep_udp_dp),
    .udp_length     (dep_udp_len),      .udp_checksum  (dep_udp_csum),
    .pkt_hdr_out    (dep_pkt_out),      .pkt_hdr_len   (dep_pkt_len),
    .valid_out      (dep_valid_out)
  );

  // ============================================================================
  // Test infrastructure
  // ============================================================================
  int pass_cnt = 0, fail_cnt = 0;

  task automatic chk(input string name, input logic cond);
    if (cond) begin
      $display("    [PASS] %s", name);
      pass_cnt++;
    end else begin
      $display("    [FAIL] %s", name);
      fail_cnt++;
    end
  endtask

  task do_reset;
    rst_n      = 0;
    p_valid_in = 0;
    repeat (3) @(posedge clk);
    @(negedge clk);
    rst_n = 1;
    @(posedge clk); #1;
  endtask

  // ============================================================================
  // MAIN TEST SEQUENCE
  // ============================================================================
  initial begin
    $dumpfile("tb_echo.vcd");
    $dumpvars(0, tb_echo);

    // ──────────────────────────────────────────────────────────────────────────
    // SECTION 1 — PARSER FSM
    // ──────────────────────────────────────────────────────────────────────────
    $display("\n══ Section 1: Parser FSM ══════════════════════════════════════");

    // ── P1: Full IPv4/UDP parse path ─────────────────────────────────────────
    $display("  P1: IPv4/UDP full-path parse");
    do_reset();
    p_eth_type   = 16'h0800;
    p_ipv4_proto = 8'h11;
    p_valid_in   = 1; #1;
    chk("P1 START: no extract_eth",       !p_ext_eth);
    chk("P1 START: not done",             !p_done);
    @(posedge clk); #1;                   // → PARSE_ETH
    chk("P1 PARSE_ETH: extract_eth",      p_ext_eth);
    chk("P1 PARSE_ETH: no extract_ipv4",  !p_ext_ipv4);
    @(posedge clk); #1;                   // → PARSE_IPV4
    chk("P1 PARSE_IPV4: extract_ipv4",    p_ext_ipv4);
    chk("P1 PARSE_IPV4: extract_ipv4opt", p_ext_ipv4opt);
    chk("P1 PARSE_IPV4: no extract_udp",  !p_ext_udp);
    @(posedge clk); #1;                   // → PARSE_UDP
    chk("P1 PARSE_UDP: extract_udp",      p_ext_udp);
    chk("P1 PARSE_UDP: not done",         !p_done);
    @(posedge clk); #1;                   // → ACCEPT
    chk("P1 ACCEPT: done",                p_done);
    chk("P1 ACCEPT: no extract_udp",      !p_ext_udp);
    @(posedge clk); #1;                   // → START (wrap)
    chk("P1 wrap START: not done",        !p_done);
    p_valid_in = 0;

    // ── P2: Non-IPv4 (ARP) → early accept ───────────────────────────────────
    $display("  P2: Non-IPv4 (ARP 0x0806) → early accept");
    do_reset();
    p_eth_type = 16'h0806; p_valid_in = 1;
    @(posedge clk); #1;                   // → PARSE_ETH
    chk("P2 PARSE_ETH: extract_eth",      p_ext_eth);
    @(posedge clk); #1;                   // → ACCEPT (default)
    chk("P2 ACCEPT: done",                p_done);
    chk("P2 ACCEPT: no extract_ipv4",     !p_ext_ipv4);
    p_valid_in = 0;

    // ── P3: IPv4/TCP → no extract_udp ───────────────────────────────────────
    $display("  P3: IPv4/TCP (proto=0x06) → no extract_udp");
    do_reset();
    p_eth_type = 16'h0800; p_ipv4_proto = 8'h06; p_valid_in = 1;
    @(posedge clk); #1;                   // → PARSE_ETH
    @(posedge clk); #1;                   // → PARSE_IPV4
    @(posedge clk); #1;                   // → ACCEPT (default)
    chk("P3 ACCEPT: done",                p_done);
    chk("P3 ACCEPT: no extract_udp",      !p_ext_udp);
    p_valid_in = 0;

    // ── P4: VLAN-tagged IPv4/UDP ─────────────────────────────────────────────
    $display("  P4: VLAN-tagged IPv4/UDP");
    do_reset();
    p_eth_type   = 16'h8100;
    p_vlan_tpid  = 16'h0800;
    p_ipv4_proto = 8'h11;
    p_valid_in   = 1;
    @(posedge clk); #1;                   // → PARSE_ETH
    chk("P4 PARSE_ETH: extract_eth",      p_ext_eth);
    @(posedge clk); #1;                   // → PARSE_VLAN
    chk("P4 PARSE_VLAN: extract_vlan",    p_ext_vlan);
    chk("P4 PARSE_VLAN: no extract_ipv4", !p_ext_ipv4);
    @(posedge clk); #1;                   // → PARSE_IPV4
    chk("P4 PARSE_IPV4: extract_ipv4",    p_ext_ipv4);
    @(posedge clk); #1;                   // → PARSE_UDP
    chk("P4 PARSE_UDP: extract_udp",      p_ext_udp);
    @(posedge clk); #1;                   // → ACCEPT
    chk("P4 ACCEPT: done",                p_done);
    p_valid_in = 0;

    // ──────────────────────────────────────────────────────────────────────────
    // SECTION 2 — PROCESSING SWAP LOGIC
    // ──────────────────────────────────────────────────────────────────────────
    $display("\n══ Section 2: Processing Logic ════════════════════════════════");

    // Stable defaults for non-critical fields
    pr_eth_valid  = 1;  pr_ipv4_valid = 1;
    pr_opt_valid  = 0;  pr_udp_valid  = 1;
    pr_eth_type   = 16'h0800;
    pr_ipv4_ver   = 4'h4;   pr_ipv4_ihl   = 4'h5;
    pr_ipv4_tos   = 8'h00;  pr_ipv4_len   = 16'd40;
    pr_ipv4_id    = 16'd1;  pr_ipv4_flg   = 3'b010;
    pr_ipv4_off   = 13'd0;  pr_ipv4_ttl   = 8'd64;
    pr_ipv4_proto = 8'h11;  pr_ipv4_chk   = 16'hBEEF;
    pr_opt_data   = '0;
    pr_udp_len    = 16'd20; pr_udp_csum   = 16'hCAFE;

    // ── PR1: Matching port → all 3 swaps ────────────────────────────────────
    $display("  PR1: dst_port == echo_port → swap eth + ipv4 + udp addresses");
    pr_eth_dmac  = 48'hAABBCCDDEEFF;  pr_eth_smac  = 48'h112233445566;
    pr_ipv4_src  = 32'hC0A80001;      pr_ipv4_dst  = 32'hC0A80002;
    pr_udp_sp    = 16'h1234;          pr_udp_dp    = 16'h5678;
    pr_meta_port = 16'h5678; #1;
    chk("PR1: eth dmac = old smac",   pr_o_eth_dmac  == 48'h112233445566);
    chk("PR1: eth smac = old dmac",   pr_o_eth_smac  == 48'hAABBCCDDEEFF);
    chk("PR1: ipv4 src = old dst",    pr_o_ipv4_src  == 32'hC0A80002);
    chk("PR1: ipv4 dst = old src",    pr_o_ipv4_dst  == 32'hC0A80001);
    chk("PR1: udp sp  = old dp",      pr_o_udp_sp    == 16'h5678);
    chk("PR1: udp dp  = old sp",      pr_o_udp_dp    == 16'h1234);
    chk("PR1: not dropped",           !pr_drop);
    chk("PR1: eth_type unchanged",    pr_o_eth_type  == 16'h0800);
    chk("PR1: ipv4 ttl unchanged",    pr_o_ipv4_ttl  == 8'd64);

    // ── PR2: Non-matching port → full pass-through ──────────────────────────
    $display("  PR2: dst_port != echo_port → pass-through");
    pr_udp_dp    = 16'h9999; #1;
    chk("PR2: eth dmac unchanged",    pr_o_eth_dmac  == 48'hAABBCCDDEEFF);
    chk("PR2: eth smac unchanged",    pr_o_eth_smac  == 48'h112233445566);
    chk("PR2: ipv4 src unchanged",    pr_o_ipv4_src  == 32'hC0A80001);
    chk("PR2: udp dp unchanged",      pr_o_udp_dp    == 16'h9999);
    chk("PR2: not dropped",           !pr_drop);

    // ── PR3: udp_valid=0 → outer if guard prevents swap ─────────────────────
    $display("  PR3: udp_valid=0 → no swap even when ports match");
    pr_udp_dp    = 16'h5678;
    pr_udp_valid = 0; #1;
    chk("PR3: eth dmac unchanged",    pr_o_eth_dmac  == 48'hAABBCCDDEEFF);
    chk("PR3: ipv4 src unchanged",    pr_o_ipv4_src  == 32'hC0A80001);
    chk("PR3: udp dp unchanged",      pr_o_udp_dp    == 16'h5678);
    pr_udp_valid = 1;

    // ── PR4: Distinct addresses ──────────────────────────────────────────────
    $display("  PR4: distinct addresses → all swap values correct");
    pr_eth_dmac  = 48'hDEADBEEFCAFE;  pr_eth_smac  = 48'hCAFEBEEFDEAD;
    pr_ipv4_src  = 32'h01020304;      pr_ipv4_dst  = 32'h05060708;
    pr_udp_sp    = 16'hAAAA;          pr_udp_dp    = 16'hBBBB;
    pr_meta_port = 16'hBBBB; #1;
    chk("PR4: eth dmac swapped",      pr_o_eth_dmac  == 48'hCAFEBEEFDEAD);
    chk("PR4: eth smac swapped",      pr_o_eth_smac  == 48'hDEADBEEFCAFE);
    chk("PR4: ipv4 src swapped",      pr_o_ipv4_src  == 32'h05060708);
    chk("PR4: ipv4 dst swapped",      pr_o_ipv4_dst  == 32'h01020304);
    chk("PR4: udp sp swapped",        pr_o_udp_sp    == 16'hBBBB);
    chk("PR4: udp dp swapped",        pr_o_udp_dp    == 16'hAAAA);

    // ── PR5: src == dst → swap is idempotent ────────────────────────────────
    $display("  PR5: src == dst (idempotent swap)");
    pr_ipv4_src  = 32'hC0A80001;  pr_ipv4_dst  = 32'hC0A80001;
    pr_udp_sp    = 16'h1234;      pr_udp_dp    = 16'h1234;
    pr_meta_port = 16'h1234; #1;
    chk("PR5: ipv4 src = C0A80001",   pr_o_ipv4_src == 32'hC0A80001);
    chk("PR5: ipv4 dst = C0A80001",   pr_o_ipv4_dst == 32'hC0A80001);
    chk("PR5: udp sp  = 0x1234",      pr_o_udp_sp   == 16'h1234);

    // ── PR6: Max-value port edge case ────────────────────────────────────────
    $display("  PR6: echo_port=0xFFFF edge case");
    pr_eth_dmac  = 48'hAABBCCDDEEFF;  pr_eth_smac  = 48'h112233445566;
    pr_ipv4_src  = 32'hFFFFFFFF;      pr_ipv4_dst  = 32'h00000000;
    pr_udp_sp    = 16'h0000;          pr_udp_dp    = 16'hFFFF;
    pr_meta_port = 16'hFFFF; #1;
    chk("PR6: ipv4 src = 0x00000000", pr_o_ipv4_src == 32'h00000000);
    chk("PR6: ipv4 dst = 0xFFFFFFFF", pr_o_ipv4_dst == 32'hFFFFFFFF);
    chk("PR6: udp sp  = 0xFFFF",      pr_o_udp_sp   == 16'hFFFF);
    chk("PR6: udp dp  = 0x0000",      pr_o_udp_dp   == 16'h0000);

    // ── PR7: valid_out is one-cycle registered ───────────────────────────────
    $display("  PR7: valid_out pipeline register latency");
    do_reset();
    pr_valid_in = 1; #1;
    chk("PR7: valid_out=0 before posedge",  !pr_valid_out);
    @(posedge clk); #1;
    chk("PR7: valid_out=1 after 1 posedge", pr_valid_out);
    pr_valid_in = 0;
    @(posedge clk); #1;
    chk("PR7: valid_out=0 after deassert",  !pr_valid_out);

    // ──────────────────────────────────────────────────────────────────────────
    // SECTION 3 — DEPARSER PACKING
    // ──────────────────────────────────────────────────────────────────────────
    $display("\n══ Section 3: Deparser Packing ════════════════════════════════");

    dep_eth_dmac   = 48'hAABBCCDDEEFF;  dep_eth_smac   = 48'h112233445566;
    dep_eth_type   = 16'h0800;
    dep_ipv4_ver   = 4'h4;   dep_ipv4_ihl   = 4'h5;
    dep_ipv4_tos   = 8'h00;  dep_ipv4_len   = 16'd40;
    dep_ipv4_id    = 16'd1;  dep_ipv4_flg   = 3'b010;
    dep_ipv4_off   = 13'd0;  dep_ipv4_ttl   = 8'd64;
    dep_ipv4_proto = 8'h11;  dep_ipv4_chk   = 16'hBEEF;
    dep_ipv4_src   = 32'hC0A80001;      dep_ipv4_dst   = 32'hC0A80002;
    dep_opt_data   = '0;
    dep_udp_sp     = 16'h1234;  dep_udp_dp   = 16'h5678;
    dep_udp_len    = 16'd20;    dep_udp_csum = 16'hCAFE;

    // ── D1: All 4 headers valid → len=656, all fields present ───────────────
    $display("  D1: all headers valid → pkt_hdr_len=656");
    dep_eth_valid = 1; dep_ipv4_valid = 1; dep_opt_valid = 1; dep_udp_valid = 1;
    #1;
    chk("D1: pkt_hdr_len = 656",          dep_pkt_len == 16'd656);
    chk("D1: eth dmac at [655:608]",       dep_pkt_out[DMAC_HI:DMAC_LO]  == 48'hAABBCCDDEEFF);
    chk("D1: eth smac at [607:560]",       dep_pkt_out[SMAC_HI:SMAC_LO]  == 48'h112233445566);
    chk("D1: eth type at [559:544]",       dep_pkt_out[ETYPE_HI:ETYPE_LO] == 16'h0800);
    chk("D1: ipv4 src at [447:416]",       dep_pkt_out[ISRC_HI:ISRC_LO]  == 32'hC0A80001);
    chk("D1: ipv4 dst at [415:384]",       dep_pkt_out[IDST_HI:IDST_LO]  == 32'hC0A80002);
    chk("D1: udp sp at [63:48]",           dep_pkt_out[USP_HI:USP_LO]    == 16'h1234);
    chk("D1: udp dp at [47:32]",           dep_pkt_out[UDP_HI2:UDP_LO2]  == 16'h5678);

    // ── D2: Only eth valid → len=112, other slots all-zero ──────────────────
    $display("  D2: only eth valid → pkt_hdr_len=112");
    dep_eth_valid = 1; dep_ipv4_valid = 0; dep_opt_valid = 0; dep_udp_valid = 0;
    #1;
    chk("D2: pkt_hdr_len = 112",           dep_pkt_len == 16'd112);
    chk("D2: eth dmac present",            dep_pkt_out[DMAC_HI:DMAC_LO]  == 48'hAABBCCDDEEFF);
    chk("D2: ipv4 slot all zeros",         dep_pkt_out[IPV4_HI:IPV4_LO]  == 160'h0);
    chk("D2: udp slot all zeros",          dep_pkt_out[UDP_HI:UDP_LO]    == 64'h0);

    // ── D3: eth + udp valid, ipv4 invalid → len=176 ─────────────────────────
    $display("  D3: eth+udp valid, ipv4 invalid → pkt_hdr_len=176");
    dep_eth_valid = 1; dep_ipv4_valid = 0; dep_opt_valid = 0; dep_udp_valid = 1;
    #1;
    chk("D3: pkt_hdr_len = 176",           dep_pkt_len == 16'd176);
    chk("D3: eth dmac present",            dep_pkt_out[DMAC_HI:DMAC_LO]  == 48'hAABBCCDDEEFF);
    chk("D3: ipv4 slot all zeros",         dep_pkt_out[IPV4_HI:IPV4_LO]  == 160'h0);
    chk("D3: udp sp present",              dep_pkt_out[USP_HI:USP_LO]    == 16'h1234);

    // ── D4: No headers valid → all zeros ─────────────────────────────────────
    $display("  D4: no headers valid → all zeros");
    dep_eth_valid = 0; dep_ipv4_valid = 0; dep_opt_valid = 0; dep_udp_valid = 0;
    #1;
    chk("D4: pkt_hdr_len = 0",             dep_pkt_len  == 16'd0);
    chk("D4: pkt_hdr_out all zeros",       dep_pkt_out  == 656'h0);

    // ──────────────────────────────────────────────────────────────────────────
    // SECTION 4 — INTEGRATION: processing → deparser
    // ──────────────────────────────────────────────────────────────────────────
    $display("\n══ Section 4: Integration Tests ═══════════════════════════════");

    // ── INT1: Swapped processing outputs land in correct deparser slots ──────
    $display("  INT1: swapped fields from processing appear in pkt_hdr_out");
    pr_eth_valid  = 1;  pr_ipv4_valid = 1;
    pr_udp_valid  = 1;  pr_opt_valid  = 0;
    pr_eth_dmac   = 48'hAABBCCDDEEFF;  pr_eth_smac  = 48'h112233445566;
    pr_eth_type   = 16'h0800;
    pr_ipv4_src   = 32'hC0A80001;      pr_ipv4_dst  = 32'hC0A80002;
    pr_ipv4_ver   = 4'h4;  pr_ipv4_ihl  = 4'h5;
    pr_ipv4_tos   = 8'h00; pr_ipv4_len  = 16'd40;
    pr_ipv4_id    = 16'd1; pr_ipv4_flg  = 3'b010;
    pr_ipv4_off   = 13'd0; pr_ipv4_ttl  = 8'd64;
    pr_ipv4_proto = 8'h11; pr_ipv4_chk  = 16'hBEEF;
    pr_udp_sp     = 16'h1234;          pr_udp_dp    = 16'hEC00;
    pr_meta_port  = 16'hEC00;          // match → swap fires
    pr_udp_len    = 16'd20; pr_udp_csum = 16'hCAFE;
    pr_opt_data   = '0; #1;

    // Route processing outputs to deparser
    dep_eth_valid  = 1; dep_ipv4_valid = 1; dep_udp_valid = 1; dep_opt_valid = 0;
    dep_eth_dmac   = pr_o_eth_dmac;    dep_eth_smac   = pr_o_eth_smac;
    dep_eth_type   = pr_o_eth_type;
    dep_ipv4_ver   = pr_o_ipv4_ver;    dep_ipv4_ihl   = pr_o_ipv4_ihl;
    dep_ipv4_tos   = pr_o_ipv4_tos;    dep_ipv4_len   = pr_o_ipv4_len;
    dep_ipv4_id    = pr_o_ipv4_id;     dep_ipv4_flg   = pr_o_ipv4_flg;
    dep_ipv4_off   = pr_o_ipv4_off;    dep_ipv4_ttl   = pr_o_ipv4_ttl;
    dep_ipv4_proto = pr_o_ipv4_proto;  dep_ipv4_chk   = pr_o_ipv4_chk;
    dep_ipv4_src   = pr_o_ipv4_src;    dep_ipv4_dst   = pr_o_ipv4_dst;
    dep_udp_sp     = pr_o_udp_sp;      dep_udp_dp     = pr_o_udp_dp;
    dep_udp_len    = pr_o_udp_len;     dep_udp_csum   = pr_o_udp_csum;
    dep_opt_data   = '0; #1;

    chk("INT1: dep eth_dmac = swapped smac",
        dep_pkt_out[DMAC_HI:DMAC_LO] == 48'h112233445566);
    chk("INT1: dep eth_smac = swapped dmac",
        dep_pkt_out[SMAC_HI:SMAC_LO] == 48'hAABBCCDDEEFF);
    chk("INT1: dep ipv4 src = swapped dst",
        dep_pkt_out[ISRC_HI:ISRC_LO] == 32'hC0A80002);
    chk("INT1: dep ipv4 dst = swapped src",
        dep_pkt_out[IDST_HI:IDST_LO] == 32'hC0A80001);
    chk("INT1: dep udp sp  = swapped dp",
        dep_pkt_out[USP_HI:USP_LO]   == 16'hEC00);
    chk("INT1: pkt_hdr_len = 336 (eth+ipv4+udp)",
        dep_pkt_len == 16'd336);

    // ── INT2: Deparser valid_out pipeline latency ────────────────────────────
    $display("  INT2: deparser valid_out is one-cycle registered");
    do_reset();
    dep_eth_valid = 1; dep_ipv4_valid = 0; dep_udp_valid = 0; dep_opt_valid = 0;
    dep_valid_in  = 1; #1;
    chk("INT2: dep valid_out=0 before posedge", !dep_valid_out);
    @(posedge clk); #1;
    chk("INT2: dep valid_out=1 after posedge",  dep_valid_out);
    dep_valid_in = 0;
    @(posedge clk); #1;
    chk("INT2: dep valid_out=0 after deassert", !dep_valid_out);

    // ──────────────────────────────────────────────────────────────────────────
    // SUMMARY
    // ──────────────────────────────────────────────────────────────────────────
    $display("\n════════════════════════════════════════════════════════════════");
    $display("  Results: %0d passed, %0d failed  (total %0d)",
             pass_cnt, fail_cnt, pass_cnt + fail_cnt);
    $display("════════════════════════════════════════════════════════════════");
    if (fail_cnt == 0)
      $display("  ALL TESTS PASSED");
    else
      $display("  FAILURES DETECTED — see [FAIL] lines above");
    $display("");
    $finish;
  end

  // Watchdog
  initial begin
    #200000;
    $display("[TIMEOUT] Watchdog triggered — simulation hung");
    $finish;
  end

endmodule
