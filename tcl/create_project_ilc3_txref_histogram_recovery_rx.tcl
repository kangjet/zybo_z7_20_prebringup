# ============================================================
# create_project_ilc3_txref_histogram_recovery_rx.tcl
# ILC3 256B packet PHY RX with TX-referenced TH/TT metadata parser
# and event-based recovery latency tracking.
# ============================================================

set PART       "xc7z020clg400-1"
set PROJ_NAME  "ilc3_txref_histogram_recovery_rx"
set PROJ_DIR   "[file normalize {C:/zybo_z7_20_prebringup/build/vivado_ilc3_txref_histogram_recovery_rx}]"
set RTL_DIR    "[file normalize {C:/zybo_z7_20_prebringup/rtl}]"
set XDC_DIR    "[file normalize {C:/zybo_z7_20_prebringup/constraints}]"
set SYMBOL_HOLD_CLKS [expr {[info exists ::env(SYMBOL_HOLD_CLKS)] ? $::env(SYMBOL_HOLD_CLKS) : 85}]
set TAG_INTERVAL_SYMBOLS [expr {[info exists ::env(TAG_INTERVAL_SYMBOLS)] ? $::env(TAG_INTERVAL_SYMBOLS) : 32}]
set TAG_PAIR_COUNT [expr {[info exists ::env(TAG_PAIR_COUNT)] ? $::env(TAG_PAIR_COUNT) : 2}]

create_project $PROJ_NAME $PROJ_DIR -part $PART -force

add_files -norecurse [list \
    $RTL_DIR/top_ilc3_txref_histogram_recovery_rx_board.v \
    $RTL_DIR/ilc3_core/ilc3_rx_core.v \
    $RTL_DIR/uart_tx_simple.v \
]

set_property top top_ilc3_txref_histogram_recovery_rx_board [current_fileset]
set_property generic "SYMBOL_HOLD_CLKS=$SYMBOL_HOLD_CLKS ENABLE_TAG=1 TAG_INTERVAL_SYMBOLS=$TAG_INTERVAL_SYMBOLS TAG_PAIR_COUNT=$TAG_PAIR_COUNT" [current_fileset]

add_files -fileset constrs_1 -norecurse $XDC_DIR/ilc3_accuracy_rx_board.xdc

set_property STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY none [get_runs synth_1]

puts "Project created: $PROJ_DIR/$PROJ_NAME.xpr"
puts "ILC3 TX-ref histogram recovery RX SYMBOL_HOLD_CLKS=$SYMBOL_HOLD_CLKS TAG_INTERVAL_SYMBOLS=$TAG_INTERVAL_SYMBOLS TAG_PAIR_COUNT=$TAG_PAIR_COUNT"
puts "Run: launch_runs impl_1 -to_step write_bitstream -jobs 4"
