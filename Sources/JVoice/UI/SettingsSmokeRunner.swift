import AppKit
import SwiftUI

/// Hidden dev mode: `JVoice --settings-smoke`.
///
/// Builds the real Settings window — the same `SettingsWindow(coordinator:)`
/// call the menu bar makes — forces a layout/display pass, and exits 0. Run it
/// from an assembled `.app` bundle; that is the environment that matters.
///
/// It exists because Settings was unopenable in every shipped build between
/// 2026-06-06 and 2026-09-21 and nothing could have caught it: the failure was
/// a `Swift.fatalError` inside SwiftPM's generated `Bundle.module` accessor,
/// raised while AppKit laid out the hosting view, and it only reproduces
/// inside a packaged app. `swift test` cannot execute on this machine, and no
/// unit test renders AppKit.
///
/// Deliberately NOT `VoiceCoordinator.start()`: no status item, no global
/// hotkey registration, no login item, no model load, no orphan sweep — so it
/// is safe to run while the installed app is in use. It only reads settings.
@MainActor
enum SettingsSmokeRunner {
    static func shouldRun(arguments: [String]) -> Bool {
        arguments.contains("--settings-smoke")
    }

    static func runAndExit() -> Never {
        NSApplication.shared.setActivationPolicy(.accessory)

        let coordinator = VoiceCoordinator()
        let window = SettingsWindow(coordinator: coordinator)

        guard let contentView = window.contentView else {
            FileHandle.standardError.write(Data("settings-smoke: FAILED — window has no content view\n".utf8))
            exit(1)
        }

        // The window must really be on screen: SwiftUI only reaches
        // `makeNSView` on the representables (where the crash lived) during a
        // genuine display pass. `alphaValue = 0` keeps it invisible while the
        // window server still drives that pass — the same trick
        // `HUDWindow.prewarm()` uses.
        window.alphaValue = 0
        window.orderFrontRegardless()
        contentView.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.75))

        let size = contentView.frame.size
        print("settings-smoke: OK — Settings built, laid out and drawn (\(Int(size.width))×\(Int(size.height)))")
        exit(0)
    }
}
