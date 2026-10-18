import CoreGraphics
import Foundation

/// Where `LaunchAtLoginPrompt` keeps its state: the app's `UserDefaults.standard`; tests use an
/// in-memory store, so a test run never writes a preferences file.
protocol LaunchAtLoginPromptStorage {
    func integer(forKey defaultName: String) -> Int
    func bool(forKey defaultName: String) -> Bool
    func double(forKey defaultName: String) -> Double
    func set(_ value: Int, forKey defaultName: String)
    func set(_ value: Bool, forKey defaultName: String)
    func set(_ value: Double, forKey defaultName: String)
}

extension UserDefaults: LaunchAtLoginPromptStorage {}

/// When JVoice asks "Open JVoice at login?" (a small corner card, `UI/LaunchAtLoginPromptController.swift`).
/// Same rules as MacStats and BetterScreenshot (docs/sparkle-updates/README.md). Pure (Foundation +
/// CoreGraphics), so `scripts/run-logic-tests.sh` runs it on this Mac.
///
/// Rules: count each completed dictation whose text reached the user (pasted, or copied in
/// clipboard-only mode); a cancelled, empty ("No speech detected"), failed or refused one isn't one.
/// Once `usesBeforeAsking` are recorded, ask at the next calm moment (`isCalmMoment`). It is answered
/// at most once ever, never asked when launch at login is already on, and never asked of users of
/// ≤ 1.1.4, whose first launch turned it on by itself (that build wrote `legacyAutoEnabled`): they
/// either still have it, or turned it off on purpose. A choice made with the menu's Launch at Login
/// item also counts as answered. A card left unanswered goes away by itself after
/// `unansweredHideSeconds`. It only counts as a showing if the user could have seen it (`Showing`):
/// then it comes back after a later dictation at least `reshowAfterSeconds` later (or after a
/// relaunch), at most `maxShowings` times in all; after the last one it counts as answered "no".
///
/// All state is in the standard defaults under the `Key` names (namespace `jvoice.app.*`).
struct LaunchAtLoginPrompt {
    enum Key {
        /// Int: completed dictations counted so far (stops at `usesBeforeAsking`).
        static let uses = "jvoice.app.launchAtLoginPrompt.uses"
        /// Bool: the question was answered (or ignored `maxShowings` times), or the user chose with the
        /// menu item, or launch at login was found on. Never asked again.
        static let asked = "jvoice.app.launchAtLoginPrompt.asked"
        /// Int: times the card was seen and went away unanswered (`Showing.counts`).
        static let unansweredShowings = "jvoice.app.launchAtLoginPrompt.unansweredShowings"
        /// Double: when the last such showing ended, in seconds since 1970 (0 = never).
        static let lastShownAt = "jvoice.app.launchAtLoginPrompt.lastShownAt"
        /// Bool, read only: written by ≤ 1.1.4 with its silent first-launch enable
        /// (`LaunchAtLoginManager.performFirstRunEnableIfNeeded`, removed in 1.2.0).
        static let legacyAutoEnabled = "jvoice.app.launchAtLogin.didInitialize"
    }

    static let usesBeforeAsking = 5

    /// The decision itself, free of storage.
    static func shouldAsk(uses: Int, asked: Bool, legacyAutoEnabled: Bool, enabled: Bool) -> Bool {
        uses >= usesBeforeAsking && !asked && !legacyAutoEnabled && !enabled
    }

    // MARK: Calm moment

    /// Seconds after the dictation that made it due before the card may appear: the user is usually
    /// still reading or editing what was just pasted.
    static let settleSeconds: TimeInterval = 3
    /// No key pressed for this long: the card never pops up mid-typing (it doesn't take focus either
    /// way; this is about not distracting).
    static let typingQuietSeconds: TimeInterval = 2
    /// How long the app keeps waiting for a calm moment after a dictation; the next one tries again.
    static let giveUpSeconds: TimeInterval = 120

    /// What `isCalmMoment` looks at, read by the app once a second while the question is due.
    struct Moment: Equatable {
        var secondsSinceUse: TimeInterval
        var secondsSinceKeyPress: TimeInterval
        var mouseButtonDown: Bool
        /// Recording, transcribing, pasting, or a HUD pill (incl. an error) on screen.
        var dictationActive: Bool
        /// One of our own windows (Settings, Welcome) is in front: the user is working in it.
        var appIsActive: Bool
        /// The menu-bar menu is open (menu tracking; `appIsActive` and the mouse buttons don't show it).
        var menuIsOpen: Bool
        /// A guided-tour tag is on screen (the tour owns the user's attention).
        var tourShowing: Bool
        /// The frontmost app has a window covering a whole screen, menu bar included: a full-screen
        /// app (the card would be on another Space, unseen), a presentation or a game.
        var fullScreenInFront: Bool
    }

