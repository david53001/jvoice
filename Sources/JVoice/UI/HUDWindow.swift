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
        self.hostingController = NSHostingController(rootView: HUDView(state: .idle, theme: .dark))
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

    private var isPrewarmed = false
    private var prewarmHidePending = false

    /// Realize the panel ONCE while the app is idle so the first hotkey press
    /// doesn't pay window-server surface creation + the SwiftUI hosting view's
    /// first layout on the critical press → pill path. The recording pill is
    /// ordered front fully transparent (never visible), given a moment to render,
    /// then ordered out again. A press that lands before that happens simply
    /// takes the realized window over (`update` cancels the pending hide).
    func prewarm() {
        guard !isPrewarmed, !isVisible else { return }
        isPrewarmed = true
        prewarmHidePending = true
        currentState = .recording
        hostingController.rootView = HUDView(state: .recording, theme: .dark, meter: nil, onStop: nil)
        alphaValue = 0
        sizeToFit()
        positionAtBottomCenter()
        orderFrontRegardless()
        displayIfNeeded()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, self.prewarmHidePending else { return }
            self.prewarmHidePending = false
            self.orderOut(nil)
            self.alphaValue = 1
            self.currentState = .idle
        }
    }

    func update(state: HUDState, theme: AppTheme = .dark, meter: AudioLevelMeter? = nil) {
        // A real state change always wins over a still-pending prewarm hide.
        prewarmHidePending = false
        alphaValue = 1
        currentState = state
        hostingController.rootView = HUDView(
            state: state,
            theme: theme.theme,
            meter: meter,
            onStop: onStop
        )
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
