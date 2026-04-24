# ============================================================
# create_project_ilc3_rx.tcl — ILC3 RX Board Vivado project
# Usage: vivado -mode batch -source create_project_ilc3_rx.tcl
# Or:    Vivado Tcl Console > source {path}/create_project_ilc3_rx.tcl
# ============================================================

set PART       "xc7z020clg400-1"
set PROJ_NAME  "ilc3_rx_board"
set PROJ_DIR   "[file normalize {C:/zybo_z7_20_prebringup/build/vivado_rx}]"
set RTL_DIR    "[file normalize {C:/zybo_z7_20_prebringup/rtl}]"
set XDC_DIR    "[file normalize {C:/zybo_z7_20_prebringup/constraints}]"
set VALID_DELAY [expr {[info exists ::env(VALID_DELAY)] ? $::env(VALID_DELAY) : 2}]
set FRAME_DELAY [expr {[info exists ::env(FRAME_DELAY)] ? $::env(FRAME_DELAY) : 2}]

# Create project
create_project $PROJ_NAME $PROJ_DIR -part $PART -force

# Add RTL sources
add_files -norecurse [list \
    $RTL_DIR/top_ilc3_rx_board.v \
    $RTL_DIR/ilc3_core/ilc3_rx_core.v \
    $RTL_DIR/uart_tx_simple.v \
]

# Set top module
set_property top top_ilc3_rx_board [current_fileset]
set_property generic "VALID_DELAY=$VALID_DELAY FRAME_DELAY=$FRAME_DELAY" [current_fileset]

# Add XDC constraint
add_files -fileset constrs_1 -norecurse $XDC_DIR/ilc3_rx_board.xdc

# Synthesis settings
set_property STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY none \
    [get_runs synth_1]

puts "Project created: $PROJ_DIR/$PROJ_NAME.xpr"
puts "RX delay taps: VALID_DELAY=$VALID_DELAY FRAME_DELAY=$FRAME_DELAY"
puts "Run: launch_runs impl_1 -to_step write_bitstream -jobs 4"
