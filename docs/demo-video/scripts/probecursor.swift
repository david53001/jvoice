import AppKit
import Foundation
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let arrow = NSCursor.arrow
print("after app: hotspot \(arrow.hotSpot) size \(arrow.image.size) reps \(arrow.image.representations.count)")
// also try currentSystem
if let cs = NSCursor.current as NSCursor? {
    print("current size \(cs.image.size)")
}
