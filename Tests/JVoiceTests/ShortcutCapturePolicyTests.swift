#if canImport(Testing)
import AppKit
import Carbon.HIToolbox
import Testing
@testable import JVoice

private func decide(
    _ key: ShortcutCapturePolicy.Key,
    anyModifier: Bool,
    besidesShift: Bool,
    functionKey: Bool = false
) -> ShortcutCapturePolicy.Decision {
    ShortcutCapturePolicy.decide(
        key: key,
        hasAnyModifier: anyModifier,
        hasModifierBesidesShift: besidesShift,
        isFunctionKey: functionKey
    )
}

@Test func bareEscapeAndTabCancel() {
    #expect(decide(.escape, anyModifier: false, besidesShift: false) == .cancel)
    #expect(decide(.tab, anyModifier: false, besidesShift: false) == .cancel)
}

@Test func bareDeleteClearsTheShortcut() {
    #expect(decide(.delete, anyModifier: false, besidesShift: false) == .clear)
}

@Test func modifiedEscapeTabAndDeleteAreOrdinaryChords() {
    #expect(decide(.escape, anyModifier: true, besidesShift: true) == .accept)
    #expect(decide(.tab, anyModifier: true, besidesShift: true) == .accept)
    #expect(decide(.delete, anyModifier: true, besidesShift: true) == .accept)
}

@Test func aModifierBesidesShiftMakesAChord() {
    #expect(decide(.other, anyModifier: true, besidesShift: true) == .accept)
}

@Test func shiftAloneIsRejected() {
    // ⇧A is not a workable global shortcut — the package beeps at it too.
    #expect(decide(.other, anyModifier: true, besidesShift: false) == .reject)
}

@Test func aBarePrintableKeyIsRejected() {
    #expect(decide(.other, anyModifier: false, besidesShift: false) == .reject)
}

@Test func functionKeysNeedNoModifier() {
    #expect(decide(.other, anyModifier: false, besidesShift: false, functionKey: true) == .accept)
    #expect(decide(.other, anyModifier: true, besidesShift: false, functionKey: true) == .accept)
}

@Test func shiftedEscapeIsRejectedRatherThanCancelling() {
    // Shift is held, so it is no longer the bare "cancel" press — but ⇧ alone
    // still does not make a chord.
    #expect(decide(.escape, anyModifier: true, besidesShift: false) == .reject)
}

// MARK: - Real key events (the NSEvent adapter)

/// A key-down NSEvent as the recorder's local monitor receives it. macOS itself
/// puts `.numericPad` / `.function` on arrows, nav keys, ⌦ and the keypad.
private func keyDown(_ keyCode: Int, _ flags: CGEventFlags = []) -> NSEvent? {
    guard let cg = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: true) else { return nil }
    cg.flags = cg.flags.union(flags)
    return NSEvent(cgEvent: cg)
}

private func decide(event keyCode: Int, _ flags: CGEventFlags = []) -> ShortcutCapturePolicy.Decision? {
    keyDown(keyCode, flags).map(ShortcutCapturePolicy.decide(event:))
}

@Test func bareArrowNavigationAndKeypadKeysAreNotChords() {
    // Before 2026-09-23 these were saved as bare global hotkeys: their own
    // .numericPad/.function flags counted as "a modifier besides shift".
    for keyCode in [kVK_RightArrow, kVK_LeftArrow, kVK_UpArrow, kVK_DownArrow, kVK_Home, kVK_End,
                    kVK_PageUp, kVK_PageDown, kVK_ANSI_Keypad5, kVK_ANSI_KeypadEnter] {
        #expect(decide(event: keyCode) == .reject, "keyCode \(keyCode)")
    }
}

@Test func bareForwardDeleteClearsLikeDelete() {
    #expect(decide(event: kVK_ForwardDelete) == .clear)
    #expect(decide(event: kVK_Delete) == .clear)
}

@Test func realEventsKeepTheExistingRules() {
    #expect(decide(event: kVK_Escape) == .cancel)
    #expect(decide(event: kVK_F5) == .accept)                      // F-keys stay recordable bare
    #expect(decide(event: kVK_Space, .maskAlternate) == .accept)   // ⌥Space
    #expect(decide(event: kVK_LeftArrow, .maskControl) == .accept) // well-formed; the system check refuses it
    #expect(decide(event: kVK_RightArrow, .maskShift) == .reject)  // ⇧ alone
    #expect(decide(event: kVK_ANSI_A, .maskAlphaShift) == .reject) // Caps Lock is not a modifier
}

@Test func onlyCommandOptionControlShiftCountAsHeld() {
    let flags: NSEvent.ModifierFlags = [.capsLock, .numericPad, .function, .help, .command]
    #expect(ShortcutCapturePolicy.chordModifiers(flags) == .command)
}

// MARK: - Refusals

