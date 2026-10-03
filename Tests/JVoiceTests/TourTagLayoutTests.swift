// Where the tour tag goes (Sources/JVoice/Tours/Kit/TagLayout.swift), its key handling (TagKeys.swift)
// and its strings (TagStyle.swift), ported from BetterScreenshot's TourKit TagLayoutTests. TagStyle's
// colour/dim tests and TagContrastTests are left out while the tag colours are being restyled.
// This suite is the authority (CI); `scripts/run-logic-tests.sh` (the "Tours" section) mirrors it as
// the local smoke check — change both.
#if canImport(Testing)
import AppKit
import Testing
@testable import JVoice

private let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)   // visible frame (menu bar excluded)
private let tagSize = CGSize(width: 240, height: 90)
private let margin = TagStyle.screenMargin
private let gap = TagStyle.leaderLength

private func inside(_ r: CGRect, _ area: CGRect) -> Bool {
    r.minX >= area.minX - 0.001 && r.maxX <= area.maxX + 0.001 && r.minY >= area.minY - 0.001 && r.maxY <= area.maxY + 0.001
}

private func onEdge(_ p: CGPoint, of r: CGRect) -> Bool {
    let onX = abs(p.x - r.minX) < 0.001 || abs(p.x - r.maxX) < 0.001
    let onY = abs(p.y - r.minY) < 0.001 || abs(p.y - r.maxY) < 0.001
    let withinX = p.x >= r.minX - 0.001 && p.x <= r.maxX + 0.001
    let withinY = p.y >= r.minY - 0.001 && p.y <= r.maxY + 0.001
    return (onX && withinY) || (onY && withinX)
}

@Suite struct TourTagLayoutTests {
    @Test func boxIsTheAnchorGrownByThePaddingAndOuterByTheStroke() {
        let anchor = CGRect(x: 600, y: 400, width: 50, height: 20)
        let p = TagLayout.place(anchor: anchor, tagSize: tagSize, visible: screen)
        #expect(p.box == anchor.insetBy(dx: -TagStyle.boxPadding, dy: -TagStyle.boxPadding))
        #expect(p.outer == p.box.insetBy(dx: -TagStyle.boxStroke, dy: -TagStyle.boxStroke))
    }

    @Test func prefersLeftLikeTheMock() {
        let p = TagLayout.place(anchor: CGRect(x: 800, y: 400, width: 100, height: 30), tagSize: tagSize, visible: screen)
        #expect(p.side == .left)
        #expect(p.tag.maxX == p.outer.minX - gap)
        #expect(p.tag.midY == p.box.midY)
        #expect(p.tag.size == tagSize)
        #expect(p.leader?.from == CGPoint(x: p.tag.maxX, y: p.box.midY))
        #expect(p.leader?.to == CGPoint(x: p.outer.minX, y: p.box.midY))
    }

    @Test func rightWhenNoRoomOnTheLeft() {
        let p = TagLayout.place(anchor: CGRect(x: 60, y: 400, width: 100, height: 30), tagSize: tagSize, visible: screen)
        #expect(p.side == .right)
        #expect(p.tag.minX == p.outer.maxX + gap)
        #expect(p.leader?.from.x == p.tag.minX)
        #expect(p.leader?.to.x == p.outer.maxX)
    }

    /// The Welcome tour's first step points at the menu-bar J.
    @Test func menuBarIconGetsTheTagBelowIt() {
        let p = TagLayout.place(anchor: CGRect(x: 1200, y: 878, width: 22, height: 22), tagSize: tagSize, visible: screen)
        #expect(p.side == .below)
        #expect(p.tag.maxY == p.outer.minY - gap)
        #expect(inside(p.tag, screen.insetBy(dx: margin, dy: margin)))
        #expect(p.leader?.to == CGPoint(x: p.box.midX, y: p.outer.minY))
    }

    @Test func menuBarIconAtTheRightEdgeSlidesTheTagLeftButStaysUnderIt() {
        let p = TagLayout.place(anchor: CGRect(x: 1410, y: 878, width: 22, height: 22), tagSize: tagSize, visible: screen)
        #expect(p.side == .below)
        #expect(p.tag.maxX == screen.maxX - margin)
        #expect(p.tag.maxX > p.box.minX)
        #expect(p.leader!.from.x <= p.tag.maxX - TagStyle.tagRadius)
    }

