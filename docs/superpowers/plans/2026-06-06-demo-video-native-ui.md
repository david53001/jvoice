# Demo Video: Native-Identical Apple UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Remotion demo's macOS environment indistinguishable from the real thing. David rejected the current hand-drawn approximations: the Notes window has a *yellow title bar that real Notes does not have*, the dock icons are generic colored rectangles, and the menu-bar glyphs are hand-traced SVGs.

**Architecture — the key insight:** the video renders **locally on this Mac**, so we don't need to *approximate* Apple's UI — we can *extract the real artifacts*: real app icons via `NSWorkspace`, real SF Symbols via `NSImage(systemSymbolName:)`, the real macOS wallpaper from `/System/Library/Desktop Pictures`, and the real arrow cursor from `NSCursor.arrow`. A single Swift extraction script materializes everything into `docs/demo-video/public/system/`; the React components then consume pixel-true PNGs instead of hand-drawn shapes. The only remaining hand-built chrome (window frame, menu bar layout, dock panel) is rebuilt to measured macOS metrics. Text renders in genuine SF Pro because Chrome-on-macOS resolves `-apple-system` natively.

**Tech Stack:** Swift (AppKit) extraction script, Remotion 4 (`Img` + `staticFile`), ffmpeg (gif).

**Session constraints:**
- NO git commits/pushes.
- Visual verification is MANDATORY at every step: render stills, Read them, compare, iterate. The acceptance bar is David's: "the Apple UI must be completely identical."
- JVoice's own UI (HUD pill, settings panel, menu dropdown contents) is already product-exact from DESIGN-TOKENS.md — do not redesign it; only the *Apple environment* changes. One exception: the JVoice status item becomes a "J" (see app-identity plan).

**Verified facts:**
- All needed SF Symbols exist on this machine (apple.logo, wifi, battery.100, switch.2, magnifyingglass, mic.fill, list.bullet, square.grid.2x2, trash, square.and.pencil, textformat, checklist, sidebar.left, square.and.arrow.up, lock.open.fill — spike-tested OK).
- `/System/Library/Desktop Pictures/Sonoma.heic` exists; ffmpeg at `/opt/homebrew/bin/ffmpeg`.
- Dock trash icon candidates: `/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/TrashIcon.icns` (check at runtime; fall back to `FullTrashIcon.icns`, then to NSWorkspace icon for `~/.Trash`).
- Composition: 1600×1000@30fps, 600 frames, `docs/demo-video/src/Root.tsx`.

---

### Task 1: Asset extraction script

**Files:**
- Create: `docs/demo-video/scripts/extract-assets.swift`
- Output dir: `docs/demo-video/public/system/` (gitignored? check `docs/demo-video/.gitignore` — assets SHOULD be committed eventually so CI/other machines can render; do not add to gitignore)

- [ ] **Step 1: Write the script**

