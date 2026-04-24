# HW PPU UART Bringup 작업 일지 (2026-03-27)

## 개요

Zybo Z7-20 보드에서 **PL UART** (PL Fabric 기반 Verilog 구현)를 이용한 HW PPU 커맨드 프로토콜 양방향 통신 구현 완료 및 PS7 EMIO UART 시도 기록.

---

## 1. 최종 동작 상태 (PL UART)

| 항목 | 상태 |
|------|------|
| LED0 | 깜빡임 (heartbeat 정상) |
| LED1 | ON (RX 수신 확인) |
| LED2 | OFF (에러 없음) |
| LED3 | ON (모든 lane 수신 완료) |
| Flutter PING | `connected=true serial=Z7-20-COM3` ✅ |
| Boot signal | `[0xBB, 0xAA, 0x00, 0x01]` ✅ |

---

## 2. 하드웨어 구성

### 보드
- Zybo Z7-20 (Zynq-7020, PL 125 MHz 클럭)

### 커넥션 (2개 COM 포트)
| 포트 | 역할 | 물리 경로 |
|------|------|-----------|
| COM8 | JTAG / Vitis XSCT | FT2232HQ Channel A (USB-JTAG) |
| COM3 | HW PPU UART | FT2232HQ Channel B → PMOD JE |

> **주의**: PL UART 사용 시 COM3만 사용. COM8은 JTAG/PS7 전용.

### PMOD JE 핀 매핑
| 기능 | PMOD JE 핀 | FPGA 핀 |
|------|-----------|---------|
| UART TX | Pin 1 | V12 |
| UART RX | Pin 3 | J15 |

---

## 3. PL 설계 파일

### 3-1. RTL 파일

#### [rtl/top_zybo_ilc3_prebringup.v](../rtl/top_zybo_ilc3_prebringup.v)
- 최상위 모듈 (PL-only, Block Design 없음)
- 포트: `sys_clk`, `sys_rst_n`, `led[3:0]`, `uart_tx`, `uart_rx`
- 기능:
  - Heartbeat counter → LED[0]
  - ILC3 lane test (8 lanes) → LED[1..3]
  - UART 115200 8N1 커맨드 FSM

**FSM 상태:**
```
CS_BOOT (0) → Boot signal [0xBB, 0xAA, 0x00, 0x01] 전송
CS_IDLE (1) → RX 대기
CS_SEND (2) → 응답 전송
```

**커맨드 프로토콜:**
```
CMD_PING (0x01) → [0xAA, 0x01]
기타 명령       → [0xFF, cmd]  (NACK)
```

#### [rtl/uart_rx_simple.v](../rtl/uart_rx_simple.v)
- 115200 baud UART RX
- `CLKS_PER_BIT = 1085` (125 MHz / 115200 ≈ 1085)
- 2단 동기화 FF (메타스태빌리티 방지)
- start bit 중앙 샘플링 방식
- 상태: S_IDLE → S_START → S_DATA → S_STOP

#### [rtl/uart_tx_simple.v](../rtl/uart_tx_simple.v)
- 115200 baud UART TX
- `start` 펄스 → 8N1 전송

### 3-2. 제약 파일

#### [constraints/zybo_z7_20_template.xdc](../constraints/zybo_z7_20_template.xdc)
```
sys_clk  → K17 (125 MHz)
sys_rst_n → R18 (버튼)
uart_tx  → V12 (PMOD JE Pin 1)
uart_rx  → J15 (PMOD JE Pin 3)  ← 이번 작업에서 추가
led[0]   → M14
led[1]   → M15
led[2]   → G14
led[3]   → D18
```

---

## 4. Vivado 빌드 절차

```
1. Vivado에서 프로젝트 열기: C:\zybo_z7_20_prebringup\build\vivado\...
2. Sources에 uart_rx_simple.v 추가 (이번 작업 전 누락)
3. Run Synthesis → Run Implementation → Generate Bitstream
4. Open Hardware Manager → Program Device
5. LED0 깜빡임 확인
```

---

## 5. PS7 EMIO UART 시도 (미완료)

### 목적
PS ARM Cortex-A9 펌웨어 (main.c)에서 UART를 EMIO 경로로 사용.
→ 최종 목표: HW PPU 내부에 `base_secret` 저장 (PS7 OTP/eFuse 또는 ATECC608A)

### 구성
```
PS UART0 → EMIO → PL Fabric → PMOD JE Pin1/3 (TX/RX)
```

### 생성된 파일

#### [tcl/create_ps7_bd.tcl](../tcl/create_ps7_bd.tcl)
- Vivado TCL Console에서 실행
- PS7 블록 설계 `ps7_uart_emio` 생성
- UART0 EMIO 설정, DDR/FIXED_IO 외부화
- HDL Wrapper 자동 생성

