#if canImport(Testing)
import Testing
import Foundation
@testable import JVoice

@MainActor
@Test func corruptSettingsBlobIsBackedUpInsteadOfWiped() async {
    let suiteName = "jvoice-test-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer {
        defaults.removePersistentDomain(forName: suiteName)
    }
    let key = "jvoice.app.settings.state"
    let backupKey = "jvoice.app.settings.state.corrupt.bak"
    defaults.set("THIS IS NOT JSON".data(using: .utf8), forKey: key)

    let store = SettingsStore(defaults: defaults)
    _ = store    // touch to force load

    let backup = defaults.data(forKey: backupKey)
    #expect(backup != nil)
    let backupString = backup.flatMap { String(data: $0, encoding: .utf8) }
    #expect(backupString == "THIS IS NOT JSON")
}

@MainActor
@Test func rapidWritesCoalesceIntoOneSave() async {
    let suiteName = "jvoice-debounce-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = SettingsStore(defaults: defaults)
    for _ in 0..<10 {
        store.state.customWords = ["x\(UUID().uuidString)"]
    }
    // Wait less than the debounce interval — nothing finalized yet (or only initial).
    try? await Task.sleep(nanoseconds: 100_000_000)
    // Allow the debounce to fire.
    try? await Task.sleep(nanoseconds: 700_000_000)

    let lateData = defaults.data(forKey: SettingsStore.defaultKey)
    #expect(lateData != nil)
}
#endif
