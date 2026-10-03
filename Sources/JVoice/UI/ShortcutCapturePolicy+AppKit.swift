import AppKit
import Carbon.HIToolbox

/// The thin AppKit / Carbon side of `ShortcutCapturePolicy`: turning an
/// `NSEvent`, the system's symbolic hotkeys and the app's main menu into the
/// policy's inputs. Deliberately free of KeyboardShortcuts (and so of its
/// `Bundle.module` trap) and of any window, so `scripts/run-logic-tests.sh`
/// can drive it with synthesized key events.
extension ShortcutCapturePolicy {
    /// The held modifiers that make up a chord: ⌘⌥⌃⇧ only — exactly what a
    /// Carbon hotkey (and so the stored `Shortcut`) can carry. `.capsLock` is
    /// a toggle state, and macOS sets `.numericPad` / `.function` on the
    /// arrows, Home/End/PgUp/PgDn, ⌦ and keypad keys THEMSELVES; counting
    /// those as "held" let a bare → or ⌦ be saved as a global hotkey. This
    /// drops them like the KeyboardShortcuts package's `NSEvent.modifiers`
    /// does, and `.help` / device-dependent bits too. (F-keys also carry
    /// `.function`; they stay recordable bare through `isFunctionKey`.)
    static func chordModifiers(_ flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        flags.intersection([.command, .option, .control, .shift])
    }

    /// `decide` for a key-down event.
    static func decide(event: NSEvent) -> Decision {
        let modifiers = chordModifiers(event.modifierFlags)
        return decide(
            key: key(for: event),
            hasAnyModifier: !modifiers.isEmpty,
            hasModifierBesidesShift: !modifiers.subtracting(.shift).isEmpty,
            isFunctionKey: isFunctionKey(event)
        )
    }

    static func key(for event: NSEvent) -> Key {
        if event.keyCode == UInt16(kVK_Escape) {
            return .escape
        }
        switch event.specialKey {
        case .tab:
            return .tab
        case .delete, .deleteForward, .backspace:
            return .delete
        default:
            return .other
        }
    }

    static func isFunctionKey(_ event: NSEvent) -> Bool {
        guard let special = event.specialKey else { return false }
        return (NSEvent.SpecialKey.f1.rawValue...NSEvent.SpecialKey.f35.rawValue).contains(special.rawValue)
    }

    /// The event's key with no modifiers applied ("c" for ⌘C, "z" for ⇧⌘Z),
    /// for matching menu key equivalents.
    static func character(of event: NSEvent) -> String? {
        event.characters(byApplyingModifiers: [])
    }

    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> Int {
        var carbon = 0
        if flags.contains(.command) { carbon |= carbonCommand }
        if flags.contains(.shift) { carbon |= carbonShift }
        if flags.contains(.option) { carbon |= carbonOption }
        if flags.contains(.control) { carbon |= carbonControl }
        return carbon
    }

    /// The system-wide shortcuts that are switched on (Spotlight ⌘Space,
    /// screenshots ⌘⇧3, Mission Control ⌃↑, Spaces ⌃←, …) — the list the
    /// KeyboardShortcuts package's `isTakenBySystem` reads.
    static func systemReservedChords() -> [Chord] {
        var unmanaged: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&unmanaged) == noErr,
              let entries = unmanaged?.takeRetainedValue() as? [[String: Any]]
        else { return [] }

        return entries.compactMap { entry in
            guard (entry[kHISymbolicHotKeyEnabled as String] as? Bool) == true,
                  let keyCode = entry[kHISymbolicHotKeyCode as String] as? Int,
                  let modifiers = entry[kHISymbolicHotKeyModifiers as String] as? Int
            else { return nil }
            return Chord(keyCode: keyCode, carbonModifiers: modifiers)
        }
    }

    /// Every key equivalent in `menu` and its submenus. Items that need fn
    /// (Globe) are skipped: a Carbon hotkey has no fn bit, so they can never
    /// collide — the package's exact-mask comparison skips them the same way.
    @MainActor
    static func menuShortcuts(in menu: NSMenu?) -> [MenuShortcut] {
        guard let menu else { return [] }
        var shortcuts: [MenuShortcut] = []
        for item in menu.items {
            if !item.keyEquivalent.isEmpty, !item.keyEquivalentModifierMask.contains(.function) {
                shortcuts.append(MenuShortcut(
                    title: item.title,
                    keyEquivalent: item.keyEquivalent,
                    carbonModifiers: carbonModifiers(item.keyEquivalentModifierMask)
                ))
            }
            shortcuts += menuShortcuts(in: item.submenu)
        }
        return shortcuts
    }
}
