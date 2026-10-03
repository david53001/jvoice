#if canImport(Testing)
import Testing
@testable import JVoice

@Test func resolveReturnsNilWhenDisabled() {
    #expect(AppModeResolver.resolve(bundleId: "com.microsoft.VSCode", userRules: [], enabled: false) == nil)
}

@Test func resolveReturnsNilForMissingOrBlankBundleId() {
    #expect(AppModeResolver.resolve(bundleId: nil, userRules: [], enabled: true) == nil)
    #expect(AppModeResolver.resolve(bundleId: "   ", userRules: [], enabled: true) == nil)
}

@Test func resolveMatchesBuiltInCodeApps() {
    #expect(AppModeResolver.resolve(bundleId: "com.microsoft.VSCode", userRules: [], enabled: true) == .code)
    #expect(AppModeResolver.resolve(bundleId: "com.apple.Terminal", userRules: [], enabled: true) == .code)
    #expect(AppModeResolver.resolve(bundleId: "com.jetbrains.pycharm", userRules: [], enabled: true) == .code)
    #expect(AppModeResolver.resolve(bundleId: "com.apple.dt.Xcode", userRules: [], enabled: true) == .code)
}

@Test func resolveReturnsNilForNonCodeApp() {
    #expect(AppModeResolver.resolve(bundleId: "com.apple.Safari", userRules: [], enabled: true) == nil)
}

@Test func userRulesTakePrecedenceOverBuiltIns() {
    // A user rule matching VS Code (case-insensitive substring) overrides the
    // built-in Code default.
    let rules = [AppModeRule(appMatch: "VSCode", mode: .veryCasual)]
    #expect(AppModeResolver.resolve(bundleId: "com.microsoft.VSCode", userRules: rules, enabled: true) == .veryCasual)
}

@Test func userRulesMatchInListOrder() {
    let rules = [AppModeRule(appMatch: "safari", mode: .formal),
                 AppModeRule(appMatch: "terminal", mode: .veryCasual)]
    // "safari" does not match "com.apple.Terminal"; "terminal" does → veryCasual,
    // ahead of the built-in Code default.
    #expect(AppModeResolver.resolve(bundleId: "com.apple.Terminal", userRules: rules, enabled: true) == .veryCasual)
}

@Test func userRuleSubstringMatchesArbitraryApp() {
    let rules = [AppModeRule(appMatch: "slack", mode: .formal)]
    #expect(AppModeResolver.resolve(bundleId: "com.tinyspeck.slackmacgap", userRules: rules, enabled: true) == .formal)
}
#endif
