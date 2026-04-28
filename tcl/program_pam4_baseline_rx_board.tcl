# ============================================================
# program_pam4_baseline_rx_board.tcl - PAM4 RX JTAG programming
# Target: Digilent/210351BE5D1FA
# ============================================================

set BIT_FILE [file normalize {C:/zybo_z7_20_prebringup/build/vivado_pam4_rx/pam4_baseline_rx.runs/impl_1/top_pam4_baseline_rx_board.bit}]
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

puts "PAM4 baseline RX Board programmed OK: $BIT_FILE"
close_hw_manager
