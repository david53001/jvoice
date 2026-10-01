using JVoice.Core.Models;

namespace JVoice.Core;

/// Pure decision logic extracted from the (UI-thread) VoiceCoordinator so it
/// is unit-testable from net9.0 JVoice.Tests (which cannot reference the
/// net9.0-windows JVoice.App). The WPF coordinator calls these.
public enum TrayIconActivity { Idle, Recording, Transcribing }

/// What a hotkey / tray / pill press does (Mac 8ea5088 <c>PressAction</c>).
public enum PressAction
{
    /// Idle: open the microphone.
    Start,
    /// Recording: stop and transcribe.
    Stop,
    /// The microphone is still opening (the pill is already up): end the recording as soon as it
    /// opens instead of dropping the press.
    StopOnceOpened,
    /// A stop is already running, or the previous dictation is still being transcribed/pasted.
    Ignore,
}

/// Why a paste didn't land (mirrors the app's PasteOutcome failures).
public enum PasteFailure { AccessDenied, ClipboardLocked, TargetRejected }

public static class CoordinatorDecisions
{
    /// Ports VoiceCoordinator.stopRecordingAndTranscribe's target resolution:
    /// the live foreground window is the paste target *unless it belongs to JVoice
    /// itself* (our HUD/Settings), in which case fall back to the last foreground
    /// window that wasn't ours.
    ///
    /// `currentForegroundIsSelf` MUST be computed by the caller from process
    /// ownership of the live foreground (Environment.ProcessId), mirroring the
    /// macOS `frontmost.processIdentifier != ownPID` check — NOT by comparing the
    /// handle against a single HWND snapshot taken at launch. JVoice is a tray app
    /// with no window of its own at startup, so such a snapshot is just whatever app
    /// was foreground when JVoice launched (e.g. the terminal it was launched from);
    /// comparing against it silently mis-rejected real paste targets, which was the
    /// cause of "it didn't paste where I clicked, especially in a terminal".
    public static IntPtr ResolveTargetWindow(IntPtr currentForeground, bool currentForegroundIsSelf, IntPtr lastNonSelf)
    {
        if (currentForeground != IntPtr.Zero && !currentForegroundIsSelf)
            return currentForeground;
        return lastNonSelf; // may be Zero → caller surfaces "no target app"
    }

    /// Ports updateHUD's menu-bar mirror switch.
    public static TrayIconActivity HudToTray(HudStateKind kind) => kind switch
    {
        HudStateKind.Recording => TrayIconActivity.Recording,
        HudStateKind.PreparingModel or HudStateKind.DownloadingModel or HudStateKind.Transcribing
            => TrayIconActivity.Transcribing,
        _ => TrayIconActivity.Idle, // Idle, Done, Error
    };

    /// Ports scheduleHUDReset default delays.
    public static int HudResetDelayMs(HudStateKind kind) => kind switch
    {
        HudStateKind.Error => 3000,
        HudStateKind.Notice => 3000, // Mac showTourNotice: 3 s
        _ => 1000,
    };

    /// §7 #44 — may a hotkey press (with no recording active) START a new recording?
    /// Ports BOTH of Swift toggleRecording's start-branch guards:
    ///   guard !isStartingRecording else { return }
    ///   guard !transcriptionManager.isTranscribing else { return }   // ← the port had DROPPED this
    /// The second guard is what makes a pending transcript outrank a new start request. Without it
    /// (2026-07-23): a key auto-repeat 313 ms after the stop press hit ToggleRecording's start
    /// branch, which cancelled the still-in-flight whole-file decode of a finished 165 s dictation
    /// — silently, because that cancel lands in the "user moved on" OperationCanceledException
    /// handler — and the accidental 3.7 s re-recording pasted "*referred*" instead. Test-locked so
    /// the guard can never be dropped again.
    public static bool CanStartRecording(bool isStartingRecording, bool isTranscribing)
        => !isStartingRecording && !isTranscribing;

    /// The single decision behind ToggleRecording (Mac 8ea5088 <c>pressAction</c>). Recording wins over
    /// starting (both are briefly true at the end of a start), so a press right after the mic opened is
    /// a stop; a press while the mic is still opening stops it once it opens; any press while the
    /// previous dictation is being transcribed/pasted is ignored — it never cancels it.
    public static PressAction PressAction(bool isRecording, bool isStartingRecording, bool isStoppingRecording, bool isTranscribing)
    {
        if (isRecording) return isStoppingRecording ? Core.PressAction.Ignore : Core.PressAction.Stop;
        if (isStartingRecording) return Core.PressAction.StopOnceOpened;
        return CanStartRecording(false, isTranscribing) ? Core.PressAction.Start : Core.PressAction.Ignore;
    }

    /// A paste that didn't land never loses the dictation (Mac 8ea5088): the text goes to the clipboard
    /// (when it's free) and to Recent Transcripts, and the pill says where it is.
    public static string UnpastedMessage(PasteFailure failure) => failure switch
    {
        PasteFailure.AccessDenied => "Can't paste into an admin window — the text is on your clipboard (Ctrl+V).",
        PasteFailure.ClipboardLocked => "Clipboard was busy — the text is in Recent Transcripts.",
        _ => "Couldn't paste into this app — the text is on your clipboard (Ctrl+V).",
    };
}
