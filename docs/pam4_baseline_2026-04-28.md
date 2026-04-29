# PAM4 Baseline Result - 2026-04-28

## Baseline Commit

- Commit before analog measurement note: `5083cc3 Add stable PAM4 digital baseline`

## Digital Baseline

The PAM4 baseline TX/RX pair was implemented with two digital PAM4 code bits.

- TX pattern: `00 -> 01 -> 10 -> 11 -> repeat`
- Default TX rate: `SYMBOL_HOLD_CLKS=125`, about 1 us/level at 125 MHz
- RX monitor: stable-code sampling with `STABLE_CLKS=16`
- RX UART format: `PAM4RX OK=XXXXXXXX NG=XXXXXXXX C=X`

Observed result:

- PAM4 digital baseline ran for more than 20 minutes.
- `PAM4RX OK` continued increasing.
- `PAM4RX NG=00000000` stayed at zero.

## Analog Resistor-DAC Baseline

The analog PAM4 node was built with an external weighted resistor network.

```text
TX JD2 / T15 / pam4_code[1] / MSB ---- 10 kOhm ----+
                                                    +---- PAM4 analog node ---- AD3 CH1+
TX JD1 / T14 / pam4_code[0] / LSB ---- 20 kOhm ----+

AD3 CH1- / GND ------------------------------------ board GND
```

Direct JD2 check without the resistor network:

- Low: about -30.49 mV
- High: about 3.354 V
- Delta: about 3.384 V

This confirms the JD2 LVCMOS33 output and measurement ground reference were correct.

## 1 us/level Observation

With the default `SYMBOL_HOLD_CLKS=125` setting, the 10 kOhm / 20 kOhm analog node appeared rounded or sawtooth-like instead of fully settled.

Interpretation:

- This was treated as settling behavior, not as a wiring failure.
- The likely contributors are the 10 kOhm / 20 kOhm source resistance, AD3 input capacitance, and wiring capacitance.
- The digital RX baseline stayed valid because the RX monitor still observes the digital JD1/JD2 lines, not the analog node.

## 100 us/level Slow Measurement

For analog level verification, the TX project was regenerated with:

```powershell
$env:SYMBOL_HOLD_CLKS='12500'
```

This gives about 100 us/level at 125 MHz.

Vivado observations:

- `PAM4 SYMBOL_HOLD_CLKS=12500`
- Synthesis parameter bound to `12500`
- Bitstream generation completed
- DRC: 0 errors
- Route timing estimate: WNS 2.863 ns, TNS 0.000 ns
- TX board programmed with the slow-mode bitstream

AD3 observation at the analog node:

- Level 00: about 0 V
- Level 01: about 1.1 V
- Level 10: about 2.2 V
- Level 11: about 3.3 V

Result:

- The 10 kOhm / 20 kOhm resistor DAC produced the expected 4-level PAM4 analog waveform in slow mode.
- The PAM4 digital baseline and resistor-DAC analog 4-level baseline are verified.

## Noise Injection Trial

Noise injection was tried with:

```text
AD3 W1 ---- 10 kOhm ---- PAM4 analog node
AD3 GND -------------- board GND
```

Observed result:

- The injection path was visible on the scope.
- With the available 10 kOhm injection resistor, node disturbance was very small even when W1 amplitude was increased up to 2 Vpp.
- This setup is not sufficient for meaningful noise margin measurement.

Interpretation:

- The PAM4 node is held by the JD2/JD1 resistor DAC, so the 10 kOhm injection path is too weak.
- Current RX does not decode the analog node, so RX `NG` is not expected to respond to analog-node noise.

## Current Board State

At the end of this measurement, the TX board is loaded with the analog measurement slow-mode TX bitstream:

- `SYMBOL_HOLD_CLKS=12500`
- about 100 us/level

## 2026-04-29 Slow-Mode Soak Check

On 2026-04-29 KST, the same PAM4 slow-mode TX/RX pair was reloaded and run for about 2 hours while waiting for lower-value resistors.

Observed RX UART tail:

```text
PAM4RX OK=06060DFE NG=00000000 C=2
PAM4RX OK=0606350E NG=00000000 C=2
PAM4RX OK=06065C1E NG=00000000 C=2
PAM4RX OK=0606832E NG=00000000 C=2
PAM4RX OK=0606AA3E NG=00000000 C=2
PAM4RX OK=0606D14E NG=00000000 C=2
PAM4RX OK=0606F85E NG=00000000 C=2
PAM4RX OK=06071F6E NG=00000000 C=2
PAM4RX OK=0607467E NG=00000000 C=2
PAM4RX OK=06076D8E NG=00000000 C=2
PAM4RX OK=0607949E NG=00000000 C=2
PAM4RX OK=0607BBAE NG=00000000 C=2
PAM4RX OK=0607E2BE NG=00000000 C=2
PAM4RX OK=060809CE NG=00000000 C=2
PAM4RX OK=060830DE NG=00000000 C=2
PAM4RX OK=060857EE NG=00000000 C=2
```

Result:

- Slow-mode PAM4 baseline ran for about 2 hours.
- RX `OK` continued increasing.
- RX `NG=00000000` stayed at zero.
- This confirms the 2026-04-29 reloaded slow-mode PAM4 baseline remained stable.

To return to the normal digital baseline speed, regenerate and reload TX with:

```powershell
$env:SYMBOL_HOLD_CLKS='125'
& 'C:\AMDDesignTools\2025.2\Vivado\bin\vivado.bat' -mode batch -source 'C:\zybo_z7_20_prebringup\tcl\create_project_pam4_baseline_tx.tcl'
& 'C:\AMDDesignTools\2025.2\Vivado\bin\vivado.bat' -mode batch -source 'C:\zybo_z7_20_prebringup\tcl\build_pam4_baseline_tx_impl.tcl'
& 'C:\AMDDesignTools\2025.2\Vivado\bin\vivado.bat' -mode batch -source 'C:\zybo_z7_20_prebringup\tcl\program_pam4_baseline_tx_board.tcl'
```

## Next Work

Prepare lower resistor values before the next test pass.

Recommended PAM4 DAC pairs:

- 1 kOhm / 2 kOhm
- 2.2 kOhm / 4.7 kOhm
- 4.7 kOhm / 10 kOhm

Recommended noise injection series resistors:

- 1 kOhm
- 2.2 kOhm
- 4.7 kOhm
- 10 kOhm

Next test sequence:

1. Verify slow-mode 4-level analog node with the new resistor pair.
2. Return TX to `SYMBOL_HOLD_CLKS=125`.
3. Measure 1 us/level settling and persistence.
4. Retry W1 noise injection with lower series resistance.
5. Move to analog RX only after the analog node and noise margin are characterized.
