transcript off
onbreak {quit -force}
onerror {quit -force}
transcript on

vlib work
vlib activehdl/xpm
vlib activehdl/lib_pkg_v1_0_3
vlib activehdl/fifo_generator_v13_2_9
vlib activehdl/lib_fifo_v1_0_18
vlib activehdl/blk_mem_gen_v8_4_7
vlib activehdl/lib_bmg_v1_0_16
vlib activehdl/axi_pcie_v2_9_10
vlib activehdl/xil_defaultlib
vlib activehdl/lib_cdc_v1_0_2
vlib activehdl/proc_sys_reset_v5_0_14
vlib activehdl/axi_amm_bridge_v1_0_19

vmap xpm activehdl/xpm
vmap lib_pkg_v1_0_3 activehdl/lib_pkg_v1_0_3
vmap fifo_generator_v13_2_9 activehdl/fifo_generator_v13_2_9
vmap lib_fifo_v1_0_18 activehdl/lib_fifo_v1_0_18
vmap blk_mem_gen_v8_4_7 activehdl/blk_mem_gen_v8_4_7
vmap lib_bmg_v1_0_16 activehdl/lib_bmg_v1_0_16
vmap axi_pcie_v2_9_10 activehdl/axi_pcie_v2_9_10
vmap xil_defaultlib activehdl/xil_defaultlib
vmap lib_cdc_v1_0_2 activehdl/lib_cdc_v1_0_2
vmap proc_sys_reset_v5_0_14 activehdl/proc_sys_reset_v5_0_14
vmap axi_amm_bridge_v1_0_19 activehdl/axi_amm_bridge_v1_0_19

vlog -work xpm  -sv2k12 -l xpm -l lib_pkg_v1_0_3 -l fifo_generator_v13_2_9 -l lib_fifo_v1_0_18 -l blk_mem_gen_v8_4_7 -l lib_bmg_v1_0_16 -l axi_pcie_v2_9_10 -l xil_defaultlib -l lib_cdc_v1_0_2 -l proc_sys_reset_v5_0_14 -l axi_amm_bridge_v1_0_19 \
"/tools/Xilinx/Vivado/2023.2/data/ip/xpm/xpm_cdc/hdl/xpm_cdc.sv" \
"/tools/Xilinx/Vivado/2023.2/data/ip/xpm/xpm_fifo/hdl/xpm_fifo.sv" \
"/tools/Xilinx/Vivado/2023.2/data/ip/xpm/xpm_memory/hdl/xpm_memory.sv" \

vcom -work xpm -  \
"/tools/Xilinx/Vivado/2023.2/data/ip/xpm/xpm_VCOMP.vhd" \

vcom -work lib_pkg_v1_0_3 -  \
"../../../../pcie_implt.gen/sources_1/bd/pcie_block/ipshared/56d9/hdl/lib_pkg_v1_0_rfs.vhd" \

vlog -work fifo_generator_v13_2_9  -v2k5 -l xpm -l lib_pkg_v1_0_3 -l fifo_generator_v13_2_9 -l lib_fifo_v1_0_18 -l blk_mem_gen_v8_4_7 -l lib_bmg_v1_0_16 -l axi_pcie_v2_9_10 -l xil_defaultlib -l lib_cdc_v1_0_2 -l proc_sys_reset_v5_0_14 -l axi_amm_bridge_v1_0_19 \
"../../../../pcie_implt.gen/sources_1/bd/pcie_block/ipshared/ac72/simulation/fifo_generator_vlog_beh.v" \

vcom -work fifo_generator_v13_2_9 -  \
"../../../../pcie_implt.gen/sources_1/bd/pcie_block/ipshared/ac72/hdl/fifo_generator_v13_2_rfs.vhd" \

vlog -work fifo_generator_v13_2_9  -v2k5 -l xpm -l lib_pkg_v1_0_3 -l fifo_generator_v13_2_9 -l lib_fifo_v1_0_18 -l blk_mem_gen_v8_4_7 -l lib_bmg_v1_0_16 -l axi_pcie_v2_9_10 -l xil_defaultlib -l lib_cdc_v1_0_2 -l proc_sys_reset_v5_0_14 -l axi_amm_bridge_v1_0_19 \
"../../../../pcie_implt.gen/sources_1/bd/pcie_block/ipshared/ac72/hdl/fifo_generator_v13_2_rfs.v" \

vcom -work lib_fifo_v1_0_18 -  \
"../../../../pcie_implt.gen/sources_1/bd/pcie_block/ipshared/1531/hdl/lib_fifo_v1_0_rfs.vhd" \

vlog -work blk_mem_gen_v8_4_7  -v2k5 -l xpm -l lib_pkg_v1_0_3 -l fifo_generator_v13_2_9 -l lib_fifo_v1_0_18 -l blk_mem_gen_v8_4_7 -l lib_bmg_v1_0_16 -l axi_pcie_v2_9_10 -l xil_defaultlib -l lib_cdc_v1_0_2 -l proc_sys_reset_v5_0_14 -l axi_amm_bridge_v1_0_19 \
"../../../../pcie_implt.gen/sources_1/bd/pcie_block/ipshared/3c0c/simulation/blk_mem_gen_v8_4.v" \

