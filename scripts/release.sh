#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Earl Scioneaux, III
#
# Builds a release (spec §7.7, §10b): from a tagged, clean commit only, so the
# tag is the "corresponding source". Produces in dist/:
#   GawdSpeed-<version>.dmg               the app, an Applications link, and Docs/ (guide, licenses)
#   GawdSpeed-<version>-source.tar.gz     this repo at the tag
#   ffmpeg-<v>.tar.xz, lame-<v>.tar.gz    the bundled ffmpeg's exact sources
#   build-ffmpeg.sh                       how they were built
#
# Signing happens on this Mac only. The certificate and the notarization
# login stay in the keychain, and are never uploaded to GitHub (Earl's call,
# 2026-10-06). Their names come from the environment or from the git-ignored
# scripts/release.local.env:
#   DEVELOPER_ID_APPLICATION  e.g. "Developer ID Application: Name (TEAMID)"
#   NOTARY_PROFILE            a `xcrun notarytool store-credentials` profile name
# Without them the app is ad-hoc signed and the DMG is marked UNSIGNED.
#
# A pre-release suffix (0.1.0-beta1) names the files; the app's version is
# the number before it (macOS version strings are numbers only).
#
# Usage: scripts/release.sh 0.2.0            (HEAD must be tagged v0.2.0)
#        scripts/release.sh 0.2.0 --dry-run  (any clean HEAD; for testing)
#        scripts/release.sh 0.2.0 --publish  (tagged; also creates the public
#                                             GitHub Release. Only when Earl says.)

set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=${1:?usage: scripts/release.sh <version> [--dry-run | --publish]}
MODE=${2:-}
DRY_RUN=$([[ "$MODE" == "--dry-run" ]] && echo "--dry-run" || echo "")
# UNSIGNED=1 skips the local signing setup (for testing the build alone).
[[ -z "${UNSIGNED:-}" && -f scripts/release.local.env ]] && source scripts/release.local.env
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

# The app links to this commit's source on GitHub, so it must be pushed.
COMMIT=$(git rev-parse HEAD)
git fetch -q origin
git merge-base --is-ancestor "$COMMIT" origin/main \
    || { echo "Refusing to build: push $COMMIT first (the app links to its source on GitHub)." >&2; exit 1; }

# Check the notarization login before a long build, not after it.
if [[ -n "${DEVELOPER_ID_APPLICATION:-}" && -n "${NOTARY_PROFILE:-}" ]]; then
    xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" > /dev/null 2>&1 || {
        echo "The notarization login '$NOTARY_PROFILE' isn't in the keychain. Recreate it with:" >&2
        echo "  xcrun notarytool store-credentials $NOTARY_PROFILE --team-id TT4MXN2YL4" >&2
        echo "(it asks for the Apple ID and an app-specific password from account.apple.com)" >&2
        exit 1
    }
fi

# 2. Build from a clean copy of the commit, never the working folder, so the
#    app matches its published source exactly (GPL corresponding source).
SRC=build/release-src
rm -rf build/release "$SRC" "$DIST"
mkdir -p "$SRC" "$DIST"
git archive HEAD | tar -x -C "$SRC"
mkdir -p "$SRC/build" && [[ -d build/ffmpeg-src ]] && cp -R build/ffmpeg-src "$SRC/build/"   # reuse downloads
(cd "$SRC" && scripts/build-ffmpeg.sh && xcodegen generate)
xcodebuild -project "$SRC/GawdSpeed.xcodeproj" -scheme GawdSpeed -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath build/release \
    MARKETING_VERSION="${VERSION%%-*}" GS_SOURCE_COMMIT="$COMMIT" build | grep -E "error:|\*\* " || true
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

# 4. DMG: a styled window with just GawdSpeed, an Applications link and a
#    Docs folder (guide and licenses), over a background that says what to
#    do. Icon slots match scripts/make-dmg-background.py.
STAGE=build/release/dmg
rm -rf "$STAGE" && mkdir -p "$STAGE/Docs" "$STAGE/.background"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp "$SRC/docs/guide/GawdSpeed-Guide.pdf" "$SRC/LICENSE" "$SRC/THIRD_PARTY_NOTICES.md" "$STAGE/Docs/"
cp -R "$SRC/LICENSES" "$STAGE/Docs/"
cp "$SRC/Branding/dmg-background.tiff" "$STAGE/.background/background.tiff"
SUFFIX=$([[ $SIGNED == unsigned ]] && echo "-UNSIGNED" || echo "")
DMG="$DIST/$APP_NAME-$VERSION$SUFFIX.dmg"
VOLUME="$APP_NAME $VERSION"
RW=build/release/rw.dmg
hdiutil create -volname "$VOLUME" -srcfolder "$STAGE" -ov -format UDRW -fs HFS+ "$RW" > /dev/null
MOUNT=$(hdiutil attach -readwrite -noverify -noautoopen "$RW" | awk -F'\t' '/\/Volumes\// {print $NF}')
osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$VOLUME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 840, 548}
        set opts to the icon view options of container window
        set arrangement of opts to not arranged
        set icon size of opts to 80
        set text size of opts to 13
        set background picture of opts to file ".background:background.tiff"
        set position of item "$APP_NAME.app" of container window to {170, 140}
        set position of item "Applications" of container window to {470, 140}
        set position of item "Docs" of container window to {300, 254}
        close
        open
        update without registering applications
        delay 2
        close
    end tell
end tell
APPLESCRIPT
# The disk's icon, added after Finder has laid out the window: hdiutil
# -srcfolder leaves .VolumeIcon.icns out, and when copied in before the
# Finder step it was gone by the time the disk was unmounted.
cp "$APP/Contents/Resources/AppIcon.icns" "$MOUNT/.VolumeIcon.icns"
SetFile -a C "$MOUNT"
sync
hdiutil detach -quiet "$MOUNT"
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -ov -o "$DMG" > /dev/null
rm -f "$RW"
[[ $SIGNED != unsigned ]] && codesign --sign "$DEVELOPER_ID_APPLICATION" --timestamp "$DMG"
if [[ $SIGNED == notarized ]]; then
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
fi

# 5. Corresponding source (GPL): this repo at the tag, and ffmpeg's exact sources.
git archive --format=tar.gz --prefix="$APP_NAME-$VERSION/" -o "$DIST/$APP_NAME-$VERSION-source.tar.gz" HEAD
cp "$SRC"/build/ffmpeg-src/ffmpeg-*.tar.xz "$SRC"/build/ffmpeg-src/lame-*.tar.gz "$SRC/scripts/build-ffmpeg.sh" "$DIST/"
cp "$SRC/build/ffmpeg/BUILDINFO.txt" "$DIST/ffmpeg-BUILDINFO.txt"

(cd "$DIST" && shasum -a 256 * > SHA256SUMS)
echo "Release $VERSION ($SIGNED) in $DIST/:"
ls -la "$DIST"

# 6. Publish (public!) only when asked, and only a signed build of a tag.
if [[ "$MODE" == "--publish" ]]; then
    [[ $SIGNED == notarized ]] || { echo "Not publishing: the build is $SIGNED, not notarized." >&2; exit 1; }
    git push origin "$TAG"
    REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
    gh release create "$TAG" "$DIST"/* --title "GawdSpeed $VERSION" --notes \
"Built from tag [$TAG](https://github.com/$REPO/tree/$TAG), which is this release's corresponding source.

GawdSpeed is free software under the GNU GPL v3 or later. The DMG includes the license and third-party notices. Also attached: the source at this tag, and the exact FFmpeg and LAME sources plus the script that built the bundled ffmpeg."
fi
