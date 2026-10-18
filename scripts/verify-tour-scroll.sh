#!/usr/bin/env bash
set -euo pipefail

# Local check that the guided tour's outline box + tag follow a scrolling window (Settings) in the same
# run-loop turn as the scroll — no lag, cut to the scroll view's viewport, hidden when scrolled out.
# Compiles the tour kit (Sources/JVoice/Tours/Kit) + catalog with scripts/tour-scroll-probe/main.swift
# and EXECUTES it. Light: a few transparent windows behind everything for about a second; no app
# launch, no UserDefaults writes, no WhisperKit.
#
# Usage:  scripts/verify-tour-scroll.sh

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

swiftc -O -o "$TMP_DIR/tour-scroll-probe" \
    "$REPO_ROOT"/Sources/JVoice/Tours/Kit/*.swift \
    "$REPO_ROOT/Sources/JVoice/Tours/TourCatalog.swift" \
    "$REPO_ROOT/Sources/JVoice/Tours/OpacityDemoTimeline.swift" \
    "$REPO_ROOT/Sources/JVoice/UI/UIOpacity.swift" \
    "$REPO_ROOT/Sources/JVoice/UI/Components/OpacityBacking.swift" \
    "$REPO_ROOT/scripts/tour-scroll-probe/main.swift"
"$TMP_DIR/tour-scroll-probe"
