using JVoice.Core.Models;
using JVoice.Core.Text;
using Xunit;

namespace JVoice.Tests;

public class TextProcessorTests
{
    private static readonly Dictionary<string, string> Empty = new();

    [Fact]
    public void Casual_StripsTerminalPunctuation_NoCapitalize()
        => Assert.Equal("hello world",
            TextProcessor.Process("hello world.", ToneStyle.Casual, Empty, false, Array.Empty<string>()));

    [Fact]
    public void Formal_CapitalizesAndAddsPeriod()
        => Assert.Equal("Hello world.",
            TextProcessor.Process("hello world", ToneStyle.Formal, Empty, false, Array.Empty<string>()));

    [Fact]
    public void VeryCasual_Lowercases_ButKeepsCorrectionCasing()
    {
        // veryCasual lowercases BEFORE corrections, so custom/builtin casing survives.
        var outp = TextProcessor.Process("I love JVOICE", ToneStyle.VeryCasual, Empty, false, Array.Empty<string>());
        Assert.Contains("JVoice", outp);
    }

    [Fact]
    public void RemoveFillerWords_StripsDisfluencies()
        => Assert.Equal("so can we move",
            TextProcessor.Process("so um can we uh move", ToneStyle.Casual, Empty, true, Array.Empty<string>()));

    [Fact]
    public void BuiltinDictionary_FixesKnownSpellings()
        => Assert.Equal("WhisperKit",
            TextProcessor.Process("whisper kit", ToneStyle.Casual, Empty, false, Array.Empty<string>()));

    [Theory]
    [InlineData("hello [BLANK_AUDIO] world", "hello world")]
    [InlineData("[MUSIC] hi", "hi")]
    [InlineData("a [APPLAUSE] b", "a b")]
    public void StripDecoderArtifacts_RemovesBracketSentinels(string input, string expected)
        => Assert.Equal(expected, TextProcessor.StripDecoderArtifacts(input));

    [Fact]
    public void StripDecoderArtifacts_PreservesLowercaseBracket()
        => Assert.Equal("see [note] here", TextProcessor.StripDecoderArtifacts("see [note] here"));

    [Theory]
    [InlineData("Thanks for watching!", "")]
    [InlineData("Thank you.", "")]
    [InlineData(".", "")]
    public void RemoveWhisperHallucinations_NukesSentinels(string input, string expected)
        => Assert.Equal(expected, TextProcessor.RemoveWhisperHallucinations(input));

    [Fact]
    public void RemoveWhisperHallucinations_KeepsRealSpeech()
        => Assert.Equal("thank you for the help",
            TextProcessor.RemoveWhisperHallucinations("thank you for the help"));

    [Fact]
    public void BuildUserDictionary_MapsSpokenVariants()
    {
        var dict = TextProcessor.BuildUserDictionary(new[] { "VS Code" });
        Assert.True(dict.ContainsKey("vs code"));
        Assert.Equal("VS Code", dict["vs code"]);
    }

    [Fact]
    public void ExtractCorrections_FindsNewWords()
    {
        var added = TextProcessor.ExtractCorrections("i use vs code", "i use VSCode");
        Assert.Contains("VSCode", added);
    }
}
