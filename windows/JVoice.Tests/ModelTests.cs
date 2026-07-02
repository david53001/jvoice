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

    // ===== WhisperModelOption (+GGML map) — parity with WhisperModelOptionTests.swift =====

    // Swift largeTurboIsOfferedAsAModelOption + completeness: exactly the 4 cases exist.
    [Fact]
    public void Model_AllFourCasesPresent()
    {
        var all = Enum.GetValues<WhisperModelOption>();
        Assert.Equal(4, all.Length);
        Assert.Contains(WhisperModelOption.Tiny, all);
        Assert.Contains(WhisperModelOption.Base, all);
        Assert.Contains(WhisperModelOption.Small, all);
        Assert.Contains(WhisperModelOption.LargeTurbo, all);
    }

    // No two models may map to the same GGML file (a collision would download/cache the wrong model),
    // and every filename is well-formed (ggml-*.bin).
    [Fact]
    public void Model_GgmlFileNames_AreDistinctAndWellFormed()
    {
        var files = Enum.GetValues<WhisperModelOption>().Select(m => m.GgmlFileName()).ToArray();
        Assert.Equal(files.Length, files.Distinct().Count());
        Assert.All(files, f =>
        {
            Assert.StartsWith("ggml-", f);
            Assert.EndsWith(".bin", f);
        });
    }

    // Swift largeTurboHasReadableDisplayName: the raw model identifier must never leak into the UI.
    // (Windows uses its own wording — "Large" — but the no-raw-id invariant still holds.)
    [Theory]
    [InlineData(WhisperModelOption.Tiny)]
    [InlineData(WhisperModelOption.Base)]
    [InlineData(WhisperModelOption.Small)]
    [InlineData(WhisperModelOption.LargeTurbo)]
    public void Model_DisplayName_DoesNotLeakRawIdentifier(WhisperModelOption m)
    {
        var lower = m.DisplayName().ToLowerInvariant();
        Assert.False(string.IsNullOrWhiteSpace(lower));
        Assert.DoesNotContain("ggml", lower);
        Assert.DoesNotContain("q5_0", lower);
        Assert.DoesNotContain("v20240930", lower);
        Assert.DoesNotContain(".bin", lower);
    }

    [Theory]
    [InlineData(WhisperModelOption.Tiny)]
    [InlineData(WhisperModelOption.Base)]
    [InlineData(WhisperModelOption.Small)]
    [InlineData(WhisperModelOption.LargeTurbo)]
    public void Model_Guidance_IsNonEmpty(WhisperModelOption m)
        => Assert.False(string.IsNullOrWhiteSpace(m.Guidance()));

    // Swift largeTurboRoundTripsThroughCodable (C# format): LargeTurbo survives a JSON round-trip.
    [Fact]
    public void Model_LargeTurbo_RoundTripsThroughJson()
    {
        var state = SettingsState.Default with { Model = WhisperModelOption.LargeTurbo };
        var back = SettingsStateJson.Deserialize(SettingsStateJson.Serialize(state));
        Assert.Equal(WhisperModelOption.LargeTurbo, back.Model);
    }
}
