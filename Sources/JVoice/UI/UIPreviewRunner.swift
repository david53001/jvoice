import AppKit
import SwiftUI

/// Hidden dev mode: `JVoice --ui-preview <dir>`.
///
/// Opens the real Settings window (Light and Dark), the Welcome window (both pages) and the HUD pill
/// in every state (plus a tour tag over Settings), one at a time, and saves a screenshot of the screen
/// under each window — desktop included, so the translucency shows — to `<dir>` with
/// `screencapture -R`. That needs Screen Recording permission for the terminal that runs it; without
/// it (`CGPreflightScreenCaptureAccess()` false, or `screencapture` fails) each window is drawn from
/// its views instead (`NSView.cacheDisplay`, no permission needed): layout, text, tints and corners
/// are right, but behind-window materials come out flat and a tour tag's own panel is left out
/// (files end in `-views.png`). `ImageRenderer` / `CALayer.render` come back blank, see `UI/CLAUDE.md`.
/// Settings is also shown scrolled to the bottom (the Updates card), once with a forced
/// "Update Available (1.2.1)…" label (`Updates.showPendingVersionForPreview`), the longest title.
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

        // Without Screen Recording `screencapture` saves nothing (or only the wallpaper): draw from the views.
        var screenCapture = CGPreflightScreenCaptureAccess()
        if !screenCapture { print("ui-preview: no Screen Recording permission; drawing windows from their views (materials flat)") }

        func capture(_ window: NSWindow, _ name: String, after delay: TimeInterval = 0.8) {
            window.displayIfNeeded()
            capture(window.frame, name, after: delay, window: window)
        }

        /// `window`: what to draw from its views when the screen can't be captured.
        func capture(_ frame: NSRect, _ name: String, after delay: TimeInterval = 0.8, window: NSWindow? = nil) {
            RunLoop.main.run(until: Date().addingTimeInterval(delay))
            if !screenCapture {
                if let window { drawFromViews(window, name) }
                return
            }
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
            if task.terminationStatus == 0 {
                saved += 1; print("ui-preview: \(out)")
            } else {
                screenCapture = false   // e.g. "could not create image from rect": no permission after all
                print("ui-preview: screencapture failed; drawing windows from their views (materials flat)")
                if let window { drawFromViews(window, name) }
            }
        }

        func drawFromViews(_ window: NSWindow, _ name: String) {
            // The frame view (title bar included) when there is one, else the content view.
            guard let view = window.contentView?.superview ?? window.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            let out = dir.appendingPathComponent("\(name)-views.png")
            guard let png = rep.representation(using: .png, properties: [:]), (try? png.write(to: out)) != nil else { return }
            saved += 1; print("ui-preview: \(out.path)")
        }

        /// Scrolls Settings' content to the bottom (the Updates card is last in the right column).
        func scrollToBottom(_ window: NSWindow) {
            func firstScrollView(_ view: NSView) -> NSScrollView? {
                if let scroll = view as? NSScrollView { return scroll }
                for sub in view.subviews { if let found = firstScrollView(sub) { return found } }
                return nil
            }
            guard let content = window.contentView, let scroll = firstScrollView(content),
                  let document = scroll.documentView else { return }
            let clip = scroll.contentView
            let y = document.isFlipped ? max(0, document.bounds.height - clip.bounds.height) : 0
            clip.scroll(to: NSPoint(x: clip.bounds.minX, y: y))
            scroll.reflectScrolledClipView(clip)
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
                capture(settings.frame.union(tag.tagPanel.frame), "tour-tag-\(label)", window: settings)
                tag.hide()
            }
            // The Updates card: as installed (not started here, so its button is disabled), then with
            // a found update waiting — the longest label the button gets.
            scrollToBottom(settings)
            capture(settings, "settings-bottom-\(label)")
            Updates.shared.showPendingVersionForPreview("1.2.1")
            capture(settings, "settings-update-available-\(label)")
            Updates.shared.showPendingVersionForPreview(nil)
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

        // The one-time "Open JVoice at login?" card (`LaunchAtLoginPromptController`), on the screen
        // under the pointer like the real one; its buttons do nothing here.
        let card = LaunchAtLoginCard()
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main {
            for (label, name) in appearances {
                card.show(title: "Open JVoice at login?",
                          message: "Your dictation shortcut keeps working after a restart. You can change this any time in the JVoice menu.",
                          actions: [.init("No Thanks") {}, .init("Open at Login", primary: true) {}],
                          on: screen, appearance: NSAppearance(named: name))
                capture(card.window, "login-card-\(label)")
                card.show(title: "JVoice will open at login.", message: nil, actions: [],
                          on: screen, appearance: NSAppearance(named: name))
                capture(card.window, "login-card-done-\(label)")
            }
        }
        card.hide()

        print("ui-preview: \(saved) screenshots in \(dir.path)")
        exit(saved > 0 ? 0 : 1)
    }
}
