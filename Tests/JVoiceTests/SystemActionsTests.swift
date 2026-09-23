#if canImport(Testing)
import Testing
import Foundation
@testable import JVoice

/// `SettingsStore` loads while `AppDelegate` builds the coordinator, BEFORE
/// `applicationDidFinishLaunching` installs `SystemActions.errorHandler` — a
/// warning reported then must be held and delivered once the handler exists.
@MainActor
@Test func errorsReportedBeforeTheHandlerExistsAreDeliveredWhenItIsInstalled() {
    let previous = SystemActions.errorHandler
    SystemActions.errorHandler = nil
    defer { SystemActions.errorHandler = previous }

    SystemActions.report("queued warning")
    var received: [String] = []
    SystemActions.errorHandler = { received.append($0) }
    #expect(received.contains("queued warning"))

    SystemActions.report("live warning")
    #expect(received.last == "live warning")
}

/// The downgrade case: settings written by a newer JVoice are refused and reset;
/// that warning must reach a handler installed after the store loaded.
@MainActor
@Test func settingsResetWarningReachesAHandlerInstalledAfterLoad() {
    let previous = SystemActions.errorHandler
    SystemActions.errorHandler = nil
    defer { SystemActions.errorHandler = previous }

    let suiteName = "jvoice-test-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    defaults.set(#"{"schemaVersion":999}"#.data(using: .utf8), forKey: "k")
    _ = SettingsStore(defaults: defaults, key: "k", corruptBackupKey: "bak")

    var received: [String] = []
    SystemActions.errorHandler = { received.append($0) }
    #expect(received.contains { $0.hasPrefix("Settings file was unreadable") })
}
#endif
