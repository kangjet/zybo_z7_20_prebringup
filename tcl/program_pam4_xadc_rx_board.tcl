set TARGET {localhost:3121/xilinx_tcf/Digilent/210351BE5D1FA}

open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target $TARGET

set devs [get_hw_devices xc7z020_*]
if {[llength $devs] == 0} {
    puts stderr "No xc7z020 hardware device found."
    exit 1
}

set dev [lindex $devs 0]
current_hw_device $dev
refresh_hw_device $dev

set bitfile [glob -nocomplain {C:/zybo_z7_20_prebringup/build/vivado_pam4_xadc_rx/pam4_xadc_rx.runs/impl_1/*.bit}]
if {[llength $bitfile] == 0} {
    puts stderr "PAM4 XADC RX bitstream was not found."
    exit 1
}

set_property PROGRAM.FILE [lindex $bitfile 0] $dev
program_hw_devices $dev
refresh_hw_device $dev

puts "Programmed PAM4 XADC RX board with [lindex $bitfile 0]"
close_hw_manager
