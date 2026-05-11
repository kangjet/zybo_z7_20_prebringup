# ============================================================
# create_project_ilc3_analog_compare_rx.tcl
# ILC3 RX monitor matched to PAM4 LMV339 comparator wiring
# ============================================================

set PART       "xc7z020clg400-1"
set PROJ_NAME  "ilc3_analog_compare_rx"
set PROJ_DIR   "[file normalize {C:/zybo_z7_20_prebringup/build/vivado_ilc3_analog_compare_rx}]"
set RTL_DIR    "[file normalize {C:/zybo_z7_20_prebringup/rtl}]"
set XDC_DIR    "[file normalize {C:/zybo_z7_20_prebringup/constraints}]"

create_project $PROJ_NAME $PROJ_DIR -part $PART -force

add_files -norecurse [list \
    $RTL_DIR/top_ilc3_analog_compare_rx_board.v \
    $RTL_DIR/uart_tx_simple.v \
]

set_property top top_ilc3_analog_compare_rx_board [current_fileset]

add_files -fileset constrs_1 -norecurse $XDC_DIR/ilc3_analog_compare_rx_board.xdc

set_property STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY none [get_runs synth_1]

puts "Project created: $PROJ_DIR/$PROJ_NAME.xpr"
puts "Run: launch_runs impl_1 -to_step write_bitstream -jobs 4"
