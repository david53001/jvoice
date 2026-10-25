import AppKit
import SwiftUI

/// Hidden dev mode: `JVoice --settings-smoke`.
///
/// Builds the real Settings window — the same `SettingsWindow(coordinator:)`
/// call the menus and the Dock click make — forces a layout/display pass, and exits 0. Run it
/// from an assembled `.app` bundle; that is the environment that matters.
///
/// It exists because Settings was unopenable in every shipped build between
/// 2026-06-06 and 2026-09-21 and nothing could have caught it: the failure was
/// a `Swift.fatalError` inside SwiftPM's generated `Bundle.module` accessor,
/// raised while AppKit laid out the hosting view, and it only reproduces
/// inside a packaged app. `swift test` cannot execute on this machine, and no
/// unit test renders AppKit.
///
/// Deliberately NOT `VoiceCoordinator.start()`: no global
/// hotkey registration, no login item, no model load, no orphan sweep — so it
/// is safe to run while the installed app is in use. It only reads settings.
@MainActor
enum SettingsSmokeRunner {
    static func shouldRun(arguments: [String]) -> Bool {
        arguments.contains("--settings-smoke")
    }

    static func runAndExit() -> Never {
        NSApplication.shared.setActivationPolicy(.accessory)
        APIKeyStore.useScratchDirectory()   // never reads the owner's real key

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
        // Parked behind every real window too, so the invisible window can't swallow the owner's clicks.
        window.level = UIPreviewRunner.behindLevel
        window.orderFrontRegardless()
        contentView.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.75))

        let size = contentView.frame.size
        print("settings-smoke: OK — Settings built, laid out and drawn (\(Int(size.width))×\(Int(size.height)))")

        // The menus (1.4.0, a Dock app): built exactly as at launch / on a Dock right-click, and every
        // item validated as AppKit would before showing it. A crash here would be a crash at every launch.
        let menus = AppMenus(coordinator: coordinator)
        let mainMenu = menus.makeMainMenu()
        let dockMenu = menus.makeDockMenu()
        func items(_ menu: NSMenu) -> [NSMenuItem] { menu.items.flatMap { [$0] + ($0.submenu.map(items) ?? []) } }
        for item in items(mainMenu) + items(dockMenu) where item.target === menus { _ = menus.validateMenuItem(item) }
        let keys = Set(items(mainMenu).filter { !$0.keyEquivalent.isEmpty }.map(\.keyEquivalent))
        let dockTitles = items(dockMenu).map(\.title)
        let missingKeys = [",", "q", "h", "z", "Z", "x", "c", "v", "a", "m", "w"].filter { !keys.contains($0) }
        let missingDock = ["Start Dictation", "Settings…", "Launch at Login", "Help & Tours", "Reset All Tours",
                           Updates.shared.actionTitle].filter { !dockTitles.contains($0) }
        guard missingKeys.isEmpty, missingDock.isEmpty else {
            FileHandle.standardError.write(Data("settings-smoke: FAILED — menus miss keys \(missingKeys), Dock items \(missingDock)\n".utf8))
            exit(1)
        }
        print("settings-smoke: OK — main menu (\(items(mainMenu).count) items) and Dock menu (\(items(dockMenu).count) items) built")
        exit(0)
    }
}
