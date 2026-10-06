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

## FFmpeg (bundled command-line tool, `Contents/Helpers/ffmpeg`)

- **Version:** 9.0.2 (`ffmpeg-9.0.2.tar.xz`, SHA-256 `8c3850283eb25fa026482078a04051e0be17347b09ef81a0849bec15a96e002e`)
- **Upstream:** https://ffmpeg.org
- **License:** GPL-3.0-or-later as built (`--enable-gpl --enable-version3`) ([LICENSES/GPL-3.0-or-later.txt](LICENSES/GPL-3.0-or-later.txt)); never built with `--enable-nonfree`
- **Copyright:** the FFmpeg developers
- **Used as:** our own static build, made by `scripts/build-ffmpeg.sh` from the pinned release above, run as a separate program to decode formats AVFoundation can't and to write FLAC and MP3
- **Ships in app:** yes. The exact configure lines are in the app at `Contents/Resources/ffmpeg-BUILDINFO.txt`, and every GitHub Release attaches the source archive and the build script.
- Not vendored in `ThirdParty/`: the source is downloaded and checksum-verified at build time.

## LAME (inside the bundled ffmpeg, for MP3 export)

- **Version:** 3.100 (`lame-3.100.tar.gz`, SHA-256 `ddfe36cab873794038ae2c1210557ad34857a4b6bdc515785d1da9e175b1da1e`)
- **Upstream:** https://lame.sourceforge.io
- **License:** LGPL-2.0-or-later ([LICENSES/LGPL-2.0-or-later-LAME.txt](LICENSES/LGPL-2.0-or-later-LAME.txt))
- **Copyright:** the LAME developers
- **Used as:** a static library linked into the bundled ffmpeg. The one build-time change: `lame_init_old` is removed from `include/libmp3lame.sym`, an export list that still names a removed function.
- **Ships in app:** yes, inside `ffmpeg`

---

## iii.audio name and logo: `Sources/Resources/Assets.xcassets/iiiAudioWordmark.imageset`

- **Copyright:** (C) 2026 Earl Scioneaux, III. All rights reserved.
- **License:** **not** covered by the GPL. The wordmark is the maker's mark of
  iii.audio. You may build and run GawdSpeed from source with it in place.
  If you distribute a modified version, remove or replace it.
- **Ships in app:** yes (a small mark in the window footer and the About window)

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
