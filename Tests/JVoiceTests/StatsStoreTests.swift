#if canImport(Testing)
import Testing
import Foundation
@testable import JVoice

@Test
func statsStore_recordAccumulatesWordsAndComputesWPM() {
    let suite = "jvoice.test.stats.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }

    let store = StatsStore(defaults: defaults)
    store.record(words: 10, durationSeconds: 60)
    #expect(store.totalWords == 10)
    #expect(store.averageWPM == 10)
}

@Test
func statsStore_zeroWordsIsNoOp() {
    let suite = "jvoice.test.stats.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }

    let store = StatsStore(defaults: defaults)
    store.record(words: 0, durationSeconds: 5)
    #expect(store.totalWords == 0)
    #expect(store.averageWPM == 0)
}

@Test
func statsStore_zeroDurationIsNoOp() {
    let suite = "jvoice.test.stats.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }

    let store = StatsStore(defaults: defaults)
    store.record(words: 5, durationSeconds: 0)
    #expect(store.totalWords == 0)
    #expect(store.averageWPM == 0)
}

@Test
func statsStore_averageWPMIsZeroWithNoData() {
    let suite = "jvoice.test.stats.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }

    let store = StatsStore(defaults: defaults)
    #expect(store.averageWPM == 0)
}

@Test
func statsStore_accumulatesAcrossTwoRecords() {
    let suite = "jvoice.test.stats.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }

    let store = StatsStore(defaults: defaults)
    store.record(words: 10, durationSeconds: 60)
    store.record(words: 20, durationSeconds: 60)
    // 30 words over 120 seconds → 15 WPM.
    #expect(store.totalWords == 30)
    #expect(store.averageWPM == 15)
}

@Test
func statsStore_estimatedMinutesSavedIsZeroWithNoData() {
    let suite = "jvoice.test.stats.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }

    let store = StatsStore(defaults: defaults)
    #expect(store.estimatedMinutesSaved == 0)
}

@Test
func statsStore_estimatedMinutesSavedUses40WpmBaseline() {
    let suite = "jvoice.test.stats.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }

    let store = StatsStore(defaults: defaults)
    // 40 words spoken in 6s: typing = 40/40 = 1 min; spoken = 6/60 = 0.1 min; saved = 0.9.
    store.record(words: 40, durationSeconds: 6)
    #expect(abs(store.estimatedMinutesSaved - 0.9) < 1e-9)
}

@Test
func statsStore_estimatedMinutesSavedFloorsAtZero() {
    let suite = "jvoice.test.stats.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }

    let store = StatsStore(defaults: defaults)
    // 10 words spoken in 60s: typing 0.25 min < spoken 1 min → floored at 0.
    store.record(words: 10, durationSeconds: 60)
    #expect(store.estimatedMinutesSaved == 0)
}
#endif
