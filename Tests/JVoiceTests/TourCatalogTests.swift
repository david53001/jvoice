// A lint of JVoice's real tour catalog (Sources/JVoice/Tours/TourCatalog.swift): copy limits, anchor /
// event / shortcut names, catalog shape, and that every body fits the tag's two lines. Ported from
// BetterScreenshot's TourKit CatalogLintTests + CatalogShapeTests + TagFitTests, adapted to JVoice (its
// straight-apostrophe rule is dropped: JVoice's UI copy uses straight apostrophes).
// This suite is the authority (CI); `scripts/run-logic-tests.sh` (the "Tours" section) mirrors it as
// the local smoke check — change both.
#if canImport(Testing)
import AppKit
import Testing
@testable import JVoice

/// The `KeyboardShortcuts.Name`s a `{shortcut:…}` placeholder may name.
private let shortcutNames: Set<String> = [HotKeyShortcutName.toggleRecording.rawValue, HotKeyShortcutName.undoLastPaste.rawValue]
/// Every `TourEventName` constant — the `.action(…)` names a Try step may wait for. Add new constants here.
private let eventNames: Set<String> = [TourEventName.recordingStarted, TourEventName.recordingStopped, TourEventName.dictationPasted]
/// The anchor prefix of each surface's controls ("<surface>.<name>").
private func anchorPrefix(_ s: TourSurface) -> String {
    switch s {
    case .welcome: return "welcome"
    case .recordingPill: return "pill"
    case .settings: return "settings"
    }
}
/// Anchors outside any surface's window: the menu-bar J (the Welcome tour's first step).
private let extraAnchors: Set<String> = ["menuBar.icon"]

/// Copy rules: title ≤ 4 words; body ≤ 20 words and ≤ 2 sentences; Try bodies start with a verb; anchors
/// look like "<surface>.<name>" on the tour's own surface; placeholders name real shortcuts; a Try step's
/// action is a `TourEventName`; a `requires` names an earlier Try step's event.
private enum CatalogLint {
    static let maxTitleWords = 4, maxBodyWords = 20, maxSentences = 2
    static let notVerbs: Set<String> = ["this", "these", "that", "the", "your", "a", "an", "here", "it", "you", "jvoice"]

    /// A word has a letter or digit ("—", "·", "■" don't count); a placeholder is one word.
    static func words(_ text: String) -> [Substring] {
        text.split(whereSeparator: \.isWhitespace).filter { $0.contains { $0.isLetter || $0.isNumber } }
    }

    static func sentenceCount(_ text: String) -> Int {
        let pieces = text.components(separatedBy: CharacterSet(charactersIn: ".!?…"))
        return max(1, pieces.filter { $0.contains { $0.isLetter || $0.isNumber } }.count)
    }

    static func isAnchorShaped(_ s: String) -> Bool {
        s.range(of: #"^[a-z][A-Za-z0-9]*(\.[a-z][A-Za-z0-9]*)+$"#, options: .regularExpression) != nil
    }

    static func problems(_ step: TourStep, in tour: Tour) -> [String] {
        let at = "\(tour.id.rawValue)/\(step.anchor)"
        var out: [String] = []
        let tw = words(step.title).count
        if tw == 0 || tw > maxTitleWords { out.append("\(at): title has \(tw) words") }
        let bw = words(step.body).count
        if bw == 0 || bw > maxBodyWords { out.append("\(at): body has \(bw) words") }
        if sentenceCount(step.body) > maxSentences { out.append("\(at): body has more than 2 sentences") }
        if !isAnchorShaped(step.anchor) {
            out.append("\(at): anchor isn't <surface>.<name>")
        } else if !extraAnchors.contains(step.anchor) && !step.anchor.hasPrefix(anchorPrefix(tour.surface) + ".") {
            out.append("\(at): anchor isn't on the \(tour.surface) surface (\(anchorPrefix(tour.surface)).…)")
        }
        for name in TourText.shortcutNames(in: step.body) where !shortcutNames.contains(name) {
            out.append("\(at): {shortcut:\(name)} isn't a KeyboardShortcuts name")
        }
        let stripped = TourText.resolvingShortcuts(in: step.body) { _ in "" }
        if stripped.contains("{") || stripped.contains("}") || step.title.contains("{") {
            out.append("\(at): stray brace — placeholders are {shortcut:<name>} in the body only")
        }
        if case .tryIt(let event) = step.kind {
            if let first = words(step.body).first, notVerbs.contains(first.lowercased()) {
                out.append("\(at): Try body should start with a verb, not \"\(first)\"")
            }
            switch event {
            case .action(let n):
                if !eventNames.contains(n) { out.append("\(at): event \"\(n)\" isn't a TourEventName") }
            case .menuOpened(let a), .choiceMade(let a):
                if !isAnchorShaped(a) { out.append("\(at): event anchor \"\(a)\" isn't <surface>.<name>") }
            }
        }
        return out
    }

    /// Plus: no two Try steps in one tour wait for the same event (the engine would skip the second as
    /// "already done"); a `requires` is what an earlier Try step of the same tour waits for.
    static func problems(_ tour: Tour) -> [String] {
        var out = tour.steps.flatMap { problems($0, in: tour) }
        var awaited: Set<TourEvent> = []
        for s in tour.steps {
            if let needed = s.requires, !awaited.contains(needed) {
                out.append("\(tour.id.rawValue)/\(s.anchor): requires \(needed), which no earlier Try step waits for")
            }
            guard case .tryIt(let event) = s.kind else { continue }
            if !awaited.insert(event).inserted { out.append("\(tour.id.rawValue): two Try steps wait for \(event)") }
        }
        return out
    }
}

private func step(_ title: String, _ body: String, anchor: String = "settings.model",
                  kind: TourStep.Kind = .explain) -> TourStep {
    TourStep(anchor: anchor, kind: kind, title: title, body: body)
}
private let settingsTour = TourCatalog.tour(.settings)
private let welcomeTour = TourCatalog.tour(.welcome)
private func makeSettingsTour(_ steps: [TourStep]) -> Tour {
    Tour(id: .settings, surface: .settings, trigger: .surfaceShown(.settings), steps: steps)
}

@Suite struct TourCatalogLintTests {
    @Test(arguments: TourCatalog.all.map(\.id))
    func everyCatalogStepPassesTheCopyRules(_ id: TourID) {
        let tour = TourCatalog.tour(id)
        #expect(!tour.steps.isEmpty)
        for problem in CatalogLint.problems(tour) { Issue.record(Comment(rawValue: problem)) }
    }

