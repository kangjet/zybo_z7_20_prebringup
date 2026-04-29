# ============================================================
# create_project_pam4_xadc_rx.tcl - PAM4 XADC RX monitor
# Usage: vivado -mode batch -source create_project_pam4_xadc_rx.tcl
# ============================================================

set PART       "xc7z020clg400-1"
set PROJ_NAME  "pam4_xadc_rx"
set PROJ_DIR   "[file normalize {C:/zybo_z7_20_prebringup/build/vivado_pam4_xadc_rx}]"
set RTL_DIR    "[file normalize {C:/zybo_z7_20_prebringup/rtl}]"
set XDC_DIR    "[file normalize {C:/zybo_z7_20_prebringup/constraints}]"

create_project $PROJ_NAME $PROJ_DIR -part $PART -force

add_files -norecurse [list \
    $RTL_DIR/top_pam4_xadc_rx_board.v \
    $RTL_DIR/uart_tx_simple.v \
]

set_property top top_pam4_xadc_rx_board [current_fileset]

add_files -fileset constrs_1 -norecurse $XDC_DIR/pam4_xadc_rx_board.xdc

set_property STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY none \
    [get_runs synth_1]

puts "Project created: $PROJ_DIR/$PROJ_NAME.xpr"
puts "Run: launch_runs impl_1 -to_step write_bitstream -jobs 4"
