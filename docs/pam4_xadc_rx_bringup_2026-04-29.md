# PAM4 XADC RX bring-up 기록

작성일: 2026-04-29
작업 repo: `C:\zybo_z7_20_prebringup`
기준 커밋: `794badd Record PAM4 noise injection baseline`

## 목적

기존 PAM4 RX는 JD1/JD2 디지털 핀을 직접 읽는 monitor였다.
이번 단계에서는 TX의 1k/2k resistor-DAC analog node를 RX 보드 JA XADC 입력으로 넣고, FPGA 내부 XADC가 실제 analog level을 읽는지 확인했다.

## 최종 연결

PAM4 DAC:

```text
TX JD2 / MSB ---- 1 kOhm ----+
                             +---- PAM4 analog node ---- AD3 CH1+
TX JD1 / LSB ---- 2 kOhm ----+

AD3 CH1- / GND -------------- board GND
TX GND ---------------------- RX GND ---------------- AD3 GND
```

XADC 입력:

```text
PAM4 analog node ---- 27 kOhm ----+---- RX JA1 / XADC AD14P
                                  |
                                 10 kOhm
                                  |
GND ------------------------------+---- RX JA7 / XADC AD14N
```

주의:

- XADC 입력은 1 V 이하로 제한해야 하므로 3.3 V PAM4 node를 JA에 직접 연결하지 않는다.
- 27k/10k 분압 기준으로 3.3 V는 약 0.89 V가 된다.
- RX UART는 COM7, RX JTAG는 COM9다.
- TX UART는 COM3, TX JTAG는 COM8이다.

## 추가한 파일

```text
rtl/top_pam4_xadc_rx_board.v
constraints/pam4_xadc_rx_board.xdc
tcl/create_project_pam4_xadc_rx.tcl
tcl/build_pam4_xadc_rx_impl.tcl
tcl/program_pam4_xadc_rx_board.tcl
```

## XADC RX 동작

새 RX top은 JA1/JA7의 XADC VAUX14를 읽고, UART로 1초마다 raw 값을 출력한다.

UART 출력 형식:

```text
XADC RAW=XXX LV=X MIN=XXX MAX=XXX N=XXXXXXXX
```

필드 의미:

- `RAW`: 최근 XADC 12-bit raw sample
- `LV`: 현재 threshold 기준 level 판정
- `MIN`: 1초 window 내 최소 raw
- `MAX`: 1초 window 내 최대 raw
- `N`: 누적 XADC sample count

## 구현 중 확인한 문제와 수정

1. XADC bitstream이 올라갔는데 COM7에서 계속 `PAM4RX ...`가 출력됨
   - 원인 후보로 JTAG target/COM 매핑을 확인했다.
   - 실제 매핑은 TX=COM8 JTAG/COM3 UART, RX=COM9 JTAG/COM7 UART로 정리했다.

2. XADC top reset 극성 문제
   - 기존 PAM4 RX는 BTN0가 idle LOW, pressed HIGH인 조건에 맞춰 reset synchronizer를 사용한다.
   - XADC top 초기 구현은 reset 극성이 달라 idle 상태에서 reset에 묶일 수 있었다.
   - 기존 RX와 동일한 reset synchronizer 방식으로 수정했다.

3. XADC VAUX14 제약 문제
   - 초기 build에서 Bank 35 IOSTANDARD 충돌이 발생했다.
   - `vauxp14/vauxn14`에 `IOSTANDARD LVCMOS33`을 명시해 구현을 통과시켰다.

## 빌드 결과

수정 후 Vivado build 결과:

```text
synth_design: 0 errors, 0 critical warnings
place/route: completed successfully
write_bitstream: completed successfully
DRC: 0 errors
```

생성 bitstream:

```text
C:\zybo_z7_20_prebringup\build\vivado_pam4_xadc_rx\pam4_xadc_rx.runs\impl_1\top_pam4_xadc_rx_board.bit
```

## 확인된 UART 로그

TX 재로딩 전에는 TX 출력이 없어 XADC가 거의 0 V만 읽었다.

예:

```text
XADC RAW=008 LV=0 MIN=000 MAX=090 N=00125700
XADC RAW=011 LV=0 MIN=000 MAX=097 N=0024C05A
```

TX 보드에 PAM4 TX bitstream을 다시 로딩한 뒤에는 XADC raw 값이 PAM4 analog node를 따라 움직였다.

예:

```text
PAM4 CNT=003567DF C=3
PAM4 CNT=0039386F C=3
PAM4 CNT=003D08FF C=3

XADC RAW=5D0 LV=1 MIN=000 MAX=ABA N=16B9F98C
XADC RAW=32C LV=1 MIN=000 MAX=AC5 N=16CC62E6
XADC RAW=428 LV=1 MIN=000 MAX=AC8 N=16DECC41
XADC RAW=85A LV=2 MIN=000 MAX=AC2 N=16F1359C
XADC RAW=1A2 LV=0 MIN=000 MAX=AB6 N=17039EF6
XADC RAW=861 LV=2 MIN=000 MAX=AC4 N=172871AC
XADC RAW=8AE LV=2 MIN=000 MAX=ABA N=17E08F36
```

## 파형 확인

AD3 Scope에서 PAM4 analog node 정상 파형을 확인했다.

관찰:

- 4개 레벨이 구분됨
- 약 0 V, 0.8 V, 1.5 V, 2.2 V 부근 레벨
- 1 us/level 조건에서 edge settling은 있으나 1k/2k 기준으로 레벨 분리가 유지됨

사용자 확인 이미지:

```text
c:\Users\kangmu\Pictures\iCloud Photos\Photos\이미지 2026. 4. 29. 오후 4.36.png
```

## 현재 판정

현재 단계는 정상 진행으로 판단한다.

확인된 사실:

- TX PAM4 analog node가 정상 4레벨로 출력된다.
- 27k/10k 분압 후 RX JA1/JA7 XADC 입력으로 신호가 들어온다.
- RX FPGA의 XADC monitor가 UART로 raw sample을 출력한다.
- XADC raw 값이 PAM4 analog node 변화에 따라 움직인다.

아직 남은 일:

- 현재 threshold에서는 `LV=3`이 잘 나오지 않는다.
- 실제 `MAX`가 대략 `0xAC0~0xADF` 수준이라 기존 `THRESH_23`이 너무 높다.

다음 threshold 후보:

```text
THRESH_01 = 12'h250
THRESH_12 = 12'h550
THRESH_23 = 12'h850
```

다음 작업은 threshold를 조정한 뒤 `LV=0/1/2/3`이 모두 안정적으로 나오는지 확인하는 것이다.
