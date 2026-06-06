#!/usr/bin/env bash
set -euo pipefail

# Build, install, and codesign JVoice. Uses a stable self-signed identity
# from the login keychain when available (see scripts/setup-signing.sh)
# so macOS TCC permissions persist across rebuilds. Falls back to ad-hoc
# with a warning if no identity is set up.
#
# Usage:  scripts/install.sh

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="/Applications/JVoice.app"
BINARY="$REPO_ROOT/.build/release/JVoice"
INFO_PLIST_SRC="$REPO_ROOT/Resources/Info.plist"
ICON_SRC="$REPO_ROOT/Resources/AppIcon.icns"

cd "$REPO_ROOT"

echo "==> Building release..."
swift build -c release

echo "==> Stopping running JVoice..."
pkill -x JVoice 2>/dev/null || true
sleep 0.5

echo "==> Ensuring bundle structure..."
mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources"

echo "==> Syncing Info.plist..."
cp "$INFO_PLIST_SRC" "$APP_PATH/Contents/Info.plist"

echo "==> Writing PkgInfo..."
printf 'APPL????' > "$APP_PATH/Contents/PkgInfo"

echo "==> Installing binary..."
cp "$BINARY" "$APP_PATH/Contents/MacOS/JVoice"

# SPM emits a `<Package>_<Target>.bundle` next to the binary for any target with
# resources (KeyboardShortcuts 1.10+ ships .lproj localizations). Bundle.module
# fatalErrors at runtime if these aren't in Contents/Resources/, which is what
# crashed the Settings window when the KeyboardShortcuts.Recorder loaded.
echo "==> Installing SPM resource bundles..."
BUILD_DIR="$(dirname "$BINARY")"
rm -rf "$APP_PATH/Contents/Resources"/*.bundle
shopt -s nullglob
for bundle in "$BUILD_DIR"/*.bundle; do
    cp -R "$bundle" "$APP_PATH/Contents/Resources/"
done
shopt -u nullglob

echo "==> Installing app icon..."
if [ -f "$ICON_SRC" ]; then
    cp "$ICON_SRC" "$APP_PATH/Contents/Resources/AppIcon.icns"
else
    echo "    WARNING: $ICON_SRC not found."
fi

echo "==> Determining signing identity..."
# Look up by name, address codesign by SHA-1 hash so it works even when the
# self-signed cert hasn't been user-trusted via the keychain GUI (which would
# otherwise require an interactive password prompt during setup).
IDENTITY_LINE=$(security find-identity -p codesigning login.keychain 2>/dev/null \
    | grep "JVoice Self-Signed" | head -1 || true)
if [ -n "$IDENTITY_LINE" ]; then
    SIGN_IDENTITY=$(echo "$IDENTITY_LINE" | awk '{print $2}')
    echo "    Using stable identity: JVoice Self-Signed ($SIGN_IDENTITY) — TCC permissions persist"
else
    SIGN_IDENTITY="-"
    echo "    WARNING: Using ad-hoc signing. TCC permissions reset every build."
    echo "    Run scripts/setup-signing.sh once to fix this."
fi

echo "==> Re-signing..."
codesign --force --deep --sign "$SIGN_IDENTITY" --identifier com.jvoice.app "$APP_PATH"

echo "==> Verifying signature..."
codesign -dv "$APP_PATH" 2>&1 | grep -E "Identifier|Format|Signature"

echo "==> Registering bundle with Launch Services..."
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -f "$APP_PATH"

echo "==> Launching..."
open "$APP_PATH"

echo "==> Done."
