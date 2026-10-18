// The tour outline following a control's own shape (the recording pill's capsule —
// `TagLayout.boxRadius`) and the Settings tour's Opacity step demo (`OpacityDemoTimeline`), both
// added 2026-09-30. This suite is the authority (CI); `scripts/run-logic-tests.sh` (the "Tours"
// section) mirrors it as the local smoke check — change both.
#if canImport(Testing)
import AppKit
import Testing
@testable import JVoice

@Suite struct TourOutlineShapeTests {
    @Test func defaultRadiusWithoutADeclaredShape() {
        #expect(TagLayout.boxRadius(box: CGRect(x: 0, y: 0, width: 200, height: 30), anchorRadius: nil)
                == TagStyle.boxRadius)
    }

    @Test func capsulePillGetsAConcentricCapsuleBox() {
        let pill = CGRect(x: 600, y: 64, width: 240, height: 56)
        let box = pill.insetBy(dx: -TagStyle.boxPadding, dy: -TagStyle.boxPadding)
        #expect(TagLayout.boxRadius(box: box, anchorRadius: 28) == box.height / 2)
        #expect(TagLayout.boxRadius(box: box, anchorRadius: .infinity) == box.height / 2)
    }

    @Test func leaderMeetsTheCapsuleOnItsStraightEdge() throws {
        let pill = CGRect(x: 600, y: 64, width: 240, height: 56)
        let p = TagLayout.place(anchor: pill, tagSize: CGSize(width: 240, height: 90),
                                visible: CGRect(x: 0, y: 0, width: 1440, height: 875),
                                order: TagLayout.order(verticalFirst: true), anchorRadius: 28)
        let leader = try #require(p.leader)
        let r = p.box.height / 2
        #expect(leader.to.x >= p.box.minX + r && leader.to.x <= p.box.maxX - r)
    }
}

@Suite struct OpacityTourDemoTests {
    private typealias T = OpacityDemoTimeline

    @Test func settingsTourHasTheOpacityStep() {
        #expect(TourCatalog.settings.steps.contains { $0.anchor == T.anchor })
    }

    @Test func downToTransparentUpToOpaqueBackToYours() {
        #expect(T.frame(at: 0, from: 0.5).value == 0.5)
        #expect(T.frame(at: 2.0, from: 0.5) == .init(value: 0, readout: "Watch: 0 % Transparent"))
        #expect(T.frame(at: 5.6, from: 0.5) == .init(value: 1, readout: "Watch: 100 % Opaque"))
        #expect(T.frame(at: T.loopDuration - 0.1, from: 0.3) == .init(value: 0.3, readout: "Yours: 30 %"))
        #expect(T.frame(at: 1, from: 0.5).readout.hasSuffix("↓"))
        #expect(T.frame(at: 4, from: 0.5).readout.hasSuffix("↑"))
    }

    @Test func staysInRangeAndLoops() {
        for i in 0...Int(T.loopDuration * 20) {
            let v = T.frame(at: Double(i) * 0.05, from: 0.62).value
            #expect(v >= 0 && v <= 1)
        }
        let once = T.frame(at: 1.3, from: 0.5), again = T.frame(at: 1.3 + T.loopDuration, from: 0.5)
        #expect(abs(once.value - again.value) < 1e-9 && once.readout == again.readout)
    }
}
#endif
