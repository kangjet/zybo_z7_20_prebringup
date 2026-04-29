# PAM4 Baseline 작업 요약

작성일: 2026-04-28
작업 repo: C:\zybo_z7_20_prebringup
기준 커밋: 718e133 Record stable ILC3 one-hour link baseline

## 배경

ILC3 TX/RX 실보드 링크는 1시간 이상 송수신 이상 없음으로 확인된 상태에서 PAM4 baseline 실증 단계로 진입했다.

이번 작업은 "진짜 단일 아날로그 PAM4 RX"가 아니라, PAM4 baseline 실증을 위한 첫 단계다.

- TX 보드: 2비트 PAM4 코드 발생기
- RX 보드: 2비트 디지털 코드 순서 검증 모니터
- AD3 측정: TX의 두 디지털 핀을 외부 저항 가중 합성한 노드에서 4레벨 PAM4 파형 확인

즉, FPGA PMOD 핀 자체는 LVCMOS33 0/3.3 V 디지털 출력이며, 단일선 4레벨 PAM4 파형은 외부 저항 합성 노드에서 만들어야 한다.

## 추가한 설계

### TX: PAM4 baseline pattern generator

Top module:

- rtl/top_pam4_baseline_tx_board.v

동작:

- PMOD JD의 두 핀으로 2비트 코드 출력
- 코드 순서: 00 -> 01 -> 10 -> 11 -> 반복
- 각 코드 유지 시간: SYMBOL_HOLD_CLKS=125
- sys_clk=125 MHz 기준 125 clocks = 1 us
- pam4_valid/pam4_sync는 심볼 중앙부에서만 활성화되는 wide window 방식
- UART 로그: `PAM4 CNT=XXXXXXXX C=X`

출력 핀:

- T14 / JD1 = pam4_code[0] LSB
- T15 / JD2 = pam4_code[1] MSB
- U14 / JD7 = pam4_valid
- U15 / JD8 = pam4_sync, code 00 중앙부에서 활성화

### RX: PAM4 baseline digital monitor

Top module:

- rtl/top_pam4_baseline_rx_board.v

동작:

- TX의 T14/T15/U14/U15를 RX JD 입력으로 수신
- 2비트 코드가 16 RX clock 동안 안정적으로 유지될 때만 새 심볼로 인정
- 안정화된 코드 변화 순서가 00 -> 01 -> 10 -> 11 -> 00 순서인지 검사
- `pam4_valid_in`/`pam4_sync_in`은 동기화 후 상태 확인/재동기화 보조로 사용
- UART 로그: `PAM4RX OK=XXXXXXXX NG=XXXXXXXX C=X`

입력 핀:

- T14 / JD1 = pam4_code_in[0]
- T15 / JD2 = pam4_code_in[1]
- U14 / JD7 = pam4_valid_in
- U15 / JD8 = pam4_sync_in

## Vivado 빌드 결과

TX PAM4 baseline bitstream:

- Path: C:\zybo_z7_20_prebringup\build\vivado_pam4_tx\pam4_baseline_tx.runs\impl_1\top_pam4_baseline_tx_board.bit
- Size: 4,045,702 bytes
- Timing: WNS 3.385 ns, TNS 0.000 ns
- Timing constraints met

RX PAM4 baseline monitor bitstream:

- Path: C:\zybo_z7_20_prebringup\build\vivado_pam4_rx\pam4_baseline_rx.runs\impl_1\top_pam4_baseline_rx_board.bit
- Size: 4,045,702 bytes
- Timing: WNS 2.538 ns, TNS 0.000 ns
- DRC: 0 errors
- Timing constraints met

## JTAG 로딩 결과

TX 보드:

- Script: tcl/program_pam4_baseline_tx_board.tcl
- Target: Digilent/210351BE5C62A
- Result: PAM4 baseline TX Board programmed OK
- Startup status: HIGH

RX 보드:

- Script: tcl/program_pam4_baseline_rx_board.tcl
- Target: Digilent/210351BE5D1FA
- Result: PAM4 baseline RX Board programmed OK
- Startup status: HIGH

## 확인된 TX UART 로그

사용자가 확인한 TX UART 예:

```text
PAM4 CNT=0081B31F C=3
PAM4 CNT=008583AF C=3
PAM4 CNT=0089543F C=3
PAM4 CNT=008D24CF C=3
PAM4 CNT=0090F55F C=3
PAM4 CNT=0094C5EF C=3
PAM4 CNT=0098967F C=3
PAM4 CNT=009C670F C=3
PAM4 CNT=00A0379F C=3
PAM4 CNT=00A4082F C=3
PAM4 CNT=00A7D8BF C=3
PAM4 CNT=00ABA94F C=3
PAM4 CNT=00AF79DF C=3
PAM4 CNT=00B34A6F C=3
PAM4 CNT=00B71AFF C=3
PAM4 CNT=00BAEB8F C=3
PAM4 CNT=00BEBC1F C=3
PAM4 CNT=00C28CAF C=3
PAM4 CNT=00C65D3F C=3
```

`C=3`으로 보이는 것은 1초 단위 로그 시점이 반복 패턴 중 code 3 구간을 샘플링하고 있기 때문이다. 패턴 자체는 00, 01, 10, 11 반복이다.

## RX 안정화 이후 확인된 UART 로그

초기 RX 판정은 `pam4_valid_in` 상승 에지에서 즉시 `pam4_code_in[1:0]`를 검사했기 때문에, 2비트가 동시에 바뀌는 전이 순간의 중간값을 NG로 잡을 수 있었다.

2026-04-28 11:57 KST 기준 RX를 안정화 샘플링 방식으로 수정했다.

- `STABLE_CLKS=16`
- 입력 코드가 16 RX clock 동안 동일하게 유지될 때만 새 심볼로 인정
- 새로 인정된 심볼이 이전 심볼 +1 modulo 4인지 검사
- 수정 후 RX bitstream 재빌드 및 RX 보드 로딩 완료

사용자가 확인한 RX UART 예:

```text
PAM4RX OK=01406F49 NG=00000000 C=0
PAM4RX OK=014FB18A NG=00000000 C=1
PAM4RX OK=015EF3CA NG=00000000 C=1
PAM4RX OK=016E360A NG=00000000 C=1
PAM4RX OK=017D784B NG=00000000 C=2
PAM4RX OK=018CBA8B NG=00000000 C=2
PAM4RX OK=019BFCCC NG=00000000 C=3
PAM4RX OK=01AB3F0C NG=00000000 C=3
PAM4RX OK=01BA814C NG=00000000 C=3
PAM4RX OK=01C9C38D NG=00000000 C=0
PAM4RX OK=01D905CD NG=00000000 C=0
PAM4RX OK=01E8480D NG=00000000 C=0
PAM4RX OK=01F78A4E NG=00000000 C=1
PAM4RX OK=0206CC8E NG=00000000 C=1
PAM4RX OK=02160ECF NG=00000000 C=2
PAM4RX OK=0225510F NG=00000000 C=2
PAM4RX OK=0234934F NG=00000000 C=2
PAM4RX OK=0243D590 NG=00000000 C=3
PAM4RX OK=025317D0 NG=00000000 C=3
PAM4RX OK=02625A11 NG=00000000 C=0
PAM4RX OK=02719C51 NG=00000000 C=0
```

판정:

- `OK` 지속 증가 확인
- `NG=00000000` 유지 확인
- `C`가 0/1/2/3 범위에서 순환 확인
- 현재 상태는 PAM4 digital baseline RX 정상으로 기록

## 20분 이상 soak test 결과

2026-04-28 KST, RX 안정화 샘플링 적용 후 PAM4 digital baseline을 20분 이상 연속 구동했다.

사용자 확인 결과:

- 20분 이상 구동
- RX `NG=00000000` 유지
- RX `OK` 지속 증가
- `C`는 0/1/2/3 범위에서 순환

20분 이상 구동 중 사용자가 확인한 후반 RX UART 예:

