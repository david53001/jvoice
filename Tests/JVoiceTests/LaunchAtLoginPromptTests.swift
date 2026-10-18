#if canImport(Testing)
import CoreGraphics
import Foundation
import Testing
@testable import JVoice

/// The one-time "Open JVoice at login?" decision (`LaunchAtLoginPrompt`). Mirrored locally by the
/// "Launch-at-login prompt" section of `scripts/run-logic-tests.sh` (this suite only runs in CI).
@Suite struct LaunchAtLoginPromptTests {
    /// In-memory storage, so a test run never writes a preferences file.
    final class MemoryStore: LaunchAtLoginPromptStorage {
        var values: [String: Any] = [:]
        func integer(forKey key: String) -> Int { values[key] as? Int ?? 0 }
        func bool(forKey key: String) -> Bool { values[key] as? Bool ?? false }
        func double(forKey key: String) -> Double { values[key] as? Double ?? 0 }
        func set(_ value: Int, forKey key: String) { values[key] = value }
        func set(_ value: Bool, forKey key: String) { values[key] = value }
        func set(_ value: Double, forKey key: String) { values[key] = value }
    }

    typealias Prompt = LaunchAtLoginPrompt

    /// A moment that is calm in every respect; each test spoils one field.
    let calm = Prompt.Moment(secondsSinceUse: 10, secondsSinceKeyPress: 10, mouseButtonDown: false,
                             dictationActive: false, appIsActive: false, menuIsOpen: false,
                             tourShowing: false, fullScreenInFront: false)
    let t0 = Date(timeIntervalSince1970: 2_000_000_000)

    func duePrompt(_ store: MemoryStore = MemoryStore()) -> Prompt {
        let prompt = Prompt(storage: store)
        for _ in 1...5 { prompt.recordUse() }
        return prompt
    }

    func showing(seconds: Int, visible: (Int) -> Bool = { _ in true },
                 secondsSinceInput: (Int) -> TimeInterval) -> Prompt.Showing {
        var s = Prompt.Showing()
        for second in 1...seconds {
            s.tick(seconds: 1, cardVisible: visible(second), secondsSinceInput: secondsSinceInput(second))
        }
        return s
    }

    var seenShowing: Prompt.Showing { showing(seconds: 25, secondsSinceInput: { _ in 0.3 }) }

    // MARK: The decision

    @Test func asksOnlyFromTheFifthUse() {
        #expect(Prompt.usesBeforeAsking == 5)
        for uses in 0..<5 {
            #expect(!Prompt.shouldAsk(uses: uses, asked: false, legacyAutoEnabled: false, enabled: false))
        }
        #expect(Prompt.shouldAsk(uses: 5, asked: false, legacyAutoEnabled: false, enabled: false))
        #expect(Prompt.shouldAsk(uses: 6, asked: false, legacyAutoEnabled: false, enabled: false))
    }

    @Test func neverAsksWhenAlreadyEnabled() {
        #expect(!Prompt.shouldAsk(uses: 5, asked: false, legacyAutoEnabled: false, enabled: true))
    }

    @Test func neverAsksTwice() {
        #expect(!Prompt.shouldAsk(uses: 5, asked: true, legacyAutoEnabled: false, enabled: false))
    }

    @Test func neverAsksUsersOfTheOldAutoEnable() {
        // ≤ 1.1.4 turned it on at first launch: still on (nothing to do) or turned off on purpose.
        #expect(!Prompt.shouldAsk(uses: 5, asked: false, legacyAutoEnabled: true, enabled: false))
        #expect(!Prompt.shouldAsk(uses: 5, asked: false, legacyAutoEnabled: true, enabled: true))
    }

    // MARK: Counting, persisted

    @Test func fiveRecordedUsesMakeItDueAndTheCounterStops() {
        let prompt = Prompt(storage: MemoryStore())
        for _ in 1...4 {
            #expect(prompt.recordUse())
            #expect(!prompt.couldAsk)
        }
        #expect(prompt.recordUse())
        #expect(prompt.uses == 5)
        #expect(prompt.couldAsk)
        #expect(prompt.shouldAsk(enabled: false))
        #expect(!prompt.shouldAsk(enabled: true))
        #expect(!prompt.recordUse())
        #expect(prompt.uses == 5)
    }

