import AppKit
import SwiftUI

/// Hidden dev mode: `JVoice --ui-preview <dir>`.
///
/// Opens the real Settings window (Light and Dark), the Welcome window (both pages) and the HUD pill
/// in every state (plus a tour tag over Settings), one at a time, and saves a screenshot of the screen
/// under each window — desktop included, so the translucency shows — to `<dir>` with
/// `screencapture -R`: the only way to look at the UI without clicking through the app (`ImageRenderer` / `CALayer.render` come back blank, see `UI/CLAUDE.md`). The capture needs Screen
/// Recording permission for the terminal that runs it; without it macOS saves only the wallpaper.
///
/// Like `--settings-smoke` it never calls `VoiceCoordinator.start()` and never writes a setting:
/// appearances are forced on the windows directly, not through `appTheme`. Run it from an assembled
/// `.app` (recipe in `UI/CLAUDE.md`). The windows really appear on screen for about a second each.
@MainActor
enum UIPreviewRunner {
    static func shouldRun(arguments: [String]) -> Bool {
        arguments.contains("--ui-preview")
    }

    static func runAndExit(arguments: [String]) -> Never {
        guard let flag = arguments.firstIndex(of: "--ui-preview"), arguments.indices.contains(flag + 1) else {
            FileHandle.standardError.write(Data("usage: JVoice --ui-preview <output-dir>\n".utf8))
            exit(2)
        }
        let dir = URL(fileURLWithPath: arguments[flag + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSApplication.shared.setActivationPolicy(.accessory)
        let coordinator = VoiceCoordinator()
        var saved = 0

        func capture(_ window: NSWindow, _ name: String, after delay: TimeInterval = 0.8) {
            window.displayIfNeeded()
            capture(window.frame, name, after: delay)
        }

        func capture(_ frame: NSRect, _ name: String, after delay: TimeInterval = 0.8) {
            RunLoop.main.run(until: Date().addingTimeInterval(delay))
            let out = dir.appendingPathComponent("\(name).png").path
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            // The screen region under the window, not `-l <window>`: a single-window capture has no
            // backdrop, so materials and Liquid Glass would come out flat black.
            let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
            let r = frame.insetBy(dx: -12, dy: -12)
            let region = "\(Int(r.minX)),\(Int(primaryHeight - r.maxY)),\(Int(r.width)),\(Int(r.height))"
            task.arguments = ["-x", "-R", region, out]
            try? task.run()
            task.waitUntilExit()
            if task.terminationStatus == 0 { saved += 1; print("ui-preview: \(out)") }
        }

        let appearances: [(String, NSAppearance.Name)] = [("light", .aqua), ("dark", .darkAqua)]

        for (label, name) in appearances {
            let settings = SettingsWindow(coordinator: coordinator)
            settings.appearance = NSAppearance(named: name)
            settings.orderFrontRegardless()
            capture(settings, "settings-\(label)")
            // A tour tag on the model card (the Settings tour's second step).
            if let anchor = settings.view(forTourAnchor: "settings.model"),
               let step = TourCatalog.settings.steps.first(where: { $0.anchor == "settings.model" }) {
                let tag = TagOverlayController()
                tag.show(step: step, body: step.body, number: 2, total: TourCatalog.settings.steps.count,
                         anchor: anchor, host: settings)
                capture(settings.frame.union(tag.tagPanel.frame), "tour-tag-\(label)")
                tag.hide()
            }
            settings.orderOut(nil)

            let welcome = WelcomeWindow(coordinator: coordinator)
            welcome.appearance = NSAppearance(named: name)
            welcome.show(page: .permissions, askTourQuestion: true)
            capture(welcome, "welcome-permissions-\(label)")
            welcome.show(page: .allSet)
            capture(welcome, "welcome-allset-\(label)")
            welcome.orderOut(nil)
        }

        let hud = HUDWindow()
        hud.onStop = {}   // show the stop button
        let states: [(String, HUDState)] = [
            ("recording", .recording),
            ("transcribing", .transcribing),
            ("preparing", .preparingModel),
            ("downloading", .downloadingModel(downloadedBytes: 180_000_000, totalBytes: 600_000_000)),
            ("done", .done("Pasted")),
            ("error", .error("Microphone access is off. Turn it on in System Settings.")),
            ("notice", .notice("Tours reset")),
        ]
        for (label, theme) in [("light", AppTheme.light), ("dark", AppTheme.dark)] {
            for (stateName, state) in states {
                hud.update(state: state, theme: theme)
                capture(hud, "hud-\(stateName)-\(label)")
            }
            // Half-way through the transcribing → Pasted morph (`HUDLayout.morph`, 0.3 s).
            hud.update(state: .transcribing, theme: theme)
            RunLoop.main.run(until: Date().addingTimeInterval(0.5))
            hud.update(state: .done("Pasted"), theme: theme)
            capture(hud, "hud-morph-mid-\(label)", after: 0.12)
            RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        }
        hud.update(state: .idle)

        print("ui-preview: \(saved) screenshots in \(dir.path)")
        exit(saved > 0 ? 0 : 1)
    }
}
