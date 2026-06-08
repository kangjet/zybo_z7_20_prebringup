## ============================================================
## ilc3_accuracy_tx_board.xdc
## TX for ILC3 PAM4-comparison accuracy test
## ============================================================

set_property PACKAGE_PIN K17 [get_ports sys_clk]
set_property IOSTANDARD LVCMOS33 [get_ports sys_clk]
create_clock -period 8.000 -name sys_clk [get_ports sys_clk]

set_property PACKAGE_PIN K18 [get_ports rst_btn_n]
set_property IOSTANDARD LVCMOS33 [get_ports rst_btn_n]

## Resistor-DAC path and timing strobes.
## JD1/T14 = pam4_code[0] LSB
## JD2/T15 = pam4_code[1] MSB
## JD7/U14 = sample strobe, one sys_clk pulse per sample
## JD8/U15 = frame sync, one sys_clk pulse at frame start
set_property PACKAGE_PIN T14 [get_ports {pam4_code[0]}]
set_property PACKAGE_PIN T15 [get_ports {pam4_code[1]}]
set_property PACKAGE_PIN U14 [get_ports pam4_valid]
set_property PACKAGE_PIN U15 [get_ports pam4_sync]
set_property IOSTANDARD LVCMOS33 [get_ports {pam4_code[*]}]
set_property IOSTANDARD LVCMOS33 [get_ports pam4_valid]
set_property IOSTANDARD LVCMOS33 [get_ports pam4_sync]

## PMOD JC control from RX and ACK back to RX.
## RX JC1/V15 -> TX JC1/V15 = rtx_req_in
## RX JC2/W15 -> TX JC2/W15 = rtx_seq_in
## TX JC3/W14 -> RX JC3/W14 = rtx_ack_out
set_property PACKAGE_PIN V15 [get_ports rtx_req_in]
set_property PACKAGE_PIN W15 [get_ports rtx_seq_in]
set_property PACKAGE_PIN W14 [get_ports rtx_ack_out]
set_property IOSTANDARD LVCMOS33 [get_ports rtx_req_in]
set_property IOSTANDARD LVCMOS33 [get_ports rtx_seq_in]
set_property IOSTANDARD LVCMOS33 [get_ports rtx_ack_out]

set_property PACKAGE_PIN V12 [get_ports uart_tx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_tx]

set_property PACKAGE_PIN M14 [get_ports {led[0]}]
set_property PACKAGE_PIN M15 [get_ports {led[1]}]
set_property PACKAGE_PIN G14 [get_ports {led[2]}]
set_property PACKAGE_PIN D18 [get_ports {led[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[*]}]

set_false_path -from [get_ports rtx_req_in]
set_false_path -from [get_ports rtx_seq_in]
