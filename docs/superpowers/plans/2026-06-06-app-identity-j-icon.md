# App Identity: Black "J" Icon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give JVoice its own identity: a black-squircle "J" app icon (same visual family as MacOSUtils' "M" and BetterScreenshot's camera), a "J" glyph as the menu-bar status item (native template image), and a refreshed demo-video icon asset.

**Architecture:** A self-contained `scripts/generate-icon.swift` (adapted from `../MacOSUtils/scripts/generate-icon.swift`) renders the iconset → `Resources/AppIcon.icns` + a 1024px PNG for the Remotion demo. The menu bar icon is drawn at runtime as an `NSImage` template (bold "J" glyph) so it adapts natively to light/dark menu bars — replacing both the `waveform` SF Symbol and the forced `darkAqua` appearance hack.

**Tech Stack:** AppKit/CoreText scripting (no new dependencies), `iconutil`.

**Session constraint:** NO git commits/pushes this session (David's explicit instruction). Verification steps replace commit steps.

**Context for zero-context engineers:**
- The current `Resources/AppIcon.icns` is a verbatim copy of MacOSUtils' "M" icon — wrong app identity, must be replaced.
- `Sources/JVoice/UI/MenuBarController.swift:79-87` currently shows SF Symbol `waveform` (idle) / red `mic.fill` (recording) and forces `NSAppearance(named: .darkAqua)` on the button — the forced appearance defeats native template tinting and is the kind of hack that breaks on light menu bars.
- `swift build` must keep passing; `swift test` compiles but executes 0 tests locally (CLT-only machine — real runs in CI).
- The demo video reads `docs/demo-video/public/app-icon.png`; it currently contains the "M" icon too.

---

### Task 1: Icon generator script

**Files:**
- Create: `scripts/generate-icon.swift`

- [ ] **Step 1: Write the generator** (adapted from MacOSUtils' generator; changes: glyph "M"→"J", glyph scale 0.54→0.60 because "J" is a narrow glyph and needs a bigger point size for equal visual weight, plus a second output: a 1024px PNG for the demo video).

```swift
#!/usr/bin/env swift
//
// Generates the JVoice app icon: a minimalist "J" monogram (dark stealth)
// on a macOS rounded-square, then assembles Resources/AppIcon.icns and
// exports docs/demo-video/public/app-icon.png (1024px) for the Remotion demo.
//
// Design: near-black vertical gradient (#1C1C1E -> #0A0A0A) inside a rounded
// square, with a centered heavy "J" in soft light-gray and a faint glow —
// the same visual family as MacOSUtils ("M") and BetterScreenshot (camera).
//
// Usage:  swift scripts/generate-icon.swift
//
import AppKit
import CoreText
import Foundation

// Repo root = parent of this script's directory (scripts/..).
let scriptURL = URL(fileURLWithPath: #filePath)
let repoRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let resourcesDir = repoRoot.appendingPathComponent("Resources")
let icnsURL = resourcesDir.appendingPathComponent("AppIcon.icns")
let demoIconURL = repoRoot.appendingPathComponent("docs/demo-video/public/app-icon.png")

let iconsetURL = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("AppIcon-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

// iconset entries macOS expects.
let variants: [(name: String, px: Int)] = [
    ("icon_16x16",    16), ("icon_16x16@2x",    32),
    ("icon_32x32",    32), ("icon_32x32@2x",    64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

/// Centered "J" glyph as a path, sized/positioned within `rect`.
func monogramPath(in rect: NSRect, weightSide side: CGFloat) -> NSBezierPath {
    let font = NSFont.systemFont(ofSize: side * 0.60, weight: .black)
    let attr = NSAttributedString(string: "J", attributes: [.font: font])
    let line = CTLineCreateWithAttributedString(attr)
    let runs = CTLineGetGlyphRuns(line) as! [CTRun]

    let combined = CGMutablePath()
    for run in runs {
        let count = CTRunGetGlyphCount(run)
        var glyphs = [CGGlyph](repeating: 0, count: count)
        var positions = [CGPoint](repeating: .zero, count: count)
        CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
        CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
        for i in 0..<count {
            guard let gp = CTFontCreatePathForGlyph(font, glyphs[i], nil) else { continue }
            let t = CGAffineTransform(translationX: positions[i].x, y: positions[i].y)
            combined.addPath(gp, transform: t)
        }
    }

    let path = NSBezierPath(cgPath: combined)
    // Center by the glyph's true bounding box (no line-box padding skew).
    let b = path.bounds
    let dx = rect.midX - b.midX
    let dy = rect.midY - b.midY
    path.transform(using: AffineTransform(translationByX: dx, byY: dy))
    return path
}

func render(px: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: px, height: px)

    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    ctx.imageInterpolation = .high

    let S = CGFloat(px)
    // macOS icon grid: rounded square ~80.5% of canvas, centered.
    let shapeSide = (S * 0.805).rounded()
    let o = ((S - shapeSide) / 2).rounded()
    let rect = NSRect(x: o, y: o, width: shapeSide, height: shapeSide)
    let radius = shapeSide * 0.2237 // Apple continuous-corner ratio

    // --- Background squircle: subtle near-black vertical gradient ---
    let squircle = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    NSGraphicsContext.saveGraphicsState()
    squircle.addClip()
    let bottom = NSColor(srgbRed: 10/255, green: 10/255, blue: 10/255, alpha: 1)  // #0A0A0A
    let top    = NSColor(srgbRed: 28/255, green: 28/255, blue: 30/255, alpha: 1)  // #1C1C1E
    NSGradient(starting: bottom, ending: top)!.draw(in: rect, angle: 90)
    // faint top inner highlight — soft glass edge
    let inner = NSBezierPath(roundedRect: rect.insetBy(dx: shapeSide * 0.012, dy: shapeSide * 0.012),
                             xRadius: radius, yRadius: radius)
    inner.lineWidth = max(1, S * 0.004)
    NSColor(white: 1, alpha: 0.05).setStroke()
    inner.stroke()
    NSGraphicsContext.restoreGraphicsState()

    // --- "J" monogram: soft glow + light fill (reads as a lighter recess) ---
    let m = monogramPath(in: rect, weightSide: shapeSide)
    NSGraphicsContext.saveGraphicsState()
    let glow = NSShadow()
    glow.shadowColor = NSColor(white: 1, alpha: 0.30)
    glow.shadowBlurRadius = shapeSide * 0.035
    glow.shadowOffset = .zero
    glow.set()
    NSColor(srgbRed: 0.93, green: 0.93, blue: 0.95, alpha: 1).setFill() // #EDEDF2
    m.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

for v in variants {
    let rep = render(px: v.px)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write(Data("failed to encode \(v.name)\n".utf8)); continue
    }
    try data.write(to: iconsetURL.appendingPathComponent("\(v.name).png"))
    print("• \(v.name).png (\(v.px)px)")
}

// Demo-video icon asset (1024px).
let demoRep = render(px: 1024)
if let data = demoRep.representation(using: .png, properties: [:]) {
    try data.write(to: demoIconURL)
    print("• demo-video app-icon.png (1024px)")
}

// Assemble the .icns.
try FileManager.default.createDirectory(at: resourcesDir, withIntermediateDirectories: true)
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconsetURL.path, "-o", icnsURL.path]
try task.run()
task.waitUntilExit()
try? FileManager.default.removeItem(at: iconsetURL)

if task.terminationStatus == 0 {
    print("✅ wrote \(icnsURL.path)")
} else {
    FileHandle.standardError.write(Data("❌ iconutil exited \(task.terminationStatus)\n".utf8))
    exit(task.terminationStatus)
}
```

- [ ] **Step 2: Run it**

Run: `swift scripts/generate-icon.swift`
Expected: ten `• icon_*.png` lines + `• demo-video app-icon.png (1024px)` + `✅ wrote .../Resources/AppIcon.icns`

- [ ] **Step 3: Visual verification (mandatory)**

Run: `cd /tmp && rm -rf jv-icon.iconset && iconutil -c iconset <repo>/Resources/AppIcon.icns -o jv-icon.iconset`
Then **Read** `/tmp/jv-icon.iconset/icon_512x512.png` with the Read tool and confirm: black squircle, centered light-gray "J", balanced visual weight (compare against MacOSUtils' M icon). If the "J" looks too small/large or off-center (the J glyph's descender hook can skew optical centering), adjust the `0.60` scale factor and/or add a small optical y-offset (e.g. `dy + side * 0.01`) and re-run. Iterate until it looks right.

---

### Task 2: Menu bar "J" status icon (native template image)

**Files:**
- Modify: `Sources/JVoice/UI/MenuBarController.swift:79-88`
- Test: `Tests/JVoiceTests/MenuBarIconTests.swift` (create)

- [ ] **Step 1: Write the failing test** (NSImage drawing works headless on CI's macos runner; do NOT touch NSStatusBar in tests)

```swift
import XCTest
@testable import JVoice

@MainActor
final class MenuBarIconTests: XCTestCase {
    func testIdleIconIsTemplateImage() {
        let image = MenuBarController.makeStatusIcon()
        XCTAssertTrue(image.isTemplate, "Menu bar icon must be a template image so it adapts to light/dark menu bars")
        XCTAssertEqual(image.size, NSSize(width: 18, height: 18))
    }

    func testIdleIconHasNonEmptyContent() {
        let image = MenuBarController.makeStatusIcon()
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else {
            return XCTFail("Icon should produce a bitmap representation")
        }
        // At least some pixels must be opaque — guards against an empty draw.
        var opaqueCount = 0
        for x in 0..<rep.pixelsWide {
            for y in 0..<rep.pixelsHigh where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 {
                opaqueCount += 1
            }
        }
        XCTAssertGreaterThan(opaqueCount, 10, "The J glyph should cover at least a few pixels")
    }
}
```

- [ ] **Step 2: Verify it fails to compile** (no `makeStatusIcon` yet)

Run: `swift build --build-tests 2>&1 | tail -5`
Expected: error mentioning `makeStatusIcon`

- [ ] **Step 3: Implement** — replace `updateStatusButton` in `MenuBarController.swift`:

```swift
    private func updateStatusButton(_ button: NSStatusBarButton?) {
        guard let button else { return }

        if recordingState {
            let image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "JVoice — recording")
            button.image = image
            button.contentTintColor = .systemRed
        } else {
            button.image = Self.statusIcon
            button.contentTintColor = nil
        }
    }

    /// The product mark: a bold "J", rendered as a template image so the
    /// system tints it like a native status item (black on light menu bars,
    /// white on dark ones).
    private static let statusIcon: NSImage = makeStatusIcon()

    static func makeStatusIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let font = NSFont.systemFont(ofSize: 15, weight: .bold)
            let string = NSAttributedString(string: "J", attributes: [
                .font: font,
                .foregroundColor: NSColor.black,
            ])
            let glyphSize = string.size()
            string.draw(at: NSPoint(
                x: (rect.width - glyphSize.width) / 2,
                y: (rect.height - glyphSize.height) / 2
            ))
            return true
        }
        image.isTemplate = true
        return image
    }
```

Also DELETE the old body's `button.appearance = NSAppearance(named: .darkAqua)` line and the `symbolName` ternary — the full old implementation (lines 79-87) is replaced by the above.

- [ ] **Step 4: Build + test-compile**

Run: `swift build && swift build --build-tests`
Expected: `Build complete!` twice (tests execute in CI only)

---

### Task 3: Sync the demo video's status-item glyph (consumed by the demo-video plan)

The Remotion demo (`docs/demo-video/src/Desktop.tsx`) shows the waveform icon as JVoice's idle status item. After this plan, the product truth is a "J". The change is owned by `2026-06-06-demo-video-native-ui.md` Task 3 — no action here beyond having regenerated `docs/demo-video/public/app-icon.png` in Task 1.

Also update `docs/demo-video/DESIGN-TOKENS.md`: document the new status item ("bold 15pt SF Pro 'J', template image; recording = red mic.fill") so the tokens file stays the source of truth.

---

### Self-review checklist
- [x] Generator writes BOTH icns and demo png — covered Task 1
- [x] Menu bar template image + no forced appearance — covered Task 2
- [x] Test compiles without NSStatusBar — uses factory only
- [x] No commits (session constraint)
