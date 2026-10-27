# Modes hold for a full frame, with two mailbox stages and four event stages.
# Later stages and consumers keep ordinary setup/hold analysis.
# sof: sparse 409.6 -> 204.8 MHz event and stable mode mailbox.
set txmon_src [get_cells -hier -quiet -filter {NAME =~ */u_tx_air_frame_monitor/sof_toggle_reg}]
set txmon_dst [get_cells -hier -quiet -regexp {^.*/u_tx_air_frame_monitor/sof_sync_reg\[0\]$}]
set txmon_d [get_pins -quiet -of_objects $txmon_dst -filter {REF_PIN_NAME == D}]
set txmon_mode_src [get_cells -hier -quiet -filter {NAME =~ */u_tx_air_frame_monitor/sof_mode_hold_reg*}]
set txmon_mode_dst [get_pins -quiet -of_objects [get_cells -hier -quiet -filter {NAME =~ */u_tx_air_frame_monitor/sof_mode_sync1_reg*}] -filter {REF_PIN_NAME == D}]
set_max_delay -datapath_only 4.882 -from $txmon_src -to $txmon_d
set_max_delay -datapath_only 4.882 -from $txmon_mode_src -to $txmon_mode_dst
set_bus_skew 2.441 -from $txmon_mode_src -to $txmon_mode_dst
# done: sparse 409.6 -> 204.8 MHz event and stable mode mailbox.
set txmon_src [get_cells -hier -quiet -filter {NAME =~ */u_tx_air_frame_monitor/done_toggle_reg}]
set txmon_dst [get_cells -hier -quiet -regexp {^.*/u_tx_air_frame_monitor/done_sync_reg\[0\]$}]
set txmon_d [get_pins -quiet -of_objects $txmon_dst -filter {REF_PIN_NAME == D}]
set txmon_mode_src [get_cells -hier -quiet -filter {NAME =~ */u_tx_air_frame_monitor/done_mode_hold_reg*}]
set txmon_mode_dst [get_pins -quiet -of_objects [get_cells -hier -quiet -filter {NAME =~ */u_tx_air_frame_monitor/done_mode_sync1_reg*}] -filter {REF_PIN_NAME == D}]
set_max_delay -datapath_only 4.882 -from $txmon_src -to $txmon_d
set_max_delay -datapath_only 4.882 -from $txmon_mode_src -to $txmon_mode_dst
set_bus_skew 2.441 -from $txmon_mode_src -to $txmon_mode_dst
set txmon_run_dst [get_cells -hier -quiet -regexp {^.*/u_tx_air_frame_monitor/run_sync_reg\[0\]$}]
set txmon_run_d [get_pins -quiet -of_objects $txmon_run_dst -filter {REF_PIN_NAME == D}]
# Expand only this known source's physical replicas. An all_fanin collection
# formed before phys_opt otherwise leaves replicated release_out cells uncovered.
set txmon_run_src [get_cells -quiet -include_replicated_objects u_tx_run_reset/release_out_reg]
set_max_delay -datapath_only 4.882 -from $txmon_run_src -to $txmon_run_d
# Sticky diagnostic crosses fast -> slow through two ASYNC_REG stages. Only
# its first capture has a full slow-period data-path budget; stage one -> two
# and the ILA consumer retain ordinary local setup/hold analysis.
set txmon_error_src [get_cells -quiet -include_replicated_objects u_fmc_THz_test_top/u_tx_air_frame_monitor/stream_error_reg]
set txmon_error_dst [get_cells -hier -quiet -regexp {^u_fmc_THz_test_top/stream_error_sync_reg\[0\]$}]
set txmon_error_d [get_pins -quiet -of_objects $txmon_error_dst -filter {REF_PIN_NAME == D}]
set_max_delay -datapath_only 4.882 -from $txmon_error_src -to $txmon_error_d
