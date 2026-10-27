# Rebuild the public Tx using delivered EDIF cores and readable integration RTL.
# Usage: vivado -mode batch -source recreate_tx.tcl -tclargs OUTPUT_DIR STAGE
# STAGE: create, synth, or bit. Default output is validation/tx, default stage is bit.
set package_root [file normalize [file join [file dirname [info script]] ..]]
set project_side tx
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
create_project tx $output_dir -part xczu47dr-ffve1156-2-i
set source_dir [file join $output_dir tx.srcs]
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
add_files -norecurse [file join $source_dir {sources_1/bd/system/system.bd}]
add_files -norecurse [file join $source_dir {sources_1/tx/CP_Insert.v}]
add_files -norecurse [file join $source_dir {sources_1/dsp/nco/CosLookUpTableGen.v}]
add_files -norecurse [file join $source_dir {sources_1/dsp/nco/DitherGen.v}]
add_files -norecurse [file join $source_dir {sources_1/eth/ETH_TOP.v}]
add_files -norecurse [file join $source_dir {sources_1/tx/Gain.v}]
add_files -norecurse [file join $source_dir {sources_1/tx/Head_Insert.v}]
add_files -norecurse [file join $source_dir {sources_1/eth/MAC_BufferFlowControl.v}]
add_files -norecurse [file join $source_dir {sources_1/eth/MAC_FIFO.v}]
add_files -norecurse [file join $source_dir {sources_1/eth/MAC_PHY_interface.v}]
add_files -norecurse [file join $source_dir {sources_1/eth/MAC_TT.v}]
add_files -norecurse [file join $source_dir {sources_1/eth/MAC_TX_FlowControl.v}]
add_files -norecurse [file join $source_dir {sources_1/tx/Mod_Map.v}]
add_files -norecurse [file join $source_dir {sources_1/dsp/nco/NCO_HDL_Optimized_12bit.v}]
add_files -norecurse [file join $source_dir {sources_1/ldpc/PHY_LDPC.v}]
add_files -norecurse [file join $source_dir {sources_1/board/PHY_Mode_Control.v}]
add_files -norecurse [file join $source_dir {sources_1/tx/PHY_SYMBOL.v}]
add_files -norecurse [file join $source_dir {sources_1/tx/PHY_TOP.v}]
add_files -norecurse [file join $source_dir {sources_1/dsp/nco/PhaseMul.v}]
add_files -norecurse [file join $source_dir {sources_1/tx/Pilot_Insert.v}]
add_files -norecurse [file join $source_dir {sources_1/tx/Rate_Convert.v}]
add_files -norecurse [file join $source_dir {sources_1/board/Reset_Sync.v}]
add_files -norecurse [file join $source_dir {sources_1/ldpc/Scramble_PN6144.v}]
add_files -norecurse [file join $source_dir {sources_1/dsp/nco/SinLookUpTableGen.v}]
add_files -norecurse [file join $source_dir {sources_1/dsp/nco/WaveformGen.v}]
add_files -norecurse [file join $source_dir {sources_1/board/ad_iobuf.v}]
add_files -norecurse [file join $source_dir {sources_1/eth/ethernet_tx_rx.v}]
add_files -norecurse [file join $source_dir {sources_1/board/fmc_THz_test_top.v}]
add_files -norecurse [file join $source_dir {sources_1/ldpc/phy_64toW.v}]
add_files -norecurse [file join $source_dir {sources_1/eth/phy_in_request.v}]
add_files -norecurse [file join $source_dir {sources_1/feedback_rx/reset_sync.v}]
add_files -norecurse [file join $source_dir {sources_1/eth/ten_ge_tt_pack.v}]
add_files -norecurse [file join $source_dir {sources_1/control/tx_air_frame_monitor.v}]
add_files -norecurse [file join $source_dir {sources_1/feedback_rx/tx_fb_async_fifo.v}]
add_files -norecurse [file join $source_dir {sources_1/feedback_rx/tx_fb_decoder.v}]
add_files -norecurse [file join $source_dir {sources_1/feedback_rx/tx_fb_fde64.v}]
add_files -norecurse [file join $source_dir {sources_1/feedback_rx/tx_fb_frontend.v}]
add_files -norecurse [file join $source_dir {sources_1/feedback_rx/tx_fb_metric41.v}]
add_files -norecurse [file join $source_dir {sources_1/feedback_rx/tx_fb_receiver.v}]
add_files -norecurse [file join $source_dir {sources_1/feedback_rx/tx_fb_rrc12.v}]
add_files -norecurse [file join $source_dir {sources_1/control/tx_feedback_controller.v}]
add_files -norecurse [file join $source_dir {sources_1/board/tx_feedback_receive.v}]
add_files -norecurse [file join $source_dir {sources_1/dsp/up/up_12ploy.v}]
add_files -norecurse [file join $source_dir {sources_1/board/user_control.v}]
add_files -norecurse [file join $source_dir {sources_1/board/adaloop_top.v}]
add_files -norecurse [file join $source_dir {sources_1/coe/enc_edges.mem}]
add_files -norecurse [file join $source_dir {sources_1/coe/head_all.mem}]
add_files -norecurse [file join $source_dir {sources_1/coe/pn6144_lsb.mem}]
add_files -norecurse [file join $source_dir {sources_1/feedback_rx/coefficients/fb_fde_recip_q18.mem}]
add_files -norecurse [file join $source_dir {sources_1/feedback_rx/coefficients/fb_fde_train_spectrum_q13.mem}]
add_files -norecurse [file join $source_dir {sources_1/feedback_rx/coefficients/fb_rx_header_q13.mem}]
add_files -norecurse [file join $source_dir {sources_1/feedback_rx/coefficients/fb_rx_nco_cos_q14.mem}]
add_files -norecurse [file join $source_dir {sources_1/feedback_rx/coefficients/fb_rx_nco_sin_q14.mem}]
add_files -norecurse [file join $source_dir {sources_1/feedback_rx/coefficients/fb_rx_pn12_q13.mem}]
add_files -norecurse [file join $source_dir {sources_1/feedback_rx/coefficients/fb_rx_rrc12_q16.mem}]
add_files -norecurse [file join $source_dir {sources_1/ip/xxv_ethernet_2/xxv_ethernet_2.xci}]
add_files -norecurse [file join $source_dir {sources_1/ip/Vio_MAC_FlowControl/Vio_MAC_FlowControl.xci}]
add_files -norecurse [file join $source_dir {sources_1/ip/xge_tt_rx_mac_fifo/xge_tt_rx_mac_fifo.xci}]
add_files -norecurse [file join $source_dir {sources_1/ip/FIFO_IndepClk_MACaddr/FIFO_IndepClk_MACaddr.xci}]
add_files -norecurse [file join $source_dir {sources_1/ip/FIFO_IndepClk_FlowC/FIFO_IndepClk_FlowC.xci}]
add_files -norecurse [file join $source_dir {sources_1/ip/MAC_Buffer/MAC_Buffer.xci}]
add_files -norecurse [file join $source_dir {sources_1/ip/vio_tx_control/vio_tx_control.xci}]
add_files -norecurse [file join $source_dir {sources_1/ip/Mult_Gain/Mult_Gain.xci}]
add_files -norecurse [file join $source_dir {sources_1/ip/xge_tt_rx_user_fifo/xge_tt_rx_user_fifo.xci}]
add_files -norecurse [file join $source_dir {sources_1/ip/ILA_MAC_STATE/ILA_MAC_STATE.xci}]
add_files -norecurse [file join $source_dir {sources_1/ip/vio_gain/vio_gain.xci}]
add_files -norecurse [file join $source_dir {sources_1/ip/tx_fb_fft64_ip/tx_fb_fft64_ip.xci}]
add_files -norecurse [file join $source_dir {sources_1/ip/ila_feedback_constellation/ila_feedback_constellation.xci}]
add_files -norecurse [file join $source_dir {sources_1/ip/ila_feedback_rf/ila_feedback_rf.xci}]
add_files -norecurse [file join $source_dir {sources_1/ip/ila_feedback_rrc/ila_feedback_rrc.xci}]
add_files -norecurse [file join $source_dir {sources_1/ip/ila_feedback_sync/ila_feedback_sync.xci}]
add_files -norecurse [file join $source_dir {sources_1/ip/ila_feedback_pn/ila_feedback_pn.xci}]
add_files -norecurse [file join $source_dir {sources_1/ip/ila_feedback_fde/ila_feedback_fde.xci}]
add_files -norecurse [file join $source_dir {sources_1/ip/vio_tx_auto/vio_tx_auto.xci}]
add_files -norecurse [file join $source_dir {sources_1/ip/ila_tx_feedback_control/ila_tx_feedback_control.xci}]
add_files -norecurse [file join $source_dir {sources_1/ip/ila_tx_dac/ila_tx_dac.xci}]
add_files -fileset constrs_1 -norecurse [file join $source_dir {constrs_1/new/board.xdc}]
add_files -fileset constrs_1 -norecurse [file join $source_dir {constrs_1/new/rate_convert_cdc.xdc}]
add_files -fileset constrs_1 -norecurse [file join $source_dir {constrs_1/new/reset_control_cdc.xdc}]
add_files -fileset constrs_1 -norecurse [file join $source_dir {constrs_1/new/timing.xdc}]
add_files -fileset constrs_1 -norecurse [file join $source_dir {constrs_1/new/feedback_cdc.xdc}]
add_files -fileset constrs_1 -norecurse [file join $source_dir {constrs_1/new/debug.xdc}]
add_files -fileset constrs_1 -norecurse [file join $source_dir {constrs_1/new/tx_monitor_cdc.xdc}]
set_property PROCESSING_ORDER {LATE} [get_files [file join $source_dir {constrs_1/new/rate_convert_cdc.xdc}]]
set_property PROCESSING_ORDER {LATE} [get_files [file join $source_dir {constrs_1/new/reset_control_cdc.xdc}]]
set_property PROCESSING_ORDER {LATE} [get_files [file join $source_dir {constrs_1/new/timing.xdc}]]
set_property PROCESSING_ORDER {LATE} [get_files [file join $source_dir {constrs_1/new/feedback_cdc.xdc}]]
set_property PROCESSING_ORDER {LATE} [get_files [file join $source_dir {constrs_1/new/debug.xdc}]]
set_property PROCESSING_ORDER {LATE} [get_files [file join $source_dir {constrs_1/new/tx_monitor_cdc.xdc}]]
# Declare cores for synthesis; the post-hook binds EDIF into the saved checkpoint.
if {$argc < 3} {error {Use build/build.py to materialize the delivered netlists first.}}
set delivered_core_root [file normalize [lindex $argv 2]]
foreach core_dir [glob [file join $delivered_core_root tx *]] {
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
set_property STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE Explore [get_runs impl_1]

set_property STEPS.SYNTH_DESIGN.ARGS.SHREG_MIN_SIZE 5 [get_runs synth_1]
foreach run [get_runs] {
    set properties [list_property $run]
    if {[lsearch -exact $properties AUTO_INCREMENTAL_CHECKPOINT] >= 0} {set_property AUTO_INCREMENTAL_CHECKPOINT 0 $run}
    if {[lsearch -exact $properties INCREMENTAL_CHECKPOINT] >= 0} {reset_property INCREMENTAL_CHECKPOINT $run}
}
update_compile_order -fileset sources_1
generate_target all [get_files -quiet *.bd]
set standalone_ip_files [list]
lappend standalone_ip_files [get_files [file join $source_dir {sources_1/ip/xxv_ethernet_2/xxv_ethernet_2.xci}]]
lappend standalone_ip_files [get_files [file join $source_dir {sources_1/ip/Vio_MAC_FlowControl/Vio_MAC_FlowControl.xci}]]
lappend standalone_ip_files [get_files [file join $source_dir {sources_1/ip/xge_tt_rx_mac_fifo/xge_tt_rx_mac_fifo.xci}]]
lappend standalone_ip_files [get_files [file join $source_dir {sources_1/ip/FIFO_IndepClk_MACaddr/FIFO_IndepClk_MACaddr.xci}]]
lappend standalone_ip_files [get_files [file join $source_dir {sources_1/ip/FIFO_IndepClk_FlowC/FIFO_IndepClk_FlowC.xci}]]
lappend standalone_ip_files [get_files [file join $source_dir {sources_1/ip/MAC_Buffer/MAC_Buffer.xci}]]
lappend standalone_ip_files [get_files [file join $source_dir {sources_1/ip/vio_tx_control/vio_tx_control.xci}]]
lappend standalone_ip_files [get_files [file join $source_dir {sources_1/ip/Mult_Gain/Mult_Gain.xci}]]
lappend standalone_ip_files [get_files [file join $source_dir {sources_1/ip/xge_tt_rx_user_fifo/xge_tt_rx_user_fifo.xci}]]
lappend standalone_ip_files [get_files [file join $source_dir {sources_1/ip/ILA_MAC_STATE/ILA_MAC_STATE.xci}]]
lappend standalone_ip_files [get_files [file join $source_dir {sources_1/ip/vio_gain/vio_gain.xci}]]
lappend standalone_ip_files [get_files [file join $source_dir {sources_1/ip/tx_fb_fft64_ip/tx_fb_fft64_ip.xci}]]
lappend standalone_ip_files [get_files [file join $source_dir {sources_1/ip/ila_feedback_constellation/ila_feedback_constellation.xci}]]
lappend standalone_ip_files [get_files [file join $source_dir {sources_1/ip/ila_feedback_rf/ila_feedback_rf.xci}]]
lappend standalone_ip_files [get_files [file join $source_dir {sources_1/ip/ila_feedback_rrc/ila_feedback_rrc.xci}]]
lappend standalone_ip_files [get_files [file join $source_dir {sources_1/ip/ila_feedback_sync/ila_feedback_sync.xci}]]
lappend standalone_ip_files [get_files [file join $source_dir {sources_1/ip/ila_feedback_pn/ila_feedback_pn.xci}]]
lappend standalone_ip_files [get_files [file join $source_dir {sources_1/ip/ila_feedback_fde/ila_feedback_fde.xci}]]
lappend standalone_ip_files [get_files [file join $source_dir {sources_1/ip/vio_tx_auto/vio_tx_auto.xci}]]
lappend standalone_ip_files [get_files [file join $source_dir {sources_1/ip/ila_tx_feedback_control/ila_tx_feedback_control.xci}]]
lappend standalone_ip_files [get_files [file join $source_dir {sources_1/ip/ila_tx_dac/ila_tx_dac.xci}]]
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
write_hw_platform -fixed -force -file [file join $output_dir tx_hardware.xsa]
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
    write_debug_probes -force [file join $output_dir tx.ltx]
    write_hw_platform -fixed -include_bit -force -file [file join $output_dir tx_with_bit.xsa]
    close_design
}
set fh [open [file join $output_dir BUILD_COMPLETE.txt] w]
puts $fh "stage=$build_stage synthesis=$synth_status"
close $fh
close_project
