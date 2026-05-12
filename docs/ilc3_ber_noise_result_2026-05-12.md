# ILC3 BER Noise Test Result

Date: 2026-05-12

## 목적

ILC3 accuracy TX/RX 기준으로 판정속도 안정 조건을 먼저 고정한 뒤, 500 mHz 저주파 노이즈 주입에 대한 BER-style 경계값을 확인했다.

PAM4와의 직접 비교는 아직 보류한다. PAM4는 동일한 `BER-style SE/WI/QN` 포맷으로 다시 측정해야 공정 비교가 가능하다.

## 최종 ILC3 설정

```text
SYMBOL_HOLD_CLKS   = 69  ; SH=0045
STROBE_OFFSET_CLKS = 48
STROBE_PULSE_CLKS  = 4
```

로그 포맷:

```text
ILC3BER SH=0045 OK=XXXXXXXX SE=XXXXXXXX FS=XXXXXXXX WI=XXXXXXXX QN=XXXXXXXX R=X E=X L=X
```

정상 판정 기준:

```text
L=1
WI=00000000
SE=00000000
QN=00000000
```

## 아날로그 조건

테스트 중 확인된 기준값:

```text
th0 ~= 104 mV
th1 ~= 175 mV
th2 ~= 246 mV
```

threshold 간격:

```text
th1 - th0 ~= 71 mV
th2 - th1 ~= 71 mV
```

따라서 150~180 mV 노이즈도 threshold spacing 기준으로는 충분히 큰 주입량이다.

## 판정속도 안정성 결과

노이즈 OFF 상태에서 다음 조건이 안정으로 확인됐다.

```text
SH=0045
STROBE_OFFSET=48
PULSE=4
```

대표 결과:

```text
ILC3BER SH=0045 OK=15459EA7 SE=00000000 FS=015459EC WI=00000000 QN=00000000 R=7 E=7 L=1
```

TX/RX 보드 리셋 후 재현성도 확인했다.

```text
ILC3BER SH=0045 OK=125B4401 SE=00000000 FS=0125B442 WI=00000000 QN=00000000 R=0 E=0 L=1
```

## 500 mHz 노이즈 주입 결과

| Noise amplitude | Result | 근거 |
|---:|---|---|
| 150 mV | Clean | `SE=0`, `QN=0`, `WI=0` 유지 |
| 160 mV | Clean | `SE=0`, `QN=0`, `WI=0` 유지 |
| 170 mV | Clean | `SE=0`, `QN=0`, `WI=0` 유지 |
| 180 mV | NG | rare symbol mismatch 발생 |
| 200 mV | NG / borderline | 초기 `QN=8` 관측 |
| 250 mV | NG | `QN` 증가 |
| 300 mV | NG | `QN` 증가 |
| 400 mV | NG | `QN` 증가 |
| 500 mV | NG | `QN` 증가 |

## 주요 로그

### 170 mV clean

```text
ILC3BER SH=0045 OK=11D10D09 SE=00000000 FS=011D10D2 WI=00000000 QN=00000000 R=1 E=1 L=1
```

판정:

```text
500 mHz / 170 mV = clean
```

### 180 mV NG 재확인

180 mV 재측정은 `SE/QN=0`에서 시작한 뒤 오류가 발생했다.

```text
ILC3BER SH=0045 OK=0228DAB3 SE=00000000 FS=00228DAD WI=00000000 QN=00000000 R=7 E=7 L=1
ILC3BER SH=0045 OK=02976CDA SE=00000002 FS=002976CF WI=00000000 QN=00000002 R=1 E=1 L=1
```

판정:

```text
500 mHz / 180 mV = first NG boundary
```

### 200 mV borderline/NG

```text
ILC3BER SH=0045 OK=086C220B SE=00000008 FS=0086C223 WI=00000000 QN=00000008 R=7 E=7 L=1
```

판정:

```text
500 mHz / 200 mV = NG 또는 borderline
```

### 250 mV NG

```text
ILC3BER SH=0045 OK=0182FF58 SE=0000001A FS=00182FF9 WI=00000000 QN=0000001A R=1 E=1 L=1
ILC3BER SH=0045 OK=02CEB55A SE=00000095 FS=002CEB60 WI=00000000 QN=00000095 R=1 E=1 L=1
```

판정:

```text
500 mHz / 250 mV = NG
```

## 결론

ILC3 단독 BER-style 테스트 기준:

```text
Clean pass: 500 mHz / 170 mV
First NG:   500 mHz / 180 mV
```

에러 성격:

```text
WI=0 유지
L=1 유지
SE/QN 증가
```

따라서 observed error는 invalid/window 문제가 아니라 실제 symbol mismatch로 판단한다.

## PAM4 비교 관련 주의

이전 PAM4 결과와 직접 비교하면 안 된다.

이유:

- 이전 PAM4는 주로 `PAM4Q` 로그 기반 관찰이었다.
- 현재 ILC3는 `BER-style SE/WI/QN` 분리 측정이다.
- 비교하려면 PAM4도 같은 방식의 `PAM4BER` 또는 동등한 accuracy RX/TX 로그로 재측정해야 한다.

다음 단계:

```text
PAM4 accuracy TX/RX 로딩
PAM4도 SH/offset 기준 안정 조건 확인
500 mHz noise amplitude sweep
SE/WI/QN 기준으로 ILC3와 비교
```

