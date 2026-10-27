# Standard impl_1 PHYS_OPT_DESIGN.TCL.POST hook, in the existing placed design.
# The main step uses AggressiveExplore. This hook requests only the three
# mapping options below, then audits actual reset structure. No retiming,
# checkpoint/project writes, timing exceptions, or swallowed tool errors.
namespace eval rx_impl_post {}
set rx_impl_post::tools [file normalize [file dirname [info script]]]
set rx_impl_post::deploy [file normalize [file join $rx_impl_post::tools ..]]
set rx_impl_post::reports [file join $rx_impl_post::deploy build_final reports]
file mkdir $rx_impl_post::reports
set rx_impl_post::stream [open [file join $rx_impl_post::reports impl_physopt_post_execution.txt] w]
puts $rx_impl_post::stream "hook=PHYS_OPT_DESIGN.TCL.POST\nstarted_epoch=[clock seconds]\ndesign=[current_design]\nstate=STARTED"
puts $rx_impl_post::stream "command=phys_opt_design -dsp_register_opt -bram_enable_opt -critical_pin_opt\nfunctional_retime_requested=0"
flush $rx_impl_post::stream
puts "RX_IMPL_PHYSOPT_POST_START=[clock seconds]"
phys_opt_design -dsp_register_opt -bram_enable_opt -critical_pin_opt
puts $rx_impl_post::stream "mapping_command_returned_epoch=[clock seconds]"
flush $rx_impl_post::stream
source [file join $rx_impl_post::tools verify_region_reset_replication.tcl]
set rx_impl_post::audit [rx_verify_region_reset_replication [file join $rx_impl_post::reports region_reset_after_preroute] 1]
if {[dict get $rx_impl_post::audit result] ne "PASS_STRUCTURAL_ONLY"} {error "Post-physical-optimization reset structure failed"}
puts $rx_impl_post::stream "audit=$rx_impl_post::audit\nresult=PASS_STRUCTURAL_ONLY\ntiming_pass_not_asserted=1\ncompleted_epoch=[clock seconds]"
close $rx_impl_post::stream
puts "RX_IMPL_PHYSOPT_POST_COMPLETE=[clock seconds]"
