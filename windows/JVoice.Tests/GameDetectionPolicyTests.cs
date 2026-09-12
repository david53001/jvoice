using JVoice.Core;
using JVoice.Core.Models;
using Xunit;

namespace JVoice.Tests;

// Truth-table coverage for GameDetectionPolicy.ShouldSuppress.
// All Win32 signal-gathering lives in the App layer; this tests only the pure brain.
public class GameDetectionPolicyTests
{
    // Convenience: all signals false (the "nothing detected" baseline).
    private static GameSignals None => new(false, false, false, false, false, false);

    // All game signals true, force-flags false (maximum signal, no user override).
    private static GameSignals AllGame => new(
        D3DFullscreen: true, RegisteredGame: true, KnownGamePath: true,
        ForegroundIsFullscreen: true, UserForceGame: false, UserForceNotGame: false);

    // ---- Off mode: never suppresses (except UserForceGame overrides Off) ----

    [Fact]
    public void Off_NoSignals_False()
        => Assert.False(GameDetectionPolicy.ShouldSuppress(None, GameDetectionMode.Off));

    [Fact]
    public void Off_AllGameSignalsTrue_False()
        => Assert.False(GameDetectionPolicy.ShouldSuppress(AllGame, GameDetectionMode.Off));

    [Theory]
    [InlineData(false, false, false, false)] // no confident signals, still off
    [InlineData(true,  false, false, false)] // D3D only
    [InlineData(false, true,  false, false)] // RegisteredGame only
    [InlineData(false, false, true,  false)] // KnownGamePath only
    [InlineData(false, false, false, true)]  // ForegroundFullscreen only
    public void Off_IndividualSignals_AlwaysFalse(bool d3d, bool reg, bool known, bool full)
    {
        var s = new GameSignals(d3d, reg, known, full, UserForceGame: false, UserForceNotGame: false);
        Assert.False(GameDetectionPolicy.ShouldSuppress(s, GameDetectionMode.Off));
    }

    // UserForceGame beats Off mode — explicit deny overrides the mode setting.
    [Fact]
    public void Off_UserForceGame_True()
    {
        var s = new GameSignals(false, false, false, false, UserForceGame: true, UserForceNotGame: false);
        Assert.True(GameDetectionPolicy.ShouldSuppress(s, GameDetectionMode.Off));
    }

    // ---- UserForceNotGame: explicit allow wins over everything ----

    [Theory]
    [InlineData(false)] // Off
    [InlineData(true)]  // Balanced
    // Note: Aggressive = 2 tested separately below
    public void UserForceNotGame_WinsOverMode_Balanced(bool balanced)
    {
        var mode = balanced ? GameDetectionMode.Balanced : GameDetectionMode.Off;
        // All game signals true to maximise suppression pressure.
        var s = new GameSignals(true, true, true, true, UserForceGame: false, UserForceNotGame: true);
        Assert.False(GameDetectionPolicy.ShouldSuppress(s, mode));
    }

    [Fact]
    public void UserForceNotGame_WinsOverAggressive_False()
    {
        var s = new GameSignals(true, true, true, true, UserForceGame: false, UserForceNotGame: true);
        Assert.False(GameDetectionPolicy.ShouldSuppress(s, GameDetectionMode.Aggressive));
    }

    [Fact]
    public void UserForceNotGame_WinsEvenWhenD3DAndFullscreen_False()
    {
        var s = new GameSignals(D3DFullscreen: true, RegisteredGame: false, KnownGamePath: false,
            ForegroundIsFullscreen: true, UserForceGame: false, UserForceNotGame: true);
        Assert.False(GameDetectionPolicy.ShouldSuppress(s, GameDetectionMode.Aggressive));
    }

    // ---- UserForceGame: explicit deny wins over mode (covered Off above) ----

    [Theory]
    [InlineData(true)]  // Balanced
    [InlineData(false)] // Off (re-tested here for completeness across modes)
    public void UserForceGame_WinsOverMode(bool balanced)
    {
        var mode = balanced ? GameDetectionMode.Balanced : GameDetectionMode.Off;
        var s = new GameSignals(false, false, false, false, UserForceGame: true, UserForceNotGame: false);
        Assert.True(GameDetectionPolicy.ShouldSuppress(s, mode));
    }

