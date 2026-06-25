#!/usr/bin/env swift
//
// Generates the JVoice app icon: a minimalist "J" monogram (dark stealth)
// on a macOS rounded-square, then assembles Resources/AppIcon.icns.
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
