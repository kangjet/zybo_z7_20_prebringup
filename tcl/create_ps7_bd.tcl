# create_ps7_bd.tcl
# Vivado TCL Console에서 source 하세요:
#   source C:/zybo_z7_20_prebringup/tcl/create_ps7_bd.tcl
#
# 결과: ps7_uart_emio 블록 설계 + HDL Wrapper 생성
#       PS7 UART0 → EMIO → PMOD JE Pin1(TX) / Pin3(RX) 연결용

set bd_name "ps7_uart_emio"

# ── 1. 블록 설계 생성 ──────────────────────────────────────────────────────
create_bd_design $bd_name

# ── 2. Zynq PS7 추가 ──────────────────────────────────────────────────────
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7 processing_system7_0

# ── 3. Board preset 적용 + DDR / FIXED_IO 외부 포트화 ──────────────────────
apply_bd_automation \
    -rule xilinx.com:bd_rule:processing_system7 \
    -config {make_external "FIXED_IO, DDR" apply_board_preset "1" \
             Master "Disable" Slave "Disable"} \
    [get_bd_cells processing_system7_0]

# ── 4. UART0 = EMIO,  AXI / 기타 불필요한 인터페이스 비활성화 ──────────────
set_property -dict [list \
    CONFIG.PCW_UART0_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_UART0_UART0_IO          {EMIO} \
    CONFIG.PCW_USE_M_AXI_GP0           {0}   \
    CONFIG.PCW_USE_S_AXI_HP0           {0}   \
] [get_bd_cells processing_system7_0]

# ── 5. UART0 EMIO 핀 외부 포트화 (Vivado 버전별 핀 이름 자동 탐색) ──────────
set made_external 0

# 방법 A: 개별 핀 (Vivado 2019~ 일반적)
set all_pins [get_bd_pins -of_objects [get_bd_cells processing_system7_0]]
set txd_pin ""
set rxd_pin ""
foreach p $all_pins {
    set pname [get_property NAME $p]
    if {[string match -nocase "*uart*" $pname]} {
        if {[string match -nocase "*tx*" $pname]} { set txd_pin $p }
        if {[string match -nocase "*rx*" $pname]} { set rxd_pin $p }
    }
}

if {$txd_pin ne "" && $rxd_pin ne ""} {
    make_bd_pins_external $txd_pin
    make_bd_pins_external $rxd_pin
    set made_external 1
    puts "=== UART0 EMIO 핀 외부화: TX=$txd_pin  RX=$rxd_pin ==="
}

# 방법 B: 인터페이스로 노출되는 경우 (일부 버전)
if {!$made_external} {
    set uart_iface [get_bd_intf_pins -of_objects \
        [get_bd_cells processing_system7_0] -filter {NAME =~ *UART*}]
    if {[llength $uart_iface] > 0} {
        make_bd_intf_pins_external $uart_iface
        set made_external 1
        puts "=== UART0 EMIO 인터페이스 외부화: $uart_iface ==="
    }
}

if {!$made_external} {
    puts ""
    puts "!!! UART0 핀 자동 탐색 실패 !!!"
    puts "GUI에서 processing_system7_0 의 UART_0 포트를 우클릭 → Make External 하세요."
    puts ""
}

# ── 6. 검증 + 저장 ────────────────────────────────────────────────────────
validate_bd_design
save_bd_design

# ── 7. 출력물 생성 + HDL Wrapper ──────────────────────────────────────────
generate_target all [get_files ${bd_name}.bd]

set wrapper [make_wrapper -files [get_files ${bd_name}.bd] -top]
add_files -norecurse $wrapper

puts ""
puts "==================================================="
puts "  ps7_uart_emio 블록 설계 완료!"
puts "  Wrapper: $wrapper"
puts ""
puts "  다음 단계:"
puts "  1. Wrapper의 UART 포트명 확인 (아래 명령 실행)"
puts "     get_ports -of_objects \[get_cells u_ps7\]"
puts "  2. top_zybo_ilc3_prebringup.v 수정"
puts "==================================================="
