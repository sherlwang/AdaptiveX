# Only raw asynchronous reset pins of ETH domain synchronizers.
# Preserve the existing MAC-core reset synchronizer exception as well.
set eth_reset_regs [get_cells -hier -quiet -filter {ASYNC_REG == TRUE && (NAME =~ *u_ETH_TOP/u_phy_reset/release_dly_reg* || NAME =~ *u_ETH_TOP/u_mac_reset/release_dly_reg* || NAME =~ *u_ETH_TOP/u_cone_reset/release_dly_reg* || NAME =~ *u_fmc_THz_test_top/u_eth_core_reset/release_dly_reg*)}]
set eth_reset_pins [get_pins -quiet -of_objects $eth_reset_regs -filter {REF_PIN_NAME == CLR || REF_PIN_NAME == PRE}]
set_false_path -to $eth_reset_pins
