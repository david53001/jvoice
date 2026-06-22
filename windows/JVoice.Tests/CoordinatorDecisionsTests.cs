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
}
