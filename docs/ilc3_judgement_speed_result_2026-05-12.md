# ILC3 판정속도 한계 테스트 결과

Date: 2026-05-12

## 목적

PAM4 대비 ILC3 비교 실험을 진행하기 전에, ILC3 자체의 판정속도 한계를 먼저 확인했다.  
이번 테스트의 핵심은 `SYMBOL_HOLD_CLKS(SH)`와 TX strobe 위치를 바꿔가며, RX가 장시간 동안 동일 symbol stream을 오류 없이 판정할 수 있는 최소 안정 조건을 찾는 것이다.

## 테스트 대상 파일

### ILC3 accuracy TX

- RTL: `rtl/top_ilc3_accuracy_tx_board.v`
- Constraint: `constraints/ilc3_accuracy_tx_board.xdc`
- Project TCL: `tcl/create_project_ilc3_accuracy_tx.tcl`
- Build TCL: `tcl/build_ilc3_accuracy_tx_impl.tcl`
- Program TCL: `tcl/program_ilc3_accuracy_tx_board.tcl`

TX는 ILC3 비교용 symbol stream을 출력하며, 다음 build-time parameter를 사용한다.

```text
SYMBOL_HOLD_CLKS
STROBE_OFFSET_CLKS
STROBE_PULSE_CLKS
```

### ILC3 accuracy RX

- RTL: `rtl/top_ilc3_accuracy_rx_board.v`
- Constraint: `constraints/ilc3_accuracy_rx_board.xdc`
- Project TCL: `tcl/create_project_ilc3_accuracy_rx.tcl`
- Build TCL: `tcl/build_ilc3_accuracy_rx_impl.tcl`
- Program TCL: `tcl/program_ilc3_accuracy_rx_board.tcl`

RX는 첫 정상 frame을 학습한 뒤, 이후 frame과 비교한다. 고정 expected pattern이 아니라 learned pattern 기반이므로 TX/RX 양쪽 파일 형태가 정확히 맞는지 확인하는 용도에 적합하다.

## 로그 포맷

```text
ILC3BER SH=XXXX OK=XXXXXXXX SE=XXXXXXXX FS=XXXXXXXX WI=XXXXXXXX QN=XXXXXXXX R=X E=X L=X
```

필드 의미:

- `SH`: `SYMBOL_HOLD_CLKS`
- `OK`: 정상 판정 누적 카운터
- `SE`: symbol mismatch 누적 카운터
- `FS`: frame/sample 진행 카운터
- `WI`: thermometer/입력 invalid 카운터
- `QN`: 품질/오류 누적 카운터. 현재 테스트에서는 `SE + WI` 성격으로 사용
- `R`: 현재 수신 판정 symbol
- `E`: 현재 기대 symbol
- `L`: learned/lock 상태. `1`이면 RX가 pattern을 학습하고 비교 중

정상 판정 기준:

```text
L=1
WI=00000000
SE=00000000
QN=00000000
```

## 보드 및 아날로그 조건

테스트 중 확인된 조건:

- JD7/JD8/JD9는 TX/RX 보드에 결선됨
- `th0`는 warm-up 전 낮게 시작하며 시간이 지나면서 상승하는 경향이 있음
- 확인된 안정 기준 근처 threshold:
  - `th0 ~= 102 mV`
  - `th2 ~= 237 mV`
- WaveForms 측정상 analog swing은 약 `310 mV` 수준으로 확인됨
- JD7 측정값으로 약 `440 mV`가 관측된 구간이 있었음

주의:

- 아침 전원 투입 직후에는 `th0/th1/th2`가 낮게 시작함
- RX 학습형 구조이므로 재시작/리셋 시 TX가 먼저 정상 stream을 출력하고, RX를 나중에 리셋하는 순서가 더 안전함

## 테스트 결과 요약

