set script_dir [file normalize [file dirname [info script]]]
set root_dir   [file normalize [file join $script_dir ..]]
set rpt_dir    [file normalize [file join $root_dir build reports]]

source [file join $script_dir create_project.tcl]
file mkdir $rpt_dir

launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
open_run impl_1

report_utilization -file [file join $rpt_dir impl_utilization.rpt]
report_timing_summary -max_paths 20 -file [file join $rpt_dir impl_timing_summary.rpt]
report_route_status -file [file join $rpt_dir impl_route_status.rpt]

set bitfile [glob -nocomplain [file join $root_dir build vivado ilc3_zybo_z7_20_prebringup.runs impl_1 *.bit]]
puts {[OK] impl completed}
puts {[OK] bitstream: }
puts $bitfile
puts {[OK] reports: }
puts $rpt_dir
