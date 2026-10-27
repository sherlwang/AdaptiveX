# Related 409.6/204.8 MHz clocks: constrain only Gray-pointer crossings.
# Each first synchronizer stage is ASYNC_REG in Rate_Convert_Rx12to24.
# The four collections below each match six registers in the synthesized Rx top.
set rx_wr_src [get_cells -hier -quiet -filter {NAME =~ *u_Rate_Convert_Rx12to24/wr_gray_reg*}]
set rx_wr_dst [get_cells -hier -quiet -filter {NAME =~ *u_Rate_Convert_Rx12to24/wr_gray_r1_reg*}]
set rx_rd_src [get_cells -hier -quiet -filter {NAME =~ *u_Rate_Convert_Rx12to24/rd_gray_reg*}]
set rx_rd_dst [get_cells -hier -quiet -filter {NAME =~ *u_Rate_Convert_Rx12to24/rd_gray_w1_reg*}]
set_max_delay -datapath_only 2.44140625 -from $rx_wr_src -to $rx_wr_dst
set_bus_skew 2.44140625 -from $rx_wr_src -to $rx_wr_dst
set_max_delay -datapath_only 2.44140625 -from $rx_rd_src -to $rx_rd_dst
set_bus_skew 2.44140625 -from $rx_rd_src -to $rx_rd_dst

# Async assertion at the PHY region synchronizers; all data paths remain timed.
set phy_reset_regs [get_cells -hier -quiet -filter {(NAME =~ *u_PHY_TOP_Rx/u_frontend_reset/release_q_reg* || NAME =~ *u_PHY_TOP_Rx/u_nlms_reset/release_q_reg* || NAME =~ *u_PHY_TOP_Rx/u_cfo_reset/release_q_reg* || NAME =~ *u_PHY_TOP_Rx/u_fde_reset/release_q_reg* || NAME =~ *u_PHY_TOP_Rx/u_demap_reset/release_q_reg*) && ASYNC_REG == TRUE}]
set phy_reset_pins [get_pins -quiet -of_objects $phy_reset_regs -filter {REF_PIN_NAME == CLR || REF_PIN_NAME == PRE}]
set_false_path -to $phy_reset_pins
