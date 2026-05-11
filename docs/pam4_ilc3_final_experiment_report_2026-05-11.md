# PAM4 vs ILC3 final analog-noise comparison report - 2026-05-11

## Executive summary

The 2026-05-11 experiment compared PAM4 and ILC3 under the same PAM4-style analog test path:

```text
TX two-pin resistor-DAC analog node -> LMV339 comparator thresholds -> RX monitor
```

The target claim was:

```text
ILC3 has at least +3 dB noise-margin / SNR-related advantage over PAM4.
```

Result:

```text
PAM4 boundary at 500 mHz was around 540-550 mV source-noise injection.
ILC3 stayed QN/WI clean up to 1.65 V source-noise injection.

1650 / 550 = 3.0
20log10(3.0) = 9.54 dB
```

Conclusion:

```text
The +3 dB target is satisfied with margin.
The measured result supports at least +9.5 dB source-referred noise-tolerance advantage for ILC3.
```

Important wording:

```text
Correct: ILC3 fail boundary is above 1.65 V.
Incorrect: ILC3 fail boundary is exactly 1.65 V.
```

This conclusion is for analog level robustness. It is not a protocol BER result.

## Test purpose

The purpose was to compare PAM4 and ILC3 fairly under the same analog front-end condition.

The original ILC3 TX/RX packet link was not a fair comparison target because it used a different physical output format. Therefore a dedicated ILC3 analog-comparison TX/RX was created.

Comparison target:

```text
PAM4 analog node and LMV339 comparator condition
```

Not the comparison target:

```text
Original ILC3 digital PMOD packet OK/NG link
```

## Frequency notation

User bench notation:

```text
500 mHz = 0.5 Hz
```

Do not interpret `500mHz` in these notes as 500 MHz.

## Hardware / measurement setup

Common analog path:

```text
TX board resistor-DAC output
JD1/JD2 two-pin PAM4-style analog path
Noise injection into analog path
LMV339 comparator threshold inputs
RX board comparator monitor
UART log capture
```

PAM4 reference threshold region used for the final comparison:

```text
TX analog full scale ~= 320-330 mV
input+              ~= 183 mV
TH0                 ~= 102-107 mV
TH1                 ~= 168-174 mV
TH2                 ~= 238-243 mV
```

PAM4 analog levels from scope captures:

```text
LV0 ~=   0 mV
LV1 ~= 106 mV
LV2 ~= 210-215 mV
LV3 ~= 320 mV
```

ILC3 analog comparison condition recorded during the session:

```text
TH0 ~= 110 mV
TH2 ~= 243-246 mV
input+ ~= 181-184 mV in clean comparison checks
TX analog node was observed around 195 mV in one ILC3 mapping check
Another ILC3 scope span showed about 310 mV
```

The analog-scale variation should be recorded with each future run. It does not invalidate this comparison because the result is stated as a source-noise tolerance lower bound.

## Files / bitstreams used

### ILC3 analog-comparison TX

Source files:

```text
rtl/top_ilc3_analog_compare_tx_board.v
constraints/ilc3_analog_compare_tx_board.xdc
tcl/create_project_ilc3_analog_compare_tx.tcl
tcl/build_ilc3_analog_compare_tx_impl.tcl
tcl/program_ilc3_analog_compare_tx_board.tcl
```

Bitstream:

```text
build/vivado_ilc3_analog_compare_tx/ilc3_analog_compare_tx.runs/impl_1/top_ilc3_analog_compare_tx_board.bit
```

Purpose:

```text
Drive ILC3 symbols onto the same two-pin PAM4 resistor-DAC analog path.
```

Current TX mapping:

| ILC3 sample | resistor-DAC code | intended analog state |
|---:|---|---|
| -1 | `00` | below TH0 |
| 0 | `01` | between TH0 and TH2 |
| +1 | `10` | above TH2 |

Rejected earlier mapping:

```text
0  -> 10
+1 -> 11
```

Reason rejected:

```text
It placed the ILC3 zero state too high, near or above TH2.
```

### ILC3 analog-comparison RX

Source files:

```text
rtl/top_ilc3_analog_compare_rx_board.v
constraints/ilc3_analog_compare_rx_board.xdc
tcl/create_project_ilc3_analog_compare_rx.tcl
tcl/build_ilc3_analog_compare_rx_impl.tcl
tcl/program_ilc3_analog_compare_rx_board.tcl
```

Bitstream:

```text
build/vivado_ilc3_analog_compare_rx/ilc3_analog_compare_rx.runs/impl_1/top_ilc3_analog_compare_rx_board.bit
```

Purpose:

```text
Monitor the LMV339 comparator outputs using the same PAM4-style W0/W1/W3/W7/WI/QW/QN log form.
```

