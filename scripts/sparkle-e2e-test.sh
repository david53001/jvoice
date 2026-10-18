#!/usr/bin/env bash
# End-to-end test of Sparkle auto-updates, on a throwaway copy of JVoice (docs/sparkle-updates/README.md):
#
#   scripts/sparkle-e2e-test.sh [work-dir]   (default: a new temp dir; deleted at the end unless KEEP=1)
#
# 1. builds JVoice once (debug, this Mac's architecture) with -DSPARKLE_E2E_TEST: logs Sparkle's
#    steps, installs right away instead of on quit, and starts nothing but the updater (no status
#    item, hotkeys, microphone, model load, orphan-WAV sweep or Welcome window). The build goes to
#    E2E_BUILD_DIR (default <work-dir>/build; a full WhisperKit debug build, a few minutes — point
#    E2E_BUILD_DIR at a kept folder such as .build/sparkle-e2e to reuse it between runs)
# 2. makes two copies with bundle id com.jvoice.app.sparkletest: OLD (build 100, 90.0) and NEW
#    (build 101, 90.1), both with SUFeedURL = a python http.server on 127.0.0.1 only, signed
#    inside-out with the real "JVoice Self-Signed" identity; NEW is zipped and EdDSA-signed with
#    the real Sparkle key from the login Keychain
# 3. GOOD: OLD runs, finds NEW in the local appcast, downloads, verifies, installs, relaunches;
#    checks the installed bundle is build 101 and passes codesign --verify --deep --strict
# 4. BAD: same with an appcast whose signature doesn't match the zip; checks it is refused and the
#    installed copy stays build 100
#
# Never touches the real JVoice (/Applications or dist/), its bundle id's defaults or a running
# copy: everything is keyed by the test bundle id and the work dir's path. Quits what it started
# and removes the test bundle id's defaults, caches and Launch Services entries.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SPARKLE_BIN="${SPARKLE_BIN:-$HOME/Developer/Sparkle/2.10.0/bin}"
TEST_ID="com.jvoice.app.sparkletest"
PORT="${PORT:-8767}"
WORK="${1:-$(mktemp -d)}"
mkdir -p "$WORK"
WORK="$(cd "$WORK" && pwd -P)"
BUILD_DIR="${E2E_BUILD_DIR:-$WORK/build}"
INSTALL="$WORK/install/JVoice.app"
FEED="$WORK/feed"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
SERVER_PID=""

say() { printf '\n==> %s\n' "$*"; }

stop_test_apps() {
    # Only processes running from this work dir or Sparkle's per-app cache for the test id.
    pkill -f "$WORK/install/JVoice.app/" 2>/dev/null || true
    pkill -f "Caches/$TEST_ID/" 2>/dev/null || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        pgrep -f "$WORK/install/JVoice.app/" >/dev/null || break
        sleep 0.5
    done
}

reset_test_state() {
    defaults delete "$TEST_ID" >/dev/null 2>&1 || true
    rm -f "$HOME/Library/Preferences/$TEST_ID.plist"
    rm -rf "$HOME/Library/Caches/$TEST_ID" "$HOME/Library/HTTPStorages/$TEST_ID" \
           "$HOME/Library/HTTPStorages/$TEST_ID.binarycookies" \
           "$HOME/Library/Saved Application State/$TEST_ID.savedState"
}