```swift
#!/usr/bin/env swift
//
// Extracts the real macOS UI artifacts the demo video needs into
// docs/demo-video/public/system/. Everything the video shows of Apple's UI
// comes from the OS itself — real app icons, real SF Symbols, the real
// wallpaper, the real cursor — so the recreation is pixel-true.
//
// Usage:  swift docs/demo-video/scripts/extract-assets.swift
//
import AppKit
import Foundation

let scriptURL = URL(fileURLWithPath: #filePath)
let videoRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let outDir = videoRoot.appendingPathComponent("public/system")
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func writePNG(_ image: NSImage, to url: URL, width: Int, height: Int) {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: width, height: height),
               from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
    print("• \(url.lastPathComponent) (\(width)x\(height))")
}

// ---------- 1) Real app icons (dock) ----------
let apps: [(name: String, path: String)] = [
    ("finder",   "/System/Library/CoreServices/Finder.app"),
    ("safari",   "/Applications/Safari.app"),
    ("messages", "/System/Applications/Messages.app"),
    ("notes",    "/System/Applications/Notes.app"),
    ("settings", "/System/Applications/System Settings.app"),
]
for app in apps {
    let icon = NSWorkspace.shared.icon(forFile: app.path)
    writePNG(icon, to: outDir.appendingPathComponent("app-\(app.name).png"), width: 256, height: 256)
}

// Trash: the Dock's icon lives in CoreTypes.
let coreTypes = "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources"
let trashCandidates = ["\(coreTypes)/TrashIcon.icns", "\(coreTypes)/FullTrashIcon.icns"]
var trashWritten = false
for candidate in trashCandidates where !trashWritten {
    if let img = NSImage(contentsOfFile: candidate) {
        writePNG(img, to: outDir.appendingPathComponent("app-trash.png"), width: 256, height: 256)
        trashWritten = true
    }
}
if !trashWritten {
    let trashURL = FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first!
    writePNG(NSWorkspace.shared.icon(forFile: trashURL.path),
             to: outDir.appendingPathComponent("app-trash.png"), width: 256, height: 256)
}

// ---------- 2) Real SF Symbols, recolored, @4x ----------
// Draw the symbol, then recolor every pixel via .sourceIn — deterministic flat
// tint without relying on palette-config rendering quirks.
func symbolPNG(_ symbol: String, fileName: String, pointSize: CGFloat,
               weight: NSFont.Weight, hex: (CGFloat, CGFloat, CGFloat), alpha: CGFloat = 1.0) {
    let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
    guard let base = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
        .withSymbolConfiguration(config) else {
        print("⚠️ MISSING SYMBOL: \(symbol)")
        return
    }
    let scale: CGFloat = 4
    let w = Int(ceil(base.size.width * scale)), h = Int(ceil(base.size.height * scale))
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: CGFloat(w), height: CGFloat(h))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    base.draw(in: NSRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)),
              from: .zero, operation: .sourceOver, fraction: 1)
    NSColor(srgbRed: hex.0, green: hex.1, blue: hex.2, alpha: alpha).set()
    NSRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)).fill(using: .sourceIn)
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: outDir.appendingPathComponent(fileName))
    print("• \(fileName) (\(w)x\(h))")
}

let menuBarWhite: (CGFloat, CGFloat, CGFloat) = (1, 1, 1)
let toolbarGray: (CGFloat, CGFloat, CGFloat) = (0.69, 0.69, 0.71)   // #B0B0B5 Notes toolbar buttons
let systemRed: (CGFloat, CGFloat, CGFloat) = (1.0, 0.27, 0.23)      // systemRed dark

// Menu bar (status) glyphs — sized to menu-bar proportions.
symbolPNG("apple.logo", fileName: "mb-apple.png", pointSize: 16, weight: .medium, hex: menuBarWhite)
symbolPNG("battery.100", fileName: "mb-battery.png", pointSize: 15, weight: .regular, hex: menuBarWhite)
symbolPNG("wifi", fileName: "mb-wifi.png", pointSize: 15, weight: .medium, hex: menuBarWhite)
symbolPNG("magnifyingglass", fileName: "mb-search.png", pointSize: 14, weight: .medium, hex: menuBarWhite)
symbolPNG("switch.2", fileName: "mb-controlcenter.png", pointSize: 14, weight: .medium, hex: menuBarWhite)
symbolPNG("mic.fill", fileName: "mb-mic-recording.png", pointSize: 15, weight: .medium, hex: systemRed)

// Notes toolbar glyphs.
symbolPNG("sidebar.left", fileName: "nt-sidebar.png", pointSize: 16, weight: .medium, hex: toolbarGray)
symbolPNG("list.bullet", fileName: "nt-list.png", pointSize: 14, weight: .medium, hex: toolbarGray)
symbolPNG("square.grid.2x2", fileName: "nt-grid.png", pointSize: 14, weight: .medium, hex: toolbarGray)
symbolPNG("trash", fileName: "nt-trash.png", pointSize: 15, weight: .medium, hex: toolbarGray)
symbolPNG("square.and.pencil", fileName: "nt-compose.png", pointSize: 16, weight: .medium, hex: toolbarGray)
symbolPNG("textformat", fileName: "nt-format.png", pointSize: 15, weight: .medium, hex: toolbarGray)
symbolPNG("checklist", fileName: "nt-checklist.png", pointSize: 15, weight: .medium, hex: toolbarGray)
symbolPNG("tablecells", fileName: "nt-table.png", pointSize: 15, weight: .medium, hex: toolbarGray)
symbolPNG("photo", fileName: "nt-media.png", pointSize: 15, weight: .medium, hex: toolbarGray)
symbolPNG("lock.open.fill", fileName: "nt-lock.png", pointSize: 14, weight: .medium, hex: toolbarGray)
symbolPNG("square.and.arrow.up", fileName: "nt-share.png", pointSize: 15, weight: .medium, hex: toolbarGray)
symbolPNG("link", fileName: "nt-link.png", pointSize: 14, weight: .medium, hex: toolbarGray)

// ---------- 3) Real cursor ----------
let arrow = NSCursor.arrow
print("cursor hotspot: \(arrow.hotSpot), size: \(arrow.image.size)")
writePNG(arrow.image, to: outDir.appendingPathComponent("cursor-arrow.png"),
         width: Int(arrow.image.size.width * 4), height: Int(arrow.image.size.height * 4))
// Persist the hotspot for the React component.
let meta = "{\"hotspotX\": \(arrow.hotSpot.x), \"hotspotY\": \(arrow.hotSpot.y), \"width\": \(arrow.image.size.width), \"height\": \(arrow.image.size.height)}"
try meta.write(to: outDir.appendingPathComponent("cursor-meta.json"), atomically: true, encoding: .utf8)
print("• cursor-meta.json — \(meta)")
```