Final RX state:

```text
W1 is counted.
Frame/preamble expected checker is disabled/rejected.
RX is analog level monitor, not protocol BER checker.
```

### PAM4 comparator reference RX

Reference files:

```text
rtl/top_pam4_comparator_rx_board.v
constraints/pam4_comparator_rx_board.xdc
tcl/create_project_pam4_comparator_rx.tcl
tcl/build_pam4_comparator_rx_impl.tcl
tcl/program_pam4_comparator_rx_board.tcl
```

Purpose:

```text
PAM4 LMV339 comparator baseline and noise-boundary measurement.
```

## UART / log data forms

### PAM4 comparator monitor form

Actual monitor line shape:

```text
PAM4Q W W0=XXXXXXXX W1=XXXXXXXX W3=XXXXXXXX W7=XXXXXXXX WI=XXXXXXXX QW=XXXXXXXX QN=XXXXXXXX R=X A=X
```

Example:

```text
PAM4Q W W0=01DD8AB0 W1=01CB7AC7 W3=01E45734 W7=01E5FC94 WI=00000000 QW=00000053 QN=00000018 R=3 A=3
```

Field meaning:

| Field | Meaning |
|---|---|
| `W0` | dwell count below TH0 |
| `W1` | dwell count in TH0..TH1 band |
| `W3` | dwell count in TH1..TH2 band |
| `W7` | dwell count above TH2 |
| `WI` | invalid thermometer/order state dwell count |
| `QW` | warning / margin indicator |
| `QN` | fail / NG counter used for boundary detection |
| `R` | raw code display |
| `A` | accepted code display |

### ILC3 analog-comparison RX form

Actual monitor line shape:

```text
ILC3Q W W0=XXXXXXXX W1=XXXXXXXX W3=XXXXXXXX W7=XXXXXXXX WI=XXXXXXXX QW=XXXXXXXX QN=XXXXXXXX R=X A=X
```

Example clean/noise-run line:

```text
ILC3Q W W0=01BA79CE W1=00E7ECF6 W3=02BEAA46 W7=02124835 WI=00000000 QW=00000000 QN=00000000 R=7 A=7
```

Field meaning:

| Field | Meaning |
|---|---|
| `W0` | below TH0 dwell count |
| `W1` | TH0..TH1 dwell count |
| `W3` | TH1..TH2 dwell count |
| `W7` | above TH2 dwell count |
| `WI` | invalid thermometer/order dwell count |
| `QW` | warning / reserved warning counter |
| `QN` | invalid/fail counter for analog monitor |
| `R` | raw display state |
| `A` | accepted display state |

Current pass/fail interpretation:

```text
WI > 0 or QN > 0 -> analog-level fail
QW only          -> warning / margin reduction
WI=0 and QN=0   -> analog-level pass
```

Important:

```text
QN=0 does not mean packet BER=0.
QN=0 means the analog comparator monitor did not see invalid/fail state.
```

### ILC3 analog-comparison TX form

TX status line shape from RTL:

```text
ILC3TX CNT=XXXXXXXX C=X
```

Field meaning:

| Field | Meaning |
|---|---|
| `CNT` | TX frame counter |
| `C` | current resistor-DAC code display |

### Original ILC3 packet-link form

Original packet TX/RX logs seen before the analog-compare path:

```text
TX PKT=001B2AAF S=AA550800 A=01010100
RX OK=00000184 NG=00026D4A F=000011554054050000000000
```

These are not the current analog-comparison pass/fail form.

Do not mix:

```text
Original ILC3 packet OK/NG
PAM4/ILC3 analog W0/W1/W3/W7/WI/QW/QN
```

## PAM4 result table

Final PAM4 comparison condition:

```text
500 mHz source-noise sweep
PAM4 TX analog full scale ~= 320-330 mV
Thresholds around TH0/TH1/TH2 ~= 104/172/241 mV
```

| Condition | Result | Interpretation |
|---:|---|---|
| 500 mHz / 500 mV | QN not newly increasing, QW increased | pass-warning |
| 500 mHz / 525 mV | QN not newly increasing, QW increased | pass-warning |
| 500 mHz / 540 mV | QN increased | fail |
| 500 mHz / 550 mV | treated as boundary/fail side in final discussion | fail boundary region |
| 1 Hz / 525 mV | QN clean, QW warning | pass-warning |
| 1 Hz / 540 mV | QN increased | fail |

PAM4 boundary:

```text
Practical fail boundary ~= 540-550 mV source-noise injection
```

The final conclusion uses the conservative `550 mV` PAM4 boundary for SNR-margin calculation.

## ILC3 result table

Final ILC3 analog-comparison condition:

