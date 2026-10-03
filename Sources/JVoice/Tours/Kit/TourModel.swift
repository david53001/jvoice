/// The data every tour is made of. Ported from BetterScreenshot's TourKit (its v3 spec §14 / §14.9);
/// JVoice's design + decisions: `Sources/JVoice/Tours/CLAUDE.md`.

/// Every tour. Raw values are persisted (UserDefaults `toursSeen` / `toursPaused`) — never rename one.
public enum TourID: String, CaseIterable, Codable, Sendable {
    case welcome, recordingPill, settings
}

/// A window or panel a tour runs on. The app reports each one as it appears
/// (`TourEvents.surfaceShown`), with the window the tags attach to.
public enum TourSurface: String, CaseIterable, Sendable {
    /// The first-run Welcome window (`UI/WelcomeWindow.swift`).
    case welcome
    /// The HUD pill while recording (`UI/HUDWindow.swift`), reported when a recording starts.
    case recordingPill
    /// The Settings window (`UI/SettingsWindow.swift`).
    case settings
}

/// Something the user did that a Try step can wait for. Surfaces post these through `TourEvents`;
/// names are plain strings so surfaces need nothing else from TourKit.
public enum TourEvent: Hashable, Sendable {
    /// The pop-up menu or dropdown of the control with this tour anchor was opened.
    case menuOpened(String)
    /// A choice was made in the control (or its menu) with this tour anchor.
    case choiceMade(String)
    /// Anything else, named "<area>.<verb>": "recording.started", "recording.stopped",
    /// "dictation.pasted" — the full list is `TourEventName`.
    case action(String)
}

/// Every `.action(…)` name the app posts. Surfaces use these constants, never string literals.
public enum TourEventName {
    /// A recording started (hotkey, menu or pill) — posted right after the pill is shown.
    public static let recordingStarted = "recording.started"
    /// A recording was stopped by the user (hotkey, menu or the pill's stop button).
    public static let recordingStopped = "recording.stopped"
    /// A dictation finished with text (pasted, or put on the clipboard).
    public static let dictationPasted = "dictation.pasted"
}

/// One highlighted control and one short tag.
public struct TourStep: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// "This is X" — advances when the user presses Next.
        case explain
        /// "Do X" — advances by itself when `advanceOn` is posted; Skip step is always offered.
        case tryIt(advanceOn: TourEvent)
    }

    /// The tour anchor of the control this step points at (`NSView.tourAnchor`), "<surface>.<name>",
    /// e.g. "settings.shortcut".
    public let anchor: String
    public let kind: Kind
    /// At most 4 words.
    public let title: String
    /// At most 20 words, 1–2 short sentences; Try steps start with a verb. `{shortcut:<KeyboardShortcuts
    /// name>}` (e.g. `{shortcut:toggleRecording}`) is replaced with the user's current key combo.
    public let body: String
    /// Show this step only if this event has been seen during the tour; otherwise it's skipped like a
    /// missing anchor. Nil = no precondition.
    public let requires: TourEvent?
    /// Where the tag goes relative to the outlined control. `.automatic` lets the layout choose.
    public let placement: Placement

    /// A step's preferred tag position (review 2026-09-26, T3/E4/V2/V4).
    public enum Placement: String, Equatable, Sendable {
        /// The layout picks the side with room.
        case automatic
        case left, right, above, below
        /// Inside the control's top-right corner, no leader line — for controls that fill most of their
        /// window (the editor canvas, the video preview, the Settings cards), where "beside" means over
        /// the neighbouring UI.
        case insideCorner
    }

    public init(anchor: String, kind: Kind, title: String, body: String,
                requires: TourEvent? = nil, placement: Placement = .automatic) {
        self.anchor = anchor
        self.kind = kind
        self.title = title
        self.body = body
        self.requires = requires
        self.placement = placement
    }
}

/// What starts a tour automatically (only for users with first-use tours on — spec §14.9).
public enum TourTrigger: Equatable, Sendable {
    /// The first time this surface appears.
    case surfaceShown(TourSurface)
    /// The first time this event is posted.
    case event(TourEvent)
    /// Never by itself: the app starts it (Welcome, after "Show Me Around") or another tour hands over.
    case startedByApp
}

public struct Tour: Equatable, Sendable {
    public let id: TourID
    /// Bump after a big UI change so users with first-use tours on see it once more.
    public let version: Int
    /// The surface whose window the tags attach to.
    public let surface: TourSurface
    public let trigger: TourTrigger
    public let steps: [TourStep]
    /// The tour that starts when this one finishes.
    public let handsOverTo: TourID?

    public init(id: TourID, version: Int = 1, surface: TourSurface, trigger: TourTrigger,
                steps: [TourStep], handsOverTo: TourID? = nil) {
        self.id = id
        self.version = version
        self.surface = surface
        self.trigger = trigger
        self.steps = steps
        self.handsOverTo = handsOverTo
    }
}