    @Test func verticalFirstPutsTheTagBelowAControlInABar() {
        let p = TagLayout.place(anchor: CGRect(x: 600, y: 700, width: 28, height: 28), tagSize: tagSize, visible: screen,
                                order: TagLayout.order(verticalFirst: true))
        #expect(p.side == .below)
        #expect(p.tag.midX == p.box.midX)
    }

    @Test func aboveWhenNothingFitsBesideOrBelow() {
        let p = TagLayout.place(anchor: CGRect(x: 20, y: 20, width: 1400, height: 40), tagSize: tagSize, visible: screen)
        #expect(p.side == .above)
        #expect(p.tag.minY == p.outer.maxY + gap)
    }

    @Test func slidesDownFromTheTopEdgeButKeepsTouchingTheBox() {
        let p = TagLayout.place(anchor: CGRect(x: 800, y: 850, width: 100, height: 20), tagSize: tagSize, visible: screen)
        #expect(p.side == .left)
        #expect(p.tag.maxY == screen.maxY - margin)
        #expect(p.tag.minY < p.box.maxY && p.tag.maxY > p.box.minY)
        #expect(p.leader!.from.y <= p.tag.maxY - TagStyle.tagRadius)
    }

    @Test func overTheControlWhenNoSideHasRoom() {
        let p = TagLayout.place(anchor: screen.insetBy(dx: 4, dy: 4), tagSize: tagSize, visible: screen)
        #expect(p.side == .over)
        #expect(p.leader == nil)
        #expect(inside(p.tag, screen.insetBy(dx: margin, dy: margin)))
    }

    @Test func secondScreenUsesItsOwnVisibleFrame() {
        let second = CGRect(x: 1440, y: -200, width: 1920, height: 1055)
        let p = TagLayout.place(anchor: CGRect(x: 1460, y: 300, width: 40, height: 40), tagSize: tagSize, visible: second)
        #expect(p.side == .right)
        #expect(inside(p.tag, second.insetBy(dx: margin, dy: margin)))
    }

    @Test func neverOffTheVisibleFrameAndLeaderJoinsTagToBox() {
        let area = screen.insetBy(dx: margin, dy: margin)
        var sides = Set<String>()
        var bad: [String] = []
        for vertical in [false, true] {
            for x in stride(from: CGFloat(0), through: 1400, by: 70) {
                for y in stride(from: CGFloat(0), through: 860, by: 43) {
                    for size in [CGSize(width: 24, height: 24), CGSize(width: 320, height: 36), CGSize(width: 60, height: 400)] {
                        let anchor = CGRect(origin: CGPoint(x: x, y: y), size: size)
                        let p = TagLayout.place(anchor: anchor, tagSize: tagSize, visible: screen,
                                                order: TagLayout.order(verticalFirst: vertical))
                        sides.insert(p.side.rawValue)
                        if !inside(p.tag, area) { bad.append("tag \(p.tag) off screen for \(anchor)") }
                        if let l = p.leader {
                            if !onEdge(l.from, of: p.tag) { bad.append("leader \(l.from) not on tag \(p.tag)") }
                            if !onEdge(l.to, of: p.outer) { bad.append("leader \(l.to) not on box \(p.outer)") }
                            if p.tag.intersects(p.outer) { bad.append("tag \(p.tag) covers box \(p.outer)") }
                        }
                    }
                }
            }
        }
        #expect(bad.isEmpty, "\(bad.prefix(3))")
        #expect(sides == ["left", "right", "below", "above"])
    }

    @Test func smallPanelHostGetsTheTagOutsideTheWholePanel() {
        let strip = CGRect(x: 400, y: 30, width: 640, height: 120)
        let mic = CGRect(x: 700, y: 60, width: 80, height: 22)
        let p = TagLayout.place(anchor: mic, tagSize: tagSize, visible: screen,
                                order: TagLayout.order(verticalFirst: true), keepOut: strip)
        #expect(p.side == .above)
        #expect(p.tag.minY == strip.maxY + gap)
        #expect(!p.tag.intersects(strip))
        #expect(p.leader?.from.y == p.tag.minY)
        #expect(p.leader?.to.y == p.outer.maxY)
    }