- [ ] **Step 2: Run + convert the wallpaper**

```bash
cd docs/demo-video
swift scripts/extract-assets.swift
sips -s format jpeg -Z 3200 "/System/Library/Desktop Pictures/Sonoma.heic" --out public/system/wallpaper.jpg
ls -la public/system/
```

Expected: all `•` lines, no `⚠️ MISSING SYMBOL`, wallpaper.jpg present.

- [ ] **Step 3: Visual verification.** Read `public/system/app-notes.png`, `app-finder.png`, `mb-apple.png`, `wallpaper.jpg`, `cursor-arrow.png` with the Read tool. Confirm: real Notes icon (yellow gradient + lined paper, Apple's actual artwork), real multicolor Finder face, crisp Apple logo, a usable wallpaper (if Sonoma.heic's first frame looks wrong/washed out, try `"Mac Purple.heic"` or another from `ls "/System/Library/Desktop Pictures/"` — pick the best-looking; a purple-ish tone matches the previous grade).

---

### Task 2: Menu bar — real glyphs, correct metrics, "J" status item

**Files:**
- Modify: `docs/demo-video/src/Desktop.tsx` (full rewrite of `MenuBar`; delete `WaveformIcon` and `MicFillIcon`)
- Modify: `docs/demo-video/src/JVoiceDemo.tsx:57` (status-item position) and `:183-186` (wallpaper)

**Metrics (real macOS 14, 1×):** menu bar height 24-25px (use 25 in this comp), 13px SF Pro Text, app name bold (600), menu titles regular spaced ~19px apart, right-cluster status items spaced ~14px, Apple logo ~4px left padding beyond the 16px inset, clock format `Fri Jun 6 9:41 AM`.

- [ ] **Step 1: Rewrite `MenuBar` in Desktop.tsx:**

```tsx
import React from "react";
import { Img, staticFile } from "remotion";
import { SYSTEM_FONT } from "./tokens";

// macOS menu bar height (macOS 14 at 1x).
export const MENUBAR_H = 25;

const MenuGlyph: React.FC<{ src: string; h: number; style?: React.CSSProperties }> = ({
  src,
  h,
  style,
}) => (
  <Img
    src={staticFile(`system/${src}`)}
    style={{ height: h, width: "auto", display: "block", ...style }}
  />
);

export const MenuBar: React.FC<{
  recording?: boolean;
  highlightJVoice?: boolean;
}> = ({ recording = false, highlightJVoice = false }) => {
  return (
    <div
      style={{
        position: "absolute",
        top: 0,
        left: 0,
        right: 0,
        height: MENUBAR_H,
        background: "rgba(24,24,28,0.62)",
        backdropFilter: "blur(50px) saturate(1.6)",
        WebkitBackdropFilter: "blur(50px) saturate(1.6)",
        display: "flex",
        alignItems: "center",
        justifyContent: "space-between",
        paddingLeft: 16,
        paddingRight: 16,
        fontFamily: SYSTEM_FONT,
        color: "rgba(255,255,255,0.95)",
        fontSize: 13,
        zIndex: 50,
      }}
    >
      <div style={{ display: "flex", alignItems: "center", gap: 19 }}>
        <MenuGlyph src="mb-apple.png" h={16} style={{ marginTop: -1 }} />
        <span style={{ fontWeight: 600 }}>Notes</span>
        <span>File</span>
        <span>Edit</span>
        <span>Format</span>
        <span>View</span>
        <span>Window</span>
        <span>Help</span>
      </div>
      <div style={{ display: "flex", alignItems: "center", gap: 14 }}>
        {/* JVoice status item — the product's "J" mark (template-style white) */}
        <div
          style={{
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            minWidth: 24,
            height: MENUBAR_H - 4,
            padding: "0 4px",
            borderRadius: 4,
            background: highlightJVoice ? "rgba(255,255,255,0.22)" : "transparent",
          }}
        >
          {recording ? (
            <MenuGlyph src="mb-mic-recording.png" h={15} />
          ) : (
            <span style={{ fontWeight: 700, fontSize: 15, lineHeight: 1 }}>J</span>
          )}
        </div>
        <MenuGlyph src="mb-battery.png" h={12} />
        <MenuGlyph src="mb-wifi.png" h={12} />
        <MenuGlyph src="mb-search.png" h={13} />
        <MenuGlyph src="mb-controlcenter.png" h={13} />
        <span style={{ fontSize: 13 }}>Fri Jun 6  9:41 AM</span>
      </div>
    </div>
  );
};
```

