# ============================================================
# create_project_ilc3_analog_compare_tx.tcl
# ILC3 TX adapted to PAM4 analog comparison resistor-DAC
# ============================================================

set PART       "xc7z020clg400-1"
set PROJ_NAME  "ilc3_analog_compare_tx"
set PROJ_DIR   "[file normalize {C:/zybo_z7_20_prebringup/build/vivado_ilc3_analog_compare_tx}]"
set RTL_DIR    "[file normalize {C:/zybo_z7_20_prebringup/rtl}]"
set XDC_DIR    "[file normalize {C:/zybo_z7_20_prebringup/constraints}]"
set SYMBOL_HOLD_CLKS [expr {[info exists ::env(SYMBOL_HOLD_CLKS)] ? $::env(SYMBOL_HOLD_CLKS) : 125}]

create_project $PROJ_NAME $PROJ_DIR -part $PART -force

add_files -norecurse [list \
    $RTL_DIR/top_ilc3_analog_compare_tx_board.v \
    $RTL_DIR/uart_tx_simple.v \
]

set_property top top_ilc3_analog_compare_tx_board [current_fileset]
set_property generic "SYMBOL_HOLD_CLKS=$SYMBOL_HOLD_CLKS" [current_fileset]

add_files -fileset constrs_1 -norecurse $XDC_DIR/ilc3_analog_compare_tx_board.xdc

set_property STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY none [get_runs synth_1]

puts "Project created: $PROJ_DIR/$PROJ_NAME.xpr"
puts "ILC3 analog compare TX SYMBOL_HOLD_CLKS=$SYMBOL_HOLD_CLKS"
puts "Run: launch_runs impl_1 -to_step write_bitstream -jobs 4"
