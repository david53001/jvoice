import Foundation

#if canImport(KeyboardShortcuts)
import KeyboardShortcuts
public typealias HotKeyShortcutName = KeyboardShortcuts.Name

public extension KeyboardShortcuts.Name {
    static let toggleRecording = Self("toggleRecording", default: .init(.space, modifiers: [.option]))
    /// Opt-in "undo last paste" chord. NO default: unset means disabled (a
    /// registered global chord is swallowed system-wide, so it must stay unset
    /// until the user assigns one). Mirrors the Windows port.
    static let undoLastPaste = Self("undoLastPaste")
}
#else
public struct HotKeyShortcutName: Hashable, Sendable {
    public var rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public static let toggleRecording = HotKeyShortcutName("toggleRecording")
    public static let undoLastPaste = HotKeyShortcutName("undoLastPaste")
}
#endif

@MainActor
public final class HotKeyManager {
    public typealias ToggleAction = @Sendable () -> Void

    public let shortcutName: HotKeyShortcutName
    private let onToggle: ToggleAction
    private var isRegistered = false
    private var lastFiredAt: Date = .distantPast
    private static let minimumInterval: TimeInterval = 0.15

    public init(shortcutName: HotKeyShortcutName = .toggleRecording, onToggle: @escaping ToggleAction) {
        self.shortcutName = shortcutName
        self.onToggle = onToggle
        // Registration happens at app start (VoiceCoordinator.start →
        // hotKeyManager.register()), not at construction — so the global
        // hotkey isn't grabbed merely by building the manager (e.g. in tests).
    }

    public func register() {
        guard !isRegistered else { return }
        isRegistered = true

        #if canImport(KeyboardShortcuts)
        KeyboardShortcuts.onKeyDown(for: shortcutName) { [weak self] in
            guard let self else { return }
            let now = Date()
            if now.timeIntervalSince(self.lastFiredAt) < HotKeyManager.minimumInterval { return }
            self.lastFiredAt = now
            self.onToggle()
        }
        #endif
    }

    public func trigger() {
        onToggle()
    }

    public func handleToggle() {
        trigger()
    }
}
