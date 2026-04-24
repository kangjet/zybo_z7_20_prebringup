open_project {C:/zybo_z7_20_prebringup/build/vivado_tx/ilc3_tx_board.xpr}
reset_run synth_1
reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

set bitfile [glob -nocomplain {C:/zybo_z7_20_prebringup/build/vivado_tx/ilc3_tx_board.runs/impl_1/*.bit}]
if {[llength $bitfile] == 0} {
    puts stderr "TX bitstream was not generated."
    exit 1
}

puts "TX bitstream: [lindex $bitfile 0]"
