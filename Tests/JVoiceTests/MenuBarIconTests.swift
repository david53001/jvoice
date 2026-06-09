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
#endif
