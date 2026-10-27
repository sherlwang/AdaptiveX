# Standard impl_1 PHYS_OPT_DESIGN.TCL.PRE hook, with an already placed design.
# No project/DCP is opened or saved here. Native optimization errors are fatal.
namespace eval rx_impl_pre {}
set rx_impl_pre::tools [file normalize [file dirname [info script]]]
set rx_impl_pre::deploy [file normalize [file join $rx_impl_pre::tools ..]]
set rx_impl_pre::rx [file normalize [file join $rx_impl_pre::deploy .. ..]]
set rx_impl_pre::reports [file join $rx_impl_pre::deploy build_final reports impl_physopt_pre]
file mkdir $rx_impl_pre::reports
source [file join $rx_impl_pre::tools verify_region_reset_replication.tcl]

proc rx_impl_pre::log {stream line} {puts $stream $line; flush $stream; puts "RX_IMPL_PRE: $line"}
proc rx_impl_pre::optional_property {object property} {
    if {[lsearch -exact [list_property $object] $property] < 0} {return NOT_AVAILABLE}
    return [get_property $property $object]
}
proc rx_impl_pre::placed_clock {cell stream phase} {
    set name [get_property NAME $cell]
    set loc [get_property LOC $cell]
    set bel [get_property BEL $cell]
    set clocks [rx_region_reset_audit::names [get_clocks -quiet -of_objects [rx_region_reset_audit::pin $cell C]]]
    log $stream "phase=$phase;cell=$name;REF_NAME=[get_property REF_NAME $cell];LOC=<$loc>;BEL=<$bel>;clocks=$clocks"
    if {$loc eq "" || $bel eq "" || [llength $clocks] != 1} {error "Not a uniquely clocked placed target: $name"}
    return [lindex $clocks 0]
}

# Before read_xdc, accept either original or already repaired last-stage
# attributes, so project autoload followed by explicit reload is idempotent.
proc rx_impl_pre::guard {stream phase repaired} {
    variable reports
    set metadata {}
    set presets {}
    set replication_nets {}
    set protected_q {}
    set regions 0
    foreach vector {reset_pipe_reg read_reset_pipe_reg} {
        set previous {}
        set clock_name {}
        for {set bit 0} {$bit < 3} {incr bit} {
            set name [format {u_fmc_THz_test_top/u_ETH_TOP/u_constellation_eth_jiemian/u_sample_cdc/%s[%d]} $vector $bit]
            set cell [rx_region_reset_audit::cell $name]
            if {[get_property REF_NAME $cell] ne "FDPE"} {error "Metadata reset is not FDPE: $name"}
            set clock [placed_clock $cell $stream $phase]
            if {$bit == 0} {set clock_name $clock} elseif {$clock ne $clock_name} {error "Metadata reset chain clocks differ: $vector"}
            if {$bit > 0} {rx_region_reset_audit::assert_source [rx_region_reset_audit::pin $cell D] [rx_region_reset_audit::pin $previous Q]}
            set pre [rx_region_reset_audit::pin $cell PRE]
            set raw [get_property ASYNC_REG $cell]
            log $stream "phase=$phase;metadata_cell=$name;ASYNC_REG_raw=<$raw>;PRE=[get_property NAME $pre]"
            if {$repaired && ![rx_region_reset_audit::bool $raw 0]} {error "Metadata ASYNC_REG readback failed: $name"}
            lappend metadata $cell
            lappend presets $pre
            set previous $cell
        }
    }
    foreach region {frontend cfo fde nlms demap} {
        set previous {}
        set clock_name {}
        for {set bit 0} {$bit < 3} {incr bit} {
            set name [format {u_fmc_THz_test_top/u_PHY_TOP_Rx/u_%s_reset/release_q_reg[%d]} $region $bit]
            set cell [rx_region_reset_audit::cell $name]
            if {[get_property REF_NAME $cell] ne "FDCE"} {error "Region reset is not FDCE: $name"}
            set clock [placed_clock $cell $stream $phase]
            if {$bit == 0} {set clock_name $clock} elseif {$clock ne $clock_name} {error "Region reset chain clocks differ: $region"}
            set q [rx_region_reset_audit::pin $cell Q]
            set canonical [get_nets -quiet -of_objects $q]
            set segments [get_nets -quiet -segments -of_objects $q]
            if {[llength $canonical] != 1 || ![llength $segments]} {error "Region reset Q net missing/ambiguous: $name"}
            foreach property {DONT_TOUCH ASYNC_REG} {
                set raw [get_property $property $cell]
                log $stream "phase=$phase;region_cell=$name;property=$property;raw=<$raw>"
                if {$bit < 2 && ![rx_region_reset_audit::bool $raw 0]} {error "Protected stage lost $property: $name"}
                if {$bit == 2 && $repaired && [rx_region_reset_audit::bool $raw 1]} {error "Last-stage $property readback failed: $name"}
            }
            foreach net $segments {
                set raw [get_property DONT_TOUCH $net]
                set net_name [get_property NAME $net]
                log $stream "phase=$phase;q_segment=$net_name;DONT_TOUCH_raw=<$raw>"
                if {$bit < 2} {dict set protected_q $net_name [rx_region_reset_audit::bool $raw 1]}
                if {$bit == 2 && $repaired && [rx_region_reset_audit::bool $raw 1]} {error "Last-stage Q segment still protected: $net_name"}
            }
            if {$bit < 2 && ![rx_region_reset_audit::bool [get_property DONT_TOUCH [lindex $canonical 0]] 0]} {error "Protected canonical Q net lost DONT_TOUCH: $name"}
            if {$bit > 0} {
                set d [rx_region_reset_audit::pin $cell D]
                rx_region_reset_audit::assert_source $d [rx_region_reset_audit::pin $previous Q]
                # A nonempty actual setup path proves we did not cut this real D.
                set paths [get_timing_paths -quiet -from $previous -to $d -delay_type max -max_paths 1]
                if {[llength $paths] != 1} {error "Real reset-chain D path is not timed: $name"}
                set path [lindex $paths 0]
                log $stream "phase=$phase;timed_chain_D=[get_property NAME $d];source=[get_property NAME $previous];REQUIREMENT=[get_property REQUIREMENT $path];EXCEPTION=<[optional_property $path EXCEPTION]>"
            }
            if {$bit == 2} {lappend replication_nets [lindex $canonical 0]}
            set previous $cell
        }
        incr regions
    }
    if {[llength $metadata] != 6 || [llength $presets] != 6 || [llength $replication_nets] != 5 || $regions != 5} {error "Repair scope differs from exactly 6 metadata FFs/5 regions"}
    return [dict create metadata $metadata presets $presets replication_nets $replication_nets protected_q $protected_q]
}

