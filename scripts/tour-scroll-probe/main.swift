import AppKit
import SwiftUI

// Headless check (run via scripts/verify-tour-scroll.sh): does the tour tag's outline box follow a
// SwiftUI ScrollView in the SAME run-loop turn as the scroll? Before 2026-09-28 it only moved on a 0.1 s
// timer and lagged up to ~220 pt behind the content while scrolling Settings (David: "the box shifts up…
// it lags back"). Windows sit just above the desktop level, fully transparent, and are ordered back —
// nothing appears over the user's screen.
struct Rows: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ForEach(0..<30) { i in
                    Group {
                        if i == 8 { Text("row \(i)").frame(width: 200, height: 40).tourAnchor("probe.card") }
                        else { Text("row \(i)").frame(width: 200, height: 40) }
                    }
                }
            }
        }.frame(width: 300, height: 300)
    }
}

@MainActor func probeVisibleRect(_ a: NSView) -> CGRect {
    var r = a.convert(a.bounds, to: nil); var v = a.superview
    while let x = v { if let c = x as? NSClipView { r = r.intersection(c.convert(c.bounds, to: nil)) }; v = x.superview }
    return r
}
@MainActor func runProbe() {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    TagOverlayController.probeLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
    let host = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 300, height: 300), styleMask: [.titled],
                        backing: .buffered, defer: false)
    host.contentView = NSHostingView(rootView: Rows())
    host.level = TagOverlayController.probeLevel!
    host.alphaValue = 0
    host.orderBack(nil)
    host.contentView?.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.4))
    guard let anchor = host.view(forTourAnchor: "probe.card"), let scroll = anchor.enclosingScrollView else {
        print("FAIL: anchor/scroll view not found"); exit(1)
    }
    let overlay = TagOverlayController()
    overlay.decor.alphaValue = 0; overlay.tagPanel.alphaValue = 0
    let step = TourStep(anchor: "probe.card", kind: .explain, title: "Probe", body: "Probe body.")
    overlay.show(step: step, body: step.body, number: 1, total: 1, anchor: anchor, host: host)

    var failures = 0
    func check(_ label: String) {
        // NO run-loop spin between the scroll and this check: the timer can't have fired.
        let visible = probeVisibleRect(anchor)
        if visible.isNull || visible.width <= 0 || visible.height <= 0 {
            let ok = !overlay.decor.isVisible && !overlay.tagPanel.isVisible
            print(ok ? "  ✓ \(label): scrolled out → overlay hidden" : "  ✗ \(label): scrolled out but overlay still shown")
            if !ok { failures += 1 }
            return
        }
        let want = host.convertToScreen(visible)
        let got = overlay.decorView.box.offsetBy(dx: overlay.decor.frame.minX, dy: overlay.decor.frame.minY)
        // The box is the anchor grown by TagStyle.boxPadding on each side.
        let expected = want.insetBy(dx: -TagStyle.boxPadding, dy: -TagStyle.boxPadding)
        let err = max(abs(got.midX - expected.midX), abs(got.midY - expected.midY),
                      abs(got.height - expected.height))
        let viewport = host.convertToScreen(scroll.contentView.convert(scroll.contentView.bounds, to: nil))
        let insideViewport = got.insetBy(dx: TagStyle.boxPadding + 0.5, dy: TagStyle.boxPadding + 0.5)
            .intersection(viewport).height >= min(want.height, viewport.height) - 1
        let ok = err < 1.0 && overlay.decor.isVisible && insideViewport
        print("  \(ok ? "✓" : "✗") \(label): box off by \(String(format: "%.1f", err)) pt\(insideViewport ? "" : " (outside viewport)")")
        if !ok { failures += 1 }
    }

    let clip = scroll.contentView
    func scrollTo(_ y: CGFloat) {
        clip.scroll(to: NSPoint(x: 0, y: y))
        scroll.reflectScrolledClipView(clip)
    }
    print("Tour box follows scrolling in the same turn")
    anchor.scrollToVisible(anchor.bounds)
    RunLoop.main.run(until: Date().addingTimeInterval(0.3))
    check("after scrollToVisible")
    let y0 = clip.bounds.minY
    for (i, dy) in [12, 24, 36, 60, 90, -40, -80, 5].enumerated() {
        scrollTo(clip.bounds.minY + CGFloat(dy))
        check("scroll step \(i + 1) (\(dy > 0 ? "+" : "")\(dy) pt)")
    }
    scrollTo(y0 + 150)       // anchor half out of the top of the viewport
    check("anchor partly scrolled out → box cut to viewport")
    scrollTo(y0 + 900)       // fully out
    check("anchor fully out")
    scrollTo(y0)             // back
    check("scrolled back")
    overlay.hide()
    print(failures == 0 ? "PASS" : "FAIL: \(failures)")
    exit(failures == 0 ? 0 : 1)
}
MainActor.assumeIsolated { runProbe() }
