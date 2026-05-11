source {C:/zybo_z7_20_prebringup/tcl/create_project_ilc3_analog_compare_rx.tcl}
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
set bitfile [glob -nocomplain {C:/zybo_z7_20_prebringup/build/vivado_ilc3_analog_compare_rx/ilc3_analog_compare_rx.runs/impl_1/*.bit}]
puts "BITFILE=$bitfile"
