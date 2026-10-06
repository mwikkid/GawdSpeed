# GawdSpeed

A practice and transcription player for macOS. Load a song, slow it down
without changing its pitch, loop the hard part, and work it out by ear.

> **Status:** early development (Phase 0: project skeleton and both
> time-stretch engines under test). Not ready to use yet.

## Features (planned)

- Speed from 25% to 100%, pitch preserved; optional transpose (±12 semitones + cents)
- Two time-stretch algorithms to compare by ear:
  **A** = [Signalsmith Stretch](https://github.com/Signalsmith-Audio/signalsmith-stretch),
  **B** = [Rubber Band Library](https://breakfastquay.com/rubberband/) (R3 engine)
- Waveform with loop regions, high-pass and low-pass filters
- Export the slowed-down audio, either the whole song or just a selection

## Building

Requires macOS 14+, Xcode, and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`).

```bash
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