    // The lint itself (so it's known to bite).

    @Test func lintAcceptsGoodCopy() {
        #expect(CatalogLint.problems(step("Speech model", "Bigger is slower. It runs here."), in: settingsTour) == [])
        #expect(CatalogLint.problems(step("Try it", "Press {shortcut:toggleRecording} and talk — anything works.", anchor: "welcome.tryIt",
                                          kind: .tryIt(advanceOn: .action(TourEventName.recordingStarted))), in: welcomeTour) == [])
        #expect(CatalogLint.problems(step("Your menu bar J", "Click it.", anchor: "menuBar.icon"), in: welcomeTour) == [])
        #expect(CatalogLint.problems(step("Pick one", "Open the model menu.",
                                          kind: .tryIt(advanceOn: .menuOpened("settings.model"))), in: settingsTour) == [])
    }

    @Test func lintRejectsLongTitleAndBody() {
        #expect(CatalogLint.problems(step("This title is five words", "Fine."), in: settingsTour).count == 1)
        #expect(CatalogLint.problems(step("Title", Array(repeating: "word", count: 21).joined(separator: " ")), in: settingsTour).count == 1)
        #expect(CatalogLint.problems(step("Title", Array(repeating: "word", count: 20).joined(separator: " ") + " —"), in: settingsTour) == [])
    }

    @Test func lintRejectsThreeSentences() {
        #expect(CatalogLint.problems(step("Title", "One. Two. Three."), in: settingsTour).count == 1)
        #expect(CatalogLint.problems(step("Title", "One! Two?"), in: settingsTour) == [])
    }

    @Test(arguments: ["model", "Settings.model", "settings.", ".model", "settings model", "settings.custom-words", "welcome.shortcut"])
    func lintRejectsBadAnchors(_ bad: String) {
        #expect(CatalogLint.problems(step("Title", "Body.", anchor: bad), in: settingsTour).count == 1)
    }

    @Test func lintAcceptsANestedAnchor() {
        #expect(CatalogLint.problems(step("Title", "Body.", anchor: "settings.card.model"), in: settingsTour) == [])
    }

    @Test func lintRejectsUnknownShortcutsAndStrayBraces() {
        #expect(CatalogLint.problems(step("Title", "Press {shortcut:captureArea}."), in: settingsTour).count == 1)
        #expect(CatalogLint.problems(step("Title", "Press {shortcut toggleRecording}."), in: settingsTour).count == 1)
        #expect(CatalogLint.problems(step("Title {x}", "Body."), in: settingsTour).count == 1)
        for name in shortcutNames {
            #expect(CatalogLint.problems(step("Title", "Press {shortcut:\(name)}."), in: settingsTour) == [], "\(name)")
        }
    }

    @Test func lintRejectsTryBodyNotStartingWithVerb() {
        let s = step("Title", "The model menu picks it.", kind: .tryIt(advanceOn: .menuOpened("settings.model")))
        #expect(CatalogLint.problems(s, in: settingsTour).count == 1)
    }

    @Test func lintRejectsBadEventNames() {
        let notAConstant = step("Title", "Talk now.", kind: .tryIt(advanceOn: .action("recording.begun")))
        let notAnAnchor = step("Title", "Open it.", kind: .tryIt(advanceOn: .menuOpened("model")))
        #expect(CatalogLint.problems(notAConstant, in: settingsTour).count == 1)
        #expect(CatalogLint.problems(notAnAnchor, in: settingsTour).count == 1)
    }

    @Test func lintRejectsTwoTryStepsOnOneEventAndABackwardsRequirement() {
        let a = step("Start", "Press the keys.", anchor: "settings.a", kind: .tryIt(advanceOn: .action(TourEventName.recordingStarted)))
        let b = step("Again", "Press them again.", anchor: "settings.b", kind: .tryIt(advanceOn: .action(TourEventName.recordingStarted)))
        #expect(CatalogLint.problems(makeSettingsTour([a, b])).count == 1)
        let stop = TourStep(anchor: "settings.b", kind: .tryIt(advanceOn: .action(TourEventName.recordingStopped)),
                            title: "Stop", body: "Press again.", requires: .action(TourEventName.recordingStarted))
        #expect(CatalogLint.problems(makeSettingsTour([a, stop])) == [])
        #expect(CatalogLint.problems(makeSettingsTour([stop, a])).count == 1)
    }
}

