import AppKit
import SwiftUI

public extension NSView {
    /// The stable id a tour step points at ("<surface>.<name>", e.g. "editor.inspector.colour").
    /// Stored as the view's accessibility identifier, so it survives layout changes and costs nothing
    /// when no tour runs.
    var tourAnchor: String? {
        get {
            let id = accessibilityIdentifier()
            return id.isEmpty ? nil : id
        }
        set { setAccessibilityIdentifier(newValue ?? "") }
    }
}

public extension NSWindow {
    /// The visible view carrying `anchor`, searching the whole window including title-bar accessories.
    /// Nil when it isn't there or is hidden — the tour then skips that step.
    func view(forTourAnchor anchor: String) -> NSView? {
        // The content view's superview is the window's frame view, which also holds the title bar.
        guard let root = contentView?.superview ?? contentView else { return nil }
        return Self.find(anchor, in: root)
    }

    private static func find(_ anchor: String, in view: NSView) -> NSView? {
        if view.isHidden { return nil }
        if view.tourAnchor == anchor { return view }
        for sub in view.subviews {
            if let found = find(anchor, in: sub) { return found }
        }
        return nil
    }
}

public extension View {
    /// SwiftUI windows (Settings, History): puts a transparent AppKit view carrying `id` behind this
    /// view, the same size, so `NSWindow.view(forTourAnchor:)` finds SwiftUI content too.
    func tourAnchor(_ id: String) -> some View {
        background(TourAnchorView(id: id))
    }
}

private struct TourAnchorView: NSViewRepresentable {
    let id: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.tourAnchor = id
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        view.tourAnchor = id
    }
}
