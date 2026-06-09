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

    // Recording → red mic.
    controller.updateActivity(.recording)
    #expect(button.image != nil)
    #expect(button.contentTintColor == .systemRed)

    // Transcribing → cyan waveform (matches the HUD's transcribing accent).
    controller.updateActivity(.transcribing)
    #expect(button.image != nil)
    #expect(button.contentTintColor == NSColor(srgbRed: 0.0, green: 0.831, blue: 0.878, alpha: 1.0))

    // Idle → template "J", no tint.
    controller.updateActivity(.idle)
    #expect(button.image != nil)
    #expect(button.contentTintColor == nil)
}
#endif
