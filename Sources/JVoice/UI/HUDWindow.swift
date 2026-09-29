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
        // The capsule's one soft shadow is the system window shadow, traced from the pill's own
        // alpha (re-traced after every size/state change — `retraceShadow`).
        hasShadow = true
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
    ///
    /// After the hide the content goes back to the empty idle view: the
    /// recording pill's bars are a `TimelineView` that keeps ticking at 30 Hz
    /// in an ordered-out window (~6% CPU, measured, until the first
    /// dictation). The panel and hosting controller stay realized, so the
    /// first show keeps its speed.
    func prewarm() {
        guard !isPrewarmed, !isVisible else { return }
        isPrewarmed = true
        prewarmHidePending = true
        currentState = .recording
        hostingController.rootView = HUDView(state: .recording, meter: nil, onStop: nil)
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
            self.hostingController.rootView = HUDView(state: .idle)
        }
    }

    func update(state: HUDState, theme: AppTheme = .system, meter: AudioLevelMeter? = nil) {
        // A real state change always wins over a still-pending prewarm hide.
        prewarmHidePending = false
        alphaValue = 1
        currentState = state
        // System / Light / Dark: the material, glass and semantic colours all follow the panel's
        // appearance (nil = macOS's). Assigned only on a change — it re-resolves the whole view tree.
        let wanted = theme.nsAppearance
        if appearance?.name != wanted?.name { appearance = wanted }
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
            retraceShadow()
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
        let y = visibleFrame.minY + HUDLayout.bottomGap - HUDLayout.shadowPadding
        setFrameOrigin(NSPoint(x: x, y: y))
    }

    /// The window server traces a borderless panel's shadow from what was last drawn, so after a new
    /// state is shown the shadow is re-traced on the next turn (once SwiftUI has drawn it) — never on
    /// the press → pill path itself (latency contract).
    private func retraceShadow() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isVisible else { return }
            self.invalidateShadow()
        }
    }
}

/// The Recording tour runs on this panel (reported by `VoiceCoordinator` as the `.recordingPill`
/// surface). The window is the capsule plus `HUDLayout.shadowPadding` of transparent margin on every
/// side, so the tour dims and keeps its tag clear of the capsule only — not a square band around it.
extension HUDWindow: TourHostShaping {
    var tourHostShape: TourHostShape? {
        TourHostShape(frame: frame.insetBy(dx: HUDLayout.shadowPadding, dy: HUDLayout.shadowPadding),
                      cornerRadius: HUDLayout.pillCorner)
    }
}
