import AppKit
import SwiftUI

@MainActor
final class HUDWindow: NSPanel {
    private let hostingController: NSHostingController<HUDView>
    private var currentState: HUDState = .idle
    var onStop: (() -> Void)?

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override init(contentRect: NSRect,
                  styleMask style: NSWindow.StyleMask,
                  backing bufferingType: NSWindow.BackingStoreType,
                  defer flag: Bool) {
        self.hostingController = NSHostingController(rootView: HUDView(state: .idle))
        super.init(contentRect: contentRect, styleMask: style, backing: bufferingType, defer: flag)
    }

    convenience init() {
        self.init(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 50),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // HUD must stay above the panel (which sits at statusWindow + 1)
        // so the recording pill never disappears behind the panel.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 2)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = true
        animationBehavior = .utilityWindow
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        contentViewController = hostingController
    }

    func update(state: HUDState) {
        currentState = state
        hostingController.rootView = HUDView(state: state, onStop: onStop)
        ignoresMouseEvents = (state != .recording)

        if state.isVisible {
            sizeToFit()
            positionAtBottomCenter()
            orderFrontRegardless()
        } else {
            orderOut(nil)
        }
    }

    private func sizeToFit() {
        let fittingSize = hostingController.view.fittingSize
        let minimumSize = HUDLayout.minimumSize(for: currentState)
        let width = max(minimumSize.width, fittingSize.width)
        let height = max(minimumSize.height, fittingSize.height)
        setFrame(NSRect(origin: frame.origin, size: NSSize(width: width, height: height)), display: false)
    }

    private func positionAtBottomCenter() {
        guard let screen = NSScreen.main else { return }
        let visibleFrame = screen.visibleFrame
        let x = visibleFrame.midX - frame.width / 2
        let y = visibleFrame.minY + 24
        setFrameOrigin(NSPoint(x: x, y: y))
    }
}