    [Fact]
    public void UserForceGame_WinsOverAggressive_True()
    {
        var s = new GameSignals(false, false, false, false, UserForceGame: true, UserForceNotGame: false);
        Assert.True(GameDetectionPolicy.ShouldSuppress(s, GameDetectionMode.Aggressive));
    }

    // ---- Precedence: BOTH force flags set — UserForceNotGame is checked first → false ----

    [Theory]
    [InlineData(GameDetectionMode.Off)]
    [InlineData(GameDetectionMode.Balanced)]
    [InlineData(GameDetectionMode.Aggressive)]
    public void BothForceFlags_NotGameWins_False(GameDetectionMode mode)
    {
        var s = new GameSignals(true, true, true, true, UserForceGame: true, UserForceNotGame: true);
        Assert.False(GameDetectionPolicy.ShouldSuppress(s, mode));
    }

    // ---- Balanced mode: high-confidence signals ----

    [Theory]
    [InlineData(true,  false, false, false, true)]  // D3DFullscreen alone → suppress
    [InlineData(false, true,  false, false, true)]  // RegisteredGame alone → suppress
    [InlineData(false, false, true,  false, true)]  // KnownGamePath alone → suppress
    [InlineData(false, false, false, true,  false)] // ForegroundFullscreen alone → NOT suppress (key guardrail)
    [InlineData(false, false, false, false, false)] // nothing → false
    [InlineData(true,  true,  true,  true,  true)]  // all → true
    public void Balanced_TruthTable(bool d3d, bool reg, bool known, bool full, bool expected)
    {
        var s = new GameSignals(d3d, reg, known, full, UserForceGame: false, UserForceNotGame: false);
        Assert.Equal(expected, GameDetectionPolicy.ShouldSuppress(s, GameDetectionMode.Balanced));
    }

    // ---- Aggressive mode: also suppresses on bare fullscreen ----

    [Theory]
    [InlineData(true,  false, false, false, true)]  // D3DFullscreen alone → true
    [InlineData(false, true,  false, false, true)]  // RegisteredGame alone → true
    [InlineData(false, false, true,  false, true)]  // KnownGamePath alone → true
    [InlineData(false, false, false, true,  true)]  // ForegroundFullscreen alone → true (unlike Balanced)
    [InlineData(false, false, false, false, false)] // nothing → false
    [InlineData(true,  true,  true,  true,  true)]  // all → true
    public void Aggressive_TruthTable(bool d3d, bool reg, bool known, bool full, bool expected)
    {
        var s = new GameSignals(d3d, reg, known, full, UserForceGame: false, UserForceNotGame: false);
        Assert.Equal(expected, GameDetectionPolicy.ShouldSuppress(s, GameDetectionMode.Aggressive));
    }

    // Confirm the key behavioural difference: ForegroundFullscreen alone differs between modes.
    [Fact]
    public void FullscreenAlone_Balanced_False_Aggressive_True()
    {
        var s = new GameSignals(false, false, false, ForegroundIsFullscreen: true,
            UserForceGame: false, UserForceNotGame: false);
        Assert.False(GameDetectionPolicy.ShouldSuppress(s, GameDetectionMode.Balanced));
        Assert.True(GameDetectionPolicy.ShouldSuppress(s, GameDetectionMode.Aggressive));
    }

    // ---- Regression: Off mode stays off regardless of which single signal fires ----

    [Theory]
    [InlineData(true,  false, false, false)]
    [InlineData(false, true,  false, false)]
    [InlineData(false, false, true,  false)]
    [InlineData(false, false, false, true)]
    public void Off_SingleSignal_AlwaysFalse(bool d3d, bool reg, bool known, bool full)
    {
        var s = new GameSignals(d3d, reg, known, full, UserForceGame: false, UserForceNotGame: false);
        Assert.False(GameDetectionPolicy.ShouldSuppress(s, GameDetectionMode.Off));
    }
}
