# Decisions

Changes to, and settlements of, the spec (`docs/SPEC.md`), newest first. Each entry gives
the date, who decided, and why.

## 2026-10-06 (Phase 4)

- **Source for testers is a link, not a bundle** (Earl). Each release build stamps its git
  commit into the app (`GSSourceCommit`). About ▸ "Source code for this build" links to that
  commit on GitHub, and `scripts/release.sh` refuses to build a commit that isn't pushed.
  ffmpeg and LAME sources are named with pinned URLs and checksums in `build-ffmpeg.sh` and
  `THIRD_PARTY_NOTICES.md` (GPLv3 §6(d): source on a server, with clear directions). Public
  GitHub Releases still attach every source archive. Clicking the iii.audio mark opens the
  About window (the credits).

- **A two-page PDF guide** (Earl asked): an annotated screenshot with every control explained,
  the "first loop in 30 seconds", Settings and the keyboard shortcuts. Its source is
  `docs/guide/guide.html` and `scripts/make-guide.sh` prints it with headless Chrome; the PDF is
  committed. It ships in the app (Help ▸ GawdSpeed Guide) and loose in the DMG. Re-run the
  script after changing the controls; the screenshot is `docs/guide/window.png`, taken of a
  generated demo song.
- **App icon** from Earl's artwork: the inner square, fitted to the macOS icon layout.
- **The link field no longer takes the keyboard at launch.** It had been switching off Space and
  the other single-key shortcuts until the first click elsewhere.

- **Signing stays on Earl's Mac** (Earl: "I'm just making sure we're being secure"). There
  are no signing secrets on GitHub and no tag-triggered release workflow. `scripts/release.sh`
  signs with the Developer ID certificate in the keychain ("Earlfriend LLC", shared with
  Hysterical) and notarizes with the keychain profile `Hysterical`. Their names live in the
  git-ignored `scripts/release.local.env`. Gatekeeper shows the developer as Earlfriend LLC,
  while the copyright stays personal.
- **No public release yet** (Earl): he wants hands-on time first. `--publish` exists but
  only runs on his word, and only for a notarized build of a tag.
- **`docs/SPEC.md` stays out of the repo** (Earl). It lives on his Mac only.
- **Sparkle auto-updates: not added** (optional in the spec).

## 2026-10-06 (Phase 3)

- **Named regions open as a panel from a "Regions" button**, not a permanent sidebar
  (spec §5.9). The window scales as one fixed-shape piece, so a sidebar would shrink
  everything else. Saved regions also show as orange bars on the overview strip.
- **First-run tips are click-only.** A Return shortcut on the tips' Next button worked
  once, then the menu's Return ("Back to Start") took the key back.
- **Undo groups by stillness:** a change becomes one undo step after half a second
  without further changes, so a whole knob turn or slider drag undoes in one go.
- **FLAC tags are read from AVFoundation's Vorbis-comment items** (`vorb/TITLE`). Apple
  leaves them out of its "common" metadata, so FLAC files showed their file name
  instead of their title. The FLAC export test caught this.
- **Bundled ffmpeg 9.0.2 with LAME 3.100**, built by `scripts/build-ffmpeg.sh`: universal,
  8.8 MB, network off, GPL-3.0-or-later as built. CI caches the build. Not built in:
  hand-written x86 assembly (no `nasm` on the build Mac), so the Intel slice is a little
  slower at decoding.

## 2026-10-06 (Phase 2)

- **Saved positions are seconds of source time, not file frames** (Claude). The spec's
  §3 rule 2 says "source-file frames". The audio in memory is resampled to the output
  device's rate, so a frame count would change meaning when the device changes. Seconds
  of source time keep the rule's intent: never stretched time.
- **Per-song memory and the peak cache are keyed by a content fingerprint**
  (`FileFingerprint`: SHA-256 of the file's size plus its first and last megabyte), not
  a hash of the whole file. It's instant on large files, survives renames, and changes
  if the audio is edited.
- **Export doesn't copy title/artist tags yet** (spec §5.10). AVAudioFile can't write
  them; this waits for Phase 3, alongside FLAC and MP3 export.
- **Single-key shortcuts (Space, I, O, L, arrows, −, =, [, ]) switch off while a text
  field or the Export sheet has the keyboard**, so typing a loop time doesn't trigger them.

## 2026-10-06 (after Earl's first try of Phase 1)

- **"transpose" and "tune" are two separate, labelled groups** (Earl: "I didn't realize
  you had both a tune and a transpose"). Transpose is semitone − / + buttons. Tune is a
  cents slider. A "● original key" chip appears only while either is shifted, and
  clicking it resets both.
- **Tooltips are drawn inside the interface** (`Sources/UI/Tooltip.swift`), replacing
  SwiftUI's `.help()`, which positions its tooltips from the unscaled layout.
- **Only the top strip drags the window.** A draggable background was moving the
  window when Earl turned the filter knobs.
- **Logo moved into the transpose/tune/filters row; status messages moved into the
  transport row; the bottom strip is gone.** The design size is now 900 × 490 (it was the
  spec's 900 × 520).
- **Import from a website** is spec Phase 4 and not built yet. Earl asked where it was.

## 2026-10-06

- **Interface scales with the window, as in Hysterical** (Earl). Drag the window corner
  and the whole interface grows or shrinks together, including controls, text and the
  logo, so it can be read from across the room with an instrument in hand. It's laid
  out at a design size (900×520) and drawn through one scale factor. Phase 1.
- **iii.audio wordmark in a corner of the window** (Earl). The wordmark is the one from
  Hysterical (`Assets/LogoWordmark.png`), small and out of the way. Its license (Claude,
  the conservative default): the logo is **not** covered by the GPL. It's marked
  "all rights reserved" in `THIRD_PARTY_NOTICES.md`, so forks may use the code but not the
  branding. This can be loosened later; a GPL grant can't be taken back.
- **Default algorithm is B (Rubber Band)** (Claude, from FINDINGS F1). It measured
  pitch-exact everywhere, while A drifts when transposing and below 40% speed. The spec
  said "default A, revisit after listening tests"; this is that revisit, based on
  measurement. Earl's listening can flip it back.
- **The audio chain lives in C++, not Swift** (Claude). This covers the parameter
  queue, both stretchers, crossfades, loop wrap and filters. It's internal and changes
  nothing visible. Reasons: the audio thread must never allocate or lock (spec §3 rule
  3); Swift's built-in atomics need macOS 15 and we target 14; and export reuses the exact
  same code. swift-atomics (Apache-2.0) is therefore not needed. §4's `TimeStretcher`
  is a C++ interface (`Bridge/Stretcher.hpp`), and the biquads will be C++.
- **Bundle ID `audio.iii.GawdSpeed`** (Earl). It ships under iii.audio. The copyright
  stays personal.
- **Rubber Band v4.0.0** instead of v3 (Claude, Earl agreed). Same R3 engine and API,
  plus bug fixes.
