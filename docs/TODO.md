# Running list

## HANDOFF — one fixed block, replaced at every wrap, never appended (budget 60 lines / 6 KB)

**Read this, then `git status -sb` and `git log --oneline db6c0e2..HEAD`:
anything after the commit below is what this block does not know.**

- **wrapped:** 2026-10-07 10:40 at `db6c0e2` — by the wrap-up skill
- **branch:** main, level with origin. Side experiments: none.
- **first thing next session:** ask Earl how hands-on time with the beta went, and
  act on his notes. Then his answer on Spotify (T6).
- **then:** open rows below (T1–T8); a public release only on his word (T1).
- **staged, not run:** `dist/GawdSpeed-0.1.0-beta1.dmg` (signed, notarized, built from
  `db6c0e2`; sent to Earl 2026-10-06; `dist/` is git-ignored).
  `dist/GawdSpeed-0.1.0-beta1.dmg.zip` appeared at 19:49 that day; not made by the
  release script (likely Earl's own zip for sending).
- **installed:** this Mac: yt-dlp 2026.08.19 at `~/Library/Application Support/GawdSpeed/bin/yt-dlp`;
  test clip (Big Buck Bunny, CC) in `~/Music/GawdSpeed/Downloads`; notarytool profile
  `Hysterical` (recreated by Earl 2026-10-06); signing names in `scripts/release.local.env`.
- **running in the background:** none. GawdSpeed (Release build from
  `build/DerivedData`) is open on Earl's screen on purpose.
- **open questions to Earl:** Spotify: route 1 (link → same song on YouTube) or
  route 2 (record the Spotify app), see T6; tag `v0.1.0-beta1` publicly or not (T1).
- **awaiting Earl's eyes:** the beta in hand (T2): A vs B on real songs, dragging
  highlights and the overview box, Regions panel, Export via Save dialog, device picker.
- **the thread:** Phases 0–4 of `docs/SPEC.md` are built. The last work was a tidy DMG
  (drag instruction, Docs folder) and the signed beta. Earl's last question was whether
  Spotify support is possible; the answer was two routes, route 1 recommended.
- **where the rest is:** decisions `docs/DECISIONS.md`; measured results
  `docs/FINDINGS.md` (F1 Signalsmith pitch, F2 filter zipper); standing rules and
  gotchas `CLAUDE.md`; Earl's spec `docs/SPEC.md` (his Mac only); memory
  `gawdspeed-repo.md`.

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

## Done (2026-10-06)

Phases 0–4: engine, player, loops, export, ffmpeg formats, URL import, signing and
release. The commit log has the detail; `docs/DECISIONS.md` has every departure from the spec.
