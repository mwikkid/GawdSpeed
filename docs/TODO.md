# Running list

## HANDOFF — one fixed block, replaced at every wrap, never appended (budget 60 lines / 6 KB)

**Read this, then `git status -sb` and `git log --oneline d0f282f..HEAD`:
anything after the commit below is what this block does not know.**

- **wrapped:** 2026-11-09 at `d0f282f` — by the wrap-up skill
- **branch:** main, level with origin; CI green on `d0f282f`. Side experiments: none.
- **first thing next session:** Marisa's reaction to 0.1.1 (via Earl), then Earl's open asks.
- **then:** a public pre-release of 0.1.1 once Marisa's run is clean (T1); workup files
  (T9) if Earl answers its two questions; open rows below.
- **staged, not run:** `dist/GawdSpeed-0.1.1.dmg` (signed, notarized, from `5f6f38b`).
  Shared with Marisa from Earl's Drive by link,
  `gdrive:GawdSpeed/Tester builds/GawdSpeed-0.1.1.dmg`; the link itself is in memory
  `gawdspeed-repo.md`, not here (this repo is public).
- **installed:** this Mac: `/Applications/GawdSpeed.app` is 0.1.0 (`db6c0e2`, Earl's own
  install), not 0.1.1. yt-dlp 2026.08.19 in `~/Library/Application Support/GawdSpeed/bin`;
  notarytool profile `Hysterical`; signing names in `scripts/release.local.env`.
- **running in the background:** none.
- **open questions to Earl:** T1 publish 0.1.1 as a GitHub pre-release (recommended
  after Marisa's run); T9 workup files (markup only or with the song? a notes field?);
  T6 Spotify route 1 or 2; the proposed measurement-discipline rule ("a number identical
  across a fix means the fix missed the cause").
- **awaiting Earl's eyes:** 0.1.1 in Marisa's hands; T3's mouse-only checks.
- **the thread:** Earl is putting the repo on his résumé. The README was rewritten
  (features, "how it's built", screenshot), and the repo description, homepage
  (iii.audio) and topics were set; he agreed it's ready. He asked whether a download
  belongs on GitHub: it's normal for apps as a Release; recommended a pre-release after
  Marisa's testing; his call.
- **where the rest is:** `docs/DECISIONS.md` (newest first), `docs/FINDINGS.md`,
  `CLAUDE.md`, `docs/BACKUP.md`, `docs/SPEC.md` (Mac only), memory `gawdspeed-repo.md`.

## Open

| # | Item | Status |
|---|---|---|
| T1 | Public release (`git tag vX && scripts/release.sh X --publish`) | recommended as a pre-release of 0.1.1 after Marisa's run; Earl's call (2026-11-09) |
| T2 | Hands-on notes: Earl on 0.1.0-beta1, Marisa on 0.1.1 | Marisa's first note came in (speeds above 100%), done as T10; more awaited |
| T3 | Untested by hand: overview-box drag, Regions panel buttons and rename, Export through the Save dialog, output-device switch, smooth follow | waiting on Earl (synthetic mouse can't reach the window) |
| T4 | APE and AMR decoding never exercised (no encoder here to make test files) | open |
| T5 | Algorithm A pitch error (FINDINGS F1): keep, patch our copy, or report upstream | open; B is the default meanwhile |
| T6 | Spotify: route 1 (Spotify link → YouTube match, confirm) or route 2 (ScreenCaptureKit app-audio capture) | asked 2026-10-06, unanswered |
| T7 | Sparkle auto-updates (spec Phase 4, optional) | not started |
| T8 | Export doesn't write title/artist tags for WAV/AIFF/ALAC/AAC (FLAC and MP3 do) | open |
| T9 | Workup files: File ▸ Save Workup (⌘S) to a named `.gawdspeed` file (markup, song reference, maybe notes) on top of the invisible per-song memory | proposed 2026-10-31, waiting on Earl's two answers |
| T10 | Speeds above 100% (Marisa) | done in 0.1.1, 2026-11-07 |
| T11 | README and GitHub page fit for Earl's résumé | done 2026-11-09 (`d0f282f`); description, homepage, topics set |

## Done (2026-10-06)

Phases 0–4: engine, player, loops, export, ffmpeg formats, URL import, signing and
release. The commit log has the detail; `docs/DECISIONS.md` has every departure from the spec.
