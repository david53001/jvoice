import AppKit
import ApplicationServices
import AVFoundation

@main
enum JVoiceMain {
    static func main() {
        // Hidden dev/bench mode: `JVoice --bench <wav> [--model …] [--vocab …]`.
        // Lets transcription speed and vocabulary biasing be verified on this
        // machine, where XCTest cannot execute. Normal launches fall through
        // to the app unchanged.
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
        // whether this is a first launch — and do it HERE, before the app builds the
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
        // A plain AppKit app (since 1.4.0, when JVoice became a Dock app): no SwiftUI `App`, so no SwiftUI
        // scene can open a window of its own (it opened a blank "JVoice Settings" window in 2026-10) and
        // the main menu is entirely JVoice's (`AppMenus`). SwiftUI is still used inside the windows.
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            let delegate = AppDelegate()
            app.delegate = delegate   // weak: `withExtendedLifetime` keeps it for the app's whole life
            withExtendedLifetime(delegate) { app.run() }
        }
    }
}