- [ ] **Step 2: Wallpaper.** In `JVoiceDemo.tsx`, replace the gradient `wallpaper()` helper usage:

```tsx
      <AbsoluteFill>
        <Img
          src={staticFile("system/wallpaper.jpg")}
          style={{ width: "100%", height: "100%", objectFit: "cover" }}
        />
      </AbsoluteFill>
```

(placed where `style={{ background: wallpaper(), … }}` was; delete the `wallpaper()` function; keep the vignette overlay — it reads well on video). Add `Img, staticFile` to the remotion import.

- [ ] **Step 3: Status item position.** The J item now sits first in the right cluster. Recompute `jvoiceIcon` in `JVoiceDemo.tsx`: right cluster from the right edge: 16(pad) + clock(~118) + 14 + cc(13≈w13) + 14 + search(13) + 14 + wifi(~17) + 14 + battery(~27) + 14 + half of J-item(~12) → x ≈ W − 290. **Don't trust arithmetic — verify against a rendered still** (Task 6) by reading the pixel position of the J and adjusting until the hover highlight and dropdown align.

- [ ] **Step 4: Render a menu-bar still and inspect**

```bash
cd docs/demo-video && npx remotion still JVoiceDemo /tmp/jv-mb-check.png --frame=470
```

Read `/tmp/jv-mb-check.png`: real Apple logo, real wifi/battery/CC glyphs, J visible, plausible spacing. Iterate.

---

### Task 3: Dock — real app icons

**Files:**
- Modify: `docs/demo-video/src/Dock.tsx` (replace all hand-drawn icons)

**Metrics:** dock panel: translucent light gray blur, radius ~22, icons 58-64px with ~6px gap at default size, 1px divider (rgba(255,255,255,0.3)) before Trash with 8px margins. Real dock icon PNGs contain their own squircle + margins — no CSS borderRadius on them.

- [ ] **Step 1: Rewrite Dock.tsx:**