**실행 방법:**
```tcl
# Vivado TCL Console에서:
source C:/zybo_z7_20_prebringup/tcl/create_ps7_bd.tcl
```

#### C:\vitis_workspace\load_elf.tcl
- JTAG cold boot: ps7_init + ELF 로드
- PS7_INIT 경로: `C:/vitis_workspace/hw_emio_uart_extracted/ps7_init.tcl`

#### C:\vitis_workspace\hello_world\src\main.c
- HW PPU Firmware v0.1
- UART0 EMIO 모드 (MIO 14/15 재설정 제거)
- CMD_PING, CMD_AUTH, CMD_ENCRYPT, CMD_DECRYPT 구현

### EMIO 시도 결과: NOPING

**확인된 문제점:**

| 문제 | 원인 | 상태 |
|------|------|------|
| MIO 경로 덮어쓰기 | main.c에서 MIO 14/15 UART0 설정 | 수정 완료 |
| 구 ps7_init.tcl | MIO UART0 기준으로 생성된 ps7_init | 새 ps7_init 적용 |
| EMIO 라우팅 미동작 | PL에서 EMIO TX/RX 핀 연결 확인 필요 | **미완료** |

### PS7 EMIO 디버깅 남은 작업

1. **PuTTY COM3 (115200)** 에서 부팅 신호 `BB AA 00 01` 수신 확인
2. Block Design에서 UART0_TX_0 / UART0_RX_0 포트가 상위 top 모듈에 올바르게 연결되었는지 확인
3. XDC에서 PS7 EMIO 포트명에 맞는 핀 제약 적용 여부 확인
4. `ps7_init.tcl` 내 UART0 관련 레지스터 설정값 검증

---

## 6. Flutter / SW 변경 사항

### 프로젝트 경로: C:\hw_ppu_windows_9toz

### phaselock_risk_engine.dart
- 누적창: 7일 rolling → **오늘 00:00 daily reset** 으로 변경
- `_todayMidnight()` 함수 추가
- `_appendMonthlyHistory()`: `risk_history/risk_YYYY_MM.jsonl` 월별 append

### screen_ghost.dart
- `header()` 함수에 `bgColor` 파라미터 추가
- 섹션별 배경색 구분:
  | 섹션 | 배경색 |
  |------|--------|
  | 사진 | 파란색 |
  | 영상 | 보라색 |
  | 오디오 | 청록색 |
  | 문서 | 주황색 |
  | 압축 | 노란색 |
  | 코드 | 초록색 |
  | 기타 | 회색 |

---

## 7. 발생한 에러 및 해결

| 에러 | 원인 | 해결 |
|------|------|------|
| `flutter run` 실패 (No pubspec.yaml) | 잘못된 디렉토리에서 실행 | `cd C:\hw_ppu_windows_9toz` 후 실행 |
| `sdk ^3.9.2 vs 3.8.0` 불일치 | 잘못된 프로젝트 (phaselock_app_hw) | 올바른 프로젝트(hw_ppu_windows_9toz) 사용 |
| `.flutter-plugins-dependencies 쓰기 권한` | 숨김 파일 잠금 | `del /F /A:H` 로 삭제 |
| DAP APB transaction error (0x30000021) | 보드 전원 문제 | 보드 전원 Off/On |
| Memory write error (DDR held in reset) | 구 ps7_init.tcl | 새 EMIO 설계 기반 ps7_init 적용 |
| `write_hw_platform` 에러 | .xsa 확장자 누락 | 파일명에 `.xsa` 추가 |
| arm-none-eabi-size PATH 없음 | Vitis PATH 미설정 | ELF 생성 완료 확인 후 무시 |
| PS7 EMIO NOPING | MIO 경로 덮어쓰기 + 구 ps7_init | main.c 수정 + 새 ps7_init 적용 (EMIO 라우팅은 미확인) |

---

## 8. 다음 단계 (우선순위 순)

- [ ] **PS7 EMIO 디버깅**: PuTTY COM3에서 부팅 신호 수신 확인
- [ ] **CMD_DERIVE_KEY 구현**: PS 펌웨어에 SHA-256 키 파생 커맨드 추가
- [ ] **Flutter deriveKey()**: phaselock_hw_ppu.dart에 키 파생 함수 구현
- [ ] **base_secret 이전**: 파일시스템(.pl_base_secret) → HW PPU 내부
- [ ] **QSPI BOOT.BIN**: bitstream + ELF 합본 생성 (1회 프로그래밍)

---

## 9. 참고 — 키 파생 설계

```
SHA-256(base_secret ‖ phase_token ‖ folderId ‖ label)
                ↑
        HW PPU 내부 저장
        (현재: .pl_base_secret 파일)
        (목표: PS7 eFuse / ATECC608A Key Slot)
```

Phase 2: ATECC608A ECDH / iCE40 AES-256-GCM 예정.
