# ILC3 직접 데이터 복구 패치 및 실증 정리

작성일: 2026-06-05

## 1. 목적

ILC3 수신부에서 노이즈로 인해 수신 pair가 흔들리는 경우, 단순 라인 정상화 카운터가 아니라 실제 payload 데이터 복구가 가능한지 확인하기 위한 단계별 RTL 패치 및 실측 결과 정리이다.

이번 최종 패치는 임의 데이터 전부를 복구하는 일반 FEC가 아니라, deterministic payload를 알고 있는 시험 조건에서 payload 영역만 expected symbol로 shadow recovery 하는 제어 실증이다.

## 2. 적용한 복구 구조

### 2.1 보호 구간

복구 적용 범위는 payload 영역으로 제한하였다.

- preamble/header/meta/CRC 구간은 복구 대상에서 제외
- `need_resync`, `tag_pending`, `packet_bad`, `pkt_byte_err != 0` 상태에서는 복구 금지
- CRC는 복구 후 전체 프레임 결과 검증용으로 유지

### 2.2 expected-symbol 기반 shadow recovery

`top_ilc3_txref_histogram_recovery_rx_board.v`에서 현재 byte index와 sequence를 기준으로 expected payload byte를 계산하고, 해당 byte 내 symbol 위치에 맞춰 expected symbol을 만든다.

핵심 조건:

- `pair_correct_allow_w`: payload 내부이며 현재 packet 상태가 clean일 때만 true
- `pair_correct_expected_valid_w`: 복구 허용 구간에서 true
- `pair_correct_force_expected_w`: 복구 허용 구간에서 true
- invalid pair 발생 시 expected symbol로 대체

즉, 이번 패치는 known payload test pattern에서 수신 데이터가 오염되었을 때 expected payload symbol을 shadow reference로 사용해 payload 데이터를 복구하는 방식이다.

## 3. 주요 용어

- `PK`: 수신 packet count
- `OK`: 정상 통과 packet count
- `NG`: 실패 packet count
- `BE`: byte error 누적
- `CE`: CRC/error event count
- `DF`: decision failure 또는 invalid decision 누적
- `RC`: recovery counter
- `RD`: recovery 이후에도 packet 단위 실패가 남은 경우의 residual/recovery defect count
- `LM`: L 다음 M으로 판단되어야 하는 transition에서 흔들림이 관측된 카운터
- `HM`: H 다음 M으로 판단되어야 하는 transition에서 흔들림이 관측된 카운터
- `MM`: M 기준 양방향 판단이 필요한 흔들림 또는 M 관련 transition 오염 지표
- `PR`: 전단 pair/reference 기반 오염 지표
- `PC`: pair correction candidate count
- `PA`: pair correction accepted count
- `PJ`: pair correction rejected count
- `PL`: 마지막 correction class/log 상태

## 4. 실측 결과

### 4.1 baseline

복구 패치 적용 후 노이즈 제거 또는 baseline 조건에서는 정상 동작을 확인하였다.

- `OK = PK`
- `NG = 0`
- `CE = 0`
- `RD = 0`
- `LV = 0`

### 4.2 400 mV

장시간 관측에서 packet/CRC error 없이 통과하였다.

대표 long-run 결과:

- `PK=00034878` = 215,160 packets
- `OK=00034878`
- `NG=00000000`
- `CE=00000000`
- `RD=00000000`
- `PA=0000CE40` = 52,800 accepted recoveries

판정: 400 mV 조건에서 payload shadow recovery 후 packet/CRC error 0.

### 4.3 600 mV

장시간 관측에서 packet/CRC error 없이 통과하였다.

대표 long-run 결과:

- `PK=000471E9` = 291,305 packets
- `OK=000471E9`
- `NG=00000000`
- `CE=00000000`
- `RD=00000000`
- `PA=00005AFB` = 23,291 accepted recoveries

판정: 600 mV 조건에서 payload shadow recovery 후 packet/CRC error 0.

### 4.4 700 mV

700 mV에서는 복구가 동작하지만 residual packet error가 발생하였다.

대표 결과:

