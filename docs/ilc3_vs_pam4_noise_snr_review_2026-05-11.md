# ILC3 vs PAM4 noise comparison, SNR proxy, and review - 2026-05-11

## Scope

This note summarizes the final 2026-05-11 comparison state between:

- PAM4 LMV339 analog comparator test
- ILC3 analog-comparison TX/RX using the same PAM4-style two-pin resistor-DAC analog path

The comparison target is the PAM4 analog/noise robustness condition. It is not the original ILC3 digital PMOD packet-link result.

User notation:

```text
500 mHz = 0.5 Hz
```

## PAM4 reference condition

Final PAM4 comparison baseline used during the session:

```text
TX analog full scale ~= 320-330 mV
input+              ~= 183 mV
TH0                 ~= 102-107 mV
TH1                 ~= 168-174 mV
TH2                 ~= 238-243 mV
```

Measured PAM4 analog levels from scope captures:

```text
LV0 ~=   0 mV
LV1 ~= 106 mV
LV2 ~= 210-215 mV
LV3 ~= 320 mV
```

Final PAM4 low-frequency noise result:

```text
500 mHz: 525 mV = pass-warning, 540 mV = fail
1 Hz:    525 mV = pass-warning, 540 mV = fail

Practical PAM4 fail boundary ~= 530-540 mV source setting
```

The observed PAM4 failure was `QN` onset while `WI` stayed zero. That means the failure was not an invalid thermometer-code failure.

## ILC3 analog-comparison condition

The original ILC3 TX was not used for final comparison because it drove a different interface. A dedicated ILC3 analog-comparison TX/RX was used instead.

Current ILC3 analog-comparison RX field meaning:

```text
W0/W1/W3/W7 = dwell counts in valid comparator bands
WI          = invalid thermometer/order state
QW          = warning / margin indicator
QN          = analog-level fail / invalid-state counter
R/A         = raw/accepted display only, not packet expected-vs-actual NG
```

Important correction made during the session:

```text
W1 is now counted.
The attempted frame/preamble expected checker was rejected because it produced false NG in clean state.
The final RX state is an analog level robustness monitor, not a frame BER checker.
```

Clean ILC3 checks after correction:

```text
W0/W1/W3/W7 all active
WI = 00000000
QW = 00000000
QN = 00000000
```

Recorded ILC3 threshold / node notes:

```text
TH0 ~= 110 mV
TH2 ~= 243-246 mV
input+ observed around 181-184 mV in one clean check
TX analog node was observed around 195 mV in one ILC3 mapping check
Scope span also showed about 310 mV in another ILC3 capture
```

Because the measured ILC3 analog scale varied between captures, the robust comparison should primarily use the same source-noise setting and threshold condition, then state the analog-scale caveat.

## ILC3 noise sweep result

Latest ILC3 noise injection result:

```text
500 mHz / 990 mV:
  WI = 00000000
  QW = 00000000
  QN = 00000000
  Result = PASS

1 Hz ~ 5 Hz / 990 mV:
  WI = 00000000
  QW = 00000000
  QN = 00000000
  Result = PASS
```

Interpretation:

```text
ILC3 did not reach the fail boundary up to the tested source-noise limit of 990 mV.
Therefore the ILC3 fail boundary is >990 mV under the recorded condition.
```

Do not test above 1 V unless the hardware limit is explicitly re-checked. The useful comparison is already available at the safe upper limit.

## Source-referred SNR proxy

Formal SNR cannot be computed exactly from the current data because the actual injected noise amplitude at the analog node was not measured as RMS.

The available value is a source-referred noise tolerance comparison:

```text
PAM4 fail boundary ~= 540 mV source setting
ILC3 no-fail lower bound = 990 mV source setting
```

Noise-source tolerance ratio:

```text
990 / 540 = 1.833
20 * log10(1.833) = 5.26 dB
```

Using the lower PAM4 boundary estimate:

```text
990 / 530 = 1.868
20 * log10(1.868) = 5.43 dB
```

Conservative statement:

```text
ILC3 source-noise tolerance is at least +5.3 dB higher than PAM4 under the current comparison setup.
```

This is a lower bound because ILC3 did not fail at 990 mV.

## Source-referred signal/noise examples

These are not formal SNR values. They are only source-referred ratios using Wavegen amplitude as the noise quantity.

PAM4 at fail boundary:

```text
Signal full scale ~= 320 mV
Noise source at fail ~= 540 mV
20 * log10(320 / 540) = -4.5 dB
```

ILC3 at tested pass condition, if using 310 mV scope span:

```text
Signal span ~= 310 mV
Noise source pass point = 990 mV
20 * log10(310 / 990) = -10.1 dB
```

ILC3 at tested pass condition, if using 195 mV analog-node note:

```text
Signal span ~= 195 mV
Noise source pass point = 990 mV
20 * log10(195 / 990) = -14.1 dB
```

These values show that ILC3 stayed valid even when the source-noise setting was much larger than the observed signal span. They do not replace a real node-noise RMS SNR measurement.

## Review: possible mistakes or weak assumptions

### 1. `500 MHz` vs `500 mHz`

Some notes/log labels used `500mhz`. In this test context the intended value is:

```text
500 mHz = 0.5 Hz
```

It must not be interpreted as 500 MHz.

### 2. `QN=0` is not packet BER

Current ILC3 RX is an analog level monitor. `QN=0` means the comparator level decode did not enter the invalid/fail condition.

It does not mean:

```text
packet BER = 0
frame decode perfect
full ILC3 protocol recovered
```

For packet BER, the RX would need a reliable TX symbol clock / strobe / framing reference.

### 3. `R/A` mismatch is not the current NG criterion

Current `R/A` fields are raw and accepted display states. They are useful diagnostics but not the pass/fail basis.

Current pass/fail basis:

```text
WI > 0 or QN > 0 -> fail
QW only          -> warning
WI=0 and QN=0   -> analog-level pass
```

### 4. ILC3 analog scale changed between captures

ILC3 analog node was reported around 195 mV in one capture and about 310 mV span in another scope view.

This does not invalidate the `QN=0 at 990 mV` observation, but it means the report should state the exact analog scale for each run. For a strict normalized comparison, re-measure:

```text
TX analog min/max
input+
TH0
TH2
noise source amplitude
injection resistor
```

### 5. Formal SNR still requires node-noise measurement

To compute real SNR, measure actual node noise while noise is ON:

```text
SNR = 20 * log10(signal_RMS / noise_RMS)
```

The current calculation is source-referred only:

```text
source noise setting at fail/pass boundary
```

### 6. ILC3 boundary is not found yet

ILC3 passed at 990 mV. Therefore the result is:

```text
ILC3 boundary > 990 mV
```

It is not correct to write:

```text
ILC3 boundary = 990 mV
```

## Current conclusion

Under the current analog comparison setup:

```text
PAM4 practical fail boundary ~= 530-540 mV source noise
ILC3 tested pass point       = 990 mV source noise
ILC3 lower-bound advantage   > +5.3 dB source-referred
```

This supports the claim that the ILC3 analog-comparison path is more robust than the PAM4 comparator path under the tested low-frequency noise injection condition.

The claim should be limited to analog level robustness, not protocol BER, until a synchronized ILC3 frame checker is implemented.

