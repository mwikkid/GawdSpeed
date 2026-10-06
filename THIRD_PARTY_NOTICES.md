# Third-party notices

GawdSpeed is free software, licensed under the GNU General Public License,
version 3 or (at your option) any later version. See [LICENSE](LICENSE). It
includes or uses the third-party software below. Full license texts are in
[LICENSES/](LICENSES/).

Each vendored library sits under `ThirdParty/<name>/` with its original license
file, a `VERSION` file (upstream URL, tag, commit) and a `MODIFICATIONS.md`.

`scripts/check-licenses.sh` checks this file against `ThirdParty/`: every
folder there must have an entry here headed `ThirdParty/<name>`.

---

## Signalsmith Stretch — `ThirdParty/signalsmith-stretch`

- **Version:** 1.4.0 (commit `a670068d9aeb64913331d5cc29337b19a457a7df`)
- **Upstream:** https://github.com/Signalsmith-Audio/signalsmith-stretch
- **License:** MIT ([LICENSES/MIT-signalsmith-stretch.txt](LICENSES/MIT-signalsmith-stretch.txt))
- **Copyright:** (c) 2022 Geraint Luff / Signalsmith Audio Ltd.
- **Used as:** vendored source, compiled into the app (Algorithm A)
- **Ships in app:** yes

## Signalsmith Linear — `ThirdParty/signalsmith-linear`

- **Version:** 0.6.4 (commit `de55e6a50ffcf6f8f43f649692d94691c7025151`). This is the version Signalsmith Stretch 1.4.0 pins.
- **Upstream:** https://github.com/Signalsmith-Audio/linear
- **License:** MIT ([LICENSES/MIT-signalsmith-linear.txt](LICENSES/MIT-signalsmith-linear.txt))
- **Copyright:** (c) 2025 Signalsmith Audio
- **Used as:** vendored source (FFT/STFT headers used by Signalsmith Stretch), compiled into the app
- **Ships in app:** yes

## Rubber Band Library — `ThirdParty/rubberband`

- **Version:** v4.0.0 (commit `1d95888bec3ae0a17c0c4af791810d5a63f6bc35`)
- **Upstream:** https://github.com/breakfastquay/rubberband
- **License:** GPL-2.0-or-later ([LICENSES/GPL-2.0-or-later.txt](LICENSES/GPL-2.0-or-later.txt))
- **Copyright:** Copyright 2007-2024 Particular Programs Ltd.
- **Used as:** vendored source, built from `single/RubberBandSingle.cpp` and compiled into the app (Algorithm B, R3 "finer" engine)
- **Ships in app:** yes
- **Backends compiled in:** FFT from Apple's Accelerate framework (vDSP, part of macOS);
  resampler is Rubber Band's own BQResampler. None of the third-party code Rubber Band
  bundles in `src/ext` (kissfft, Speex resampler, pommier, getopt) is compiled, so it is
  not included.

---

## Build-only tools (not shipped in the app)

### XcodeGen

- **Upstream:** https://github.com/yonaskolb/XcodeGen
- **License:** MIT
- **Used as:** build tool. It generates `GawdSpeed.xcodeproj` from `project.yml`.
- **Ships in app:** no

## System frameworks

Accelerate, AVFoundation, AppKit and SwiftUI are part of macOS and are linked
from the operating system, not distributed with GawdSpeed.
