# Implementation-only endpoint exceptions for asynchronous reset synchronizers.
# NEVER cut their outputs: local recovery/removal and fanout remain timed.
set reset_sync_regs [get_cells -hier -quiet -filter {NAME =~ */release_dly_reg* || NAME =~ */release_out_reg* || NAME =~ *u_Rate_Convert/wr_reset_reg* || NAME =~ *u_Rate_Convert/rd_reset_reg*}]
set reset_sync_clr [get_pins -quiet -of_objects $reset_sync_regs -filter {REF_PIN_NAME == CLR}]
set_false_path -to $reset_sync_clr
# This diagnostic bit crosses recovered RX -> TX. Only stage one is excepted;
# the destination chain and ILA input remain timed. No payload bypass exists.
set error_meta [get_cells -hier -quiet -filter {NAME =~ */error_mac_meta_reg}]
set_false_path -to [get_pins -of_objects $error_meta -filter {REF_PIN_NAME == D}]
# Endpoint-count assertions belong in Tcl reporting, not the XDC parser.
