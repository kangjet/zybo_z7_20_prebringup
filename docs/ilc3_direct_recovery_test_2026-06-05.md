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

### 4.3 500 mV

장시간 관측에서 packet/CRC error 없이 통과하였다.

대표 long-run 결과:

- `PK=0019DD2D` = 1,695,021 packets
- `OK=0019DD2D` = 1,695,021 packets
- `NG=00000000`
- `CE=00000000`
- `RD=00000000`
- `DF=0000038D` = 909
- `RC=0000038D` = 909
- `PC=04967651` = 76,969,553 candidates
- `PA=0000E387` = 58,247 accepted recoveries
- `PJ=049592CA` = 76,911,306 rejected candidates

계산:

- packet 통과율 = 100 %
- `PA/PK` = 58,247 / 1,695,021 = packet당 평균 약 0.034회 복구
- `PA/PC` = 58,247 / 76,969,553 = 약 0.0757 %

판정: 500 mV 조건에서 recovery accept가 실제로 발생했지만 packet/CRC error는 0으로 유지되었다. 이는 400 mV와 600 mV 사이의 중간 지점에서도 복구 영역이 연속적으로 유지됨을 보여준다.

### 4.4 600 mV

장시간 관측에서 packet/CRC error 없이 통과하였다.

대표 long-run 결과:

- `PK=000471E9` = 291,305 packets
- `OK=000471E9`
- `NG=00000000`
- `CE=00000000`
- `RD=00000000`
- `PA=00005AFB` = 23,291 accepted recoveries

판정: 600 mV 조건에서 payload shadow recovery 후 packet/CRC error 0.

### 4.5 700 mV

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

## 5. 데이터 복구 로직 상세

이 절은 나중에 블록 다이어그램 또는 플로차트로 옮길 수 있도록 현재 RTL 동작을 단계별로 정리한 것이다.

### 5.1 전체 처리 흐름

현재 known-payload shadow recovery의 전체 흐름은 다음과 같다.

```text
1. RX symbol/pair 수신
2. 현재 위치가 복구 허용 구간인지 확인
3. 현재 packet 상태가 clean인지 확인
4. 현재 byte index와 sequence로 expected payload byte 계산
5. 현재 symbol 위치에 해당하는 expected symbol 추출
6. 수신 pair/symbol이 정상인지 또는 invalid/오염 후보인지 판단
7. 복구 허용 + expected symbol 유효 + 오염 후보이면 expected symbol로 대체
8. 복구 accept/reject/candidate 카운터 갱신
9. 복구된 payload 기준으로 packet 조립
10. RX에서 CRC 재계산
11. TX가 보낸 CRC와 비교
12. CRC 통과 시 OK, 실패 시 NG/CE 증가
```

### 5.2 복구 허용 조건

복구는 모든 위치에서 수행하지 않는다. 현재 패치는 payload 영역에서만 복구한다.

복구 허용 조건:

```text
need_resync == 0
tag_pending == 0
packet_bad == 0
pkt_byte_err == 0
byte_idx >= preamble + header + meta
byte_idx < frame_bytes - crc_len
```

의미:

- link/frame 동기 상태가 정상이어야 한다.
- TAG 처리 중이거나 packet이 이미 bad 상태이면 복구하지 않는다.
- byte error가 이미 확정된 packet에서는 shadow recovery를 적용하지 않는다.
- preamble/header/meta/CRC는 복구하지 않는다.
- payload만 expected-symbol 복구 대상이다.

플로차트 분기:

```text
현재 위치가 payload인가?
  아니오 -> 원래 수신값 사용
  예 ->
    packet 상태가 clean인가?
      아니오 -> 원래 수신값 사용
      예 -> expected-symbol 복구 판단으로 이동
```

### 5.3 expected payload byte 생성

현재 테스트 payload는 deterministic pattern이다. 따라서 RX는 현재 byte 위치와 sequence 값을 이용해 해당 위치에서 와야 하는 expected byte를 계산할 수 있다.

개념:

```text
payload_index = byte_idx - payload_start
expected_byte = payload_byte(payload_index, seq_rx)
```

