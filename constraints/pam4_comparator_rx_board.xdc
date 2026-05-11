## ============================================================
## pam4_comparator_rx_board.xdc - LMV339 comparator PAM4 RX monitor
## Target: Zybo Z7-20 (xc7z020clg400-1)
## ============================================================

## Clock (125 MHz onboard)
set_property PACKAGE_PIN K17 [get_ports sys_clk]
set_property IOSTANDARD LVCMOS33 [get_ports sys_clk]
create_clock -period 8.000 -name sys_clk [get_ports sys_clk]

## Reset button (BTN0, active-high press resets design)
set_property PACKAGE_PIN K18 [get_ports rst_btn_n]
set_property IOSTANDARD LVCMOS33 [get_ports rst_btn_n]

## PMOD JD inputs from LMV339 comparator outputs
## JD1 = OUT0/TH0, JD2 = OUT1/TH1, JD3 = OUT2/TH2
set_property PACKAGE_PIN T14 [get_ports {cmp_in[0]}]
set_property PACKAGE_PIN T15 [get_ports {cmp_in[1]}]
set_property PACKAGE_PIN P14 [get_ports {cmp_in[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {cmp_in[*]}]

## UART TX (PMOD JE1, Bank 34, V12)
set_property PACKAGE_PIN V12 [get_ports uart_tx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_tx]

## LEDs
set_property PACKAGE_PIN M14 [get_ports {led[0]}]
set_property PACKAGE_PIN M15 [get_ports {led[1]}]
set_property PACKAGE_PIN G14 [get_ports {led[2]}]
set_property PACKAGE_PIN D18 [get_ports {led[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[*]}]

set_false_path -from [get_ports {cmp_in[*]}]
