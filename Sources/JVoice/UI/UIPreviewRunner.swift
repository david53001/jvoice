import AppKit
import SwiftUI

/// Hidden dev mode: `JVoice --ui-preview <dir>`.
///
/// Opens the real Settings window (Light and Dark; top and scrolled to the bottom), the Welcome window (both pages) and the HUD pill
/// in every state (plus a tour tag over Settings), one at a time, and saves a screenshot of the screen
/// under each window — desktop included, so the translucency shows — to `<dir>` with
/// `CGWindowListCreateImage` of that screen region, taken in-process: the only way to look at the UI without clicking through the app (`ImageRenderer` / `CALayer.render` come back blank, see `UI/CLAUDE.md`). A process
/// may capture its own windows without Screen Recording permission (other apps' windows are left out,
/// so use `--backdrop` for a known background).
///
/// Options (2026-09-30, Settings → Opacity): `--opacity <0…1>` previews that Opacity without saving it;
/// `--backdrop white|black|wallpaper` puts a full-screen window of that under everything (white = the
/// worst case for the pill; wallpaper = a bright macOS wallpaper); `--active` draws Settings' and
/// Welcome's material in its active (key-window, see-through) state instead of the inactive one the
/// never-key preview windows get (controls still look inactive); `--hud-timeline`
/// also captures the "Pasted" and error pills 0.5, 2 and 5 s after they appear (Liquid Glass re-adapts
/// to what's behind it over ~1 s).
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
        func option(_ name: String) -> String? {
            arguments.firstIndex(of: name).flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
        }
        if let raw = option("--opacity"), let value = Double(raw) {
            UIOpacityStore.shared.persists = false   // preview only — never written
            UIOpacityStore.shared.value = UIOpacity.clamped(value)
        }
        WindowMaterial.forcesActiveState = arguments.contains("--active")
        let backdrop = option("--backdrop").flatMap(Self.backdropWindow)
        backdrop?.orderFrontRegardless()
        let coordinator = VoiceCoordinator()
        var saved = 0

        func capture(_ window: NSWindow, _ name: String, after delay: TimeInterval = 0.8) {
            window.displayIfNeeded()
            capture(window.frame, name, after: delay)
        }

        func capture(_ frame: NSRect, _ name: String, after delay: TimeInterval = 0.8) {
            RunLoop.main.run(until: Date().addingTimeInterval(delay))
            let out = dir.appendingPathComponent("\(name).png")
            // The screen region under the window, not the window alone: a single-window capture has no
            // backdrop, so materials and Liquid Glass would come out flat black.
            let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
            let r = frame.insetBy(dx: -12, dy: -12)
            let region = CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
            guard let image = Self.captureRegion(region),
                  let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]),
                  (try? png.write(to: out)) != nil else { return }
            saved += 1
            print("ui-preview: \(out.path)")
        }

        let appearances: [(String, NSAppearance.Name)] = [("light", .aqua), ("dark", .darkAqua)]

        for (label, name) in appearances {
            let settings = SettingsWindow(coordinator: coordinator)
            settings.appearance = NSAppearance(named: name)
            settings.orderFrontRegardless()
            capture(settings, "settings-\(label)")
            // Scrolled to the bottom: the Appearance (Opacity) card.
            if let scroll = Self.outermostScrollView(in: settings.contentView), let document = scroll.documentView {
                let bottom = document.isFlipped ? max(0, document.bounds.height - scroll.contentView.bounds.height) : 0
                scroll.contentView.scroll(to: NSPoint(x: 0, y: bottom))
                scroll.reflectScrolledClipView(scroll.contentView)
                capture(settings, "settings-bottom-\(label)")
                scroll.contentView.scroll(to: .zero)
                scroll.reflectScrolledClipView(scroll.contentView)
            }
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
            if arguments.contains("--hud-timeline") {
                // A fresh show each time (not a morph), sampled as the glass settles over the backdrop.
                for (stateName, state) in [("done", HUDState.done("Pasted")), ("error", states[5].1)] {
                    hud.update(state: .idle)
                    RunLoop.main.run(until: Date().addingTimeInterval(0.3))
                    hud.update(state: state, theme: theme)
                    capture(hud, "hud-\(stateName)-\(label)-t0.5", after: 0.5)
                    capture(hud, "hud-\(stateName)-\(label)-t2", after: 1.5)
                    capture(hud, "hud-\(stateName)-\(label)-t5", after: 3)
                }
            }
            // Half-way through the transcribing → Pasted morph (`HUDLayout.morph`, 0.3 s).
            hud.update(state: .transcribing, theme: theme)
            RunLoop.main.run(until: Date().addingTimeInterval(0.5))
            hud.update(state: .done("Pasted"), theme: theme)
            capture(hud, "hud-morph-mid-\(label)", after: 0.12)
            RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        }
        hud.update(state: .idle)

        backdrop?.orderOut(nil)
        print("ui-preview: \(saved) screenshots in \(dir.path)")
        exit(saved > 0 ? 0 : 1)
    }

    /// The biggest `NSScrollView` under `view` (SwiftUI's page-level `ScrollView`, not a card's list).
    private static func outermostScrollView(in view: NSView?) -> NSScrollView? {
        guard let view else { return nil }
        var found: [NSScrollView] = []
        func walk(_ v: NSView) {
            if let s = v as? NSScrollView { found.append(s) }
            v.subviews.forEach(walk)
        }
        walk(view)
        return found.max { $0.frame.height < $1.frame.height }
    }

    /// `CGWindowListCreateImage` (on-screen windows in `rect`, global top-left coordinates), looked up at
    /// run time: the macOS 15 SDK marks it unavailable to Swift in favour of ScreenCaptureKit, which
    /// needs Screen Recording permission even for the app's own windows.
    private static func captureRegion(_ rect: CGRect) -> CGImage? {
        typealias CreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW),
              let symbol = dlsym(handle, "CGWindowListCreateImage") else { return nil }
        let create = unsafeBitCast(symbol, to: CreateImage.self)
        // kCGWindowListOptionOnScreenOnly, kCGNullWindowID, kCGWindowImageBestResolution
        return create(rect, 1 << 0, 0, 1 << 3)?.takeRetainedValue()
    }

    /// A full-screen borderless window under every preview window: `white`, `black`, or `wallpaper` (a
    /// bright stock macOS wallpaper — the "busy bright wallpaper" of the opacity spec).
    private static func backdropWindow(_ kind: String) -> NSWindow? {
        guard let screen = NSScreen.main else { return nil }
        let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.level = .normal
        window.isReleasedWhenClosed = false
        switch kind {
        case "white": window.backgroundColor = .white
        case "black": window.backgroundColor = .black
        case "wallpaper":
            guard let image = NSImage(contentsOfFile: "/System/Library/Desktop Pictures/Mac Yellow.heic") else { return nil }
            let view = NSImageView(image: image)
            view.imageScaling = .scaleAxesIndependently
            window.contentView = view
        default: return nil
        }
        return window
    }
}
