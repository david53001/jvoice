import AppKit
import ApplicationServices
import AVFoundation
import SwiftUI

@main
enum JVoiceMain {
    static func main() {
        // Hidden dev/bench mode: `JVoice --bench <wav> [--model …] [--vocab …]`.
        // Lets transcription speed and vocabulary biasing be verified on this
        // machine, where XCTest cannot execute. Normal launches fall through
        // to the SwiftUI app unchanged.
        if BenchRunner.shouldRun(arguments: CommandLine.arguments) {
            BenchRunner.runAndExit(arguments: CommandLine.arguments)
        }
        // Hidden dev mode: `JVoice --math-probe "<text>"` (or piped stdin) reports what
        // the spoken-mathematics engine would do to each line — the tool the "never bleeds
        // into ordinary speech" guarantee is measured with.
        if MathProbe.shouldRun(arguments: CommandLine.arguments) {
            MathProbe.runAndExit(arguments: CommandLine.arguments)
        }
        // Hidden dev mode: `JVoice --settings-smoke` builds the Settings
        // window and exits — the only way to catch an AppKit/SwiftUI crash in
        // Settings on a machine that cannot execute the test suite.
        if SettingsSmokeRunner.shouldRun(arguments: CommandLine.arguments) {
            MainActor.assumeIsolated { SettingsSmokeRunner.runAndExit() }
        }
        // Guided tours are for NEW users only (BetterScreenshot spec §14.9). Decide once, for good,
        // whether this is a first launch — and do it HERE, before `JVoiceApp.main()` builds the
        // AppDelegate → VoiceCoordinator → SettingsStore, whose init writes `jvoice.app.settings.state`
        // on a fresh install (and the KeyboardShortcuts names write their defaults on first touch),
        // either of which would make a brand-new user look like an existing one. Nothing above this line
        // writes to UserDefaults; the dev modes above exit and are never classified. When in doubt the
        // answer is "existing" (e.g. a `.build/` binary with no bundle id): an existing user is never
        // asked and never gets a tour by itself.
        MainActor.assumeIsolated {
            let micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            TourCoordinator.classifyAudienceIfNeeded(permissionGranted: micGranted || AXIsProcessTrusted())
        }
        JVoiceApp.main()
    }
}

struct JVoiceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        // No scenes. Windows are managed imperatively by AppDelegate / SettingsWindow.
        // SwiftUI requires at least one Scene; an empty Settings scene is acceptable as a placeholder.
        // Its own "Settings…" (⌘,) menu command would open that placeholder — a blank window —
        // so the command is replaced with one that opens the real SettingsWindow.
        Settings { EmptyView() }
            .commands {
                CommandGroup(replacing: .appSettings) {
                    Button("Settings…") { appDelegate.coordinator.openSettingsWindow() }
                        .keyboardShortcut(",", modifiers: .command)
                }
            }
    }
}
