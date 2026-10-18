# Sourced by the build/release/test scripts. The Command Line Tools' default MacOSX27.0 SDK expects a
# SwiftUIMacros compiler plugin the CLT doesn't ship (SwiftUI macros fail to build), so pin the
# 26.5 SDK when it's installed. An SDKROOT you set yourself wins; CI (no such SDK) is unaffected.
# Same file as MacStats' and BetterScreenshot's.
SDK_26_5="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
if [ -z "${SDKROOT:-}" ] && [ -d "$SDK_26_5" ]; then export SDKROOT="$SDK_26_5"; fi
