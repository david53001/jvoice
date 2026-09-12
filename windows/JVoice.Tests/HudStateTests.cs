using JVoice.Core.Models;
using Xunit;

namespace JVoice.Tests;

public class HudStateTests
{
    private static HudState ForKind(HudStateKind k) => k switch
    {
        HudStateKind.Idle => HudState.Idle,
        HudStateKind.Recording => HudState.Recording,
        HudStateKind.PreparingModel => HudState.PreparingModel,
        HudStateKind.DownloadingModel => HudState.DownloadingModel(0.5),
        HudStateKind.Transcribing => HudState.Transcribing,
        HudStateKind.Done => HudState.Done("x"),
        HudStateKind.Error => HudState.Error("e"),
        _ => HudState.Idle,
    };

    // Headline matches Swift HUDState.headline exactly (the 6 Swift kinds + the new DownloadingModel).
    [Theory]
    [InlineData(HudStateKind.Idle, "Ready")]
    [InlineData(HudStateKind.Recording, "Listening")]
    [InlineData(HudStateKind.PreparingModel, "Preparing Model")]
    [InlineData(HudStateKind.DownloadingModel, "Downloading Model")]
    [InlineData(HudStateKind.Transcribing, "Transcribing")]
    [InlineData(HudStateKind.Done, "Pasted")]
    [InlineData(HudStateKind.Error, "Something Went Wrong")]
    public void Headline_MatchesSwift(HudStateKind k, string expected)
        => Assert.Equal(expected, ForKind(k).Headline);

    // IsVisible: every kind except Idle is visible (Swift parity; DownloadingModel is visible).
    [Theory]
    [InlineData(HudStateKind.Idle, false)]
    [InlineData(HudStateKind.Recording, true)]
    [InlineData(HudStateKind.PreparingModel, true)]
    [InlineData(HudStateKind.DownloadingModel, true)]
    [InlineData(HudStateKind.Transcribing, true)]
    [InlineData(HudStateKind.Done, true)]
    [InlineData(HudStateKind.Error, true)]
    public void IsVisible_PerKind(HudStateKind k, bool expected)
        => Assert.Equal(expected, ForKind(k).IsVisible);

    // IsBusy: recording/preparing/downloading/transcribing (Swift parity; DownloadingModel is busy).
    [Theory]
    [InlineData(HudStateKind.Idle, false)]
    [InlineData(HudStateKind.Recording, true)]
    [InlineData(HudStateKind.PreparingModel, true)]
    [InlineData(HudStateKind.DownloadingModel, true)]
    [InlineData(HudStateKind.Transcribing, true)]
    [InlineData(HudStateKind.Done, false)]
    [InlineData(HudStateKind.Error, false)]
    public void IsBusy_PerKind(HudStateKind k, bool expected)
        => Assert.Equal(expected, ForKind(k).IsBusy);

    // IsTerminal: only Done/Error (Swift parity).
    [Theory]
    [InlineData(HudStateKind.Idle, false)]
    [InlineData(HudStateKind.Recording, false)]
    [InlineData(HudStateKind.PreparingModel, false)]
    [InlineData(HudStateKind.DownloadingModel, false)]
    [InlineData(HudStateKind.Transcribing, false)]
    [InlineData(HudStateKind.Done, true)]
    [InlineData(HudStateKind.Error, true)]
    public void IsTerminal_PerKind(HudStateKind k, bool expected)
        => Assert.Equal(expected, ForKind(k).IsTerminal);

    [Fact]
    public void Payload_OnlyDoneAndErrorCarry()
    {
        Assert.Equal("done-text", HudState.Done("done-text").Payload);
        Assert.Equal("err-text", HudState.Error("err-text").Payload);
        Assert.Null(HudState.Idle.Payload);
        Assert.Null(HudState.Recording.Payload);
        Assert.Null(HudState.PreparingModel.Payload);
        Assert.Null(HudState.DownloadingModel(0.5).Payload);
        Assert.Null(HudState.Transcribing.Payload);
    }

    [Fact]
    public void Progress_OnlyDownloadingModelCarries()
    {
        Assert.Equal(0.42, HudState.DownloadingModel(0.42).Progress);
        Assert.Null(HudState.Recording.Progress);
        Assert.Null(HudState.Done("x").Progress);
        Assert.Null(HudState.Idle.Progress);
    }

    // Error subtitle falls back to a generic message when the payload is empty (Swift parity).
    [Fact]
    public void Subtitle_DoneIsNull_ErrorFallsBackWhenEmpty()
    {
        Assert.Null(HudState.Done("x").Subtitle);
        Assert.Equal("boom", HudState.Error("boom").Subtitle);
        Assert.Equal("Something went wrong", HudState.Error("").Subtitle);
    }

    // Every non-Done kind has a non-empty subtitle (the exact Windows copy is intentional UI wording).
    [Theory]
    [InlineData(HudStateKind.Idle)]
    [InlineData(HudStateKind.Recording)]
    [InlineData(HudStateKind.PreparingModel)]
    [InlineData(HudStateKind.DownloadingModel)]
    [InlineData(HudStateKind.Transcribing)]
    [InlineData(HudStateKind.Error)]
    public void Subtitle_NonDoneKindsHaveText(HudStateKind k)
        => Assert.False(string.IsNullOrEmpty(ForKind(k).Subtitle));

    // Structural invariants that must hold for EVERY kind: a headline always exists; busy and terminal
    // are mutually exclusive; and a state is visible iff it is busy or terminal (only Idle is hidden).
    [Fact]
    public void Invariants_HoldForEveryKind()
    {
        foreach (HudStateKind k in Enum.GetValues<HudStateKind>())
        {
            var s = ForKind(k);
            Assert.Equal(k, s.Kind);
            Assert.False(string.IsNullOrEmpty(s.Headline));
            Assert.False(s.IsBusy && s.IsTerminal);
            Assert.Equal(s.IsBusy || s.IsTerminal, s.IsVisible);
        }
    }
}
