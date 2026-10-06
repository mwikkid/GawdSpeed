# Findings

Measured results that shape decisions. Never delete a row; change its status.

## F1: Algorithm A (Signalsmith Stretch 1.4.0) misses the 1-cent pitch target

**Status:** open. Waiting on Earl: accept it, patch our vendored copy, or change the default algorithm.

Measured 2026-10-06 on a pure sine at 48 kHz, mono, render block 512, fixed
random seed. One run per case. Two independent meters agree: the FFT peak meter
in `Tests/Support/SignalMeters.swift`, and an interpolated zero-crossing count
over 0.5–3.9 s of output.

| Case | Algorithm A | Algorithm B (Rubber Band R3) |
|---|---|---|
| 440 Hz, 50% / 75% / 100% speed | 0.00 c | 0.00 c |
| 440 Hz, 100%, +3 st | **+4.45 c** | 0.00 c |
| 220 Hz, 100%, +3 st | +1.49 c | 0.00 c |
| 880 Hz, 100%, +3 st | +0.72 c | 0.00 c |
| 440 Hz, 75%, −2 st | **+3.66 c** (FFT) | 0.00 c |
| 440 Hz, 25% speed (0.25 s windows) | **−7.8 to +16.5 c**, mean +3.7 c | 0.0 c |
| 220 Hz, 25% speed (0.25 s windows) | **−1.6 to +31.1 c**, mean +10.4 c | 0.0 c |
| 220 / 440 Hz, 40% speed | within ±0.5 c | 0.0 c |

Why:
- **Transposition:** open upstream issues describe the mechanism:
  [#31](https://github.com/Signalsmith-Audio/signalsmith-stretch/issues/31)
  (transposed partials land sharp),
  [#32](https://github.com/Signalsmith-Audio/signalsmith-stretch/issues/32)
  (large shifts off pitch) and
  [#33](https://github.com/Signalsmith-Audio/signalsmith-stretch/issues/33)
  (±1.2 c drift). The error depends on where the note falls between FFT bins,
  so it varies with the note rather than being a fixed offset.
- **Very slow speeds:** this is by design. `maxCleanStretch = 2`
  (`signalsmith-stretch.h:509`). Above that stretch, the library randomises each
  bin's time factor, so a held note wanders in pitch. From these measurements it
  is audible at 25% but not at 40%.

What the tests can and can't judge: these are pure sines, the worst case for
pitch error and the easiest case for everything else. Whether the warble at
25% is audible on real music is a listening question.

The suite marks exactly these cases as expected failures
(`StretcherTests.knownMiss`). They are strict, so a fix makes the suite fail
until the list is updated.

## F2: A biquad low-pass zippers when its cutoff moves; state-variable form does not

**Status:** fixed (2026-10-06). Filters are now cascaded state-variable sections (`Bridge/Filters.hpp`).

The first filters were cascaded RBJ biquads (transposed direct form II), with
coefficients recomputed every 32 samples while the cutoff glides. With a
440 Hz tone playing, the click meter read (threshold 3):

| Change | Biquad | State-variable (now) |
|---|---|---|
| high-pass on (300 Hz) / off / moved 100 → 1500 Hz | below 3 | 1.03 / 1.02 / 1.04 |
| low-pass on (2 kHz) | **14.1** | 1.00 |
| low-pass off (2 kHz → 20 kHz) | **10.6** | 1.04 |
| low-pass moved (8 kHz → 600 Hz) | **18.9** | 0.98 |

The other live changes, measured the same way (one run each): seeks
1.22–1.41, A↔B switches 0.85 / 2.21 (B → A is the highest reading of any
change), into or out of bypass 0.99–1.77, speed changes 1.03–1.87, pause
0.83–0.96. The negative control (a hard cut with no crossfade in the same
engine output) reads 165–230.

Why low-pass only: in this form a low-pass's `b0` swings from about 0.6 to
0.015 across the knob's range, so each coefficient update jumps the output.
A high-pass's `b0` stays near 1. A first fix (crossfading dry/filtered when
switching out) didn't change the "off" reading at all (10.6 both times), which
showed the click was in the glide, not the switch.
