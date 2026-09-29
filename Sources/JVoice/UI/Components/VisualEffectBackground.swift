import AppKit
import SwiftUI

/// An `NSVisualEffectView` behind SwiftUI content. SwiftUI's own `.regularMaterial` inside a clear,
/// borderless window blends *within* the window and can come out as a flat tint; the AppKit view with
/// `.behindWindow` blending blurs the desktop for real.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var state: NSVisualEffectView.State = .active

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = state
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.state = state
    }
}

enum WindowMaterial {
    /// Makes `window`'s content a behind-window material (the desktop shows softly through), with
    /// `rootView` hosted on top and the title bar transparent so the material runs under it.
    /// `.sidebar` is the translucency the owner asked for; `.underWindowBackground` is one step less
    /// see-through if text ever gets muddy over a bright wallpaper.
    @discardableResult
    static func install<V: View>(_ rootView: V, in window: NSWindow,
                                 material: NSVisualEffectView.Material = .sidebar) -> NSHostingView<V> {
        let effect = NSVisualEffectView()
        effect.material = material
        effect.blendingMode = .behindWindow
        effect.state = .followsWindowActiveState
        let hosting = NSHostingView(rootView: rootView)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: effect.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        window.titlebarAppearsTransparent = true
        window.contentView = effect
        // Size the window to the SwiftUI root's own frame, as a hosting content view would.
        window.setContentSize(hosting.fittingSize)
        return hosting
    }
}
