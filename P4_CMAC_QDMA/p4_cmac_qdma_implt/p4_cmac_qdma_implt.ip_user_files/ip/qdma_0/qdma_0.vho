-- (c) Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
-- (c) Copyright 2022-2025 Advanced Micro Devices, Inc. All rights reserved.
-- 
-- This file contains confidential and proprietary information
-- of AMD and is protected under U.S. and international copyright
-- and other intellectual property laws.
-- 
-- DISCLAIMER
-- This disclaimer is not a license and does not grant any
-- rights to the materials distributed herewith. Except as
-- otherwise provided in a valid license issued to you by
-- AMD, and to the maximum extent permitted by applicable
-- law: (1) THESE MATERIALS ARE MADE AVAILABLE "AS IS" AND
-- WITH ALL FAULTS, AND AMD HEREBY DISCLAIMS ALL WARRANTIES
-- AND CONDITIONS, EXPRESS, IMPLIED, OR STATUTORY, INCLUDING
-- BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, NON-
-- INFRINGEMENT, OR FITNESS FOR ANY PARTICULAR PURPOSE; and
-- (2) AMD shall not be liable (whether in contract or tort,
-- including negligence, or under any other theory of
-- liability) for any loss or damage of any kind or nature
-- related to, arising under or in connection with these
-- materials, including for any direct, or any indirect,
-- special, incidental, or consequential loss or damage
-- (including loss of data, profits, goodwill, or any type of
-- loss or damage suffered as a result of any action brought
-- by a third party) even if such damage or loss was
-- reasonably foreseeable or AMD had been advised of the
-- possibility of the same.
-- 
-- CRITICAL APPLICATIONS
-- AMD products are not designed or intended to be fail-
-- safe, or for use in any application requiring fail-safe
-- performance, such as life-support or safety devices or
-- systems, Class III medical devices, nuclear facilities,
-- applications related to the deployment of airbags, or any
-- other applications that could lead to death, personal
-- injury, or severe property or environmental damage
-- (individually and collectively, "Critical
-- Applications"). Customer assumes the sole risk and
-- liability of any use of AMD products in Critical
-- Applications, subject only to applicable laws and
-- regulations governing limitations on product liability.
-- 
-- THIS COPYRIGHT NOTICE AND DISCLAIMER MUST BE RETAINED AS
-- PART OF THIS FILE AT ALL TIMES.
-- 
-- DO NOT MODIFY THIS FILE.
-- IP VLNV: xilinx.com:ip:qdma:5.0
-- IP Revision: 6

-- The following code must appear in the VHDL architecture header.

------------- Begin Cut here for COMPONENT Declaration ------ COMP_TAG
COMPONENT qdma_0
  PORT (
    sys_clk : IN STD_LOGIC;
    sys_clk_gt : IN STD_LOGIC;
    sys_rst_n : IN STD_LOGIC;
    user_lnk_up : OUT STD_LOGIC;
    pci_exp_txp : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
    pci_exp_txn : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
    pci_exp_rxp : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
    pci_exp_rxn : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
    axi_aclk : OUT STD_LOGIC;
    axi_aresetn : OUT STD_LOGIC;
    usr_irq_in_vld : IN STD_LOGIC;
    usr_irq_in_vec : IN STD_LOGIC_VECTOR(10 DOWNTO 0);
    usr_irq_in_fnc : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
    usr_irq_out_ack : OUT STD_LOGIC;
    usr_irq_out_fail : OUT STD_LOGIC;
    usr_flr_fnc : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
    usr_flr_set : OUT STD_LOGIC;
    usr_flr_done_fnc : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
    usr_flr_done_vld : IN STD_LOGIC;
    tm_dsc_sts_vld : OUT STD_LOGIC;
    tm_dsc_sts_port_id : OUT STD_LOGIC_VECTOR(2 DOWNTO 0);
    tm_dsc_sts_qen : OUT STD_LOGIC;
    tm_dsc_sts_byp : OUT STD_LOGIC;
    tm_dsc_sts_dir : OUT STD_LOGIC;
    tm_dsc_sts_mm : OUT STD_LOGIC;
    tm_dsc_sts_error : OUT STD_LOGIC;
    tm_dsc_sts_qid : OUT STD_LOGIC_VECTOR(10 DOWNTO 0);
    tm_dsc_sts_avl : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
    tm_dsc_sts_qinv : OUT STD_LOGIC;
    tm_dsc_sts_irq_arm : OUT STD_LOGIC;
    tm_dsc_sts_rdy : IN STD_LOGIC;
    tm_dsc_sts_pidx : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
    dsc_crdt_in_crdt : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
    dsc_crdt_in_qid : IN STD_LOGIC_VECTOR(10 DOWNTO 0);
    dsc_crdt_in_dir : IN STD_LOGIC;
    dsc_crdt_in_fence : IN STD_LOGIC;
    dsc_crdt_in_vld : IN STD_LOGIC;
    dsc_crdt_in_rdy : OUT STD_LOGIC;
    m_axi_awready : IN STD_LOGIC;
    m_axi_wready : IN STD_LOGIC;
    m_axi_bid : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
    m_axi_bresp : IN STD_LOGIC_VECTOR(1 DOWNTO 0);
    m_axi_bvalid : IN STD_LOGIC;
    m_axi_arready : IN STD_LOGIC;
    m_axi_rid : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
    m_axi_rdata : IN STD_LOGIC_VECTOR(511 DOWNTO 0);
    m_axi_rresp : IN STD_LOGIC_VECTOR(1 DOWNTO 0);
    m_axi_rlast : IN STD_LOGIC;
    m_axi_rvalid : IN STD_LOGIC;
    m_axi_awid : OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
    m_axi_awaddr : OUT STD_LOGIC_VECTOR(63 DOWNTO 0);
    m_axi_awuser : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
    m_axi_awlen : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
    m_axi_awsize : OUT STD_LOGIC_VECTOR(2 DOWNTO 0);
    m_axi_awburst : OUT STD_LOGIC_VECTOR(1 DOWNTO 0);
    m_axi_awprot : OUT STD_LOGIC_VECTOR(2 DOWNTO 0);
    m_axi_awvalid : OUT STD_LOGIC;
    m_axi_awlock : OUT STD_LOGIC;
    m_axi_awcache : OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
    m_axi_wdata : OUT STD_LOGIC_VECTOR(511 DOWNTO 0);
    m_axi_wuser : OUT STD_LOGIC_VECTOR(63 DOWNTO 0);
    m_axi_wstrb : OUT STD_LOGIC_VECTOR(63 DOWNTO 0);
    m_axi_wlast : OUT STD_LOGIC;
    m_axi_wvalid : OUT STD_LOGIC;
    m_axi_bready : OUT STD_LOGIC;
    m_axi_arid : OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
    m_axi_araddr : OUT STD_LOGIC_VECTOR(63 DOWNTO 0);
    m_axi_aruser : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
    m_axi_arlen : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
    m_axi_arsize : OUT STD_LOGIC_VECTOR(2 DOWNTO 0);
    m_axi_arburst : OUT STD_LOGIC_VECTOR(1 DOWNTO 0);
    m_axi_arprot : OUT STD_LOGIC_VECTOR(2 DOWNTO 0);
    m_axi_arvalid : OUT STD_LOGIC;
    m_axi_arlock : OUT STD_LOGIC;
    m_axi_arcache : OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
    m_axi_rready : OUT STD_LOGIC;
    m_axil_awaddr : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
    m_axil_awuser : OUT STD_LOGIC_VECTOR(54 DOWNTO 0);
    m_axil_awprot : OUT STD_LOGIC_VECTOR(2 DOWNTO 0);
    m_axil_awvalid : OUT STD_LOGIC;
    m_axil_awready : IN STD_LOGIC;
    m_axil_wdata : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
    m_axil_wstrb : OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
    m_axil_wvalid : OUT STD_LOGIC;
    m_axil_wready : IN STD_LOGIC;
    m_axil_bvalid : IN STD_LOGIC;
    m_axil_bresp : IN STD_LOGIC_VECTOR(1 DOWNTO 0);
    m_axil_bready : OUT STD_LOGIC;
    m_axil_araddr : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
    m_axil_aruser : OUT STD_LOGIC_VECTOR(54 DOWNTO 0);
    m_axil_arprot : OUT STD_LOGIC_VECTOR(2 DOWNTO 0);
    m_axil_arvalid : OUT STD_LOGIC;
    m_axil_arready : IN STD_LOGIC;
    m_axil_rdata : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
    m_axil_rresp : IN STD_LOGIC_VECTOR(1 DOWNTO 0);
    m_axil_rvalid : IN STD_LOGIC;
    m_axil_rready : OUT STD_LOGIC;
    m_axis_h2c_tdata : OUT STD_LOGIC_VECTOR(511 DOWNTO 0);
    m_axis_h2c_tcrc : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
    m_axis_h2c_tuser_qid : OUT STD_LOGIC_VECTOR(10 DOWNTO 0);
    m_axis_h2c_tuser_port_id : OUT STD_LOGIC_VECTOR(2 DOWNTO 0);
    m_axis_h2c_tuser_err : OUT STD_LOGIC;
    m_axis_h2c_tuser_mdata : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
    m_axis_h2c_tuser_mty : OUT STD_LOGIC_VECTOR(5 DOWNTO 0);
    m_axis_h2c_tuser_zero_byte : OUT STD_LOGIC;
    m_axis_h2c_tvalid : OUT STD_LOGIC;
    m_axis_h2c_tlast : OUT STD_LOGIC;
    m_axis_h2c_tready : IN STD_LOGIC;
    s_axis_c2h_tdata : IN STD_LOGIC_VECTOR(511 DOWNTO 0);
    s_axis_c2h_tcrc : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
    s_axis_c2h_ctrl_marker : IN STD_LOGIC;
    s_axis_c2h_ctrl_port_id : IN STD_LOGIC_VECTOR(2 DOWNTO 0);
    s_axis_c2h_ctrl_ecc : IN STD_LOGIC_VECTOR(6 DOWNTO 0);
    s_axis_c2h_ctrl_len : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
    s_axis_c2h_ctrl_qid : IN STD_LOGIC_VECTOR(10 DOWNTO 0);
    s_axis_c2h_ctrl_has_cmpt : IN STD_LOGIC;
    s_axis_c2h_mty : IN STD_LOGIC_VECTOR(5 DOWNTO 0);
    s_axis_c2h_tvalid : IN STD_LOGIC;
    s_axis_c2h_tlast : IN STD_LOGIC;
    s_axis_c2h_tready : OUT STD_LOGIC;
    s_axis_c2h_cmpt_tdata : IN STD_LOGIC_VECTOR(511 DOWNTO 0);
    s_axis_c2h_cmpt_size : IN STD_LOGIC_VECTOR(1 DOWNTO 0);
    s_axis_c2h_cmpt_dpar : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
    s_axis_c2h_cmpt_tvalid : IN STD_LOGIC;
    s_axis_c2h_cmpt_ctrl_qid : IN STD_LOGIC_VECTOR(10 DOWNTO 0);
    s_axis_c2h_cmpt_ctrl_cmpt_type : IN STD_LOGIC_VECTOR(1 DOWNTO 0);
    s_axis_c2h_cmpt_ctrl_wait_pld_pkt_id : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
    s_axis_c2h_cmpt_ctrl_port_id : IN STD_LOGIC_VECTOR(2 DOWNTO 0);
    s_axis_c2h_cmpt_ctrl_marker : IN STD_LOGIC;
    s_axis_c2h_cmpt_ctrl_user_trig : IN STD_LOGIC;
    s_axis_c2h_cmpt_ctrl_col_idx : IN STD_LOGIC_VECTOR(2 DOWNTO 0);
    s_axis_c2h_cmpt_ctrl_err_idx : IN STD_LOGIC_VECTOR(2 DOWNTO 0);
    s_axis_c2h_cmpt_tready : OUT STD_LOGIC;
    s_axis_c2h_cmpt_ctrl_no_wrb_marker : IN STD_LOGIC;
    axis_c2h_status_drop : OUT STD_LOGIC;
    axis_c2h_status_valid : OUT STD_LOGIC;
    axis_c2h_status_cmp : OUT STD_LOGIC;
    axis_c2h_status_error : OUT STD_LOGIC;
    axis_c2h_status_last : OUT STD_LOGIC;
    axis_c2h_status_qid : OUT STD_LOGIC_VECTOR(10 DOWNTO 0);
    axis_c2h_dmawr_cmp : OUT STD_LOGIC;
    soft_reset_n : IN STD_LOGIC;
    phy_ready : OUT STD_LOGIC;
    qsts_out_op : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
    qsts_out_data : OUT STD_LOGIC_VECTOR(63 DOWNTO 0);
    qsts_out_port_id : OUT STD_LOGIC_VECTOR(2 DOWNTO 0);
    qsts_out_qid : OUT STD_LOGIC_VECTOR(12 DOWNTO 0);
    qsts_out_vld : OUT STD_LOGIC;
    qsts_out_rdy : IN STD_LOGIC 
  );
END COMPONENT;
-- COMP_TAG_END ------ End COMPONENT Declaration ------------

-- The following code must appear in the VHDL architecture
-- body. Substitute your own instance name and net names.

------------- Begin Cut here for INSTANTIATION Template ----- INST_TAG
your_instance_name : qdma_0
  PORT MAP (
    sys_clk => sys_clk,
    sys_clk_gt => sys_clk_gt,
    sys_rst_n => sys_rst_n,
    user_lnk_up => user_lnk_up,
    pci_exp_txp => pci_exp_txp,
    pci_exp_txn => pci_exp_txn,
    pci_exp_rxp => pci_exp_rxp,
    pci_exp_rxn => pci_exp_rxn,
    axi_aclk => axi_aclk,
    axi_aresetn => axi_aresetn,
    usr_irq_in_vld => usr_irq_in_vld,
    usr_irq_in_vec => usr_irq_in_vec,
    usr_irq_in_fnc => usr_irq_in_fnc,
    usr_irq_out_ack => usr_irq_out_ack,
    usr_irq_out_fail => usr_irq_out_fail,
    usr_flr_fnc => usr_flr_fnc,
    usr_flr_set => usr_flr_set,
    usr_flr_done_fnc => usr_flr_done_fnc,
    usr_flr_done_vld => usr_flr_done_vld,
    tm_dsc_sts_vld => tm_dsc_sts_vld,
    tm_dsc_sts_port_id => tm_dsc_sts_port_id,
    tm_dsc_sts_qen => tm_dsc_sts_qen,
    tm_dsc_sts_byp => tm_dsc_sts_byp,
    tm_dsc_sts_dir => tm_dsc_sts_dir,
    tm_dsc_sts_mm => tm_dsc_sts_mm,
    tm_dsc_sts_error => tm_dsc_sts_error,
    tm_dsc_sts_qid => tm_dsc_sts_qid,
    tm_dsc_sts_avl => tm_dsc_sts_avl,
    tm_dsc_sts_qinv => tm_dsc_sts_qinv,
    tm_dsc_sts_irq_arm => tm_dsc_sts_irq_arm,
    tm_dsc_sts_rdy => tm_dsc_sts_rdy,
    tm_dsc_sts_pidx => tm_dsc_sts_pidx,
    dsc_crdt_in_crdt => dsc_crdt_in_crdt,
    dsc_crdt_in_qid => dsc_crdt_in_qid,
    dsc_crdt_in_dir => dsc_crdt_in_dir,
    dsc_crdt_in_fence => dsc_crdt_in_fence,
    dsc_crdt_in_vld => dsc_crdt_in_vld,
    dsc_crdt_in_rdy => dsc_crdt_in_rdy,
    m_axi_awready => m_axi_awready,
    m_axi_wready => m_axi_wready,
    m_axi_bid => m_axi_bid,
    m_axi_bresp => m_axi_bresp,
    m_axi_bvalid => m_axi_bvalid,
    m_axi_arready => m_axi_arready,
    m_axi_rid => m_axi_rid,
    m_axi_rdata => m_axi_rdata,
    m_axi_rresp => m_axi_rresp,
    m_axi_rlast => m_axi_rlast,
    m_axi_rvalid => m_axi_rvalid,
    m_axi_awid => m_axi_awid,
    m_axi_awaddr => m_axi_awaddr,
    m_axi_awuser => m_axi_awuser,
    m_axi_awlen => m_axi_awlen,
    m_axi_awsize => m_axi_awsize,
    m_axi_awburst => m_axi_awburst,
    m_axi_awprot => m_axi_awprot,
    m_axi_awvalid => m_axi_awvalid,
    m_axi_awlock => m_axi_awlock,
    m_axi_awcache => m_axi_awcache,
    m_axi_wdata => m_axi_wdata,
    m_axi_wuser => m_axi_wuser,
    m_axi_wstrb => m_axi_wstrb,
    m_axi_wlast => m_axi_wlast,
    m_axi_wvalid => m_axi_wvalid,
    m_axi_bready => m_axi_bready,
    m_axi_arid => m_axi_arid,
    m_axi_araddr => m_axi_araddr,
    m_axi_aruser => m_axi_aruser,
    m_axi_arlen => m_axi_arlen,
    m_axi_arsize => m_axi_arsize,
    m_axi_arburst => m_axi_arburst,
    m_axi_arprot => m_axi_arprot,
    m_axi_arvalid => m_axi_arvalid,
    m_axi_arlock => m_axi_arlock,
    m_axi_arcache => m_axi_arcache,
    m_axi_rready => m_axi_rready,
    m_axil_awaddr => m_axil_awaddr,
    m_axil_awuser => m_axil_awuser,
    m_axil_awprot => m_axil_awprot,
    m_axil_awvalid => m_axil_awvalid,
    m_axil_awready => m_axil_awready,
    m_axil_wdata => m_axil_wdata,
    m_axil_wstrb => m_axil_wstrb,
    m_axil_wvalid => m_axil_wvalid,
    m_axil_wready => m_axil_wready,
    m_axil_bvalid => m_axil_bvalid,
    m_axil_bresp => m_axil_bresp,
    m_axil_bready => m_axil_bready,
    m_axil_araddr => m_axil_araddr,
    m_axil_aruser => m_axil_aruser,
    m_axil_arprot => m_axil_arprot,
    m_axil_arvalid => m_axil_arvalid,
    m_axil_arready => m_axil_arready,
    m_axil_rdata => m_axil_rdata,
    m_axil_rresp => m_axil_rresp,
    m_axil_rvalid => m_axil_rvalid,
    m_axil_rready => m_axil_rready,
    m_axis_h2c_tdata => m_axis_h2c_tdata,
    m_axis_h2c_tcrc => m_axis_h2c_tcrc,
    m_axis_h2c_tuser_qid => m_axis_h2c_tuser_qid,
    m_axis_h2c_tuser_port_id => m_axis_h2c_tuser_port_id,
    m_axis_h2c_tuser_err => m_axis_h2c_tuser_err,
    m_axis_h2c_tuser_mdata => m_axis_h2c_tuser_mdata,
    m_axis_h2c_tuser_mty => m_axis_h2c_tuser_mty,
    m_axis_h2c_tuser_zero_byte => m_axis_h2c_tuser_zero_byte,
    m_axis_h2c_tvalid => m_axis_h2c_tvalid,
    m_axis_h2c_tlast => m_axis_h2c_tlast,
    m_axis_h2c_tready => m_axis_h2c_tready,
    s_axis_c2h_tdata => s_axis_c2h_tdata,
    s_axis_c2h_tcrc => s_axis_c2h_tcrc,
    s_axis_c2h_ctrl_marker => s_axis_c2h_ctrl_marker,
    s_axis_c2h_ctrl_port_id => s_axis_c2h_ctrl_port_id,
    s_axis_c2h_ctrl_ecc => s_axis_c2h_ctrl_ecc,
    s_axis_c2h_ctrl_len => s_axis_c2h_ctrl_len,
    s_axis_c2h_ctrl_qid => s_axis_c2h_ctrl_qid,
    s_axis_c2h_ctrl_has_cmpt => s_axis_c2h_ctrl_has_cmpt,
    s_axis_c2h_mty => s_axis_c2h_mty,
    s_axis_c2h_tvalid => s_axis_c2h_tvalid,
    s_axis_c2h_tlast => s_axis_c2h_tlast,
    s_axis_c2h_tready => s_axis_c2h_tready,
    s_axis_c2h_cmpt_tdata => s_axis_c2h_cmpt_tdata,
    s_axis_c2h_cmpt_size => s_axis_c2h_cmpt_size,
    s_axis_c2h_cmpt_dpar => s_axis_c2h_cmpt_dpar,
    s_axis_c2h_cmpt_tvalid => s_axis_c2h_cmpt_tvalid,
    s_axis_c2h_cmpt_ctrl_qid => s_axis_c2h_cmpt_ctrl_qid,
    s_axis_c2h_cmpt_ctrl_cmpt_type => s_axis_c2h_cmpt_ctrl_cmpt_type,
    s_axis_c2h_cmpt_ctrl_wait_pld_pkt_id => s_axis_c2h_cmpt_ctrl_wait_pld_pkt_id,
    s_axis_c2h_cmpt_ctrl_port_id => s_axis_c2h_cmpt_ctrl_port_id,
    s_axis_c2h_cmpt_ctrl_marker => s_axis_c2h_cmpt_ctrl_marker,
    s_axis_c2h_cmpt_ctrl_user_trig => s_axis_c2h_cmpt_ctrl_user_trig,
    s_axis_c2h_cmpt_ctrl_col_idx => s_axis_c2h_cmpt_ctrl_col_idx,
    s_axis_c2h_cmpt_ctrl_err_idx => s_axis_c2h_cmpt_ctrl_err_idx,
    s_axis_c2h_cmpt_tready => s_axis_c2h_cmpt_tready,
    s_axis_c2h_cmpt_ctrl_no_wrb_marker => s_axis_c2h_cmpt_ctrl_no_wrb_marker,
    axis_c2h_status_drop => axis_c2h_status_drop,
    axis_c2h_status_valid => axis_c2h_status_valid,
    axis_c2h_status_cmp => axis_c2h_status_cmp,
    axis_c2h_status_error => axis_c2h_status_error,
    axis_c2h_status_last => axis_c2h_status_last,
    axis_c2h_status_qid => axis_c2h_status_qid,
    axis_c2h_dmawr_cmp => axis_c2h_dmawr_cmp,
    soft_reset_n => soft_reset_n,
    phy_ready => phy_ready,
    qsts_out_op => qsts_out_op,
    qsts_out_data => qsts_out_data,
    qsts_out_port_id => qsts_out_port_id,
    qsts_out_qid => qsts_out_qid,
    qsts_out_vld => qsts_out_vld,
    qsts_out_rdy => qsts_out_rdy
  );
-- INST_TAG_END ------ End INSTANTIATION Template ---------

-- You must compile the wrapper file qdma_0.vhd when simulating
-- the core, qdma_0. When compiling the wrapper file, be sure to
-- reference the VHDL simulation library.



