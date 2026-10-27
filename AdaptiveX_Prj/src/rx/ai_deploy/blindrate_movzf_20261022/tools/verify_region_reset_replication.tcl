# Read-only structural audit for an ALREADY OPEN diagnostic checkpoint.
# Does not open/save a project/DCP, set properties, alter constraints, or optimize.
# It permits the original final-stage FF to disappear after replication, while
# requiring the two protected stages and every actual final-stage D connection.
# Usage: rx_verify_region_reset_replication <report_directory> ?strict=1?
namespace eval rx_region_reset_audit {}

proc rx_region_reset_audit::names {objects} {
    set names {}
    foreach object $objects {lappend names [get_property NAME $object]}
    return [lsort -unique $names]
}

proc rx_region_reset_audit::bool {value allow_unset} {
    set v [string tolower [string trim $value]]
    if {$v in {1 true}} {return 1}
    if {$v in {0 false}} {return 0}
    if {$allow_unset && $v eq ""} {return 0}
    error "Unrecognized Boolean property representation: <$value>"
}

proc rx_region_reset_audit::cell {name {optional 0}} {
    # The NAME expression is data, never an eval; [] in register names remain
    # literal. The final equality check also excludes any unintended match.
    set objects [get_cells -quiet -hier -filter [format {NAME == %s} $name]]
    if {$optional && ![llength $objects]} {return {}}
    if {[llength $objects] != 1 || [get_property NAME [lindex $objects 0]] ne $name} {
        error "Exact reset cell missing/ambiguous: $name"
    }
    return [lindex $objects 0]
}

proc rx_region_reset_audit::pin {cell terminal} {
    set pins [get_pins -quiet -of_objects $cell -filter [format {REF_PIN_NAME == %s} $terminal]]
    if {[llength $pins] != 1} {error "Expected one $terminal pin on [get_property NAME $cell]"}
    return [lindex $pins 0]
}

proc rx_region_reset_audit::driver_names {pin} {
    set nets [get_nets -quiet -segments -of_objects $pin]
    if {![llength $nets]} {error "No electrical net for [get_property NAME $pin]"}
    return [names [get_pins -quiet -leaf -of_objects $nets -filter {DIRECTION == OUT}]]
}

proc rx_region_reset_audit::assert_source {destination expected_q} {
    set sources [driver_names $destination]
    set expected [get_property NAME $expected_q]
    if {[llength $sources] != 1 || [lindex $sources 0] ne $expected} {
        error "Direct D connection differs: [get_property NAME $destination] actual=$sources expected=$expected"
    }
}

