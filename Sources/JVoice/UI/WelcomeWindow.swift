import AppKit
import AVFoundation
import Combine
import ApplicationServices
import KeyboardShortcuts
import SwiftUI

/// JVoice's first-run window (guided tours, BetterScreenshot v3 spec §14.9 — "new users only, and ask
/// first"). Two pages:
///  - `.permissions` — what JVoice does, plus live Microphone / Accessibility status rows (polled
///    once a second while the window is up). Permissions are recommended, never required to go on.
///  - `.allSet` — a shortcut cheat sheet (tour anchors `welcome.shortcut` / `welcome.tryIt`) and, for a
///    new user who hasn't answered yet, "Want a quick tour?". Otherwise one "Start Dictating" button.
///
/// Closing the window before the question was answered counts as No Thanks, on either page: JVoice
/// launches at login, so a first-run window that came back on every login until clicked through
/// would nag exactly the people the tours are meant to welcome.
@MainActor
final class WelcomeWindow: NSWindow {
    enum Page { case permissions, allSet }

    /// The answer: true = Show Me Around (with this window, so the Welcome tour runs over it),
    /// false = No Thanks or the window was closed while the question was still open.
    var onTourAnswer: ((Bool, NSWindow?) -> Void)?

    private let model = WelcomeModel()
    private var pollTimer: Timer?
    private var closeObserver: NSObjectProtocol?
    private var appearanceObserver: AnyCancellable?

    init(coordinator: VoiceCoordinator) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: WelcomeView.width, height: WelcomeView.height),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        title = "Welcome to JVoice"
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isReleasedWhenClosed = false
        isMovableByWindowBackground = true
        appearance = coordinator.appTheme.nsAppearance   // nil = follow macOS
        // Same translucent backdrop as Settings: a behind-window material under the transparent title bar.
        WindowMaterial.install(WelcomeView(
            coordinator: coordinator,
            model: model,
            onContinue: { [weak self] in self?.goToAllSet() },
            onShowMeAround: { [weak self] in self?.answer(showMeAround: true) },
            onNoThanks: { [weak self] in self?.answer(showMeAround: false) },
            onStartDictating: { [weak self] in self?.close() }
        ), in: self)
        setContentSize(NSSize(width: WelcomeView.width, height: WelcomeView.height))
        center()
        // The ⓘ like every JVoice window: replay the Welcome tour or one part of it. The view's 40 pt
        // top / 36 pt side padding keeps it clear of the content under the transparent title bar.
        InfoButton.install(in: self, tour: .welcome, shortcuts: SettingsWindow.infoShortcuts())

        // Follow a System / Light / Dark change made in Settings while this window is open.
        appearanceObserver = coordinator.$appTheme.dropFirst().sink { [weak self] theme in
            self?.appearance = theme.nsAppearance
        }

        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: self, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.windowWillClose() }
        }
    }

    /// Shows `page`. `askTourQuestion` = the all-set page carries "Want a quick tour?" (a new user who
    /// hasn't answered — `TourCoordinator.shouldAskQuestion`); nil keeps whatever is already decided.
    func show(page: Page, askTourQuestion: Bool? = nil) {
        if let askTourQuestion { model.pendingQuestion = askTourQuestion }
        model.page = page
        model.refresh()
        startPolling()
        // Accessory (LSUIElement) app: without this the window opens behind the frontmost app.
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        TourEvents.surfaceShown(.welcome, in: self)
    }

    // MARK: - Actions

    private func goToAllSet() {
        model.page = .allSet
        model.refresh()
    }

    private func answer(showMeAround: Bool) {
        // The question goes first: the page swaps it for "Start Dictating", and the Welcome tour's
        // anchors (the shortcut row, the "Try it" line) sit above it, so they don't move.
        model.pendingQuestion = false
        onTourAnswer?(showMeAround, showMeAround ? self : nil)
        if !showMeAround { close() }
    }

    private func windowWillClose() {
        pollTimer?.invalidate()
        pollTimer = nil
        guard model.pendingQuestion else { return }
        model.pendingQuestion = false
        onTourAnswer?(false, nil)
    }

    // MARK: - Live permission status

    private func startPolling() {
        pollTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }
}

