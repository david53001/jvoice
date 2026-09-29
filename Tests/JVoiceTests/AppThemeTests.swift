#if canImport(Testing)
import Testing
import Foundation
@testable import JVoice

@Test func appThemeToggleAlternates() {
    #expect(AppTheme.dark.toggled == .light)
    #expect(AppTheme.light.toggled == .dark)
    #expect(AppTheme.system.toggled == .dark)
}

@Test func appThemeUnknownDecodesToSystem() throws {
    let json = "\"sepia\"".data(using: .utf8)!
    let decoded = try JSONDecoder().decode(AppTheme.self, from: json)
    #expect(decoded == .system)
}

@Test func appThemeRoundTrips() throws {
    for theme in AppTheme.allCases {
        let data = try JSONEncoder().encode(theme)
        let back = try JSONDecoder().decode(AppTheme.self, from: data)
        #expect(back == theme)
    }
}
#endif
