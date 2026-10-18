#!/usr/bin/env bash
# Builds, signs and packages a macOS release, ready to publish (docs/sparkle-updates/README.md):
#
#   scripts/package-release.sh [release-notes.md]
#
# 1. release build → dist/JVoice.app (scripts/build-app.sh: Sparkle.framework embedded, signed
#    inside-out with "JVoice Self-Signed" — required; scripts/setup-signing.sh)
# 2. dist/JVoice.app.zip (ditto, keeps the signature + framework symlinks) — the asset both
#    scripts/install.sh and Sparkle download — and dist/JVoice-<version>.dmg (manual download)
# 3. EdDSA-signs the zip with the Sparkle key from the login Keychain (sign_update)
# 4. dist/appcast.xml — the Sparkle feed for this one release; its URL in every installed app is
#    releases/LATEST/download/appcast.xml, so publishing this release as "latest" is what ships it
# 5. prints the exact `gh release create` command, tagged on this HEAD (it publishes nothing)
#
# Order: bump Resources/Info.plist → scripts/run-logic-tests.sh → commit → git push origin main →
# this script → the printed gh command (the checks below need the bump committed and pushed first).
#
# The optional notes file (Markdown) becomes both the GitHub release notes and the text Sparkle
# shows in its update window; without one, a short default pointing to the release page is used.
#
# Refuses to package (each check has an override, for dry runs only):
#   - uncommitted changes                                             ALLOW_DIRTY=1
#   - HEAD isn't origin/main (what the release will be tagged from)   ALLOW_NOT_MAIN=1
#   - the signing certificate isn't the one every earlier release used, so every user would have
#     to allow Microphone and Accessibility again; checked on the keychain before building and on
#     the built app after                                             ALLOW_NEW_CERT=1
#   - a GitHub release with this tag already exists                   (no override: bump the version)
#
# With any ALLOW_* override set it is a DRY RUN: everything goes to dist/dry-run/ under *-DRYRUN
# names (JVoice-DRYRUN.app.zip, JVoice-<version>-DRYRUN.dmg, appcast-DRYRUN.xml,
# release-notes-DRYRUN.md), it prints "DRY RUN - not publishable" and no gh command. Never upload
# those files (their appcast carries edSignature="DRYRUN-not-signed" and a DRYRUN-not-a-release.zip
# URL, so Sparkle would refuse it anyway).
#
# Windows releases (tags windows-v*) are made separately and MUST use --latest=false, or the Mac
# feed (releases/latest/download/appcast.xml) would point at a release without the Mac appcast.
set -euo pipefail
NOTES_FILE="${1:-}"
[ -z "$NOTES_FILE" ] || [ -f "$NOTES_FILE" ] || { echo "error: notes file '$NOTES_FILE' not found" >&2; exit 1; }
NOTES_FILE="${NOTES_FILE:+$(cd "$(dirname "$NOTES_FILE")" && pwd)/$(basename "$NOTES_FILE")}"
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
DIST="$ROOT/dist"
REPO="david53001/jvoice"
SPARKLE_BIN="${SPARKLE_BIN:-$HOME/Developer/Sparkle/2.10.0/bin}"
# SHA-1 of the "JVoice Self-Signed" certificate every release since v1.0.0 is signed with; the
# Microphone and Accessibility permissions are keyed on it (designated requirement
# `identifier "com.jvoice.app" and certificate leaf = H"…"`).
RELEASE_CERT="1164938af56472957620eeaaca96e33572677860"
IDENTITY="JVoice Self-Signed"

DRY_RUN=0
OVERRIDES=""
for override in ALLOW_DIRTY ALLOW_NOT_MAIN ALLOW_NEW_CERT; do
    if [ "${!override:-0}" = 1 ]; then DRY_RUN=1; OVERRIDES="$OVERRIDES $override=1"; fi
done

PLIST="$ROOT/Resources/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")"
MIN_OS="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$PLIST")"
TAG="v$VERSION"

[ -x "$SPARKLE_BIN/sign_update" ] || { echo "error: Sparkle tools not found in $SPARKLE_BIN" >&2; exit 1; }
[[ "$BUILD" =~ ^[0-9]+$ ]] || { echo "error: CFBundleVersion must be a whole number (got '$BUILD')" >&2; exit 1; }

