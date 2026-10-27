# Build the supplied board initialization with Vitis 2021.2.
# Usage: xsct -nodisp build_app.tcl tx|rx hardware.xsa new_workspace
# The collected C/H/LD files are copied into a newly created workspace.
# No target connection, programming or register access is performed here.

proc usage {} {
    puts stderr "Usage: xsct -nodisp build_app.tcl tx|rx hardware.xsa new_workspace"
    exit 2
}

if {$argc != 3} { usage }
set role [string tolower [lindex $argv 0]]
if {$role ni {tx rx}} { usage }
set xsa [file normalize [lindex $argv 1]]
set workspace [file normalize [lindex $argv 2]]
set script_dir [file dirname [file normalize [info script]]]
set source_dir [file join $script_dir $role]
if {![file isfile $xsa]} { error "Hardware handoff does not exist: $xsa" }
if {![file isfile [file join $source_dir main.c]]} { error "Missing original application: $source_dir" }
if {[file exists $workspace] && (![file isdirectory $workspace] ||
    [llength [glob -nocomplain -directory $workspace *]] > 0 ||
    [file exists [file join $workspace .metadata]])} {
    error "Choose an empty/new workspace; refusing to overwrite: $workspace"
}
file mkdir $workspace

if {[catch {
    set tool_version [version]
    if {![string match *2021.2* $tool_version]} {
        error "This recipe is validated for Vitis 2021.2; current tool: $tool_version"
    }
    puts "SOFTWARE_BUILD role=$role"
    puts "SOFTWARE_BUILD xsa=$xsa"
    puts "SOFTWARE_BUILD sources=$source_dir"
    puts "SOFTWARE_BUILD workspace=$workspace"
    puts "SOFTWARE_BUILD tool=$tool_version"
    setws $workspace
    set platform_name "rf_${role}_platform"
    set app_name "rf_${role}_init"
    platform create -name $platform_name -hw $xsa -proc psu_cortexa53_0 -arch 64-bit -os standalone -no-boot-bsp
    platform active $platform_name
    set domain_name [domain active]
    if {$domain_name eq ""} { error "No standalone domain was created" }
    bsp setlib -name libmetal
    platform write
    platform generate

    app create -name $app_name -platform $platform_name -domain $domain_name -template {Empty Application(C)} -lang c
    importsources -name $app_name -path $source_dir -linker-script
    set app_source_dir [file join $workspace $app_name src]
    foreach include_dir [list $app_source_dir [file join $app_source_dir devices] [file join $app_source_dir rfsoc]] {
        app config -name $app_name -add include-path $include_dir
    }
    app config -name $app_name -add define-compiler-symbols __BAREMETAL__
    if {$role eq "tx"} {set role_profile 0} else {set role_profile 1}
    app config -name $app_name -add define-compiler-symbols RFDC_PROFILE=$role_profile
    app config -name $app_name -set compiler-optimization {None (-O0)}
    app config -name $app_name -add libraries m
    app config -name $app_name -add libraries metal
    app config -name $app_name -set linker-script [file join $app_source_dir lscript.ld]
    app build -name $app_name

    set elf [file join $workspace $app_name Debug "${app_name}.elf"]
    if {![file isfile $elf]} { error "Application build did not produce expected ELF: $elf" }
    set artifact_dir [file join $workspace artifacts]
    file mkdir $artifact_dir
    set exported_elf [file join $artifact_dir "${role}_init.elf"]
    file copy -force $elf $exported_elf
    set result [open [file join $artifact_dir build_result.txt] w]
    puts $result "status=application_build_pass"
    puts $result "role=$role"
    puts $result "tool=$tool_version"
    puts $result "xsa=$xsa"
    puts $result "processor=psu_cortexa53_0"
    puts $result "os=standalone"
    puts $result "arch=64-bit"
    puts $result "domain=$domain_name"
    puts $result "platform=$platform_name"
    puts $result "application=$app_name"
    puts $result "source_dir=$source_dir"
    puts $result "elf=$exported_elf"
    puts $result "board_execution=not_performed"
    close $result
    puts "SOFTWARE_BUILD_PASS elf=$exported_elf"
} message options]} {
    puts stderr "SOFTWARE_BUILD_FAIL: $message"
    if {[dict exists $options -errorinfo]} { puts stderr [dict get $options -errorinfo] }
    exit 1
}
exit 0
