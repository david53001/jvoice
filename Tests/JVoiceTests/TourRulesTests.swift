// The guided tour's "may this start by itself?" rules + shortcut placeholders
// (Sources/JVoice/Tours/Kit/TourRules.swift), ported from BetterScreenshot's TourKit tests.
// This suite is the authority (CI); `scripts/run-logic-tests.sh` (the "Tours" section) mirrors it as
// the local smoke check — change both.
#if canImport(Testing)
import AppKit
import Testing
@testable import JVoice

private let settingsV1 = Tour(id: .settings, surface: .settings, trigger: .surfaceShown(.settings), steps: [])
private let settingsV2 = Tour(id: .settings, version: 2, surface: .settings, trigger: .surfaceShown(.settings), steps: [])

@Suite struct TourRulesTests {
    @Test func autoStartNeedsToursOnAndUnseen() {
        #expect(TourRules.shouldAutoStart(settingsV1, firstUseToursEnabled: true, seen: [:]))
        #expect(!TourRules.shouldAutoStart(settingsV1, firstUseToursEnabled: false, seen: [:]))
        #expect(!TourRules.shouldAutoStart(settingsV1, firstUseToursEnabled: true, seen: ["settings": 1]))
    }

    /// Existing users never opted in (the preference is absent): nothing may start by itself.
    @Test func autoStartIsOffWhenThePreferenceIsAbsentOrFalse() {
        #expect(!TourRules.shouldAutoStart(settingsV1, firstUseToursEnabled: nil, seen: [:]))
        for tour in TourCatalog.all {
            #expect(!TourRules.shouldAutoStart(tour, firstUseToursEnabled: nil, seen: [:]), "\(tour.id)")
            #expect(!TourRules.shouldAutoStart(tour, firstUseToursEnabled: false, seen: [:]), "\(tour.id)")
        }
    }

    @Test func versionBumpReoffersOnlyWhenToursOn() {
        #expect(TourRules.shouldAutoStart(settingsV2, firstUseToursEnabled: true, seen: ["settings": 1]))
        #expect(!TourRules.shouldAutoStart(settingsV2, firstUseToursEnabled: true, seen: ["settings": 2]))
        #expect(!TourRules.shouldAutoStart(settingsV2, firstUseToursEnabled: nil, seen: ["settings": 1]))
        #expect(!TourRules.shouldAutoStart(settingsV2, firstUseToursEnabled: false, seen: ["settings": 1]))
    }

    @Test func seenIsPerTourId() {
        #expect(!TourRules.isSeen(settingsV1, seen: ["welcome": 5]))
        #expect(TourRules.isSeen(settingsV1, seen: ["settings": 3]))
    }

    @Test func questionOnlyForUnansweredNewUsers() {
        #expect(TourRules.shouldAskQuestion(audience: .new, answered: false))
        #expect(!TourRules.shouldAskQuestion(audience: .new, answered: true))
        #expect(!TourRules.shouldAskQuestion(audience: .existing, answered: false))
        #expect(!TourRules.shouldAskQuestion(audience: .existing, answered: true))
        #expect(!TourRules.shouldAskQuestion(audience: nil, answered: false))
    }

    @Test func welcomeOpensAtLaunchOnlyForUnansweredNewUsersWithPermission() {
        #expect(TourRules.shouldOpenWelcomeOnLaunch(audience: .new, answered: false, permissionGranted: true))
        #expect(!TourRules.shouldOpenWelcomeOnLaunch(audience: .new, answered: false, permissionGranted: false))
        #expect(!TourRules.shouldOpenWelcomeOnLaunch(audience: .new, answered: true, permissionGranted: true))
        #expect(!TourRules.shouldOpenWelcomeOnLaunch(audience: .existing, answered: false, permissionGranted: true))
    }

    @Test func toursTriggeredBy() {
        let catalog = TourCatalog.all
        #expect(TourRules.tours(triggeredBy: .surfaceShown(.settings), in: catalog).map(\.id) == [.settings])
        #expect(TourRules.tours(triggeredBy: .surfaceShown(.recordingPill), in: catalog).map(\.id) == [.recordingPill])
        #expect(TourRules.tours(triggeredBy: .surfaceShown(.welcome), in: catalog).map(\.id) == [])
        #expect(TourRules.tours(triggeredBy: .startedByApp, in: catalog).map(\.id) == [.welcome])
        #expect(TourRules.tours(triggeredBy: .event(.action(TourEventName.dictationPasted)), in: catalog).map(\.id) == [])
    }

    @Test func shortcutPlaceholdersResolveFromLookup() {
        let keys = ["toggleRecording": "⌥Space", "undoLastPaste": "⌃⌥Z"]
        #expect(TourText.resolvingShortcuts(in: "Press {shortcut:toggleRecording} to talk.") { keys[$0] } == "Press ⌥Space to talk.")
        #expect(TourText.resolvingShortcuts(in: "{shortcut:toggleRecording} or {shortcut:undoLastPaste}") { keys[$0] } == "⌥Space or ⌃⌥Z")
        #expect(TourText.resolvingShortcuts(in: "No placeholders.") { keys[$0] } == "No placeholders.")
    }

    @Test func unknownOrBrokenPlaceholdersAreLeftAlone() {
        let keys = ["toggleRecording": "⌥Space"]
        #expect(TourText.resolvingShortcuts(in: "Press {shortcut:nope}.") { keys[$0] } == "Press {shortcut:nope}.")
        #expect(TourText.resolvingShortcuts(in: "Press {shortcut:toggleRecording") { keys[$0] } == "Press {shortcut:toggleRecording")
    }

    @Test func shortcutNamesListsPlaceholders() {
        #expect(TourText.shortcutNames(in: "a {shortcut:toggleRecording} b {shortcut:undoLastPaste}") == ["toggleRecording", "undoLastPaste"])
        #expect(TourText.shortcutNames(in: "none") == [])
    }

    @Test func menuTitlesAreTitleCaseToursWithRealSymbols() {
        for id in TourID.allCases {
            let words = id.menuTitle.split(separator: " ")
            #expect(words.last.map(String.init) == "Tour", "\(id)")
            #expect(words.allSatisfy { $0 == "&" || $0.first?.isUppercase == true }, "\(id.menuTitle) not Title Case")
            #expect(NSImage(systemSymbolName: id.menuSymbol, accessibilityDescription: nil) != nil, "\(id.menuSymbol)")
        }
    }

    @Test func resetSaysHowToSeeToursWhenTheyAreOff() {
        #expect(TourRules.resetConfirmation(firstUseToursEnabled: true) == "Tours reset")
        for off in [false, nil] as [Bool?] {
            #expect(TourRules.resetConfirmation(firstUseToursEnabled: off) == "Tours reset — turn on Tours & tips to see them again")
        }
    }
}
#endif