```text
PAM4RX OK=766F39E9 NG=00000000 C=0
PAM4RX OK=767E7C2A NG=00000000 C=1
PAM4RX OK=768DBE6A NG=00000000 C=1
PAM4RX OK=769D00AA NG=00000000 C=1
PAM4RX OK=76AC42EB NG=00000000 C=2
PAM4RX OK=76BB852B NG=00000000 C=2
PAM4RX OK=76CAC76C NG=00000000 C=3
PAM4RX OK=76DA09AC NG=00000000 C=3
PAM4RX OK=76E94BEC NG=00000000 C=3
PAM4RX OK=76F88E2D NG=00000000 C=0
PAM4RX OK=7707D06D NG=00000000 C=0
PAM4RX OK=771712AE NG=00000000 C=1
PAM4RX OK=772654EE NG=00000000 C=1
PAM4RX OK=7735972E NG=00000000 C=1
PAM4RX OK=7744D96F NG=00000000 C=2
PAM4RX OK=77541BAF NG=00000000 C=2
PAM4RX OK=77635DF0 NG=00000000 C=3
PAM4RX OK=7772A030 NG=00000000 C=3
PAM4RX OK=7781E270 NG=00000000 C=3
PAM4RX OK=779124B1 NG=00000000 C=0
PAM4RX OK=77A066F1 NG=00000000 C=0
PAM4RX OK=77AFA932 NG=00000000 C=1
PAM4RX OK=77BEEB72 NG=00000000 C=1
```

판정:

- PAM4 digital baseline 20분 이상 soak test 통과
- 관측 구간에서 RX error counter `NG=00000000`
- 현재 단계의 디지털 2비트 PAM4 baseline은 안정 상태로 판단

## 측정 연결

디지털 코드 baseline 연결:

- TX T14/JD1 -> RX T14/JD1
- TX T15/JD2 -> RX T15/JD2
- TX U14/JD7 -> RX U14/JD7
- TX U15/JD8 -> RX U15/JD8
- GND 공통

아날로그 PAM4 측정용 저항 합성 예:

- TX T15/JD2, MSB -> 10 kOhm -> PAM4 analog node
- TX T14/JD1, LSB -> 20 kOhm -> PAM4 analog node
- AD3 CHx -> PAM4 analog node
- AD3 GND -> board GND

이상적인 4레벨:

- 00: 약 0 V
- 01: 약 1.1 V
- 10: 약 2.2 V
- 11: 약 3.3 V

저항 오차, FPGA output impedance, AD3 input impedance, 배선 영향으로 실제 레벨은 약간 달라질 수 있다.

## 아날로그 PAM4 baseline 확인

2026-04-28 KST, 저항 DAC 방식으로 PAM4 analog node 4레벨을 확인했다.

연결:

- TX T15/JD2, `pam4_code[1]` MSB -> 10 kOhm -> PAM4 analog node
- TX T14/JD1, `pam4_code[0]` LSB -> 20 kOhm -> PAM4 analog node
- AD3 Scope CH1+ -> PAM4 analog node
- AD3 Scope CH1- / GND -> board GND

먼저 저항망 제거 후 JD2 단독 출력이 정상임을 확인했다.

- Low: 약 -30.49 mV
- High: 약 3.354 V
- Delta: 약 3.384 V

1 us/level 조건:

- `SYMBOL_HOLD_CLKS=125`
- 저항망 연결 시 analog node가 톱니형/둥근 파형으로 관측됨
- 10 kOhm / 20 kOhm 저항망과 AD3/배선 capacitance 때문에 1 us 내 settling이 충분하지 않은 현상으로 판단

100 us/level slow mode 조건:

- `SYMBOL_HOLD_CLKS=12500`
- TX project 재생성, 재빌드, TX 보드 로딩 완료
- Vivado synthesis log에서 `SYMBOL_HOLD_CLKS bound to: 12500` 확인
- TX route timing estimate: WNS 2.863 ns, TNS 0.000 ns
- DRC: 0 errors

AD3 관측:

- 약 0 V
- 약 1.1 V
- 약 2.2 V
- 약 3.3 V

판정:

- 10 kOhm / 20 kOhm 저항 DAC 연결 정상
- PAM4 analog node 4레벨 계단 파형 확인
- PAM4 resistor-DAC analog baseline 확보

주의:

