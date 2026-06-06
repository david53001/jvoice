#!/bin/bash
# Renders demo.html frame-by-frame with headless Chrome and assembles
# docs/assets/demo.gif (+ demo.mp4 for social). Usage: ./render.sh
set -euo pipefail
cd "$(dirname "$0")"

CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
FRAMES=80
OUT_DIR="frames"
PAGE="file://$PWD/demo.html"

rm -rf "$OUT_DIR" && mkdir -p "$OUT_DIR"

for ((i = 0; i < FRAMES; i++)); do
  n=$(printf "%03d" "$i")
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars \
    --force-device-scale-factor=2 --window-size=800,500 \
    --screenshot="$OUT_DIR/f$n.png" "$PAGE?f=$i" 2>/dev/null
done

# GIF: 10 fps, lanczos downscale to 800px, optimized palette
ffmpeg -y -framerate 10 -i "$OUT_DIR/f%03d.png" -vf \
  "scale=800:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128[p];[b][p]paletteuse=dither=bayer:bayer_scale=4" \
  ../demo.gif 2>/dev/null

# MP4 (for TikTok/Reels/site embeds later)
ffmpeg -y -framerate 10 -i "$OUT_DIR/f%03d.png" -c:v libx264 -pix_fmt yuv420p \
  -vf "scale=1600:-2" -crf 20 ../demo.mp4 2>/dev/null

echo "Done: $(du -h ../demo.gif | cut -f1) gif, $(du -h ../demo.mp4 | cut -f1) mp4"
