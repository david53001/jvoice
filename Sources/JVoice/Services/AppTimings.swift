import SwiftUI

/// Timing tokens used across the dictation flow and UI. Refer to these instead
/// of writing literal delays / animation durations inline.
public enum AppTimings {
    /// PasteManager: how long to delay before restoring the prior pasteboard.
    public static let pasteRestoreDelay: TimeInterval = 0.30
    /// PasteManager: how long to wait after activating the front app before pasting.
    public static let pasteActivationDelay: TimeInterval = 0.08

    /// Motion tokens — durations and curves used across the UI.
    public enum Motion {
        public static let pressFeedback: TimeInterval = 0.10
        public static let press = Animation.easeOut(duration: pressFeedback)
    }
}
