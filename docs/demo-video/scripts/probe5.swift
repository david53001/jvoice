import AppKit
import Foundation
func makeRepOpt(_ width: Int, _ height: Int) -> NSBitmapImageRep? {
    return NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: width * 4, bitsPerPixel: 32)
}
let icon = NSWorkspace.shared.icon(forFile: "/System/Library/CoreServices/Finder.app")
print("icon \(icon.size)")
let r = makeRepOpt(256,256)
print("rep nil? \(r == nil)")
