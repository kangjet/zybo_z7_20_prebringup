# ILC3 데이터 복구 테스트 관련 파일 정리

작성일: 2026-06-05

## 1. 목적

ILC3 직접 데이터 복구 테스트에서 어떤 파일이 실제 복구 로직을 담당하고, 어떤 파일이 테스트 top 또는 호환 wrapper 역할을 하는지 구분하기 위한 파일 맵이다.

현재 커밋 기준:

- branch: `ilc3-pr-direct-recovery-test`
- commit: `acf6788 Add ILC3 known-payload shadow recovery`

## 2. 핵심 RTL 파일

### `rtl/ilc3_core/ilc3_rx_core.v`

역할: ILC3 RX core 본체.

이번 데이터 복구 테스트에서 가장 중요한 변경 파일이다.

추가/변경된 기능:

- `pair_correct_allow`
- `pair_correct_expected_valid`
- `pair_correct_expected_sym`
- `pair_correct_lm_evidence`
- `pair_correct_hm_evidence`
- `pair_correct_force_expected`
- `PC/PA/PJ/PL` 계열 correction debug counter

현재 최종 구조:

- payload 영역에서 invalid pair가 검출되면 expected symbol을 기준으로 shadow recovery 수행
- known payload test pattern에서만 직접 데이터 복구 실증 가능
- preamble/header/meta/CRC 영역은 복구 대상에서 제외

주의:

- 현재 구조는 임의 payload general recovery가 아니라 deterministic payload 기반 shadow recovery이다.
- general data recovery로 확장하려면 CRC/FEC, rolling shadow, prior confirmed pair, side information 등이 추가로 필요하다.

## 3. 직접 테스트 대상 top

### `rtl/top_ilc3_txref_histogram_recovery_rx_board.v`

역할: 이번 직접 데이터 복구 테스트의 실제 RX board target top.

이번 테스트에서 사용하는 핵심 top이다.

주요 역할:

- `expected_byte_no_crc(byte_idx, seq_rx)`로 expected payload byte 생성
- `sym_in_byte`에 따라 expected symbol 선택
- payload 영역에서만 `pair_correct_allow_w` 활성화
- `pair_correct_force_expected_w = pair_correct_allow_w`로 known-payload shadow recovery 활성화

보호 조건:

- `need_resync == 0`
- `tag_pending == 0`
- `packet_bad == 0`
- `pkt_byte_err == 0`
- `byte_idx`가 payload 범위 내부
- CRC 구간 제외

이 top을 기준으로 400 mV, 600 mV, 700 mV 테스트를 수행하였다.

## 4. 호환 연결용 wrapper/top 파일

아래 파일들은 `ilc3_rx_core.v`의 포트가 확장되면서 기존 top들이 깨지지 않도록 새 입력을 명시적으로 연결한 파일이다.

### `rtl/ilc3_core/ilc3_ipcore_top.v`

역할: IP core wrapper.

이번 테스트에서는 직접 복구 target이 아니며, 새 포트는 기본 비활성 값으로 연결한다.

### `rtl/top_ilc3_accuracy_rx_board.v`

역할: accuracy RX board top.

새 correction 포트 호환 연결만 반영.

### `rtl/top_ilc3_histogram_tag_packet256_rx_board.v`

역할: histogram TAG packet256 RX top.

새 correction 포트 호환 연결만 반영.

### `rtl/top_ilc3_histogram_tag_self_correct_rx_board.v`

역할: histogram TAG self-correct RX top.

새 correction 포트 호환 연결만 반영.

### `rtl/top_ilc3_packet256_rx_board.v`

역할: packet256 RX top.

새 correction 포트 호환 연결만 반영.

### `rtl/top_ilc3_rx_board.v`

역할: 기본 ILC3 RX board top.

새 correction 포트 호환 연결만 반영.

주의:

- 위 wrapper/top들은 이번 known-payload shadow recovery를 직접 활성화하지 않는다.
- `pair_correct_force_expected`는 기본적으로 `1'b0`로 연결되어 기존 동작을 유지한다.

## 5. Vivado TCL 파일

### `tcl/create_project_ilc3_txref_histogram_recovery_rx.tcl`

역할: txref histogram recovery RX 프로젝트 생성용 TCL.

### `tcl/run_impl_ilc3_txref_histogram_recovery_rx.tcl`

역할: synthesis/implementation/bitstream 생성 실행 TCL.

사용 목적:

- 이번 패치 후 bitstream 생성에 사용
- 최종 known-payload shadow recovery 패치 후 build 성공 확인

### `tcl/program_ilc3_txref_histogram_recovery_rx_board.tcl`

역할: RX board bitstream programming TCL.

사용 목적:

- build 완료 후 board programming에 사용
- 최종 패치 적용 후 실제 RX board에 programming 완료

## 6. 결과 정리 문서

### `docs/ilc3_direct_recovery_test_2026-06-05.md`

역할: 직접 데이터 복구 패치 및 실증 결과 정리 문서.

포함 내용:

- baseline 결과
- 400 mV 결과
- 600 mV 결과
- 700 mV 한계 결과
- `PK/OK/NG/CE/DF/RC/RD/LM/HM/MM/PR/PC/PA/PJ/PL` 용어 정의
- known-payload shadow recovery의 의미와 한계

## 7. 테스트 결과 기준 요약

### baseline

- `OK = PK`
- `NG = 0`
- `CE = 0`
- `RD = 0`

### 400 mV

- long-run packet/CRC error 0
- `PK=00034878`
- `PA=0000CE40`

### 600 mV

- long-run packet/CRC error 0
- `PK=000471E9`
- `PA=00005AFB`

### 700 mV

- residual error 발생
- `PK=0001585E`
- `NG=00000014`
- `CE=00000014`
- packet error rate 약 0.0227 %

## 8. 혼동 방지 포인트

- `ilc3_rx_core.v`: 복구 기능의 실제 구현 위치
- `top_ilc3_txref_histogram_recovery_rx_board.v`: 이번 실증에서 복구 기능을 실제로 활성화한 top
- 다른 top/wrapper 파일: 새 port 연결을 맞춘 호환 수정
- TCL 파일: build/program 흐름
- `docs/ilc3_direct_recovery_test_2026-06-05.md`: 실험 결과 해석 문서

현재 버전의 핵심 결론은 다음과 같다.

- known payload 조건에서는 payload 직접 복구가 실증되었다.
- 600 mV까지 packet/CRC error 0을 확인하였다.
- 700 mV는 한계 영역으로 residual error가 남는다.
- 임의 payload 일반 복구는 다음 단계의 별도 설계 항목이다.
