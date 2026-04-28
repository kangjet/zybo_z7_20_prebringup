## ============================================================
## pam4_baseline_tx_board.xdc - TX-only PAM4 baseline generator
## Target: Zybo Z7-20 (xc7z020clg400-1)
## ============================================================

## Clock (125 MHz onboard)
set_property PACKAGE_PIN K17 [get_ports sys_clk]
set_property IOSTANDARD LVCMOS33 [get_ports sys_clk]
create_clock -period 8.000 -name sys_clk [get_ports sys_clk]

## Reset button (BTN0, active-high press resets design)
set_property PACKAGE_PIN K18 [get_ports rst_btn_n]
set_property IOSTANDARD LVCMOS33 [get_ports rst_btn_n]

## PMOD JD outputs
## JD1/T14 = pam4_code[0] LSB
## JD2/T15 = pam4_code[1] MSB
## JD7/U14 = valid
## JD8/U15 = sync pulse at code 00
set_property PACKAGE_PIN T14 [get_ports {pam4_code[0]}]
set_property PACKAGE_PIN T15 [get_ports {pam4_code[1]}]
set_property PACKAGE_PIN U14 [get_ports pam4_valid]
set_property PACKAGE_PIN U15 [get_ports pam4_sync]
set_property IOSTANDARD LVCMOS33 [get_ports {pam4_code[*]}]
set_property IOSTANDARD LVCMOS33 [get_ports pam4_valid]
set_property IOSTANDARD LVCMOS33 [get_ports pam4_sync]

## UART TX (PMOD JE1, Bank 34, V12)
set_property PACKAGE_PIN V12 [get_ports uart_tx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_tx]

## LEDs
set_property PACKAGE_PIN M14 [get_ports {led[0]}]
set_property PACKAGE_PIN M15 [get_ports {led[1]}]
set_property PACKAGE_PIN G14 [get_ports {led[2]}]
set_property PACKAGE_PIN D18 [get_ports {led[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[*]}]
