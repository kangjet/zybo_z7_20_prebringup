# Result Capture Template (for scoreboard bridge)

보드 측 출력 데이터를 아래 형식으로 변환하면 `fpga_validation_pkg_v1` scoreboard에 바로 연결할 수 있다.

## cosine

```text
t,tiles,cosine_fpga,valid
0,8,0.9983,1
1,8,0.9971,1
...
```

## denom

```text
t,tiles,denom_fpga,valid
0,8,1.0002,1
1,8,0.9998,1
...
```

## logit

```text
t,tiles,logp_fpga,valid
0,8,-1.248,1
1,8,-1.251,1
...
```

## 규칙

- `t`: 0부터 시작하는 연속 정수
- `tiles`: 8/16/64 중 실제 값
- `valid`: 유효 샘플 `1`, 버릴 샘플 `0`
- fixed-point라면 변환 시 스케일 정보를 함께 기록
