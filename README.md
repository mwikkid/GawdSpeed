# GawdSpeed

A practice and transcription player for macOS. Load a song, slow it down
without changing its pitch, loop the hard part, and work it out by ear.

> **Status:** early development. Phases 1–3 work: open almost any audio or
> video file, slow it down, transpose, filter, A/B the two algorithms, zoom
> the waveform, loop and name sections, and export to WAV, AIFF, FLAC, ALAC,
> AAC or MP3. Importing from websites and signed releases come next.

## Features (planned)

- Speed from 25% to 100%, pitch preserved; optional transpose (±12 semitones + cents)
- Two time-stretch algorithms to compare by ear:
  **A** = [Signalsmith Stretch](https://github.com/Signalsmith-Audio/signalsmith-stretch),
  **B** = [Rubber Band Library](https://breakfastquay.com/rubberband/) (R3 engine)
- Waveform with loop regions, high-pass and low-pass filters
- Export the slowed-down audio, either the whole song or just a selection

## CPU cost

Measured offline by `PerformanceTests`: 30 s of stereo 48 kHz audio, three
interleaved runs, on an Apple M5 Max (2026-10-06). One machine, so treat these
as orientation rather than a benchmark.

| Path | CPU, % of one core |
|---|---|
| 100% speed, no transpose (bypass, untouched audio) | 0.01 |
| Algorithm A (Signalsmith Stretch) at 50% | 0.42 |
| Algorithm B (Rubber Band R3) at 50% | 2.86 |

Algorithm B costs about 7× as much as A, and both are far below what real-time playback needs.

## Building

Requires macOS 14+, Xcode, and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`). `scripts/build-ffmpeg.sh` builds the bundled ffmpeg
(about a minute); without it the app falls back to a Homebrew ffmpeg if there is one.

```bash
scripts/build-ffmpeg.sh
xcodegen generate
xcodebuild -project GawdSpeed.xcodeproj -scheme GawdSpeed -destination 'platform=macOS' test
scripts/check-licenses.sh
```

## License

GawdSpeed is free software, licensed under the GNU General Public License,
version 3 or (at your option) any later version. See [LICENSE](LICENSE).

It builds on the Rubber Band Library (GPL-2.0-or-later) and Signalsmith
Stretch (MIT). See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and
[LICENSES/](LICENSES/) for every third-party component and its license.
Contributions are welcome under the same license; see
[CONTRIBUTING.md](CONTRIBUTING.md).

Copyright (C) 2026 Earl Scioneaux, III
