#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Earl Scioneaux, III
#
# Builds a release (spec §7.7, §10b): from a tagged, clean commit only, so the
# tag is the "corresponding source". Produces in dist/:
#   GawdSpeed-<version>.dmg               the app, LICENSE and notices
#   GawdSpeed-<version>-source.tar.gz     this repo at the tag
#   ffmpeg-<v>.tar.xz, lame-<v>.tar.gz    the bundled ffmpeg's exact sources
#   build-ffmpeg.sh                       how they were built
#
# Signing and notarization read credentials from the environment and the
# keychain only; nothing secret lives in this repo (spec §7.5):
#   DEVELOPER_ID_APPLICATION  e.g. "Developer ID Application: Name (TEAMID)"
#   NOTARY_PROFILE            a `xcrun notarytool store-credentials` profile name
# Without them the app is ad-hoc signed and the DMG is marked UNSIGNED.
#
# Usage: scripts/release.sh 0.2.0            (HEAD must be tagged v0.2.0)
#        scripts/release.sh 0.2.0 --dry-run  (any clean HEAD; for testing)

set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=${1:?usage: scripts/release.sh <version> [--dry-run]}
DRY_RUN=${2:-}
TAG="v$VERSION"
DIST=dist
APP_NAME=GawdSpeed

# 1. The tag is the corresponding source: clean tree, HEAD at the tag.
if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
    echo "Refusing to release: uncommitted changes (a release must be built from a tagged commit)." >&2
    exit 1
fi
if [[ "$DRY_RUN" != "--dry-run" ]]; then
    [[ "$(git rev-parse HEAD)" == "$(git rev-parse "$TAG^{commit}" 2>/dev/null)" ]] \
        || { echo "Refusing to release: HEAD is not tagged $TAG." >&2; exit 1; }
fi

scripts/check-licenses.sh

# 2. Build: bundled ffmpeg, project, universal Release app.
scripts/build-ffmpeg.sh
xcodegen generate
rm -rf build/release "$DIST"
mkdir -p "$DIST"
xcodebuild -project GawdSpeed.xcodeproj -scheme GawdSpeed -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath build/release \
    MARKETING_VERSION="$VERSION" build | grep -E "error:|\*\* " || true
APP="build/release/Build/Products/Release/$APP_NAME.app"
[[ -d "$APP" ]] || { echo "Build failed: no $APP" >&2; exit 1; }
[[ -x "$APP/Contents/Helpers/ffmpeg" ]] || { echo "Build has no bundled ffmpeg" >&2; exit 1; }

# 3. Sign: the helper first, then the app; hardened runtime, secure timestamp.
SIGNED=unsigned
if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
    codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID_APPLICATION" "$APP/Contents/Helpers/ffmpeg"
    codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID_APPLICATION" "$APP"
    codesign --verify --deep --strict "$APP"
    SIGNED=signed
    if [[ -n "${NOTARY_PROFILE:-}" ]]; then
        ditto -c -k --keepParent "$APP" build/release/notarize.zip
        xcrun notarytool submit build/release/notarize.zip --keychain-profile "$NOTARY_PROFILE" --wait
        xcrun stapler staple "$APP"
        SIGNED=notarized
    fi
else
    echo "warning: DEVELOPER_ID_APPLICATION not set; the app is ad-hoc signed and Gatekeeper will warn."
fi

# 4. DMG: the app, an Applications link, LICENSE and notices.
STAGE=build/release/dmg
rm -rf "$STAGE" && mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp LICENSE THIRD_PARTY_NOTICES.md "$STAGE/"
cp -R LICENSES "$STAGE/"
SUFFIX=$([[ $SIGNED == unsigned ]] && echo "-UNSIGNED" || echo "")
DMG="$DIST/$APP_NAME-$VERSION$SUFFIX.dmg"
hdiutil create -volname "$APP_NAME $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" > /dev/null
[[ $SIGNED != unsigned ]] && codesign --sign "$DEVELOPER_ID_APPLICATION" --timestamp "$DMG"
if [[ $SIGNED == notarized ]]; then
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
fi

# 5. Corresponding source (GPL): this repo at the tag, and ffmpeg's exact sources.
git archive --format=tar.gz --prefix="$APP_NAME-$VERSION/" -o "$DIST/$APP_NAME-$VERSION-source.tar.gz" HEAD
cp build/ffmpeg-src/ffmpeg-*.tar.xz build/ffmpeg-src/lame-*.tar.gz scripts/build-ffmpeg.sh "$DIST/"
cp build/ffmpeg/BUILDINFO.txt "$DIST/ffmpeg-BUILDINFO.txt"

(cd "$DIST" && shasum -a 256 * > SHA256SUMS)
echo "Release $VERSION ($SIGNED) in $DIST/:"
ls -la "$DIST"