proc rx_verify_region_reset_replication {report_directory {strict 1}} {
    set report_directory [file normalize $report_directory]
    file mkdir $report_directory
    set stream [open [file join $report_directory region_reset_replication_structure.txt] w]
    puts $stream "design=[current_design]\nmode=READ_ONLY_EXISTING_DESIGN\nproduction_files_modified=0"
    puts $stream "policy=EXACT_FIRST_TWO_FFS_AND_ACTUAL_LAST_STAGE_D_FANOUT"
    set checked_first 0
    set checked_last 0
    set regions 0
    set code [catch {
        foreach region {frontend cfo fde nlms demap} {
            set prefix u_fmc_THz_test_top/u_PHY_TOP_Rx/u_${region}_reset
            set first {}
            set reference_clock {}
            for {set bit 0} {$bit < 2} {incr bit} {
                set name [format {%s/release_q_reg[%d]} $prefix $bit]
                set cell [rx_region_reset_audit::cell $name]
                if {[get_property REF_NAME $cell] ne "FDCE"} {error "Protected stage is not FDCE: $name"}
                foreach property {ASYNC_REG DONT_TOUCH} {
                    set raw [get_property $property $cell]
                    if {![rx_region_reset_audit::bool $raw 0]} {error "Protected $name lost $property"}
                    puts $stream "protected_cell=$name;property=$property;raw=$raw;normalized=1"
                }
                set q [rx_region_reset_audit::pin $cell Q]
                set canonical [get_nets -quiet -of_objects $q]
                if {[llength $canonical] != 1} {error "Protected stage canonical Q net ambiguous: $name"}
                set raw [get_property DONT_TOUCH [lindex $canonical 0]]
                if {![rx_region_reset_audit::bool $raw 0]} {error "Original protected Q net lost DONT_TOUCH: $name"}
                puts $stream "protected_q_net=[get_property NAME [lindex $canonical 0]];DONT_TOUCH=$raw"
                set c [rx_region_reset_audit::pin $cell C]
                set clocks [rx_region_reset_audit::names [get_clocks -quiet -of_objects $c]]
                if {[llength $clocks] != 1} {error "Protected clock ambiguous: $name/$clocks"}
                if {$bit == 0} {set reference_clock $clocks} elseif {$clocks ne $reference_clock} {
                    error "First two stages use different physical timing clocks: $prefix"
                }
                lappend first $cell
                incr checked_first
            }
            set q0 [rx_region_reset_audit::pin [lindex $first 0] Q]
            set q1 [rx_region_reset_audit::pin [lindex $first 1] Q]
            set d1 [rx_region_reset_audit::pin [lindex $first 1] D]
            rx_region_reset_audit::assert_source $d1 $q0
            puts $stream "preserved_direct_chain=[get_property NAME $q0]->[get_property NAME $d1]"

            # Discover final stages by actual leaf IN D fanout, never by assuming
            # the original [2] name survives a valid physical replication pass.
            set q1nets [get_nets -quiet -segments -of_objects $q1]
            set loads [get_pins -quiet -leaf -of_objects $q1nets -filter {DIRECTION == IN}]
            set last_names {}
            foreach load $loads {
                if {[get_property REF_PIN_NAME $load] ne "D"} {
                    error "Protected stage1 Q has non-D leaf fanout: [get_property NAME $load]"
                }
                set cells [get_cells -quiet -of_objects $load]
                if {[llength $cells] != 1} {error "Final-stage D cell ambiguous: [get_property NAME $load]"}
                set cell [lindex $cells 0]
                set name [get_property NAME $cell]
                if {[get_property REF_NAME $cell] ne "FDCE"} {error "Final-stage fanout is not FDCE: $name"}
                rx_region_reset_audit::assert_source $load $q1
                set clock [rx_region_reset_audit::names [get_clocks -quiet -of_objects [rx_region_reset_audit::pin $cell C]]]
                if {$clock ne $reference_clock} {error "Final-stage clock differs from protected chain: $name/$clock"}
                foreach property {ASYNC_REG DONT_TOUCH} {
                    set raw [get_property $property $cell]
                    if {[rx_region_reset_audit::bool $raw 1]} {error "Final-stage remains protected by $property: $name"}
                    puts $stream "final_cell=$name;property=$property;raw=<$raw>;normalized=0"
                }
                set q [rx_region_reset_audit::pin $cell Q]
                set nets [get_nets -quiet -segments -of_objects $q]
                if {![llength $nets]} {error "Final-stage Q has no real net: $name"}
                foreach net $nets {
                    set raw [get_property DONT_TOUCH $net]
                    if {[rx_region_reset_audit::bool $raw 1]} {
                        error "Final-stage Q segment remains DONT_TOUCH: [get_property NAME $net]"
                    }
                    puts $stream "final_q_net=[get_property NAME $net];DONT_TOUCH_raw=<$raw>;normalized=0"
                }
                puts $stream "actual_final_d=[get_property NAME $load];driver=[get_property NAME $q1];clock=$clock"
                lappend last_names $name
            }
            set last_names [lsort -unique $last_names]
            if {![llength $last_names]} {error "No actual final-stage D fanout remains: $prefix"}
            set original_name [format {%s/release_q_reg[2]} $prefix]
            set original [rx_region_reset_audit::cell $original_name 1]
            if {[llength $original] && [lsearch -exact $last_names $original_name] < 0} {
                error "Original final stage exists but is no longer connected to stage1 Q: $original_name"
            }
            puts $stream "${region}_original_final_present=[expr {[llength $original] == 1}]"
            puts $stream "${region}_actual_final_cell_count=[llength $last_names]"
            puts $stream "${region}_additional_final_cells=[expr {[llength $last_names]-1}]"
            incr checked_last [llength $last_names]
            incr regions
        }
        if {$checked_first != 10 || $regions != 5} {error "Expected ten protected FFs in five regions"}
    } message options]
    puts $stream "protected_first_two_ff_count=$checked_first\nactual_final_ff_count=$checked_last\nregions_checked=$regions"
    if {$code} {
        puts $stream "FAIL=$message\nerror_info=[dict get $options -errorinfo]\nresult=FAIL"
    } else {
        puts $stream "result=PASS_STRUCTURAL_ONLY"
        puts $stream "timing_pass_not_asserted=1\nreplication_in_every_region_not_asserted=1"
    }
    close $stream
    if {$code && $strict} {error "Region-reset structural audit FAILED: $message"}
    return [dict create result [expr {$code ? "FAIL" : "PASS_STRUCTURAL_ONLY"}] protected_first_two_ff_count $checked_first actual_final_ff_count $checked_last regions_checked $regions]
}
