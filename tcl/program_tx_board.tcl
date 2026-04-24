# ============================================================
# program_tx_board.tcl — TX Board JTAG programming
# Target: Digilent/210351BE5C62A  (COM8 JTAG — verify in Device Manager)
# Bitstream: top_ilc3_tx_board.bit
# Usage: vivado -mode batch -source program_tx_board.tcl
# ============================================================

set BIT_FILE [file normalize {C:/zybo_z7_20_prebringup/build/vivado_tx/ilc3_tx_board.runs/impl_1/top_ilc3_tx_board.bit}]
set TARGET   {localhost:3121/xilinx_tcf/Digilent/210351BE5C62A}

open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target $TARGET

set dev [lindex [get_hw_devices xc7z020_*] 0]
current_hw_device $dev
refresh_hw_device $dev

set_property PROGRAM.FILE $BIT_FILE $dev
program_hw_devices $dev
refresh_hw_device $dev

puts "TX Board programmed OK: $BIT_FILE"
close_hw_manager
