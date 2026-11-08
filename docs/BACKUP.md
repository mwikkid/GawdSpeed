# Backups

`python3 ~/.claude/skills/wrap-up/tools/backup.py .` copies what `.backup-set` names to
Harpo and Google Drive. That's what git doesn't hold and no script can make again:

- `dist/`: the build that was actually sent out (DMG, its source archive, ffmpeg and LAME
  sources, checksums). A rebuild wouldn't be byte-identical: it would carry new signatures
  and a new notarization.
- `docs/SPEC.md`: Earl's spec, kept out of the public repo on purpose.
- `scripts/release.local.env`: the names of the signing identity and notarization profile
  (no secrets; those stay in the keychain).

Left out because a script makes them again: `build/` (Xcode output: `xcodebuild`; ffmpeg:
`scripts/build-ffmpeg.sh`, which re-downloads and checksums its sources; release staging:
`scripts/release.sh`) and `GawdSpeed.xcodeproj` (`xcodegen generate`).
