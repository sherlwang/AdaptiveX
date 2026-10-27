# Read-only audit of an ALREADY OPEN synthesized/implemented design.
# Does not open a project/checkpoint, change constraints, or launch any run.
# Usage:
#   source .../verify_feedback_constraints.tcl
#   rx_verify_feedback_constraints <report_directory> ?stage? ?strict?
# stage is a report label (for example synth or routed). strict defaults to 1.
# Empty/mismatched real objects and absent effective exceptions FAIL the audit.
# Vivado 2021.2 command references:
# https://docs.amd.com/r/2021.2-English/ug835-vivado-tcl-commands/report_exceptions
# https://docs.amd.com/r/2021.2-English/ug835-vivado-tcl-commands/report_bus_skew

namespace eval rx_fb_audit {}

proc rx_fb_audit::save {path contents} {
    set stream [open $path w]
    puts $stream $contents
    close $stream
}

proc rx_fb_audit::describe {stream label objects} {
    puts $stream "${label}_count=[llength $objects]"
    foreach object $objects {puts $stream "${label}_object=[get_property NAME $object]"}
}

proc rx_fb_audit::failure {stream failures_var message} {
    upvar 1 $failures_var failures
    lappend failures $message
    puts $stream "FAIL=$message"
}

# This uses actual connected clock pins when the top-level alias was renamed.
# A global clock-name/frequency match alone is deliberately not a fallback.
proc rx_fb_audit::clock {stream net_name mhz output_number consumer_pins failures_var} {
    upvar 1 $failures_var failures
    set candidates {}
    set nets [get_nets -quiet $net_name]
    if {[llength $nets]} {
        lappend candidates [list "top_net:$net_name" [get_clocks -quiet -of_objects $nets]]
    } else {
        puts $stream "${net_name}_top_alias=ABSENT; checking connected clock pins"
    }
    set bufg_pins [get_pins -quiet -hier -filter "NAME =~ *system_i/clk_wiz_0/*/clkout${output_number}_buf/O"]
    if {[llength $bufg_pins]} {
        lappend candidates [list "ClockWizard_BUFG_output" [get_clocks -quiet -of_objects $bufg_pins]]
    }
    foreach pattern $consumer_pins {
        set pins [get_pins -quiet -hier -filter "NAME =~ $pattern"]
        if {[llength $pins]} {
            lappend candidates [list "consumer:$pattern" [get_clocks -quiet -of_objects $pins]]
        }
    }
    set all_clocks {}
    set expected [expr {1000.0/$mhz}]
    foreach candidate $candidates {
        lassign $candidate method clocks
        set clocks [lsort -unique $clocks]
        puts $stream "${net_name}_candidate=$method;clocks=$clocks"
        if {[llength $clocks] != 1} {
            failure $stream failures "Ambiguous/missing clock at $net_name via $method"
            continue
        }
        set clock [lindex $clocks 0]
        set period [get_property PERIOD $clock]
        puts $stream "${net_name}_period_ns=$period;expected_ns=$expected"
        if {abs($period-$expected)>0.01} {
            failure $stream failures "Incorrect $net_name physical clock period: $period"
        }
        lappend all_clocks $clock
    }
    set all_clocks [lsort -unique $all_clocks]
    if {[llength $all_clocks] != 1} {
        failure $stream failures "No unique connected physical clock for $net_name: $all_clocks"
    }
    return $all_clocks
}