    @Test func keepOutIsDroppedWhenNothingFitsOutsideIt() {
        let p = TagLayout.place(anchor: CGRect(x: 700, y: 400, width: 80, height: 22), tagSize: tagSize,
                                visible: screen, keepOut: screen)
        #expect(p.side == .left)
        #expect(p.tag.maxX == p.outer.minX - gap)
    }

    @Test func menuBarBoxIsClippedToTheScreen() {
        let full = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let icon = CGRect(x: 1200, y: 875, width: 34, height: 25)
        let p = TagLayout.place(anchor: icon, tagSize: tagSize, visible: screen, screen: full)
        #expect(p.outer.maxY == full.maxY)
        #expect(p.box.minY == icon.minY - TagStyle.boxPadding)
        #expect(p.side == .below)
    }

    @Test func barsPreferVerticalAndClampHandlesEmptyRanges() {
        #expect(TagLayout.prefersVertical(containerSize: CGSize(width: 600, height: 40)))
        #expect(TagLayout.prefersVertical(containerSize: CGSize(width: 90, height: 30)))
        #expect(!TagLayout.prefersVertical(containerSize: CGSize(width: 300, height: 400)))
        #expect(!TagLayout.prefersVertical(containerSize: CGSize(width: 80, height: 30)))
        #expect(!TagLayout.prefersVertical(containerSize: .zero))
        #expect(TagLayout.clamp(5, 10, 20) == 10)
        #expect(TagLayout.clamp(25, 10, 20) == 20)
        #expect(TagLayout.clamp(5, 20, 10) == 15)
    }

    // MARK: A step's own placement

