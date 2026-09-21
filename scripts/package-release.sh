#!/usr/bin/env bash
# Build the release bundle for a GitHub release and package it twice:
#   dist/JVoice.app.zip        — what scripts/install.sh (the one-liner) downloads
#   dist/JVoice-<version>.dmg  — the manual drag-to-Applications download
#
# Signs with the stable local "JVoice Self-Signed" identity (scripts/setup-signing.sh
# creates it once). This MUST be the same certificate on every release: macOS ties
# the Microphone/Accessibility permissions to bundle id + signing certificate, so a
# release signed by the same cert updates in place without re-asking. Refuses to
# build ad-hoc for that reason.
#
# Usage:  scripts/package-release.sh        (version comes from Resources/Info.plist)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"
DIST="$REPO_ROOT/dist"
APP="$DIST/JVoice.app"
BINARY="$REPO_ROOT/.build/release/JVoice"
VERSION="$(defaults read "$REPO_ROOT/Resources/Info.plist" CFBundleShortVersionString)"

IDENTITY_LINE=$(security find-identity -p codesigning login.keychain 2>/dev/null | grep "JVoice Self-Signed" | head -1 || true)
[ -n "$IDENTITY_LINE" ] || { echo "error: no 'JVoice Self-Signed' identity — run scripts/setup-signing.sh first (releases must all use the same cert)." >&2; exit 1; }
SIGN_IDENTITY=$(echo "$IDENTITY_LINE" | awk '{print $2}')

echo "==> Building release ($VERSION)..."
swift build -c release

echo "==> Assembling bundle..."
rm -rf "$DIST"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$REPO_ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
cp "$BINARY" "$APP/Contents/MacOS/JVoice"
cp "$REPO_ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
# SPM resource bundles (KeyboardShortcuts localizations). These do NOT satisfy
# `Bundle.module` in a packaged app — see the longer note in dev-install.sh.
shopt -s nullglob
for bundle in "$(dirname "$BINARY")"/*.bundle; do cp -R "$bundle" "$APP/Contents/Resources/"; done
shopt -u nullglob

echo "==> Signing with JVoice Self-Signed ($SIGN_IDENTITY)..."
codesign --force --deep --sign "$SIGN_IDENTITY" --identifier com.jvoice.app "$APP"
codesign --verify --deep --strict "$APP"
codesign -d -r- "$APP" 2>&1 | grep designated

echo "==> Zipping (ditto keeps the signature intact)..."
ditto -c -k --keepParent "$APP" "$DIST/JVoice.app.zip"

echo "==> Building DMG..."
STAGE="$(mktemp -d)"; trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/JVoice.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "JVoice $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DIST/JVoice-$VERSION.dmg"

ls -la "$DIST"/JVoice.app.zip "$DIST"/JVoice-"$VERSION".dmg
echo "==> Done. Publish with:"
echo "    gh release create v$VERSION dist/JVoice.app.zip dist/JVoice-$VERSION.dmg --title \"JVoice $VERSION\" --notes-file <notes.md>"
