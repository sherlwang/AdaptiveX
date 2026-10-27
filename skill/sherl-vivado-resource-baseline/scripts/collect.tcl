# Read an existing Vivado design; never create, reset, launch or save a run.
# Called by baseline.py so every output stays in a fresh evidence directory.
array set opt {-dcp {} -project {} -run impl_1 -out {} -phy {} -audits 0 -cap 200000 -depth 64}
foreach {key value} $argv {
    if {![info exists opt($key)]} {error "Unknown option: $key"}
    set opt($key) $value
}
if {$opt(-out) eq {} || (($opt(-dcp) eq {}) == ($opt(-project) eq {}))} {
    error "Supply -out and exactly one of -dcp or -project"
}
file mkdir $opt(-out)
set status [open [file join $opt(-out) report_status.tsv] w]
puts $status "report\tstatus\tdetail"
proc clean {value} {return [string map [list "\t" " " "\n" " " "\r" " "] $value]}
proc prop {object name} {
    if {[catch {get_property $name $object} value]} {return {}}
    return $value
}
proc report {name command} {
    global status opt
    if {[catch {uplevel 1 $command} message]} {
        puts $status "$name\tERROR\t[clean $message]"
        flush $status
        return 0
    }
    puts $status "$name\tOK\t"
    flush $status
    return 1
}
set meta [open [file join $opt(-out) metadata.tsv] w]
puts $meta "key\tvalue"
puts $meta "tool_version\t[clean [version -short]]"
# This no-path message repeats the entire expanded endpoint list. Preserve
# explicit empty counts below instead; all errors and other warnings remain.
set_msg_config -id {Vivado 12-975} -suppress
puts $meta "suppressed_message\tVivado 12-975 only; empty timing queries are explicitly counted"
set required_ok 1
if {$opt(-project) ne {}} {
    open_project -read_only $opt(-project)
    set run [get_runs -quiet $opt(-run)]
    if {[llength $run] != 1} {error "Expected one existing run: $opt(-run)"}
    puts $meta "run_name\t$opt(-run)"
    foreach key [lsort [list_property $run]] {
        if {[regexp {^(STRATEGY|FLOW|STATUS|SRCSET|CONSTRSET|STEPS\..*\.ARGS\..*)$} $key]} {
            puts $meta "run.$key\t[clean [prop $run $key]]"
        }
    }
    open_run $opt(-run)
} else {
    open_checkpoint $opt(-dcp)
}
puts $meta "design\t[clean [prop [current_design] NAME]]"
puts $meta "part\t[clean [prop [current_design] PART]]"
puts $meta "phy\t$opt(-phy)"
puts $meta "hierarchy_depth_limit\t$opt(-depth)"
puts $meta "path_count_limit\t$opt(-cap)"
close $meta

set clocks [open [file join $opt(-out) clocks.tsv] w]
puts $clocks "clock\tperiod\twaveform\tgenerated"
foreach clock [lsort [get_clocks]] {
    puts $clocks "$clock\t[prop $clock PERIOD]\t[prop $clock WAVEFORM]\t[prop $clock IS_GENERATED]"
}
close $clocks
set o $opt(-out)
foreach {name command} [list \
    utilization [list report_utilization -file $o/utilization.rpt] \
    hierarchy [list report_utilization -hierarchical -hierarchical_depth $opt(-depth) -file $o/hierarchy.rpt] \
    timing_summary [list report_timing_summary -delay_type min_max -report_unconstrained -check_timing_verbose -max_paths 20 -file $o/timing_summary.rpt] \
    check_timing [list check_timing -verbose -file $o/check_timing.rpt] \
    clocks [list report_clocks -file $o/clocks.rpt]] {
    if {![report $name $command]} {set required_ok 0}
}