- 현재 TX 보드는 analog 측정용 slow mode, 약 100 us/level 상태로 로딩되어 있다.
- 원래 digital baseline 속도, 약 1 us/level로 복귀하려면 `SYMBOL_HOLD_CLKS=125`로 TX를 재생성/재빌드/재로딩해야 한다.

## 2026-04-29 slow-mode soak 확인

2026-04-29 KST, 저항 추가 준비 전 기존 PAM4 slow-mode TX/RX를 다시 로딩하고 약 2시간 구동했다.

조건:

- TX: analog 측정용 slow mode, `SYMBOL_HOLD_CLKS=12500`
- 약 100 us/level
- RX: 안정화 샘플링 monitor

사용자가 확인한 RX UART 후반 로그:

```text
PAM4RX OK=06060DFE NG=00000000 C=2
PAM4RX OK=0606350E NG=00000000 C=2
PAM4RX OK=06065C1E NG=00000000 C=2
PAM4RX OK=0606832E NG=00000000 C=2
PAM4RX OK=0606AA3E NG=00000000 C=2
PAM4RX OK=0606D14E NG=00000000 C=2
PAM4RX OK=0606F85E NG=00000000 C=2
PAM4RX OK=06071F6E NG=00000000 C=2
PAM4RX OK=0607467E NG=00000000 C=2
PAM4RX OK=06076D8E NG=00000000 C=2
PAM4RX OK=0607949E NG=00000000 C=2
PAM4RX OK=0607BBAE NG=00000000 C=2
PAM4RX OK=0607E2BE NG=00000000 C=2
PAM4RX OK=060809CE NG=00000000 C=2
PAM4RX OK=060830DE NG=00000000 C=2
PAM4RX OK=060857EE NG=00000000 C=2
```

판정:

- PAM4 slow-mode baseline 약 2시간 구동
- RX `OK` 지속 증가
- RX `NG=00000000` 유지
- 2026-04-29 재로딩 후 slow-mode PAM4 baseline 안정 상태 확인

## 2026-04-29 1k/2k DAC 정속 및 noise 주입 결과

새 저항 도착 후 PAM4 DAC를 아래와 같이 변경했다.

- JD2 / MSB -> 1 kOhm -> PAM4 analog node
- JD1 / LSB -> 2 kOhm -> PAM4 analog node
- W1 -> 1 kOhm -> PAM4 analog node
- AD3/board GND 공통

TX는 정속 조건으로 복귀했다.

- `SYMBOL_HOLD_CLKS=125`
- 약 1 us/level
- TX route timing estimate: WNS 3.423 ns, TNS 0.000 ns
- DRC: 0 errors

결과:

- 1 kOhm / 2 kOhm DAC slow-mode 4레벨 정상 확인
- 정속 1 us/level에서도 4레벨 분리 확인
- RX reset 후 `NG=00000000` 유지
- W1 noise injection 경로 확인
- 100 mV / 200 mV / 500 mV noise 주입 시 analog node에 baseline wander/변조 관측
- 500 mV 조건에서도 4레벨 구조 유지
- RX digital monitor는 `NG=00000000` 유지

관련 상세 보고서:

- `pam4_1k2k_noise_test_result_2026-04-29.md`

관련 이미지:

- `pam4_base.png`
- `pam4_noise_100mV.png`
- `pam4_noise_200mV.png`
- `pam4_noise_500mV.png`

## 현재 한계

현재 RX 모니터는 단일 아날로그 PAM4 노드를 직접 디코딩하지 않는다. RX는 여전히 두 개의 디지털 비트 라인을 받아 순서를 검증한다.

진짜 analog PAM4 RX를 하려면 다음 중 하나가 필요하다.

- XADC 입력으로 PAM4 node 샘플링
- 외부 comparator 3개로 threshold 분리
- 외부 ADC 모듈 사용
- 저속 실험용 RC/threshold 보드 구성

## 다음 단계

1. AD3 persistence 또는 histogram으로 4레벨 분산 기록
2. 필요 시 저항값 또는 출력 DRIVE/SLEW 조정 검토
3. 원래 속도, `SYMBOL_HOLD_CLKS=125`, 복귀 후 digital baseline 재확인
4. noise 주입 기준점 설정
5. 이후 analog RX 경로 설계(XADC/comparator/ADC)로 이동
