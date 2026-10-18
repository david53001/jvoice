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
        // The capsule draws its own soft shadow (HUDView's `PillShadow`), inside `shadowPadding`.
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
    /// Shrinks the panel to the new capsule once a morph has finished (`update`).
    private var settleWork: DispatchWorkItem?

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
        // A pill appearing (not morphing from one on screen — the invisible prewarm doesn't count) goes
        // to the display the user is on now.
        if !isVisible || prewarmHidePending { pillScreen = nil }
        // A real state change always wins over a still-pending prewarm hide.
        prewarmHidePending = false
        alphaValue = 1
        // One visible pill replacing another morphs (the capsule resizes, contents cross-fade); the
        // first show and the hide stay instant.
        let morphs = isVisible && currentState.isVisible && state.isVisible
        currentState = state
        settleWork?.cancel()
        settleWork = nil
        // System / Light / Dark: the material, glass and semantic colours all follow the panel's
        // appearance (nil = macOS's). Assigned only on a change — it re-resolves the whole view tree.
        let wanted = theme.nsAppearance
        if appearance?.name != wanted?.name { appearance = wanted }
        hostingController.rootView = HUDView(
            state: state,
            theme: theme.theme,
            meter: meter,
            onStop: onStop,
            animated: morphs
        )
        ignoresMouseEvents = (state != .recording)

        if state.isVisible {
            if morphs {
                // Room for both capsules while the old one animates into the new (content is
                // bottom-anchored and centred, so neither moves); shrink to the new one afterwards.
                sizeToFit(atLeast: frame.size)
                let work = DispatchWorkItem { [weak self] in
                    guard let self, self.isVisible else { return }
                    self.settleWork = nil
                    self.sizeToFit()
                    self.positionAtBottomCenter()
                }
                settleWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + HUDLayout.morphSettleDelay, execute: work)
            } else {
                sizeToFit()
            }
            positionAtBottomCenter()
            orderFrontRegardless()
        } else {
            orderOut(nil)
        }
    }

    /// Sizes the panel to the capsule now showing (never below `atLeast`, used during a morph).
    private func sizeToFit(atLeast floor: NSSize = .zero) {
        let fittingSize = hostingController.view.fittingSize
        let minimumSize = HUDLayout.minimumSize
        let width = max(minimumSize.width, fittingSize.width, floor.width)
        let height = max(minimumSize.height, fittingSize.height, floor.height)
        setFrame(NSRect(origin: frame.origin, size: NSSize(width: width, height: height)), display: false)
    }

    /// The display the pill is on: picked when it appears (the one under the mouse — where the user is
    /// working), then kept while it stays up, so a recording → transcribing → Pasted morph never jumps
    /// to another monitor if the pointer moves.
    private weak var pillScreen: NSScreen?

    private func positionAtBottomCenter() {
        if pillScreen == nil || !NSScreen.screens.contains(where: { $0 === pillScreen }) {
            pillScreen = NSScreen.underMouse
        }
        guard let screen = pillScreen else { return }
        let visibleFrame = screen.visibleFrame
        let x = visibleFrame.midX - frame.width / 2
        let y = visibleFrame.minY + HUDLayout.bottomGap - HUDLayout.shadowPadding
        setFrameOrigin(NSPoint(x: x, y: y))
    }
}

/// The Recording tour runs on this panel (reported by `VoiceCoordinator` as the `.recordingPill`
/// surface). The window is the capsule plus `HUDLayout.shadowPadding` of transparent margin (and,
/// during a morph, room for the bigger of two capsules), so the tour dims and keeps its tag clear of the
/// capsule only — bottom-anchored and centred, like the content — not a square band around it.
extension HUDWindow: TourHostShaping {
    var tourHostShape: TourHostShape? {
        let pad = HUDLayout.shadowPadding
        let fit = hostingController.view.fittingSize
        let width = min(frame.width, max(fit.width, HUDLayout.minimumSize.width)) - 2 * pad
        let height = min(frame.height, max(fit.height, HUDLayout.minimumSize.height)) - 2 * pad
        let capsule = CGRect(x: frame.midX - width / 2, y: frame.minY + pad, width: width, height: height)
        return TourHostShape(frame: capsule, cornerRadius: min(HUDLayout.pillCorner, height / 2))
    }
}
