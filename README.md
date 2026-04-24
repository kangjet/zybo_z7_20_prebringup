# zybo_z7_20_prebringup

Zybo Z7-20 보드 도착 전, ILC3 IPCore를 Vivado에서 재현 가능하게 준비하는 최소 패키지다.

## 포함 내용

- `tools/stage_ilc3_rtl_from_zip.sh`: ILC3 RTL zip에서 필요한 코어 파일 추출
- `rtl/top_zybo_ilc3_prebringup.v`: Zybo용 합성 타깃 top wrapper (8-lane loopback smoke)
- `constraints/zybo_z7_20_template.xdc`: 보드 핀 매핑 템플릿
- `tcl/create_project.tcl`: Vivado 프로젝트 생성
- `tcl/run_synth.tcl`: synth + 리포트 자동 생성
- `tcl/run_impl.tcl`: impl + bitstream 자동 생성(보드 핀 반영 후)
- `docs/bringup_checklist.md`: 보드 도착 후 실행 체크리스트

## 빠른 사용

1. RTL 파일 스테이징
```bash
cd /Users/kangjet/ILC-4_CoPBit/CoPBit_Research/coda/fpga_validation_pkg_v1/zybo_z7_20_prebringup
./tools/stage_ilc3_rtl_from_zip.sh
```

2. Vivado synth 실행
```bash
vivado -mode batch -source tcl/run_synth.tcl
```

3. 보드 도착 후
- `constraints/zybo_z7_20_template.xdc`에 Zybo 실제 핀 매핑 반영
- impl/bitstream 실행
```bash
vivado -mode batch -source tcl/run_impl.tcl
```

## 주의

- 현재 top은 `ilc3_ipcore_x8_top.v`를 쓰지 않고, `ilc3_ipcore_top.v`를 lane별로 직접 인스턴스한다.
  - 이유: `ilc3_ipcore_x8_top.v`는 내부 `ilc3_channel_model.v`(랜덤 기반) 의존이 있어 FPGA 합성 경로로는 분리하는 것이 안전하다.
- 이 패키지는 "보드 전 준비" 목적이며, 실측 CSV 생성/scoreboard 연동은 보드 도착 후 체크리스트 기준으로 진행한다.
