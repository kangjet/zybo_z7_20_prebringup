source {C:/zybo_z7_20_prebringup/tcl/create_project_pam4_accuracy_tx.tcl}
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
set bitfile [glob -nocomplain {C:/zybo_z7_20_prebringup/build/vivado_pam4_accuracy_tx/pam4_accuracy_tx.runs/impl_1/*.bit}]
puts "BITFILE=$bitfile"
