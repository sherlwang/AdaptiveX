# Read-only check of the six precisely excluded asynchronous PRE endpoints and
# the four real local synchronous D-chain paths. Does not open/change a design.
proc rx_verify_metadata_reset_final {task_directory} {
    file mkdir $task_directory
    set task_f [open [file join $task_directory metadata_fifo_reset_final.txt] w]
    puts $task_f "mode=READ_ONLY_EXISTING_DESIGN"
    source [file join [file dirname [info script]] verify_feedback_constraints.tcl]
    rx_report_api::export [file join $task_directory all_valid_exceptions.xdc]
    set task_presets [get_pins -quiet -of_objects [get_cells -quiet -hier -filter {NAME =~ *u_sample_cdc/reset_pipe_reg* || NAME =~ *u_sample_cdc/read_reset_pipe_reg*}] -filter {REF_PIN_NAME == PRE}]
    if {[llength $task_presets] != 6} {error "Final metadata PRE set differs from exactly six"}
    set task_valid [rx_report_api::filtered [file join $task_directory metadata_presets_valid_exceptions.rpt] -to $task_presets]
    rx_report_api::assert_false_targets $task_valid $task_presets
    set task_count 0
    set task_data_count 0
    set task_prefix {u_fmc_THz_test_top/u_ETH_TOP/u_constellation_eth_jiemian/u_sample_cdc}
    foreach {task_vector task_period} {reset_pipe_reg 4.8828125 read_reset_pipe_reg 6.4} {
        set task_previous {}
        for {set task_bit 0} {$task_bit < 3} {incr task_bit} {
            set task_name [format {%s/%s[%d]} $task_prefix $task_vector $task_bit]
            set task_cell [get_cells -quiet -hier -filter "NAME == $task_name"]
            if {[llength $task_cell] != 1 || [get_property REF_NAME $task_cell] ne "FDPE" || ![get_property ASYNC_REG $task_cell]} {
                error "Final metadata reset synchronizer missing/wrong: $task_name"
            }
            set task_pre [get_pins -quiet -of_objects $task_cell -filter {REF_PIN_NAME == PRE}]
            set task_c [get_pins -quiet -of_objects $task_cell -filter {REF_PIN_NAME == C}]
            set task_clock [get_clocks -quiet -of_objects $task_c]
            if {[llength $task_pre] != 1 || [llength $task_clock] != 1 || abs([get_property PERIOD $task_clock]-$task_period) > 0.01} {
                error "Final metadata reset PRE/clock mismatch: $task_name"
            }

            if {![regexp -nocase {set_false_path|false.?path} $task_valid] || [llength [get_timing_paths -quiet -to $task_pre -delay_type max -max_paths 1]]} {
                error "Final precise metadata PRE exception ineffective: $task_pre"
            }
            puts $task_f "preset=$task_pre;clock=$task_clock;ASYNC_REG=[get_property ASYNC_REG $task_cell];effective_false_path=1"
            incr task_count
            if {[llength $task_previous]} {
                set task_d [get_pins -quiet -of_objects $task_cell -filter {REF_PIN_NAME == D}]
                set task_paths [get_timing_paths -quiet -from $task_previous -to $task_d -delay_type max -max_paths 1]
                if {[llength $task_paths] != 1 || abs([get_property REQUIREMENT $task_paths]-$task_period) > 0.01} {
                    error "Metadata real local D chain is no longer timed: $task_name"
                }
                puts $task_f "timed_local_data=$task_previous->$task_d;requirement_ns=[get_property REQUIREMENT $task_paths];slack_ns=[get_property SLACK $task_paths]"
                incr task_data_count
            }
            set task_previous [get_pins -quiet -of_objects $task_cell -filter {REF_PIN_NAME == Q}]
        }
    }
    if {$task_count != 6 || $task_data_count != 4} {error "Final metadata reset scope mismatch"}
    puts $task_f "preset_count=$task_count\ntimed_local_data_count=$task_data_count\nresult=PASS_SIX_ASYNC_PRE_CUT_LOCAL_DATA_TIMED"
    close $task_f
    puts "RX_FINAL_METADATA_RESET_SCOPE_PASS"
}
