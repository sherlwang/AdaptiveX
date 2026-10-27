# Related RF clocks remain timed. Receiver-only FIFO constraints, no TX event FIFO.
# Endpoint assertions are in scripts/assert_feedback_cdc_endpoints.tcl.
# u_symbol_fifo: only Gray source -> first synchronizer, with later stages timed.
set txfb_wr_dst [get_pins -quiet -of_objects [get_cells -hier -quiet -filter {NAME =~ */u_symbol_fifo/wr_gray_r1_reg*}] -filter {REF_PIN_NAME == D}]
set txfb_wr_src [filter [all_fanin -flat -startpoints_only -only_cells -to $txfb_wr_dst] {NAME =~ */u_symbol_fifo/wr_gray_reg* || NAME =~ */u_symbol_fifo/wr_binary_reg*}]
set txfb_rd_dst [get_pins -quiet -of_objects [get_cells -hier -quiet -filter {NAME =~ */u_symbol_fifo/rd_gray_w1_reg*}] -filter {REF_PIN_NAME == D}]
set txfb_rd_src [filter [all_fanin -flat -startpoints_only -only_cells -to $txfb_rd_dst] {NAME =~ */u_symbol_fifo/rd_gray_reg* || NAME =~ */u_symbol_fifo/rd_binary_reg*}]
set_max_delay -datapath_only 2.441 -from $txfb_wr_src -to $txfb_wr_dst
set_bus_skew 2.441 -from $txfb_wr_src -to $txfb_wr_dst
set_max_delay -datapath_only 2.441 -from $txfb_rd_src -to $txfb_rd_dst
set_bus_skew 2.441 -from $txfb_rd_src -to $txfb_rd_dst
# u_timing_fifo: only Gray source -> first synchronizer, with later stages timed.
set txfb_wr_dst [get_pins -quiet -of_objects [get_cells -hier -quiet -filter {NAME =~ */u_timing_fifo/wr_gray_r1_reg*}] -filter {REF_PIN_NAME == D}]
set txfb_wr_src [filter [all_fanin -flat -startpoints_only -only_cells -to $txfb_wr_dst] {NAME =~ */u_timing_fifo/wr_gray_reg* || NAME =~ */u_timing_fifo/wr_binary_reg*}]
set txfb_rd_dst [get_pins -quiet -of_objects [get_cells -hier -quiet -filter {NAME =~ */u_timing_fifo/rd_gray_w1_reg*}] -filter {REF_PIN_NAME == D}]
set txfb_rd_src [filter [all_fanin -flat -startpoints_only -only_cells -to $txfb_rd_dst] {NAME =~ */u_timing_fifo/rd_gray_reg* || NAME =~ */u_timing_fifo/rd_binary_reg*}]
set_max_delay -datapath_only 2.441 -from $txfb_wr_src -to $txfb_wr_dst
set_bus_skew 2.441 -from $txfb_wr_src -to $txfb_wr_dst
set_max_delay -datapath_only 2.441 -from $txfb_rd_src -to $txfb_rd_dst
set_bus_skew 2.441 -from $txfb_rd_src -to $txfb_rd_dst
# u_packet_fifo: only Gray source -> first synchronizer, with later stages timed.
set txfb_wr_dst [get_pins -quiet -of_objects [get_cells -hier -quiet -filter {NAME =~ */u_packet_fifo/wr_gray_r1_reg*}] -filter {REF_PIN_NAME == D}]
set txfb_wr_src [filter [all_fanin -flat -startpoints_only -only_cells -to $txfb_wr_dst] {NAME =~ */u_packet_fifo/wr_gray_reg* || NAME =~ */u_packet_fifo/wr_binary_reg*}]
set txfb_rd_dst [get_pins -quiet -of_objects [get_cells -hier -quiet -filter {NAME =~ */u_packet_fifo/rd_gray_w1_reg*}] -filter {REF_PIN_NAME == D}]
set txfb_rd_src [filter [all_fanin -flat -startpoints_only -only_cells -to $txfb_rd_dst] {NAME =~ */u_packet_fifo/rd_gray_reg* || NAME =~ */u_packet_fifo/rd_binary_reg*}]
set_max_delay -datapath_only 2.441 -from $txfb_wr_src -to $txfb_wr_dst
set_bus_skew 2.441 -from $txfb_wr_src -to $txfb_wr_dst
set_max_delay -datapath_only 2.441 -from $txfb_rd_src -to $txfb_rd_dst
set_bus_skew 2.441 -from $txfb_rd_src -to $txfb_rd_dst
# u_point_fifo: only Gray source -> first synchronizer, with later stages timed.
set txfb_wr_dst [get_pins -quiet -of_objects [get_cells -hier -quiet -filter {NAME =~ */u_point_fifo/wr_gray_r1_reg*}] -filter {REF_PIN_NAME == D}]
set txfb_wr_src [filter [all_fanin -flat -startpoints_only -only_cells -to $txfb_wr_dst] {NAME =~ */u_point_fifo/wr_gray_reg* || NAME =~ */u_point_fifo/wr_binary_reg*}]
set txfb_rd_dst [get_pins -quiet -of_objects [get_cells -hier -quiet -filter {NAME =~ */u_point_fifo/rd_gray_w1_reg*}] -filter {REF_PIN_NAME == D}]
set txfb_rd_src [filter [all_fanin -flat -startpoints_only -only_cells -to $txfb_rd_dst] {NAME =~ */u_point_fifo/rd_gray_reg* || NAME =~ */u_point_fifo/rd_binary_reg*}]
set_max_delay -datapath_only 2.441 -from $txfb_wr_src -to $txfb_wr_dst
set_bus_skew 2.441 -from $txfb_wr_src -to $txfb_wr_dst
set_max_delay -datapath_only 2.441 -from $txfb_rd_src -to $txfb_rd_dst
set_bus_skew 2.441 -from $txfb_rd_src -to $txfb_rd_dst
# u_symbol_fifo: two destination periods for RAM write-clock -> transaction capture.
# The read address -> capture path keeps ordinary setup/hold analysis.
set txfb_ram [get_cells -hier -quiet -filter {IS_PRIMITIVE == 1 && NAME =~ */u_symbol_fifo/words_reg* && (REF_NAME =~ RAMD* || REF_NAME =~ RAMS*)}]
set txfb_ram_clk [get_pins -quiet -of_objects $txfb_ram -filter {REF_PIN_NAME == CLK || REF_PIN_NAME == WCLK}]
set txfb_capture [get_pins -quiet -of_objects [get_cells -hier -quiet -filter {NAME =~ */u_rx/sym_i_reg* || NAME =~ */u_rx/sym_q_reg* || NAME =~ */u_rx/phase_fast_reg*}] -filter {REF_PIN_NAME == D}]
set_max_delay -datapath_only 4.882 -from $txfb_ram_clk -to $txfb_capture
# u_timing_fifo: two destination periods for RAM write-clock -> transaction capture.
# The read address -> capture path keeps ordinary setup/hold analysis.
set txfb_ram [get_cells -hier -quiet -filter {IS_PRIMITIVE == 1 && NAME =~ */u_timing_fifo/words_reg* && (REF_NAME =~ RAMD* || REF_NAME =~ RAMS*)}]
set txfb_ram_clk [get_pins -quiet -of_objects $txfb_ram -filter {REF_PIN_NAME == CLK || REF_PIN_NAME == WCLK}]
set txfb_capture [get_pins -quiet -of_objects [get_cells -hier -quiet -filter {NAME =~ */u_rx/phase_select_reg*}] -filter {REF_PIN_NAME == D}]
set_max_delay -datapath_only 48.828 -from $txfb_ram_clk -to $txfb_capture
# u_packet_fifo: two destination periods for RAM write-clock -> transaction capture.
# The read address -> capture path keeps ordinary setup/hold analysis.
set txfb_ram [get_cells -hier -quiet -filter {IS_PRIMITIVE == 1 && NAME =~ */u_packet_fifo/words_reg* && (REF_NAME =~ RAMD* || REF_NAME =~ RAMS*)}]
set txfb_ram_clk [get_pins -quiet -of_objects $txfb_ram -filter {REF_PIN_NAME == CLK || REF_PIN_NAME == WCLK}]
set txfb_capture [get_pins -quiet -of_objects [get_cells -hier -quiet -filter {NAME =~ */u_rx/packet24_reg* || NAME =~ */u_rx/packet_cfo_reg* || NAME =~ */u_rx/packet_pn_reg* || NAME =~ */u_rx/packet_phase_reg*}] -filter {REF_PIN_NAME == D}]
set_max_delay -datapath_only 9.765 -from $txfb_ram_clk -to $txfb_capture
# u_point_fifo: two destination periods for RAM write-clock -> transaction capture.
# The read address -> capture path keeps ordinary setup/hold analysis.
set txfb_ram [get_cells -hier -quiet -filter {IS_PRIMITIVE == 1 && NAME =~ */u_point_fifo/words_reg* && (REF_NAME =~ RAMD* || REF_NAME =~ RAMS*)}]
set txfb_ram_clk [get_pins -quiet -of_objects $txfb_ram -filter {REF_PIN_NAME == CLK || REF_PIN_NAME == WCLK}]
set txfb_capture [get_pins -quiet -of_objects [get_cells -hier -quiet -filter {NAME =~ */u_rx/const_i_reg* || NAME =~ */u_rx/const_q_reg* || NAME =~ */u_rx/const_index_reg*}] -filter {REF_PIN_NAME == D}]
set_max_delay -datapath_only 9.765 -from $txfb_ram_clk -to $txfb_capture
# Asynchronous assertion only at local release chains. Their outputs, pointer
# stage one -> stage two, and downstream arithmetic keep setup/hold checks.
set txfb_release [get_cells -hier -quiet -filter {ASYNC_REG == TRUE && (NAME =~ */u_symbol_fifo/wr_release_reg* || NAME =~ */u_symbol_fifo/rd_release_reg* || NAME =~ */u_timing_fifo/wr_release_reg* || NAME =~ */u_timing_fifo/rd_release_reg* || NAME =~ */u_packet_fifo/wr_release_reg* || NAME =~ */u_packet_fifo/rd_release_reg* || NAME =~ */u_point_fifo/wr_release_reg* || NAME =~ */u_point_fifo/rd_release_reg*)}]
set_false_path -to [get_pins -quiet -of_objects $txfb_release -filter {REF_PIN_NAME == CLR || REF_PIN_NAME == PRE}]
