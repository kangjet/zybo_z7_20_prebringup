## ============================================================
## ilc3_analog_compare_rx_board.xdc
## RX monitor matched to PAM4 LMV339 comparator wiring
## ============================================================

set_property PACKAGE_PIN K17 [get_ports sys_clk]
set_property IOSTANDARD LVCMOS33 [get_ports sys_clk]
create_clock -period 8.000 -name sys_clk [get_ports sys_clk]

set_property PACKAGE_PIN K18 [get_ports rst_btn_n]
set_property IOSTANDARD LVCMOS33 [get_ports rst_btn_n]

## Same LMV339 input pins as PAM4 comparator RX.
## cmp_in[0] = TH0
## cmp_in[1] = TH1
## cmp_in[2] = TH2
set_property PACKAGE_PIN T14 [get_ports {cmp_in[0]}]
set_property PACKAGE_PIN T15 [get_ports {cmp_in[1]}]
set_property PACKAGE_PIN P14 [get_ports {cmp_in[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {cmp_in[*]}]

## Optional frame sync from comparison TX pam4_sync.
## Connect TX JD8/U15 to RX JD8/U15 when using expected-sequence QN.
set_property PACKAGE_PIN U15 [get_ports sync_in]
set_property IOSTANDARD LVCMOS33 [get_ports sync_in]

set_property PACKAGE_PIN V12 [get_ports uart_tx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_tx]

set_property PACKAGE_PIN M14 [get_ports {led[0]}]
set_property PACKAGE_PIN M15 [get_ports {led[1]}]
set_property PACKAGE_PIN G14 [get_ports {led[2]}]
set_property PACKAGE_PIN D18 [get_ports {led[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[*]}]

set_false_path -from [get_ports {cmp_in[*]}]
set_false_path -from [get_ports sync_in]