```tsx
import React from "react";
import { Img, staticFile } from "remotion";

// Dock geometry (comp coordinates). The Notes icon center is exported for cursor targeting.
export const DOCK = {
  bottom: 14,
  iconSize: 62,
  gap: 8,
  padding: 8,
  dividerW: 17, // 8px margin + 1px line + 8px margin
};

type DockEntry = { key: string; asset: string } | { key: "divider" };

const ENTRIES: DockEntry[] = [
  { key: "finder", asset: "app-finder.png" },
  { key: "safari", asset: "app-safari.png" },
  { key: "messages", asset: "app-messages.png" },
  { key: "notes", asset: "app-notes.png" },
  { key: "settings", asset: "app-settings.png" },
  { key: "divider" },
  { key: "trash", asset: "app-trash.png" },
];

export const NOTES_INDEX = ENTRIES.findIndex((e) => e.key === "notes");

const entryWidth = (e: DockEntry) => ("asset" in e ? DOCK.iconSize : DOCK.dividerW);

const totalWidth = () =>
  ENTRIES.reduce((acc, e) => acc + entryWidth(e), 0) +
  (ENTRIES.length - 1) * DOCK.gap +
  DOCK.padding * 2;

// Returns the center (x,y) of the dock entry at index, given comp dims.
export const dockIconCenter = (
  index: number,
  compW: number,
  compH: number,
): { x: number; y: number } => {
  const startX = (compW - totalWidth()) / 2 + DOCK.padding;
  let x = startX;
  for (let i = 0; i < index; i++) x += entryWidth(ENTRIES[i]) + DOCK.gap;
  x += entryWidth(ENTRIES[index]) / 2;
  const dockTop = compH - DOCK.bottom - (DOCK.iconSize + DOCK.padding * 2);
  const y = dockTop + DOCK.padding + DOCK.iconSize / 2;
  return { x, y };
};

export const Dock: React.FC<{ compW: number; compH: number; bounceNotes?: number }> = ({
  compW,
  compH,
  bounceNotes = 0,
}) => {
  return (
    <div
      style={{
        position: "absolute",
        bottom: DOCK.bottom,
        left: (compW - totalWidth()) / 2,
        width: totalWidth(),
        padding: DOCK.padding,
        borderRadius: 22,
        background: "rgba(160,160,170,0.26)",
        backdropFilter: "blur(40px) saturate(1.6)",
        WebkitBackdropFilter: "blur(40px) saturate(1.6)",
        border: "0.5px solid rgba(255,255,255,0.25)",
        boxShadow: "0 12px 40px rgba(0,0,0,0.35)",
        display: "flex",
        alignItems: "center",
        gap: DOCK.gap,
        zIndex: 40,
        boxSizing: "border-box",
      }}
    >
      {ENTRIES.map((e) =>
        "asset" in e ? (
          <Img
            key={e.key}
            src={staticFile(`system/${e.asset}`)}
            style={{
              width: DOCK.iconSize,
              height: DOCK.iconSize,
              transform: e.key === "notes" ? `translateY(${-bounceNotes}px)` : "none",
            }}
          />
        ) : (
          <div
            key="divider"
            style={{
              width: 1,
              height: DOCK.iconSize * 0.85,
              margin: "0 8px",
              background: "rgba(255,255,255,0.28)",
            }}
          />
        ),
      )}
    </div>
  );
};
```

Note: `dockIconCenter`'s signature is unchanged, and `NOTES_INDEX` still resolves — `JVoiceDemo.tsx` needs no changes for the dock.

- [ ] **Step 2: Still-check** (`--frame=30`, cursor approaching dock): real icons, even spacing, divider+trash present, Notes bounce still works (`--frame=68`).

---

### Task 4: Notes window — real dark-mode chrome (kill the yellow title bar)

**Files:**
- Modify: `docs/demo-video/src/NotesWindow.tsx` (full rewrite)

**Reference values (macOS 14 dark-mode Notes; verify against a reference image — try `screencapture` of the real Notes app first: `open -a Notes`, wait, `screencapture -x -l $(osascript -e 'tell app "Notes" to id of window 1') /tmp/notes-ref.png` — if Screen Recording permission blocks this, search the web for a "macOS Sonoma Notes dark mode" screenshot and eyeball-match):**
- Unified toolbar: **dark gray, NOT yellow** — `#2C2A28`-ish translucent; bottom hairline `rgba(0,0,0,0.35)`.
- Traffic lights: 12px ø, 8px gap, 20px inset; `#FF5F57`, `#FEBC2E`, `#28C840`, each with a faint dark inner ring.
- Two panes: note list ~0.28 width on `#1E1E1E`; editor on `#1E1E1E`; 1px separator `rgba(255,255,255,0.09)`.
- Note list: "Notes" window-title bold 15px white sits in the toolbar above the list; list shows a "Today" section header (11px, gray 0.45 uppercase? — real Notes uses 13px semibold white for date groups); selected row = rounded 8px rect `#3F3F43`; title 13px semibold white; snippet 11px `rgba(255,255,255,0.45)` with time prefix.
- Toolbar buttons (left→right over the list pane: view-toggle `nt-list.png`/`nt-grid.png` + `nt-trash.png`; over the editor pane: `nt-compose.png`, `nt-format.png`, `nt-checklist.png`, `nt-table.png`, `nt-media.png`, `nt-link.png`, `nt-lock.png`, `nt-share.png`, search `mb-search.png` at far right), ~17px tall, color baked into PNGs.
- Editor: centered date line 11px `rgba(255,255,255,0.35)`; body text white 0.92. Keep the demo's 22px body size (readability at video scale is the one sanctioned deviation).
- Caret: macOS Notes caret is the yellow accent — keep `#f0b429` 2px caret.

