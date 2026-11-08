# Running list

## HANDOFF — one fixed block, replaced at every wrap, never appended (budget 60 lines / 6 KB)

**Read this, then `git status -sb` and `git log --oneline 5f6f38b..HEAD`:
anything after the commit below is what this block does not know.**

- **wrapped:** 2026-11-07 19:30 at `5f6f38b` — by hand (Earl asked to save)
- **branch:** main, level with origin. Side experiments: none.
- **first thing next session:** Marisa's reaction to 0.1.1 (she asked for faster
  speeds, now 25–200%), via Earl. Then Earl's open asks below.
- **then:** the workup-file idea (T9) if Earl wants it; open rows T1–T8.
- **staged, not run:** `dist/GawdSpeed-0.1.1.dmg` (signed, notarized, built from
  `5f6f38b`), sent to Earl 2026-11-07 for Marisa. Backed up via `.backup-set`
  (Harpo + Google Drive). The 0.1.0-beta1 DMG is no longer in `dist/`; Earl has the
  copy he sent.
- **installed:** this Mac: `/Applications/GawdSpeed.app` is 0.1.0 (`db6c0e2`), Earl's own
  install; 0.1.1 isn't installed there. yt-dlp 2026.08.19 in
  `~/Library/Application Support/GawdSpeed/bin`; notarytool profile `Hysterical`; signing
  names in `scripts/release.local.env`.
- **running in the background:** none.
- **open questions to Earl:** workup files (T9): markup only or with the song, and a notes
  field? Spotify route 1/2 (T6). Public tag (T1). The rule for measurement-discipline
  ("a number identical across a fix means the fix missed the cause"): not yet answered.
- **awaiting Earl's eyes:** 0.1.1 in Marisa's hands; T3's mouse-only checks.
- **the thread:** Earl asked for a way to save a song's workup. It turned out per-song
  memory already saves it, invisibly (his Oct 29 save holds 2 regions). The proposal
  is a named `.gawdspeed` workup file on top. Then Marisa asked for faster speeds,
  shipped as 0.1.1.
- **where the rest is:** `docs/DECISIONS.md` (newest first), `docs/FINDINGS.md`,
  `CLAUDE.md` (rules and gotchas), `docs/BACKUP.md`, `docs/SPEC.md` (Mac only),
  memory `gawdspeed-repo.md`.

## Open

| # | Item | Status |
|---|---|---|
| T1 | Public release (`git tag vX && scripts/release.sh X --publish`) | waiting: Earl wants hands-on time first |
| T2 | Earl's hands-on notes on the 0.1.0-beta1 | waiting on Earl |
| T3 | Untested by hand: overview-box drag, Regions panel buttons and rename, Export through the Save dialog, output-device switch, smooth follow | waiting on Earl (synthetic mouse can't reach the window) |
| T4 | APE and AMR decoding never exercised (no encoder here to make test files) | open |
| T5 | Algorithm A pitch error (FINDINGS F1): keep, patch our copy, or report upstream | open; B is the default meanwhile |
| T6 | Spotify: route 1 (Spotify link → YouTube match, confirm) or route 2 (ScreenCaptureKit app-audio capture) | asked 2026-10-06, unanswered |
| T7 | Sparkle auto-updates (spec Phase 4, optional) | not started |
| T8 | Export doesn't write title/artist tags for WAV/AIFF/ALAC/AAC (FLAC and MP3 do) | open |
| T9 | Workup files: File ▸ Save Workup (⌘S) to a named `.gawdspeed` file (markup, song reference, maybe notes) on top of the invisible per-song memory | proposed 2026-10-31, waiting on Earl's two answers |
| T10 | Speeds above 100% (Marisa) | done in 0.1.1, 2026-11-07 |

## Done (2026-10-06)

Phases 0–4: engine, player, loops, export, ffmpeg formats, URL import, signing and
release. The commit log has the detail; `docs/DECISIONS.md` has every departure from the spec.
