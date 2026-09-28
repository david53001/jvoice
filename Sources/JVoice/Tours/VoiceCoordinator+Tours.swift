import Foundation

extension VoiceCoordinator {
    /// A short tour confirmation in the HUD pill ("Tours reset", "… starts at your next dictation").
    /// The pill has no neutral text state today — `.done` / `.copied` always read "Pasted" / "Copied" —
    /// so this rides the transient message path (`showError`: shown for 3 s, then back to idle).
    /// Never shown over a recording or transcription in progress.
    func showTourNotice(_ message: String) {
        guard !hudState.isBusy else { return }
        showError(message)
    }
}