# Both the actual path REQUIREMENT/EXCEPTION and the valid exception report
# must agree. Merely finding a set_max_delay command in an XDC is insufficient.
proc rx_fb_audit::maxdelay {stream report_dir label sources destinations budget failures_var} {
    upvar 1 $failures_var failures
    describe $stream ${label}_sources $sources
    describe $stream ${label}_destinations $destinations
    if {![llength $sources] || ![llength $destinations]} {
        failure $stream failures "$label has empty real source/destination objects"
        return
    }
    set valid_file [file join $report_dir ${label}_valid_exceptions.rpt]
    set valid [rx_report_api::filtered $valid_file -from $sources -to $destinations]
    save $valid_file $valid
    set ignored [report_exceptions -from $sources -to $destinations -ignored -return_string]
    save [file join $report_dir ${label}_ignored_exceptions.rpt] $ignored
    set ignored_rows [rx_report_api::parse_filtered $ignored]
    puts $stream "${label}_ignored_row_count=[llength $ignored_rows]"
    if {[llength $ignored_rows]} {failure $stream failures "$label has ignored exceptions in the exact source/destination scope"}
    if {![regexp -nocase {set_max_delay|max.?delay} $valid]} {
        failure $stream failures "$label has no valid set_max_delay exception"
    }
    report_timing -from $sources -to $destinations -delay_type max -max_paths 32 -nworst 1 -file [file join $report_dir ${label}_setup.rpt]
    set paths [get_timing_paths -quiet -from $sources -to $destinations -delay_type max -max_paths 128 -nworst 1]
    puts $stream "${label}_timed_path_count=[llength $paths]"
    if {![llength $paths]} {
        failure $stream failures "$label has no timed max-delay paths (possibly overridden by a false path)"
    }
    foreach path $paths {
        set requirement [get_property REQUIREMENT $path]
        set path_properties [list_property $path]
        set exception NOT_AVAILABLE
        if {[lsearch -exact $path_properties EXCEPTION] >= 0} {set exception [get_property EXCEPTION $path]}
        puts $stream "${label}_path_properties=$path_properties"
        puts $stream "${label}_path=[get_property NAME $path];requirement=$requirement;exception_optional=$exception;slack=[get_property SLACK $path]"
        if {abs($requirement-$budget)>0.0001} {
            failure $stream failures "$label effective max-delay exception differs from $budget ns"
        }
    }
}

proc rx_fb_audit::reset {stream report_dir label registers failures_var} {
    upvar 1 $failures_var failures
    describe $stream ${label}_registers $registers
    set pins {}
    if {[llength $registers]} {
        set pins [get_pins -quiet -of_objects $registers -filter {REF_PIN_NAME == CLR || REF_PIN_NAME == PRE}]
    }
    describe $stream ${label}_async_pins $pins
    if {![llength $registers] || ![llength $pins]} {
        failure $stream failures "$label reset-synchronizer/async-pin set is empty"
        return
    }
    set valid_file [file join $report_dir ${label}_valid_exceptions.rpt]
    set valid [rx_report_api::filtered $valid_file -to $pins]
    save $valid_file $valid
    if {![regexp -nocase {set_false_path|false.?path} $valid]} {
        failure $stream failures "$label has no valid asynchronous reset false-path exception"
    }
}

