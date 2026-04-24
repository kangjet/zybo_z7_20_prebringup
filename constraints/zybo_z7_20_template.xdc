## Clock (Zybo Z7-20 125MHz onboard clock)
set_property PACKAGE_PIN K17 [get_ports sys_clk]
set_property IOSTANDARD LVCMOS33 [get_ports sys_clk]

create_clock -period 8.000 -name sys_clk -waveform {0 4} [get_ports sys_clk]

## Reset: RTL 내부에서 1'b1 고정 (버튼 의존성 제거)

## UART TX (임시: PMOD로 뺌 — 보드 오면 실제 UART로 재매핑)
# 기존 D18은 LD3(led[3])로 쓰므로 UART와 충돌나면 안 됨
set_property PACKAGE_PIN V12 [get_ports uart_tx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_tx]

## UART RX (PMOD JE Pin 3 = J15)
set_property PACKAGE_PIN J15 [get_ports uart_rx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_rx]

## LEDs (Zybo GPIO)
set_property PACKAGE_PIN M14 [get_ports {led[0]}]
set_property PACKAGE_PIN M15 [get_ports {led[1]}]
set_property PACKAGE_PIN G14 [get_ports {led[2]}]
set_property PACKAGE_PIN D18 [get_ports {led[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[*]}]
