# ============================================================
# create_project_pam4_packet256_tx.tcl
# PAM4 256B packet PHY TX over analog accuracy path
# ============================================================

set PART       "xc7z020clg400-1"
set PROJ_NAME  "pam4_packet256_tx"
set PROJ_DIR   "[file normalize {C:/zybo_z7_20_prebringup/build/vivado_pam4_packet256_tx}]"
set RTL_DIR    "[file normalize {C:/zybo_z7_20_prebringup/rtl}]"
set XDC_DIR    "[file normalize {C:/zybo_z7_20_prebringup/constraints}]"
set SYMBOL_HOLD_CLKS [expr {[info exists ::env(SYMBOL_HOLD_CLKS)] ? $::env(SYMBOL_HOLD_CLKS) : 125}]
set STROBE_OFFSET_CLKS [expr {[info exists ::env(STROBE_OFFSET_CLKS)] ? $::env(STROBE_OFFSET_CLKS) : 100}]
set STROBE_PULSE_CLKS [expr {[info exists ::env(STROBE_PULSE_CLKS)] ? $::env(STROBE_PULSE_CLKS) : 4}]

create_project $PROJ_NAME $PROJ_DIR -part $PART -force

add_files -norecurse [list \
    $RTL_DIR/top_pam4_packet256_tx_board.v \
    $RTL_DIR/uart_tx_simple.v \
]

set_property top top_pam4_packet256_tx_board [current_fileset]
set_property generic "SYMBOL_HOLD_CLKS=$SYMBOL_HOLD_CLKS STROBE_OFFSET_CLKS=$STROBE_OFFSET_CLKS STROBE_PULSE_CLKS=$STROBE_PULSE_CLKS" [current_fileset]

add_files -fileset constrs_1 -norecurse $XDC_DIR/pam4_accuracy_tx_board.xdc

set_property STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY none [get_runs synth_1]

puts "Project created: $PROJ_DIR/$PROJ_NAME.xpr"
puts "PAM4 packet256 TX SYMBOL_HOLD_CLKS=$SYMBOL_HOLD_CLKS STROBE_OFFSET_CLKS=$STROBE_OFFSET_CLKS STROBE_PULSE_CLKS=$STROBE_PULSE_CLKS"
puts "Run: launch_runs impl_1 -to_step write_bitstream -jobs 4"