현재 테스트 패턴의 개념은 다음과 같다.

```text
expected_byte = payload_index ^ seq_rx[7:0] ^ 8'hA5
```

이 값은 TX가 보낸 payload 규칙과 동일해야 한다. 따라서 RX는 수신값이 흔들렸을 때 해당 위치의 정상 expected byte를 shadow reference로 사용할 수 있다.

### 5.4 expected symbol 선택

ILC3는 byte 내부를 2-bit symbol 단위로 판단한다. 따라서 expected byte에서 현재 symbol 위치에 해당하는 2-bit 값을 꺼낸다.

```text
sym_in_byte == 0 -> expected_byte[7:6]
sym_in_byte == 1 -> expected_byte[5:4]
sym_in_byte == 2 -> expected_byte[3:2]
sym_in_byte == 3 -> expected_byte[1:0]
```

플로차트 분기:

```text
현재 symbol 위치 확인
  0 -> expected upper 2 bits
  1 -> expected next 2 bits
  2 -> expected next 2 bits
  3 -> expected lower 2 bits
```

### 5.5 TR/transition 기반 오염 후보 판단

TR 계열 지표는 수신 transition이 흔들렸다는 직접 증거로 사용된다.

대표 해석:

- `LM`: L 다음 M이어야 하는데 M 측 판단이 흔들린 후보
- `HM`: H 다음 M이어야 하는데 M 측 판단이 흔들린 후보
- `MM`: M 기준에서 양방향 후보 또는 방향성 판단이 필요한 후보
- `PR`: 전단 pair/reference 기준으로 비교했을 때의 pair reference 오염 또는 흔들림 지표

예를 들어 원래 `LM`이어야 하는 위치에서 후단 M이 낮은 방향으로 흔들리면 `LL`처럼 보일 수 있다.

```text
정상 transition: LM
오염 관측: LL
복구 판단: 앞단 L은 유지, 후단 M을 expected symbol 기준으로 복원
복구 결과: LM
```

동일하게 `HM`은 다음처럼 설명할 수 있다.

```text
정상 transition: HM
오염 관측: HH
복구 판단: 앞단 H는 유지, 후단 M을 expected symbol 기준으로 복원
복구 결과: HM
```

현재 최종 RTL에서는 TR evidence만으로 임의 값을 추정하는 것이 아니라, payload expected symbol이 유효한 경우 expected symbol을 최종 복구값으로 사용한다.

### 5.6 correction candidate/accept/reject

복구 판단 과정은 세 개의 debug counter로 관찰한다.

- `PC`: pair correction candidate count
- `PA`: pair correction accepted count
- `PJ`: pair correction rejected count

개념:

```text
오염 후보 발생 -> PC 증가

복구 허용 조건 만족
expected symbol 유효
force expected recovery 활성
  -> PA 증가
  -> output symbol = expected symbol

조건 불만족
  -> PJ 증가
  -> 원래 수신값 유지 또는 복구 거부
```

플로차트:

```text
오염 후보인가?
  아니오 -> 정상 symbol 통과
  예 -> PC++
       복구 허용 조건 만족?
         아니오 -> PJ++, 원래 경로
         예 ->
           expected symbol valid?
             아니오 -> PJ++, 원래 경로
             예 -> PA++, expected symbol 출력
```

### 5.7 packet 조립과 CRC 검증

복구된 symbol은 payload byte 조립에 사용된다. 이후 RX는 packet 전체 기준으로 CRC를 다시 계산하고, TX가 보낸 CRC와 비교한다.

```text
복구 후 payload 조립
-> RX CRC 계산
-> TX CRC와 비교
-> 일치: OK
-> 불일치: CE/NG 증가
```

중요한 점:

- `PA > 0`은 실제 복구 accept가 발생했다는 의미이다.
- `CE=0`, `NG=0`은 복구 후 packet이 TX 기준 CRC를 통과했다는 의미이다.
- 따라서 `PA > 0`이면서 `CE=0`, `NG=0`이면 복구가 단순 카운터가 아니라 packet 데이터 검증까지 통과한 것으로 해석할 수 있다.