    /// A moment when the card can't interrupt anything: the dictation has settled, nothing of ours is
    /// in use, no drag is in progress, the user isn't typing and nothing full-screen is in front.
    static func isCalmMoment(_ m: Moment) -> Bool {
        m.secondsSinceUse >= settleSeconds && m.secondsSinceKeyPress >= typingQuietSeconds
            && !m.mouseButtonDown && !m.dictationActive && !m.appIsActive && !m.menuIsOpen
            && !m.tourShowing && !m.fullScreenInFront
    }

    /// An on-screen window, as `CGWindowListCopyWindowInfo` reports it (bounds and owner need no
    /// Screen Recording permission).
    struct WindowInfo: Equatable {
        var ownerPID: Int32
        /// `kCGWindowLayer`: 0 for normal windows, negative for the desktop, higher for panels.
        var layer: Int
        /// Top-left origin on the primary screen (Quartz window coordinates).
        var bounds: CGRect
    }

    /// `Moment.fullScreenInFront`: the frontmost app has a window exactly the size of a screen, menu
    /// bar included (a full-screen app, a presentation, a full-screen game). A zoomed window stops at
    /// the menu bar, and the desktop (negative layer) or another app's window don't count.
    /// `screenFrames` are `NSScreen.frame`s (bottom-left origin, the primary screen first).
    static func fullScreenInFront(frontmostPID: Int32?, windows: [WindowInfo], screenFrames: [CGRect]) -> Bool {
        guard let frontmostPID, let primary = screenFrames.first else { return false }
        let screens = screenFrames.map {
            CGRect(x: $0.minX, y: primary.maxY - $0.maxY, width: $0.width, height: $0.height)
        }
        return windows.contains { $0.ownerPID == frontmostPID && $0.layer >= 0 && screens.contains($0.bounds) }
    }

    // MARK: The flow, one step at a time (the app's controller only carries these out)

    /// What to do right after a dictation (`afterUse`).
    enum AfterUse: Equatable {
        /// Not due, or the card is already up.
        case nothing
        /// Due, but the card was seen less than `reshowAfterSeconds` ago in this launch, or shown
        /// unseen less than `reshowAfterUnseenSeconds` ago.
        case tooSoon
        /// Due: look for a calm moment (`waitStep`, once a second).
        case startWaiting
        /// Launch at login is on already: marked asked, so no later dictation checks again.
        case alreadyEnabled
    }

    /// A completed dictation: records it (`recordUse`), then decides. `isEnabled` reads the system's
    /// status (an XPC call), so it is only called when the question could be due and isn't spaced
    /// out; found on, the question is marked asked. `shownThisLaunch`: a counted showing ended since
    /// the app started; `unseenShowingEndedAt`: when the last showing that didn't count ended, in
    /// this launch.
    func afterUse(cardVisible: Bool, shownThisLaunch: Bool, unseenShowingEndedAt: Date? = nil,
                  now: Date = Date(), isEnabled: () -> Bool) -> AfterUse {
        recordUse()
        guard couldAsk, !cardVisible else { return .nothing }
        guard Self.mayShowAgain(secondsSinceLastShowing: secondsSinceLastShowing(now: now),
                                shownThisLaunch: shownThisLaunch,
                                secondsSinceUnseenShowing: unseenShowingEndedAt.map { now.timeIntervalSince($0) })
        else { return .tooSoon }
        guard !isEnabled() else {
            markAsked()
            return .alreadyEnabled
        }
        return .startWaiting
    }

    /// One tick of the wait for a calm moment (`waitStep`).
    enum WaitStep: Equatable {
        /// Not calm yet: check again in a second.
        case keepWaiting
        /// `giveUpSeconds` passed since the dictation: stop; the next dictation starts a new wait.
        case giveUp
        /// Calm, still due, launch at login still off: show the card.
        case show
        /// Answered meanwhile (the menu item): stop.
        case noLongerDue
        /// Turned on meanwhile (System Settings): stop; marked asked, never asked.
        case alreadyEnabled
    }

