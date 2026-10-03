import Foundation

/// What a key press means while the Settings recorder is listening for a
/// chord. Pure so it can be verified locally (`scripts/run-logic-tests.sh`)
/// without a window; the NSEvent / Carbon / menu adapters live in
/// `ShortcutCapturePolicy+AppKit.swift` and the recorder view in `ShortcutRecorder`.
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
    ///   - hasAnyModifier: ⌘⌥⌃⇧ held. Escape/Tab/Delete only mean
    ///     cancel/clear when pressed bare — with a modifier they are ordinary
    ///     shortcut keys (⌘⌫ is a fine chord). Caps Lock and the
    ///     `.numericPad` / `.function` flags macOS puts on the arrows,
    ///     Home/End/PgUp/PgDn, ⌦ and keypad keys are NOT modifiers — see
    ///     `chordModifiers(_:)`.
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

    // MARK: - Refusals: well-formed chords JVoice must still not register

    /// Carbon modifier bits — `cmdKey`, `shiftKey`, `optionKey`, `controlKey`
    /// from Carbon.HIToolbox (ABI-stable; the tests assert they still agree).
    /// Carbon is the representation `KeyboardShortcuts.Shortcut` stores and
    /// both `RegisterEventHotKey` and `CopySymbolicHotKeys` speak.
    public static let carbonCommand = 0x0100
    public static let carbonShift = 0x0200
    public static let carbonOption = 0x0800
    public static let carbonControl = 0x1000
    static let carbonModifierMask = carbonCommand | carbonShift | carbonOption | carbonControl

    /// A key + modifiers in Carbon terms. Modifiers are masked to ⌘⇧⌥⌃: the
    /// system stores extra bits on some entries (e.g. ⌃F2 as 135168 rather
    /// than 4096), which must not stop two equal chords comparing equal.
    public struct Chord: Hashable, Sendable {
        public let keyCode: Int
        public let modifiers: Int

        public init(keyCode: Int, carbonModifiers: Int) {
            self.keyCode = keyCode
            self.modifiers = carbonModifiers & ShortcutCapturePolicy.carbonModifierMask
        }
    }

    /// One key equivalent from the app's main menu (Copy ⌘C, Quit ⌘Q, …).
    public struct MenuShortcut: Equatable, Sendable {
        public let title: String
        /// Lower-cased key equivalent.
        public let key: String
        /// Carbon ⌘⇧⌥⌃ bits.
        public let modifiers: Int

        /// An upper-case key equivalent ("Z") implies ⇧, exactly as AppKit
        /// reads it — normalised so "Z"+⌘ and "z"+⇧⌘ are the same entry.
        public init(title: String, keyEquivalent: String, carbonModifiers: Int) {
            self.title = title
            let lowered = keyEquivalent.lowercased()
            var modifiers = carbonModifiers & ShortcutCapturePolicy.carbonModifierMask
            if lowered != keyEquivalent {
                modifiers |= ShortcutCapturePolicy.carbonShift
            }
            self.key = lowered
            self.modifiers = modifiers
        }
    }

    /// Why a chord that `decide` accepted must still be refused.
    public enum Refusal: Equatable, Sendable {
        /// Already assigned to the other JVoice action (its title). Both
        /// actions would run on one press, and clearing either would
        /// unregister the shared system hotkey.
        case assignedTo(String)
        /// A macOS system shortcut owns it (System Settings › Keyboard ›
        /// Keyboard Shortcuts) — e.g. ⌘Space, ⌘⇧3, ⌃←.
        case reservedBySystem
        /// A standard menu command owns it (its title) — e.g. Copy ⌘C,
        /// Undo ⌘Z, Quit ⌘Q. Registered globally, it would stop working in
        /// every app.
        case usedByMenu(String)

        /// One line for the Settings row. `chord` is the display form ("⌘C").
        public func message(for chord: String) -> String {
            switch self {
            case .assignedTo(let action):
                return "\(chord) is already set for \(action). Pick a different shortcut."
            case .reservedBySystem:
                return "\(chord) is a macOS shortcut. Pick another, or free it in System Settings › Keyboard › Keyboard Shortcuts."
            case .usedByMenu(let title):
                return "\(chord) is the standard “\(title)” shortcut. Pick a different one."
            }
        }
    }

    /// Bare F12 is listed by the system but still works as a hotkey — the
    /// same exemption the KeyboardShortcuts package makes (kVK_F12 = 0x6F).
    static let systemExemptions: Set<Chord> = [Chord(keyCode: 0x6F, carbonModifiers: 0)]

    /// The refusal for a chord `decide` accepted, or nil when it is free.
    /// Ported from the KeyboardShortcuts recorder (`takenByMainMenu`,
    /// `isTakenBySystem`), plus the cross-action check it has no notion of.
    ///
    /// - Parameters:
    ///   - chord: the pressed chord.
    ///   - character: the chord key's character with no modifiers applied
    ///     ("c" for ⌘C), matched against menu key equivalents.
    ///   - otherActions: the OTHER JVoice actions' assigned chords (unset
    ///     ones omitted), with their display titles.
    ///   - systemChords: the enabled system symbolic hotkeys.
    ///   - menuShortcuts: the app main menu's key equivalents.
    public static func refusal(
        for chord: Chord,
        character: String?,
        otherActions: [(title: String, chord: Chord)],
        systemChords: [Chord],
        menuShortcuts: [MenuShortcut]
    ) -> Refusal? {
        if let other = otherActions.first(where: { $0.chord == chord }) {
            return .assignedTo(other.title)
        }
        if !systemExemptions.contains(chord), systemChords.contains(chord) {
            return .reservedBySystem
        }
        if let character, !character.isEmpty {
            let key = character.lowercased()
            if let item = menuShortcuts.first(where: { $0.key == key && $0.modifiers == chord.modifiers }) {
                return .usedByMenu(item.title)
            }
        }
        return nil
    }
}
