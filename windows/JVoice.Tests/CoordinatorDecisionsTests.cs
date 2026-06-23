using JVoice.Core;
using JVoice.Core.Models;
using Xunit;

namespace JVoice.Tests;

public class CoordinatorDecisionsTests
{
    private static readonly IntPtr Self = new(1);
    private static readonly IntPtr AppA = new(2);
    private static readonly IntPtr AppB = new(3);

    [Fact]
    public void Resolve_UsesForeground_WhenNotSelf()
        => Assert.Equal(AppA, CoordinatorDecisions.ResolveTargetWindow(AppA, Self, AppB));

    [Fact]
    public void Resolve_FallsBackToLastNonSelf_WhenForegroundIsSelf()
        => Assert.Equal(AppB, CoordinatorDecisions.ResolveTargetWindow(Self, Self, AppB));

    [Fact]
    public void Resolve_FallsBackToLastNonSelf_WhenForegroundIsZero()
        => Assert.Equal(AppB, CoordinatorDecisions.ResolveTargetWindow(IntPtr.Zero, Self, AppB));

    [Fact]
    public void Resolve_ReturnsZero_WhenNothingUsable()
        => Assert.Equal(IntPtr.Zero, CoordinatorDecisions.ResolveTargetWindow(Self, Self, IntPtr.Zero));

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
        => Assert.Equal(Self, CoordinatorDecisions.ResolveTargetWindow(Self, Self, Self));

    [Fact]
    public void Resolve_ForegroundEqualsLastNonSelf_ReturnsForeground()
        => Assert.Equal(AppA, CoordinatorDecisions.ResolveTargetWindow(AppA, Self, AppA));
}