| 조건 | TX offset | 결과 | 판정 |
|---|---:|---|---|
| `SH=0038` | 별도 조건 | `SE/QN` 큰 폭 증가 | 실패 |
| `SH=003E` | 별도 조건 | `SE/QN` 증가 | 실패 |
| `SH=0042` | 별도 조건 | `SE/QN` 증가 | 실패 |
| `SH=0043` | 기존 조건 | 장시간 후 rare error 발생 | 경계/불안정 |
| `SH=0044` | 48 | `OK=0D5E0226` 근처에서 `QN=1` | 장시간 완전 clean 아님 |
| `SH=0045` | 49 | 초반부터 `SE/QN` 지속 증가 | offset 실패 |
| `SH=0045` | 48 | `OK=15459EA7`까지 `SE/QN=0` | 안정 |
| `SH=0045` 리셋 후 | 48 | `OK=125B4401`까지 `SE/QN=0` | 재현성 확인 |

## 주요 로그 근거

### SH=0044 장시간 rare error

```text
ILC3BER SH=0044 OK=0D5E0226 SE=00000001 FS=00D5E024 WI=00000000 QN=00000001 R=7 E=7 L=1
```

해석:

- `L=1`, `WI=0`이므로 lock/invalid 문제는 아님
- `SE=1`, `QN=1`이므로 실제 symbol mismatch로 기록
- SH=0044는 단기 clean이 가능하지만 장시간 완전 clean은 아님

### SH=0045 offset 49 실패

```text
ILC3BER SH=0045 OK=006E9018 SE=000001F6 FS=0006E922 WI=00000000 QN=000001F6 R=0 E=0 L=1
ILC3BER SH=0045 OK=020D2777 SE=00000EB7 FS=0020D364 WI=00000000 QN=00000EB7 R=0 E=0 L=1
```

해석:

- `L=1`, `WI=0`
- 초반부터 `SE/QN` 지속 증가
- SH=0045 자체 문제가 아니라 TX strobe offset 49가 판정 위치와 맞지 않는 것으로 판단

### SH=0045 offset 48 안정

```text
ILC3BER SH=0045 OK=15459EA7 SE=00000000 FS=015459EC WI=00000000 QN=00000000 R=7 E=7 L=1
```

해석:

- 기준 `OK >= 10000000`을 넘긴 장시간 구간에서 `SE/QN=0`
- `WI=0`, `L=1` 유지
- SH=0044보다 안정

### 보드 리셋 후 재현성 확인

```text
ILC3BER SH=0045 OK=125B4401 SE=00000000 FS=0125B442 WI=00000000 QN=00000000 R=0 E=0 L=1
```

해석:

- TX/RX 리셋 후에도 동일 조건에서 `OK >= 10000000` 이상 clean
- 재현성 확인됨

## 결론

현재 ILC3 accuracy 테스트 기준 안정 설정은 다음과 같다.

```text
SYMBOL_HOLD_CLKS = 69  ; SH=0045
STROBE_OFFSET_CLKS = 48
STROBE_PULSE_CLKS = 4
```

판정:

- `SH=0044`는 장시간에서 rare error가 발생했으므로 한계 근처 조건이다.
- `SH=0045 / offset=49`는 strobe 위치가 맞지 않아 초반부터 에러가 누적된다.
- `SH=0045 / offset=48`은 장시간 clean이고, TX/RX 보드 리셋 후에도 clean이 재현됐다.

따라서 ILC3 accuracy/판정속도 기준값은 `SH=0045, offset=48, pulse=4`로 기록한다.

## 다음 작업

PAM4도 동일한 방식으로 accuracy/BER 로그 포맷을 맞춰 테스트해야 한다.  
비교는 단순 QN 로그가 아니라 동일 조건에서 다음 항목을 같이 봐야 한다.

- 같은 analog/threshold 조건
- 같은 noise injection 조건
- 같은 `OK` 기준의 장시간 run
- `WI`, `SE`, `QN` 분리 기록
- 판정속도 한계: ILC3의 `SH=0045 / offset=48`에 대응되는 PAM4 최소 안정 조건

