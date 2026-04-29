# PAM4 1k/2k 정속 및 Noise 주입 테스트 결과

작성일: 2026-04-29
작업 repo: C:\zybo_z7_20_prebringup
기준 커밋: 23167e1 Record PAM4 slow-mode soak

## 목적

새로 준비한 저항으로 PAM4 resistor-DAC를 낮은 임피던스로 재구성하고, 정속 1 us/level 조건에서 analog node settling과 W1 noise 주입 반응을 확인했다.

## 고정 연결

PAM4 DAC:

```text
TX JD2 / MSB ---- 1 kOhm ----+
                             +---- PAM4 analog node ---- AD3 CH1+
TX JD1 / LSB ---- 2 kOhm ----+

AD3 CH1- / GND -------------- board GND
AD3 GND --------------------- board GND
```

Noise injection:

```text
AD3 W1 ---- 1 kOhm ---- PAM4 analog node
AD3 GND --------------- board GND
```

주의:

- CH1/CH2는 Scope 입력이다.
- W1/W2가 Wavegen 출력이다.
- Noise 주입은 W1 출력 단자에서 직렬 저항을 통해 PAM4 analog node로 연결해야 한다.
- Offset은 0 V로 고정한다.

## TX/RX 조건

TX:

- `top_pam4_baseline_tx_board`
- `SYMBOL_HOLD_CLKS=125`
- 125 MHz 기준 약 1 us/level
- 패턴: `00 -> 01 -> 10 -> 11 -> 반복`

RX:

- `top_pam4_baseline_rx_board`
- 안정화 샘플링 monitor
- RX는 analog node가 아니라 JD1/JD2 digital line을 직접 검사한다.

TX 재빌드/로딩 결과:

- `PAM4 SYMBOL_HOLD_CLKS=125` 확인
- Synthesis log: `SYMBOL_HOLD_CLKS bound to: 125`
- Bitgen completed successfully
- DRC: 0 errors
- Route timing estimate: WNS 3.423 ns, TNS 0.000 ns
- TX board program 완료

## 1k/2k slow-mode 사전 확인

정속 복귀 전, 기존 slow mode 상태에서 1 kOhm / 2 kOhm DAC 4레벨을 확인했다.

관측:

- Low: 약 19.7 mV
- High: 약 3.344 V
- Delta: 약 3.325 V
- 중간 레벨 약 1.1 V / 2.2 V 분리 확인

판정:

- 1 kOhm / 2 kOhm DAC 연결 정상
- 기존 10 kOhm / 20 kOhm 대비 analog node가 더 단단하게 잡힘

## 정속 1 us/level baseline

정속 1 us/level로 TX를 재빌드/로딩한 뒤 analog node를 확인했다.

관측:

- 4레벨 `0 V / 1.1 V / 2.2 V / 3.3 V` 분리 확인
- 기존 10 kOhm / 20 kOhm 조건처럼 완전한 톱니 형태로 무너지지 않음
- 전이 후 RC settling은 보이나, 각 심볼 중앙부 plateau가 형성됨

RX 확인:

초기 TX 재로딩 직후 RX reset 전에는 `NG=00000003`이 관측됐으나 더 증가하지 않았다. RX reset 후에는 `NG=00000000` 유지가 확인됐다.

RX reset 후 확인 로그:

```text
PAM4RX OK=0112A889 NG=00000000 C=3
PAM4RX OK=0121EAC9 NG=00000000 C=3
PAM4RX OK=01312D0A NG=00000000 C=0
PAM4RX OK=01406F4A NG=00000000 C=0
PAM4RX OK=014FB18B NG=00000000 C=1
PAM4RX OK=015EF3CB NG=00000000 C=1
PAM4RX OK=016E360C NG=00000000 C=2
PAM4RX OK=017D784C NG=00000000 C=2
PAM4RX OK=018CBA8D NG=00000000 C=3
PAM4RX OK=019BFCCD NG=00000000 C=3
PAM4RX OK=01AB3F0D NG=00000000 C=3
PAM4RX OK=01BA814E NG=00000000 C=0
PAM4RX OK=01C9C38E NG=00000000 C=0
PAM4RX OK=01D905CF NG=00000000 C=1
PAM4RX OK=01E8480F NG=00000000 C=1
PAM4RX OK=01F78A50 NG=00000000 C=2
PAM4RX OK=0206CC90 NG=00000000 C=2
PAM4RX OK=02160ED1 NG=00000000 C=3
PAM4RX OK=02255111 NG=00000000 C=3
PAM4RX OK=02349352 NG=00000000 C=0
```

