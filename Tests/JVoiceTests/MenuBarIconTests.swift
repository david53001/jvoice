#if canImport(Testing)
import AppKit
import Testing
@testable import JVoice

@Test @MainActor
func statusIconIsTemplateImage() {
    let image = MenuBarController.makeStatusIcon()
    // Template images adapt natively to light/dark menu bars — the forced
    // darkAqua appearance hack must never come back.
    #expect(image.isTemplate)
    #expect(image.size == NSSize(width: 18, height: 18))
}

@Test @MainActor
func statusIconHasNonEmptyContent() {
    let image = MenuBarController.makeStatusIcon()
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff) else {
        Issue.record("Icon should produce a bitmap representation")
        return
    }
    // At least some pixels must be opaque — guards against an empty draw.
    var opaqueCount = 0
    for x in 0..<rep.pixelsWide {
        for y in 0..<rep.pixelsHigh where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 {
            opaqueCount += 1
        }
    }
    #expect(opaqueCount > 10, "The J glyph should cover at least a few pixels")
}

@Test @MainActor
func statusButtonReflectsActivityState() {
    let controller = MenuBarController(coordinator: VoiceCoordinator())
    controller.installStatusItem()
    guard let button = controller.statusItem?.button else {
        Issue.record("Installing the status item should produce a button")
        return
    }

    // Recording → red mic, with the color BAKED into a non-template image
    // (not applied via `contentTintColor`). A tinted template status-bar image
    // is muted by menu-bar vibrancy and can render near-black on a dark menu
    // bar; the color must live in the image's pixels to stay visible.
    controller.updateActivity(.recording)
    #expect(button.contentTintColor == nil)
    guard let recImage = button.image else {
        Issue.record("Recording should set a button image")
        return
    }
    #expect(recImage.isTemplate == false)
    let red = averageOpaqueColor(recImage)
    #expect(red.redComponent > 0.6, "Recording icon should be predominantly red")
    #expect(red.greenComponent < 0.5)
    #expect(red.blueComponent < 0.5)

    // Transcribing → cyan waveform (matches the HUD's transcribing accent),
    // likewise baked into a non-template image.
    controller.updateActivity(.transcribing)
    #expect(button.contentTintColor == nil)
    guard let transImage = button.image else {
        Issue.record("Transcribing should set a button image")
        return
    }
    #expect(transImage.isTemplate == false)
    let cyan = averageOpaqueColor(transImage)
    #expect(cyan.redComponent < 0.4, "Transcribing icon should be predominantly cyan")
    #expect(cyan.greenComponent > 0.5)
    #expect(cyan.blueComponent > 0.5)

    // Idle → template "J" (adapts natively to light/dark menu bars), no tint.
    controller.updateActivity(.idle)
    #expect(button.image?.isTemplate == true)
    #expect(button.contentTintColor == nil)
}

/// Average sRGB color of an image's solidly-opaque pixels (antialiased edges,
/// with partial alpha, are excluded so the result is the flat fill color).
@MainActor
private func averageOpaqueColor(_ image: NSImage) -> NSColor {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff) else {
        Issue.record("Image should produce a bitmap representation")
        return .clear
    }
    var r = 0.0, g = 0.0, b = 0.0, count = 0.0
    for x in 0..<rep.pixelsWide {
        for y in 0..<rep.pixelsHigh {
            guard let pixel = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                  pixel.alphaComponent > 0.9 else { continue }
            r += pixel.redComponent
            g += pixel.greenComponent
            b += pixel.blueComponent
            count += 1
        }
    }
    guard count > 0 else { return .clear }
    return NSColor(srgbRed: r / count, green: g / count, blue: b / count, alpha: 1.0)
}
#endif
