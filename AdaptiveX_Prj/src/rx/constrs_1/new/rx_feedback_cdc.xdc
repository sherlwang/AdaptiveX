# Ada event source 204.8 MHz -> feedback DAC 40.96 MHz, one 32-word FIFO.
# Keep RF clocks related; only Gray synchronizer inputs get CDC budgets.
# No receiver FIFO, receiver payload, or standalone-link objects are imported.
set rx_fb_wr_dst [get_pins -of_objects [get_cells -hier -filter {NAME =~ *u_event_fifo/wr_gray_r1_reg*}] -filter {REF_PIN_NAME == D}]
set rx_fb_wr_src [filter [all_fanin -flat -startpoints_only -only_cells -to $rx_fb_wr_dst] {NAME =~ *u_event_fifo/wr_gray_reg* || NAME =~ *u_event_fifo/wr_binary_reg*}]
set_max_delay -datapath_only 4.882 -from $rx_fb_wr_src -to $rx_fb_wr_dst
set_bus_skew 4.882 -from $rx_fb_wr_src -to $rx_fb_wr_dst

set rx_fb_rd_dst [get_pins -of_objects [get_cells -hier -filter {NAME =~ *u_event_fifo/rd_gray_w1_reg*}] -filter {REF_PIN_NAME == D}]
set rx_fb_rd_src [filter [all_fanin -flat -startpoints_only -only_cells -to $rx_fb_rd_dst] {NAME =~ *u_event_fifo/rd_gray_reg* || NAME =~ *u_event_fifo/rd_binary_reg*}]
set_max_delay -datapath_only 4.882 -from $rx_fb_rd_src -to $rx_fb_rd_dst
set_bus_skew 4.882 -from $rx_fb_rd_src -to $rx_fb_rd_dst

# FWFT data become eligible after synchronized pointers and registered empty.
# Budget RAM write clock -> CRC capture only; keep read-address timing intact.
set rx_fb_data_ram [get_cells -hier -filter {IS_PRIMITIVE == 1 && NAME =~ *u_event_fifo/messages_reg* && (REF_NAME =~ RAMD* || REF_NAME =~ RAMS*)}]
set rx_fb_data_clk [get_pins -of_objects $rx_fb_data_ram -filter {REF_PIN_NAME == CLK || REF_PIN_NAME == WCLK}]
set rx_fb_data_capture [get_pins -of_objects [get_cells -hier -filter {NAME =~ *u_framer/prepared_packet24_reg*}] -filter {REF_PIN_NAME == D}]
set_max_delay -datapath_only 48.828 -from $rx_fb_data_clk -to $rx_fb_data_capture

# Asynchronous assertion only; normal reset recovery/removal remains timed.
set rx_fb_fifo_release [get_cells -hier -filter {ASYNC_REG == TRUE && (NAME =~ *u_event_fifo/wr_release_reg* || NAME =~ *u_event_fifo/rd_release_reg*)}]
set rx_fb_fifo_release_clr [get_pins -of_objects $rx_fb_fifo_release -filter {REF_PIN_NAME == CLR || REF_PIN_NAME == PRE}]
set_false_path -to $rx_fb_fifo_release_clr
set rx_fb_reset_release [get_cells -hier -filter {NAME =~ *u_feedback_tx*/release_dly_reg* || NAME =~ *u_feedback_tx*/release_out_reg*}]
set rx_fb_reset_clr [get_pins -quiet -of_objects $rx_fb_reset_release -filter {REF_PIN_NAME == CLR}]
set_false_path -to $rx_fb_reset_clr
