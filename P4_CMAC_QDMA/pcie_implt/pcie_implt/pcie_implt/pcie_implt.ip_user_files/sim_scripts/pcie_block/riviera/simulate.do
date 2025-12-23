transcript off
onbreak {quit -force}
onerror {quit -force}
transcript on

asim +access +r +m+pcie_block  -L xpm -L lib_pkg_v1_0_3 -L fifo_generator_v13_2_9 -L lib_fifo_v1_0_18 -L blk_mem_gen_v8_4_7 -L lib_bmg_v1_0_16 -L axi_pcie_v2_9_10 -L xil_defaultlib -L lib_cdc_v1_0_2 -L proc_sys_reset_v5_0_14 -L axi_amm_bridge_v1_0_19 -L unisims_ver -L unimacro_ver -L secureip -O5 xil_defaultlib.pcie_block xil_defaultlib.glbl

do {pcie_block.udo}

run 1000ns

endsim

quit -force
