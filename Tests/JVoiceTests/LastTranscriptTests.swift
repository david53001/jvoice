#if canImport(Testing)
import Testing
@testable import JVoice

@Test
func lastTranscriptStorePersistsTranscript() {
    let suite = "jvoice.test.lastTranscript.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let store = LastTranscriptStore(defaults: defaults)
    store.transcript = "hello world"
    let store2 = LastTranscriptStore(defaults: defaults)
    #expect(store2.transcript == "hello world")
    defaults.removePersistentDomain(forName: suite)
}

@Test
func lastTranscriptStoreDefaultsToEmpty() {
    let suite = "jvoice.test.lastTranscript.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let store = LastTranscriptStore(defaults: defaults)
    #expect(store.transcript == "")
    defaults.removePersistentDomain(forName: suite)
}

@Test
func extractCorrections_sameWordCount_caseChange() {
    let result = TextProcessor.extractCorrections(from: "python is great", corrected: "Python is great")
    #expect(result.count == 1 && result.contains("Python"))
}

@Test
func extractCorrections_differentWordCount_merge() {
    let result = TextProcessor.extractCorrections(from: "mine craft is cool", corrected: "Minecraft is cool")
    #expect(result.contains("Minecraft"))
}

@Test
func extractCorrections_noChange_returnsEmpty() {
    let result = TextProcessor.extractCorrections(from: "hello world", corrected: "hello world")
    #expect(result.isEmpty)
}

@Test
func extractCorrections_multipleChanges() {
    let result = TextProcessor.extractCorrections(from: "use react every day", corrected: "use React every day")
    #expect(result.contains("React"))
}

#elseif canImport(XCTest)
import XCTest
@testable import JVoice

final class LastTranscriptTests: XCTestCase {
    func testPersistsTranscript() {
        let suite = "jvoice.test.lastTranscript.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = LastTranscriptStore(defaults: defaults)
        store.transcript = "hello world"
        let store2 = LastTranscriptStore(defaults: defaults)
        XCTAssertEqual(store2.transcript, "hello world")
        defaults.removePersistentDomain(forName: suite)
    }

    func testDefaultsToEmpty() {
        let suite = "jvoice.test.lastTranscript.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = LastTranscriptStore(defaults: defaults)
        XCTAssertEqual(store.transcript, "")
        defaults.removePersistentDomain(forName: suite)
    }

    func testExtractCorrections_sameWordCount_caseChange() {
        let result = TextProcessor.extractCorrections(from: "python is great", corrected: "Python is great")
        XCTAssertTrue(result.count == 1 && result.contains("Python"))
    }

    func testExtractCorrections_differentWordCount_merge() {
        let result = TextProcessor.extractCorrections(from: "mine craft is cool", corrected: "Minecraft is cool")
        XCTAssertTrue(result.contains("Minecraft"))
    }

    func testExtractCorrections_noChange_returnsEmpty() {
        let result = TextProcessor.extractCorrections(from: "hello world", corrected: "hello world")
        XCTAssertTrue(result.isEmpty)
    }

    func testExtractCorrections_multipleChanges() {
        let result = TextProcessor.extractCorrections(from: "use react every day", corrected: "use React every day")
        XCTAssertTrue(result.contains("React"))
    }
}

#else
import Foundation
@testable import JVoice

enum LastTranscriptTestsFallback {
    static func run() {
        let suite = "jvoice.test.lastTranscript.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = LastTranscriptStore(defaults: defaults)
        store.transcript = "hello"
        assert(LastTranscriptStore(defaults: defaults).transcript == "hello")
        defaults.removePersistentDomain(forName: suite)
    }
}
#endif
