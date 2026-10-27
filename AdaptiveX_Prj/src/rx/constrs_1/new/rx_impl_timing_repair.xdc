# Implementation only; register USED_IN_SYNTHESIS=false, USED_IN_IMPLEMENTATION=true,
# PROCESSING_ORDER=LATE. PRE explicitly reloads this idempotent declaration file.
# Complex uniqueness/primitive/clock/D-chain/readback guards live in PRE, because
# Vivado 2021.2 XDC does not support general Tcl control flow.
# Only asynchronous PRE pins below are timing exceptions. D/CE remain timed.
set rx_itr_reset_w0 [get_cells -quiet -hier -filter {NAME == u_fmc_THz_test_top/u_ETH_TOP/u_constellation_eth_jiemian/u_sample_cdc/reset_pipe_reg[0] && REF_NAME == FDPE}]
set rx_itr_reset_w1 [get_cells -quiet -hier -filter {NAME == u_fmc_THz_test_top/u_ETH_TOP/u_constellation_eth_jiemian/u_sample_cdc/reset_pipe_reg[1] && REF_NAME == FDPE}]
set rx_itr_reset_w2 [get_cells -quiet -hier -filter {NAME == u_fmc_THz_test_top/u_ETH_TOP/u_constellation_eth_jiemian/u_sample_cdc/reset_pipe_reg[2] && REF_NAME == FDPE}]
set rx_itr_reset_r0 [get_cells -quiet -hier -filter {NAME == u_fmc_THz_test_top/u_ETH_TOP/u_constellation_eth_jiemian/u_sample_cdc/read_reset_pipe_reg[0] && REF_NAME == FDPE}]
set rx_itr_reset_r1 [get_cells -quiet -hier -filter {NAME == u_fmc_THz_test_top/u_ETH_TOP/u_constellation_eth_jiemian/u_sample_cdc/read_reset_pipe_reg[1] && REF_NAME == FDPE}]
set rx_itr_reset_r2 [get_cells -quiet -hier -filter {NAME == u_fmc_THz_test_top/u_ETH_TOP/u_constellation_eth_jiemian/u_sample_cdc/read_reset_pipe_reg[2] && REF_NAME == FDPE}]
set_property ASYNC_REG TRUE $rx_itr_reset_w0
set_property ASYNC_REG TRUE $rx_itr_reset_w1
set_property ASYNC_REG TRUE $rx_itr_reset_w2
set_property ASYNC_REG TRUE $rx_itr_reset_r0
set_property ASYNC_REG TRUE $rx_itr_reset_r1
set_property ASYNC_REG TRUE $rx_itr_reset_r2
set_false_path -to [get_pins -quiet -of_objects $rx_itr_reset_w0 -filter {REF_PIN_NAME == PRE}]
set_false_path -to [get_pins -quiet -of_objects $rx_itr_reset_w1 -filter {REF_PIN_NAME == PRE}]
set_false_path -to [get_pins -quiet -of_objects $rx_itr_reset_w2 -filter {REF_PIN_NAME == PRE}]
set_false_path -to [get_pins -quiet -of_objects $rx_itr_reset_r0 -filter {REF_PIN_NAME == PRE}]
set_false_path -to [get_pins -quiet -of_objects $rx_itr_reset_r1 -filter {REF_PIN_NAME == PRE}]
set_false_path -to [get_pins -quiet -of_objects $rx_itr_reset_r2 -filter {REF_PIN_NAME == PRE}]

# Only the last release stage is eligible for physical replication. The ten
# earlier FDCEs and their Q nets are deliberately absent from these assignments.
set rx_itr_frontend [get_cells -quiet -hier -filter {NAME == u_fmc_THz_test_top/u_PHY_TOP_Rx/u_frontend_reset/release_q_reg[2] && REF_NAME == FDCE}]
set_property DONT_TOUCH FALSE $rx_itr_frontend
set_property ASYNC_REG FALSE $rx_itr_frontend
set_property DONT_TOUCH FALSE [get_nets -quiet -segments -of_objects [get_pins -quiet -of_objects $rx_itr_frontend -filter {REF_PIN_NAME == Q}]]
set rx_itr_cfo [get_cells -quiet -hier -filter {NAME == u_fmc_THz_test_top/u_PHY_TOP_Rx/u_cfo_reset/release_q_reg[2] && REF_NAME == FDCE}]
set_property DONT_TOUCH FALSE $rx_itr_cfo
set_property ASYNC_REG FALSE $rx_itr_cfo
set_property DONT_TOUCH FALSE [get_nets -quiet -segments -of_objects [get_pins -quiet -of_objects $rx_itr_cfo -filter {REF_PIN_NAME == Q}]]
set rx_itr_fde [get_cells -quiet -hier -filter {NAME == u_fmc_THz_test_top/u_PHY_TOP_Rx/u_fde_reset/release_q_reg[2] && REF_NAME == FDCE}]
set_property DONT_TOUCH FALSE $rx_itr_fde
set_property ASYNC_REG FALSE $rx_itr_fde
set_property DONT_TOUCH FALSE [get_nets -quiet -segments -of_objects [get_pins -quiet -of_objects $rx_itr_fde -filter {REF_PIN_NAME == Q}]]
set rx_itr_nlms [get_cells -quiet -hier -filter {NAME == u_fmc_THz_test_top/u_PHY_TOP_Rx/u_nlms_reset/release_q_reg[2] && REF_NAME == FDCE}]
set_property DONT_TOUCH FALSE $rx_itr_nlms
set_property ASYNC_REG FALSE $rx_itr_nlms
set_property DONT_TOUCH FALSE [get_nets -quiet -segments -of_objects [get_pins -quiet -of_objects $rx_itr_nlms -filter {REF_PIN_NAME == Q}]]
set rx_itr_demap [get_cells -quiet -hier -filter {NAME == u_fmc_THz_test_top/u_PHY_TOP_Rx/u_demap_reset/release_q_reg[2] && REF_NAME == FDCE}]
set_property DONT_TOUCH FALSE $rx_itr_demap
set_property ASYNC_REG FALSE $rx_itr_demap
set_property DONT_TOUCH FALSE [get_nets -quiet -segments -of_objects [get_pins -quiet -of_objects $rx_itr_demap -filter {REF_PIN_NAME == Q}]]
