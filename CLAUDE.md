# GawdSpeed: notes for Claude Code

A macOS practice and transcription player: it slows audio down without
changing pitch, and adds transpose, loops, filters and export. The full spec is
`docs/SPEC.md`; read it first. `docs/FINDINGS.md` records measured results
that shaped decisions. Never delete a row there; change its status.

## This repo

- **Public** GitHub repo `mwikkid/GawdSpeed`, licensed GPL-3.0-or-later because it uses
  Rubber Band (GPL). Nothing private goes in here: no secrets, personal notes or music.
- It is its own git repo; the `~/Projects` monorepo ignores `GawdSpeed/`. Commit here.
- Commits use the GitHub noreply address (set in this repo's local git config).
- Bundle ID: `audio.iii.GawdSpeed` (ships under iii.audio). The copyright is personal:
  `Copyright (C) 2026 Earl Scioneaux, III`, with the comma.

## Commands

```bash
xcodegen generate                      # after any change to project.yml or adding/removing files
xcodebuild -project GawdSpeed.xcodeproj -scheme GawdSpeed -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData test
scripts/check-licenses.sh              # must pass before every commit
```

`GawdSpeed.xcodeproj`, `build/` and `TestOutput/` are generated and git-ignored.

## Layout and conventions

- `Bridge/`: the C/C++ side, built as the `GawdDSP` static library. Swift sees only
  `Bridge/include` (the `GawdDSP` clang module). Each engine is a `gs::Stretcher` (C++)
  exposed through `GSStretcher.h`; nothing outside the audio/DSP layer calls it.
- `ThirdParty/<name>/`: vendored upstream code, left untouched. **Never put a
  `ThirdParty/<name>/` folder itself on a header search path.** Its `VERSION` file
  shadows the C++ standard header `<version>` on macOS's case-insensitive disk, and
  the build breaks with "unknown type name 'upstream'". Include as
  `"rubberband/rubberband/RubberBandStretcher.h"` with `ThirdParty/` on the path.
  `check-licenses.sh` fails if this happens.
- Positions are always in source frames. The stretchers report `position()`: the
  source frame heard at the next output frame.
- Tests: `Tests/Support` holds the harness and the measuring instruments. An
  instrument is checked against known signals (`InstrumentTests`) before it judges
  anything, and every check has a negative control that proves it can fail.
- **Never leave a control that looks alive but ignores input.** Earl read the
  greyed-out-but-normal-looking empty state as "completely dead" (2026-10-06). Keep
  controls live, and when an action can't happen yet, say why in the status line.
- Tooltips use `.tip()` (`Sources/UI/Tooltip.swift`), not `.help()`, because
  `.help()` misplaces its tooltips once the interface is scaled. My synthetic-mouse
  hover tool doesn't reach the window, so Earl confirms hover behaviour.
- Known Algorithm A pitch misses are expected failures, and strict (see FINDINGS F1).
  If one starts passing, update the list rather than loosening the test.

## Licensing rules (spec §7, copied verbatim; standing rules)

**Treat this section as standing rules. Copy it into `CLAUDE.md`.**

### 7.1 Project license
- GawdSpeed's own code is licensed **GPL-3.0-or-later**. Root `LICENSE` file = full GPLv3 text.
- Why 3.0 and not 2.0: Rubber Band is GPL-2.0-*or-later*, so GPLv3 is allowed, and GPLv3 is also compatible with Apache-2.0 dependencies (e.g. swift-atomics), which GPLv2 is not.
- Copyright line: `Copyright (C) 2026 Earl Scioneaux, III` — personal copyright, not the LLC.
- Every source file we write starts with an SPDX header:
  `// SPDX-License-Identifier: GPL-3.0-or-later` + copyright line.
- `README.md` states the license and links to `LICENSE` and `THIRD_PARTY_NOTICES.md`.

### 7.2 Third-party inventory
Maintain these, and keep them in sync every time a dependency is added, removed, or updated:
- **`THIRD_PARTY_NOTICES.md`** — one entry per dependency: name, version/tag/commit, upstream URL, license (SPDX id), copyright holder(s), how it's used (vendored source / SwiftPM / bundled binary / runtime-invoked tool / build-only tool), and whether it ships inside the app.
- **`LICENSES/`** folder — full license text for every license that applies (`GPL-3.0-or-later.txt`, `GPL-2.0-or-later.txt`, `MIT-signalsmith.txt`, `Apache-2.0.txt`, …).
- **Vendored code** under `ThirdParty/<name>/` keeps its original LICENSE/COPYING and copyright headers **untouched**. Record the exact upstream tag/commit in `ThirdParty/<name>/VERSION`. Any local modification is listed in `ThirdParty/<name>/MODIFICATIONS.md` (GPL requires marking changes).
- **Inside the app bundle:** copy `LICENSE`, `THIRD_PARTY_NOTICES.md` and `LICENSES/` into the app's Resources. The **About window** shows the GawdSpeed license, a link to the source repo, and a "Acknowledgements" view listing every shipped dependency with its license text.

### 7.3 Known dependencies (starting inventory — verify each)
| Dependency | License | Ships in app? | Notes |
|---|---|---|---|
| Signalsmith Stretch (+ any Signalsmith headers it needs) | MIT | Yes (compiled in) | Keep copyright notice + MIT text |
| Rubber Band Library v3 | GPL-2.0-or-later | Yes (compiled in) | Note which FFT/resampler backends are built in; if any bundled third-party code inside Rubber Band has its own license, list it too |
| swift-atomics (if used) | Apache-2.0 | Yes | Include Apache-2.0 text and any NOTICE file |
| yt-dlp | Unlicense | **No** — user-installed or downloaded at runtime | Still list it in notices as a runtime-invoked tool |
| ffmpeg (bundled CLI, our own build) | GPL-2.0-or-later as configured (with `--enable-gpl --enable-version3` → GPL-3.0-or-later) | Yes | Built from a pinned release by `scripts/build-ffmpeg.sh`; **never `--enable-nonfree`**; record version + full configure flags in notices; attach the exact ffmpeg source tarball + build script to every GitHub Release |
| LAME (inside ffmpeg build, for MP3 export) | LGPL-2.0-or-later | Yes | List separately; include its license text |
| Sparkle (if added) | MIT | Yes | |
| XcodeGen | MIT | No (build tool) | List as build-only |

- **Contributions:** no CLA/DCO. Anyone contributing does so under GPL-3.0-or-later (state this in `CONTRIBUTING.md`).

### 7.4 Rules for adding anything new
Before adding **any** dependency, code snippet, asset, font, icon, or sound:
1. Identify its license and record it in `THIRD_PARTY_NOTICES.md` in the same commit.
2. **Allowed (GPLv3-compatible):** MIT, BSD-2/3-Clause, ISC, Zlib, Apache-2.0, MPL-2.0, LGPL-2.1+/3.0, GPL-2.0-or-later, GPL-3.0, Unlicense, CC0, public domain.
3. **Not allowed without asking Earl:** GPL-2.0-*only*, AGPL, "non-commercial" licenses (CC BY-NC etc.), proprietary/no-license code, anything with unclear license, code copied from Stack Overflow/blogs without a clear license.
4. Do not copy code from other projects into our files without attribution; prefer vendoring with the original license intact.

### 7.5 Things that must never go in the public repo
- Copyrighted music or audio. Test audio must be **generated** (sine, clicks, synthesized drums/piano) or clearly CC0, with its source recorded in `TestAudio/SOURCES.md`.
- Anything downloaded via YouTube import.
- Apple signing certificates, notarization credentials/API keys, `.p12`/`.p8` files, provisioning profiles, team-specific secrets. Use environment variables / keychain and add these patterns to `.gitignore`.

### 7.6 Automated check
- `scripts/check-licenses.sh` (run in CI and before each release): fails if any directory in `ThirdParty/` lacks a LICENSE and VERSION file or a matching `THIRD_PARTY_NOTICES.md` entry, if any Swift/C/C++ file we own lacks an SPDX header, or if obvious secret files are tracked.
- GitHub Actions: build + test + license check on every push.

### 7.7 Releases (GPL obligations)
- Each binary release is a **GitHub Release built from a tagged commit**; the tag is the "corresponding source". Never ship a binary built from uncommitted changes.
- Release notes link to the source tag. Release zip/DMG includes `LICENSE` and notices.
