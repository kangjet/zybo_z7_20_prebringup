if {![info exists ::env(SYMBOL_HOLD_CLKS)]} {
    set ::env(SYMBOL_HOLD_CLKS) 125
}
if {![info exists ::env(STROBE_OFFSET_CLKS)]} {
    set ::env(STROBE_OFFSET_CLKS) 100
}
if {![info exists ::env(STROBE_PULSE_CLKS)]} {
    set ::env(STROBE_PULSE_CLKS) 4
}

puts "PAM4 accuracy TX build defaults: SYMBOL_HOLD_CLKS=$::env(SYMBOL_HOLD_CLKS) STROBE_OFFSET_CLKS=$::env(STROBE_OFFSET_CLKS) STROBE_PULSE_CLKS=$::env(STROBE_PULSE_CLKS)"

source {C:/zybo_z7_20_prebringup/tcl/create_project_pam4_accuracy_tx.tcl}
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
set bitfile [glob -nocomplain {C:/zybo_z7_20_prebringup/build/vivado_pam4_accuracy_tx/pam4_accuracy_tx.runs/impl_1/*.bit}]
puts "BITFILE=$bitfile"