proc rx_impl_pre::check_presets {stream presets} {
    variable reports
    if {[llength $presets] != 6} {error "Expected exactly six PRE endpoints"}
    set valid [rx_report_api::filtered [file join $reports metadata_presets_valid_exceptions.rpt] -to $presets]
    rx_report_api::assert_false_targets $valid $presets
    foreach pre $presets {log $stream "valid_false_path_PRE=[get_property NAME $pre];valid_exception_report=metadata_presets_valid_exceptions.rpt"}
}

set rx_impl_pre::stream [open [file join $rx_impl_pre::reports execution.txt] w]
rx_impl_pre::log $rx_impl_pre::stream "hook=PHYS_OPT_DESIGN.TCL.PRE;started_epoch=[clock seconds];design=[current_design];state=STARTED"
source [file join $rx_impl_pre::tools verify_feedback_constraints.tcl]
rx_preflight_report_exceptions_api [file join $rx_impl_pre::reports report_api_native_preflight]
set rx_impl_pre::before [rx_impl_pre::guard $rx_impl_pre::stream before_explicit_read_xdc 0]
# Must remain an independent top-level read_xdc command: the resume guard checks
# this explicit declaration reload in the actual placed design, not a synth DCP.
read_xdc [file join $rx_impl_pre::rx rx.srcs constrs_1 new rx_impl_timing_repair.xdc]
rx_report_api::export [file join $rx_impl_pre::reports after_explicit_read_valid_exceptions.xdc]
set rx_impl_pre::after [rx_impl_pre::guard $rx_impl_pre::stream after_explicit_read_xdc 1]
set rx_impl_pre::before_q [dict get $rx_impl_pre::before protected_q]
set rx_impl_pre::after_q [dict get $rx_impl_pre::after protected_q]
if {[dict size $rx_impl_pre::before_q] != [dict size $rx_impl_pre::after_q]} {error "Protected Q segment count changed during read_xdc"}
dict for {rx_impl_pre::name rx_impl_pre::expected} $rx_impl_pre::before_q {
    if {![dict exists $rx_impl_pre::after_q $rx_impl_pre::name] || [dict get $rx_impl_pre::after_q $rx_impl_pre::name] != $rx_impl_pre::expected} {error "Protected first-two-stage Q segment properties changed during read_xdc: $rx_impl_pre::name"}
}
rx_impl_pre::check_presets $rx_impl_pre::stream [dict get $rx_impl_pre::after presets]
rx_verify_region_reset_replication [file join $rx_impl_pre::reports before_replication] 1
set rx_impl_pre::nets [dict get $rx_impl_pre::after replication_nets]
foreach rx_impl_pre::net $rx_impl_pre::nets {rx_impl_pre::log $rx_impl_pre::stream "force_replication_physical_Q_net=[get_property NAME $rx_impl_pre::net]"}
rx_impl_pre::log $rx_impl_pre::stream "command=phys_opt_design -force_replication_on_nets;exact_net_count=[llength $rx_impl_pre::nets];command_started_epoch=[clock seconds]"
# Do not catch/ignore a native command rejection in a production implementation.
phys_opt_design -force_replication_on_nets $rx_impl_pre::nets
rx_impl_pre::log $rx_impl_pre::stream "replication_command_returned_epoch=[clock seconds]"
rx_verify_region_reset_replication [file join $rx_impl_pre::reports after_replication] 1
foreach rx_impl_pre::cell [dict get $rx_impl_pre::after metadata] {
    set rx_impl_pre::raw [get_property ASYNC_REG $rx_impl_pre::cell]
    rx_impl_pre::log $rx_impl_pre::stream "after_replication_metadata_cell=[get_property NAME $rx_impl_pre::cell];ASYNC_REG_raw=<$rx_impl_pre::raw>"
    if {![rx_region_reset_audit::bool $rx_impl_pre::raw 0]} {error "Metadata ASYNC_REG lost after physical replication"}
}
rx_impl_pre::check_presets $rx_impl_pre::stream [dict get $rx_impl_pre::after presets]
rx_impl_pre::log $rx_impl_pre::stream "result=PASS_STRUCTURAL_ONLY;timing_pass_not_asserted=1;completed_epoch=[clock seconds]"
close $rx_impl_pre::stream
puts "RX_IMPL_PHYSOPT_PRE_COMPLETE=[clock seconds]"
