import React from "react";
import { Img, staticFile } from "remotion";

// The real macOS arrow pointer, extracted via NSCursor.arrow.
// Native image/hotspot baked from public/system/cursor-meta.json:
//   { hotspotX: 5, hotspotY: 5, width: 28, height: 40 }
// The native 28×40 image is displayed at a slightly smaller logical size so it
// reads at macOS pointer scale in this 1600×1000 comp; the hotspot scales with it.
const NATIVE_W = 28;
const NATIVE_H = 40;
const HOTSPOT_X = 5;
const HOTSPOT_Y = 5;

// Display size of the pointer.
const CURSOR_W = 21;
const CURSOR_H = (CURSOR_W / NATIVE_W) * NATIVE_H; // 30
const DISP_HOTSPOT_X = (HOTSPOT_X / NATIVE_W) * CURSOR_W; // ~3.75
const DISP_HOTSPOT_Y = (HOTSPOT_Y / NATIVE_H) * CURSOR_H; // ~3.75

export const Cursor: React.FC<{ x: number; y: number; scale?: number }> = ({
  x,
  y,
  scale = 1,
}) => (
  <Img
    src={staticFile("system/cursor-arrow.png")}
    style={{
      position: "absolute",
      left: x - DISP_HOTSPOT_X,
      top: y - DISP_HOTSPOT_Y,
      width: CURSOR_W,
      height: CURSOR_H,
      transform: `scale(${scale})`,
      transformOrigin: `${DISP_HOTSPOT_X}px ${DISP_HOTSPOT_Y}px`,
      zIndex: 9999,
      pointerEvents: "none",
      filter: "drop-shadow(0px 1px 1.5px rgba(0,0,0,0.35))",
    }}
  />
);
