// (c) Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
// (c) Copyright 2022-2025 Advanced Micro Devices, Inc. All rights reserved.
// 
// This file contains confidential and proprietary information
// of AMD and is protected under U.S. and international copyright
// and other intellectual property laws.
// 
// DISCLAIMER
// This disclaimer is not a license and does not grant any
// rights to the materials distributed herewith. Except as
// otherwise provided in a valid license issued to you by
// AMD, and to the maximum extent permitted by applicable
// law: (1) THESE MATERIALS ARE MADE AVAILABLE "AS IS" AND
// WITH ALL FAULTS, AND AMD HEREBY DISCLAIMS ALL WARRANTIES
// AND CONDITIONS, EXPRESS, IMPLIED, OR STATUTORY, INCLUDING
// BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, NON-
// INFRINGEMENT, OR FITNESS FOR ANY PARTICULAR PURPOSE; and
// (2) AMD shall not be liable (whether in contract or tort,
// including negligence, or under any other theory of
// liability) for any loss or damage of any kind or nature
// related to, arising under or in connection with these
// materials, including for any direct, or any indirect,
// special, incidental, or consequential loss or damage
// (including loss of data, profits, goodwill, or any type of
// loss or damage suffered as a result of any action brought
// by a third party) even if such damage or loss was
// reasonably foreseeable or AMD had been advised of the
// possibility of the same.
// 
// CRITICAL APPLICATIONS
// AMD products are not designed or intended to be fail-
// safe, or for use in any application requiring fail-safe
// performance, such as life-support or safety devices or
// systems, Class III medical devices, nuclear facilities,
// applications related to the deployment of airbags, or any
// other applications that could lead to death, personal
// injury, or severe property or environmental damage
// (individually and collectively, "Critical
// Applications"). Customer assumes the sole risk and
// liability of any use of AMD products in Critical
// Applications, subject only to applicable laws and
// regulations governing limitations on product liability.
// 
// THIS COPYRIGHT NOTICE AND DISCLAIMER MUST BE RETAINED AS
// PART OF THIS FILE AT ALL TIMES.
// 
// DO NOT MODIFY THIS FILE.

// IP VLNV: xilinx.com:ip:qdma:5.0
// IP Revision: 6

// The following must be inserted into your Verilog file for this
// core to be instantiated. Change the instance name and port connections
// (in parentheses) to your own signal names.