- [ ] **Step 1: Rewrite NotesWindow.tsx:**

```tsx
import React from "react";
import { Img, staticFile } from "remotion";
import { SYSTEM_FONT } from "./tokens";

const Tool: React.FC<{ src: string; h?: number; dim?: boolean }> = ({ src, h = 17, dim }) => (
  <Img
    src={staticFile(`system/${src}`)}
    style={{ height: h, width: "auto", display: "block", opacity: dim ? 0.55 : 0.9 }}
  />
);

// A macOS 14 dark-mode Notes window: unified dark toolbar (real Notes has no
// colored title bar), notes-list pane + editor pane, real SF Symbol toolbar.
export const NotesWindow: React.FC<{
  width: number;
  height: number;
  text: string;
  caretVisible: boolean;
  showCaret: boolean;
}> = ({ width, height, text, caretVisible, showCaret }) => {
  const listW = Math.round(width * 0.28);
  return (
    <div
      style={{
        width,
        height,
        borderRadius: 11,
        overflow: "hidden",
        background: "#1e1e1e",
        boxShadow:
          "0 30px 80px rgba(0,0,0,0.55), 0 0 0 0.5px rgba(255,255,255,0.14), inset 0 0.5px 0 rgba(255,255,255,0.10)",
        fontFamily: SYSTEM_FONT,
        display: "flex",
        flexDirection: "column",
      }}
    >
      {/* Unified toolbar — dark chrome, like the real app */}
      <div
        style={{
          height: 52,
          background: "rgba(44,42,40,0.98)",
          display: "flex",
          alignItems: "center",
          flexShrink: 0,
          borderBottom: "1px solid rgba(0,0,0,0.4)",
        }}
      >
        {/* traffic lights */}
        <div style={{ display: "flex", gap: 8, paddingLeft: 20, width: listW - 20, alignItems: "center", boxSizing: "border-box" }}>
          <div style={{ width: 12, height: 12, borderRadius: "50%", background: "#ff5f57", boxShadow: "inset 0 0 0 0.5px rgba(0,0,0,0.2)" }} />
          <div style={{ width: 12, height: 12, borderRadius: "50%", background: "#febc2e", boxShadow: "inset 0 0 0 0.5px rgba(0,0,0,0.2)" }} />
          <div style={{ width: 12, height: 12, borderRadius: "50%", background: "#28c840", boxShadow: "inset 0 0 0 0.5px rgba(0,0,0,0.2)" }} />
          <div style={{ marginLeft: 14, display: "flex", alignItems: "center", gap: 16 }}>
            <Tool src="nt-sidebar.png" h={16} dim />
          </div>
        </div>
        {/* over the list/editor boundary: window title + tools */}
        <div style={{ flex: 1, display: "flex", alignItems: "center", justifyContent: "space-between", paddingRight: 16 }}>
          <div style={{ display: "flex", alignItems: "center", gap: 16 }}>
            <span style={{ fontSize: 15, fontWeight: 700, color: "rgba(255,255,255,0.9)" }}>Notes</span>
            <div style={{ display: "flex", alignItems: "center", gap: 13, marginLeft: 4 }}>
              <Tool src="nt-list.png" h={14} />
              <Tool src="nt-grid.png" h={14} dim />
              <Tool src="nt-trash.png" h={15} dim />
            </div>
          </div>
          <div style={{ display: "flex", alignItems: "center", gap: 17 }}>
            <Tool src="nt-compose.png" h={16} />
            <Tool src="nt-format.png" h={15} dim />
            <Tool src="nt-checklist.png" h={15} dim />
            <Tool src="nt-table.png" h={15} dim />
            <Tool src="nt-media.png" h={15} dim />
            <Tool src="nt-link.png" h={14} dim />
            <Tool src="nt-lock.png" h={14} dim />
            <Tool src="nt-share.png" h={15} dim />
            <Tool src="mb-search.png" h={14} dim />
          </div>
        </div>
      </div>

      <div style={{ display: "flex", flex: 1, minHeight: 0 }}>
        {/* Notes list pane */}
        <div
          style={{
            width: listW,
            background: "#1e1e1e",
            borderRight: "1px solid rgba(255,255,255,0.09)",
            padding: "12px 8px",
            display: "flex",
            flexDirection: "column",
            gap: 2,
            boxSizing: "border-box",
          }}
        >
          <span style={{ fontSize: 13, fontWeight: 600, color: "rgba(255,255,255,0.92)", margin: "2px 8px 8px" }}>
            Today
          </span>
          {/* selected note row */}
          <div
            style={{
              background: "#3f3f43",
              borderRadius: 8,
              padding: "9px 11px",
              display: "flex",
              flexDirection: "column",
              gap: 3,
            }}
          >
            <span style={{ fontSize: 13, fontWeight: 600, color: "rgba(255,255,255,0.95)" }}>
              {text ? text.split(/[.!?]/)[0].slice(0, 26) : "New Note"}
            </span>
            <span style={{ fontSize: 11, color: "rgba(255,255,255,0.45)" }}>
              9:41 AM {text ? text.slice(0, 16) : "No additional text"}
            </span>
          </div>
          <span style={{ fontSize: 13, fontWeight: 600, color: "rgba(255,255,255,0.92)", margin: "14px 8px 8px" }}>
            Yesterday
          </span>
          {["Team practice", "Grocery list", "Ideas"].map((t) => (
            <div key={t} style={{ display: "flex", flexDirection: "column", gap: 2, padding: "6px 11px" }}>
              <span style={{ fontSize: 13, fontWeight: 600, color: "rgba(255,255,255,0.85)" }}>{t}</span>
              <span style={{ fontSize: 11, color: "rgba(255,255,255,0.40)" }}>Yesterday</span>
            </div>
          ))}
        </div>

        {/* Editor pane */}
        <div style={{ flex: 1, background: "#1e1e1e", padding: "20px 34px", position: "relative" }}>
          <div style={{ fontSize: 11, color: "rgba(255,255,255,0.35)", textAlign: "center", marginBottom: 22 }}>
            June 6, 2026 at 9:41 AM
          </div>
          <div
            style={{
              fontSize: 22,
              lineHeight: 1.5,
              color: "rgba(255,255,255,0.92)",
              fontWeight: 400,
              whiteSpace: "pre-wrap",
              minHeight: 30,
            }}
          >
            {text}
            {showCaret && (
              <span
                style={{
                  display: "inline-block",
                  width: 2,
                  height: 24,
                  background: "#f0b429",
                  marginLeft: 1,
                  verticalAlign: "text-bottom",
                  opacity: caretVisible ? 1 : 0,
                  transform: "translateY(4px)",
                }}
              />
            )}
          </div>
        </div>
      </div>
    </div>
  );
};
```