# Sequential boundaries, plus top-level I/O, partition the PHY path scopes.
set phy_seq {}
set other_seq {}
if {$opt(-phy) ne {}} {
    set matched 0
    foreach cell [get_cells -hier -filter {IS_PRIMITIVE == 0}] {
        if {[prop $cell NAME] eq $opt(-phy)} {incr matched}
    }
    if {$matched != 1} {error "PHY instance must be an exact existing path: $opt(-phy) (matches=$matched)"}
    foreach cell [get_cells -hier -filter {IS_SEQUENTIAL == 1}] {
        if {[string first "$opt(-phy)/" [prop $cell NAME]] == 0} {
            lappend phy_seq $cell
        } else {
            lappend other_seq $cell
        }
    }
    if {![llength $phy_seq]} {error "PHY scope has no sequential cells"}
}
set query [open [file join $o path_scope_summary.tsv] w]
puts $query "scope\tdelay\tworst_slack_ns\tnegative_paths\tunique_endpoints\tcap_reached"
set paths_out [open [file join $o negative_paths.tsv] w]
set fields {SLACK STARTPOINT_PIN ENDPOINT_PIN STARTPOINT_CLOCK ENDPOINT_CLOCK LOGIC_LEVELS DATAPATH_DELAY REQUIREMENT}
puts $paths_out "scope\tdelay\t[join $fields \t]"
set scopes {whole}
if {$opt(-phy) ne {}} {set scopes {whole phy_internal into_phy out_of_phy}}
foreach scope $scopes {
    set bounds {}
    switch $scope {
        phy_internal {set bounds [list -from $phy_seq -to $phy_seq]}
        into_phy {set bounds [list -from [concat $other_seq [get_ports -quiet -filter {DIRECTION == IN || DIRECTION == INOUT}]] -to $phy_seq]}
        out_of_phy {set bounds [list -from $phy_seq -to [concat $other_seq [get_ports -quiet -filter {DIRECTION == OUT || DIRECTION == INOUT}]]]}
    }
    foreach delay {max min} {
        set representative [get_timing_paths {*}$bounds -delay_type $delay -max_paths 30 -nworst 1]
        set negative [get_timing_paths {*}$bounds -delay_type $delay -slack_lesser_than 0 -max_paths $opt(-cap) -nworst 1]
        set ends [dict create]
        foreach path $negative {
            set values [list $scope $delay]
            foreach field $fields {lappend values [clean [prop $path $field]]}
            puts $paths_out [join $values \t]
            dict set ends [prop $path ENDPOINT_PIN] 1
        }
        set slack {}
        foreach path $representative {
            set value [prop $path SLACK]
            if {$slack eq {} || $value < $slack} {set slack $value}
        }
        puts $query "$scope\t$delay\t$slack\t[llength $negative]\t[dict size $ends]\t[expr {[llength $negative] >= $opt(-cap)}]"
        if {[llength $representative]} {
            report "${scope}_${delay}" [list report_timing -of_objects $representative -file $o/${scope}_${delay}_paths.rpt]
        } else {
            set empty [open $o/${scope}_${delay}_paths.rpt w]
            puts $empty "EMPTY: no timed paths returned for scope=$scope delay=$delay. See check_timing.rpt for unconstrained paths."
            close $empty
            puts $status "${scope}_${delay}\tEMPTY\tNo timed paths returned; query completed without an error"
            flush $status
        }
    }
}
close $query
close $paths_out

if {$opt(-audits)} {
    foreach {name command} [list \
        clock_interaction [list report_clock_interaction -file $o/clock_interaction.rpt] \
        cdc [list report_cdc -details -file $o/cdc.rpt] \
        exception_coverage [list report_exceptions -coverage -file $o/exception_coverage.rpt] \
        exception_ignored [list report_exceptions -ignored -file $o/exception_ignored.rpt] \
        bus_skew [list report_bus_skew -file $o/bus_skew.rpt] \
        methodology [list report_methodology -file $o/methodology.rpt] \
        drc [list report_drc -file $o/drc.rpt]] {report $name $command}
}
close $status
close_design
if {$opt(-project) ne {}} {close_project}
if {!$required_ok} {error "Required report failed; inspect report_status.tsv"}
puts "BASELINE_REPORT_COLLECTION_COMPLETE"
exit
