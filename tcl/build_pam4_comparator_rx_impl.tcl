open_project C:/zybo_z7_20_prebringup/build/vivado_pam4_comparator_rx/pam4_comparator_rx.xpr
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

set bitfile [glob -nocomplain {C:/zybo_z7_20_prebringup/build/vivado_pam4_comparator_rx/pam4_comparator_rx.runs/impl_1/*.bit}]
if {[llength $bitfile] == 0} {
    puts stderr "PAM4 comparator RX bitstream was not generated."
    exit 1
}

puts "PAM4 comparator RX bitstream: [lindex $bitfile 0]"
