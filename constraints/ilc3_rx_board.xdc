## ============================================================
## ilc3_rx_board.xdc — RX Board (Board 2: COM7 UART / COM9 JTAG)
## Target: Zybo Z7-20 (xc7z020clg400-1)
## ============================================================

## Clock (125 MHz onboard)
set_property PACKAGE_PIN K17 [get_ports sys_clk]
set_property IOSTANDARD LVCMOS33 [get_ports sys_clk]
create_clock -period 8.000 -name sys_clk [get_ports sys_clk]

## Reset button (BTN0, active-low)
set_property PACKAGE_PIN K18 [get_ports rst_btn_n]
set_property IOSTANDARD LVCMOS33 [get_ports rst_btn_n]

## ── PMOD JD (Bank 34, LVCMOS33) — Amplitude input ← TX board ──
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

## ── PMOD JC (Bank 34, LVCMOS33) — Control output → TX board ──
set_property PACKAGE_PIN V15 [get_ports rx_ready_out]
set_property PACKAGE_PIN W15 [get_ports pkt_done_out]
set_property IOSTANDARD LVCMOS33 [get_ports rx_ready_out]
set_property IOSTANDARD LVCMOS33 [get_ports pkt_done_out]

## ── PMOD JC (Bank 34, LVCMOS33) — Debug output → AD3 ──
set_property PACKAGE_PIN W14 [get_ports crc_pass_dbg]
set_property PACKAGE_PIN Y14 [get_ports crc_fail_dbg]
set_property IOSTANDARD LVCMOS33 [get_ports crc_pass_dbg]
set_property IOSTANDARD LVCMOS33 [get_ports crc_fail_dbg]

## ── UART TX (PMOD JE1, Bank 34, V12) ──
set_property PACKAGE_PIN V12 [get_ports uart_tx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_tx]

## ── LEDs ──
set_property PACKAGE_PIN M14 [get_ports {led[0]}]
set_property PACKAGE_PIN M15 [get_ports {led[1]}]
set_property PACKAGE_PIN G14 [get_ports {led[2]}]
set_property PACKAGE_PIN D18 [get_ports {led[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[*]}]

## ── Async input false path (2-FF sync: PMOD ← TX board) ──
set_false_path -from [get_ports {ilc3_amp[*]}]
set_false_path -from [get_ports ilc3_amp_valid]
set_false_path -from [get_ports ilc3_frame_start]
set_false_path -from [get_ports ilc3_frame_end]
