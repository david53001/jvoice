#!/bin/bash
# One-line installer AND updater for JVoice (macOS 14+, Apple Silicon):
#
#   curl -fsSL https://raw.githubusercontent.com/david53001/jvoice/main/scripts/install.sh | bash
#
# Downloads the newest macOS release from GitHub, puts JVoice.app in
# /Applications (replacing an older copy), removes the quarantine flag (the app
# is self-signed, not notarized — this project has no paid Apple Developer
# account, so Gatekeeper would otherwise refuse to open it), and launches it.
#
# Running it again later UPDATES the app. Nothing else is touched, so settings,
# custom words, stats and recent transcripts (all in
# ~/Library/Preferences/com.jvoice.app.plist), the downloaded Whisper model
# (~/Documents/huggingface/), launch-at-login, and the Microphone +
# Accessibility permissions all carry over — macOS ties those permissions to
# the app's bundle id plus signing certificate, and every release is signed
# with the same certificate, so the app does not ask again.
set -euo pipefail

REPO="david53001/jvoice"
ASSET="JVoice.app.zip"
DEST="/Applications/JVoice.app"

if [ "$(uname -s)" != "Darwin" ]; then echo "JVoice is a macOS app (there is a separate Windows installer on the releases page)." >&2; exit 1; fi
MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
if [ "$MAJOR" -lt 14 ]; then echo "JVoice needs macOS 14 (Sonoma) or newer; you have $(sw_vers -productVersion)." >&2; exit 1; fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# The repo also publishes Windows releases, so "latest" may not be a macOS
# release: pick the newest release that carries the macOS asset. The API lists
# releases newest-first; no jq/python needed (stock macOS may lack both).
echo "==> Finding the newest macOS release..."
URL="$(curl -fsSL "https://api.github.com/repos/$REPO/releases?per_page=30" \
    | grep -o "\"browser_download_url\": *\"[^\"]*/$ASSET\"" | head -1 | sed 's/.*"\(https[^"]*\)"/\1/')"
[ -n "$URL" ] || { echo "error: no release with $ASSET found for $REPO" >&2; exit 1; }
echo "    $URL"

echo "==> Downloading..."
curl -fsSL -o "$TMP/$ASSET" "$URL"
ditto -x -k "$TMP/$ASSET" "$TMP"
[ -d "$TMP/JVoice.app" ] || { echo "error: archive did not contain JVoice.app" >&2; exit 1; }
codesign --verify --deep --strict "$TMP/JVoice.app" 2>/dev/null || { echo "error: downloaded app failed signature verification" >&2; exit 1; }

if pgrep -xq JVoice; then
    echo "==> Quitting the running copy (it saves its settings on quit)..."
    osascript -e 'tell application id "com.jvoice.app" to quit' >/dev/null 2>&1 || pkill -x JVoice || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -xq JVoice || break; sleep 0.5; done
    pkill -x JVoice 2>/dev/null || true
fi

echo "==> Installing to ${DEST}..."
rm -rf "$DEST"
ditto "$TMP/JVoice.app" "$DEST"
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

echo "==> Launching..."
open -a "$DEST"
VERSION="$(defaults read "$DEST/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "?")"
echo "Done — JVoice $VERSION is installed. Look for the J in your menu bar; press ⌥Space to dictate."
echo "First install only: macOS asks for Microphone and Accessibility access, then the Whisper model downloads."
