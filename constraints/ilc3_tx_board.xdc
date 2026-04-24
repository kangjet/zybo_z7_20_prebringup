## ============================================================
## ilc3_tx_board.xdc — TX Board (Board 1: COM3 UART / COM8 JTAG)
## Target: Zybo Z7-20 (xc7z020clg400-1)
## ============================================================

## Clock (125 MHz onboard)
set_property PACKAGE_PIN K17 [get_ports sys_clk]
set_property IOSTANDARD LVCMOS33 [get_ports sys_clk]
create_clock -period 8.000 -name sys_clk [get_ports sys_clk]

## Reset button (BTN0, active-low)
set_property PACKAGE_PIN K18 [get_ports rst_btn_n]
set_property IOSTANDARD LVCMOS33 [get_ports rst_btn_n]

## ── PMOD JD (Bank 34, LVCMOS33) — Amplitude output → RX board ──
set_property PACKAGE_PIN T14 [get_ports {ilc3_amp[0]}]
set_property PACKAGE_PIN T15 [get_ports {ilc3_amp[1]}]
set_property PACKAGE_PIN P14 [get_ports {ilc3_amp[2]}]
set_property PACKAGE_PIN R14 [get_ports {ilc3_amp[3]}]
set_property PACKAGE_PIN U14 [get_ports ilc3_amp_valid]
set_property PACKAGE_PIN U15 [get_ports ilc3_frame_start]
set_property PACKAGE_PIN V17 [get_ports ilc3_frame_end]
set_property IOSTANDARD LVCMOS33 [get_ports {ilc3_amp[*]}]
set_property IOSTANDARD LVCMOS33 [get_ports ilc3_amp_valid]
set_property IOSTANDARD LVCMOS33 [get_ports ilc3_frame_start]
set_property IOSTANDARD LVCMOS33 [get_ports ilc3_frame_end]

## ── PMOD JC (Bank 34, LVCMOS33) — Control input from RX board ──
set_property PACKAGE_PIN V15 [get_ports rx_ready_in]
set_property PACKAGE_PIN W15 [get_ports pkt_done_in]
set_property IOSTANDARD LVCMOS33 [get_ports rx_ready_in]
set_property IOSTANDARD LVCMOS33 [get_ports pkt_done_in]

## ── PMOD JC (Bank 34, LVCMOS33) — TX symbol debug output ──
set_property PACKAGE_PIN T11 [get_ports {tx_sym_dbg[0]}]
set_property PACKAGE_PIN T10 [get_ports {tx_sym_dbg[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {tx_sym_dbg[*]}]

## ── UART TX (PMOD JE1, Bank 34, V12) ──
set_property PACKAGE_PIN V12 [get_ports uart_tx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_tx]

## ── LEDs ──
set_property PACKAGE_PIN M14 [get_ports {led[0]}]
set_property PACKAGE_PIN M15 [get_ports {led[1]}]
set_property PACKAGE_PIN G14 [get_ports {led[2]}]
set_property PACKAGE_PIN D18 [get_ports {led[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[*]}]
