#if canImport(Testing)
import Testing
@testable import JVoice

// MARK: - Custom Words: a rejected word says why

@Test func acceptedCustomWordsHaveNoRejection() {
    #expect(SettingsEntryPolicy.customWordRejection("VS Code", existing: ["JVoice"]) == nil)
    #expect(SettingsEntryPolicy.customWordRejection(String(repeating: "a", count: 60), existing: []) == nil)
}

@Test func customWordRejectionsMirrorTheCoordinatorsGuards() {
    #expect(SettingsEntryPolicy.customWordRejection(String(repeating: "a", count: 61), existing: [])?.hasPrefix("Too long") == true)
    #expect(SettingsEntryPolicy.customWordRejection("!!!", existing: [])?.contains("letter or number") == true)
    #expect(SettingsEntryPolicy.customWordRejection("vs code", existing: ["VS Code"]) == "“VS Code” is already in your list.")
}

@Test @MainActor func everyWordTheCoordinatorRejectsGetsAReason() {
    // Pins the mirror: whatever `addCustomWord` turns away must have a reason
    // to show, and whatever it accepts must not.
    let coordinator = VoiceCoordinator()
    let saved = coordinator.customWords
    defer { coordinator.customWords = saved }
    coordinator.customWords = ["VS Code"]
    for word in ["vs code", "!!!", String(repeating: "x", count: 61), "Li-Fraumeni"] {
        let reason = SettingsEntryPolicy.customWordRejection(word, existing: coordinator.customWords)
        let added = coordinator.addCustomWord(word)
        #expect((added == nil) == (reason != nil), "\(word)")
    }
}

// MARK: - App Modes: an app name becomes the bundle ID rules match

private let slack = SettingsEntryPolicy.InstalledApp(name: "Slack", bundleID: "com.tinyspeck.slackmacgap")
private let chrome = SettingsEntryPolicy.InstalledApp(name: "Google Chrome", bundleID: "com.google.Chrome")
private let vscode = SettingsEntryPolicy.InstalledApp(name: "Visual Studio Code", bundleID: "com.microsoft.VSCode")
private let xcode = SettingsEntryPolicy.InstalledApp(name: "Xcode", bundleID: "com.apple.dt.Xcode")
private let memos = SettingsEntryPolicy.InstalledApp(name: "VoiceMemos", bundleID: "com.apple.VoiceMemos")
private let drawio = SettingsEntryPolicy.InstalledApp(name: "draw.io", bundleID: "com.jgraph.drawio.desktop")
private let installed = [slack, chrome, vscode, xcode, memos, drawio, chrome]

private func target(_ typed: String) -> SettingsEntryPolicy.AppRuleTarget {
    SettingsEntryPolicy.appRuleTarget(for: typed, installed: installed)
}

@Test func appNamesResolveToBundleIDs() {
    #expect(target("slack") == .app(slack))
    #expect(target("Google Chrome") == .app(chrome))
    #expect(target("voice memos") == .app(memos))   // spaces don't matter
    #expect(target("Slack.app") == .app(slack))     // a trailing .app is ignored
}

@Test func aUniquePartialNameResolves() {
    #expect(target("chrome") == .app(chrome))
}

@Test func severalMatchesAreReportedNotGuessed() {
    #expect(target("code") == .ambiguous(["Visual Studio Code", "Xcode"]))
    #expect(SettingsEntryPolicy.appRuleNotice(for: target("code"), typed: "code")?.contains("Visual Studio Code, Xcode") == true)
}

@Test func typedBundleIDsAreKeptVerbatim() {
    #expect(target("com.tinyspeck.slackmacgap") == .bundleID("com.tinyspeck.slackmacgap"))
    #expect(target("com.jetbrains.") == .bundleID("com.jetbrains."))
    #expect(target("draw.io") == .app(drawio))      // an exact app name beats bundle-ID shape
}

@Test func anAppThatIsNotInstalledIsReportedInsteadOfAddedAsADeadRule() {
    #expect(target("Photoshop") == .notFound)
    #expect(target("   ") == .notFound)
    #expect(SettingsEntryPolicy.appRuleNotice(for: .notFound, typed: "Photoshop")?.contains("“Photoshop”") == true)
    #expect(SettingsEntryPolicy.appRuleNotice(for: .app(slack), typed: "slack") == nil)
}

@Test func looksLikeBundleID() {
    #expect(SettingsEntryPolicy.looksLikeBundleID("com.google.Chrome"))
    #expect(SettingsEntryPolicy.looksLikeBundleID("com.jetbrains."))
    #expect(!SettingsEntryPolicy.looksLikeBundleID("Google Chrome"))
    #expect(!SettingsEntryPolicy.looksLikeBundleID("Notes.app"))
    #expect(!SettingsEntryPolicy.looksLikeBundleID("slack"))
}

@Test func aResolvedRuleMatchesWhereTheTypedNameNeverDid() {
    let byName = [AppModeRule(appMatch: "Google Chrome", mode: .formal)]
    let byBundleID = [AppModeRule(appMatch: chrome.bundleID, mode: .formal)]
    #expect(AppModeResolver.resolve(bundleId: chrome.bundleID, userRules: byName, enabled: true) == nil)
    #expect(AppModeResolver.resolve(bundleId: chrome.bundleID, userRules: byBundleID, enabled: true) == .formal)
}

@Test func aRealInstalledAppResolves() {
    // /System/Applications/System Settings.app ships with every macOS 13+.
    let resolved = SettingsEntryPolicy.appRuleTarget(for: "system settings", installed: SettingsEntryPolicy.installedApps())
    #expect(resolved == .app(.init(name: "System Settings", bundleID: "com.apple.systempreferences")))
}
#endif
