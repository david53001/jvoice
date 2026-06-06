#if canImport(Testing)
import Testing
@testable import JVoice

@Test func permissionErrorMessageMentionsSystemSettings() {
    let err = PermissionError.microphoneDenied
    #expect(err.userMessage.contains("System Settings"))
    #expect(err.deepLink.absoluteString.contains("x-apple.systempreferences"))
}

@Test func permissionErrorCoversKnownTypes() {
    let cases: [PermissionError] = [
        .microphoneDenied,
        .accessibilityDenied,
        .automationDenied(target: "Music"),
        .bluetoothDenied,
        .locationDenied,
        .screenRecordingDenied,
    ]
    for c in cases {
        #expect(!c.userMessage.isEmpty)
    }
}
#endif