# What gets packaged must be exactly what is committed and pushed to main.
if [ -n "$(git status --porcelain)" ] && [ "${ALLOW_DIRTY:-0}" != 1 ]; then
    echo "error: uncommitted changes (git status); commit them first, or ALLOW_DIRTY=1 for a dry run" >&2
    exit 1
fi
if [ "${ALLOW_NOT_MAIN:-0}" != 1 ]; then
    git fetch -q origin main || { echo "error: can't fetch origin/main to compare with HEAD" >&2; exit 1; }
    if [ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]; then
        echo "error: HEAD is not origin/main; merge and push first, or ALLOW_NOT_MAIN=1 for a dry run" >&2
        exit 1
    fi
fi

if ! command -v gh >/dev/null; then
    echo "error: gh (GitHub CLI) not found; it's needed to check for and publish the release" >&2
    exit 1
fi
if GH_OUT="$(gh release view "$TAG" --repo "$REPO" 2>&1)"; then
    echo "error: release $TAG already exists on $REPO; bump CFBundleShortVersionString in $PLIST" >&2
    exit 1
elif ! grep -qi "not found" <<<"$GH_OUT"; then
    echo "error: couldn't check whether release $TAG exists: $GH_OUT" >&2
    exit 1
fi

# Sparkle only offers an update whose CFBundleVersion is higher than the installed one, so refuse a
# build number that isn't above the currently published feed's (best effort: skipped when offline
# or before the first Sparkle release, whose "latest" carries no appcast yet).
LIVE_BUILD="$(curl -fsSL --max-time 10 "https://github.com/$REPO/releases/latest/download/appcast.xml" 2>/dev/null |
    sed -n 's:.*<sparkle\:version>\([0-9]*\)</sparkle\:version>.*:\1:p' | head -1 || true)"
if [ -n "$LIVE_BUILD" ] && [ "$BUILD" -le "$LIVE_BUILD" ]; then
    echo "error: CFBundleVersion $BUILD is not above the published build $LIVE_BUILD; bump it in $PLIST" >&2
    exit 1
fi

# The certificate, before spending a release build (checked again on the built app).
KEYCHAIN_CERT="$(security find-certificate -c "$IDENTITY" -Z login.keychain 2>/dev/null |
    sed -n 's/^SHA-1 hash: //p' | tr 'A-F' 'a-f' | head -1 || true)"
if [ "$KEYCHAIN_CERT" != "$RELEASE_CERT" ] && [ "${ALLOW_NEW_CERT:-0}" != 1 ]; then
    echo "error: the '$IDENTITY' certificate in the login keychain is '${KEYCHAIN_CERT:-missing}'," >&2
    echo "       not the release certificate $RELEASE_CERT. Every user would have to allow Microphone" >&2
    echo "       and Accessibility again. Restore the original identity (docs/sparkle-updates/README.md)," >&2
    echo "       or, only if the owner accepts that cost, set RELEASE_CERT to the new hash" >&2
    echo "       (ALLOW_NEW_CERT=1 for a dry run). Nothing was built." >&2
    exit 1
fi

if [ "$DRY_RUN" = 1 ]; then
    # Never the names a release uploads, and never next to them: nothing here can be published by mistake.
    OUT="$DIST/dry-run"
    APP="$OUT/JVoice.app"
    ZIP="$OUT/JVoice-DRYRUN.app.zip"
    DMG="$OUT/JVoice-$VERSION-DRYRUN.dmg"
    APPCAST="$OUT/appcast-DRYRUN.xml"
    NOTES_OUT="$OUT/release-notes-DRYRUN.md"
else
    OUT="$DIST"
    APP="$DIST/JVoice.app"
    ZIP="$DIST/JVoice.app.zip"
    DMG="$DIST/JVoice-$VERSION.dmg"
    APPCAST="$DIST/appcast.xml"
    NOTES_OUT="$DIST/release-notes.md"
