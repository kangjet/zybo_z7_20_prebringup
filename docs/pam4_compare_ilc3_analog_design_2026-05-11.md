# PAM4 comparison ILC3 analog design - 2026-05-11

## Purpose

The comparison target is the PAM4 LMV339 analog test condition, not the existing ILC3 PMOD digital-bus link.

The existing ILC3 TX bitstream drives a 4-bit signed amplitude bus:

- `ilc3_amp[3:0]`
- `-1 = 4'b1111`
- `0 = 4'b0000`
- `+1 = 4'b0001`

That output is not compatible with the PAM4 two-pin resistor-DAC analog node used during the PAM4 noise-margin measurements.

## Baseline To Match

PAM4/LMV339 comparison baseline observed on 2026-05-11:

- TX analog full scale: about `320-330 mV`
- Input+: about `181-184 mV`
- Thresholds after settling: about `TH0=104-107 mV`, `TH2=241-243 mV`
- PAM4 analog node levels from the scope:
  - LV0: about `0 mV`
  - LV1: about `106 mV`
  - LV2: about `210-215 mV`
  - LV3: about `320 mV`

The ILC3 comparison design must therefore use the same:

- TX board
- RX board
- JD1/JD2 resistor-DAC analog node
- LMV339 comparator path
- Noise injection point
- UART log layout

## TX Mapping

The ILC3 analog-comparison TX converts ILC3 ternary samples to the same two-pin PAM4 resistor-DAC node.

ILC3 core sample mapping:

| ILC3 sample | Meaning | PAM4 resistor-DAC code | Expected analog level |
|---|---|---|---|
| `-1` | low | `00` | about `0 mV` |
| `0` | middle | `01` | between `TH0` and `TH2` |
| `+1` | high | `10` | about `316-330 mV` |

Reason:

- `TH0 ~= 107 mV` separates low from middle.
- `TH2 ~= 243 mV` separates middle from high.
- Initial `0 -> 10`, `+1 -> 11` mapping was rejected on hardware because it produced about `316 mV` and `466 mV`, putting the ILC3 zero state above `TH2`.
- Revised `0 -> 01`, `+1 -> 10` keeps the zero state inside the `TH0..TH2` decision window and keeps the positive state above `TH2`.

## RX Decode

The RX comparison monitor uses LMV339 outputs:

- `cmp_in[0]`: TH0 comparator output
- `cmp_in[1]`: TH1 comparator output
- `cmp_in[2]`: TH2 comparator output

Decode rule:

| TH2 | TH1 | TH0 | log bucket | meaning |
|---|---|---|---|---|
| 0 | 0 | 0 | `W0` | below TH0 |
| 0 | 0 | 1 | `W1` | TH0..TH1 band |
| 0 | 1 | 1 | `W3` | TH1..TH2 band |
| 1 | 1 | 1 | `W7` | above TH2 |
| other | other | other | `WI/QN` | invalid thermometer ordering |

Important 2026-05-11 correction:

```text
W1 is counted in the final RX.
An attempted frame/preamble expected checker was rejected because it produced false NG in clean state.
The current RX is an analog level robustness monitor, not a protocol BER checker.
```

The RX monitor logs in the same field shape as the PAM4 comparator monitor:

```text
ILC3Q W W0=XXXXXXXX W1=XXXXXXXX W3=XXXXXXXX W7=XXXXXXXX WI=XXXXXXXX QW=XXXXXXXX QN=XXXXXXXX R=X A=X
```

Field meaning:

- `W0`: low-state dwell count
- `W1`: dwell count in the TH0..TH1 band
- `W3`: dwell count in the TH1..TH2 band
- `W7`: dwell count above TH2
- `WI`: invalid thermometer/order dwell count
- `QW`: quality warning count / reserved warning counter
- `QN`: invalid-state fail counter
- `R`: raw synthetic thermometer-like code
- `A`: accepted synthetic thermometer-like code

Synthetic codes are chosen to preserve visual compatibility with PAM4 logs:

- below TH0: `0`
- TH0..TH1: `1`
- TH1..TH2: `3`
- above TH2: `7`
- invalid: any non-thermometer combination

## Test Procedure

1. Load `top_ilc3_analog_compare_tx_board.bit` on TX.
2. Load `top_ilc3_analog_compare_rx_board.bit` on RX.
3. Keep Wavegen/noise off.
4. Confirm the analog node uses the same PAM4 resistor-DAC path:
   - JD1/T14 -> PAM4 LSB resistor path
   - JD2/T15 -> PAM4 MSB resistor path
5. Confirm analog node levels:
   - low around `0 mV`
   - middle around `210 mV`
   - high around `320 mV`
6. Confirm clean baseline:
   - `WI=00000000`
   - `QN` not increasing
7. Run the same noise sweep as PAM4:
   - `500 mHz / 300 mV`
   - `500 mHz / 350 mV`
   - `500 mHz / 400 mV`
   - `500 mHz / 500 mV`
   - `500 mHz / 525 mV`
   - `500 mHz / 540 mV`
   - repeat at `1 Hz` around the boundary

## Comparison Rule

Use the source-noise fail boundary for comparison:

- PAM4/LMV339 current boundary: about `525-540 mV`
- ILC3 analog-comparison boundary: to be measured under the same wiring and thresholds

Do not compare against the old ILC3 four-bit PMOD digital-bus result. That result uses a different physical interface and is not an analog-noise tolerance comparison.
