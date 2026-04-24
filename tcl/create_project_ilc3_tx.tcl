# ============================================================
# create_project_ilc3_tx.tcl — ILC3 TX Board Vivado project
# Usage: vivado -mode batch -source create_project_ilc3_tx.tcl
# Or:    Vivado Tcl Console > source {path}/create_project_ilc3_tx.tcl
# ============================================================

set PART       "xc7z020clg400-1"
set PROJ_NAME  "ilc3_tx_board"
set PROJ_DIR   "[file normalize {C:/zybo_z7_20_prebringup/build/vivado_tx}]"
set RTL_DIR    "[file normalize {C:/zybo_z7_20_prebringup/rtl}]"
set XDC_DIR    "[file normalize {C:/zybo_z7_20_prebringup/constraints}]"

# Create project
create_project $PROJ_NAME $PROJ_DIR -part $PART -force

# Add RTL sources
add_files -norecurse [list \
    $RTL_DIR/top_ilc3_tx_board.v \
    $RTL_DIR/ilc3_core/ilc3_tx_core.v \
    $RTL_DIR/uart_tx_simple.v \
]

# Set top module
set_property top top_ilc3_tx_board [current_fileset]

# Add XDC constraint
add_files -fileset constrs_1 -norecurse $XDC_DIR/ilc3_tx_board.xdc

# Synthesis & implementation settings
set_property STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY none \
    [get_runs synth_1]

puts "Project created: $PROJ_DIR/$PROJ_NAME.xpr"
puts "Run: launch_runs impl_1 -to_step write_bitstream -jobs 4"
