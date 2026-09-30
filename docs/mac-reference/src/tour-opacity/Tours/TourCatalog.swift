/// Every JVoice tour, as data — the contract between the tour system and the surfaces.
///
/// Anchor ids ("<surface>.<name>") are set on real controls with `.tourAnchor("…")` (SwiftUI) or
/// `view.tourAnchor = "…"` (AppKit); Try steps wait for the `TourEventName` the app posts. Copy rules
/// (enforced by the catalog lint in `scripts/run-logic-tests.sh`): title ≤ 4 words, body ≤ 20 words,
/// Try steps start with a verb, one idea per step, plain words. `{shortcut:<KeyboardShortcuts name>}`
/// shows the user's CURRENT combo (e.g. ⌥Space), or "(not set)".
public enum TourCatalog {
    public static let all: [Tour] = [welcome, recordingPill, settings]

    public static func tour(_ id: TourID) -> Tour {
        all.first { $0.id == id }!
    }

    /// Started by "Show Me Around" on the Welcome window's last page, by the Help & Tours menu, or a
    /// replay; hosted by the Welcome window. Step 1's anchor is the menu-bar status item's button, which
    /// lives in the status bar's own window (found through `TourCoordinator.extraAnchorWindows`).
    static let welcome = Tour(id: .welcome, surface: .welcome, trigger: .startedByApp, steps: [
        TourStep(anchor: "menuBar.icon", kind: .explain, title: "Your menu bar J",
                 body: "JVoice lives here. Click it to start dictating, open Settings or quit."),
        TourStep(anchor: "welcome.shortcut", kind: .explain, title: "Your dictation shortcut",
                 body: "Press {shortcut:toggleRecording} in any app to start talking. Press it again to stop."),
        TourStep(anchor: "welcome.tryIt", kind: .tryIt(advanceOn: .action(TourEventName.recordingStarted)),
                 title: "Try it now",
                 body: "Click into any text box, then press {shortcut:toggleRecording} and say something."),
    ])

    /// The first recording's HUD pill. One Try step: the user is talking, so nothing asks for a click.
    static let recordingPill = Tour(id: .recordingPill, surface: .recordingPill,
                                    trigger: .surfaceShown(.recordingPill), steps: [
        TourStep(anchor: "pill.controls", kind: .tryIt(advanceOn: .action(TourEventName.recordingStopped)),
                 title: "JVoice is listening",
                 body: "Speak, then press {shortcut:toggleRecording} again or click ■. Your words get typed for you."),
    ])

    /// The first Settings window (SwiftUI; anchors via `.tourAnchor`). The window scrolls, so the
    /// coordinator scrolls each anchor into view before its tag shows.
    static let settings = Tour(id: .settings, surface: .settings, trigger: .surfaceShown(.settings), steps: [
        TourStep(anchor: "settings.stats", kind: .explain, title: "Your stats",
                 body: "Words dictated, your speaking speed and the typing time you saved."),
        TourStep(anchor: "settings.model", kind: .explain, title: "Speech model",
                 body: "Bigger models are more accurate but slower. Everything runs on this Mac."),
        TourStep(anchor: "settings.processing", kind: .explain, title: "Clean-up options",
                 body: "Drop filler words, turn spoken maths into symbols, and more."),
        TourStep(anchor: "settings.voiceStyle", kind: .explain, title: "Voice style",
                 body: "Choose how your text comes out, from very casual to formal."),
        TourStep(anchor: "settings.appModes", kind: .explain, title: "App modes",
                 body: "Give an app its own style, like Code in your editor."),
        TourStep(anchor: "settings.shortcut", kind: .explain, title: "Your shortcut",
                 body: "Click the shortcut, then press new keys to change it. Esc cancels."),
        TourStep(anchor: "settings.transcripts", kind: .explain, title: "Recent transcripts",
                 body: "Your last dictations, kept on this Mac. Hover one to copy it again."),
        TourStep(anchor: "settings.customWords", kind: .explain, title: "Custom words",
                 body: "Add names and jargon so JVoice always spells them your way."),
        TourStep(anchor: OpacityDemoTimeline.anchor, kind: .explain, title: "Opacity",
                 body: "Sets how see-through JVoice's windows and pill are."),
        TourStep(anchor: "settings.help", kind: .explain, title: "Replay any tour",
                 body: "Click ⓘ to replay this tour, or pick one part to see again."),
    ])
}

public extension TourID {
    /// The Help & Tours menu item (Title Case).
    var menuTitle: String {
        switch self {
        case .welcome:       return "Welcome Tour"
        case .recordingPill: return "Recording Tour"
        case .settings:      return "Settings Tour"
        }
    }

    /// SF Symbol for that menu item.
    var menuSymbol: String {
        switch self {
        case .welcome:       return "hand.wave"
        case .recordingPill: return "mic"
        case .settings:      return "gearshape"
        }
    }
}
