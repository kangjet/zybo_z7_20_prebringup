# Zybo Z7-20 Bring-up Checklist (ILC3)

## 0. 사전 준비

- Vivado 설치 확인
- USB-JTAG/UART 드라이버 확인
- 보드 전원/점퍼 확인

## 1. RTL 스테이징

```bash
cd /Users/kangjet/ILC-4_CoPBit/CoPBit_Research/coda/fpga_validation_pkg_v1/zybo_z7_20_prebringup
./tools/stage_ilc3_rtl_from_zip.sh
```

체크:
- `rtl/ilc3_core/ilc3_tx_core.v`
- `rtl/ilc3_core/ilc3_rx_core.v`
- `rtl/ilc3_core/ilc3_ipcore_top.v`

## 2. 보드 핀 반영

- Digilent Zybo Z7-20 master XDC를 열고
  `constraints/zybo_z7_20_template.xdc`의 placeholder를 실제 핀으로 치환
- 최소 신호: `sys_clk`, `sys_rst_n`, `led[3:0]`
- UART 로그가 필요하면 `uart_tx`도 매핑

## 3. 합성/구현/bitstream

```bash
vivado -mode batch -source tcl/run_impl.tcl
```

체크:
- `build/reports/impl_timing_summary.rpt`에서 WNS/TNS
- `build/reports/impl_utilization.rpt`에서 LUT/FF/BRAM/DSP
- bitstream 생성 확인

## 4. 보드 다운로드

- Vivado Hardware Manager로 `.bit` 다운로드
- LED 동작 확인:
  - `led[0]`: heartbeat
  - `led[1]`: 최소 1개 lane에서 rx_valid 관측됨
  - `led[2]`: lane compare mismatch 발생
  - `led[3]`: 모든 lane에서 rx_valid 관측 완료

## 5. ILC3 실검증으로 확장

현재 prebringup top은 내부 loopback smoke 검증용이다.
실측 검증으로 확장할 때는 아래를 추가한다.

- 결과 샘플 캡처 경로 (UART/AXI-lite/ILA/BRAM dump)
- `t,tiles,<kernel>_fpga,valid` CSV 변환 스크립트
- `fpga_validation_pkg_v1/tools/fpga_run_scoreboard.sh` 실행

예시:
```bash
cd /Users/kangjet/ILC-4_CoPBit/CoPBit_Research/coda/fpga_validation_pkg_v1
./tools/fpga_run_scoreboard.sh cosine tiles8 artifacts/fpga_runs/fpga_out_cosine_tiles8.csv
```

## 6. 첫 실패시 우선 점검

- reset polarity 불일치 (`sys_rst_n`)
- clock period/XDC 누락
- top 포트명과 XDC 포트명 불일치
- unconstrained I/O 경고 무시 여부