판정:

- 1 kOhm / 2 kOhm DAC + 정속 1 us/level PAM4 baseline 정상
- RX reset 후 `NG=00000000` 유지

## W1 Noise 주입 확인

초기 혼동:

- AD3의 CH1/CH2는 입력이고, W1/W2가 Wavegen 출력이다.
- W1 출력 단자가 아니라 Scope 입력 쪽을 연결하면 noise가 주입되지 않는다.
- W1 출력 단자를 확인한 뒤 noise 주입 경로가 정상 동작함을 확인했다.

Wavegen 설정:

- Type: Noise
- Frequency: 10 kHz
- Offset: 0 V
- Amplitude sweep: 100 mV, 200 mV, 500 mV
- 1 V 이상 offset은 사용하지 않음. Offset은 0 V 고정.

결과 요약:

| 조건 | 관측 | RX |
| --- | --- | --- |
| Base / no intentional noise | 1 us/level 4레벨 유지 | reset 후 `NG=0` |
| W1 noise 100 mV | analog node에 baseline wander/저주파 변조 관측, 4레벨 구조 유지 | `NG=0` |
| W1 noise 200 mV | 흔들림 증가, 4레벨 구조 유지 | `NG=0` |
| W1 noise 500 mV | 강한 변조 관측, 레벨이 위/아래로 크게 이동, 4레벨 구조는 유지 | `NG=0` |

첨부 이미지:

- `pam4_base.png`
- `pam4_noise_100mV.png`
- `pam4_noise_200mV.png`
- `pam4_noise_500mV.png`

## 해석

확인된 사실:

- 1 kOhm / 2 kOhm PAM4 resistor-DAC는 정속 1 us/level에서 기존 10 kOhm / 20 kOhm 대비 settling이 개선됐다.
- W1 -> 1 kOhm -> PAM4 analog node 경로로 noise가 실제 주입됨을 확인했다.
- 100 mV ~ 500 mV noise 주입에서도 analog node의 4레벨 구조는 유지됐다.
- RX digital monitor는 `NG=0`을 유지했다.

제한:

- 현재 RX는 analog node를 디코딩하지 않는다.
- RX는 JD1/JD2 digital line을 직접 검사하므로, analog node noise가 RX `NG`로 직접 이어지지 않는 것이 정상이다.
- 따라서 이 결과는 analog node 관측 기준의 noise 주입/레벨 유지 결과이며, analog PAM4 BER margin 결과는 아니다.

## 현재 판정

현재 단계 통과:

- 1 kOhm / 2 kOhm DAC 정속 1 us/level baseline
- W1 1 kOhm injection 경로 확인
- 100 mV / 200 mV / 500 mV noise 주입 시 analog node 4레벨 구조 유지
- RX digital monitor `NG=0` 유지

다음 단계 후보:

1. Persistence/histogram으로 100 mV / 200 mV / 500 mV 조건의 레벨 분산 정량 기록
2. 필요 시 1 V amplitude까지 단기 관측하되, node가 0 V 아래/3.3 V 위로 크게 벗어나면 중단
3. analog RX 경로 설계
   - XADC
   - 외부 comparator threshold 3개
   - 외부 ADC

## 메모

현재 실험에서 중요한 기준:

- Amplitude sweep을 수행한다.
- Offset은 0 V 고정한다.
- W1은 반드시 W1 출력 단자에서 인출한다.
- CH1은 PAM4 analog node 측정용 입력이다.
