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
        // Hidden dev mode: `JVoice --polish-eval <cases.json> [--model …] [--thinking off|low]` runs
        // the AI Polish eval against the real API (the user's own key) — accuracy + latency + cost.
        if PolishEvalRunner.shouldRun(arguments: CommandLine.arguments) {
            PolishEvalRunner.runAndExit(arguments: CommandLine.arguments)
        }
        // Hidden dev mode: `JVoice --settings-smoke` builds the Settings
        // window and exits — the only way to catch an AppKit/SwiftUI crash in
        // Settings on a machine that cannot execute the test suite.
        if SettingsSmokeRunner.shouldRun(arguments: CommandLine.arguments) {
            MainActor.assumeIsolated { SettingsSmokeRunner.runAndExit() }
        }
        // Hidden dev mode: `JVoice --ui-preview <dir>` screenshots Settings, Welcome and every HUD
        // state in Light and Dark — the only way to look at the UI without clicking through it.
        if UIPreviewRunner.shouldRun(arguments: CommandLine.arguments) {
            MainActor.assumeIsolated { UIPreviewRunner.runAndExit(arguments: CommandLine.arguments) }
        }
        // Guided tours are for NEW users only (BetterScreenshot spec §14.9). Decide once, for good,
        // whether this is a first launch — and do it HERE, before `JVoiceApp.main()` builds the
        // AppDelegate → VoiceCoordinator → SettingsStore, whose init writes `jvoice.app.settings.state`
        // on a fresh install (and the KeyboardShortcuts names write their defaults on first touch),
        // either of which would make a brand-new user look like an existing one. Nothing above this line
        // writes to UserDefaults; the dev modes above exit and are never classified. When in doubt the
        // answer is "existing" (e.g. a `.build/` binary with no bundle id): an existing user is never
        // asked and never gets a tour by itself.
        #if !SPARKLE_E2E_TEST   // the e2e test build starts only the updater (AppDelegate)
        MainActor.assumeIsolated {
            let micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            TourCoordinator.classifyAudienceIfNeeded(permissionGranted: micGranted || AXIsProcessTrusted())
        }
        #endif
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
        // SwiftUI requires at least one Scene. It used to be an empty `Settings` scene, but SwiftUI
        // opened that placeholder as a blank 900×450 "JVoice Settings" window on its own (e.g. when the
        // running app was launched again) — David saw it, 2026-10-17. A menu-bar extra that is never
        // inserted is a scene that can't produce any window (the real status item is MenuBarController's).
        // "Settings…" (⌘,) opens the real SettingsWindow.
        MenuBarExtra("JVoice", systemImage: "waveform", isInserted: .constant(false)) { EmptyView() }
            .commands {
                CommandGroup(replacing: .appSettings) {
                    Button("Settings…") { appDelegate.coordinator.openSettingsWindow() }
                        .keyboardShortcut(",", modifiers: .command)
                }
            }
    }
}
