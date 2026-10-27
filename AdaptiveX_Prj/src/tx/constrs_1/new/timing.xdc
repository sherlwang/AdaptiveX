# PS clock is asynchronous to the RF MMCM; its three related outputs stay timed.
# Do not separate 409.6 / 204.8 / 40.96 MHz with asynchronous clock groups.
set tx_ps_clocks [get_clocks -quiet -include_generated_clocks clk_pl_0]
set tx_rf_nets [get_nets -quiet {data_clk data_clk1 data_clk2}]
set tx_rf_clocks [get_clocks -quiet -include_generated_clocks -of_objects $tx_rf_nets]
set_clock_groups -asynchronous -group $tx_ps_clocks -group $tx_rf_clocks