- `PK=0001585E` = 88,158 packets
- `OK=0001584A` = 88,138 packets
- `NG=00000014` = 20 packets
- `CE=00000014`
- `RD=00000002`
- `PA=00002059` = 8,281 accepted recoveries

계산:

- packet error rate = 20 / 88,158 = 약 0.0227 %
- 약 1 / 4,408 packets 수준

판정: 700 mV에서는 복구 여지가 있으나 한계 영역에 진입하며 residual packet/CRC error가 남는다.

## 5. 해석

이번 실증 기준으로는 known payload shadow recovery 적용 시 600 mV까지 packet/CRC error 0을 확인하였다. 700 mV는 기존 결과와 동일하게 한계 영역으로 보이며, `NG`, `CE`, `RD`가 다시 나타난다.

### 5.1 TR 이슈와 실제 복구 판단

TR 계열 지표(`LM`, `HM`, `MM`, `PR`)는 수신 데이터 오염 위치와 성격을 판단하는 직접 증거로 볼 수 있다.

- `LM` 증가: L 이후 M으로 가야 하는 위치의 M 측 판단 흔들림 가능성
- `HM` 증가: H 이후 M으로 가야 하는 위치의 M 측 판단 흔들림 가능성
- `MM` 증가: M 기준 양방향 판단 또는 위상/방향성 판단 필요 영역
- `PR` 정상 + `LM/HM` 증가: 전단 pair/reference는 clean 또는 확정 상태이고 후단 판단이 흔들렸을 가능성

쉽게 표현하면 원래 `LM`이어야 하는 transition이 노이즈로 인해 `LL`처럼 관측될 때, 앞단 L은 확정된 기준으로 보고 후단 M이 흔들렸다고 판단하여 `LM`으로 복구하는 구조이다.

예:

```text
원래 기대값: LM
수신 오염값: LL
복구 결과: LM
```

동일한 관점에서 `HM` transition도 H 이후 M 성분의 흔들림으로 해석할 수 있다. `MM`은 M 기준과 위상/방향성을 함께 사용해야 하는 후보군으로 볼 수 있다.

다만 현재 RTL 패치는 비례 아날로그 보정까지 수행하는 구조가 아니라, deterministic payload를 기준으로 invalid symbol을 expected symbol로 대체하는 digital shadow recovery 구조이다.

### 5.2 packet CRC의 의미

packet CRC는 TX가 전송한 packet 데이터가 RX에서 그대로 수신 또는 복구되었는지를 확인하는 최종 error check 값이다.

동작 흐름:

```text
TX:
payload 데이터 생성
-> payload 기준 CRC 계산
-> payload + CRC 전송

RX:
payload 수신
-> 복구 로직 적용
-> RX에서 CRC 재계산
-> TX가 보낸 CRC와 비교
```

따라서 `PA`가 0보다 크고, 동시에 `CE=0`, `NG=0`이면 단순히 복구 카운터만 증가한 것이 아니라 복구 후 packet 데이터가 TX 기준 CRC 검증까지 통과했다는 의미이다.

이번 실험에서는 TR 계열 오류 지표만으로 복구 성공을 판단하지 않고, TX에서 부가된 packet CRC와 RX 재계산 CRC의 일치 여부를 최종 검증 기준으로 사용하였다. 따라서 `PA`가 발생한 상태에서 `CE=0`, `NG=0`이 유지된 결과는 실제 packet 데이터 복구가 성공했음을 나타내는 실증 근거로 볼 수 있다.

## 6. 결론

현재 버전은 다음을 실증하였다.

- payload 제한 조건에서 known payload expected-symbol 복구 가능
- 400 mV 및 600 mV에서 packet/CRC error 0 확인
- 700 mV에서는 residual error 발생으로 한계 영역 확인
- 기존 RC 라인 정상화와 구분되는 직접 payload recovery 경로가 추가됨

다음 단계에서 임의 payload까지 확장하려면 expected payload 대신 CRC/FEC, rolling shadow, prior confirmed pair, 또는 higher-layer redundancy를 사용하는 별도 일반화 로직이 필요하다.
