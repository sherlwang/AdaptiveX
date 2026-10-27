# Gray pointer CDC only. Keep both synchronizer stages (ASYNC_REG in RTL).
# Explicit path-delay and bus-skew bounds; do not false-path the whole FIFO.
# Related 204.8/409.6 clocks need no global asynchronous clock-group exception.
set rc_wr_src [get_cells -hier -quiet -filter {NAME =~ *u_Rate_Convert/wr_gray_reg*}]
set rc_wr_dst [get_cells -hier -quiet -filter {NAME =~ *u_Rate_Convert/wr_gray_r1_reg*}]
set rc_rd_src [get_cells -hier -quiet -filter {NAME =~ *u_Rate_Convert/rd_gray_reg*}]
set rc_rd_dst [get_cells -hier -quiet -filter {NAME =~ *u_Rate_Convert/rd_gray_w1_reg*}]
set_max_delay -datapath_only 2.44140625 -from $rc_wr_src -to $rc_wr_dst
set_bus_skew 2.44140625 -from $rc_wr_src -to $rc_wr_dst
set_max_delay -datapath_only 2.44140625 -from $rc_rd_src -to $rc_rd_dst
set_bus_skew 2.44140625 -from $rc_rd_src -to $rc_rd_dst
