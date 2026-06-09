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

// A real GUI app context is required for NSCursor.arrow to resolve to an actual
// image (otherwise its size is 0×0 and the bitmap rep fails). .accessory keeps
// it off the Dock/menu bar.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let scriptURL = URL(fileURLWithPath: #filePath)
let videoRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let outDir = videoRoot.appendingPathComponent("public/system")
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func makeRep(_ width: Int, _ height: Int) -> NSBitmapImageRep {
    return NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: width * 4, bitsPerPixel: 32
    )!
}

func writePNG(_ image: NSImage, to url: URL, width: Int, height: Int) {
    let rep = makeRep(width, height)
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
    let rep = makeRep(w, h)
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
// Transcribing state: cyan waveform (matches the HUD transcribing accent rgb(0,212,224)).
let transcribingCyan: (CGFloat, CGFloat, CGFloat) = (0.0, 0.831, 0.878)
symbolPNG("waveform", fileName: "mb-waveform-transcribing.png", pointSize: 15, weight: .medium, hex: transcribingCyan)

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
