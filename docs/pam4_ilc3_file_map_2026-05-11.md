# PAM4 / ILC3 analog comparison file map - 2026-05-11

## Purpose

This file lists the important files created or used during the 2026-05-11 PAM4 vs ILC3 analog-noise comparison work.

The main goal is to avoid mixing these three different test families:

```text
1. PAM4 LMV339 comparator baseline
2. ILC3 analog-comparison TX/RX using the PAM4 resistor-DAC path
3. Original ILC3 packet/digital PMOD link
```

The current comparison should use family 1 and family 2 only.

## Current source tree

Main hardware repository:

```text
C:\zybo_z7_20_prebringup
```

Session summary folder:

```text
C:\Users\kangmu\iCloudDrive\WIN TO MAC\5월11일_ilc3\pam4
```

## Files to load for the current ILC3 vs PAM4 analog comparison

### ILC3 analog-comparison TX

Source:

```text
rtl/top_ilc3_analog_compare_tx_board.v
constraints/ilc3_analog_compare_tx_board.xdc
tcl/create_project_ilc3_analog_compare_tx.tcl
tcl/build_ilc3_analog_compare_tx_impl.tcl
tcl/program_ilc3_analog_compare_tx_board.tcl
```

Generated bitstream:

```text
build/vivado_ilc3_analog_compare_tx/ilc3_analog_compare_tx.runs/impl_1/top_ilc3_analog_compare_tx_board.bit
```

Use:

```text
Load this on the TX board for the ILC3 analog comparison.
It drives the same two-pin PAM4 resistor-DAC analog path instead of the original ILC3 four-bit PMOD amplitude bus.
```

Important behavior:

```text
ILC3 sample -1 -> resistor-DAC code 00
ILC3 sample  0 -> resistor-DAC code 01
ILC3 sample +1 -> resistor-DAC code 10
```

Reason:

```text
The mapping keeps the ILC3 middle state between TH0 and TH2,
and keeps the high state above TH2.
```

Do not use the original ILC3 TX bitstream for the PAM4 analog comparison. It does not drive the same analog interface.

### ILC3 analog-comparison RX

Source:

```text
rtl/top_ilc3_analog_compare_rx_board.v
constraints/ilc3_analog_compare_rx_board.xdc
tcl/create_project_ilc3_analog_compare_rx.tcl
tcl/build_ilc3_analog_compare_rx_impl.tcl
tcl/program_ilc3_analog_compare_rx_board.tcl
```

Generated bitstream:

```text
build/vivado_ilc3_analog_compare_rx/ilc3_analog_compare_rx.runs/impl_1/top_ilc3_analog_compare_rx_board.bit
```

Use:

```text
Load this on the RX board for the ILC3 analog comparison.
It monitors the LMV339 comparator outputs and prints PAM4-like ILC3Q logs.
```

Current final RX interpretation:

```text
W0 = below TH0 dwell count
W1 = TH0..TH1 dwell count
W3 = TH1..TH2 dwell count
W7 = above TH2 dwell count
WI = invalid thermometer/order dwell count
QW = warning / reserved warning counter
QN = invalid-state fail counter
R  = raw display state
A  = accepted display state
```

Important limitation:

```text
This RX is an analog level robustness monitor.
It is not a protocol BER checker.
QN=0 means analog-level monitor pass, not packet BER=0.
```

### Program scripts for the current comparison

Program TX:

```powershell
& 'C:\AMDDesignTools\2025.2\Vivado\bin\vivado.bat' -mode batch -source 'C:\zybo_z7_20_prebringup\tcl\program_ilc3_analog_compare_tx_board.tcl'
```

Program RX:

```powershell
& 'C:\AMDDesignTools\2025.2\Vivado\bin\vivado.bat' -mode batch -source 'C:\zybo_z7_20_prebringup\tcl\program_ilc3_analog_compare_rx_board.tcl'
```

Target boards encoded in the scripts:

```text
TX JTAG target: Digilent/210351BE5C62A
RX JTAG target: Digilent/210351BE5D1FA
```

Avoid programming TX/RX in parallel because `hw_server` target access can collide.

## PAM4 comparator reference files

Source:

```text
rtl/top_pam4_comparator_rx_board.v
constraints/pam4_comparator_rx_board.xdc
tcl/create_project_pam4_comparator_rx.tcl
tcl/build_pam4_comparator_rx_impl.tcl
tcl/program_pam4_comparator_rx_board.tcl
```

Use:

```text
These are the PAM4 LMV339 comparator monitor files used for the PAM4 baseline/noise-boundary work.
They are reference files for comparison, not the ILC3 analog-comparison RX.
```

Current PAM4 reference condition:

```text
TX analog full scale ~= 320-330 mV
TH0/TH1/TH2 ~= 104/172/241 mV, approximately
PAM4 low-frequency fail boundary ~= 530-540 mV source-noise setting
```

## Result and design documents

### `docs/pam4_compare_ilc3_analog_design_2026-05-11.md`

Use:

```text
Design note for why the original ILC3 TX/RX was not comparable to PAM4,
and why the dedicated ILC3 analog-comparison TX/RX was created.
```

Important contents:

```text
Same PAM4 resistor-DAC path
ILC3 TX mapping
RX W0/W1/W3/W7 meaning
Current limitation: analog level monitor, not protocol BER checker
```

iCloud copy:

```text
C:\Users\kangmu\iCloudDrive\WIN TO MAC\5월11일_ilc3\pam4\pam4_compare_ilc3_analog_design_2026-05-11.md
```

### `docs/ilc3_vs_pam4_noise_snr_review_2026-05-11.md`

Use:

```text
Final condition/result/SNR-proxy review for 2026-05-11.
```

Important conclusion:

```text
PAM4 practical fail boundary ~= 530-540 mV source noise
ILC3 tested pass point       = 990 mV source noise
ILC3 lower-bound advantage   > +5.3 dB source-referred
```

Important limitation:

```text
This is source-referred noise tolerance, not formal SNR.
Formal SNR requires actual analog-node noise RMS measurement.
```

iCloud copy:

```text
C:\Users\kangmu\iCloudDrive\WIN TO MAC\5월11일_ilc3\pam4\ilc3_vs_pam4_noise_snr_review_2026-05-11.md
```

### `ilc3_vs_pam4_noise_test_result_2026-05-11.md`

Location:

```text
C:\Users\kangmu\iCloudDrive\WIN TO MAC\5월11일_ilc3\pam4\ilc3_vs_pam4_noise_test_result_2026-05-11.md
```

Use:

```text
Earlier intermediate comparison result note.
Keep for history, but prefer the newer SNR review file for the final 2026-05-11 conclusion.
```

Reason:

```text
Some earlier text was written before the final W1 correction and final 990 mV ILC3 pass result.
```

### `pam4_lmv339_2026-05-11_noise_boundary_summary.md`

Location:

```text
C:\Users\kangmu\iCloudDrive\WIN TO MAC\5월11일_ilc3\pam4\pam4_lmv339_2026-05-11_noise_boundary_summary.md
```

Use:

```text
PAM4-only LMV339 noise-boundary history for 2026-05-11.
Use this as the PAM4 reference data source.
```

Important result:

```text
PAM4 current comparison fail boundary ~= 530-540 mV
Earlier 313 mV boundary belongs to a different threshold condition and should not be mixed with the final comparison.
```

## Files that are not the current comparison target

Original ILC3 packet TX/RX files and bitstreams are still useful for ILC3 packet-link testing, but they are not directly comparable to the PAM4 analog-noise test because the physical output and RX decision path are different.

Do not mix these results:

```text
Original ILC3 packet OK/NG counters
PAM4/ILC3 analog-comparator W0/W1/W3/W7/WI/QW/QN counters
```

## Known caveats

### 1. `500 mHz` notation

In these bench notes:

```text
500 mHz = 0.5 Hz
```

Do not read it as 500 MHz.

### 2. Current pass/fail meaning

For the analog-comparison logs:

```text
WI > 0 or QN > 0 -> analog-level fail
QW only          -> warning / margin reduction
WI=0 and QN=0   -> analog-level pass
```

### 3. Formal SNR is not complete yet

The current `+5.3 dB` result is source-referred:

```text
20log10(990 / 540) ~= +5.3 dB
```

Formal SNR requires:

```text
actual signal RMS at analog node
actual noise RMS at analog node while noise is ON
```

### 4. ILC3 fail boundary was not reached

Latest ILC3 result:

```text
500 mHz / 990 mV: PASS
1 Hz ~ 5 Hz / 990 mV: PASS
```

Therefore:

```text
ILC3 fail boundary > 990 mV
```

Do not write:

```text
ILC3 fail boundary = 990 mV
```

## Practical next-use checklist

For continuing comparison work:

```text
1. Load top_ilc3_analog_compare_tx_board.bit on TX.
2. Load top_ilc3_analog_compare_rx_board.bit on RX.
3. Confirm noise OFF clean state:
   W0/W1/W3/W7 active, WI=0, QN=0.
4. Record:
   TX analog min/max, input+, TH0, TH1, TH2, injection resistor, Wavegen amplitude/frequency.
5. Use QN/WI for pass/fail.
6. Use R/A only as display diagnostics.
```