// MARK: - Model

@MainActor
private final class WelcomeModel: ObservableObject {
    @Published var page: WelcomeWindow.Page = .permissions
    /// "Want a quick tour?" is still to be answered. Shown on the all-set page only, but it counts from
    /// the first page on: closing the window anywhere before answering = No Thanks.
    @Published var pendingQuestion = false
    @Published private(set) var microphone: AVAuthorizationStatus = .notDetermined
    @Published private(set) var accessibilityTrusted = false
    @Published private(set) var toggleShortcut = TourText.unboundShortcut
    @Published private(set) var undoShortcut: String?
    /// The Accessibility prompt was already raised from this window; the next click opens the pane.
    var didPromptAccessibility = false

    func refresh() {
        let mic = AVCaptureDevice.authorizationStatus(for: .audio)
        if mic != microphone { microphone = mic }
        let trusted = AXIsProcessTrusted()
        if trusted != accessibilityTrusted { accessibilityTrusted = trusted }
        let toggle = KeyboardShortcuts.getShortcut(for: .toggleRecording)?.description ?? TourText.unboundShortcut
        if toggle != toggleShortcut { toggleShortcut = toggle }
        let undo = KeyboardShortcuts.getShortcut(for: .undoLastPaste)?.description
        if undo != undoShortcut { undoShortcut = undo }
    }

    func requestMicrophone() {
        switch microphone {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                Task { @MainActor [weak self] in self?.refresh() }
            }
        default:
            NSWorkspace.shared.open(SettingsURLs.microphone)
        }
    }

    func requestAccessibility() {
        if didPromptAccessibility {
            NSWorkspace.shared.open(SettingsURLs.accessibility)
            return
        }
        didPromptAccessibility = true
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true]
        _ = AXIsProcessTrustedWithOptions(options)
    }
}

// MARK: - View

private struct WelcomeView: View {
    static let width: CGFloat = 460
    static let height: CGFloat = 470

    @ObservedObject var coordinator: VoiceCoordinator
    @ObservedObject var model: WelcomeModel
    let onContinue: () -> Void
    let onShowMeAround: () -> Void
    let onNoThanks: () -> Void
    let onStartDictating: () -> Void

    private var theme: Theme { coordinator.appTheme.theme }

    var body: some View {
        VStack(spacing: 0) {
            switch model.page {
            case .permissions: permissionsPage
            case .allSet: allSetPage
            }
        }
        .padding(.horizontal, 36)
        .padding(.top, 40)
        .padding(.bottom, 28)
        .frame(width: Self.width, height: Self.height, alignment: .top)
    }

    // MARK: Page 1 — welcome + permissions