//----------- Begin Cut here for INSTANTIATION Template ---// INST_TAG
qdma_0 your_instance_name (
  .sys_clk(sys_clk),                                                            // input wire sys_clk
  .sys_clk_gt(sys_clk_gt),                                                      // input wire sys_clk_gt
  .sys_rst_n(sys_rst_n),                                                        // input wire sys_rst_n
  .user_lnk_up(user_lnk_up),                                                    // output wire user_lnk_up
  .pci_exp_txp(pci_exp_txp),                                                    // output wire [15 : 0] pci_exp_txp
  .pci_exp_txn(pci_exp_txn),                                                    // output wire [15 : 0] pci_exp_txn
  .pci_exp_rxp(pci_exp_rxp),                                                    // input wire [15 : 0] pci_exp_rxp
  .pci_exp_rxn(pci_exp_rxn),                                                    // input wire [15 : 0] pci_exp_rxn
  .axi_aclk(axi_aclk),                                                          // output wire axi_aclk
  .axi_aresetn(axi_aresetn),                                                    // output wire axi_aresetn
  .usr_irq_in_vld(usr_irq_in_vld),                                              // input wire usr_irq_in_vld
  .usr_irq_in_vec(usr_irq_in_vec),                                              // input wire [10 : 0] usr_irq_in_vec
  .usr_irq_in_fnc(usr_irq_in_fnc),                                              // input wire [7 : 0] usr_irq_in_fnc
  .usr_irq_out_ack(usr_irq_out_ack),                                            // output wire usr_irq_out_ack
  .usr_irq_out_fail(usr_irq_out_fail),                                          // output wire usr_irq_out_fail
  .usr_flr_fnc(usr_flr_fnc),                                                    // output wire [7 : 0] usr_flr_fnc
  .usr_flr_set(usr_flr_set),                                                    // output wire usr_flr_set
  .usr_flr_done_fnc(usr_flr_done_fnc),                                          // input wire [7 : 0] usr_flr_done_fnc
  .usr_flr_done_vld(usr_flr_done_vld),                                          // input wire usr_flr_done_vld
  .tm_dsc_sts_vld(tm_dsc_sts_vld),                                              // output wire tm_dsc_sts_vld
  .tm_dsc_sts_port_id(tm_dsc_sts_port_id),                                      // output wire [2 : 0] tm_dsc_sts_port_id
  .tm_dsc_sts_qen(tm_dsc_sts_qen),                                              // output wire tm_dsc_sts_qen
  .tm_dsc_sts_byp(tm_dsc_sts_byp),                                              // output wire tm_dsc_sts_byp
  .tm_dsc_sts_dir(tm_dsc_sts_dir),                                              // output wire tm_dsc_sts_dir
  .tm_dsc_sts_mm(tm_dsc_sts_mm),                                                // output wire tm_dsc_sts_mm
  .tm_dsc_sts_error(tm_dsc_sts_error),                                          // output wire tm_dsc_sts_error
  .tm_dsc_sts_qid(tm_dsc_sts_qid),                                              // output wire [10 : 0] tm_dsc_sts_qid
  .tm_dsc_sts_avl(tm_dsc_sts_avl),                                              // output wire [15 : 0] tm_dsc_sts_avl
  .tm_dsc_sts_qinv(tm_dsc_sts_qinv),                                            // output wire tm_dsc_sts_qinv
  .tm_dsc_sts_irq_arm(tm_dsc_sts_irq_arm),                                      // output wire tm_dsc_sts_irq_arm
  .tm_dsc_sts_rdy(tm_dsc_sts_rdy),                                              // input wire tm_dsc_sts_rdy
  .tm_dsc_sts_pidx(tm_dsc_sts_pidx),                                            // output wire [15 : 0] tm_dsc_sts_pidx
  .dsc_crdt_in_crdt(dsc_crdt_in_crdt),                                          // input wire [15 : 0] dsc_crdt_in_crdt
  .dsc_crdt_in_qid(dsc_crdt_in_qid),                                            // input wire [10 : 0] dsc_crdt_in_qid
  .dsc_crdt_in_dir(dsc_crdt_in_dir),                                            // input wire dsc_crdt_in_dir
  .dsc_crdt_in_fence(dsc_crdt_in_fence),                                        // input wire dsc_crdt_in_fence
  .dsc_crdt_in_vld(dsc_crdt_in_vld),                                            // input wire dsc_crdt_in_vld
  .dsc_crdt_in_rdy(dsc_crdt_in_rdy),                                            // output wire dsc_crdt_in_rdy
  .m_axi_awready(m_axi_awready),                                                // input wire m_axi_awready
  .m_axi_wready(m_axi_wready),                                                  // input wire m_axi_wready
  .m_axi_bid(m_axi_bid),                                                        // input wire [3 : 0] m_axi_bid
  .m_axi_bresp(m_axi_bresp),                                                    // input wire [1 : 0] m_axi_bresp
  .m_axi_bvalid(m_axi_bvalid),                                                  // input wire m_axi_bvalid
  .m_axi_arready(m_axi_arready),                                                // input wire m_axi_arready
  .m_axi_rid(m_axi_rid),                                                        // input wire [3 : 0] m_axi_rid
  .m_axi_rdata(m_axi_rdata),                                                    // input wire [511 : 0] m_axi_rdata
  .m_axi_rresp(m_axi_rresp),                                                    // input wire [1 : 0] m_axi_rresp
  .m_axi_rlast(m_axi_rlast),                                                    // input wire m_axi_rlast
  .m_axi_rvalid(m_axi_rvalid),                                                  // input wire m_axi_rvalid
  .m_axi_awid(m_axi_awid),                                                      // output wire [3 : 0] m_axi_awid
  .m_axi_awaddr(m_axi_awaddr),                                                  // output wire [63 : 0] m_axi_awaddr
  .m_axi_awuser(m_axi_awuser),                                                  // output wire [31 : 0] m_axi_awuser
  .m_axi_awlen(m_axi_awlen),                                                    // output wire [7 : 0] m_axi_awlen
  .m_axi_awsize(m_axi_awsize),                                                  // output wire [2 : 0] m_axi_awsize
  .m_axi_awburst(m_axi_awburst),                                                // output wire [1 : 0] m_axi_awburst
  .m_axi_awprot(m_axi_awprot),                                                  // output wire [2 : 0] m_axi_awprot
  .m_axi_awvalid(m_axi_awvalid),                                                // output wire m_axi_awvalid
  .m_axi_awlock(m_axi_awlock),                                                  // output wire m_axi_awlock
  .m_axi_awcache(m_axi_awcache),                                                // output wire [3 : 0] m_axi_awcache
  .m_axi_wdata(m_axi_wdata),                                                    // output wire [511 : 0] m_axi_wdata
  .m_axi_wuser(m_axi_wuser),                                                    // output wire [63 : 0] m_axi_wuser
  .m_axi_wstrb(m_axi_wstrb),                                                    // output wire [63 : 0] m_axi_wstrb
  .m_axi_wlast(m_axi_wlast),                                                    // output wire m_axi_wlast
  .m_axi_wvalid(m_axi_wvalid),                                                  // output wire m_axi_wvalid
  .m_axi_bready(m_axi_bready),                                                  // output wire m_axi_bready
  .m_axi_arid(m_axi_arid),                                                      // output wire [3 : 0] m_axi_arid
  .m_axi_araddr(m_axi_araddr),                                                  // output wire [63 : 0] m_axi_araddr
  .m_axi_aruser(m_axi_aruser),                                                  // output wire [31 : 0] m_axi_aruser
  .m_axi_arlen(m_axi_arlen),                                                    // output wire [7 : 0] m_axi_arlen
  .m_axi_arsize(m_axi_arsize),                                                  // output wire [2 : 0] m_axi_arsize
  .m_axi_arburst(m_axi_arburst),                                                // output wire [1 : 0] m_axi_arburst
  .m_axi_arprot(m_axi_arprot),                                                  // output wire [2 : 0] m_axi_arprot
  .m_axi_arvalid(m_axi_arvalid),                                                // output wire m_axi_arvalid
  .m_axi_arlock(m_axi_arlock),                                                  // output wire m_axi_arlock
  .m_axi_arcache(m_axi_arcache),                                                // output wire [3 : 0] m_axi_arcache
  .m_axi_rready(m_axi_rready),                                                  // output wire m_axi_rready
  .m_axil_awaddr(m_axil_awaddr),                                                // output wire [31 : 0] m_axil_awaddr
  .m_axil_awuser(m_axil_awuser),                                                // output wire [54 : 0] m_axil_awuser
  .m_axil_awprot(m_axil_awprot),                                                // output wire [2 : 0] m_axil_awprot
  .m_axil_awvalid(m_axil_awvalid),                                              // output wire m_axil_awvalid
  .m_axil_awready(m_axil_awready),                                              // input wire m_axil_awready
  .m_axil_wdata(m_axil_wdata),                                                  // output wire [31 : 0] m_axil_wdata
  .m_axil_wstrb(m_axil_wstrb),                                                  // output wire [3 : 0] m_axil_wstrb
  .m_axil_wvalid(m_axil_wvalid),                                                // output wire m_axil_wvalid
  .m_axil_wready(m_axil_wready),                                                // input wire m_axil_wready
  .m_axil_bvalid(m_axil_bvalid),                                                // input wire m_axil_bvalid
  .m_axil_bresp(m_axil_bresp),                                                  // input wire [1 : 0] m_axil_bresp
  .m_axil_bready(m_axil_bready),                                                // output wire m_axil_bready
  .m_axil_araddr(m_axil_araddr),                                                // output wire [31 : 0] m_axil_araddr
  .m_axil_aruser(m_axil_aruser),                                                // output wire [54 : 0] m_axil_aruser
  .m_axil_arprot(m_axil_arprot),                                                // output wire [2 : 0] m_axil_arprot
  .m_axil_arvalid(m_axil_arvalid),                                              // output wire m_axil_arvalid
  .m_axil_arready(m_axil_arready),                                              // input wire m_axil_arready
  .m_axil_rdata(m_axil_rdata),                                                  // input wire [31 : 0] m_axil_rdata
  .m_axil_rresp(m_axil_rresp),                                                  // input wire [1 : 0] m_axil_rresp
  .m_axil_rvalid(m_axil_rvalid),                                                // input wire m_axil_rvalid
  .m_axil_rready(m_axil_rready),                                                // output wire m_axil_rready
  .m_axis_h2c_tdata(m_axis_h2c_tdata),                                          // output wire [511 : 0] m_axis_h2c_tdata
  .m_axis_h2c_tcrc(m_axis_h2c_tcrc),                                            // output wire [31 : 0] m_axis_h2c_tcrc
  .m_axis_h2c_tuser_qid(m_axis_h2c_tuser_qid),                                  // output wire [10 : 0] m_axis_h2c_tuser_qid
  .m_axis_h2c_tuser_port_id(m_axis_h2c_tuser_port_id),                          // output wire [2 : 0] m_axis_h2c_tuser_port_id
  .m_axis_h2c_tuser_err(m_axis_h2c_tuser_err),                                  // output wire m_axis_h2c_tuser_err
  .m_axis_h2c_tuser_mdata(m_axis_h2c_tuser_mdata),                              // output wire [31 : 0] m_axis_h2c_tuser_mdata
  .m_axis_h2c_tuser_mty(m_axis_h2c_tuser_mty),                                  // output wire [5 : 0] m_axis_h2c_tuser_mty
  .m_axis_h2c_tuser_zero_byte(m_axis_h2c_tuser_zero_byte),                      // output wire m_axis_h2c_tuser_zero_byte
  .m_axis_h2c_tvalid(m_axis_h2c_tvalid),                                        // output wire m_axis_h2c_tvalid
  .m_axis_h2c_tlast(m_axis_h2c_tlast),                                          // output wire m_axis_h2c_tlast
  .m_axis_h2c_tready(m_axis_h2c_tready),                                        // input wire m_axis_h2c_tready
  .s_axis_c2h_tdata(s_axis_c2h_tdata),                                          // input wire [511 : 0] s_axis_c2h_tdata
  .s_axis_c2h_tcrc(s_axis_c2h_tcrc),                                            // input wire [31 : 0] s_axis_c2h_tcrc
  .s_axis_c2h_ctrl_marker(s_axis_c2h_ctrl_marker),                              // input wire s_axis_c2h_ctrl_marker
  .s_axis_c2h_ctrl_port_id(s_axis_c2h_ctrl_port_id),                            // input wire [2 : 0] s_axis_c2h_ctrl_port_id
  .s_axis_c2h_ctrl_ecc(s_axis_c2h_ctrl_ecc),                                    // input wire [6 : 0] s_axis_c2h_ctrl_ecc
  .s_axis_c2h_ctrl_len(s_axis_c2h_ctrl_len),                                    // input wire [15 : 0] s_axis_c2h_ctrl_len
  .s_axis_c2h_ctrl_qid(s_axis_c2h_ctrl_qid),                                    // input wire [10 : 0] s_axis_c2h_ctrl_qid
  .s_axis_c2h_ctrl_has_cmpt(s_axis_c2h_ctrl_has_cmpt),                          // input wire s_axis_c2h_ctrl_has_cmpt
  .s_axis_c2h_mty(s_axis_c2h_mty),                                              // input wire [5 : 0] s_axis_c2h_mty
  .s_axis_c2h_tvalid(s_axis_c2h_tvalid),                                        // input wire s_axis_c2h_tvalid
  .s_axis_c2h_tlast(s_axis_c2h_tlast),                                          // input wire s_axis_c2h_tlast
  .s_axis_c2h_tready(s_axis_c2h_tready),                                        // output wire s_axis_c2h_tready
  .s_axis_c2h_cmpt_tdata(s_axis_c2h_cmpt_tdata),                                // input wire [511 : 0] s_axis_c2h_cmpt_tdata
  .s_axis_c2h_cmpt_size(s_axis_c2h_cmpt_size),                                  // input wire [1 : 0] s_axis_c2h_cmpt_size
  .s_axis_c2h_cmpt_dpar(s_axis_c2h_cmpt_dpar),                                  // input wire [15 : 0] s_axis_c2h_cmpt_dpar
  .s_axis_c2h_cmpt_tvalid(s_axis_c2h_cmpt_tvalid),                              // input wire s_axis_c2h_cmpt_tvalid
  .s_axis_c2h_cmpt_ctrl_qid(s_axis_c2h_cmpt_ctrl_qid),                          // input wire [10 : 0] s_axis_c2h_cmpt_ctrl_qid
  .s_axis_c2h_cmpt_ctrl_cmpt_type(s_axis_c2h_cmpt_ctrl_cmpt_type),              // input wire [1 : 0] s_axis_c2h_cmpt_ctrl_cmpt_type
  .s_axis_c2h_cmpt_ctrl_wait_pld_pkt_id(s_axis_c2h_cmpt_ctrl_wait_pld_pkt_id),  // input wire [15 : 0] s_axis_c2h_cmpt_ctrl_wait_pld_pkt_id
  .s_axis_c2h_cmpt_ctrl_port_id(s_axis_c2h_cmpt_ctrl_port_id),                  // input wire [2 : 0] s_axis_c2h_cmpt_ctrl_port_id
  .s_axis_c2h_cmpt_ctrl_marker(s_axis_c2h_cmpt_ctrl_marker),                    // input wire s_axis_c2h_cmpt_ctrl_marker
  .s_axis_c2h_cmpt_ctrl_user_trig(s_axis_c2h_cmpt_ctrl_user_trig),              // input wire s_axis_c2h_cmpt_ctrl_user_trig
  .s_axis_c2h_cmpt_ctrl_col_idx(s_axis_c2h_cmpt_ctrl_col_idx),                  // input wire [2 : 0] s_axis_c2h_cmpt_ctrl_col_idx
  .s_axis_c2h_cmpt_ctrl_err_idx(s_axis_c2h_cmpt_ctrl_err_idx),                  // input wire [2 : 0] s_axis_c2h_cmpt_ctrl_err_idx
  .s_axis_c2h_cmpt_tready(s_axis_c2h_cmpt_tready),                              // output wire s_axis_c2h_cmpt_tready
  .s_axis_c2h_cmpt_ctrl_no_wrb_marker(s_axis_c2h_cmpt_ctrl_no_wrb_marker),      // input wire s_axis_c2h_cmpt_ctrl_no_wrb_marker
  .axis_c2h_status_drop(axis_c2h_status_drop),                                  // output wire axis_c2h_status_drop
  .axis_c2h_status_valid(axis_c2h_status_valid),                                // output wire axis_c2h_status_valid
  .axis_c2h_status_cmp(axis_c2h_status_cmp),                                    // output wire axis_c2h_status_cmp
  .axis_c2h_status_error(axis_c2h_status_error),                                // output wire axis_c2h_status_error
  .axis_c2h_status_last(axis_c2h_status_last),                                  // output wire axis_c2h_status_last
  .axis_c2h_status_qid(axis_c2h_status_qid),                                    // output wire [10 : 0] axis_c2h_status_qid
  .axis_c2h_dmawr_cmp(axis_c2h_dmawr_cmp),                                      // output wire axis_c2h_dmawr_cmp
  .soft_reset_n(soft_reset_n),                                                  // input wire soft_reset_n
  .phy_ready(phy_ready),                                                        // output wire phy_ready
  .qsts_out_op(qsts_out_op),                                                    // output wire [7 : 0] qsts_out_op
  .qsts_out_data(qsts_out_data),                                                // output wire [63 : 0] qsts_out_data
  .qsts_out_port_id(qsts_out_port_id),                                          // output wire [2 : 0] qsts_out_port_id
  .qsts_out_qid(qsts_out_qid),                                                  // output wire [12 : 0] qsts_out_qid
  .qsts_out_vld(qsts_out_vld),                                                  // output wire qsts_out_vld
  .qsts_out_rdy(qsts_out_rdy)                                                  // input wire qsts_out_rdy
);
// INST_TAG_END ------ End INSTANTIATION Template ---------

// You must compile the wrapper file qdma_0.v when simulating
// the core, qdma_0. When compiling the wrapper file, be sure to
// reference the Verilog simulation library.