- [ ] **Step 2: Still-check** `--frame=200` (recording over Notes) and `--frame=410` (typed text): NO yellow chrome anywhere except caret, toolbar reads like real Notes, list pane plausible. Compare side-by-side against the reference screenshot if one was captured. Iterate on colors/spacing.

---

### Task 5: Real cursor

**Files:**
- Modify: `docs/demo-video/src/Cursor.tsx`

- [ ] **Step 1: Use the extracted pointer.** Read `public/system/cursor-meta.json` values (hotspot, size) printed by the extraction script and bake them in as constants:

```tsx
import React from "react";
import { Img, staticFile } from "remotion";

// The real macOS arrow pointer, extracted via NSCursor.arrow.
// Hotspot/size baked from public/system/cursor-meta.json.
const HOTSPOT_X = 4; // ← replace with cursor-meta.json value
const HOTSPOT_Y = 4; // ← replace with cursor-meta.json value
const CURSOR_W = 17; // ← replace with cursor-meta.json value
const CURSOR_H = 23; // ← replace with cursor-meta.json value

export const Cursor: React.FC<{ x: number; y: number; scale?: number }> = ({
  x,
  y,
  scale = 1,
}) => (
  <Img
    src={staticFile("system/cursor-arrow.png")}
    style={{
      position: "absolute",
      left: x - HOTSPOT_X,
      top: y - HOTSPOT_Y,
      width: CURSOR_W,
      height: CURSOR_H,
      transform: `scale(${scale})`,
      transformOrigin: `${HOTSPOT_X}px ${HOTSPOT_Y}px`,
      zIndex: 9999,
      pointerEvents: "none",
      filter: "drop-shadow(0px 1px 1.5px rgba(0,0,0,0.35))",
    }}
  />
);
```

