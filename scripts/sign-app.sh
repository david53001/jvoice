#!/usr/bin/env bash
# Signs an assembled JVoice.app inside-out: Sparkle's nested helpers, then the framework, then the
# app (no --deep: it would re-sign the helpers without their own options).
#
#   scripts/sign-app.sh path/to/JVoice.app
#
# Uses the stable "JVoice Self-Signed" identity from scripts/setup-signing.sh (login keychain), so
# the Microphone and Accessibility permissions survive every rebuild and update; without it, falls
# back to ad-hoc with a warning, or fails when JVOICE_REQUIRE_IDENTITY=1 (releases, the e2e test).
# Sparkle's helpers keep the hardened runtime they ship with (they load only system libraries); the
# app itself stays without it, as before: it is not sandboxed or notarized, and the runtime's library
# validation would refuse a Sparkle.framework signed by a self-signed certificate (no Team ID).
set -euo pipefail
APP="$1"

IDENTITY_LINE=$(security find-identity -p codesigning login.keychain 2>/dev/null | grep "\"JVoice Self-Signed\"" | head -1 || true)
if [ -n "$IDENTITY_LINE" ]; then
    # Addressed by SHA-1 so it works although the self-signed cert isn't user-trusted.
    SIGN=(--sign "$(echo "$IDENTITY_LINE" | awk '{print $2}')")
    WHO="stable identity 'JVoice Self-Signed'; permissions persist"
elif [ "${JVOICE_REQUIRE_IDENTITY:-0}" = 1 ]; then
    echo "error: no 'JVoice Self-Signed' identity; run scripts/setup-signing.sh (releases must all use the same cert)" >&2
    exit 1
else
    echo "warning: 'JVoice Self-Signed' not found; signing ad-hoc (run scripts/setup-signing.sh for persistent permissions)" >&2
    SIGN=(--sign -)
    WHO="ad-hoc"
fi

FW="$APP/Contents/Frameworks/Sparkle.framework"
if [ -d "$FW" ]; then
    V="$FW/Versions/B"
    # (build-app.sh removed the XPC services: only sandboxed apps use them.)
    codesign --force "${SIGN[@]}" -o runtime "$V/Autoupdate"
    codesign --force "${SIGN[@]}" -o runtime "$V/Updater.app"
    codesign --force "${SIGN[@]}" -o runtime "$FW"
fi

# No entitlements (not sandboxed). The identifier is the bundle's own id (com.jvoice.app; the e2e
# test's copies carry a test id), so the designated requirement stays
# `identifier "com.jvoice.app" and certificate leaf = H"…"` as on every release since 1.0.0 —
# what the Microphone and Accessibility permissions (TCC) are keyed on.
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")"
codesign --force "${SIGN[@]}" --identifier "$BUNDLE_ID" "$APP"
codesign --verify --deep --strict "$APP"
echo "Signed $APP ($WHO)"