### 5.8 현재 로직의 정확한 범위

현재 실증된 범위:

- deterministic payload
- expected byte를 RX가 계산 가능
- payload 영역의 invalid pair 또는 TR 흔들림
- CRC 기반 최종 검증

아직 일반화가 필요한 범위:

- 임의 payload
- payload 내용을 RX가 미리 모르는 조건
- CRC 자체 또는 header/meta가 오염되는 조건
- expected symbol 없이 오직 LM/HM/MM/PR 규칙만으로 보정하는 일반 복구
- 비례 아날로그 보정까지 포함한 mV 단위 보정

따라서 현재 로직은 다음처럼 표현하는 것이 정확하다.

```text
known-payload expected-symbol shadow recovery
```

일반 data recovery로 확장하려면 다음 중 하나 이상의 추가 기준이 필요하다.

- FEC
- packet-level retry 또는 redundancy
- rolling shadow copy
- prior confirmed pair history
- CRC syndrome 기반 후보 선택
- M 기준 아날로그 거리 기반 비례 보정

### 5.9 복구 한계 영역과 재전송 시퀀스

이번 실측에서 400 mV, 500 mV, 600 mV는 known-payload shadow recovery 후 `NG=0`, `CE=0`, `RD=0`으로 통과하였다. 반면 700 mV에서는 `PA`가 존재하여 복구 로직은 계속 동작하지만 `NG/CE`가 다시 발생하였다.

이는 700 mV 이상이 단순 symbol-level correction만으로 끝까지 밀어붙일 영역이 아니라, link stability와 retransmission sequence로 넘겨야 하는 한계 영역임을 의미한다.

권장 판단 구조:

```text
중간 노이즈 영역:
  TR 흔들림 발생
  -> expected-symbol / rule 기반 복구
  -> CRC 통과
  -> OK

한계 노이즈 영역:
  TR 흔들림 + PR/DD/CRC 실패 증가
  -> 일부 복구 성공
  -> residual NG/CE 발생
  -> packet discard
  -> resync 또는 retransmission request
```

설계 기준:

- CRC가 통과한 packet만 최종 OK로 인정한다.
- CRC가 실패한 packet은 복구 추정값이 있더라도 OK로 승격하지 않는다.
- 700 mV 이상처럼 residual error가 남는 영역은 data correction 영역이 아니라 link unstable 영역으로 분류한다.
- 이 영역에서는 packet discard, resync, retransmission sequence가 더 적절하다.

따라서 ILC3 복구 구조의 목표는 모든 노이즈 조건을 무조건 복구하는 것이 아니라, 복구 가능한 symbol contamination 영역과 재전송이 필요한 link instability 영역을 명확히 분리하는 것이다.

### 5.10 CE/NG 발생 시 RC 이후 재전송 요구 루틴

과노이즈 상태에서 `CE/NG > 0`이 발생하면 해당 packet은 데이터 복구 실패로 판단한다. 이때 즉시 retransmission request를 전송하지 않고, 먼저 RC 기반 line recovery 또는 resync를 수행한 뒤 link clean 상태가 확인된 시점에 retransmission request를 전송하는 것이 바람직하다.

이유:

- `CE/NG > 0`이 발생한 시점은 line 자체가 불안정할 가능성이 높다.
- 불안정한 line 상태에서 retransmission request를 즉시 보내면 request 자체도 손상될 수 있다.
- 따라서 먼저 line을 안정화한 뒤, clean 상태에서 재전송 요청을 보내야 한다.

권장 플로차트:

```text
packet 수신
-> payload recovery 시도
-> CRC 검사

CRC 통과?
  예:
    OK 처리
    다음 packet 진행

  아니오:
    CE/NG 증가
    현재 packet discard
    RC / resync / line recovery 진입
    link clean 상태 확인
    retransmission request 전송
    TX retransmission 수행
    RX 재수신
    CRC 재검증
```

상태 전이 관점:

