# Synthesis post-hook. Replace declared black boxes, then persist the complete run result.
# The build recipe copies this file next to the XPR; delivered cores are its sibling directory.
set delivered_root [file normalize [file join [file dirname [info script]] .. cores]]
set delivered_files [glob [file join $delivered_root * * core.edf]]
if {![llength $delivered_files]} {error "No delivered EDIF cores: $delivered_root"}
set status [open [file join [pwd] delivered_core_binding.txt] w]
foreach netlist $delivered_files {
    set module [file tail [file dirname $netlist]]
    set cells [get_cells -quiet -hier -filter "REF_NAME == $module"]
    if {![llength $cells]} {error "Missing declared core: $module"}
    update_design -strict -cells $cells -from_file $netlist
    foreach cell $cells {
        if {[get_property IS_BLACKBOX $cell]} {error "Core remains unresolved: $cell"}
        puts $status "BOUND module=$module cell=$cell"
    }
}
close $status
# Vivado runs the post-hook after its default checkpoint/report writes.
# Save again so GUI open_run and implementation receive the populated netlist.
set design_name [get_property TOP [current_design]]
if {$design_name eq ""} {error {Current synthesis design has no TOP property}}
write_checkpoint -force -noxdef [file join [pwd] "${design_name}.dcp"]
report_utilization -file [file join [pwd] "${design_name}_utilization_synth.rpt"] -pb [file join [pwd] "${design_name}_utilization_synth.pb"]
puts "DELIVERED_CORES_BOUND [llength $delivered_files]"
