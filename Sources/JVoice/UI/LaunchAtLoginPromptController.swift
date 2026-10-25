import AppKit
import ServiceManagement

/// "Open JVoice at login?" — asked after the 5th completed dictation (rules, the calm-moment test and
/// every flow decision: `LaunchAtLoginPrompt`, logic-tested; same behaviour as MacStats and
/// BetterScreenshot; docs/sparkle-updates/README.md). Replaces ≤ 1.1.4's silent first-launch enable.
/// This class only reads the system state and carries the decisions out.
///
/// After a dictation makes it due (`afterUse`), it checks once a second (`waitStep`, for up to
/// `giveUpSeconds`) for a calm moment — the dictation settled for 3 s, no key pressed for 2 s, no
/// mouse button down, no recording / transcription / HUD pill, none of our
/// windows in front, no tour tag, nothing full-screen in front — then shows a card in the top-right
/// screen corner (the HUD lives at the bottom centre). The card never takes focus. Unanswered, it goes
/// away after `unansweredHideSeconds` (not while the pointer is on it); if the user could have seen it
/// (`LaunchAtLoginPrompt.Showing`) that counts as one of `maxShowings`, and it comes back after a later
/// dictation a day later or after a relaunch; if not, after a dictation at least 10 minutes later.
/// Answers: **No Thanks**, or **Open at Login** → `SMAppService.mainApp.register()`, then "will open at
/// login" (closes after 1.6 s), "One more step" + **Open Login Items** (`.requiresApproval`) or
/// "Couldn't turn it on." (error); those two also go away after `unansweredHideSeconds`. The menus'
/// Launch at Login item re-reads the status on every change (`LaunchAtLoginManager.didChangeNotification`).
@MainActor
final class LaunchAtLoginPromptController {
    private let rules = LaunchAtLoginPrompt()
    /// Made on the first `show`, so users who are never asked never get the window.
    private var card: LaunchAtLoginCard?
    private var waitTimer: Timer?
    private var lastUseAt = Date.distantPast
    private var closeTask: Task<Void, Never>?
    /// The question is up (not a result line): how much of it the user could have seen.
    private var showing: LaunchAtLoginPrompt.Showing?
    /// A result card that waits for a click ("One more step", "Couldn't turn it on.") is up since then.
    private var resultShownAt: Date?
    private var lastHideTick = Date()
    private var hideTimer: Timer?
    /// A counted showing ended in this launch (for `LaunchAtLoginPrompt.reshowAfterSeconds`).
    private var shownThisLaunch = false
    /// When the last showing that didn't count ended (`LaunchAtLoginPrompt.reshowAfterUnseenSeconds`).
    private var unseenShowingEndedAt: Date?
    private var choiceObserver: NSObjectProtocol?

    /// Recording, transcribing, pasting or a HUD pill on screen (set by the app delegate).
    var isDictationActive: () -> Bool = { false }
    /// A JVoice menu is open. Unused since 1.4.0 (left at `false`; the pure rule keeps its input): the
    /// old menu-bar menu is gone, JVoice's main menu only opens while JVoice is active — which already
    /// holds the card back — and the Dock draws the Dock menu in its own process, out of JVoice's sight.
    var isMenuOpen: () -> Bool = { false }
    /// JVoice's System / Light / Dark choice for the card's window.
    var appearance: () -> NSAppearance? = { nil }

