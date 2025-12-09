transcript off
onbreak {quit -force}
onerror {quit -force}
transcript on

vlib work
vlib activehdl/xilinx_vip
vlib activehdl/xpm
vlib activehdl/gtwizard_ultrascale_v1_7_17
vlib activehdl/xil_defaultlib
vlib activehdl/qdma_v5_0_6

vmap xilinx_vip activehdl/xilinx_vip
vmap xpm activehdl/xpm
vmap gtwizard_ultrascale_v1_7_17 activehdl/gtwizard_ultrascale_v1_7_17
vmap xil_defaultlib activehdl/xil_defaultlib
vmap qdma_v5_0_6 activehdl/qdma_v5_0_6

vlog -work xilinx_vip  -sv2k12 "+incdir+/tools/Xilinx/Vivado/2023.2/data/xilinx_vip/include" -l xilinx_vip -l xpm -l gtwizard_ultrascale_v1_7_17 -l xil_defaultlib -l qdma_v5_0_6 \
"/tools/Xilinx/Vivado/2023.2/data/xilinx_vip/hdl/axi4stream_vip_axi4streampc.sv" \
"/tools/Xilinx/Vivado/2023.2/data/xilinx_vip/hdl/axi_vip_axi4pc.sv" \
"/tools/Xilinx/Vivado/2023.2/data/xilinx_vip/hdl/xil_common_vip_pkg.sv" \
"/tools/Xilinx/Vivado/2023.2/data/xilinx_vip/hdl/axi4stream_vip_pkg.sv" \
"/tools/Xilinx/Vivado/2023.2/data/xilinx_vip/hdl/axi_vip_pkg.sv" \
"/tools/Xilinx/Vivado/2023.2/data/xilinx_vip/hdl/axi4stream_vip_if.sv" \
"/tools/Xilinx/Vivado/2023.2/data/xilinx_vip/hdl/axi_vip_if.sv" \
"/tools/Xilinx/Vivado/2023.2/data/xilinx_vip/hdl/clk_vip_if.sv" \
"/tools/Xilinx/Vivado/2023.2/data/xilinx_vip/hdl/rst_vip_if.sv" \

vlog -work xpm  -sv2k12 "+incdir+../../../../p4_cmac_qdma_implt.gen/sources_1/ip/qdma_0/ip_0/source" "+incdir+../../../ipstatic/hdl/verilog" "+incdir+/tools/Xilinx/Vivado/2023.2/data/xilinx_vip/include" -l xilinx_vip -l xpm -l gtwizard_ultrascale_v1_7_17 -l xil_defaultlib -l qdma_v5_0_6 \
"/tools/Xilinx/Vivado/2023.2/data/ip/xpm/xpm_cdc/hdl/xpm_cdc.sv" \
"/tools/Xilinx/Vivado/2023.2/data/ip/xpm/xpm_fifo/hdl/xpm_fifo.sv" \
"/tools/Xilinx/Vivado/2023.2/data/ip/xpm/xpm_memory/hdl/xpm_memory.sv" \

vcom -work xpm -  \
"/tools/Xilinx/Vivado/2023.2/data/ip/xpm/xpm_VCOMP.vhd" \

