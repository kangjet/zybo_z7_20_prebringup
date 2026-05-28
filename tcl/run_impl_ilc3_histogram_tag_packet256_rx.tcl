open_project C:/zybo_z7_20_prebringup/build/vivado_ilc3_histogram_tag_packet256_rx/ilc3_histogram_tag_packet256_rx.xpr
reset_run synth_1
reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
set status [get_property STATUS [get_runs impl_1]]
puts "impl_1 status: $status"
if {![string match "*Complete*" $status]} {
    exit 1
}
exit 0
