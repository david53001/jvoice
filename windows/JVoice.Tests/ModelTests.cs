using JVoice.Core.Models;
using Xunit;

namespace JVoice.Tests;

public class ModelTests
{
    [Theory]
    [InlineData(ToneStyle.Casual, "Casual")]
    [InlineData(ToneStyle.Formal, "Formal")]
    [InlineData(ToneStyle.VeryCasual, "Very Casual")]
    public void ToneStyle_DisplayName(ToneStyle s, string expected)
        => Assert.Equal(expected, s.DisplayName());

    [Theory]
    [InlineData(TranscriptionLanguage.English, "en", "English")]
    [InlineData(TranscriptionLanguage.Romanian, "ro", "Romanian")]
    public void Language_CodesAndNames(TranscriptionLanguage l, string code, string name)
    {
        Assert.Equal(code, l.WhisperCode());
        Assert.Equal(name, l.DisplayName());
    }

    [Theory]
    [InlineData(WhisperModelOption.Tiny, "Tiny", "ggml-tiny.bin")]
    [InlineData(WhisperModelOption.Base, "Base", "ggml-base.bin")]
    [InlineData(WhisperModelOption.Small, "Small", "ggml-small.bin")]
    [InlineData(WhisperModelOption.LargeTurbo, "Large", "ggml-large-v3-turbo-q5_0.bin")]
    public void Model_DisplayAndFile(WhisperModelOption m, string display, string file)
    {
        Assert.Equal(display, m.DisplayName());
        Assert.Equal(file, m.GgmlFileName());
    }

    [Fact]
    public void HudState_Factories()
    {
        Assert.Equal(HudStateKind.Recording, HudState.Recording.Kind);
        Assert.Equal("Pasted", HudState.Done("hi").Headline);
        Assert.Equal("hi", HudState.Done("hi").Payload);
        Assert.False(HudState.Idle.IsVisible);
        Assert.True(HudState.Recording.IsVisible);
        Assert.True(HudState.Transcribing.IsBusy);
        Assert.True(HudState.Error("x").IsTerminal);
    }
}
