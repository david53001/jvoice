import Foundation

/// What a key press means while the Settings recorder is listening for a
/// chord. Pure so it can be verified locally (`scripts/run-logic-tests.sh`)
/// without a window; the AppKit event plumbing lives in `ShortcutRecorder`.
///
/// The rules mirror the ones the KeyboardShortcuts package applies in its own
/// recorder — see the file header of `ShortcutRecorder.swift` for why JVoice
/// draws that control itself.
public enum ShortcutCapturePolicy {
    /// The pressed key, classified by the caller.
    public enum Key: Equatable, Sendable {
        case escape
        /// Tab moves focus on, so it cannot be recorded bare.
        case tab
        /// Delete / forward delete / backspace.
        case delete
        case other
    }

    public enum Decision: Equatable, Sendable {
        /// Stop listening, leave the assignment as it was.
        case cancel
        /// Remove the assigned shortcut.
        case clear
        /// Not a usable global chord — beep and keep listening.
        case reject
        /// Store the chord.
        case accept
    }

    /// - Parameters:
    ///   - key: the pressed key.
    ///   - hasAnyModifier: ⌘⌥⌃⇧ (or fn) held. Escape/Tab/Delete only mean
    ///     cancel/clear when pressed bare — with a modifier they are ordinary
    ///     shortcut keys (⌘⌫ is a fine chord).
    ///   - hasModifierBesidesShift: a modifier other than ⇧ is held. Shift
    ///     alone does not make a working global chord.
    ///   - isFunctionKey: F1…F35, which are usable with no modifier at all.
    public static func decide(
        key: Key,
        hasAnyModifier: Bool,
        hasModifierBesidesShift: Bool,
        isFunctionKey: Bool
    ) -> Decision {
        if !hasAnyModifier {
            switch key {
            case .escape, .tab:
                return .cancel
            case .delete:
                return .clear
            case .other:
                break
            }
        }

        return hasModifierBesidesShift || isFunctionKey ? .accept : .reject
    }
}
