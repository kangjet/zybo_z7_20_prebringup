set script_dir [file normalize [file dirname [info script]]]
set root_dir   [file normalize [file join $script_dir ..]]
set rpt_dir    [file normalize [file join $root_dir build reports]]

source [file join $script_dir create_project.tcl]
file mkdir $rpt_dir

launch_runs synth_1 -jobs 4
wait_on_run synth_1
open_run synth_1

report_utilization -file [file join $rpt_dir synth_utilization.rpt]
report_timing_summary -max_paths 20 -file [file join $rpt_dir synth_timing_summary.rpt]
report_power -file [file join $rpt_dir synth_power.rpt]

puts {[OK] synth completed}
puts "[OK] reports: $rpt_dir"
