#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Earl Scioneaux, III
#
# Prints docs/guide/guide.html to docs/guide/GawdSpeed-Guide.pdf with headless
# Chrome. The PDF is committed; the app bundles it (Help > GawdSpeed Guide) and
# scripts/release.sh puts it in the DMG. Re-run after changing the controls.

set -euo pipefail
cd "$(dirname "$0")/.."
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
[[ -x "$CHROME" ]] || { echo "Needs Google Chrome (or set CHROME=/path/to/chrome)" >&2; exit 1; }
"$CHROME" --headless=new --disable-gpu --no-pdf-header-footer --allow-file-access-from-files \
    --print-to-pdf="$(pwd)/docs/guide/GawdSpeed-Guide.pdf" "file://$(pwd)/docs/guide/guide.html" 2>/dev/null
echo "Wrote docs/guide/GawdSpeed-Guide.pdf ($(mdls -raw -name kMDItemNumberOfPages docs/guide/GawdSpeed-Guide.pdf 2>/dev/null || echo '?') pages)"
