using JVoice.Core.Models;

namespace JVoice.Core;

/// Pure decision logic extracted from the (UI-thread) VoiceCoordinator so it
/// is unit-testable from net9.0 JVoice.Tests (which cannot reference the
/// net9.0-windows JVoice.App). The WPF coordinator calls these.
public enum TrayIconActivity { Idle, Recording, Transcribing }

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
        _ => 1000,
    };
}