vlog -work gtwizard_ultrascale_v1_7_17  -v2k5 "+incdir+../../../../p4_cmac_qdma_implt.gen/sources_1/ip/qdma_0/ip_0/source" "+incdir+../../../ipstatic/hdl/verilog" "+incdir+/tools/Xilinx/Vivado/2023.2/data/xilinx_vip/include" -l xilinx_vip -l xpm -l gtwizard_ultrascale_v1_7_17 -l xil_defaultlib -l qdma_v5_0_6 \
"../../../ipstatic/hdl/gtwizard_ultrascale_v1_7_bit_sync.v" \
"../../../ipstatic/hdl/gtwizard_ultrascale_v1_7_gte4_drp_arb.v" \
"../../../ipstatic/hdl/gtwizard_ultrascale_v1_7_gthe4_delay_powergood.v" \
"../../../ipstatic/hdl/gtwizard_ultrascale_v1_7_gtye4_delay_powergood.v" \
"../../../ipstatic/hdl/gtwizard_ultrascale_v1_7_gthe3_cpll_cal.v" \
"../../../ipstatic/hdl/gtwizard_ultrascale_v1_7_gthe3_cal_freqcnt.v" \
"../../../ipstatic/hdl/gtwizard_ultrascale_v1_7_gthe4_cpll_cal.v" \
"../../../ipstatic/hdl/gtwizard_ultrascale_v1_7_gthe4_cpll_cal_rx.v" \
"../../../ipstatic/hdl/gtwizard_ultrascale_v1_7_gthe4_cpll_cal_tx.v" \
"../../../ipstatic/hdl/gtwizard_ultrascale_v1_7_gthe4_cal_freqcnt.v" \
"../../../ipstatic/hdl/gtwizard_ultrascale_v1_7_gtye4_cpll_cal.v" \
"../../../ipstatic/hdl/gtwizard_ultrascale_v1_7_gtye4_cpll_cal_rx.v" \
"../../../ipstatic/hdl/gtwizard_ultrascale_v1_7_gtye4_cpll_cal_tx.v" \
"../../../ipstatic/hdl/gtwizard_ultrascale_v1_7_gtye4_cal_freqcnt.v" \
"../../../ipstatic/hdl/gtwizard_ultrascale_v1_7_gtwiz_buffbypass_rx.v" \
"../../../ipstatic/hdl/gtwizard_ultrascale_v1_7_gtwiz_buffbypass_tx.v" \
"../../../ipstatic/hdl/gtwizard_ultrascale_v1_7_gtwiz_reset.v" \
"../../../ipstatic/hdl/gtwizard_ultrascale_v1_7_gtwiz_userclk_rx.v" \
"../../../ipstatic/hdl/gtwizard_ultrascale_v1_7_gtwiz_userclk_tx.v" \
"../../../ipstatic/hdl/gtwizard_ultrascale_v1_7_gtwiz_userdata_rx.v" \
"../../../ipstatic/hdl/gtwizard_ultrascale_v1_7_gtwiz_userdata_tx.v" \
"../../../ipstatic/hdl/gtwizard_ultrascale_v1_7_reset_sync.v" \
"../../../ipstatic/hdl/gtwizard_ultrascale_v1_7_reset_inv_sync.v" \