private typealias P = ShortcutCapturePolicy
private let optSpace = P.Chord(keyCode: kVK_Space, carbonModifiers: optionKey)
private let cmdSpace = P.Chord(keyCode: kVK_Space, carbonModifiers: cmdKey)
private let cmdC = P.Chord(keyCode: kVK_ANSI_C, carbonModifiers: cmdKey)
private let editMenu: [P.MenuShortcut] = [
    P.MenuShortcut(title: "Undo", keyEquivalent: "z", carbonModifiers: cmdKey),
    P.MenuShortcut(title: "Redo", keyEquivalent: "Z", carbonModifiers: cmdKey),
    P.MenuShortcut(title: "Copy", keyEquivalent: "c", carbonModifiers: cmdKey),
]

private func refusal(
    _ chord: P.Chord,
    character: String? = nil,
    other: [(title: String, chord: P.Chord)] = [],
    system: [P.Chord] = [],
    menu: [P.MenuShortcut] = []
) -> P.Refusal? {
    P.refusal(for: chord, character: character, otherActions: other, systemChords: system, menuShortcuts: menu)
}

@Test func carbonBitsMatchCarbon() {
    #expect(P.carbonCommand == cmdKey)
    #expect(P.carbonShift == shiftKey)
    #expect(P.carbonOption == optionKey)
    #expect(P.carbonControl == controlKey)
    #expect(P.carbonModifiers([.command, .shift, .function, .capsLock]) == cmdKey | shiftKey)
}

@Test func aChordAlreadySetForTheOtherActionIsRefused() {
    // Both actions would run on one press, and clearing either would
    // unregister the shared system hotkey.
    #expect(refusal(optSpace, character: " ", other: [(title: "Toggle Recording", chord: optSpace)])
        == .assignedTo("Toggle Recording"))
    #expect(refusal(optSpace, character: " ", other: [(title: "Toggle Recording", chord: cmdSpace)]) == nil)
}

@Test func systemShortcutsAreRefused() {
    #expect(refusal(cmdSpace, character: " ", system: [cmdSpace]) == .reservedBySystem)
    // The system stores some modifiers with extra bits (⌃F2 as 135168).
    let ctrlF2 = P.Chord(keyCode: kVK_F2, carbonModifiers: controlKey)
    #expect(refusal(ctrlF2, system: [P.Chord(keyCode: kVK_F2, carbonModifiers: 135168)]) == .reservedBySystem)
}

@Test func bareF12IsExemptFromTheSystemList() {
    let f12 = P.Chord(keyCode: kVK_F12, carbonModifiers: 0)
    #expect(refusal(f12, system: [f12]) == nil)
}

@Test func standardMenuShortcutsAreRefused() {
    #expect(refusal(cmdC, character: "c", menu: editMenu) == .usedByMenu("Copy"))
    #expect(refusal(P.Chord(keyCode: kVK_ANSI_Z, carbonModifiers: cmdKey), character: "z", menu: editMenu) == .usedByMenu("Undo"))
    // An upper-case key equivalent implies ⇧.
    #expect(refusal(P.Chord(keyCode: kVK_ANSI_Z, carbonModifiers: cmdKey | shiftKey), character: "z", menu: editMenu) == .usedByMenu("Redo"))
    #expect(refusal(P.Chord(keyCode: kVK_ANSI_C, carbonModifiers: cmdKey | optionKey), character: "c", menu: editMenu) == nil)
}

@Test func theDefaultChordIsFree() {
    #expect(refusal(optSpace, character: " ", system: [cmdSpace], menu: editMenu) == nil)
}

@Test func refusalMessagesSayWhy() {
    #expect(P.Refusal.assignedTo("Undo Last Paste").message(for: "⌥Space").contains("Undo Last Paste"))
    #expect(P.Refusal.reservedBySystem.message(for: "⌘Space").hasPrefix("⌘Space is a macOS shortcut"))
    #expect(P.Refusal.usedByMenu("Copy").message(for: "⌘C").contains("“Copy”"))
}

@Test @MainActor func menuShortcutsWalkSubmenus() {
    let edit = NSMenu(title: "Edit")
    edit.addItem(withTitle: "Undo", action: nil, keyEquivalent: "z")
    edit.addItem(withTitle: "Redo", action: nil, keyEquivalent: "Z")
    edit.addItem(withTitle: "No Shortcut", action: nil, keyEquivalent: "")
    let main = NSMenu(title: "Main")
    main.addItem(withTitle: "Edit", action: nil, keyEquivalent: "").submenu = edit

    let shortcuts = P.menuShortcuts(in: main)
    #expect(shortcuts.map(\.title) == ["Undo", "Redo"])
    #expect(shortcuts.last == P.MenuShortcut(title: "Redo", keyEquivalent: "z", carbonModifiers: cmdKey | shiftKey))
}

@Test func systemReservedChordsAreMasked() {
    let mask = cmdKey | shiftKey | optionKey | controlKey
    #expect(P.systemReservedChords().allSatisfy { $0.modifiers & ~mask == 0 })
}
#endif