cleanup() {
    set +e
    stop_test_apps
    [ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null
    reset_test_state
    [ -x "$LSREGISTER" ] && for app in "$WORK"/*/JVoice.app; do [ -d "$app" ] && "$LSREGISTER" -u "$app" 2>/dev/null; done
    if [ "${KEEP:-0}" != 1 ]; then rm -rf "$WORK"; else echo "kept $WORK"; fi
}
trap cleanup EXIT

if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "error: port $PORT is in use; set PORT=..." >&2; exit 1
fi

say "build (SPARKLE_E2E_TEST) into $WORK/stage (build folder $BUILD_DIR)"
JVOICE_APP="$WORK/stage/JVoice.app" JVOICE_REQUIRE_IDENTITY=1 \
    JVOICE_SWIFT_FLAGS="--scratch-path $BUILD_DIR -Xswiftc -DSPARKLE_E2E_TEST" \
    "$ROOT/scripts/build-app.sh" debug >"$WORK/build.log" 2>&1 || { tail -30 "$WORK/build.log"; exit 1; }

# make_variant <build> <version> <dest>
make_variant() {
    local dest="$3/JVoice.app" plist="$3/JVoice.app/Contents/Info.plist"
    mkdir -p "$3"
    ditto "$WORK/stage/JVoice.app" "$dest"
    /usr/libexec/PlistBuddy \
        -c "Set :CFBundleIdentifier $TEST_ID" \
        -c "Set :CFBundleVersion $1" \
        -c "Set :CFBundleShortVersionString $2" \
        -c "Set :SUFeedURL http://127.0.0.1:$PORT/appcast.xml" \
        -c "Add :NSAppTransportSecurity dict" \
        -c "Add :NSAppTransportSecurity:NSAllowsLocalNetworking bool true" \
        -c "Add :SUAutomaticallyUpdate bool true" \
        "$plist"
    JVOICE_REQUIRE_IDENTITY=1 "$ROOT/scripts/sign-app.sh" "$dest" >"$3.sign.log" 2>&1 || { cat "$3.sign.log"; exit 1; }
}

# write_appcast <zip> <edSignature attrs>
write_appcast() {
    cat > "$FEED/appcast.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>JVoice (end-to-end test)</title>
    <item>
      <title>JVoice 90.1 (test)</title>
      <pubDate>$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')</pubDate>
      <sparkle:version>101</sparkle:version>
      <sparkle:shortVersionString>90.1</sparkle:shortVersionString>
      <description sparkle:format="markdown"><![CDATA[Test update.]]></description>
      <enclosure url="http://127.0.0.1:$PORT/$(basename "$1")" type="application/octet-stream" $2 />
    </item>
  </channel>
</rss>
XML
}

installed_build() { /usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INSTALL/Contents/Info.plist"; }

# run_old <log> <seconds>: launch OLD, wait until the installed copy is NEW or time runs out.
run_old() {
    rm -rf "$WORK/install" && make_variant 100 90.0 "$WORK/install"
    reset_test_state
    # Make the daily check due right away (no "may we check?" dialog: SUEnableAutomaticChecks).
    defaults write "$TEST_ID" SULastCheckTime -date "2000-01-01 00:00:00 +0000"
    echo "launching OLD: build $(installed_build), $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INSTALL/Contents/Info.plist")"
    "$INSTALL/Contents/MacOS/JVoice" >"$1" 2>&1 &
    local pid=$! waited=0 loads=""
    for delay in 0.7 1 1; do   # vmmap can race the launch
        sleep "$delay"
        loads="$(vmmap "$pid" 2>/dev/null | grep -o '/[^ ]*Sparkle.framework/Versions/B/Sparkle' | sort -u || true)"
        [ -n "$loads" ] && break
    done
    echo "OLD pid $pid loads Sparkle from: ${loads:-(not seen: the process had already exited or relaunched)}"
    while [ "$waited" -lt "$2" ] && [ "$(installed_build)" = 100 ] && ! grep -q 'SPARKLE-E2E aborted' "$1"; do
        sleep 1; waited=$((waited + 1))
    done
    sleep 3   # let the relaunch happen
    echo "after ${waited}s: installed build $(installed_build)"
    grep -o 'SPARKLE-E2E.*' "$1" || true
}

mkdir -p "$FEED"
make_variant 101 90.1 "$WORK/new"
ditto -c -k --keepParent "$WORK/new/JVoice.app" "$FEED/JVoice-good.zip"
GOOD_ATTRS="$("$SPARKLE_BIN/sign_update" "$FEED/JVoice-good.zip")"

python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$FEED" >"$WORK/server.log" 2>&1 &
SERVER_PID=$!
sleep 1

say "GOOD: signed update 100 -> 101"
write_appcast "$FEED/JVoice-good.zip" "$GOOD_ATTRS"
run_old "$WORK/good.log" 90
GOOD_RESULT="$(installed_build)"
if [ "$GOOD_RESULT" = 101 ]; then
    codesign --verify --deep --strict "$INSTALL" && echo "installed copy: codesign --verify --deep --strict OK"
    codesign -dvv "$INSTALL" 2>&1 | grep -E '^(Identifier|Authority)='
    echo "installed copy: version $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INSTALL/Contents/Info.plist") (build $GOOD_RESULT)"
    echo "running after relaunch:"; pgrep -fl "$WORK/install/JVoice.app/Contents/MacOS/JVoice" || echo "(not relaunched)"
fi
stop_test_apps

say "BAD: zip whose EdDSA signature doesn't match"
# Same zip and length, but the signature of different bytes (the OLD copy zipped).
ditto -c -k --keepParent "$WORK/install/JVoice.app" "$WORK/other.zip"
BAD_SIG="$("$SPARKLE_BIN/sign_update" -p "$WORK/other.zip")"
cp "$FEED/JVoice-good.zip" "$FEED/JVoice-bad.zip"
write_appcast "$FEED/JVoice-bad.zip" "sparkle:edSignature=\"$BAD_SIG\" length=\"$(stat -f %z "$FEED/JVoice-bad.zip")\""
run_old "$WORK/bad.log" 45
BAD_RESULT="$(installed_build)"
stop_test_apps

say "server requests"
cat "$WORK/server.log"

say "RESULT"
PASS=1
if [ "$GOOD_RESULT" = 101 ]; then echo "GOOD update installed (build 101): PASS"; else echo "GOOD update NOT installed (build $GOOD_RESULT): FAIL"; PASS=0; fi
if [ "$BAD_RESULT" = 100 ]; then echo "BAD signature refused (still build 100): PASS"; else echo "BAD signature installed (build $BAD_RESULT): FAIL"; PASS=0; fi
[ "$PASS" = 1 ]
