import AppKit
import Foundation

public enum PermissionError: Error, Equatable, Sendable {
    case microphoneDenied
    case accessibilityDenied
    case automationDenied(target: String)
    case bluetoothDenied
    case locationDenied
    case screenRecordingDenied

    public var userMessage: String {
        switch self {
        case .microphoneDenied:
            return "Microphone access denied. Grant access in System Settings → Privacy & Security → Microphone."
        case .accessibilityDenied:
            return "Accessibility access required for paste. Grant access in System Settings → Privacy & Security → Accessibility."
        case .automationDenied(let target):
            return "Automation access to \(target) denied. Grant access in System Settings → Privacy & Security → Automation."
        case .bluetoothDenied:
            return "Bluetooth access denied. Grant access in System Settings → Privacy & Security → Bluetooth."
        case .locationDenied:
            return "Location access denied. Wi-Fi network listing requires Location services in System Settings → Privacy & Security → Location Services."
        case .screenRecordingDenied:
            return "Screen recording access denied. Grant access in System Settings → Privacy & Security → Screen & System Audio Recording."
        }
    }

    public var deepLink: URL {
        switch self {
        case .microphoneDenied:     return SettingsURLs.microphone
        case .accessibilityDenied:  return SettingsURLs.accessibility
        case .automationDenied:     return SettingsURLs.automation
        case .bluetoothDenied:      return SettingsURLs.bluetooth
        case .locationDenied:       return SettingsURLs.location
        case .screenRecordingDenied: return SettingsURLs.screenRecording
        }
    }

    @MainActor
    public func surface() {
        SystemActions.errorHandler?(userMessage)
    }

    @MainActor
    public func surfaceAndOpenSettings() {
        surface()
        NSWorkspace.shared.open(deepLink)
    }
}
