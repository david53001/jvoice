import Foundation

/// Deep-link URLs into System Settings on macOS 13+. These schemes were
/// stable across macOS 13–14; for macOS 15+ the URL format changed but the
/// fallback to System Settings root still works.
public enum SettingsURLs {
    public static let microphone = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
    public static let accessibility = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
    public static let automation = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!
    public static let bluetooth = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")!
    public static let location = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!
    public static let screenRecording = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
}
