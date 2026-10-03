import AppKit
import SwiftUI

/// An `NSVisualEffectView` behind SwiftUI content. SwiftUI's own `.regularMaterial` inside a clear,
/// borderless window blends *within* the window and can come out as a flat tint; the AppKit view with
/// `.behindWindow` blending blurs the desktop for real.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var state: NSVisualEffectView.State = .active
    /// A stretchable shape mask. A behind-window effect view ignores SwiftUI clip shapes and layer
    /// corner radii, so a rounded material needs its `maskImage` (e.g. `capsuleMask(height:)`).
    var maskImage: NSImage? = nil

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = state
        view.maskImage = maskImage
        return view
    }

    /// A capsule mask for a view at least `height` tall: continuous ends, a stretchable middle.
    static func capsuleMask(height: CGFloat) -> NSImage {
        let cap = ceil(height / 2)
        let side = cap * 2 + 1
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(cgPath: Capsule(style: .continuous).path(in: rect).cgPath).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: cap, left: cap, bottom: cap, right: cap)
        image.resizingMode = .stretch
        return image
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.state = state
        view.maskImage = maskImage
    }
}

enum WindowMaterial {
    /// Makes `window`'s content a behind-window material (the desktop shows softly through), with
    /// `rootView` hosted on top and the title bar transparent so the material runs under it.
    /// `.sidebar` is the translucency the owner asked for; `.underWindowBackground` is one step less
    /// see-through if text ever gets muddy over a bright wallpaper.
    @discardableResult
    /// `belowTitleBar`: the SwiftUI content starts under the (transparent) title bar instead of behind
    /// it — for scrolling content, which would otherwise pass visibly under the title and traffic
    /// lights on macOS 14/15 (no automatic scroll-edge effect there). The material still runs under it.
    static func install<V: View>(_ rootView: V, in window: NSWindow,
                                 material: NSVisualEffectView.Material = .sidebar,
                                 belowTitleBar: Bool = false) -> NSHostingView<V> {
        let effect = NSVisualEffectView()
        effect.material = material
        effect.blendingMode = .behindWindow
        effect.state = .followsWindowActiveState
        let hosting = NSHostingView(rootView: rootView)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(hosting)
        window.titlebarAppearsTransparent = true
        window.contentView = effect
        let top: NSLayoutYAxisAnchor = belowTitleBar
            ? ((window.contentLayoutGuide as? NSLayoutGuide)?.topAnchor ?? effect.topAnchor)
            : effect.topAnchor
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: top),
            hosting.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        // Size the window to the SwiftUI root's own frame (plus the title bar it now sits below), as a
        // hosting content view would.
        var size = hosting.fittingSize
        if belowTitleBar { size.height += window.frame.height - window.contentLayoutRect.height }
        window.setContentSize(size)
        return hosting
    }
}
