# ============================================================
# program_ilc3_txref_histogram_recovery_rx_board.tcl
# Target: RX board JTAG
# ============================================================

set BIT_FILE [file normalize {C:/zybo_z7_20_prebringup/build/vivado_ilc3_txref_histogram_recovery_rx/ilc3_txref_histogram_recovery_rx.runs/impl_1/top_ilc3_txref_histogram_recovery_rx_board.bit}]
set TARGET   {localhost:3121/xilinx_tcf/Digilent/210351BE5D1FA}

open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target $TARGET

set dev [lindex [get_hw_devices xc7z020_*] 0]
current_hw_device $dev
refresh_hw_device $dev

set_property PROGRAM.FILE $BIT_FILE $dev
program_hw_devices $dev
refresh_hw_device $dev

puts "ILC3 TX-ref histogram recovery RX programmed OK: $BIT_FILE"
close_hw_manager
