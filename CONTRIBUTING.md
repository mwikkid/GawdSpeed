# Contributing to GawdSpeed

Thanks for your interest. A few ground rules:

- **License.** GawdSpeed is licensed under GPL-3.0-or-later. By contributing,
  you agree that your contribution is licensed under GPL-3.0-or-later. There is
  no CLA and no DCO sign-off.
- **Headers.** Every source file starts with
  `// SPDX-License-Identifier: GPL-3.0-or-later` and a copyright line.
- **Dependencies.** Anything new (library, code snippet, asset, font, icon,
  sound) needs a GPLv3-compatible license, recorded in `THIRD_PARTY_NOTICES.md`
  in the same commit. Vendored code goes under `ThirdParty/<name>/` with its
  original license, a `VERSION` file and a `MODIFICATIONS.md`.
- **No copyrighted audio.** Test audio must be generated or CC0, with its
  source listed in `TestAudio/SOURCES.md`.
- **Checks.** `scripts/check-licenses.sh` and the test suite must pass. CI runs
  both on every push.