    init() {
        // A choice made with the menu item while the card is up answers it (`setEnabled` marks it asked).
        choiceObserver = NotificationCenter.default.addObserver(
            forName: LaunchAtLoginManager.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.showing != nil, self.rules.asked else { return }
                self.close()
            }
        }
    }

    /// A dictation's text reached the user (pasted, or copied in clipboard-only mode). Cancelled,
    /// empty, failed and refused dictations never get here.
    func dictationCompleted() {
        lastUseAt = Date()
        let step = rules.afterUse(cardVisible: card?.isVisible ?? false, shownThisLaunch: shownThisLaunch,
                                  unseenShowingEndedAt: unseenShowingEndedAt,
                                  isEnabled: { LaunchAtLoginManager.isEnabled })
        if step == .startWaiting { startWaiting() }   // the rest needs nothing here (`afterUse` marks asked)
    }

    private func startWaiting() {
        guard waitTimer == nil else { return }   // already waiting; lastUseAt moved on
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        waitTimer = timer
    }

    private func stopWaiting() {
        waitTimer?.invalidate()
        waitTimer = nil
    }

    private func tick() {
        let moment = LaunchAtLoginPrompt.Moment(
            secondsSinceUse: Date().timeIntervalSince(lastUseAt),
            secondsSinceKeyPress: CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown),
            mouseButtonDown: NSEvent.pressedMouseButtons != 0,
            dictationActive: isDictationActive(),
            appIsActive: NSApp.isActive,
            menuIsOpen: isMenuOpen(),
            tourShowing: !TagOverlayController.allWindowNumbers.isEmpty,
            fullScreenInFront: Self.frontmostAppCoversAScreen())
        switch rules.waitStep(moment, isEnabled: { LaunchAtLoginManager.isEnabled }) {
        case .keepWaiting: break
        case .giveUp, .noLongerDue, .alreadyEnabled: stopWaiting()   // `waitStep` marks asked if enabled
        case .show: stopWaiting(); ask()
        }
    }

    /// `LaunchAtLoginPrompt.fullScreenInFront` on the windows on screen now.
    private static func frontmostAppCoversAScreen() -> Bool {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                              kCGNullWindowID) as? [[String: Any]] ?? []
        let windows = list.compactMap { info -> LaunchAtLoginPrompt.WindowInfo? in
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo as CFDictionary) else { return nil }
            return .init(ownerPID: pid, layer: layer, bounds: bounds)
        }
        return LaunchAtLoginPrompt.fullScreenInFront(
            frontmostPID: NSWorkspace.shared.frontmostApplication?.processIdentifier,
            windows: windows, screenFrames: NSScreen.screens.map(\.frame))
    }

    private func ask() {
        show(title: "Open JVoice at login?",
             message: "Your dictation shortcut keeps working after a restart. You can change this any time in Settings or the JVoice menu.",
             actions: [
                .init("No Thanks") { [weak self] in
                    self?.rules.markAsked()
                    self?.close()
                },
                .init("Open at Login", primary: true) { [weak self] in self?.openAtLogin() },
             ])
        showing = LaunchAtLoginPrompt.Showing()
        startHideTimer()
    }

    private func startHideTimer() {
        hideTimer?.invalidate()
        lastHideTick = Date()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.hideTick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        hideTimer = timer
    }

    private func stopHideTimer() {
        hideTimer?.invalidate()
        hideTimer = nil
    }

    /// Hides a card nobody answers after `unansweredHideSeconds`, like a banner, so it never stays over
    /// a presentation or a shared screen. Only the question counts as a showing, and only if the user
    /// could have seen it (`cardHidUnanswered`).
    private func hideTick() {
        guard let card, showing != nil || resultShownAt != nil else { stopHideTimer(); return }
        let now = Date()
        let pointerOnCard = card.window.frame.contains(NSEvent.mouseLocation)
        if var current = showing {
            current.tick(seconds: now.timeIntervalSince(lastHideTick),
                         cardVisible: card.window.occlusionState.contains(.visible) && card.window.isOnActiveSpace,
                         secondsSinceInput: CGEventSource.secondsSinceLastEventType(
                            .combinedSessionState, eventType: Self.anyInputEvent))
            showing = current
            lastHideTick = now
            guard LaunchAtLoginPrompt.shouldHideUnanswered(secondsShown: current.secondsShown,
                                                           pointerOnCard: pointerOnCard) else { return }
            if rules.cardHidUnanswered(current, now: now) { shownThisLaunch = true } else { unseenShowingEndedAt = now }
            close()
        } else if let resultShownAt,
                  LaunchAtLoginPrompt.shouldHideUnanswered(secondsShown: now.timeIntervalSince(resultShownAt),
                                                           pointerOnCard: pointerOnCard) {
            close()
        }
    }

    /// `kCGAnyInputEventType` (not imported into Swift): any key, click, scroll or mouse move.
    private static let anyInputEvent = CGEventType(rawValue: ~0)!

    private func openAtLogin() {
        showing = nil
        stopHideTimer()
        do {
            try LaunchAtLoginManager.setEnabled(true)   // also marks it asked
        } catch {
            // Never fatal (e.g. an unsigned dev copy can't register); the status below shows the outcome.
            NSLog("JVoice launch at login: register failed: \(error)")
        }
        switch LaunchAtLoginManager.status {
        case .enabled:
            show(title: "JVoice will open at login.", message: nil, actions: [])
            closeTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 1_600_000_000)
                guard !Task.isCancelled else { return }
                self?.close()
            }
        case .requiresApproval:
            show(title: "One more step",
                 message: "Allow JVoice in Login Items to finish.",
                 actions: [
                    .init("Done") { [weak self] in self?.close() },
                    .init("Open Login Items", primary: true) { [weak self] in
                        LaunchAtLoginManager.openSystemSettings()
                        self?.close()
                    },
                 ])
            showResultUntilHidden()
        default:
            show(title: "Couldn't turn it on.",
                 message: "You can try again with Launch at Login in Settings or the JVoice menu.",
                 actions: [.init("Done", primary: true) { [weak self] in self?.close() }])
            showResultUntilHidden()
        }
    }

    /// A result card with buttons goes away by itself too (the menu item shows the same state).
    private func showResultUntilHidden() {
        resultShownAt = Date()
        startHideTimer()
    }

    private func show(title: String, message: String?, actions: [LaunchAtLoginCard.Action]) {
        closeTask?.cancel()
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else { return }
        let shown = card ?? LaunchAtLoginCard()
        card = shown
        shown.show(title: title, message: message, actions: actions, on: screen, appearance: appearance())
    }

    private func close() {
        closeTask?.cancel()
        stopHideTimer()
        showing = nil
        resultShownAt = nil
        card?.hide()
    }
}
