`timescale 1ns/1ps

import p4_defs_pkg::*;
import p4_types_pkg::*;

module tb_default;

  // ============================================================
  // Clock / Reset
  // ============================================================
  logic clk;
  logic rst_n;

  initial clk = 0;
  always #5 clk = ~clk;

  // ============================================================
  // AXI Stream
  // ============================================================
  axis_word_t s_axis;
  logic       s_valid;
  logic       s_ready;

  axis_word_t m_axis;
  logic       m_valid;
  logic       m_ready;

  // ============================================================
  // DUT
  // ============================================================
  top_echo dut (
      .clk(clk),
      .rst_n(rst_n),
      .s_axis(s_axis),
      .s_valid(s_valid),
      .s_ready(s_ready),
      .m_axis(m_axis),
      .m_valid(m_valid),
      .m_ready(m_ready)
  );

  // ============================================================
  // Scoreboard
  // ============================================================
  logic [127:0] expected_queue[$];

  int tx_count;
  int rx_count;

  // ============================================================
  // Reset
  // ============================================================
  initial begin
    rst_n   = 0;
    s_valid = 0;
    m_ready = 1;

    #50;
    rst_n = 1;
  end

  // ============================================================
  // Packet generator (Ethernet frame)
  // ============================================================
  function logic [127:0] gen_packet();
    logic [127:0] pkt;

    pkt[127:80] = 48'h112233445566; // dst MAC
    pkt[79:32]  = 48'hAABBCCDDEEFF; // src MAC
    pkt[31:16]  = 16'h0800;         // eth type
    pkt[15:0]   = $random;

    return pkt;
  endfunction

  // ============================================================
  // Send packets
  // ============================================================
  initial begin
    wait(rst_n);

    tx_count = 0;

    repeat (5) begin
      send_packet(gen_packet());
    end
  end

  task send_packet(input logic [127:0] data);
    begin
      @(posedge clk);

      s_axis.tdata = data;
      s_axis.tkeep = '1;
      s_axis.tlast = 1'b1;

      s_valid = 1;

      expected_queue.push_back(data);
      tx_count++;

      wait(s_ready);

      @(posedge clk);
      s_valid = 0;
    end
  endtask

  // ============================================================
  // Receive + AXI check
  // ============================================================
  always @(posedge clk) begin
    if (m_valid && m_ready) begin
      check_packet(m_axis.tdata);
      check_parser_outputs();
      rx_count++;
    end
  end

  // ============================================================
  // Data correctness check
  // ============================================================
  task check_packet(input logic [127:0] data);
    logic [127:0] expected;

    if (expected_queue.size() == 0) begin
      $display("ERROR: Unexpected packet");
      $stop;
    end

    expected = expected_queue.pop_front();

    if (data !== expected) begin
      $display("ERROR: Packet mismatch");
      $display("Expected: %h", expected);
      $display("Got     : %h", data);
      $stop;
    end else begin
      $display("Packet OK: %h", data);
    end
  endtask

  // ============================================================
  // Parser correctness check (NEW)
  // ============================================================
  task check_parser_outputs();
    begin
      // Access internal signals (hierarchical access)
      if (dut.u_parser.bus_out.hdr.ethernet.dst_mac !== 48'h112233445566) begin
        $display("ERROR: dst_mac mismatch");
        $stop;
      end

      if (dut.u_parser.bus_out.hdr.ethernet.src_mac !== 48'hAABBCCDDEEFF) begin
        $display("ERROR: src_mac mismatch");
        $stop;
      end

      if (dut.u_parser.bus_out.hdr.ethernet.eth_type !== 16'h0800) begin
        $display("ERROR: eth_type mismatch");
        $stop;
      end
    end
  endtask

  // ============================================================
  // Finish
  // ============================================================
  initial begin
    rx_count = 0;

    wait(rst_n);
    #2000;

    if (rx_count == tx_count && expected_queue.size() == 0)
      $display("TEST PASSED");
    else
      $display("TEST FAILED");

    $finish;
  end

  // ============================================================
  // Wave dump
  // ============================================================
  initial begin
    $dumpfile("wave.vcd");
    $dumpvars(0, tb_default);
  end

endmodule