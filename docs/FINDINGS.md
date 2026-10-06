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
