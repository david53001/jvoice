import AppKit
import AVFoundation
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
        appearance = NSAppearance(named: coordinator.appTheme == .dark ? .darkAqua : .aqua)
        contentView = NSHostingView(rootView: WelcomeView(
            coordinator: coordinator,
            model: model,
            onContinue: { [weak self] in self?.goToAllSet() },
            onShowMeAround: { [weak self] in self?.answer(showMeAround: true) },
            onNoThanks: { [weak self] in self?.answer(showMeAround: false) },
            onStartDictating: { [weak self] in self?.close() }
        ))
        setContentSize(NSSize(width: WelcomeView.width, height: WelcomeView.height))
        center()
        // The ⓘ like every JVoice window: replay the Welcome tour or one part of it. The view's 40 pt
        // top / 36 pt side padding keeps it clear of the content under the transparent title bar.
        InfoButton.install(in: self, tour: .welcome, shortcuts: SettingsWindow.infoShortcuts())

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
        .background(theme.windowBackground)
        .preferredColorScheme(theme.colorScheme)
    }

    // MARK: Page 1 — welcome + permissions

    private var permissionsPage: some View {
        VStack(spacing: 0) {
            JMark(theme: theme)
            Text("Welcome to JVoice")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(theme.textPrimary)
                .padding(.top, 14)
            Text("Press \(model.toggleShortcut) anywhere, talk, press it again — your words are typed for you. Everything stays on this Mac.")
                .font(.system(size: 13))
                .foregroundStyle(theme.textSecondary)
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
                Rectangle().fill(theme.hairline).frame(height: 1)
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
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(theme.hairline))
            .padding(.top, 22)

            Text("Recommended. You can change these later in System Settings.")
                .font(.system(size: 11))
                .foregroundStyle(theme.textMuted)
                .padding(.top, 8)

            Spacer(minLength: 0)
            MonoButton(title: "Continue", primary: true, theme: theme, action: onContinue)
                .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: Page 2 — all set (+ the tour question)

    private var allSetPage: some View {
        VStack(spacing: 0) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(theme.textPrimary)
            Text("You're all set!")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(theme.textPrimary)
                .padding(.top, 12)
            Text("JVoice lives in your menu bar. Your shortcuts:")
                .font(.system(size: 13))
                .foregroundStyle(theme.textSecondary)
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
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.textPrimary)
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
                    MonoButton(title: "Start Dictating", primary: true, theme: theme, action: onStartDictating)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .frame(height: 118, alignment: .bottom)
        }
    }

    private var tourQuestion: some View {
        VStack(spacing: 0) {
            Rectangle().fill(theme.hairline).frame(width: 300, height: 1)
            Text("Want a quick tour?")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
                .padding(.top, 14)
            Text("We'll point out each part the first time you use it. You can skip any time.")
                .font(.system(size: 12))
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
            HStack(spacing: 12) {
                MonoButton(title: "No Thanks", primary: false, theme: theme, action: onNoThanks)
                    .keyboardShortcut(.cancelAction)
                MonoButton(title: "Show Me Around", primary: true, theme: theme, action: onShowMeAround)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 14)
        }
    }
}

// MARK: - Pieces

/// The black-squircle "J" (the app icon's mark), drawn so it follows the theme.
private struct JMark: View {
    let theme: Theme

    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(theme.textPrimary)
            .frame(width: 64, height: 64)
            .overlay(
                Text("J")
                    .font(.system(size: 36, weight: .heavy, design: .rounded))
                    .foregroundStyle(theme.windowBackground)
            )
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
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textSecondary)
            }
            Spacer(minLength: 8)
            if granted {
                Label("Granted", systemImage: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.textSecondary)
            } else {
                MonoButton(title: buttonTitle, primary: false, theme: theme, compact: true, action: action)
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
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.textPrimary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(theme.inputBackground))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(theme.hairline))
                .frame(width: 130, alignment: .trailing)
            Text(name)
                .font(.system(size: 13))
                .foregroundStyle(theme.textSecondary)
                .frame(width: 170, alignment: .leading)
        }
        .padding(.vertical, 2)
    }
}

/// Monochrome button: primary = filled with the text colour, secondary = hairline outline.
private struct MonoButton: View {
    let title: String
    let primary: Bool
    let theme: Theme
    var compact = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: compact ? 12 : 13, weight: .semibold))
                .foregroundStyle(primary ? theme.windowBackground : theme.textPrimary)
                .padding(.horizontal, compact ? 12 : 18)
                .padding(.vertical, compact ? 5 : 8)
                .frame(minWidth: compact ? nil : 130)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(primary ? theme.textPrimary : theme.inputBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(primary ? Color.clear : theme.hairline)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