    /// `couldAsk` and `isEnabled` are re-read right before showing, because either can change while
    /// the app waits; `isEnabled` (an XPC call) only once the moment is calm.
    func waitStep(_ m: Moment, isEnabled: () -> Bool) -> WaitStep {
        if m.secondsSinceUse >= Self.giveUpSeconds { return .giveUp }
        guard Self.isCalmMoment(m) else { return .keepWaiting }
        guard couldAsk else { return .noLongerDue }
        guard !isEnabled() else {
            markAsked()
            return .alreadyEnabled
        }
        return .show
    }

    // MARK: An unanswered card

    /// An unanswered card goes away by itself after this long on screen, like a macOS banner, so it
    /// never sits over a presentation or a shared screen. The "One more step" and "Couldn't turn it
    /// on" cards too (they don't count as showings: the question is answered).
    static let unansweredHideSeconds: TimeInterval = 25
    /// Shown (and seen) at most this many times without an answer; after the last it counts as "no".
    static let maxShowings = 3
    /// A showing only counts once the card was seen this long (`Showing.secondsSeen`).
    static let minimumSecondsSeen: TimeInterval = 5
    /// After a counted showing, the card only comes back this much later, or after a relaunch.
    static let reshowAfterSeconds: TimeInterval = 24 * 60 * 60
    /// After a showing that didn't count, it comes back on a dictation this much later (not on the
    /// very next one: someone who never touches the mouse while it's up isn't shown it every time).
    static let reshowAfterUnseenSeconds: TimeInterval = 10 * 60

    /// Whether the card should go now: after `unansweredHideSeconds`, but not while the pointer is on
    /// it (the user is about to click).
    static func shouldHideUnanswered(secondsShown: TimeInterval, pointerOnCard: Bool) -> Bool {
        secondsShown >= unansweredHideSeconds && !pointerOnCard
    }

    /// Whether another showing may start now. `secondsSinceLastShowing`: since the last counted one
    /// ended (nil: none yet, ever); `secondsSinceUnseenShowing`: since the last uncounted one ended in
    /// this launch (nil: none).
    static func mayShowAgain(secondsSinceLastShowing: TimeInterval?, shownThisLaunch: Bool,
                             secondsSinceUnseenShowing: TimeInterval? = nil) -> Bool {
        if let unseen = secondsSinceUnseenShowing, unseen < reshowAfterUnseenSeconds { return false }
        guard let seconds = secondsSinceLastShowing else { return true }
        return !shownThisLaunch || seconds >= reshowAfterSeconds
    }

    /// One showing of the question, followed by the app once a second while it is up, so that only a
    /// card the user could have seen counts: one that was on screen (on the active Space, not
    /// covered, the screen not locked or asleep) after the user had used the mouse or keyboard since
    /// it appeared (not a desk they walked away from).
    struct Showing: Equatable {
        /// Wall-clock time on screen (for `shouldHideUnanswered`).
        private(set) var secondsShown: TimeInterval = 0
        /// Time it was visible with the user there.
        private(set) var secondsSeen: TimeInterval = 0

        /// The longest a single tick adds to `secondsSeen`: a tick that comes late (the Mac slept with
        /// the card up) says nothing about the time in between.
        static let maxSecondsPerTick: TimeInterval = 2

        /// - Parameters:
        ///   - seconds: since the previous tick (or since the card appeared).
        ///   - cardVisible: the card's window is on the active Space and not covered.
        ///   - secondsSinceInput: since the last key, click, scroll or mouse move, anywhere.
        mutating func tick(seconds: TimeInterval, cardVisible: Bool, secondsSinceInput: TimeInterval) {
            secondsShown += seconds
            if cardVisible && secondsSinceInput < secondsShown {
                secondsSeen += min(seconds, Self.maxSecondsPerTick)
            }
        }

        /// Whether it counts towards `maxShowings`.
        var counts: Bool { secondsSeen >= LaunchAtLoginPrompt.minimumSecondsSeen }
    }

    // MARK: Storage

    private let storage: LaunchAtLoginPromptStorage

    init(storage: LaunchAtLoginPromptStorage = UserDefaults.standard) {
        self.storage = storage
    }

    var uses: Int { storage.integer(forKey: Key.uses) }
    var asked: Bool { storage.bool(forKey: Key.asked) }
    var unansweredShowings: Int { storage.integer(forKey: Key.unansweredShowings) }
    private var legacyAutoEnabled: Bool { storage.bool(forKey: Key.legacyAutoEnabled) }

