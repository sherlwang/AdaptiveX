# Read an existing public build and export reports without rerunning implementation.
# Usage: vivado -mode batch -source collect_reports.tcl -tclargs project.xpr synth_1|impl_1 report_dir
if {$argc != 3} {error {Expected: project.xpr synth_1|impl_1 report_dir}}
set project_file [file normalize [lindex $argv 0]]
set run_name [lindex $argv 1]
set output_dir [file normalize [lindex $argv 2]]
if {$run_name ni {synth_1 impl_1}} {error {Select synth_1 or impl_1}}
file mkdir $output_dir
open_project $project_file
open_run $run_name
if {$run_name eq "synth_1"} {
    set blackboxes [get_cells -quiet -hier -filter {IS_BLACKBOX == 1 && NAME != dbg_hub}]
} else {
    set blackboxes [get_cells -quiet -hier -filter {IS_BLACKBOX == 1}]
}
if {[llength $blackboxes]} {error "Unresolved black boxes: $blackboxes"}
report_utilization -file [file join $output_dir utilization.rpt]
report_utilization -hierarchical -hierarchical_depth 8 -file [file join $output_dir hierarchy.rpt]
report_timing_summary -delay_type min_max -report_unconstrained -file [file join $output_dir timing.rpt]
report_clock_interaction -file [file join $output_dir clocks.rpt]
report_drc -file [file join $output_dir drc.rpt]
report_bus_skew -file [file join $output_dir bus_skew.rpt]
report_cdc -details -file [file join $output_dir cdc.rpt]
set fd [open [file join $output_dir report_status.txt] w]
puts $fd "run=$run_name"
puts $fd {unresolved_black_boxes=0}
puts $fd {board_test=not_performed}
close $fd
close_project
puts {PUBLIC_REPORTS_COMPLETE}