    @Test func aStepsSideWinsWhenItFits() {
        let anchor = CGRect(x: 800, y: 400, width: 100, height: 30)
        for (preferred, side) in [(TourStep.Placement.right, TagLayout.Side.right), (.above, .above), (.below, .below), (.left, .left)] {
            let p = TagLayout.place(anchor: anchor, tagSize: tagSize, visible: screen, preferred: preferred)
            #expect(p.side == side, "\(preferred)")
            #expect(p.leader != nil)
        }
        #expect(TagLayout.place(anchor: CGRect(x: 1300, y: 400, width: 100, height: 30), tagSize: tagSize, visible: screen,
                                preferred: .right).side == .left)
    }

    @Test func aStepsSideStillKeepsOffASmallPanel() {
        let strip = CGRect(x: 400, y: 300, width: 640, height: 120)
        let p = TagLayout.place(anchor: CGRect(x: 700, y: 330, width: 80, height: 22), tagSize: tagSize, visible: screen,
                                keepOut: strip, preferred: .below)
        #expect(p.side == .below)
        #expect(p.tag.maxY == strip.minY - gap)
    }

    @Test func insideCornerPutsTheTagInTheControlsTopRightCorner() {
        let canvas = CGRect(x: 200, y: 150, width: 800, height: 600)
        let p = TagLayout.place(anchor: canvas, tagSize: tagSize, visible: screen, preferred: .insideCorner)
        #expect(p.side == .insideCorner)
        #expect(p.leader == nil)
        #expect(p.tag.maxX == canvas.maxX - TagStyle.insideCornerInset)
        #expect(p.tag.maxY == canvas.maxY - TagStyle.insideCornerInset)
        #expect(p.box == canvas.insetBy(dx: -TagStyle.boxPadding, dy: -TagStyle.boxPadding))
        #expect(TagLayout.place(anchor: CGRect(x: 800, y: 400, width: 200, height: 60), tagSize: tagSize, visible: screen,
                                preferred: .insideCorner).side == .left)
    }

    @Test func insideCornerUsesTheVisiblePartOfTheControl() {
        let window = CGRect(x: 200, y: 100, width: 960, height: 700)
        let cards = CGRect(x: 224, y: 300, width: 912, height: 900)
        let p = TagLayout.place(anchor: cards, tagSize: tagSize, visible: screen, preferred: .insideCorner, host: window)
        #expect(p.side == .insideCorner)
        #expect(p.tag.maxY == window.maxY - TagStyle.insideCornerInset)
        #expect(p.tag.maxX == cards.maxX - TagStyle.insideCornerInset)
    }

    // MARK: Big controls, title bar, host

    @Test func aBigControlSpansMostOfItsWindowBothWays() {
        let window = CGRect(x: 0, y: 0, width: 1000, height: 800)
        #expect(TagLayout.isBig(anchor: CGRect(x: 0, y: 0, width: 700, height: 600), host: window))
        #expect(!TagLayout.isBig(anchor: CGRect(x: 0, y: 0, width: 260, height: 700), host: window))
        #expect(!TagLayout.isBig(anchor: CGRect(x: 0, y: 0, width: 1000, height: 150), host: window))
        let settings = CGRect(x: 255, y: 76, width: 960, height: 847)
        #expect(TagLayout.isBig(anchor: CGRect(x: 273, y: 167, width: 923, height: 652), host: settings))
        #expect(!TagLayout.isBig(anchor: CGRect(x: 273, y: 76, width: 924, height: 458), host: settings))
        #expect(!TagLayout.isBig(anchor: CGRect(x: 900, y: 0, width: 700, height: 800), host: window))
    }

    @Test func aBigControlsTagGoesInsideItsCornerWhenItsWindowFillsTheScreen() {
        let window = CGRect(x: 154, y: 84, width: 1132, height: 708)
        let canvas = CGRect(x: 154, y: 120, width: 852, height: 620)
        let p = TagLayout.place(anchor: canvas, tagSize: tagSize, visible: screen, host: window)
        #expect(p.side == .insideCorner)
        #expect(canvas.contains(p.tag))
        #expect(p.tag.maxX == canvas.maxX - TagStyle.insideCornerInset)
        #expect(p.leader == nil)
        #expect(TagLayout.place(anchor: canvas, tagSize: tagSize, visible: screen, preferred: .above, host: window).side == .above)
        let small = TagLayout.place(anchor: CGRect(x: 1040, y: 500, width: 220, height: 60), tagSize: tagSize, visible: screen, host: window)
        #expect(small.side == .left)
        #expect(small.tag.maxX == small.outer.minX - gap)
    }

    @Test func aBigControlsTagGoesBesideTheWholeWindowWhenThereIsRoom() {
        let window = CGRect(x: 370, y: 190, width: 700, height: 500)
        let grid = CGRect(x: 370, y: 240, width: 700, height: 400)
        let p = TagLayout.place(anchor: grid, tagSize: tagSize, visible: screen, host: window)
        #expect(p.side == .left)
        #expect(p.tag.maxX == min(window.minX, p.outer.minX) - gap)
        #expect(!p.tag.intersects(window))
    }

    @Test func titleBarControlsGetTheTagBelow() {
        let content = CGRect(x: 100, y: 100, width: 800, height: 600)
        #expect(TagLayout.isInTitleBar(anchor: CGRect(x: 860, y: 704, width: 26, height: 22), contentLayout: content))
        #expect(!TagLayout.isInTitleBar(anchor: CGRect(x: 860, y: 660, width: 26, height: 22), contentLayout: content))
        #expect(TagLayout.place(anchor: CGRect(x: 860, y: 704, width: 26, height: 22), tagSize: tagSize, visible: screen,
                                order: TagLayout.order(verticalFirst: true)).side == .below)
    }

    @Test func aTagSlidesToStayWithinItsWindow() {
        let window = CGRect(x: 100, y: 84, width: 1000, height: 708)
        let info = CGRect(x: 1068, y: 766, width: 26, height: 22)
        let p = TagLayout.place(anchor: info, tagSize: tagSize, visible: screen, order: TagLayout.order(verticalFirst: true), host: window)
        #expect(p.side == .below)
        #expect(p.tag.maxX == window.maxX)
        #expect(p.leader?.from.x == p.leader?.to.x)
        let free = TagLayout.place(anchor: info, tagSize: tagSize, visible: screen, order: TagLayout.order(verticalFirst: true))
        #expect(free.tag.midX == free.box.midX)
    }

    // MARK: Leader routing

    @Test func theLeaderSlidesIntoAGapBetweenControls() {
        let box = CGRect(x: 400, y: 100, width: 260, height: 30)
        let row = [CGRect(x: 380, y: 170, width: 140, height: 28), CGRect(x: 540, y: 170, width: 140, height: 28)]
        let (from, to) = TagLayout.leader(side: .above, tag: CGRect(x: 400, y: 250, width: 240, height: 90), box: box,
                                          outer: box.insetBy(dx: -2, dy: -2), obstacles: row)
        #expect(from.x == to.x)
        #expect(from.x > 520 && from.x < 540)
        let line = CGRect(x: from.x - 1, y: to.y, width: 2, height: from.y - to.y)
        #expect(!row.contains { $0.intersects(line) })
    }

    @Test func theLeaderKeepsTheMiddleWhenNothingIsInTheWayOrACrossingIsUnavoidable() {
        let box = CGRect(x: 400, y: 100, width: 260, height: 30)
        let tag = CGRect(x: 410, y: 250, width: 240, height: 90)
        let outer = box.insetBy(dx: -2, dy: -2)
        #expect(TagLayout.leader(side: .above, tag: tag, box: box, outer: outer,
                                 obstacles: [CGRect(x: 900, y: 170, width: 50, height: 28)]).0.x == box.midX)
        #expect(TagLayout.leader(side: .above, tag: tag, box: box, outer: outer,
                                 obstacles: [CGRect(x: 300, y: 170, width: 500, height: 28)]).0.x == box.midX)
    }

    @Test func aSideLeaderAvoidsALabelToo() {
        let box = CGRect(x: 600, y: 300, width: 100, height: 120)
        let label = CGRect(x: 560, y: 350, width: 30, height: 20)
        let (from, to) = TagLayout.leader(side: .left, tag: CGRect(x: 300, y: 310, width: 240, height: 100), box: box,
                                          outer: box.insetBy(dx: -2, dy: -2), obstacles: [label])
        #expect(from.y == to.y)
        #expect(!label.intersects(CGRect(x: from.x, y: from.y - 1, width: to.x - from.x, height: 2)))
    }

    @Test func neverOffScreenWithAHostAndPlacements() {
        let area = screen.insetBy(dx: margin, dy: margin)
        let window = CGRect(x: 154, y: 84, width: 1132, height: 708)
        var bad: [String] = []
        for preferred in [TourStep.Placement.automatic, .left, .right, .above, .below, .insideCorner] {
            for x in stride(from: CGFloat(154), through: 1200, by: 90) {
                for y in stride(from: CGFloat(84), through: 700, by: 60) {
                    for size in [CGSize(width: 24, height: 24), CGSize(width: 600, height: 500), CGSize(width: 60, height: 400)] {
                        let anchor = CGRect(origin: CGPoint(x: x, y: y), size: size)
                        let p = TagLayout.place(anchor: anchor, tagSize: tagSize, visible: screen, preferred: preferred, host: window)
                        if !inside(p.tag, area) { bad.append("tag \(p.tag) off screen for \(anchor) \(preferred)") }
                        if p.side == .insideCorner, !anchor.contains(p.tag) { bad.append("inside-corner tag \(p.tag) not inside \(anchor)") }
                        if let l = p.leader, p.tag.intersects(p.outer) || !onEdge(l.to, of: p.outer) { bad.append("bad leader for \(anchor) \(preferred)") }
                    }
                }
            }
        }
        #expect(bad.isEmpty, "\(bad.prefix(3))")
    }

    @Test func aSideTagSlidesOffALabelItWouldCover() {
        let wide = CGRect(x: 0, y: 0, width: 1470, height: 900)
        let keysCell = CGRect(x: 650, y: 420, width: 70, height: 26)
        let size = CGSize(width: 260, height: 96)
        let centred = TagLayout.place(anchor: keysCell, tagSize: size, visible: wide)
        let text = CGRect(x: 380, y: centred.tag.maxY - 20, width: 440, height: 40)
        let p = TagLayout.place(anchor: keysCell, tagSize: size, visible: wide, obstacles: [text])
        #expect(p.side == .left)
        #expect(!p.tag.intersects(text))
        #expect(p.tag.minY < p.box.maxY && p.tag.maxY > p.box.minY)
        #expect(TagLayout.place(anchor: keysCell, tagSize: size, visible: wide,
                                obstacles: [CGRect(x: 900, y: 100, width: 50, height: 20)]).tag == centred.tag)
    }
}

