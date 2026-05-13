if {![info exists ::env(SYMBOL_HOLD_CLKS)]} {
    set ::env(SYMBOL_HOLD_CLKS) 125
}

puts "PAM4 accuracy RX build defaults: SYMBOL_HOLD_CLKS=$::env(SYMBOL_HOLD_CLKS)"

source {C:/zybo_z7_20_prebringup/tcl/create_project_pam4_accuracy_rx.tcl}
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
set bitfile [glob -nocomplain {C:/zybo_z7_20_prebringup/build/vivado_pam4_accuracy_rx/pam4_accuracy_rx.runs/impl_1/*.bit}]
puts "BITFILE=$bitfile"
