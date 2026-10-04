#!/usr/bin/env bash
set -euo pipefail

# Builds a standalone spoken-maths probe with plain `swiftc` (no SwiftPM):
# the Math engine (Sources/JVoice/Services/Transcription/Math/) is pure Swift with
# no dependencies, so this works even when `swift build` is broken (it was on
# 2026-10-04: a Command Line Tools 26.6 swift-package/BuildServerProtocol mismatch).
#
# Usage:  scripts/build-math-probe.sh [output-path]   (default .build/math-probe)
# Then:   .build/math-probe "<text>"   or   .build/math-probe < corpus.txt
# Output is identical to `JVoice --math-probe`: CHANGED|before|after / same|text.

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$REPO_ROOT/.build/math-probe}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

cat > "$TMP_DIR/main.swift" <<'EOF'
MathProbe.runAndExit(arguments: ["math-probe", "--math-probe"] + CommandLine.arguments.dropFirst())
EOF

mkdir -p "$(dirname "$OUT")"
swiftc -O -module-name MathProbeCLI -o "$OUT" \
  "$REPO_ROOT"/Sources/JVoice/Services/Transcription/Math/*.swift \
  "$TMP_DIR/main.swift"
echo "built $OUT"
