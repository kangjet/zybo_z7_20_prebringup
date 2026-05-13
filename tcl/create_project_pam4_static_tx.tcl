# ============================================================
# create_project_pam4_static_tx.tcl
# PAM4 static-code TX for analog/noise-path debug
# ============================================================

set PART       "xc7z020clg400-1"
set PROJ_NAME  "pam4_static_tx"
set PROJ_DIR   "[file normalize {C:/zybo_z7_20_prebringup/build/vivado_pam4_static_tx}]"
set RTL_DIR    "[file normalize {C:/zybo_z7_20_prebringup/rtl}]"
set XDC_DIR    "[file normalize {C:/zybo_z7_20_prebringup/constraints}]"

set STATIC_CODE [expr {[info exists ::env(STATIC_CODE)] ? $::env(STATIC_CODE) : 0}]

create_project $PROJ_NAME $PROJ_DIR -part $PART -force

add_files -norecurse [list \
    $RTL_DIR/top_pam4_static_tx_board.v \
]

set_property top top_pam4_static_tx_board [current_fileset]
set_property generic "STATIC_CODE=$STATIC_CODE" [current_fileset]

# Reuse the accuracy TX pinout. The static TX top has the same board-level ports.
add_files -fileset constrs_1 -norecurse $XDC_DIR/pam4_accuracy_tx_board.xdc

set_property STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY none [get_runs synth_1]

puts "Project created: $PROJ_DIR/$PROJ_NAME.xpr"
puts "PAM4 static TX STATIC_CODE=$STATIC_CODE"
puts "Run: launch_runs impl_1 -to_step write_bitstream -jobs 4"
