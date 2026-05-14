open_project C:/zybo_z7_20_prebringup/build/vivado_ilc3_packet256_rx/ilc3_packet256_rx.xpr
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
set status [get_property STATUS [get_runs synth_1]]
puts "synth_1 status: $status"
if {![string match "*Complete*" $status]} {
    exit 1
}
exit 0