@Suite struct TourTagKeysTests {
    @Test func returnAndEnterAreNextOnExplainSteps() {
        for code in [TagKeys.returnKey, TagKeys.keypadEnter] {
            #expect(TagKeys.action(keyCode: code, modifiers: [], isRepeat: false, isExplainStep: true, isEditingText: false) == .next)
            #expect(TagKeys.action(keyCode: code, modifiers: [], isRepeat: false, isExplainStep: false, isEditingText: false) == nil)
        }
    }

    @Test func escapeSkipsTheTourUnlessTheHostClaimsIt() {
        for explain in [true, false] {
            #expect(TagKeys.action(keyCode: TagKeys.escape, modifiers: [], isRepeat: false, isExplainStep: explain, isEditingText: false) == .skipTour)
        }
        #expect(TagKeys.action(keyCode: TagKeys.escape, modifiers: [], isRepeat: false, isExplainStep: true,
                               isEditingText: false, hostClaimsEscape: true) == nil)
        #expect(TagKeys.action(keyCode: TagKeys.returnKey, modifiers: [], isRepeat: false, isExplainStep: true,
                               isEditingText: false, hostClaimsEscape: true) == .next)
    }

    /// Settings while the shortcut recorder listens: Esc cancels it, Return is just a key press.
    @Test func aControlRecordingKeysGetsReturnAndEscape() {
        for code in [TagKeys.returnKey, TagKeys.keypadEnter, TagKeys.escape] {
            #expect(TagKeys.action(keyCode: code, modifiers: [], isRepeat: false, isExplainStep: true,
                                   isEditingText: false, hostClaimsKeys: true) == nil)
        }
    }

    @Test func typingModifiersRepeatsAndOtherKeysPassThrough() {
        #expect(TagKeys.action(keyCode: TagKeys.returnKey, modifiers: [], isRepeat: false, isExplainStep: true, isEditingText: true) == nil)
        #expect(TagKeys.action(keyCode: TagKeys.escape, modifiers: [], isRepeat: false, isExplainStep: true, isEditingText: true) == nil)
        for mods: NSEvent.ModifierFlags in [.command, .option, .control, .shift] {
            #expect(TagKeys.action(keyCode: TagKeys.returnKey, modifiers: mods, isRepeat: false, isExplainStep: true, isEditingText: false) == nil)
        }
        #expect(TagKeys.action(keyCode: TagKeys.returnKey, modifiers: [], isRepeat: true, isExplainStep: true, isEditingText: false) == nil)
        #expect(TagKeys.action(keyCode: 0, modifiers: [], isRepeat: false, isExplainStep: true, isEditingText: false) == nil)
        #expect(TagKeys.action(keyCode: TagKeys.keypadEnter, modifiers: [.capsLock, .numericPad], isRepeat: false,
                               isExplainStep: true, isEditingText: false) == .next)
    }
}

@Suite struct TourTagStyleTests {
    @Test func footerStrings() {
        #expect(TagStyle.counter(2, of: 7) == "2 of 7")
        #expect(TagStyle.nextButtonTitle(number: 2, total: 7) == "Next")
        #expect(TagStyle.nextButtonTitle(number: 7, total: 7) == "Done")
        #expect(TagStyle.skipStepTitle == "Skip Step")
        #expect(TagStyle.skipTourTitle == "Skip Tour")
    }

    @Test func skipTourIsLeftOutOnlyNextToTheLastStepsDone() {
        #expect(TagStyle.showsSkipTour(number: 2, total: 7, isExplain: true))
        #expect(!TagStyle.showsSkipTour(number: 7, total: 7, isExplain: true))
        #expect(TagStyle.showsSkipTour(number: 3, total: 3, isExplain: false))
    }

    @Test func voiceOverReadsTitleBodyAndPosition() {
        #expect(TagStyle.announcement(title: "Your stats", body: "Words dictated.", number: 2, total: 9)
                == "Your stats. Words dictated. Step 2 of 9.")
    }
}
#endif
