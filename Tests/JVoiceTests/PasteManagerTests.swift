import AppKit
import Foundation

final class MockPasteActionPerformer: PasteActionPerforming {
    let result: Bool
    private(set) var callCount = 0

    init(result: Bool) {
        self.result = result
    }

    func performPaste() -> Bool {
        callCount += 1
        return result
    }

    func performPaste(targetPID: pid_t) -> Bool {
        callCount += 1
        return result
    }
}

#if canImport(Testing)
import Testing
@testable import JVoice

@Test
@MainActor
func stageWritesTextToPasteboard() {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("jvoice-test-\(UUID().uuidString)"))
    let performer = MockPasteActionPerformer(result: true)
    let manager = PasteManager(performer: performer, pasteboard: pasteboard)

    manager.stage("Hello, world!")

    #expect(manager.stagedText == "Hello, world!")
    #expect(pasteboard.string(forType: .string) == "Hello, world!")
}

@Test
@MainActor
func pasteStagesTextAndInvokesPerformer() {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("jvoice-test-\(UUID().uuidString)"))
    let performer = MockPasteActionPerformer(result: true)
    let manager = PasteManager(performer: performer, pasteboard: pasteboard)

    let outcome = manager.paste("Paste me")

    // AX-trusted in CI is unknowable; only assert performer-driven branches.
    if outcome == .ok {
        #expect(manager.stagedText == "Paste me")
        #expect(pasteboard.string(forType: .string) == "Paste me")
        #expect(performer.callCount == 1)
    } else {
        #expect(outcome == .accessibilityDenied)
    }
}

@Test
@MainActor
func pasteDoesNothingWhenThereIsNoText() {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("jvoice-test-\(UUID().uuidString)"))
    let performer = MockPasteActionPerformer(result: true)
    let manager = PasteManager(performer: performer, pasteboard: pasteboard)

    let outcome = manager.paste()

    // Either AX gate blocks (accessibilityDenied) or empty staged text -> targetRejected.
    #expect(outcome == .targetRejected || outcome == .accessibilityDenied)
    #expect(manager.stagedText.isEmpty)
    #expect(performer.callCount == 0)
}

@MainActor
@Test func failedPasteRestoresOriginalClipboard() async {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString("ORIGINAL", forType: .string)

    let failingPerformer = MockPasteActionPerformer(result: false)
    let manager = PasteManager(performer: failingPerformer)
    let outcome = manager.paste("TRANSCRIPT", targetPID: 0)
    // AX-trusted in CI is unknowable: failingPerformer gives .targetRejected,
    // AX-denied short-circuits before clipboard capture.
    #expect(outcome == .targetRejected || outcome == .accessibilityDenied)

    // Wait past the 50ms restore delay + Task scheduling slack.
    try? await Task.sleep(nanoseconds: 600_000_000)

    let restored = pasteboard.string(forType: .string)
    #expect(restored == "ORIGINAL")
}

#elseif canImport(XCTest)
import XCTest
@testable import JVoice

@MainActor
final class PasteManagerTests: XCTestCase {
    func testStageWritesTextToPasteboard() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("jvoice-test-\(UUID().uuidString)"))
        let performer = MockPasteActionPerformer(result: true)
        let manager = PasteManager(performer: performer, pasteboard: pasteboard)

        manager.stage("Hello, world!")

        XCTAssertEqual(manager.stagedText, "Hello, world!")
        XCTAssertEqual(pasteboard.string(forType: .string), "Hello, world!")
    }

    func testPasteStagesTextAndInvokesPerformer() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("jvoice-test-\(UUID().uuidString)"))
        let performer = MockPasteActionPerformer(result: true)
        let manager = PasteManager(performer: performer, pasteboard: pasteboard)

        let outcome = manager.paste("Paste me")

        if outcome == .ok {
            XCTAssertEqual(manager.stagedText, "Paste me")
            XCTAssertEqual(pasteboard.string(forType: .string), "Paste me")
            XCTAssertEqual(performer.callCount, 1)
        } else {
            XCTAssertEqual(outcome, .accessibilityDenied)
        }
    }

    func testPasteDoesNothingWhenThereIsNoText() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("jvoice-test-\(UUID().uuidString)"))
        let performer = MockPasteActionPerformer(result: true)
        let manager = PasteManager(performer: performer, pasteboard: pasteboard)

        let outcome = manager.paste()

        XCTAssertTrue(outcome == .targetRejected || outcome == .accessibilityDenied)
        XCTAssertTrue(manager.stagedText.isEmpty)
        XCTAssertEqual(performer.callCount, 0)
    }
}

#else
@testable import JVoice

@MainActor
struct PasteManagerTestsFallback {
    static func run() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("jvoice-test-\(UUID().uuidString)"))
        let performer = MockPasteActionPerformer(result: true)
        let manager = PasteManager(performer: performer, pasteboard: pasteboard)

        manager.stage("Hello, world!")
        assert(manager.stagedText == "Hello, world!")
        assert(pasteboard.string(forType: .string) == "Hello, world!")

        let outcome = manager.paste("Paste me")
        if outcome == .ok {
            assert(manager.stagedText == "Paste me")
            assert(pasteboard.string(forType: .string) == "Paste me")
            assert(performer.callCount == 1)
        } else {
            assert(outcome == .accessibilityDenied)
        }

        let emptyManager = PasteManager(performer: performer, pasteboard: pasteboard)
        let emptyOutcome = emptyManager.paste()
        assert(emptyOutcome == .targetRejected || emptyOutcome == .accessibilityDenied)
        assert(emptyManager.stagedText.isEmpty)
    }
}
#endif