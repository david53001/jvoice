#if canImport(Testing)
import Testing
import Foundation
@testable import JVoice

private func makeStore() -> (TranscriptHistoryStore, UserDefaults, String) {
    let suite = "jvoice.test.transcriptHistory.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    return (TranscriptHistoryStore(defaults: defaults), defaults, suite)
}

@Test
func transcriptHistory_addPrependsNewestFirst() {
    let (store, defaults, suite) = makeStore()
    defer { defaults.removePersistentDomain(forName: suite) }

    store.add("first")
    store.add("second")
    let entries = store.entries
    #expect(entries.count == 2)
    #expect(entries.first?.text == "second")
    #expect(entries.last?.text == "first")
}

@Test
func transcriptHistory_capsAtThirtyDroppingOldest() {
    let (store, defaults, suite) = makeStore()
    defer { defaults.removePersistentDomain(forName: suite) }

    for i in 1...35 {
        store.add("entry \(i)")
    }
    let entries = store.entries
    #expect(entries.count == TranscriptHistoryStore.maxEntries)
    // Newest first; oldest five ("entry 1"..."entry 5") were dropped.
    #expect(entries.first?.text == "entry 35")
    #expect(entries.last?.text == "entry 6")
}

@Test
func transcriptHistory_blankTextIgnored() {
    let (store, defaults, suite) = makeStore()
    defer { defaults.removePersistentDomain(forName: suite) }

    store.add("   \n  ")
    #expect(store.entries.isEmpty)
}

@Test
func transcriptHistory_addTrimsWhitespace() {
    let (store, defaults, suite) = makeStore()
    defer { defaults.removePersistentDomain(forName: suite) }

    store.add("  hello world  ")
    #expect(store.entries.first?.text == "hello world")
}

@Test
func transcriptHistory_removeByIdRemovesOnlyThatEntry() {
    let (store, defaults, suite) = makeStore()
    defer { defaults.removePersistentDomain(forName: suite) }

    store.add("a")
    store.add("b")
    store.add("c")
    let middle = store.entries[1] // "b"
    store.remove(id: middle.id)
    let texts = store.entries.map(\.text)
    #expect(texts == ["c", "a"])
}

@Test
func transcriptHistory_clearEmptiesList() {
    let (store, defaults, suite) = makeStore()
    defer { defaults.removePersistentDomain(forName: suite) }

    store.add("a")
    store.add("b")
    store.clear()
    #expect(store.entries.isEmpty)
}

@Test
func transcriptHistory_persistsAcrossInstances() {
    let suite = "jvoice.test.transcriptHistory.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }

    let store = TranscriptHistoryStore(defaults: defaults)
    store.add("remembered")
    let reopened = TranscriptHistoryStore(defaults: defaults)
    #expect(reopened.entries.first?.text == "remembered")
}

@Test
func transcriptHistory_corruptBlobDecodesToEmpty() {
    let suite = "jvoice.test.transcriptHistory.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }

    defaults.set(Data([0x00, 0x01, 0x02]), forKey: "jvoice.app.transcriptHistory")
    let store = TranscriptHistoryStore(defaults: defaults)
    #expect(store.entries.isEmpty)
}
#endif