fi
mkdir -p "$OUT"
rm -f "$ZIP" "$DMG" "$APPCAST" "$NOTES_OUT"
JVOICE_APP="$APP" JVOICE_REQUIRE_IDENTITY=1 scripts/build-app.sh release

CERT="$(codesign -d -r- "$APP" 2>&1 | sed -n 's/.*certificate leaf = H"\([0-9a-f]*\)".*/\1/p')"
if [ "$CERT" != "$RELEASE_CERT" ] && [ "${ALLOW_NEW_CERT:-0}" != 1 ]; then
    echo "error: signed with certificate $CERT, not the release certificate $RELEASE_CERT." >&2
    echo "       Every user would have to allow Microphone and Accessibility again. Restore the original" >&2
    echo "       identity (docs/sparkle-updates/README.md), or, only if the owner accepts that cost, set" >&2
    echo "       RELEASE_CERT to the new hash (ALLOW_NEW_CERT=1 for a dry run)." >&2
    exit 1
fi

echo "==> Zipping (ditto keeps the signature intact)..."
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> Building DMG..."
STAGE="$(mktemp -d)"; trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/JVoice.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "JVoice $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG"

# EdDSA signature + length for the appcast enclosure (key read from the Keychain, never printed).
SIGNATURE_ATTRS="$("$SPARKLE_BIN/sign_update" "$ZIP")"
"$SPARKLE_BIN/sign_update" --verify "$ZIP" "$(sed -n 's/.*edSignature="\([^"]*\)".*/\1/p' <<<"$SIGNATURE_ATTRS")" >/dev/null
ENCLOSURE_URL="https://github.com/$REPO/releases/download/$TAG/JVoice.app.zip"
if [ "$DRY_RUN" = 1 ]; then
    # Signing was checked just above; the dry-run feed gets neither that signature nor the real
    # download URL, so even uploaded (renamed or not), it can't install anything on any Mac.
    SIGNATURE_ATTRS="sparkle:edSignature=\"DRYRUN-not-signed\" length=\"$(stat -f %z "$ZIP")\""
    ENCLOSURE_URL="https://github.com/$REPO/releases/download/$TAG/DRYRUN-not-a-release.zip"
fi

if [ -n "$NOTES_FILE" ]; then
    cp "$NOTES_FILE" "$NOTES_OUT"
else
    printf 'JVoice %s. Details: https://github.com/%s/releases/tag/%s\n' "$VERSION" "$REPO" "$TAG" > "$NOTES_OUT"
fi

cat > "$APPCAST" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>JVoice</title>
    <link>https://github.com/$REPO</link>
    <item>
      <title>JVoice $VERSION</title>
      <pubDate>$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MIN_OS</sparkle:minimumSystemVersion>
      <description sparkle:format="markdown"><![CDATA[
$(sed 's/]]>/]]]]><![CDATA[>/g' "$NOTES_OUT")
]]></description>
      <enclosure url="$ENCLOSURE_URL"
                 type="application/octet-stream" $SIGNATURE_ATTRS />
    </item>
  </channel>
</rss>
XML
xmllint --noout "$APPCAST"

echo
echo "==> verify"
codesign --verify --deep --strict "$APP" && echo "code signature OK"
codesign -dvv "$APP" 2>&1 | grep -E '^(Identifier|Authority|Signature)=' || true
ls -la "$ZIP" "$DMG" "$APPCAST"
echo "JVoice $VERSION (build $BUILD)"
echo
if [ "$DRY_RUN" = 1 ]; then
    echo "==> DRY RUN - not publishable (overrides:$OVERRIDES)."
    echo "    The files in $OUT are for inspection only; never upload them. A real release runs"
    echo "    this script with no ALLOW_* variable and prints the gh command then."
    exit 0
fi
# --target: the tag is created on exactly the commit that was packaged, even if main moves on.
# --latest: the Mac feed reads releases/latest/download/appcast.xml.
echo "==> To publish, run exactly:"
echo "gh release create $TAG \"$ZIP\" \"$DMG\" \"$APPCAST\" --repo $REPO --target $(git rev-parse HEAD) --latest --title \"JVoice $VERSION\" --notes-file \"$NOTES_OUT\""
