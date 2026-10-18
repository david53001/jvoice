import AppKit
import Sparkle

/// Auto-updates via Sparkle 2 (docs/sparkle-updates/README.md). Same setup as MacStats and
/// BetterScreenshot.
///
/// Configuration lives in `Resources/Info.plist`: `SUFeedURL` (the appcast attached to the latest
/// GitHub release), `SUPublicEDKey` (updates must be signed with the matching EdDSA key) and
/// `SUEnableAutomaticChecks` (check daily without first asking permission). The app is not
/// sandboxed, so Sparkle installs via its bundled `Autoupdate` / `Updater.app`; the framework's XPC
/// services (only for sandboxed apps) are removed by `scripts/build-app.sh`. The only network
/// traffic is the appcast + update download from GitHub (no system profile is sent) — besides the
/// one-time Whisper model download, JVoice's only runtime network call; nothing of the user's
/// (audio, transcripts, settings) is ever sent.
///
/// JVoice is a menu-bar app, so scheduled checks use Sparkle's "gentle reminders": a found update's
/// window opens *behind* the user's windows instead of taking focus — except when Sparkle decides on
/// "immediate focus" (its documented default: the app was launched recently, e.g. at login, or the
/// Mac had been idle), when it opens in front, as in most Mac apps. So that a window behind others
/// isn't missed, the menu's "Check for Updates…" item and the Settings → Updates button both read
/// "Update Available (X)…" (`actionTitle`) until the user looks at it; either one brings Sparkle's
/// window forward. (No notification: the app never asks for that permission.)
@MainActor
final class Updates: NSObject, ObservableObject {
    static let shared = Updates()

    /// Whether a check can start now (false while one is running), for the menu item and Settings.
    @Published private(set) var canCheck = false
    /// Set while a scheduled check has found an update the user hasn't looked at yet.
    @Published private(set) var pendingVersion: String?

    private var controller: SPUStandardUpdaterController!
    private var canCheckObservation: NSKeyValueObservation?

    private override init() {
        super.init()
        #if SPARKLE_E2E_TEST
        let updaterDelegate: SPUUpdaterDelegate? = self
        #else
        let updaterDelegate: SPUUpdaterDelegate? = nil
        #endif
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: updaterDelegate,
                                                  userDriverDelegate: self)
    }

    /// Starts the updater (and its schedule). Called once at launch.
    func start() {
        controller.startUpdater()
        canCheckObservation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            let value = updater.canCheckForUpdates
            Task { @MainActor in self?.canCheck = value }
        }
    }

    /// "Check for Updates…" / "Update Available (X)…": shows Sparkle's window with the result, or
    /// brings the waiting update's window forward.
    func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)   // a menu-bar app: otherwise the window can open behind others
        controller.checkForUpdates(nil)
    }

    /// The menu item and the Settings button are usable: no check running, or one waits to be seen.
    var canCheckOrShow: Bool { canCheck || pendingVersion != nil }

    /// The one label of the menu item and the Settings button: "Update Available (X)…" while a
    /// background find waits to be seen, otherwise "Check for Updates…".
    var actionTitle: String { Self.actionTitle(pendingVersion: pendingVersion) }

    nonisolated static func actionTitle(pendingVersion: String?) -> String {
        pendingVersion.map { "Update Available (\($0))…" } ?? "Check for Updates…"
    }

    /// Settings → Updates → "Check automatically" (Sparkle stores it in our defaults as
    /// `SUEnableAutomaticChecks`; the Info.plist value is only the default).
    var automaticallyChecks: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set {
            objectWillChange.send()
            controller.updater.automaticallyChecksForUpdates = newValue
        }
    }

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }
}

extension Updates: SPUStandardUserDriverDelegate {
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool,
                                                               forUpdate update: SUAppcastItem,
                                                               state: SPUUserUpdateState) {
        guard !state.userInitiated else { return }
        let version = update.displayVersionString
        Task { @MainActor in self.pendingVersion = version }
    }

    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        Task { @MainActor in self.pendingVersion = nil }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        Task { @MainActor in self.pendingVersion = nil }
    }
}

#if SPARKLE_E2E_TEST
/// Only in the throwaway build of `scripts/sparkle-e2e-test.sh` (`-DSPARKLE_E2E_TEST`): log each step
/// to stderr for the script, and install a downloaded update right away instead of on quit (the
/// script can't quit the app gracefully without an Apple-event permission prompt).
extension Updates: SPUUpdaterDelegate {
    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        NSLog("SPARKLE-E2E found %@ (build %@)", item.displayVersionString, item.versionString)
    }

    nonisolated func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        NSLog("SPARKLE-E2E downloaded %@", item.versionString)
    }

    nonisolated func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        NSLog("SPARKLE-E2E installing %@", item.versionString)
    }

    nonisolated func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                             immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        NSLog("SPARKLE-E2E ready to install %@; installing now", item.versionString)
        immediateInstallHandler()
        return true
    }

    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        NSLog("SPARKLE-E2E aborted: %@", (error as NSError).description)
    }

    nonisolated func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
                             error: Error?) {
        NSLog("SPARKLE-E2E cycle finished, error: %@", error.map { ($0 as NSError).description } ?? "none")
    }
}
#endif
