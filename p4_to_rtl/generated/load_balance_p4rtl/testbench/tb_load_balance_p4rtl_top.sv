// ============================================================================
// tb_load_balance_p4rtl_top.sv -- P4RtlPipeline build of the same app: the
// send_frame table and the IPv4 checksum run in the EGRESS control, fed by
// PHV pass-through from ingress (docs/egress_stage_plan.md). Identical
// packets, identical expectations to the load_balance_xsa version; the only
// interface difference is the sideband: egress_port is standard metadata
// here (out_std_meta_egress_port), not user metadata.
// (derived from tb_load_balance_xsa_top.sv) -- the ECMP load balancer END-TO-END through the
// AXI shell: tables programmed over AXI4-Lite, real IPv4/TCP frames in over
// AXI4-Stream, rewritten frames out, egress port on the metadata sideband.
//
// tb_load_balance_p4rtl.sv (23 assertions) drives processing_generated directly
// and pokes the tables' control-plane ports straight from the testbench. This
// is the first time any of the following has been exercised at all:
//   * the LPM table's prefix length programmed over the real AXI4-Lite bus
//     (the cp_wr_pfx_len regmap wiring was verified structurally only)
//   * a 48-bit action parameter (nhop_dmac, smac) crossing the 32-bit bus --
//     the regmap used to clip these to the low 32 bits in both directions,
//     so a MAC with a non-zero upper 16 bits could never be programmed. The
//     next-hop MACs here are AAAA:0000:0004 / BBBB:0000:0006 on purpose.
//   * the whole chain: LPM hit -> CRC16 5-tuple hash -> bucket -> exact
//     next-hop -> MAC/IP/TTL rewrite -> exact send_frame -> src MAC rewrite
//     -> InternetChecksum recompute -> egress port out on the sideband
//
// The flows and expected buckets come from tb_load_balance_p4rtl.sv: the CRC16
// of {C0A80101, 0A000005, 6, sport, 0050} lands in bucket 4 for sport 0x1234
// and bucket 6 for sport 0x9999. The IPv4 checksum is NOT hardcoded: it is
// recomputed here (RFC 1071) over the header the shell actually emitted, so
// it also checks InternetChecksum end-to-end.
//
// Compile:
//   iverilog -g2012 -o sim tb_load_balance_p4rtl_top.sv ../*.sv
//   vvp sim
// ============================================================================
`timescale 1ns/1ps

module tb_load_balance_p4rtl_top;

  localparam CLK_T = 10;
  logic clk = 0;
  always #(CLK_T/2) clk = ~clk;
  logic rst_n;

  localparam int TB_BEAT_BYTES = 32;
  localparam int TB_AXI_DATA_W = TB_BEAT_BYTES * 8;

  logic [TB_AXI_DATA_W-1:0] s_axis_tdata;
  logic [TB_BEAT_BYTES-1:0] s_axis_tkeep;
  logic s_axis_tvalid = 0, s_axis_tready, s_axis_tlast = 0;
  logic [TB_AXI_DATA_W-1:0] m_axis_tdata;
  logic [TB_BEAT_BYTES-1:0] m_axis_tkeep;
  logic m_axis_tvalid, m_axis_tready = 1'b1, m_axis_tlast;

  logic [15:0] s_axil_awaddr = 0; logic s_axil_awvalid = 0, s_axil_awready;
  logic [31:0] s_axil_wdata = 0;  logic [3:0] s_axil_wstrb = 0;
  logic s_axil_wvalid = 0, s_axil_wready; logic [1:0] s_axil_bresp;
  logic s_axil_bvalid, s_axil_bready = 1'b1;
  logic [15:0] s_axil_araddr = 0; logic s_axil_arvalid = 0, s_axil_arready;
  logic [31:0] s_axil_rdata;  logic [1:0] s_axil_rresp;
  logic s_axil_rvalid, s_axil_rready = 1'b1;

  logic [13:0] out_meta_ecmp_select;
  logic  [8:0] out_std_meta_egress_port;

  load_balance_p4rtl_top dut (
    .clk(clk), .rst_n(rst_n),
    .s_axis_tdata(s_axis_tdata), .s_axis_tkeep(s_axis_tkeep),
    .s_axis_tvalid(s_axis_tvalid), .s_axis_tready(s_axis_tready), .s_axis_tlast(s_axis_tlast),
    .m_axis_tdata(m_axis_tdata), .m_axis_tkeep(m_axis_tkeep),
    .m_axis_tvalid(m_axis_tvalid), .m_axis_tready(m_axis_tready), .m_axis_tlast(m_axis_tlast),
    .s_axil_awaddr(s_axil_awaddr), .s_axil_awvalid(s_axil_awvalid), .s_axil_awready(s_axil_awready),
    .s_axil_wdata(s_axil_wdata), .s_axil_wstrb(s_axil_wstrb),
    .s_axil_wvalid(s_axil_wvalid), .s_axil_wready(s_axil_wready),
    .s_axil_bresp(s_axil_bresp), .s_axil_bvalid(s_axil_bvalid), .s_axil_bready(s_axil_bready),
    .s_axil_araddr(s_axil_araddr), .s_axil_arvalid(s_axil_arvalid), .s_axil_arready(s_axil_arready),
    .s_axil_rdata(s_axil_rdata), .s_axil_rresp(s_axil_rresp),
    .s_axil_rvalid(s_axil_rvalid), .s_axil_rready(s_axil_rready),
    .out_meta_ecmp_select(out_meta_ecmp_select), .out_std_meta_egress_port(out_std_meta_egress_port)
  );

  int pass_cnt = 0, fail_cnt = 0;
  task automatic chk(input string name, input logic cond);
    if (cond) begin $display("    [PASS] %s", name); pass_cnt++; end
    else      begin $display("    [FAIL] %s", name); fail_cnt++; end
  endtask

  task do_reset;
    rst_n = 0; s_axis_tvalid = 0; s_axis_tlast = 0;
    repeat(5) @(posedge clk); @(negedge clk);
    rst_n = 1; @(posedge clk); #1;
  endtask

  // ── AXI4-Lite (same tasks as tb_fiveTuple_top.sv, see its notes) ─────────
  task automatic axil_write(input int word_addr, input logic [31:0] data);
    bit aw_done, w_done;
    @(negedge clk);
    s_axil_awaddr = word_addr * 4; s_axil_awvalid = 1'b1;
    s_axil_wdata = data; s_axil_wstrb = 4'hF; s_axil_wvalid = 1'b1;
    aw_done = 1'b0; w_done = 1'b0;
    while (!aw_done || !w_done) begin
      @(posedge clk); #1;
      if (!aw_done && s_axil_awready) aw_done = 1'b1;
      if (!w_done && s_axil_wready)   w_done  = 1'b1;
    end
    @(negedge clk);
    s_axil_awvalid = 1'b0; s_axil_wvalid = 1'b0;
  endtask

  task automatic axil_read(input int word_addr, output logic [31:0] data);
    bit accepted;
    @(negedge clk);
    s_axil_araddr = word_addr * 4; s_axil_arvalid = 1'b1;
    accepted = 1'b0;
    while (!accepted) begin @(posedge clk); if (s_axil_arready) accepted = 1'b1; end
    @(negedge clk);
    s_axil_arvalid = 1'b0;
    @(posedge clk);
    data = s_axil_rdata;
  endtask

  // ── Register map (emit_top._build_axil_regmap for this app) ───────────────
  //  ecmp_group (LPM):   0 idx  1 action  2 key_dstAddr  3 pfx_len
  //                      4 p_ecmp_base  5 p_ecmp_mask  6 commit
  //  ecmp_nhop (exact): 64 idx 65 action 66 key_ecmp_select
  //                     67 p_nhop_dmac[31:0] 68 p_nhop_dmac[47:32]   <- 2 words
  //                     69 p_nhop_ipv4 70 p_port 71 commit
  //                     72 query_key 73 query_commit 74 delete_commit
  //                     75 query_status 76 query_action_id
  //                     77 query_p_nhop_dmac[31:0] 78 [47:32] 79 query_p_nhop_ipv4 80 query_p_port
  //  send_frame(exact):128 idx 129 action 130 key_egress_port
  //                    131 p_smac[31:0] 132 p_smac[47:32] 133 commit
  localparam int ACT_SET_ECMP = 1, ACT_SET_NHOP = 1, ACT_RW_MAC = 1;

  task automatic prog_ecmp_group(input int idx, input [31:0] key, input int pfx,
                                 input [13:0] base_, input [15:0] mask);
    axil_write(0, idx); axil_write(1, ACT_SET_ECMP); axil_write(2, key);
    axil_write(3, pfx); axil_write(4, base_); axil_write(5, mask); axil_write(6, 1);
    repeat (4) @(posedge clk);
  endtask
  task automatic prog_ecmp_nhop(input int idx, input [13:0] bucket, input [47:0] dmac,
                                input [31:0] nhop_ip, input [8:0] port);
    axil_write(64, idx); axil_write(65, ACT_SET_NHOP); axil_write(66, bucket);
    axil_write(67, dmac[31:0]); axil_write(68, {16'd0, dmac[47:32]});
    axil_write(69, nhop_ip); axil_write(70, port); axil_write(71, 1);
    repeat (4) @(posedge clk);
  endtask
  task automatic prog_send_frame(input int idx, input [8:0] port, input [47:0] smac);
    axil_write(128, idx); axil_write(129, ACT_RW_MAC); axil_write(130, port);
    axil_write(131, smac[31:0]); axil_write(132, {16'd0, smac[47:32]}); axil_write(133, 1);
    repeat (4) @(posedge clk);
  endtask

  // ── Packet builder (network byte order) ──────────────────────────────────
  byte pb[$];
  task automatic a16(input [15:0] v); pb.push_back(v[15:8]); pb.push_back(v[7:0]); endtask
  task automatic a32(input [31:0] v); a16(v[31:16]); a16(v[15:0]); endtask
  task automatic a48(input [47:0] v); a16(v[47:32]); a32(v[31:0]); endtask

  task automatic build_frame(input [31:0] ip_src, input [31:0] ip_dst,
                             input [15:0] sport, input [15:0] dport);
    pb.delete();
    a48(48'hAABBCCDDEEFF); a48(48'h112233445566); a16(16'h0800);      // eth
    pb.push_back(8'h45); pb.push_back(8'h00); a16(16'd40); a16(16'd1); // ipv4: ver/ihl tos len id
    a16(16'h4000); pb.push_back(8'd64); pb.push_back(8'd6);            // flags ttl proto
    a16(16'h0000); a32(ip_src); a32(ip_dst);                            // csum src dst
    a16(sport); a16(dport); a32(32'd1); a32(32'd0);                     // tcp
    pb.push_back(8'h50); pb.push_back(8'h02); a16(16'd1024); a16(16'd0); a16(16'd0);
    while (pb.size() < 64) pb.push_back(8'h00);                          // pad
  endtask

  task automatic send_pb;
    int nbeats = (pb.size() + TB_BEAT_BYTES - 1) / TB_BEAT_BYTES;
    for (int b = 0; b < nbeats; b++) begin
      logic [TB_AXI_DATA_W-1:0] beat = '0;
      logic [TB_BEAT_BYTES-1:0] keep = '0;
      for (int i = 0; i < TB_BEAT_BYTES; i++)
        if (b*TB_BEAT_BYTES + i < pb.size()) begin
          beat[i*8 +: 8] = pb[b*TB_BEAT_BYTES + i]; keep[i] = 1'b1;
        end
      @(negedge clk);
      s_axis_tdata = beat; s_axis_tkeep = keep;
      s_axis_tvalid = 1'b1; s_axis_tlast = (b == nbeats-1);
      @(posedge clk);
      while (!s_axis_tready) @(posedge clk);
      #1;
    end
    @(negedge clk);
    s_axis_tvalid = 1'b0; s_axis_tlast = 1'b0;
  endtask

  byte rx[$];
  logic saw_tlast;
  task automatic capture(input int max_cycles);
    rx.delete(); saw_tlast = 1'b0;
    for (int c = 0; c < max_cycles && !saw_tlast; c++) begin
      @(posedge clk); #1;
      if (m_axis_tvalid && m_axis_tready) begin
        for (int i = 0; i < TB_BEAT_BYTES; i++)
          if (m_axis_tkeep[i]) rx.push_back(m_axis_tdata[i*8 +: 8]);
        if (m_axis_tlast) saw_tlast = 1'b1;
      end
    end
    repeat (4) @(posedge clk); #1;
  endtask

  task automatic run(input [31:0] ip_src, input [31:0] ip_dst, input [15:0] sport, input [15:0] dport);
    build_frame(ip_src, ip_dst, sport, dport);
    fork send_pb(); capture(200); join
  endtask

  // Field readers over the captured frame
  function automatic [47:0] rx_dmac();  return {rx[0],rx[1],rx[2],rx[3],rx[4],rx[5]};   endfunction
  function automatic [47:0] rx_smac();  return {rx[6],rx[7],rx[8],rx[9],rx[10],rx[11]}; endfunction
  function automatic  [7:0] rx_ttl();   return rx[14+8]; endfunction
  function automatic [15:0] rx_csum();  return {rx[14+10], rx[14+11]}; endfunction
  function automatic [31:0] rx_ipdst(); return {rx[14+16],rx[14+17],rx[14+18],rx[14+19]}; endfunction

  // RFC 1071 over the emitted IPv4 header, checksum field zeroed.
  function automatic [15:0] ipv4_csum_of_rx();
    logic [31:0] sum = 0;
    for (int i = 0; i < 20; i += 2) begin
      logic [15:0] w = {rx[14+i], rx[14+i+1]};
      if (i == 10) w = 16'h0000;
      sum += w;
    end
    while (sum[31:16]) sum = sum[15:0] + sum[31:16];
    return ~sum[15:0];
  endfunction

  logic [31:0] rd_lo, rd_hi, rd_st;
  initial begin
    $display("\n== tb_load_balance_p4rtl_top: ECMP load balancer through the AXI shell ==\n");
    do_reset();
    repeat (40) @(posedge clk);   // exact-match tables' power-on clear

    // ---- program all three tables over AXI4-Lite ----------------------------
    prog_ecmp_group(0, 32'h0A000000, 8, 14'd0, 16'd7);            // 10.0.0.0/8, 8 buckets
    prog_ecmp_nhop (0, 14'd4, 48'hAAAA00000004, 32'h0A000001, 9'd3);
    prog_ecmp_nhop (1, 14'd6, 48'hBBBB00000006, 32'h0A000002, 9'd5);
    prog_send_frame(0, 9'd3, 48'h0000DEAD0003);
    prog_send_frame(1, 9'd5, 48'h0000DEAD0005);

    // ---- T0: the 48-bit MAC survived the 32-bit bus (readback) -------------
    $display("== T0: 48-bit nhop_dmac readback over AXI4-Lite ==");
    axil_write(72, 14'd4); axil_write(73, 1);            // query bucket 4
    repeat (6) @(posedge clk);
    axil_read(75, rd_st); axil_read(77, rd_lo); axil_read(78, rd_hi);
    chk("T0: query hit",                        rd_st[1] === 1'b1);
    chk("T0: dmac[31:0]  == 0x00000004",        rd_lo === 32'h00000004);
    chk("T0: dmac[47:32] == 0xAAAA (was unreachable before)", rd_hi[15:0] === 16'hAAAA);

    // ---- T1: flow A -> LPM hit -> bucket 4 -> port 3 -----------------------
    $display("\n== T1: 10.0.0.5 sport 0x1234 -> bucket 4 -> port 3 ==");
    run(32'hC0A80101, 32'h0A000005, 16'h1234, 16'h0050);
    chk("T1: frame emerged",                     saw_tlast && rx.size() == 64);
    chk("T1: dst MAC = next hop (upper 16 bits intact)", rx_dmac() === 48'hAAAA00000004);
    chk("T1: src MAC = send_frame(port 3)",      rx_smac() === 48'h0000DEAD0003);
    chk("T1: dst IP rewritten to 10.0.0.1",      rx_ipdst() === 32'h0A000001);
    chk("T1: TTL decremented to 63",             rx_ttl() === 8'd63);
    chk("T1: IPv4 checksum valid (RFC 1071 over emitted header)", rx_csum() === ipv4_csum_of_rx());
    chk("T1: sideband egress_port == 3",         out_std_meta_egress_port === 9'd3);
    chk("T1: sideband ecmp_select == 4",         out_meta_ecmp_select === 14'd4);

    // ---- T2: flow B -> bucket 6 -> port 5 ----------------------------------
    $display("\n== T2: same dst, sport 0x9999 -> bucket 6 -> port 5 ==");
    run(32'hC0A80101, 32'h0A000005, 16'h9999, 16'h0050);
    chk("T2: dst MAC = bucket-6 next hop",       rx_dmac() === 48'hBBBB00000006);
    chk("T2: src MAC = send_frame(port 5)",      rx_smac() === 48'h0000DEAD0005);
    chk("T2: dst IP rewritten to 10.0.0.2",      rx_ipdst() === 32'h0A000002);
    chk("T2: checksum valid",                    rx_csum() === ipv4_csum_of_rx());
    chk("T2: sideband egress_port == 5",         out_std_meta_egress_port === 9'd5);

    // ---- T3: LPM prefix honoured: 11.0.0.5 must miss /8 --------------------
    $display("\n== T3: 11.0.0.5 misses the 10.0.0.0/8 entry (pfx_len programmed over the bus) ==");
    run(32'hC0A80101, 32'h0B000005, 16'h1234, 16'h0050);
    chk("T3: frame emerged",                     saw_tlast && rx.size() == 64);
    chk("T3: dst MAC untouched",                 rx_dmac() === 48'hAABBCCDDEEFF);
    chk("T3: src MAC untouched",                 rx_smac() === 48'h112233445566);
    chk("T3: dst IP untouched",                  rx_ipdst() === 32'h0B000005);
    chk("T3: TTL untouched",                     rx_ttl() === 8'd64);
    chk("T3: sideband egress_port == 0 on miss", out_std_meta_egress_port === 9'd0);

    $display("\n================================================================");
    $display("  Results: %0d passed, %0d failed  (total %0d)",
             pass_cnt, fail_cnt, pass_cnt + fail_cnt);
    $display("================================================================");
    if (fail_cnt == 0) $display("  ALL TESTS PASSED");
    else                $display("  SOME TESTS FAILED");
    $finish;
  end

endmodule
