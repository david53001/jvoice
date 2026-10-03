import AppKit

/// A host window whose own Esc must win over "Esc = Skip tour" while it has a job for it — the editor,
/// where Esc goes back to the Select tool and then clears the selection. While `claimsEscape` is true
/// the tag leaves Esc to the window; once the window has nothing left to do with it, Esc skips the tour.
@MainActor
public protocol TourEscapeClaiming: AnyObject {
    var claimsEscape: Bool { get }
}

/// A window — or the control that is its first responder — busy with Return and Esc itself right now:
/// Settings while a shortcut well is recording (the next key press becomes the shortcut, Esc cancels).
/// While `claimsTourKeys` is true the tag leaves both keys alone (review 2026-09-26, S3). Needed because
/// the tag's key monitor is usually installed before the control's own, and local monitors run in the
/// order they were added — the first to swallow a key hides it from the rest.
@MainActor
public protocol TourKeysClaiming: AnyObject {
    var claimsTourKeys: Bool { get }
}

/// What a key press does while a tag is up (spec §14.3): Return / keypad Enter = Next on Explain
/// steps, Esc = Skip tour. Everything else — any modifier, a held-down repeat, typing in a text
/// view, a control recording keys (`TourKeysClaiming`), a Try step's Return, Esc while the host claims
/// it — passes through to the app untouched. Pure and unit-tested.
enum TagKeys {
    enum Action: Equatable { case next, skipTour }

    static let returnKey: UInt16 = 36
    static let keypadEnter: UInt16 = 76
    static let escape: UInt16 = 53

    static func action(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, isRepeat: Bool,
                       isExplainStep: Bool, isEditingText: Bool, hostClaimsEscape: Bool = false,
                       hostClaimsKeys: Bool = false) -> Action? {
        if isRepeat || isEditingText || hostClaimsKeys { return nil }
        if !modifiers.intersection([.command, .option, .control, .shift]).isEmpty { return nil }
        switch keyCode {
        case returnKey, keypadEnter: return isExplainStep ? .next : nil
        case escape: return hostClaimsEscape ? nil : .skipTour
        default: return nil
        }
    }
}