vlog -work xil_defaultlib  -v2k5 "+incdir+../../../../p4_cmac_qdma_implt.gen/sources_1/ip/qdma_0/ip_0/source" "+incdir+../../../ipstatic/hdl/verilog" "+incdir+/tools/Xilinx/Vivado/2023.2/data/xilinx_vip/include" -l xilinx_vip -l xpm -l gtwizard_ultrascale_v1_7_17 -l xil_defaultlib -l qdma_v5_0_6 \
"../../../../p4_cmac_qdma_implt.gen/sources_1/ip/qdma_0/ip_0/ip_0/sim/gtwizard_ultrascale_v1_7_gtye4_channel.v" \
"../../../../p4_cmac_qdma_implt.gen/sources_1/ip/qdma_0/ip_0/ip_0/sim/qdma_0_pcie4_ip_gt_gtye4_channel_wrapper.v" \
"../../../../p4_cmac_qdma_implt.gen/sources_1/ip/qdma_0/ip_0/ip_0/sim/gtwizard_ultrascale_v1_7_gtye4_common.v" \
"../../../../p4_cmac_qdma_implt.gen/sources_1/ip/qdma_0/ip_0/ip_0/sim/qdma_0_pcie4_ip_gt_gtye4_common_wrapper.v" \
"../../../../p4_cmac_qdma_implt.gen/sources_1/ip/qdma_0/ip_0/ip_0/sim/qdma_0_pcie4_ip_gt_gtwizard_gtye4.v" \
"../../../../p4_cmac_qdma_implt.gen/sources_1/ip/qdma_0/ip_0/ip_0/sim/qdma_0_pcie4_ip_gt_gtwizard_top.v" \
"../../../../p4_cmac_qdma_implt.gen/sources_1/ip/qdma_0/ip_0/ip_0/sim/qdma_0_pcie4_ip_gt.v" \
"../../../../p4_cmac_qdma_implt.gen/sources_1/ip/qdma_0/ip_0/source/qdma_0_pcie4_ip_gtwizard_top.v" \
"../../../../p4_cmac_qdma_implt.gen/sources_1/ip/qdma_0/ip_0/source/qdma_0_pcie4_ip_phy_ff_chain.v" \
"../../../../p4_cmac_qdma_implt.gen/sources_1/ip/qdma_0/ip_0/source/qdma_0_pcie4_ip_phy_pipeline.v" \
"../../../../p4_cmac_qdma_implt.gen/sources_1/ip/qdma_0/ip_0/source/qdma_0_pcie4_ip_512b_async_fifo.v" \
"../../../../p4_cmac_qdma_implt.gen/sources_1/ip/qdma_0/ip_0/source/qdma_0_pcie4_ip_512b_cc_intfc.v" \
"../../../../p4_cmac_qdma_implt.gen/sources_1/ip/qdma_0/ip_0/source/qdma_0_pcie4_ip_512b_cc_output_mux.v" \
"../../../../p4_cmac_qdma_implt.gen/sources_1/ip/qdma_0/ip_0/source/qdma_0_pcie4_ip_512b_cq_intfc.v" \
"../../../../p4_cmac_qdma_implt.gen/sources_1/ip/qdma_0/ip_0/source/qdma_0_pcie4_ip_512b_cq_output_mux.v" \
"../../../../p4_cmac_qdma_implt.gen/sources_1/ip/qdma_0/ip_0/source/qdma_0_pcie4_ip_512b_intfc_int.v" \
"../../../../p4_cmac_qdma_implt.gen/sources_1/ip/qdma_0/ip_0/source/qdma_0_pcie4_ip_512b_intfc.v" \
"../../../../p4_cmac_qdma_implt.gen/sources_1/ip/qdma_0/ip_0/source/qdma_0_pcie4_ip_512b_rc_intfc.v" \
"../../../../p4_cmac_qdma_implt.gen/sources_1/ip/qdma_0/ip_0/source/qdma_0_pcie4_ip_512b_rc_output_mux.v" \
"../../../../p4_cmac_qdma_implt.gen/sources_1/ip/qdma_0/ip_0/source/qdma_0_pcie4_ip_512b_rq_intfc.v" \
"../../../../p4_cmac_qdma_implt.gen/sources_1/ip/qdma_0/ip_0/source/qdma_0_pcie4_ip_512b_rq_output_mux.v" \
"../../../../p4_cmac_qdma_implt.gen/sources_1/ip/qdma_0/ip_0/source/qdma_0_pcie4_ip_512b_sync_fifo.v" \
"../../../../p4_cmac_qdma_implt.gen/sources_1/ip/qdma_0/ip_0/source/qdma_0_pcie4_ip_bram_16k_int.v" \
"../../../../p4_cmac_qdma_implt.gen/sources_1/ip/qdma_0/ip_0/source/qdma_0_pcie4_ip_bram_16k.v" \
"../../../../p4_cmac_qdma_implt.gen/sources_1/ip/qdma_0/ip_0/source/qdma_0_pcie4_ip_bram_32k.v" \
"../../../../p4_cmac_qdma_implt.gen/sources_1/ip/qdma_0/ip_0/source/qdma_0_pcie4_ip_bram_4k_int.v" \
"../../../../p4_cmac_qdma_implt.gen/sources_1/ip/qdma_0/ip_0/source/qdma_0_pcie4_ip_bram_msix.v" \
"../../../../p4_cmac_qdma_implt.gen/sources_1/ip/qdma_0/ip_0/source/qdma_0_pcie4_ip_bram_rep_int.v" \
"../../../../p4_cmac_qdma_implt.gen/sources_1/ip/qdma_0/ip_0/source/qdma_0_pcie4_ip_bram_rep.v" \
"../../../../p4_cmac_qdma_implt.gen/sources_1/ip/qdma_0/ip_0/source/qdma_0_pcie4_ip_bram_tph.v" \
"../../../../p4_cmac_qdma_implt.gen/sources_1/ip/qdma_0/ip_0/source/qdma_0_pcie4_ip_bram.v" \
"../../../../p4_cmac_qdma_implt.gen/sources_1/ip/qdma_0/ip_0/source/qdma_0_pcie4_ip_gt_gt_channel.v" \
"../../../../p4_cmac_qdma_implt.gen/sources_1/ip/qdma_0/ip_0/source/qdma_0_pcie4_ip_gt_gt_common.v" \
"../../../../p4_cmac_qdma_implt.gen/sources_1/ip/qdma_0/ip_0/source/qdma_0_pcie4_ip_gt_phy_clk.v" \
"../../../../p4_cmac_qdma_implt.gen/sources_1/ip/qdma_0/ip_0/source/qdma_0_pcie4_ip_gt_phy_rst.v" \
"../../../../p4_cmac_qdma_implt.gen/sources_1/ip/qdma_0/ip_0/source/qdma_0_pcie4_ip_gt_phy_rxeq.v" \
"../../../../p4_cmac_qdma_implt.gen/sources_1/ip/qdma_0/ip_0/source/qdma_0_pcie4_ip_gt_phy_txeq.v" \
"../../../../p4_cmac_qdma_implt.gen/sources_1/ip/qdma_0/ip_0/source/qdma_0_pcie4_ip_sync_cell.v" \
"../../../../p4_cmac_qdma_implt.gen/sources_1/ip/qdma_0/ip_0/source/qdma_0_pcie4_ip_sync.v" \
"../../../../p4_cmac_qdma_implt.gen/sources_1/ip/qdma_0/ip_0/source/qdma_0_pcie4_ip_gt_cdr_ctrl_on_eidle.v" \
"../../../../p4_cmac_qdma_implt.gen/sources_1/ip/qdma_0/ip_0/source/qdma_0_pcie4_ip_gt_receiver_detect_rxterm.v" \
"../../../../p4_cmac_qdma_implt.gen/sources_1/ip/qdma_0/ip_0/source/qdma_0_pcie4_ip_gt_phy_wrapper.v" \
"../../../../p4_cmac_qdma_implt.gen/sources_1/ip/qdma_0/ip_0/source/qdma_0_pcie4_ip_init_ctrl.v" \
"../../../../p4_cmac_qdma_implt.gen/sources_1/ip/qdma_0/ip_0/source/qdma_0_pcie4_ip_pl_eq.v" \
"../../../../p4_cmac_qdma_implt.gen/sources_1/ip/qdma_0/ip_0/source/qdma_0_pcie4_ip_vf_decode.v" \
"../../../../p4_cmac_qdma_implt.gen/sources_1/ip/qdma_0/ip_0/source/qdma_0_pcie4_ip_pipe.v" \
"../../../../p4_cmac_qdma_implt.gen/sources_1/ip/qdma_0/ip_0/source/qdma_0_pcie4_ip_phy_top.v" \
"../../../../p4_cmac_qdma_implt.gen/sources_1/ip/qdma_0/ip_0/source/qdma_0_pcie4_ip_seqnum_fifo.v" \
"../../../../p4_cmac_qdma_implt.gen/sources_1/ip/qdma_0/ip_0/source/qdma_0_pcie4_ip_sys_clk_gen_ps.v" \
"../../../../p4_cmac_qdma_implt.gen/sources_1/ip/qdma_0/ip_0/source/qdma_0_pcie4_ip_pcie4_uscale_core_top.v" \
"../../../../p4_cmac_qdma_implt.gen/sources_1/ip/qdma_0/ip_0/sim/qdma_0_pcie4_ip.v" \

