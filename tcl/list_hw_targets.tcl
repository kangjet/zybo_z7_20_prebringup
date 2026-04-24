# list_hw_targets.tcl — enumerate all connected JTAG targets
open_hw_manager
connect_hw_server -allow_non_jtag

set targets [get_hw_targets]
puts "=== Connected HW Targets ==="
foreach t $targets {
    puts "  TARGET: $t"
    open_hw_target $t
    foreach d [get_hw_devices] {
        puts "    DEVICE: $d  ([get_property PART $d])"
    }
    close_hw_target $t
}
puts "==========================="
close_hw_manager
