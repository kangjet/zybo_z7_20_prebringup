## ============================================================
## pam4_xadc_rx_board.xdc - RX-side XADC monitor
## Target: Zybo Z7-20 (xc7z020clg400-1)
## JA XADC channel: AD14P/AD14N via JA1/JA7
## ============================================================

## Clock (125 MHz onboard)
set_property PACKAGE_PIN K17 [get_ports sys_clk]
set_property IOSTANDARD LVCMOS33 [get_ports sys_clk]
create_clock -period 8.000 -name sys_clk [get_ports sys_clk]

## Reset button (BTN0, active-high press resets design)
set_property PACKAGE_PIN K18 [get_ports rst_btn_n]
set_property IOSTANDARD LVCMOS33 [get_ports rst_btn_n]

## UART TX (PMOD JE1, Bank 34, V12)
set_property PACKAGE_PIN V12 [get_ports uart_tx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_tx]

## LEDs
set_property PACKAGE_PIN M14 [get_ports {led[0]}]
set_property PACKAGE_PIN M15 [get_ports {led[1]}]
set_property PACKAGE_PIN G14 [get_ports {led[2]}]
set_property PACKAGE_PIN D18 [get_ports {led[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[*]}]

## XADC VAUX14 on Zybo Z7 JA connector
## JA1 = AD14P, JA7 = AD14N.
set_property PACKAGE_PIN N15 [get_ports vauxp14]
set_property PACKAGE_PIN N16 [get_ports vauxn14]
set_property IOSTANDARD LVCMOS33 [get_ports vauxp14]
set_property IOSTANDARD LVCMOS33 [get_ports vauxn14]