vlog -work qdma_v5_0_6  -sv2k12 "+incdir+../../../../p4_cmac_qdma_implt.gen/sources_1/ip/qdma_0/ip_0/source" "+incdir+../../../ipstatic/hdl/verilog" "+incdir+/tools/Xilinx/Vivado/2023.2/data/xilinx_vip/include" -l xilinx_vip -l xpm -l gtwizard_ultrascale_v1_7_17 -l xil_defaultlib -l qdma_v5_0_6 \
"../../../ipstatic/hdl/qdma_v5_0_vl_rfs.sv" \

vlog -work xil_defaultlib  -sv2k12 "+incdir+../../../../p4_cmac_qdma_implt.gen/sources_1/ip/qdma_0/ip_0/source" "+incdir+../../../ipstatic/hdl/verilog" "+incdir+/tools/Xilinx/Vivado/2023.2/data/xilinx_vip/include" -l xilinx_vip -l xpm -l gtwizard_ultrascale_v1_7_17 -l xil_defaultlib -l qdma_v5_0_6 \
"../../../../p4_cmac_qdma_implt.gen/sources_1/ip/qdma_0/qdma_0hdl/verilog/qdma_0_core_top.sv" \
"../../../../p4_cmac_qdma_implt.gen/sources_1/ip/qdma_0/sim/qdma_0.sv" \

vlog -work xil_defaultlib \
"glbl.v"