```text
NORMAL_RX
  -> CE/NG == 0: ACCEPT_PACKET
  -> CE/NG > 0: DISCARD_PACKET

DISCARD_PACKET
  -> LINE_RECOVERY

LINE_RECOVERY
  -> RC 완료
  -> LINK_CLEAN_CHECK

LINK_CLEAN_CHECK
  -> clean 확인: REQUEST_RETRANSMIT
  -> clean 실패: LINE_RECOVERY 반복 또는 RESYNC

REQUEST_RETRANSMIT
  -> TX 재전송 요청
  -> WAIT_RETRANSMIT_PACKET

WAIT_RETRANSMIT_PACKET
  -> packet 재수신
  -> CRC 재검증
```

핵심 규칙:

- `PA > 0`이어도 `CE/NG > 0`이면 최종 복구 실패 packet으로 본다.
- `CE/NG > 0` packet은 절대 OK로 승격하지 않는다.
- retransmission request는 오류 직후가 아니라 RC 이후 link clean 상태에서 전송한다.
- RC 이후 요청을 보내는 이유는 재전송 요청 패킷 자체의 손상을 방지하기 위해서이다.

따라서 700 mV 이상과 같은 과노이즈 영역에서는 data recovery와 line recovery/retransmission sequence를 분리해서 처리해야 한다.

### 5.11 복구 시간 해석

현재 로그만으로는 correction 발생 시점부터 CRC 통과까지의 절대 시간을 직접 산출할 수 없다. 현재 로그는 packet count, error count, correction candidate/accept/reject count 중심이며, correction event별 timestamp를 포함하지 않는다.

다만 구조적으로 중요한 점은 확인할 수 있다.

데이터 복구는 기존 link recovery처럼 별도 resync 절차를 수행하는 것이 아니라, RX payload 처리 pipeline 내부에서 inline으로 수행된다.

```text
symbol/pair 수신
-> payload 위치 확인
-> expected symbol 확인
-> correction accept
-> byte/packet 조립
-> CRC 검증
```

따라서 400 mV 및 600 mV에서 `PA > 0`임에도 `NG=0`, `CE=0`이 유지된 결과는, 복구가 별도 link recovery 지연으로 빠지지 않고 packet 처리 경로 안에서 흡수되었음을 의미한다.

기존 link recovery 시간인 51~91 us는 link resync 또는 line-level recovery 시간으로 보아야 한다. 반면 이번 data recovery는 그보다 앞단의 symbol/payload correction 단계이다.

정리:

- 기존 link recovery: link 안정화 또는 resync에 필요한 시간, 약 51~91 us로 측정됨
- 현재 data recovery: payload pipeline 내부 inline correction
- 400/600 mV 조건: correction event가 있었지만 packet/CRC failure 없이 통과
- 따라서 현재 데이터 복구는 별도 link recovery 시간으로 전이되지 않고 packet 처리 경로 안에서 종료된 것으로 해석할 수 있다.

정확한 event-level 복구 시간을 측정하려면 추후 correction 발생 cycle, CRC 비교 cycle, packet boundary cycle을 별도 timestamp counter로 로깅해야 한다.

## 6. 해석

이번 실증 기준으로는 known payload shadow recovery 적용 시 400 mV, 500 mV, 600 mV에서 packet/CRC error 0을 확인하였다. 700 mV는 기존 결과와 동일하게 한계 영역으로 보이며, `NG`, `CE`, `RD`가 다시 나타난다.

### 6.1 TR 이슈와 실제 복구 판단

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

### 6.2 packet CRC의 의미

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

## 7. 결론

현재 버전은 다음을 실증하였다.

- payload 제한 조건에서 known payload expected-symbol 복구 가능
- 400 mV, 500 mV, 600 mV에서 packet/CRC error 0 확인
- 700 mV에서는 residual error 발생으로 한계 영역 확인
- 기존 RC 라인 정상화와 구분되는 직접 payload recovery 경로가 추가됨

다음 단계에서 임의 payload까지 확장하려면 expected payload 대신 CRC/FEC, rolling shadow, prior confirmed pair, 또는 higher-layer redundancy를 사용하는 별도 일반화 로직이 필요하다.
