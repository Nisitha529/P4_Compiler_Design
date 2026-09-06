// ============================================================================
// tb_load_balance_xsa.sv -- functional regression for the XilinxPipeline port
// of the ECMP load balancer (p4src/apps/load_balance_xsa.p4).
//
// Drives processing_generated directly (the same idiom tb_firewall.sv uses),
// exercising the full three-table chain in one pass:
//     ecmp_group (LPM on dstAddr) -> ecmp_nhop (exact on the hashed bucket)
//     -> send_frame (exact on the chosen port)
//
// What each test is actually pinning down:
//   T1/T2  the CRC-16 ECMP hash really drives bucket selection -- two flows
//          differing only in source port land on *different* buckets, and the
//          expected bucket numbers come from crc_model.py (independent Python
//          ground truth), not from the RTL.
//   T3     the LPM prefix length is genuinely honoured. This is the one that
//          catches the previously-broken control-plane wiring: a /8 entry must
//          match 10.0.0.5 (T1, differing host bits) yet miss 11.0.0.5 (T3).
//          A pfx_len stuck at 0 would wrongly match T3; stuck at 32 would
//          wrongly miss T1.
//   T4     drop_pkt drives the real `drop` output (xsa.p4 has no
//          mark_to_drop(); it uses standard_metadata.drop).
//   T5     the IPv4 header checksum is recomputed over the *rewritten* header,
//          checked against an independent Python RFC 1071 computation.
//
// Compile (from this directory):
//   iverilog -g2012 -o sim tb_load_balance_xsa.sv ../processing_generated.sv \
//     ../ecmp_group_table.sv ../ecmp_nhop_table.sv ../send_frame_table.sv
//   vvp sim
// ============================================================================
`timescale 1ns/1ps

module tb_load_balance_xsa;

  localparam CLK_T = 10;
  logic clk = 0;
  always #(CLK_T/2) clk = ~clk;
  logic rst_n;

  // Action IDs, from the generated action dispatch (0 = NoAction).
  localparam [1:0] ACT_SET_ECMP  = 2'd1, ACT_GRP_DROP  = 2'd2;
  localparam [1:0] ACT_SET_NHOP  = 2'd1, ACT_NHOP_DROP = 2'd2;
  localparam [1:0] ACT_RW_MAC    = 2'd1;

  logic        valid_in = 0;
  logic        eth_valid = 1, ipv4_valid = 1, tcp_valid = 1;

  logic [47:0] eth_dst = 48'hAABBCCDDEEFF, eth_src = 48'h112233445566;
  logic [15:0] eth_type = 16'h0800;
  logic  [3:0] ip_version = 4, ip_ihl = 5;
  logic  [7:0] ip_diffserv = 0;
  logic [15:0] ip_totalLen = 16'h0034, ip_id = 16'h1c46;
  logic  [2:0] ip_flags = 3'd2;
  logic [12:0] ip_frag = 0;
  logic  [7:0] ip_ttl = 8'd64, ip_proto = 8'd6;
  logic [15:0] ip_csum = 16'hDEAD;
  logic [31:0] ip_src = 32'hC0A80101, ip_dst = 32'h0A000005;
  logic [15:0] tcp_sport = 16'h1234, tcp_dport = 16'h0050;
  logic [31:0] tcp_seq = 0, tcp_ack = 0;
  logic  [3:0] tcp_doff = 5;
  logic  [2:0] tcp_res = 0, tcp_ecn = 0;
  logic  [5:0] tcp_ctrl = 0;
  logic [15:0] tcp_win = 0, tcp_cks = 0, tcp_urg = 0;
  // Metadata OUTPUTS -- the forwarding decision. xsa.p4's standard_metadata_t
  // has no egress_spec/egress_port, so user metadata is the only channel this
  // app has to report the port it chose; these ports are what make it
  // observable at all (before they existed the value was dead and synthesis
  // deleted the logic feeding it).
  logic [13:0] o_meta_ecmp;
  logic  [8:0] o_meta_port;

  logic [13:0] meta_ecmp_in = 0;
  logic  [8:0] meta_port_in = 0;

  logic        o_eth_valid, o_ipv4_valid, o_tcp_valid;
  logic [47:0] o_eth_dst, o_eth_src;
  logic [15:0] o_eth_type;
  logic  [3:0] o_ip_version, o_ip_ihl;
  logic  [7:0] o_ip_diffserv;
  logic [15:0] o_ip_totalLen, o_ip_id;
  logic  [2:0] o_ip_flags;
  logic [12:0] o_ip_frag;
  logic  [7:0] o_ip_ttl, o_ip_proto;
  logic [15:0] o_ip_csum;
  logic [31:0] o_ip_src, o_ip_dst;
  logic [15:0] o_tcp_sport, o_tcp_dport;
  logic [31:0] o_tcp_seq, o_tcp_ack;
  logic  [3:0] o_tcp_doff;
  logic  [2:0] o_tcp_res, o_tcp_ecn;
  logic  [5:0] o_tcp_ctrl;
  logic [15:0] o_tcp_win, o_tcp_cks, o_tcp_urg;
  logic        grp_hit, nhop_hit, sf_hit, valid_out, drop;

  // Control-plane write buses
  logic        grp_en = 0;  logic [5:0]  grp_idx = 0;
  logic [31:0] grp_key = 0; logic [5:0]  grp_pfx = 0;
  logic [1:0]  grp_act = 0; logic [13:0] grp_base = 0;
  logic [15:0] grp_mask = 0;
  logic        nh_en = 0;   logic [3:0]  nh_idx = 0;
  logic [13:0] nh_key = 0;  logic [1:0]  nh_act = 0;
  logic [47:0] nh_dmac = 0; logic [31:0] nh_ipv4 = 0;
  logic [8:0]  nh_port = 0;
  logic        sf_en = 0;   logic [3:0]  sf_idx = 0;
  logic [8:0]  sf_key = 0;  logic [1:0]  sf_act = 0;
  logic [47:0] sf_smac = 0;

  processing_generated dut (
    .clk(clk), .rst_n(rst_n), .valid_in(valid_in),
    .ethernet_valid(eth_valid), .ipv4_valid(ipv4_valid), .tcp_valid(tcp_valid),
    .ethernet_dstAddr(eth_dst), .ethernet_srcAddr(eth_src), .ethernet_etherType(eth_type),
    .ipv4_version(ip_version), .ipv4_ihl(ip_ihl), .ipv4_diffserv(ip_diffserv),
    .ipv4_totalLen(ip_totalLen), .ipv4_identification(ip_id), .ipv4_flags(ip_flags),
    .ipv4_fragOffset(ip_frag), .ipv4_ttl(ip_ttl), .ipv4_protocol(ip_proto),
    .ipv4_hdrChecksum(ip_csum), .ipv4_srcAddr(ip_src), .ipv4_dstAddr(ip_dst),
    .tcp_srcPort(tcp_sport), .tcp_dstPort(tcp_dport), .tcp_seqNo(tcp_seq),
    .tcp_ackNo(tcp_ack), .tcp_dataOffset(tcp_doff), .tcp_res(tcp_res),
    .tcp_ecn(tcp_ecn), .tcp_ctrl(tcp_ctrl), .tcp_window(tcp_win),
    .tcp_checksum(tcp_cks), .tcp_urgentPtr(tcp_urg),
    .meta_ecmp_select(meta_ecmp_in), .meta_egress_port(meta_port_in),
    .out_meta_ecmp_select(o_meta_ecmp), .out_meta_egress_port(o_meta_port),
    .out_ethernet_valid(o_eth_valid), .out_ipv4_valid(o_ipv4_valid), .out_tcp_valid(o_tcp_valid),
    .out_ethernet_dstAddr(o_eth_dst), .out_ethernet_srcAddr(o_eth_src),
    .out_ethernet_etherType(o_eth_type),
    .out_ipv4_version(o_ip_version), .out_ipv4_ihl(o_ip_ihl),
    .out_ipv4_diffserv(o_ip_diffserv), .out_ipv4_totalLen(o_ip_totalLen),
    .out_ipv4_identification(o_ip_id), .out_ipv4_flags(o_ip_flags),
    .out_ipv4_fragOffset(o_ip_frag), .out_ipv4_ttl(o_ip_ttl),
    .out_ipv4_protocol(o_ip_proto), .out_ipv4_hdrChecksum(o_ip_csum),
    .out_ipv4_srcAddr(o_ip_src), .out_ipv4_dstAddr(o_ip_dst),
    .out_tcp_srcPort(o_tcp_sport), .out_tcp_dstPort(o_tcp_dport),
    .out_tcp_seqNo(o_tcp_seq), .out_tcp_ackNo(o_tcp_ack),
    .out_tcp_dataOffset(o_tcp_doff), .out_tcp_res(o_tcp_res), .out_tcp_ecn(o_tcp_ecn),
    .out_tcp_ctrl(o_tcp_ctrl), .out_tcp_window(o_tcp_win),
    .out_tcp_checksum(o_tcp_cks), .out_tcp_urgentPtr(o_tcp_urg),
    .ecmp_group_cp_wr_en(grp_en), .ecmp_group_cp_wr_idx(grp_idx),
    .ecmp_group_cp_wr_key_dstAddr(grp_key), .ecmp_group_cp_wr_pfx_len(grp_pfx),
    .ecmp_group_cp_wr_action(grp_act), .ecmp_group_cp_wr_p_ecmp_base(grp_base),
    .ecmp_group_cp_wr_p_ecmp_mask(grp_mask),
    .ecmp_nhop_cp_wr_en(nh_en), .ecmp_nhop_cp_wr_idx(nh_idx),
    .ecmp_nhop_cp_wr_key_ecmp_select(nh_key), .ecmp_nhop_cp_wr_action(nh_act),
    .ecmp_nhop_cp_wr_p_nhop_dmac(nh_dmac), .ecmp_nhop_cp_wr_p_nhop_ipv4(nh_ipv4),
    .ecmp_nhop_cp_wr_p_port(nh_port),
    .send_frame_cp_wr_en(sf_en), .send_frame_cp_wr_idx(sf_idx),
    .send_frame_cp_wr_key_egress_port(sf_key), .send_frame_cp_wr_action(sf_act),
    .send_frame_cp_wr_p_smac(sf_smac),
    .ecmp_group_hit_out(grp_hit), .ecmp_nhop_hit_out(nhop_hit),
    .send_frame_hit_out(sf_hit),
    .ecmp_nhop_cp_query_en(1'b0), .ecmp_nhop_cp_query_del(1'b0),
    .ecmp_nhop_cp_query_key_ecmp_select(14'd0),
    .ecmp_nhop_cp_query_busy(), .ecmp_nhop_cp_query_hit(),
    .ecmp_nhop_cp_query_action_id(), .ecmp_nhop_cp_query_p_nhop_dmac(),
    .ecmp_nhop_cp_query_p_nhop_ipv4(), .ecmp_nhop_cp_query_p_port(),
    .send_frame_cp_query_en(1'b0), .send_frame_cp_query_del(1'b0),
    .send_frame_cp_query_key_egress_port(9'd0),
    .send_frame_cp_query_busy(), .send_frame_cp_query_hit(),
    .send_frame_cp_query_action_id(), .send_frame_cp_query_p_smac(),
    .valid_out(valid_out), .drop(drop)
  );

  int pass_cnt = 0, fail_cnt = 0;
  task automatic chk(input string name, input logic cond);
    if (cond) begin $display("    [PASS] %s", name); pass_cnt++; end
    else      begin $display("    [FAIL] %s", name); fail_cnt++; end
  endtask

  task do_reset;
    rst_n = 0; valid_in = 0;
    repeat(5) @(posedge clk); @(negedge clk);
    rst_n = 1; @(posedge clk); #1;
    // Exact-match tables power up running a clear FSM that walks every
    // address zeroing mem_valid, and silently drop control-plane writes until
    // it finishes (DEPTH cycles). Deepest exact table here is 16 entries;
    // wait it out before populating, or the entries never land.
    repeat(40) @(posedge clk);
    #1;
  endtask

  task automatic grp_write(input [5:0] idx, input [31:0] key, input [5:0] pfx,
                            input [1:0] act, input [13:0] base, input [15:0] msk);
    @(negedge clk);
    grp_idx = idx; grp_key = key; grp_pfx = pfx;
    grp_act = act; grp_base = base; grp_mask = msk; grp_en = 1;
    @(posedge clk); #1; grp_en = 0;
  endtask

  task automatic nhop_write(input [3:0] idx, input [13:0] key, input [1:0] act,
                             input [47:0] dmac, input [31:0] nip, input [8:0] prt);
    @(negedge clk);
    nh_idx = idx; nh_key = key; nh_act = act;
    nh_dmac = dmac; nh_ipv4 = nip; nh_port = prt; nh_en = 1;
    @(posedge clk); #1; nh_en = 0;
  endtask

  task automatic sf_write(input [3:0] idx, input [8:0] key, input [1:0] act,
                           input [47:0] smac);
    @(negedge clk);
    sf_idx = idx; sf_key = key; sf_act = act; sf_smac = smac; sf_en = 1;
    @(posedge clk); #1; sf_en = 0;
  endtask

  // Pipeline is 7 stages deep (valid_s6 -> valid_out); allow generous margin.
  task automatic send;
    valid_in = 1;
    repeat(10) begin @(posedge clk); #1; end
    valid_in = 0;
    @(posedge clk); #1;
  endtask

  initial begin
    $display("== tb_load_balance_xsa: XilinxPipeline ECMP load balancer ==\n");
    do_reset();

    // One /8 ECMP group covering 10.0.0.0/8, 8 buckets (mask = 7) starting at 0.
    grp_write(6'd0, 32'h0A000000, 6'd8, ACT_SET_ECMP, 14'd0, 16'd7);
    // Buckets 4 and 6 are the ones the two test flows hash to.
    nhop_write(4'd0, 14'd4, ACT_SET_NHOP, 48'hAAAA00000004, 32'h0A000001, 9'd3);
    nhop_write(4'd1, 14'd6, ACT_SET_NHOP, 48'hBBBB00000006, 32'h0A000002, 9'd5);
    sf_write(4'd0, 9'd3, ACT_RW_MAC, 48'h0000DEAD0003);
    sf_write(4'd1, 9'd5, ACT_RW_MAC, 48'h0000DEAD0005);

    // ---- T1: flow A -> CRC bucket 4 -> port 3 -------------------------------
    $display("== T1: LPM /8 hit, hash->bucket 4, nhop + send_frame ==");
    ip_dst = 32'h0A000005; tcp_sport = 16'h1234;
    send();
    chk("T1: ecmp_group hit", grp_hit === 1'b1);
    chk("T1: dst MAC rewritten to bucket-4 next hop", o_eth_dst === 48'hAAAA00000004);
    chk("T1: dst IP rewritten to bucket-4 next hop",  o_ip_dst  === 32'h0A000001);
    chk("T1: src MAC rewritten by send_frame(port 3)", o_eth_src === 48'h0000DEAD0003);
    chk("T1: TTL decremented", o_ip_ttl === 8'd63);
    chk("T1: IPv4 checksum recomputed", o_ip_csum === 16'h53d4);
    chk("T1: out_meta_ecmp_select == bucket 4", o_meta_ecmp === 14'd4);
    chk("T1: out_meta_egress_port == 3",        o_meta_port === 9'd3);

    // ---- T2: same flow but different source port -> different bucket --------
    $display("\n== T2: different flow hashes to a different bucket ==");
    ip_dst = 32'h0A000005; tcp_sport = 16'h9999;
    send();
    chk("T2: dst MAC rewritten to bucket-6 next hop", o_eth_dst === 48'hBBBB00000006);
    chk("T2: dst IP rewritten to bucket-6 next hop",  o_ip_dst  === 32'h0A000002);
    chk("T2: src MAC rewritten by send_frame(port 5)", o_eth_src === 48'h0000DEAD0005);
    chk("T2: IPv4 checksum recomputed", o_ip_csum === 16'h53d3);
    chk("T2: out_meta_ecmp_select == bucket 6", o_meta_ecmp === 14'd6);
    chk("T2: out_meta_egress_port == 5",        o_meta_port === 9'd5);

    // ---- T3: LPM prefix length must actually be honoured --------------------
    $display("\n== T3: /8 entry must NOT match 11.0.0.5 ==");
    ip_dst = 32'h0B000005; tcp_sport = 16'h1234;
    send();
    chk("T3: ecmp_group misses", grp_hit === 1'b0);
    chk("T3: dst MAC untouched", o_eth_dst === 48'hAABBCCDDEEFF);
    chk("T3: dst IP untouched",  o_ip_dst  === 32'h0B000005);
    chk("T3: src MAC untouched", o_eth_src === 48'h112233445566);
    chk("T3: TTL untouched",     o_ip_ttl  === 8'd64);
    chk("T3: checksum still recomputed over the unmodified header",
        o_ip_csum === 16'h51d0);
    // Miss -> neither set_ecmp_select nor set_nhop runs, so both metadata
    // fields must still read their zero-init value, not stage-6 garbage or a
    // leftover from T2.
    chk("T3: out_meta_ecmp_select stays 0 on miss", o_meta_ecmp === 14'd0);
    chk("T3: out_meta_egress_port stays 0 on miss", o_meta_port === 9'd0);

    // ---- T4: drop_pkt drives the real drop output ---------------------------
    $display("\n== T4: drop action asserts drop ==");
    grp_write(6'd1, 32'h0C000000, 6'd8, ACT_GRP_DROP, 14'd0, 16'd0);
    ip_dst = 32'h0C000005;
    send();
    chk("T4: drop asserted", drop === 1'b1);

    $display("\n================================================================");
    $display("  Results: %0d passed, %0d failed  (total %0d)",
             pass_cnt, fail_cnt, pass_cnt + fail_cnt);
    $display("================================================================");
    if (fail_cnt == 0) $display("  ALL TESTS PASSED");
    else                $display("  SOME TESTS FAILED");
    $finish;
  end

endmodule