    /// Seconds since the last counted showing ended, or nil if there was none.
    func secondsSinceLastShowing(now: Date = Date()) -> TimeInterval? {
        let last = storage.double(forKey: Key.lastShownAt)
        return last > 0 ? now.timeIntervalSince1970 - last : nil
    }

    /// Everything but the launch-at-login status, so callers can skip reading that (an XPC call to the
    /// system) until the question could actually be due.
    var couldAsk: Bool {
        Self.shouldAsk(uses: uses, asked: asked, legacyAutoEnabled: legacyAutoEnabled, enabled: false)
    }

    func shouldAsk(enabled: Bool) -> Bool {
        Self.shouldAsk(uses: uses, asked: asked, legacyAutoEnabled: legacyAutoEnabled, enabled: enabled)
    }

    /// Records one completed dictation. Returns whether it counted: nothing more is counted once the
    /// threshold is reached or the question can no longer come (asked, or a ≤ 1.1.4 user).
    @discardableResult
    func recordUse() -> Bool {
        guard !asked, !legacyAutoEnabled, uses < Self.usesBeforeAsking else { return false }
        storage.set(uses + 1, forKey: Key.uses)
        return true
    }

    func markAsked() {
        storage.set(true, forKey: Key.asked)
    }

    /// The question card went away unanswered (`shouldHideUnanswered`). Only a showing the user could
    /// have seen (`Showing.counts`) is recorded (`recordUnansweredShowing`, and its time for
    /// `reshowAfterSeconds`); any other only delays the next one (`reshowAfterUnseenSeconds`, kept by
    /// the app for this launch). Returns whether it counted.
    @discardableResult
    func cardHidUnanswered(_ showing: Showing, now: Date = Date()) -> Bool {
        guard showing.counts else { return false }
        storage.set(now.timeIntervalSince1970, forKey: Key.lastShownAt)
        recordUnansweredShowing()
        return true
    }

    /// One more unanswered showing. It stays due, so a later dictation brings it back, until this was
    /// the `maxShowings`th time: then it counts as answered. Returns whether that was the last.
    @discardableResult
    func recordUnansweredShowing() -> Bool {
        let showings = unansweredShowings + 1
        storage.set(showings, forKey: Key.unansweredShowings)
        guard showings >= Self.maxShowings else { return false }
        markAsked()
        return true
    }
}

// MARK: - The card's colours

/// The card's text contrast, computed for the worst backdrop (the card is translucent): a pure black
/// desktop behind a light card, pure white behind a dark one. The card puts `tintAlpha` of the window
/// background colour over its blur, and text is the label colour (85 % alpha). Both appearances stay at
/// or above `minimumContrast` (WCAG AA for body text); `run-logic-tests.sh` checks the numbers.
enum LaunchAtLoginCardColors {
    /// Opacity of the window-background tint over the card's `.hudWindow` blur.
    static let tintAlpha: Double = 0.75
    /// Opacity of the secondary button's `Color.primary` fill (the design language's small button).
    static let secondaryButtonFill: Double = 0.08
    static let minimumContrast: Double = 4.5

    /// sRGB grey levels (0…1) of the system colours involved (`windowBackgroundColor`: 236 in light,
    /// 30 in dark; `labelColor`: black / white at `labelAlpha`).
    static let lightTint = 236.0 / 255, darkTint = 30.0 / 255
    static let labelAlpha = 0.85

    /// Text on the card (or on its secondary button), worst case, for one appearance.
    static func worstContrast(dark: Bool, onSecondaryButton: Bool = false) -> Double {
        let backdrop = dark ? 1.0 : 0.0                 // the brightest / darkest desktop
        let tint = dark ? darkTint : lightTint
        let label = dark ? 1.0 : 0.0
        var surface = tintAlpha * tint + (1 - tintAlpha) * backdrop
        if onSecondaryButton { surface = secondaryButtonFill * label + (1 - secondaryButtonFill) * surface }
        let text = labelAlpha * label + (1 - labelAlpha) * surface
        return contrast(text, surface)
    }

    /// WCAG contrast ratio of two sRGB grey levels.
    static func contrast(_ a: Double, _ b: Double) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    static func luminance(_ srgb: Double) -> Double {
        srgb <= 0.04045 ? srgb / 12.92 : pow((srgb + 0.055) / 1.055, 2.4)
    }
}
