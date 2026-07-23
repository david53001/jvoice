using JVoice.Core;
using JVoice.Core.Models;
using Xunit;

namespace JVoice.Tests;

public class CoordinatorDecisionsTests
{
    private static readonly IntPtr AppA = new(2);
    private static readonly IntPtr AppB = new(3);

    [Fact]
    public void Resolve_UsesForeground_WhenNotSelf()
        => Assert.Equal(AppA, CoordinatorDecisions.ResolveTargetWindow(AppA, currentForegroundIsSelf: false, AppB));

    [Fact]
    public void Resolve_FallsBackToLastNonSelf_WhenForegroundIsSelf()
        => Assert.Equal(AppB, CoordinatorDecisions.ResolveTargetWindow(AppA, currentForegroundIsSelf: true, AppB));

    [Fact]
    public void Resolve_FallsBackToLastNonSelf_WhenForegroundIsZero()
        => Assert.Equal(AppB, CoordinatorDecisions.ResolveTargetWindow(IntPtr.Zero, currentForegroundIsSelf: false, AppB));

    [Fact]
    public void Resolve_ReturnsZero_WhenNothingUsable()
        => Assert.Equal(IntPtr.Zero, CoordinatorDecisions.ResolveTargetWindow(AppA, currentForegroundIsSelf: true, IntPtr.Zero));

    // Regression for "it didn't paste where I clicked, especially in a terminal": the SAME handle
    // value resolves differently based purely on whether it belongs to JVoice — proving the
    // self-decision is by process OWNERSHIP, not handle identity. The old code snapshotted one HWND
    // at launch and compared handles, so the terminal JVoice was launched from was mis-rejected as
    // "self" and its (correct, live) foreground handle was thrown away in favour of a stale fallback.
    [Theory]
    [InlineData(false)] // a foreign foreground window IS the paste target
    [InlineData(true)]  // our own window → fall back to the last non-self foreground
    public void Resolve_SelfDecisionIsByOwnership_NotHandleIdentity(bool isSelf)
        => Assert.Equal(isSelf ? AppB : AppA,
            CoordinatorDecisions.ResolveTargetWindow(AppA, currentForegroundIsSelf: isSelf, AppB));

    [Theory]
    [InlineData(HudStateKind.Recording, TrayIconActivity.Recording)]
    [InlineData(HudStateKind.PreparingModel, TrayIconActivity.Transcribing)]
    [InlineData(HudStateKind.DownloadingModel, TrayIconActivity.Transcribing)]
    [InlineData(HudStateKind.Transcribing, TrayIconActivity.Transcribing)]
    [InlineData(HudStateKind.Idle, TrayIconActivity.Idle)]
    [InlineData(HudStateKind.Done, TrayIconActivity.Idle)]
    [InlineData(HudStateKind.Error, TrayIconActivity.Idle)]
    public void HudToTray_Maps(HudStateKind kind, TrayIconActivity expected)
        => Assert.Equal(expected, CoordinatorDecisions.HudToTray(kind));

    [Theory]
    [InlineData(HudStateKind.Done, 1000)]
    [InlineData(HudStateKind.Error, 3000)]
    public void HudResetDelay(HudStateKind kind, int ms)
        => Assert.Equal(ms, CoordinatorDecisions.HudResetDelayMs(kind));

    // Swift: only the error path (showError) uses the 3 s delay; every other reset uses the 1 s default.
    [Theory]
    [InlineData(HudStateKind.Idle, 1000)]
    [InlineData(HudStateKind.Recording, 1000)]
    [InlineData(HudStateKind.PreparingModel, 1000)]
    [InlineData(HudStateKind.DownloadingModel, 1000)]
    [InlineData(HudStateKind.Transcribing, 1000)]
    [InlineData(HudStateKind.Done, 1000)]
    [InlineData(HudStateKind.Error, 3000)]
    public void HudResetDelay_AllKinds(HudStateKind kind, int ms)
        => Assert.Equal(ms, CoordinatorDecisions.HudResetDelayMs(kind));

    // Both maps are defined for every kind (never throw), and only the busy kinds map to a non-Idle tray.
    [Fact]
    public void HudToTray_And_ResetDelay_DefinedForEveryKind()
    {
        foreach (HudStateKind k in Enum.GetValues<HudStateKind>())
        {
            var tray = CoordinatorDecisions.HudToTray(k);
            Assert.True(Enum.IsDefined(tray));
            int ms = CoordinatorDecisions.HudResetDelayMs(k);
            Assert.True(ms is 1000 or 3000);
            bool busy = k is HudStateKind.Recording or HudStateKind.PreparingModel
                or HudStateKind.DownloadingModel or HudStateKind.Transcribing;
            Assert.Equal(busy, tray != TrayIconActivity.Idle);
        }
    }

    // The function trusts the caller's contract that lastNonSelf is already non-self (no re-check) —
    // matches Swift's `resolvedTargetPID = lastNonSelfFrontmostPID`.
    [Fact]
    public void Resolve_DoesNotReCheckLastNonSelf_AgainstSelf()
        => Assert.Equal(AppA, CoordinatorDecisions.ResolveTargetWindow(AppA, currentForegroundIsSelf: true, AppA));

    [Fact]
    public void Resolve_ForegroundEqualsLastNonSelf_ReturnsForeground()
        => Assert.Equal(AppA, CoordinatorDecisions.ResolveTargetWindow(AppA, currentForegroundIsSelf: false, AppA));

    // ---- CanStartRecording (§7 #44) ----
    // Ports Swift toggleRecording's `guard !transcriptionManager.isTranscribing else { return }`,
    // which the original Windows port DROPPED. Without it, a start request arriving while a
    // transcription is still in flight cancelled that transcription unheard — on 2026-07-23 a key
    // auto-repeat 313 ms after the stop press silently destroyed a finished 165 s dictation and a
    // 3.7 s accidental re-recording pasted "*referred*" instead. A pending transcript must always
    // outrank a new start request.
    [Fact]
    public void CanStartRecording_Normally_True()
        => Assert.True(CoordinatorDecisions.CanStartRecording(isStartingRecording: false, isTranscribing: false));

    [Fact]
    public void CanStartRecording_WhileTranscribing_False()
        => Assert.False(CoordinatorDecisions.CanStartRecording(isStartingRecording: false, isTranscribing: true));

    [Fact]
    public void CanStartRecording_WhileAlreadyStarting_False()
        => Assert.False(CoordinatorDecisions.CanStartRecording(isStartingRecording: true, isTranscribing: false));

    [Fact]
    public void CanStartRecording_BothBusy_False()
        => Assert.False(CoordinatorDecisions.CanStartRecording(isStartingRecording: true, isTranscribing: true));
}