@Suite struct TourCatalogShapeTests {
    @Test func everyTourIdHasExactlyOneTour() {
        #expect(Set(TourCatalog.all.map(\.id)) == Set(TourID.allCases))
        #expect(TourCatalog.all.count == TourID.allCases.count)
        for id in TourID.allCases { #expect(TourCatalog.tour(id).id == id) }
    }

    @Test func stepTitlesAreUniqueWithinATour() {
        // They are the ⓘ menu's "Show Me" items — two with the same name would be indistinguishable.
        for tour in TourCatalog.all {
            #expect(Set(tour.steps.map(\.title)).count == tour.steps.count, "\(tour.id.rawValue)")
        }
    }

    @Test func everySurfaceHasATour() {
        #expect(Set(TourCatalog.all.map(\.surface)) == Set(TourSurface.allCases))
    }

    @Test func handOversPointAtRealOtherTours() {
        for tour in TourCatalog.all {
            if let next = tour.handsOverTo {
                #expect(next != tour.id, "\(tour.id) hands over to itself")
                #expect(TourCatalog.all.contains { $0.id == next }, "\(tour.id) hands over to a missing tour")
            }
        }
    }

    @Test func toursAreWellFormed() {
        for tour in TourCatalog.all {
            #expect(tour.version >= 1)
            #expect(Set(tour.steps.map(\.anchor)).count == tour.steps.count, "\(tour.id) uses an anchor twice")
            if case .surfaceShown(let s) = tour.trigger { #expect(s == tour.surface, "\(tour.id)") }
        }
        #expect(TourCatalog.tour(.welcome).steps.first?.anchor == "menuBar.icon")
    }
}

// MARK: - Tag fit

/// Height of `body` in the tag's body label (same font, label type and widest inner width), with at most
/// `maxLines` lines (0 = unlimited) — as `TagViews` lays it out.
@MainActor private func tagBodyHeight(_ body: String, maxLines: Int) -> CGFloat {
    let label = NSTextField(wrappingLabelWithString: body)
    label.font = TagStyle.bodyFont
    label.maximumNumberOfLines = maxLines
    label.lineBreakMode = .byWordWrapping
    let inner = TagStyle.tagMaxWidth - 2 * TagStyle.tagPaddingX
    label.preferredMaxLayoutWidth = inner
    return ceil(label.sizeThatFits(NSSize(width: inner, height: 1000)).height)
}

/// The default combo, the longest a user can bind (every modifier on a long key name), and "(not set)".
private let tagFitKeys = ["⌥Space", "⌃⌥⇧⌘Space", "⌃⌥⇧⌘F12", TourText.unboundShortcut]

/// Bodies found NOT to fit when these tests were written (2026-09-28): each wraps to a 3rd line, so the
/// tag cuts its end off. Recorded as known issues (reported to the catalog owner, not fixed here); remove
/// an entry once its copy is shortened. Keep in sync with `knownOverflows` in scripts/run-logic-tests.sh.
private let knownTagOverflows: Set<String> = []

@MainActor
@Suite struct TourTagFitTests {
    @Test func everyBodyFitsTheTagsTwoLines() {
        for tour in TourCatalog.all {
            for s in tour.steps {
                let key = "\(tour.id)/\(s.title)"
                let check = {
                    for keys in tagFitKeys {
                        let body = TourText.resolvingShortcuts(in: s.body) { _ in keys }
                        let full = tagBodyHeight(body, maxLines: 0)
                        let shown = tagBodyHeight(body, maxLines: TagStyle.bodyMaxLines)
                        #expect(full <= shown, "\(key) [\(keys)]: body needs \(full) pt, the tag shows \(shown)")
                    }
                }
                if knownTagOverflows.contains(key) {
                    withKnownIssue("catalog copy too long for the tag's two lines", isIntermittent: true) { check() }
                } else {
                    check()
                }
            }
        }
    }

    @Test func theFitCheckBites() {
        let long = Array(repeating: "Something", count: 20).joined(separator: " ")
        #expect(tagBodyHeight(long, maxLines: 0) > tagBodyHeight(long, maxLines: TagStyle.bodyMaxLines))
    }
}
#endif