proc rx_verify_feedback_constraints {report_directory {stage impl} {strict 1}} {
    set report_directory [file normalize $report_directory]
    file mkdir $report_directory
    set stream [open [file join $report_directory feedback_constraint_audit.txt] w]
    set failures {}
    puts $stream "design=[current_design]\nstage=$stage\nmode=READ_ONLY_EXISTING_DESIGN"
    set result [catch {
        rx_report_api::export [file join $report_directory all_valid_exceptions.xdc]
        rx_fb_audit::clock $stream data_clk 409.6 1 [list *system_i/usp_rf_data_converter_0/m0_axis_aclk *u_fmc_THz_test_top/clk1] failures
        rx_fb_audit::clock $stream data_clk1 204.8 2 [list *u_PHY_TOP_Rx/debug_capture.u_ila_ai/clk *u_feedback_tx/u_tx/u_event_fifo/rd_gray_w1_reg*/C] failures
        rx_fb_audit::clock $stream data_clk2 40.96 3 [list *system_i/usp_rf_data_converter_0/s3_axis_aclk *u_feedback_tx/u_tx/u_event_fifo/wr_gray_r1_reg*/C *u_feedback_tx/u_tx/u_framer/frames_sent_reg*/C] failures

        # Audit exactly the objects selected by the production XDC. A broader
        # RAM* query is diagnostic only and cannot turn an empty selection PASS.
        set wr_dst [get_pins -quiet -of_objects [get_cells -quiet -hier -filter {NAME =~ *u_event_fifo/wr_gray_r1_reg*}] -filter {REF_PIN_NAME == D}]
        set rd_dst [get_pins -quiet -of_objects [get_cells -quiet -hier -filter {NAME =~ *u_event_fifo/rd_gray_w1_reg*}] -filter {REF_PIN_NAME == D}]
        set wr_src {}
        set rd_src {}
        if {[llength $wr_dst]} {
            set wr_src [filter [all_fanin -flat -startpoints_only -only_cells -to $wr_dst] {NAME =~ *u_event_fifo/wr_gray_reg* || NAME =~ *u_event_fifo/wr_binary_reg*}]
        }
        if {[llength $rd_dst]} {
            set rd_src [filter [all_fanin -flat -startpoints_only -only_cells -to $rd_dst] {NAME =~ *u_event_fifo/rd_gray_reg* || NAME =~ *u_event_fifo/rd_binary_reg*}]
        }
        foreach {label destinations} [list wr_gray $wr_dst rd_gray $rd_dst] {
            if {[llength $destinations] != 6} {
                rx_fb_audit::failure $stream failures "$label must have six first-stage D pins for the 32-entry FIFO"
            }
        }
        rx_fb_audit::maxdelay $stream $report_directory wr_gray $wr_src $wr_dst 4.882 failures
        rx_fb_audit::maxdelay $stream $report_directory rd_gray $rd_src $rd_dst 4.882 failures

        set data_ram [get_cells -quiet -hier -filter {IS_PRIMITIVE == 1 && NAME =~ *u_event_fifo/messages_reg* && (REF_NAME =~ RAMD* || REF_NAME =~ RAMS*)}]
        rx_fb_audit::describe $stream fwft_memory_primitives $data_ram
        set all_memory [get_cells -quiet -hier -filter {IS_PRIMITIVE == 1 && NAME =~ *u_event_fifo/* && REF_NAME =~ RAM*}]
        foreach ram $all_memory {puts $stream "memory_diagnostic=[get_property NAME $ram];REF_NAME=[get_property REF_NAME $ram]"}
        set data_clocks {}
        if {[llength $data_ram]} {
            set data_clocks [get_pins -quiet -of_objects $data_ram -filter {REF_PIN_NAME == CLK || REF_PIN_NAME == WCLK}]
        }
        set captures [get_pins -quiet -of_objects [get_cells -quiet -hier -filter {NAME =~ *u_framer/prepared_packet24_reg*}] -filter {REF_PIN_NAME == D}]
        rx_fb_audit::maxdelay $stream $report_directory fwft_data $data_clocks $captures 48.828 failures

        set fifo_release [get_cells -quiet -hier -filter {ASYNC_REG == TRUE && (NAME =~ *u_event_fifo/wr_release_reg* || NAME =~ *u_event_fifo/rd_release_reg*)}]
        set tx_release [get_cells -quiet -hier -filter {NAME =~ *u_feedback_tx*/release_dly_reg* || NAME =~ *u_feedback_tx*/release_out_reg*}]
        rx_fb_audit::reset $stream $report_directory fifo_reset_release $fifo_release failures
        rx_fb_audit::reset $stream $report_directory feedback_reset_release $tx_release failures

        # 2021.2 report_bus_skew has no -from/-to options. Inspect its real
        # per-constraint sections, including requirement and endpoint count.
        set skew_report [report_bus_skew -max_paths 1 -return_string]
        rx_fb_audit::save [file join $report_directory feedback_bus_skew.rpt] $skew_report
        set sections [regexp -all -inline {(?s)\nId:.*?(?=\nId:|\Z)} $skew_report]
        foreach target {wr_gray_r1_reg rd_gray_w1_reg} {
            set found 0
            foreach section $sections {
                if {[string first "u_event_fifo/$target" $section] < 0} {continue}
                incr found
                set has_budget [regexp {Requirement:\s+4\.882ns} $section]
                set has_endpoints [regexp {Endpoints:\s+6(?:\s|$)} $section]
                puts $stream "bus_skew_${target}=matched;budget_4_882=$has_budget;endpoints_6=$has_endpoints"
                if {!$has_budget || !$has_endpoints} {
                    rx_fb_audit::failure $stream failures "$target bus-skew requirement/coverage differs from six endpoints at 4.882 ns"
                }
                if {[regexp {Slack\s+\(VIOLATED\)} $section]} {
                    rx_fb_audit::failure $stream failures "$target effective bus-skew constraint is violated (see detailed report)"
                }
            }
            if {!$found} {rx_fb_audit::failure $stream failures "No effective bus-skew constraint for $target"}
        }
        report_exceptions -coverage -file [file join $report_directory all_exception_coverage.rpt]
        report_exceptions -ignored -file [file join $report_directory all_ignored_exceptions.rpt]
    } message options]
    if {$result} {
        rx_fb_audit::failure $stream failures "Audit query failed: $message"
        puts $stream "query_error_info=[dict get $options -errorinfo]"
    }
    puts $stream "failure_count=[llength $failures]"
    set status [expr {[llength $failures] ? "FAIL" : "PASS"}]
    puts $stream "result=$status"
    close $stream
    if {$strict && [llength $failures]} {
        error "Feedback constraint audit FAILED: [join $failures {; }]"
    }
    return [dict create result $status failures $failures report_directory $report_directory]
}

