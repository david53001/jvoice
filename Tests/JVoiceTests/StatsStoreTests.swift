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
#endif