vcom -work lib_bmg_v1_0_16 -  \
"../../../../pcie_implt.gen/sources_1/bd/pcie_block/ipshared/5c9c/hdl/lib_bmg_v1_0_rfs.vhd" \

vlog -work axi_pcie_v2_9_10  -v2k5 -l xpm -l lib_pkg_v1_0_3 -l fifo_generator_v13_2_9 -l lib_fifo_v1_0_18 -l blk_mem_gen_v8_4_7 -l lib_bmg_v1_0_16 -l axi_pcie_v2_9_10 -l xil_defaultlib -l lib_cdc_v1_0_2 -l proc_sys_reset_v5_0_14 -l axi_amm_bridge_v1_0_19 \
"../../../../pcie_implt.gen/sources_1/bd/pcie_block/ipshared/8d40/hdl/axi_pcie_v2_9_rfs.v" \

vcom -work axi_pcie_v2_9_10 -  \
"../../../../pcie_implt.gen/sources_1/bd/pcie_block/ipshared/8d40/hdl/axi_pcie_v2_9_rfs.vhd" \

vlog -work xil_defaultlib  -v2k5 -l xpm -l lib_pkg_v1_0_3 -l fifo_generator_v13_2_9 -l lib_fifo_v1_0_18 -l blk_mem_gen_v8_4_7 -l lib_bmg_v1_0_16 -l axi_pcie_v2_9_10 -l xil_defaultlib -l lib_cdc_v1_0_2 -l proc_sys_reset_v5_0_14 -l axi_amm_bridge_v1_0_19 \
"../../../bd/pcie_block/ip/pcie_block_axi_pcie_0_0/hdl/axi_pcie_v2_9_10_pcie_7x_v2_0_2_pipe_clock.v" \
"../../../bd/pcie_block/ip/pcie_block_axi_pcie_0_0/hdl/axi_pcie_v2_9_10_pcie_7x_v2_0_2_qpll_wrapper.v" \
"../../../bd/pcie_block/ip/pcie_block_axi_pcie_0_0/hdl/axi_pcie_v2_9_10_pcie_7x_v2_0_2_gt_common.v" \
"../../../bd/pcie_block/ip/pcie_block_axi_pcie_0_0/hdl/axi_pcie_v2_9_10_pcie_7x_v2_0_2_qpll_drp.v" \
"../../../bd/pcie_block/ip/pcie_block_axi_pcie_0_0/hdl/axi_pcie_v2_9_10_pcie_7x_v2_0_2_gtp_cpllpd_ovrd.v" \
"../../../bd/pcie_block/ip/pcie_block_axi_pcie_0_0/hdl/pcie_block_axi_pcie_0_0_pcie_7x_v2_0_2.v" \
"../../../bd/pcie_block/ip/pcie_block_axi_pcie_0_0/sim/pcie_block_axi_pcie_0_0.v" \

vcom -work lib_cdc_v1_0_2 -  \
"../../../../pcie_implt.gen/sources_1/bd/pcie_block/ipshared/ef1e/hdl/lib_cdc_v1_0_rfs.vhd" \

vcom -work proc_sys_reset_v5_0_14 -  \
"../../../../pcie_implt.gen/sources_1/bd/pcie_block/ipshared/408c/hdl/proc_sys_reset_v5_0_vh_rfs.vhd" \

vcom -work xil_defaultlib -  \
"../../../bd/pcie_block/ip/pcie_block_proc_sys_reset_0_0/sim/pcie_block_proc_sys_reset_0_0.vhd" \
"../../../bd/pcie_block/sim/pcie_block.vhd" \

vlog -work axi_amm_bridge_v1_0_19  -v2k5 -l xpm -l lib_pkg_v1_0_3 -l fifo_generator_v13_2_9 -l lib_fifo_v1_0_18 -l blk_mem_gen_v8_4_7 -l lib_bmg_v1_0_16 -l axi_pcie_v2_9_10 -l xil_defaultlib -l lib_cdc_v1_0_2 -l proc_sys_reset_v5_0_14 -l axi_amm_bridge_v1_0_19 \
"../../../../pcie_implt.gen/sources_1/bd/pcie_block/ipshared/9f89/hdl/axi_amm_bridge_v1_0_rfs.v" \

vlog -work xil_defaultlib  -v2k5 -l xpm -l lib_pkg_v1_0_3 -l fifo_generator_v13_2_9 -l lib_fifo_v1_0_18 -l blk_mem_gen_v8_4_7 -l lib_bmg_v1_0_16 -l axi_pcie_v2_9_10 -l xil_defaultlib -l lib_cdc_v1_0_2 -l proc_sys_reset_v5_0_14 -l axi_amm_bridge_v1_0_19 \
"../../../bd/pcie_block/ip/pcie_block_axi_amm_bridge_0_0/sim/pcie_block_axi_amm_bridge_0_0.v" \

vlog -work xil_defaultlib \
"glbl.v"

