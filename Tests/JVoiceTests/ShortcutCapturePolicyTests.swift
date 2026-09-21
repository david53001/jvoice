#if canImport(Testing)
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
#endif
