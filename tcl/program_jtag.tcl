set bit_file "C:/zybo_z7_20_prebringup/build/vivado/ilc3_zybo_z7_20_prebringup.runs/impl_1/top_zybo_ilc3_prebringup.bit"

open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target

set device [lindex [get_hw_devices xc7z*] 0]
if {$device eq ""} {
    set device [lindex [get_hw_devices] 1]
}
current_hw_device $device
refresh_hw_device $device

set_property PROGRAM.FILE $bit_file $device
program_hw_devices $device
refresh_hw_device $device

puts "\[OK\] JTAG programming done: $bit_file"
close_hw_manager
