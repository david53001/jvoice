#!/bin/bash
# One-line uninstaller for JVoice (macOS):
#
#   curl -fsSL https://raw.githubusercontent.com/david53001/jvoice/main/scripts/uninstall.sh | bash
#
# Quits JVoice and removes everything it put on this Mac: the app, its settings (custom
# words, stats and recent transcripts live there too), the downloaded Whisper models, its
# caches, and its Microphone / Accessibility permissions. Text you dictated into other
# apps is not touched. Reinstall any time with scripts/install.sh.
set -euo pipefail

APP_NAME="JVoice"
BUNDLE_ID="com.jvoice.app"
APP="/Applications/JVoice.app"

if [ "$(uname -s)" != "Darwin" ]; then echo "This uninstaller is for macOS." >&2; exit 1; fi

if pgrep -xq "$APP_NAME"; then
    echo "==> Quitting $APP_NAME..."
    osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
    for _ in $(seq 1 20); do pgrep -xq "$APP_NAME" || break; sleep 0.5; done
    pkill -x "$APP_NAME" 2>/dev/null || true
fi

echo "==> Removing $APP..."
rm -rf "$APP"

echo "==> Removing settings, Whisper models and caches..."
defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
# WhisperKit keeps models (and their download staging) under ~/Documents/huggingface/;
# only JVoice's Whisper folders are removed, then the parent folders if that left them empty.
HF="$HOME/Documents/huggingface/models"
rm -rf "$HOME/Library/Preferences/$BUNDLE_ID.plist" \
       "$HOME/Library/Application Support/JVoice" \
       "$HOME/Library/Caches/$BUNDLE_ID" "$HOME/Library/Caches/JVoice" \
       "$HOME/Library/HTTPStorages/$BUNDLE_ID" "$HOME/Library/HTTPStorages/JVoice" \
       "$HOME/Library/Saved Application State/$BUNDLE_ID.savedState" \
       "$HF"/argmaxinc/whisperkit-coreml/openai_whisper-* \
       "$HF"/argmaxinc/whisperkit-coreml/.cache/huggingface/download/openai_whisper-* \
       "$HF"/openai/whisper-*
for dir in "$HF"/argmaxinc/whisperkit-coreml/.cache/huggingface/download "$HF"/argmaxinc/whisperkit-coreml/.cache/huggingface \
           "$HF"/argmaxinc/whisperkit-coreml/.cache "$HF"/argmaxinc/whisperkit-coreml "$HF"/argmaxinc "$HF"/openai \
           "$HF" "$HOME/Documents/huggingface"; do
    rmdir "$dir" 2>/dev/null || true
done

echo "==> Resetting permissions..."
tccutil reset All "$BUNDLE_ID" >/dev/null 2>&1 || true

echo "Done. $APP_NAME is uninstalled."
