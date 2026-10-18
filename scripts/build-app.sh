#!/usr/bin/env bash
# Builds JVoice and assembles a signed JVoice.app (docs/sparkle-updates/README.md):
#
#   scripts/build-app.sh [release|debug]      (default release)
#
# JVOICE_APP                destination (default dist/JVoice.app; the Sparkle end-to-end test builds
#                           into its own scratch folder)
# JVOICE_SWIFT_FLAGS        extra `swift build` arguments (the end-to-end test uses this)
# JVOICE_REQUIRE_IDENTITY=1 fail instead of signing ad-hoc (package-release.sh sets it)
#
# Used by package-release.sh, dev-install.sh and sparkle-e2e-test.sh, so every JVoice.app is put
# together the same way: Sparkle.framework embedded in Contents/Frameworks, signed inside-out.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/sdk-env.sh

CONFIG="${1:-release}"
# shellcheck disable=SC2206
FLAGS=(${JVOICE_SWIFT_FLAGS:-})

echo "==> swift build -c $CONFIG ${FLAGS[*]+${FLAGS[*]}}"
swift build -c "$CONFIG" ${FLAGS[@]+"${FLAGS[@]}"}
BIN_DIR="$(swift build -c "$CONFIG" ${FLAGS[@]+"${FLAGS[@]}"} --show-bin-path)"
BIN="$BIN_DIR/JVoice"
[ -x "$BIN" ] || { echo "error: built executable not found at $BIN" >&2; exit 1; }

APP="${JVOICE_APP:-dist/JVoice.app}"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp Resources/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
cp "$BIN" "$APP/Contents/MacOS/JVoice"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# SPM resource bundles (KeyboardShortcuts localizations). These do NOT satisfy `Bundle.module` in a
# packaged app (Sources/JVoice/UI/CLAUDE.md); they're shipped so the localizations are present.
shopt -s nullglob
for bundle in "$BIN_DIR"/*.bundle; do cp -R "$bundle" "$APP/Contents/Resources/"; done
shopt -u nullglob

# Sparkle (auto-updates): the executable finds it through its @executable_path/../Frameworks rpath
# (Package.swift); ditto keeps the framework's symlinks. Its XPC services are only for sandboxed
# apps (JVoice isn't: it has no entitlements at all, so no app-sandbox key; Sparkle's docs say they
# may be removed then), so they go, and so do its headers and module map (only for compiling
# against it, as Xcode's "strip headers" does when embedding). sign-app.sh re-signs it afterwards.
FW="$APP/Contents/Frameworks/Sparkle.framework"
ditto "$BIN_DIR/Sparkle.framework" "$FW"
for DIR in XPCServices Headers PrivateHeaders Modules; do
    rm -rf "${FW:?}/$DIR" "${FW:?}/Versions/B/$DIR"
done

# SwiftPM also bakes in rpaths to folders on this Mac (the Command Line Tools' Swift folder) and
# @loader_path (the build folder, where Sparkle sits next to the binary). Sparkle is the only @rpath
# library (the Swift runtime is in /usr/lib/swift since macOS 12), so drop every rpath except
# /usr/lib/swift and @executable_path/../Frameworks: the app can only load the embedded Sparkle and
# carries no path from this Mac.
EXE="$APP/Contents/MacOS/JVoice"
if otool -L "$EXE" | awk 'NR > 1 { print $1 }' | grep '^@rpath/' | grep -qv '^@rpath/Sparkle.framework/'; then
    echo "error: a new @rpath library needs one of the rpaths removed below:" >&2
    otool -L "$EXE" | grep '@rpath/' >&2
    exit 1
fi
otool -l "$EXE" | awk '/cmd LC_RPATH/ { getline; getline; print $2 }' |
while read -r RPATH; do
    case "$RPATH" in
        /usr/lib/swift|@executable_path/../Frameworks) ;;
        *) install_name_tool -delete_rpath "$RPATH" "$EXE" ;;
    esac
done

# Signs inside-out with the stable "JVoice Self-Signed" identity when present (so the Microphone and
# Accessibility permissions persist across rebuilds and updates), else ad-hoc.
scripts/sign-app.sh "$APP"
echo "==> Built $APP"
