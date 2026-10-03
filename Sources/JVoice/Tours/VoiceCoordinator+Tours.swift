import Foundation

extension VoiceCoordinator {
    /// A short tour confirmation in the HUD pill ("Tours reset", "… starts at your next dictation"),
    /// shown for 3 s then back to idle. Never shown over a recording or transcription in progress.
    func showTourNotice(_ message: String) {
        guard !hudState.isBusy else { return }
        updateHUD(.notice(message))
        scheduleHUDReset(after: 3_000_000_000)
    }
}