# Compatibility preflight in the already placed standard implementation. This
# queries the same effective budgets as the final audit; no constraints change.
proc rx_query_feedback_maxdelay_preroute {report_directory} {
    file mkdir $report_directory
    set stream [open [file join $report_directory feedback_maxdelay_api_preflight.txt] w]
    set failures {}
    puts $stream "mode=READ_ONLY_EXISTING_DESIGN;stage=placed_API_PREFLIGHT"
    foreach {label pointer source_pattern binary_pattern} {
        wr_gray wr_gray_r1_reg wr_gray_reg wr_binary_reg
        rd_gray rd_gray_w1_reg rd_gray_reg rd_binary_reg
    } {
        set destinations [get_pins -quiet -of_objects [get_cells -quiet -hier -filter "NAME =~ *u_event_fifo/$pointer*"] -filter {REF_PIN_NAME == D}]
        if {[llength $destinations] != 6} {error "$label preflight requires six actual D pins"}
        set sources [filter [all_fanin -flat -startpoints_only -only_cells -to $destinations] "NAME =~ *u_event_fifo/$source_pattern* || NAME =~ *u_event_fifo/$binary_pattern*"]
        rx_fb_audit::maxdelay $stream $report_directory $label $sources $destinations 4.882 failures
    }
    set ram [get_cells -quiet -hier -filter {IS_PRIMITIVE == 1 && NAME =~ *u_event_fifo/messages_reg* && (REF_NAME =~ RAMD* || REF_NAME =~ RAMS*)}]
    set clocks [get_pins -quiet -of_objects $ram -filter {REF_PIN_NAME == CLK || REF_PIN_NAME == WCLK}]
    set captures [get_pins -quiet -of_objects [get_cells -quiet -hier -filter {NAME =~ *u_framer/prepared_packet24_reg*}] -filter {REF_PIN_NAME == D}]
    rx_fb_audit::maxdelay $stream $report_directory fwft_data $clocks $captures 48.828 failures
    puts $stream "failure_count=[llength $failures]"
    puts $stream "result=[expr {[llength $failures] ? {FAIL} : {PASS_EFFECTIVE_BUDGET_API}}]"
    close $stream
    if {[llength $failures]} {error "Effective feedback budget/API preflight failed: $failures"}
    puts RX_FEEDBACK_MAXDELAY_API_PREFLIGHT_PASS
}