- [ ] **Step 2: Still-check** any frame with the cursor over the wallpaper (`--frame=20`).

---

### Task 6: Position calibration + full review pass

- [ ] **Step 1: Render the scene-boundary stills** into `docs/demo-video/stills/` (overwriting the old ones — same filenames so docs links survive):

```bash
cd docs/demo-video
npx remotion still JVoiceDemo stills/s1-desktop.png --frame=20
npx remotion still JVoiceDemo stills/s2-notesopen.png --frame=90
npx remotion still JVoiceDemo stills/s3-notefocus.png --frame=120
npx remotion still JVoiceDemo stills/s4-recording.png --frame=200
npx remotion still JVoiceDemo stills/s5-caption.png --frame=250
npx remotion still JVoiceDemo stills/s6-transcribing.png --frame=300
npx remotion still JVoiceDemo stills/s7-typing.png --frame=390
npx remotion still JVoiceDemo stills/s8-done.png --frame=430
npx remotion still JVoiceDemo stills/s9-menu.png --frame=495
npx remotion still JVoiceDemo stills/s10-settings.png --frame=560
```

- [ ] **Step 2: Read EVERY still.** Checklist per still: real icons only (no leftover hand-drawn shapes), menu dropdown anchored under the J item (adjust `jvoiceIcon.x` / the `MenuDropdown` x-offset in `JVoiceDemo.tsx` until aligned), cursor clicks land on targets (dock Notes icon center still matches `dockIconCenter(NOTES_INDEX, …)` since geometry changed — re-derive), no clipping/overlap, wallpaper looks good under blur. Iterate components until all pass.

---

### Task 7: Final renders + distribution copies

- [ ] **Step 1: Render the video**

```bash
cd docs/demo-video && npx remotion render JVoiceDemo out/demo.mp4
cp out/demo.mp4 ../assets/demo.mp4
```

- [ ] **Step 2: GIF (two-pass palette, ≤8MB)**

```bash
cd docs/demo-video
ffmpeg -y -i out/demo.mp4 -vf "fps=20,scale=800:-1:flags=lanczos,palettegen" /tmp/jv-palette.png
ffmpeg -y -i out/demo.mp4 -i /tmp/jv-palette.png -filter_complex "fps=20,scale=800:-1:flags=lanczos[x];[x][1:v]paletteuse" out/demo.gif
ls -la out/demo.gif
```

If >8MB: retry with `fps=15,scale=720`. Then:

```bash
cp out/demo.gif ../assets/demo.gif
cp out/demo.gif ../../../Portfolio/assets/jvoice-demo.gif
```

- [ ] **Step 3: Watch-check.** Extract 6 spread frames from the final mp4 (`ffmpeg -i out/demo.mp4 -vf fps=1/4 /tmp/jv-final-%02d.png`) and Read them — confirms the encoded video matches the stills (catches font/asset loading failures during render).

---

### Task 8: DESIGN-TOKENS.md update

- [ ] **Step 1:** Append a "System environment assets (2026-06-06)" section documenting: all Apple UI artifacts now come from `public/system/` via `scripts/extract-assets.swift` (NSWorkspace icons, SF Symbols, NSCursor, system wallpaper); the JVoice status item is now a bold 15px "J" (mirrors `MenuBarController.makeStatusIcon()`); re-run the script on a new machine before rendering. Update any token that changed (MENUBAR_H 28→25).

---

### Self-review checklist
- [x] Yellow Notes title bar eliminated — Task 4
- [x] Real icons everywhere (dock, menu bar, toolbar, cursor) — Tasks 1-5
- [x] Mandatory visual iteration loops — Tasks 2,3,4,5,6,7
- [x] Outputs synced to docs/assets and Portfolio — Task 7
- [x] Tokens doc stays source of truth — Task 8
- [x] No commits (session constraint)
