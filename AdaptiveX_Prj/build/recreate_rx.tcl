# Rebuild the public fixed-phase Rx using delivered EDIF cores and readable integration RTL.
# Usage: vivado -mode batch -source recreate_rx.tcl -tclargs OUTPUT_DIR STAGE
# STAGE: create, synth, or bit. Default output is validation/rx, default stage is bit.
set package_root [file normalize [file join [file dirname [info script]] ..]]
set project_side rx
set input_source_dir [file join $package_root src $project_side]
set output_dir [file join $package_root validation $project_side]
if {$argc > 0} { set output_dir [file normalize [lindex $argv 0]] }
set build_stage bit
if {$argc > 1} { set build_stage [lindex $argv 1] }
if {$build_stage ni {create synth bit}} { error "Stage must be create, synth, or bit" }
file mkdir $output_dir
set existing_output [list]
foreach entry [glob -nocomplain -directory $output_dir * .*] {
    if {[file tail $entry] ni {. ..}} {lappend existing_output $entry}
}
if {[llength $existing_output] > 0} {error "Output directory must be empty: $output_dir"}
create_project rx $output_dir -part xczu47dr-ffve1156-2-i
set source_dir [file join $output_dir rx.srcs]
file mkdir $source_dir
foreach directory {sources_1 constrs_1} {
    file copy -force [file join $input_source_dir $directory] [file join $source_dir $directory]
}
if {[file isdirectory [file join $input_source_dir ai_deploy]]} {
    file copy -force [file join $input_source_dir ai_deploy] [file join $output_dir ai_deploy]
    foreach hook_file [glob [file join $output_dir ai_deploy blindrate_movzf_20261022 tools *.tcl]] {
        add_files -fileset utils_1 -norecurse $hook_file
    }
}
set_param general.maxThreads 4
# Keep the original BD module references enabled.
set_property source_mgmt_mode All [current_project]
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
set_property default_lib xil_defaultlib [current_project]
set_property ip_cache_permissions {disable} [current_project]
add_files -norecurse [file join $source_dir {sources_1/board/up_axi.v}]
add_files -norecurse [file join $source_dir {sources_1/ip/VIO_Rx_AI_Result/VIO_Rx_AI_Result.xci}]
add_files -norecurse [file join $source_dir {sources_1/ip/ILA_Rx_AI_Result/ILA_Rx_AI_Result.xci}]
add_files -norecurse [file join $source_dir {sources_1/ip/clk_ldpc_wiz/clk_ldpc_wiz.xci}]
add_files -norecurse [file join $source_dir {sources_1/bd/system/system.bd}]
add_files -norecurse [file join $source_dir {sources_1/eth/Constellation_Choose.v}]
add_files -norecurse [file join $source_dir {sources_1/eth/Constellation_Metadata_FIFO.v}]
add_files -norecurse [file join $source_dir {sources_1/rx/DDC_24ploy.v}]
add_files -norecurse [file join $source_dir {sources_1/eth/ETH_TOP.v}]
add_files -norecurse [file join $source_dir {sources_1/eth/MAC_TX_FlowControl.v}]
add_files -norecurse [file join $source_dir {sources_1/eth/MAC_UNTT.v}]
add_files -norecurse [file join $source_dir {sources_1/ldpc/PHY_LDPC_DEC.v}]
add_files -norecurse [file join $source_dir {sources_1/rx/PHY_TOP_Rx.v}]
add_files -norecurse [file join $source_dir {sources_1/rx/RRC_Rx_Engine.v}]
add_files -norecurse [file join $source_dir {sources_1/rx/RRC_Rx_Shared.v}]
add_files -norecurse [file join $source_dir {sources_1/rx/Rate_Convert_Rx12to24.v}]
add_files -norecurse [file join $source_dir {sources_1/board/Reset_Sync.v}]
add_files -norecurse [file join $source_dir {sources_1/rx/Rx_BER_Monitor.v}]
add_files -norecurse [file join $source_dir {sources_1/rx/Rx_Block_Window.v}]
add_files -norecurse [file join $source_dir {sources_1/rx/Rx_CFO_Estimate.v}]
add_files -norecurse [file join $source_dir {sources_1/rx/Rx_CFO_Rotate_Lane.v}]
add_files -norecurse [file join $source_dir {sources_1/rx/Rx_DDC_Buffer.v}]
add_files -norecurse [file join $source_dir {sources_1/rx_ai_switch/Rx_Frame_Gap.v}]
add_files -norecurse [file join $source_dir {sources_1/rx/Rx_Frequency_Correct.v}]
add_files -norecurse [file join $source_dir {sources_1/rx/Rx_Frontend_24.v}]
add_files -norecurse [file join $source_dir {sources_1/rx/Rx_Payload_Select.v}]
add_files -norecurse [file join $source_dir {sources_1/rx/Rx_Pilot_Mode.v}]
add_files -norecurse [file join $source_dir {sources_1/ldpc/Scramble_PN6144.v}]
add_files -norecurse [file join $source_dir {sources_1/board/ad_iobuf.v}]
add_files -norecurse [file join $source_dir {sources_1/eth/constellation_eth_jiemian.v}]
add_files -norecurse [file join $source_dir {sources_1/eth/ethernet_tx_rx.v}]
add_files -norecurse [file join $source_dir {sources_1/board/fmc_THz_test_top.v}]
add_files -norecurse [file join $source_dir {sources_1/eth/phy_Wto64.v}]
add_files -norecurse [file join $source_dir {sources_1/feedback_tx/rx_ada_feedback_tx.v}]
add_files -norecurse [file join $source_dir {sources_1/rx_ai_switch/rx_ai_decode_tags.v}]
add_files -norecurse [file join $source_dir {sources_1/rx_rate_ai/rx_blindrate_observer.v}]
add_files -norecurse [file join $source_dir {sources_1/feedback_tx/rx_fb_event_fifo.v}]
add_files -norecurse [file join $source_dir {sources_1/feedback_tx/rx_fb_framer.v}]
add_files -norecurse [file join $source_dir {sources_1/feedback_tx/rx_fb_reset_sync.v}]
add_files -norecurse [file join $source_dir {sources_1/feedback_tx/rx_fb_rrc6.v}]
add_files -norecurse [file join $source_dir {sources_1/feedback_tx/rx_fb_rrc6_phase.v}]
add_files -norecurse [file join $source_dir {sources_1/feedback_tx/rx_fb_tx.v}]
add_files -norecurse [file join $source_dir {sources_1/eth/ten_ge_tt_unpack.v}]
add_files -norecurse [file join $source_dir {sources_1/board/user_control.v}]
add_files -norecurse [file join $source_dir {sources_1/board/adaloop_top.v}]
add_files -norecurse [file join $source_dir {sources_1/ldpc/pn6144_lsb.mem}]
add_files -norecurse [file join $source_dir {sources_1/coe/rx_cfo_quarter_q15.mem}]
add_files -norecurse [file join $source_dir {sources_1/coe/rx_rrc_l12_q16.mem}]
add_files -norecurse [file join $source_dir {sources_1/coe/rx_rrc_l3_q16.mem}]
add_files -norecurse [file join $source_dir {sources_1/coe/rx_rrc_l6_q16.mem}]
add_files -norecurse [file join $source_dir {sources_1/feedback_tx/coefficients/fb_short_header_q13.mem}]
add_files -norecurse [file join $source_dir {sources_1/feedback_tx/coefficients/fb_tx_rrc6_q16.mem}]
add_files -norecurse [file join $source_dir {sources_1/ip/xxv_ethernet_2/xxv_ethernet_2.xci}]
add_files -norecurse [file join $source_dir {sources_1/ip/Vio_MAC_FlowControl/Vio_MAC_FlowControl.xci}]
add_files -norecurse [file join $source_dir {sources_1/ip/fifo_CONEdata_cdc/fifo_CONEdata_cdc.xci}]
add_files -norecurse [file join $source_dir {sources_1/ip/FIFO_Con32/FIFO_Con32.xci}]
add_files -norecurse [file join $source_dir {sources_1/ip/Sync_FIFO/Sync_FIFO.xci}]
add_files -norecurse [file join $source_dir {sources_1/ip/xge_tt_tx_user_fifo/xge_tt_tx_user_fifo.xci}]
add_files -norecurse [file join $source_dir {sources_1/ip/mult_16xconst/mult_16xconst.xci}]
add_files -norecurse [file join $source_dir {sources_1/ip/cordic_FreOffEst/cordic_FreOffEst.xci}]
add_files -norecurse [file join $source_dir {sources_1/ip/vio_rx_control/vio_rx_control.xci}]
add_files -norecurse [file join $source_dir {sources_1/ip/ILA_Rx_BlindRate_Summary/ILA_Rx_BlindRate_Summary.xci}]
add_files -fileset constrs_1 -norecurse [file join $source_dir {constrs_1/new/board.xdc}]
add_files -fileset constrs_1 -norecurse [file join $source_dir {constrs_1/new/timing.xdc}]
add_files -fileset constrs_1 -norecurse [file join $source_dir {constrs_1/new/rx_rate_convert_cdc.xdc}]
add_files -fileset constrs_1 -norecurse [file join $source_dir {constrs_1/new/ldpc_cdc.xdc}]
add_files -fileset constrs_1 -norecurse [file join $source_dir {constrs_1/new/ethernet_reset_cdc.xdc}]
add_files -fileset constrs_1 -norecurse [file join $source_dir {constrs_1/new/rx_feedback_cdc.xdc}]
add_files -fileset constrs_1 -norecurse [file join $source_dir {constrs_1/new/rx_impl_timing_repair.xdc}]
set_property SCOPED_TO_REF {PHY_LDPC_DEC} [get_files [file join $source_dir {constrs_1/new/ldpc_cdc.xdc}]]
set_property PROCESSING_ORDER {LATE} [get_files [file join $source_dir {constrs_1/new/ldpc_cdc.xdc}]]
set_property PROCESSING_ORDER {LATE} [get_files [file join $source_dir {constrs_1/new/ethernet_reset_cdc.xdc}]]
set_property PROCESSING_ORDER {LATE} [get_files [file join $source_dir {constrs_1/new/rx_impl_timing_repair.xdc}]]
set_property include_dirs [list [file join $source_dir sources_1 ldpc]] [get_filesets sources_1]
# Declare cores for synthesis; the post-hook binds EDIF into the saved checkpoint.
if {$argc < 3} {error {Use build/build.py to materialize the delivered netlists first.}}
set delivered_core_root [file normalize [lindex $argv 2]]
foreach core_dir [glob [file join $delivered_core_root rx *]] {
    set stub [file join $core_dir core_stub.v]
    set sim [file join $core_dir core_sim.v]
    if {![file isfile [file join $core_dir core.edf]] || ![file isfile $stub] || ![file isfile $sim]} {
        error "Incomplete delivered core: $core_dir"
    }
    add_files -norecurse $stub
    set_property USED_IN {synthesis} [get_files $stub]
    add_files -fileset sim_1 -norecurse $sim
    set_property USED_IN {simulation} [get_files $sim]
}
set binding_script [file join $output_dir bind_cores.tcl]
file copy -force [file join $package_root build bind_cores.tcl] $binding_script
add_files -fileset utils_1 -norecurse $binding_script
set_property top adaloop_top [get_filesets sources_1]
set_property strategy Flow_PerfOptimized_high [get_runs synth_1]
set_property strategy Performance_ExtraTimingOpt [get_runs impl_1]
set_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE ExtraTimingOpt [get_runs impl_1]
set_property STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE NoTimingRelaxation [get_runs impl_1]
set_property STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE AggressiveExplore [get_runs impl_1]
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED 1 [get_runs impl_1]
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.ARGS.DIRECTIVE AggressiveExplore [get_runs impl_1]
set_property STEPS.SYNTH_DESIGN.TCL.PRE [file join $output_dir ai_deploy blindrate_movzf_20261022 tools synth_message_limits.tcl] [get_runs synth_1]
set_property STEPS.PHYS_OPT_DESIGN.TCL.PRE [file join $output_dir ai_deploy blindrate_movzf_20261022 tools impl_physopt_pre.tcl] [get_runs impl_1]
set_property STEPS.PHYS_OPT_DESIGN.TCL.POST [file join $output_dir ai_deploy blindrate_movzf_20261022 tools impl_physopt_post.tcl] [get_runs impl_1]
set_property STEPS.SYNTH_DESIGN.ARGS.SHREG_MIN_SIZE 5 [get_runs synth_1]
foreach run [get_runs] {
    set properties [list_property $run]
    if {[lsearch -exact $properties AUTO_INCREMENTAL_CHECKPOINT] >= 0} {set_property AUTO_INCREMENTAL_CHECKPOINT 0 $run}
    if {[lsearch -exact $properties INCREMENTAL_CHECKPOINT] >= 0} {reset_property INCREMENTAL_CHECKPOINT $run}
}
update_compile_order -fileset sources_1
generate_target all [get_files -quiet *.bd]
set standalone_ip_files [list]
lappend standalone_ip_files [get_files [file join $source_dir {sources_1/ip/VIO_Rx_AI_Result/VIO_Rx_AI_Result.xci}]]
lappend standalone_ip_files [get_files [file join $source_dir {sources_1/ip/ILA_Rx_AI_Result/ILA_Rx_AI_Result.xci}]]
lappend standalone_ip_files [get_files [file join $source_dir {sources_1/ip/clk_ldpc_wiz/clk_ldpc_wiz.xci}]]
lappend standalone_ip_files [get_files [file join $source_dir {sources_1/ip/xxv_ethernet_2/xxv_ethernet_2.xci}]]
lappend standalone_ip_files [get_files [file join $source_dir {sources_1/ip/Vio_MAC_FlowControl/Vio_MAC_FlowControl.xci}]]
lappend standalone_ip_files [get_files [file join $source_dir {sources_1/ip/fifo_CONEdata_cdc/fifo_CONEdata_cdc.xci}]]
lappend standalone_ip_files [get_files [file join $source_dir {sources_1/ip/FIFO_Con32/FIFO_Con32.xci}]]
lappend standalone_ip_files [get_files [file join $source_dir {sources_1/ip/Sync_FIFO/Sync_FIFO.xci}]]
lappend standalone_ip_files [get_files [file join $source_dir {sources_1/ip/xge_tt_tx_user_fifo/xge_tt_tx_user_fifo.xci}]]
lappend standalone_ip_files [get_files [file join $source_dir {sources_1/ip/mult_16xconst/mult_16xconst.xci}]]
lappend standalone_ip_files [get_files [file join $source_dir {sources_1/ip/cordic_FreOffEst/cordic_FreOffEst.xci}]]
lappend standalone_ip_files [get_files [file join $source_dir {sources_1/ip/vio_rx_control/vio_rx_control.xci}]]
lappend standalone_ip_files [get_files [file join $source_dir {sources_1/ip/ILA_Rx_BlindRate_Summary/ILA_Rx_BlindRate_Summary.xci}]]
generate_target all $standalone_ip_files
foreach ip_file $standalone_ip_files {
    if {[get_property GENERATE_SYNTH_CHECKPOINT $ip_file]} {create_ip_run $ip_file}
}
foreach run [get_runs] {
    set properties [list_property $run]
    if {[lsearch -exact $properties AUTO_INCREMENTAL_CHECKPOINT] >= 0} {set_property AUTO_INCREMENTAL_CHECKPOINT 0 $run}
    if {[lsearch -exact $properties INCREMENTAL_CHECKPOINT] >= 0} {reset_property INCREMENTAL_CHECKPOINT $run}
}
update_compile_order -fileset sources_1
report_ip_status -file [file join $output_dir ip_status.rpt]
set fh [open [file join $output_dir input_files.txt] w]
foreach f [get_files -all] { puts $fh $f }
close $fh
set fh [open [file join $output_dir nonincremental_runs.txt] w]
foreach run [get_runs] {
    set properties [list_property $run]
    set auto not_applicable
    set reference not_applicable
    if {[lsearch -exact $properties AUTO_INCREMENTAL_CHECKPOINT] >= 0} {set auto [get_property AUTO_INCREMENTAL_CHECKPOINT $run]}
    if {[lsearch -exact $properties INCREMENTAL_CHECKPOINT] >= 0} {set reference [get_property INCREMENTAL_CHECKPOINT $run]}
    puts $fh "[get_property NAME $run] auto=$auto reference=$reference"
}
close $fh
# Strategy changes reset step hooks; register the binding hook last.
set_property STEPS.SYNTH_DESIGN.TCL.POST $binding_script [get_runs synth_1]
if {[get_property STEPS.SYNTH_DESIGN.TCL.POST [get_runs synth_1]] ne $binding_script} {
    error "The synthesis netlist-binding hook was not registered"
}
puts "SYNTH_BIND_HOOK $binding_script"
if {$build_stage eq "create"} { close_project; exit }
launch_runs synth_1 -jobs 2
wait_on_run synth_1
set synth_status [get_property STATUS [get_runs synth_1]]
if {![string match "*Complete*" $synth_status]} { error "Synthesis did not complete: $synth_status" }
open_run synth_1
set unresolved [get_cells -quiet -hier -filter {IS_BLACKBOX == 1 && NAME != dbg_hub}]
if {[llength $unresolved]} {error "Unresolved delivered/vendor cores: $unresolved"}
report_utilization -file [file join $output_dir synthesized_utilization.rpt]
report_utilization -hierarchical -hierarchical_depth 8 -file [file join $output_dir synthesized_hierarchy.rpt]
report_timing_summary -file [file join $output_dir synthesized_timing.rpt]
write_hw_platform -fixed -force -file [file join $output_dir rx_hardware.xsa]
close_design
if {$build_stage eq "bit"} {
    launch_runs impl_1 -to_step write_bitstream -jobs 2
    wait_on_run impl_1
    set impl_status [get_property STATUS [get_runs impl_1]]
    if {![string match "*Complete*" $impl_status]} { error "Implementation did not complete: $impl_status" }
    open_run impl_1
    set unresolved [get_cells -quiet -hier -filter {IS_BLACKBOX == 1}]
    if {[llength $unresolved]} {error "Unresolved implementation cells: $unresolved"}
    report_utilization -file [file join $output_dir routed_utilization.rpt]
    report_utilization -hierarchical -hierarchical_depth 8 -file [file join $output_dir routed_hierarchy.rpt]
    report_timing_summary -delay_type min_max -report_unconstrained -file [file join $output_dir routed_timing.rpt]
    report_drc -file [file join $output_dir routed_drc.rpt]
    report_clock_interaction -file [file join $output_dir routed_clock_interaction.rpt]
    report_bus_skew -file [file join $output_dir routed_bus_skew.rpt]
    write_debug_probes -force [file join $output_dir rx.ltx]
    write_hw_platform -fixed -include_bit -force -file [file join $output_dir rx_with_bit.xsa]
    close_design
}
set fh [open [file join $output_dir BUILD_COMPLETE.txt] w]
puts $fh "stage=$build_stage synthesis=$synth_status"
close $fh
close_project
