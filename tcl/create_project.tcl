set script_dir [file normalize [file dirname [info script]]]
set root_dir   [file normalize [file join $script_dir ..]]
set build_dir  [file normalize [file join $root_dir build vivado]]
set proj_name  ilc3_zybo_z7_20_prebringup
set part_name  xc7z020clg400-1

file mkdir $build_dir
create_project $proj_name $build_dir -part $part_name -force

set rtl_dir [file join $root_dir rtl]
set core_dir [file join $rtl_dir ilc3_core]

add_files -norecurse [file join $rtl_dir top_zybo_ilc3_prebringup.v]
add_files -norecurse [file join $rtl_dir uart_tx_simple.v]
add_files -norecurse [file join $rtl_dir uart_rx_simple.v]
add_files -norecurse [file join $rtl_dir uart_cmd_frame.v]
add_files -norecurse [file join $core_dir ilc3_tx_core.v]
add_files -norecurse [file join $core_dir ilc3_rx_core.v]
add_files -norecurse [file join $core_dir ilc3_ipcore_top.v]

set xdc_file [file join $root_dir constraints zybo_z7_20_template.xdc]
if {[file exists $xdc_file]} {
  add_files -fileset constrs_1 -norecurse $xdc_file
}

set_property top top_zybo_ilc3_prebringup [current_fileset]
update_compile_order -fileset sources_1

