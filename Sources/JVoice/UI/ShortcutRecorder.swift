import SwiftUI

#if canImport(KeyboardShortcuts)
import AppKit
import KeyboardShortcuts

/// Settings row that records a global chord for a `KeyboardShortcuts.Name`.
///
/// JVoice draws this itself instead of using `KeyboardShortcuts.Recorder`.
/// That view is the package's only user of `Bundle.module` (five localized
/// strings), and SwiftPM's generated `Bundle.module` accessor hard-traps
/// (`Swift.fatalError`) inside a packaged `.app`: it looks for the resource
/// bundle at `<App>.app/KeyboardShortcuts_KeyboardShortcuts.bundle` — the
/// bundle ROOT, where `codesign` refuses to seal anything ("unsealed contents
/// present in the bundle root") — and then at an absolute build-directory path
/// baked in on the build machine. Both are gone in a shipped app, so merely
/// opening Settings killed the process. Everything else in the package (Name,
/// defaults, storage, global registration) is unaffected and still used.
struct ShortcutRecorder: View {
    let label: String
    let name: KeyboardShortcuts.Name
    let theme: Theme

    @State private var shortcutText = ""
    @State private var isCapturing = false
    @State private var monitor: Any?
    /// Why the last chord pressed was refused (taken by the other action, by
    /// macOS, or by a standard menu command). Cleared by the next capture.
    @State private var refusalMessage: String?

    /// The global actions a chord can drive — a chord may belong to only one.
    private static let actions: [(name: KeyboardShortcuts.Name, title: String)] = [
        (.toggleRecording, "Toggle Recording"),
        (.undoLastPaste, "Undo Last Paste"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            row
            if let refusalMessage {
                InlineNotice(text: refusalMessage, theme: theme)
            }
        }
        .onAppear(perform: refresh)
        .onDisappear(perform: endCapture)
        // Closing Settings (or clicking away) while listening must not leave a
        // live event monitor behind — or, far worse, the app's global hotkeys
        // switched off.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            endCapture()
        }
    }

    private var row: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(theme.textSecondary)

            Spacer(minLength: 8)

            Button(action: toggleCapture) {
                Text(fieldText)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isCapturing || shortcutText.isEmpty ? theme.textMuted : theme.textPrimary)
                    .frame(minWidth: 104)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(theme.inputBackground)
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(
                                        isCapturing ? theme.textPrimary.opacity(0.55) : theme.hairline,
                                        lineWidth: 1
                                    )
                            )
                    )
            }
            .buttonStyle(.plain)
            .help(isCapturing ? "Press the new shortcut, or Esc to cancel" : "Click, then press the shortcut")

            Button(action: clear) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textMuted)
            }
            .buttonStyle(.plain)
            .help("Remove this shortcut")
            .opacity(shortcutText.isEmpty ? 0 : 1)
            .disabled(shortcutText.isEmpty)
        }
    }

    private var fieldText: String {
        if isCapturing {
            return "Press Shortcut"
        }
        return shortcutText.isEmpty ? "Record Shortcut" : shortcutText
    }

    private func refresh() {
        shortcutText = KeyboardShortcuts.getShortcut(for: name).map { "\($0)" } ?? ""
    }

    /// Recorders listening for a chord right now. While any is, Return and Esc belong to it (Esc
    /// cancels), not to a tour tag's Next / Skip Tour — `SettingsWindow.claimsTourKeys`.
    static var activeCaptures = 0

    private func toggleCapture() {
        isCapturing ? endCapture() : beginCapture()
    }

    private func beginCapture() {
        guard !isCapturing else { return }
        isCapturing = true
        Self.activeCaptures += 1
        refusalMessage = nil

        // A registered global chord is swallowed system-wide — by this app
        // too — so the hotkeys stand down while the user types one.
        KeyboardShortcuts.disable(.toggleRecording)
        KeyboardShortcuts.disable(.undoLastPaste)

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseUp, .rightMouseUp]) { event in
            handle(event)
        }
    }

    private func endCapture() {
        guard isCapturing else { return }
        isCapturing = false
        Self.activeCaptures = max(0, Self.activeCaptures - 1)

        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }

        KeyboardShortcuts.enable(.toggleRecording)
        KeyboardShortcuts.enable(.undoLastPaste)
    }

    private func clear() {
        KeyboardShortcuts.setShortcut(nil, for: name)
        shortcutText = ""
        refusalMessage = nil
        endCapture()
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard isCapturing else { return event }

        // A click anywhere else ends the capture and is delivered normally.
        guard event.type == .keyDown else {
            endCapture()
            return event
        }

        switch ShortcutCapturePolicy.decide(event: event) {
        case .cancel:
            endCapture()
        case .clear:
            clear()
        case .reject:
            NSSound.beep()
        case .accept:
            guard let shortcut = KeyboardShortcuts.Shortcut(event: event) else {
                NSSound.beep()
                break
            }
            // Refused chords keep the recorder listening, so the user can
            // simply press another one.
            if let refusal = refusal(for: shortcut, event: event) {
                NSSound.beep()
                refusalMessage = refusal.message(for: "\(shortcut)")
                break
            }
            KeyboardShortcuts.setShortcut(shortcut, for: name)
            shortcutText = "\(shortcut)"
            refusalMessage = nil
            endCapture()
        }

        return nil
    }

    /// Gathers the live inputs for `ShortcutCapturePolicy.refusal`: the other
    /// action's chord, the enabled system shortcuts and the app menu's key
    /// equivalents (Copy, Undo, Quit, Settings…).
    private func refusal(for shortcut: KeyboardShortcuts.Shortcut, event: NSEvent) -> ShortcutCapturePolicy.Refusal? {
        let otherActions = Self.actions
            .filter { $0.name != name }
            .compactMap { action -> (title: String, chord: ShortcutCapturePolicy.Chord)? in
                KeyboardShortcuts.getShortcut(for: action.name).map { (action.title, Self.chord(for: $0)) }
            }
        return ShortcutCapturePolicy.refusal(
            for: Self.chord(for: shortcut),
            character: ShortcutCapturePolicy.character(of: event),
            otherActions: otherActions,
            systemChords: ShortcutCapturePolicy.systemReservedChords(),
            menuShortcuts: ShortcutCapturePolicy.menuShortcuts(in: NSApp.mainMenu)
        )
    }

    private static func chord(for shortcut: KeyboardShortcuts.Shortcut) -> ShortcutCapturePolicy.Chord {
        ShortcutCapturePolicy.Chord(keyCode: shortcut.carbonKeyCode, carbonModifiers: shortcut.carbonModifiers)
    }
}
#endif
