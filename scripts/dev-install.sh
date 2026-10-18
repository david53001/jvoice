#!/usr/bin/env bash
set -euo pipefail

# Build, install, and codesign JVoice. Uses a stable self-signed identity
# from the login keychain when available (see scripts/setup-signing.sh)
# so macOS TCC permissions persist across rebuilds. Falls back to ad-hoc
# with a warning if no identity is set up.
#
# Usage:  scripts/dev-install.sh   (developer build; the public one-liner is scripts/install.sh)

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="/Applications/JVoice.app"
BUILT_APP="$REPO_ROOT/dist/JVoice.app"

cd "$REPO_ROOT"

# Release build + bundle (Sparkle.framework embedded, signed inside-out with "JVoice Self-Signed"
# when present, else ad-hoc with a warning) — the same bundle package-release.sh ships.
echo "==> Building release bundle..."
JVOICE_APP="$BUILT_APP" scripts/build-app.sh release

echo "==> Stopping running JVoice..."
pkill -x JVoice 2>/dev/null || true
sleep 0.5

# Replaced as a whole (a copy over the old bundle would leave stale files inside it, which breaks
# its signature). Permissions survive: TCC keys them on the bundle id + certificate, not the path.
echo "==> Installing to $APP_PATH..."
rm -rf "$APP_PATH"
ditto "$BUILT_APP" "$APP_PATH"
codesign -dv "$APP_PATH" 2>&1 | grep -E "Identifier|Format|Signature"

echo "==> Registering bundle with Launch Services..."
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -f "$APP_PATH"

echo "==> Launching..."
open "$APP_PATH"

echo "==> Done."
