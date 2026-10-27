# PS PLCLK0 is independent of the RF sample reference. The three RF MMCM
# outputs and the derived LDPC clock remain related and normally timed.
set rx_ps_clocks [get_clocks -quiet -include_generated_clocks clk_pl_0]
set rx_rf_clock_nets [get_nets -quiet {data_clk data_clk1 data_clk2}]
set rx_rf_clocks [get_clocks -quiet -include_generated_clocks -of_objects $rx_rf_clock_nets]
set_clock_groups -asynchronous -group $rx_ps_clocks -group $rx_rf_clocks

# Only asynchronous assertion endpoints of local reset release synchronizers.
set rx_release_regs [get_cells -hier -quiet -filter {NAME =~ */release_dly_reg* || NAME =~ */release_out_reg*}]
set rx_release_clr [get_pins -quiet -of_objects $rx_release_regs -filter {REF_PIN_NAME == CLR}]
set_false_path -to $rx_release_clr






