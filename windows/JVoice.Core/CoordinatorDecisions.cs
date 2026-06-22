using JVoice.Core.Models;

namespace JVoice.Core;

/// Pure decision logic extracted from the (UI-thread) VoiceCoordinator so it
/// is unit-testable from net9.0 JVoice.Tests (which cannot reference the
/// net9.0-windows JVoice.App). The WPF coordinator calls these.
public enum TrayIconActivity { Idle, Recording, Transcribing }

public static class CoordinatorDecisions
{
    /// Ports VoiceCoordinator.stopRecordingAndTranscribe's target resolution:
    /// frontmost-if-not-self else last-non-self frontmost.
    public static IntPtr ResolveTargetWindow(IntPtr currentForeground, IntPtr self, IntPtr lastNonSelf)
    {
        if (currentForeground != IntPtr.Zero && currentForeground != self)
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