    @Test func keysAreTheDocumentedOnes() {
        let store = MemoryStore()
        let prompt = Prompt(storage: store)
        prompt.recordUse()
        prompt.cardHidUnanswered(seenShowing, now: t0)
        prompt.markAsked()
        #expect(store.values["jvoice.app.launchAtLoginPrompt.uses"] as? Int == 1)
        #expect(store.values["jvoice.app.launchAtLoginPrompt.unansweredShowings"] as? Int == 1)
        #expect(store.values["jvoice.app.launchAtLoginPrompt.lastShownAt"] as? Double == t0.timeIntervalSince1970)
        #expect(store.values["jvoice.app.launchAtLoginPrompt.asked"] as? Bool == true)
        #expect(Prompt.Key.legacyAutoEnabled == "jvoice.app.launchAtLogin.didInitialize")
    }

    @Test func askedIsForGood() {
        let store = MemoryStore()
        let prompt = duePrompt(store)
        prompt.markAsked()
        #expect(!prompt.couldAsk)
        #expect(!prompt.recordUse())
        #expect(!Prompt(storage: store).couldAsk)
    }

    @Test func legacyFlagStopsCountingAndAsking() {
        let store = MemoryStore()
        store.set(true, forKey: Prompt.Key.legacyAutoEnabled)
        let prompt = Prompt(storage: store)
        for _ in 1...6 { #expect(!prompt.recordUse()) }
        #expect(prompt.uses == 0)
        #expect(!prompt.couldAsk)
    }

    @Test func aChoiceWithTheMenuItemBeforeTheFifthUseMeansNeverAsked() {
        let prompt = Prompt(storage: MemoryStore())
        prompt.recordUse()
        prompt.markAsked()   // what LaunchAtLoginManager.setEnabled does
        for _ in 1...5 { prompt.recordUse() }
        #expect(!prompt.couldAsk)
    }

    // MARK: Calm moment

    @Test func calmMomentNeedsEveryCondition() {
        #expect(Prompt.isCalmMoment(calm))
        var m = calm; m.secondsSinceUse = 1
        #expect(!Prompt.isCalmMoment(m))
        m = calm; m.secondsSinceKeyPress = 0.5
        #expect(!Prompt.isCalmMoment(m))
        m = calm; m.mouseButtonDown = true
        #expect(!Prompt.isCalmMoment(m))
        m = calm; m.dictationActive = true
        #expect(!Prompt.isCalmMoment(m))
        m = calm; m.appIsActive = true
        #expect(!Prompt.isCalmMoment(m))
        m = calm; m.menuIsOpen = true
        #expect(!Prompt.isCalmMoment(m))
        m = calm; m.tourShowing = true
        #expect(!Prompt.isCalmMoment(m))
        m = calm; m.fullScreenInFront = true
        #expect(!Prompt.isCalmMoment(m))
        m = calm; m.secondsSinceUse = Prompt.settleSeconds; m.secondsSinceKeyPress = Prompt.typingQuietSeconds
        #expect(Prompt.isCalmMoment(m))
    }

    @Test func fullScreenInFrontMeansTheFrontmostAppCoversAWholeScreen() {
        typealias W = Prompt.WindowInfo
        let screens = [CGRect(x: 0, y: 0, width: 1512, height: 982), CGRect(x: -200, y: 982, width: 1920, height: 1080)]
        let front: Int32 = 42
        let full = W(ownerPID: front, layer: 0, bounds: CGRect(x: 0, y: 0, width: 1512, height: 982))
        #expect(Prompt.fullScreenInFront(frontmostPID: front, windows: [full], screenFrames: screens))
        #expect(Prompt.fullScreenInFront(frontmostPID: front, windows: [W(ownerPID: front, layer: 0, bounds: CGRect(x: -200, y: -1080, width: 1920, height: 1080))], screenFrames: screens))
        #expect(Prompt.fullScreenInFront(frontmostPID: front, windows: [W(ownerPID: front, layer: 25, bounds: full.bounds)], screenFrames: screens))
        #expect(!Prompt.fullScreenInFront(frontmostPID: front, windows: [W(ownerPID: front, layer: 0, bounds: CGRect(x: 0, y: 33, width: 1512, height: 949))], screenFrames: screens))
        #expect(!Prompt.fullScreenInFront(frontmostPID: front, windows: [W(ownerPID: front, layer: -2147483603, bounds: full.bounds)], screenFrames: screens))
        #expect(!Prompt.fullScreenInFront(frontmostPID: 7, windows: [full], screenFrames: screens))
        #expect(!Prompt.fullScreenInFront(frontmostPID: nil, windows: [full], screenFrames: screens))
        #expect(!Prompt.fullScreenInFront(frontmostPID: front, windows: [full], screenFrames: []))
    }

    // MARK: The flow

    @Test func afterUseRecordsTheUseAndStartsWaitingOnlyWhenDueAndHidden() {
        let prompt = Prompt(storage: MemoryStore())
        var statusReads = 0
        let off = { () -> Bool in statusReads += 1; return false }
        for _ in 1...4 {
            #expect(prompt.afterUse(cardVisible: false, shownThisLaunch: false, isEnabled: off) == .nothing)
        }
        #expect(prompt.afterUse(cardVisible: true, shownThisLaunch: false, isEnabled: off) == .nothing)
        #expect(prompt.uses == 5)
        #expect(statusReads == 0)
        #expect(prompt.afterUse(cardVisible: false, shownThisLaunch: false, isEnabled: off) == .startWaiting)
        #expect(statusReads == 1)
        #expect(!prompt.asked)
    }

    @Test func alreadyEnabledMarksItAskedSoLaterUsesSkipTheStatusCall() {
        let prompt = duePrompt()
        #expect(prompt.afterUse(cardVisible: false, shownThisLaunch: false, isEnabled: { true }) == .alreadyEnabled)
        #expect(prompt.asked)
        var statusReads = 0
        #expect(prompt.afterUse(cardVisible: false, shownThisLaunch: false,
                                isEnabled: { statusReads += 1; return true }) == .nothing)
        #expect(statusReads == 0)
    }

    @Test func waitStepWaitsForCalmThenShowsAndGivesUpAfterTwoMinutes() {
        let prompt = duePrompt()
        var busy = calm; busy.secondsSinceKeyPress = 0
        var statusReads = 0
        #expect(prompt.waitStep(busy, isEnabled: { statusReads += 1; return false }) == .keepWaiting)
        #expect(statusReads == 0)
        #expect(prompt.waitStep(calm, isEnabled: { false }) == .show)
        #expect(!prompt.asked)
        var late = calm; late.secondsSinceUse = Prompt.giveUpSeconds
        #expect(prompt.waitStep(late, isEnabled: { false }) == .giveUp)
    }

    @Test func waitStepRechecksBeforeShowing() {
        let answered = duePrompt()
        answered.markAsked()
        #expect(answered.waitStep(calm, isEnabled: { false }) == .noLongerDue)
        let turnedOn = duePrompt()
        #expect(turnedOn.waitStep(calm, isEnabled: { true }) == .alreadyEnabled)
        #expect(turnedOn.asked)
    }

    // MARK: An unanswered card

    @Test func anUnansweredCardHidesAfterItsTimeButNotUnderThePointer() {
        #expect(!Prompt.shouldHideUnanswered(secondsShown: Prompt.unansweredHideSeconds - 1, pointerOnCard: false))
        #expect(Prompt.shouldHideUnanswered(secondsShown: Prompt.unansweredHideSeconds, pointerOnCard: false))
        #expect(!Prompt.shouldHideUnanswered(secondsShown: 600, pointerOnCard: true))
    }

    @Test func aShowingCountsOnlyIfTheUserCouldHaveSeenIt() {
        #expect(seenShowing.counts)
        #expect(!showing(seconds: 25, visible: { _ in false }, secondsSinceInput: { _ in 0.3 }).counts)
        #expect(!showing(seconds: 25, secondsSinceInput: { 60 + TimeInterval($0) }).counts)
        #expect(!showing(seconds: 25, secondsSinceInput: { $0 >= 22 ? 0.5 : 60 + TimeInterval($0) }).counts)
        #expect(showing(seconds: 25, secondsSinceInput: { $0 >= 20 ? 0.5 : 60 + TimeInterval($0) }).counts)
        var s = Prompt.Showing()
        s.tick(seconds: 3600, cardVisible: true, secondsSinceInput: 0.2)
        #expect(s.secondsSeen == Prompt.Showing.maxSecondsPerTick)
        #expect(!s.counts)
    }

    @Test func anUnseenShowingOnlyDelaysTheNextOne() {
        let prompt = duePrompt()
        let unseen = showing(seconds: 25, visible: { _ in false }, secondsSinceInput: { _ in 0.3 })
        #expect(!prompt.cardHidUnanswered(unseen, now: t0))
        #expect(prompt.unansweredShowings == 0)
        #expect(prompt.afterUse(cardVisible: false, shownThisLaunch: false, unseenShowingEndedAt: t0,
                                now: t0.addingTimeInterval(60), isEnabled: { false }) == .tooSoon)
        #expect(prompt.afterUse(cardVisible: false, shownThisLaunch: false, unseenShowingEndedAt: t0,
                                now: t0.addingTimeInterval(Prompt.reshowAfterUnseenSeconds), isEnabled: { false }) == .startWaiting)
    }

    @Test func aSeenShowingComesBackADayLaterOrAfterARelaunch() {
        let store = MemoryStore()
        let prompt = duePrompt(store)
        #expect(prompt.cardHidUnanswered(seenShowing, now: t0))
        for minutes: TimeInterval in [1, 3, 60, 23 * 60] {
            #expect(prompt.afterUse(cardVisible: false, shownThisLaunch: true,
                                    now: t0.addingTimeInterval(minutes * 60), isEnabled: { false }) == .tooSoon)
        }
        #expect(prompt.afterUse(cardVisible: false, shownThisLaunch: true,
                                now: t0.addingTimeInterval(Prompt.reshowAfterSeconds), isEnabled: { false }) == .startWaiting)
        #expect(Prompt(storage: store).afterUse(cardVisible: false, shownThisLaunch: false,
                                                now: t0.addingTimeInterval(60), isEnabled: { false }) == .startWaiting)
    }

    @Test func anIgnoredCardCountsAsNoAfterItsThirdSeenShowing() {
        let store = MemoryStore()
        let prompt = duePrompt(store)
        #expect(Prompt.maxShowings == 3)
        prompt.cardHidUnanswered(seenShowing, now: t0)
        prompt.cardHidUnanswered(seenShowing, now: t0.addingTimeInterval(Prompt.reshowAfterSeconds))
        #expect(prompt.couldAsk)
        prompt.cardHidUnanswered(seenShowing, now: t0.addingTimeInterval(2 * Prompt.reshowAfterSeconds))
        #expect(!prompt.couldAsk)
        #expect(prompt.asked)
        #expect(!Prompt(storage: store).couldAsk)
    }

    // MARK: The card's colours

    @Test func cardTextKeepsWCAGContrastOverTheWorstDesktop() {
        for dark in [false, true] {
            #expect(LaunchAtLoginCardColors.worstContrast(dark: dark) >= LaunchAtLoginCardColors.minimumContrast)
            for fill in LaunchAtLoginCardColors.secondaryButtonFills {   // resting, hovered, pressed
                #expect(LaunchAtLoginCardColors.worstContrast(dark: dark, buttonFill: fill)
                        >= LaunchAtLoginCardColors.minimumContrast)
            }
        }
        #expect(LaunchAtLoginCardColors.secondaryButtonFills
                == [Design.smallButtonFill, Design.smallButtonHoverFill, Design.smallButtonPressedFill])
        #expect(LaunchAtLoginCardColors.tintAlpha < 1)
    }
}
#endif