# Exercise the actual native combinations before the expensive reset guards.
proc rx_preflight_report_exceptions_api {directory} {
    file mkdir $directory
    rx_report_api::export [file join $directory all_valid_exceptions.xdc]
    set pins [get_pins -quiet -of_objects [get_cells -quiet -hier -filter {NAME =~ *u_sample_cdc/reset_pipe_reg* || NAME =~ *u_sample_cdc/read_reset_pipe_reg*}] -filter {REF_PIN_NAME == PRE}]
    if {[llength $pins] != 6} {error "Report API probe requires exact six metadata PRE pins"}
    set selected [rx_report_api::filtered [file join $directory six_PRE_valid.rpt] -to $pins]
    rx_report_api::assert_false_targets $selected $pins
    rx_query_feedback_maxdelay_preroute [file join $directory feedback_budget]
    set stream [open [file join $directory native_api_preflight.txt] w]
    puts $stream "result=PASS_NATIVE_FILTERED_AND_GLOBAL_EXPORT_API\nmetadata_PRE_count=6\nobject_filters_retained=1\nconstraint_budget_checks_retained=1"
    close $stream
    puts RX_REPORT_EXCEPTIONS_NATIVE_API_PREFLIGHT_PASS
}

# Resolve native filtered Position rows to the same global valid machine Tcl.
namespace eval rx_report_api {variable valid_commands; if {![info exists valid_commands]} {set valid_commands {}}}
proc rx_report_api::parse_global {text} {
    set result {}; set position {}; set block {}
    foreach line [split $text \n] {
        if {[regexp {^# position:\s*([0-9]+)\s*$} $line -> next]} {
            if {$position ne {}} {dict set result $position $block}
            set position $next; set block "$line\n"
        } elseif {$position ne {}} {append block "$line\n"}
    }
    if {$position ne {}} {dict set result $position $block}
    if {![dict size $result]} {error "Global valid export has no machine positions"}
    return $result
}
proc rx_report_api::parse_filtered {text} {
    set result {}; set setup_i -1; set hold_i -1; set status_i -1
    foreach line [split $text \n] {
        if {[regexp {^Position\s+From\s+Through\s+To\s+Setup\s+Hold\s+Status} $line]} {
            set setup_i [string first Setup $line]; set hold_i [string first Hold $line]; set status_i [string first Status $line]
        } elseif {$setup_i >= 0 && [regexp {^\s*([0-9]+)\s+} $line -> position]} {
            lappend result [dict create position $position setup [string trim [string range $line $setup_i [expr {$hold_i-1}]]] hold [string trim [string range $line $hold_i [expr {$status_i-1}]]] status [string trim [string range $line $status_i end]]]
        }
    }
    return $result
}
proc rx_report_api::export {path} {
    variable valid_commands
    report_exceptions -write_valid_exceptions -file $path
    set stream [open $path r]; set text [read $stream]; close $stream
    set valid_commands [parse_global $text]
}
proc rx_report_api::filtered {path args} {
    variable valid_commands
    set native [report_exceptions {*}$args -return_string]
    rx_fb_audit::save ${path}.native.rpt $native
    set rows [parse_filtered $native]
    if {![llength $rows]} {error "No actual scoped exception rows: $path"}
    set selected {}; set positions {}
    foreach row $rows {
        set position [dict get $row position]
        if {![dict exists $valid_commands $position]} {error "Scoped position $position absent from current global valid export"}
        if {[dict get $row status] ne {}} {error "Scoped exception has nonempty status: $row"}
        set block [dict get $valid_commands $position]
        if {[regexp -line {^set_false_path\y} $block] && ([string tolower [dict get $row setup]] ne "false" || [string tolower [dict get $row hold]] ne "false")} {error "False-path machine command disagrees with native Setup/Hold columns: $row"}
        if {[lsearch -exact $positions $position] < 0} {append selected "$block\n"; lappend positions $position}
    }
    rx_fb_audit::save $path $selected
    return $selected
}
proc rx_report_api::assert_false_targets {text pins} {
    set actual {}; set expected {}
    if {![regexp -line {^set_false_path\y} $text] || [regexp -line {^\s*-from\s} $text]} {error "Metadata false-path export type/source scope differs"}
    set matches [regexp -all -inline {\[get_pins \{([^\}]+)\}\]} $text]
    foreach {whole names} $matches {foreach name $names {lappend actual $name}}
    foreach pin $pins {lappend expected [get_property NAME $pin]}
    if {[lsort -unique $actual] ne [lsort -unique $expected]} {error "False-path machine target set differs from exact requested pins: actual=$actual expected=$expected"}
}