    private var permissionsPage: some View {
        VStack(spacing: 0) {
            JMark()
            Text("Welcome to JVoice")
                .font(.title2.bold())
                .padding(.top, 14)
            Text("Press \(model.toggleShortcut) anywhere, talk, press it again — your words are typed for you. Everything stays on this Mac.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            VStack(spacing: 0) {
                PermissionRow(
                    theme: theme,
                    symbol: "mic.fill",
                    title: "Microphone",
                    detail: "To hear what you say.",
                    granted: model.microphone == .authorized,
                    buttonTitle: model.microphone == .notDetermined ? "Allow" : "Open Settings",
                    action: model.requestMicrophone
                )
                Divider().padding(.horizontal, 14)
                PermissionRow(
                    theme: theme,
                    symbol: "keyboard",
                    title: "Accessibility",
                    detail: "To type the text into the app you're using.",
                    granted: model.accessibilityTrusted,
                    buttonTitle: model.didPromptAccessibility ? "Open Settings" : "Allow",
                    action: model.requestAccessibility
                )
            }
            .background(CardBackground(cornerRadius: 12))
            .padding(.top, 22)

            Text("Recommended. You can change these later in System Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 8)

            Spacer(minLength: 0)
            WelcomeButton(title: "Continue", primary: true, action: onContinue)
                .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: Page 2 — all set (+ the tour question)

    private var allSetPage: some View {
        VStack(spacing: 0) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            Text("You're all set!")
                .font(.title2.bold())
                .padding(.top, 12)
            Text("JVoice lives in your menu bar. Your shortcuts:")
                .font(.body)
                .foregroundStyle(.secondary)
                .padding(.top, 6)

            VStack(spacing: 8) {
                ShortcutRow(theme: theme, keys: model.toggleShortcut, name: "Start / stop dictation")
                    .tourAnchor("welcome.shortcut")
                if let undo = model.undoShortcut {
                    ShortcutRow(theme: theme, keys: undo, name: "Undo last paste")
                }
            }
            .padding(.top, 16)

            Text("Try it: click into any text box and press \(model.toggleShortcut)")
                .font(.body.weight(.medium))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .tourAnchor("welcome.tryIt")
                .padding(.top, 16)

            Spacer(minLength: 0)

            // The bottom area has its own fixed height, so answering the question (which swaps it for
            // "Start Dictating") never moves the tour's anchors above.
            Group {
                if model.pendingQuestion {
                    tourQuestion
                } else {
                    WelcomeButton(title: "Start Dictating", primary: true, action: onStartDictating)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .frame(height: 118, alignment: .bottom)
        }
    }

    private var tourQuestion: some View {
        VStack(spacing: 0) {
            Divider().frame(width: 300)
            Text("Want a quick tour?")
                .font(.headline)
                .padding(.top, 14)
            Text("We'll point out each part the first time you use it. You can skip any time.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
            HStack(spacing: 12) {
                WelcomeButton(title: "No Thanks", primary: false, action: onNoThanks)
                    .keyboardShortcut(.cancelAction)
                WelcomeButton(title: "Show Me Around", primary: true, action: onShowMeAround)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 14)
        }
    }
}

// MARK: - Pieces

/// The app's mark: the real app icon when running as the packaged app, else the black-squircle "J"
/// drawn with the icon's continuous 22 % corner.
private struct JMark: View {
    private static let bundledIcon: NSImage? =
        Bundle.main.bundleURL.pathExtension == "app" ? NSApp.applicationIconImage : nil

    var body: some View {
        Group {
            if let icon = Self.bundledIcon {
                // App icons carry ~10 % transparent margin on every side; 80 pt shows a ~64 pt squircle.
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 80, height: 80)
                    .padding(-8)
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.black)
                    .frame(width: 64, height: 64)
                    .overlay(
                        Text("J")
                            .font(.system(size: 36, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                    )
            }
        }
        .accessibilityHidden(true)
    }
}

private struct PermissionRow: View {
    let theme: Theme
    let symbol: String
    let title: String
    let detail: String
    let granted: Bool
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(theme.textSecondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.body.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
            }
            Spacer(minLength: 8)
            if granted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.green)
            } else {
                Button(buttonTitle, action: action)
                    .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}

private struct ShortcutRow: View {
    let theme: Theme
    let keys: String
    let name: String

    var body: some View {
        HStack(spacing: 12) {
            Text(keys)
                .font(.callout.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(theme.inputBackground))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(theme.hairline, lineWidth: Design.hairlineWidth))
                .frame(width: 130, alignment: .trailing)
            Text(name)
                .font(.body)
                .foregroundStyle(theme.textSecondary)
                .frame(width: 170, alignment: .leading)
        }
        .padding(.vertical, 2)
    }
}

/// The page's large native buttons: `.borderedProminent` for the primary action, `.bordered` beside it.
private struct WelcomeButton: View {
    let title: String
    let primary: Bool
    let action: () -> Void

    var body: some View {
        if primary {
            Button(action: action) { label }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        } else {
            Button(action: action) { label }
                .buttonStyle(.bordered)
                .controlSize(.large)
        }
    }

    private var label: some View {
        Text(title).frame(minWidth: 110)
    }
}