```text
Dedicated ILC3 analog TX/RX loaded
Same PAM4-style resistor-DAC / LMV339 comparison path
W1 counted
QN/WI used as analog-level fail indicators
```

| Condition | Observed result | Interpretation |
|---:|---|---|
| Noise OFF | W0/W1/W3/W7 active, WI=0, QN=0 | clean baseline |
| 500 mHz / 990 mV | WI=0, QW=0, QN=0 | pass |
| 1 Hz ~ 5 Hz / 990 mV | WI=0, QW=0, QN=0 | pass |
| 500 mHz / 1.65 V | QN/WI boundary not found | pass up to tested limit |

ILC3 boundary:

```text
ILC3 fail boundary > 1.65 V source-noise injection
```

The actual ILC3 boundary was not reached.

## PAM4 vs ILC3 comparison table

| Item | PAM4 | ILC3 analog comparison |
|---|---:|---:|
| Physical comparison path | PAM4 resistor-DAC + LMV339 | same PAM4 resistor-DAC + LMV339 |
| RX log form | `PAM4Q W ...` | `ILC3Q W ...` |
| Primary fail indicator | `QN` onset | `QN` / `WI` onset |
| 500 mHz boundary | about 540-550 mV | not reached up to 1.65 V |
| Boundary statement | `~550 mV` | `>1.65 V` |
| Ratio using conservative PAM4 550 mV | 1.0x | `>3.0x` |
| Source-referred margin | 0 dB reference | `>+9.5 dB` |
| Protocol BER proven? | no | no |

## SNR / noise-margin calculation

The current experiment does not measure formal SNR because the actual injected noise RMS at the analog node was not measured.

Formal SNR would require:

```text
SNR = 20log10(signal_RMS / noise_RMS)
```

What this experiment provides:

```text
source-referred noise tolerance
```

Conservative comparison:

```text
PAM4 boundary = 550 mV
ILC3 lower-bound pass point = 1650 mV

ratio = 1650 / 550 = 3.0
gain  = 20log10(3.0) = 9.54 dB
```

Target check:

```text
Required for +3 dB:
10^(3/20) = 1.414x

PAM4 550 mV * 1.414 = 778 mV

ILC3 stayed clean up to 1650 mV.
1650 mV > 778 mV
```

Therefore:

```text
The target +3 dB advantage is verified with a lower-bound margin.
```

Safe final wording:

```text
Under the same PAM4-style resistor-DAC and LMV339 comparator setup,
PAM4 reached its practical QN boundary around 540-550 mV source-noise injection,
while ILC3 did not reach QN/WI failure up to 1.65 V source-noise injection.
This gives a source-referred noise-tolerance advantage of at least +9.5 dB,
which exceeds the target +3 dB margin.
```

## What is verified

Verified:

```text
ILC3 analog level monitor remained clean at a source-noise level far above the PAM4 fail boundary.
The +3 dB source-referred noise-tolerance target is exceeded.
The comparison uses the same PAM4-style analog path and comparator threshold concept.
```

Not verified:

```text
Formal SNR at the analog node
Packet BER
Exact ILC3 fail boundary
TX symbol sequence exact recovery at RX
```

Reason:

```text
The RX currently monitors analog level validity.
It does not compare received symbols against a phase-synchronized TX expected pattern.
```

## Review of possible mistakes

### 1. Boundary vs lower bound

Do not state:

```text
ILC3 boundary = 1.65 V
```

State:

```text
ILC3 boundary > 1.65 V
```

### 2. SNR wording

Do not state:

```text
Formal SNR improved by exactly 9.5 dB
```

State:

```text
Source-referred noise tolerance improved by at least 9.5 dB.
```

### 3. Packet correctness

Do not state:

```text
QN=0 means the ILC3 data was exactly decoded.
```

State:

```text
QN=0 means the analog level monitor stayed in valid comparator states.
```

### 4. Frequency notation

Do not read the test as MHz.

State:

```text
500 mHz = 0.5 Hz
```

### 5. Analog scale variation

Record exact analog scale for any future repeat:

```text
TX analog min/max
input+
TH0/TH1/TH2
noise source amplitude
injection resistor
frequency
```

## Final conclusion

The experiment can be closed for the stated objective.

Final conclusion:

```text
For the 2026-05-11 PAM4 vs ILC3 analog-noise comparison,
PAM4 reached its practical QN boundary around 540-550 mV at 500 mHz.
ILC3 did not reach a QN/WI boundary even with 1.65 V source-noise injection.

Therefore the ILC3 analog-comparison path has at least:

20log10(1650/550) = 9.54 dB

source-referred noise-tolerance advantage over PAM4.

This exceeds the original +3 dB target.
```

The result is valid as an analog robustness comparison. A separate synchronized checker is required only if the next goal is protocol BER or exact ILC3 symbol recovery.

