import SwiftUI

#if canImport(KeyboardShortcuts)
import AppKit
import Carbon.HIToolbox
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

    var body: some View {
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
        .onAppear(perform: refresh)
        .onDisappear(perform: endCapture)
        // Closing Settings (or clicking away) while listening must not leave a
        // live event monitor behind — or, far worse, the app's global hotkeys
        // switched off.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            endCapture()
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

    private func toggleCapture() {
        isCapturing ? endCapture() : beginCapture()
    }

    private func beginCapture() {
        guard !isCapturing else { return }
        isCapturing = true

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
        endCapture()
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard isCapturing else { return event }

        // A click anywhere else ends the capture and is delivered normally.
        guard event.type == .keyDown else {
            endCapture()
            return event
        }

        let modifiers = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting(.capsLock)

        switch ShortcutCapturePolicy.decide(
            key: Self.key(for: event),
            hasAnyModifier: !modifiers.isEmpty,
            hasModifierBesidesShift: !modifiers.subtracting(.shift).isEmpty,
            isFunctionKey: Self.isFunctionKey(event)
        ) {
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
            KeyboardShortcuts.setShortcut(shortcut, for: name)
            shortcutText = "\(shortcut)"
            endCapture()
        }

        return nil
    }

    private static func key(for event: NSEvent) -> ShortcutCapturePolicy.Key {
        if event.keyCode == UInt16(kVK_Escape) {
            return .escape
        }
        switch event.specialKey {
        case .tab:
            return .tab
        case .delete, .deleteForward, .backspace:
            return .delete
        default:
            return .other
        }
    }

    private static func isFunctionKey(_ event: NSEvent) -> Bool {
        guard let special = event.specialKey else { return false }
        return (NSEvent.SpecialKey.f1.rawValue...NSEvent.SpecialKey.f35.rawValue).contains(special.rawValue)
    }
}
#endif
