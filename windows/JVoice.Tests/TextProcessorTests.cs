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

    // ===== Code mode — Windows-only ToneStyle.Code (app-aware "code mode" for terminals/IDEs) =====
    // Minimal formatting: preserve casing, symbols and terminal punctuation as spoken; NO forced
    // capitalization, NO added period, NO lowercasing. Corrections/filler-removal still apply.

    [Fact]
    public void Code_PreservesCasingAndSymbols_NoReformat()
        => Assert.Equal("MyClass.doThing()",
            TextProcessor.Process("MyClass.doThing()", ToneStyle.Code, Empty, false, Array.Empty<string>()));

    [Fact]
    public void Code_DoesNotAddTerminalPeriod()
        => Assert.Equal("run the build",
            TextProcessor.Process("run the build", ToneStyle.Code, Empty, false, Array.Empty<string>()));

    [Fact]
    public void Code_DoesNotStripTerminalPunctuation()
        => Assert.Equal("git commit.",
            TextProcessor.Process("git commit.", ToneStyle.Code, Empty, false, Array.Empty<string>()));

    [Fact]
    public void Code_DoesNotLowercase()
        => Assert.Equal("Open API URL",
            TextProcessor.Process("Open API URL", ToneStyle.Code, Empty, false, Array.Empty<string>()));

    [Fact]
    public void Code_StillHonorsFillerRemoval()
        => Assert.Equal("run the build",
            TextProcessor.Process("um run the build", ToneStyle.Code, Empty, true, Array.Empty<string>()));

    [Fact]
    public void Code_DisplayName_IsCode()
        => Assert.Equal("Code", ToneStyle.Code.DisplayName());

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

    // --- Swift-parity vectors for extractCorrections (Tests/JVoiceTests/LastTranscriptTests.swift) ---

    [Fact]
    public void ExtractCorrections_SameWordCount_CaseChange()
    {
        var result = TextProcessor.ExtractCorrections("python is great", "Python is great");
        Assert.Single(result);
        Assert.Contains("Python", result);
    }

    [Fact]
    public void ExtractCorrections_DifferentWordCount_Merge()
    {
        var result = TextProcessor.ExtractCorrections("mine craft is cool", "Minecraft is cool");
        Assert.Contains("Minecraft", result);
    }

    [Fact]
    public void ExtractCorrections_NoChange_ReturnsEmpty()
    {
        var result = TextProcessor.ExtractCorrections("hello world", "hello world");
        Assert.Empty(result);
    }

    [Fact]
    public void ExtractCorrections_MultipleChanges()
    {
        var result = TextProcessor.ExtractCorrections("use react every day", "use React every day");
        Assert.Contains("React", result);
    }

    // Swift splits words on CharacterSet.whitespaces (tab + Unicode Space_Separator) â€” which
    // deliberately EXCLUDES newlines. A newline must NOT be treated as a word boundary, so a
    // "word" that contains a newline stays intact (mirrors TextProcessor.swift extractCorrections).
    [Fact]
    public void ExtractCorrections_NewlineIsNotAWordBoundary()
    {
        var result = TextProcessor.ExtractCorrections("the\nMacOS thing", "the\nmacOS thing");
        Assert.Equal(new[] { "the\nmacOS" }, result);
    }

    // Tab IS a word boundary in Swift's .whitespaces (U+0009), same as in Split(null).
    [Fact]
    public void ExtractCorrections_TabIsAWordBoundary()
    {
        var result = TextProcessor.ExtractCorrections("python\tis great", "Python\tis great");
        Assert.Single(result);
        Assert.Contains("Python", result);
    }

    // ===== Swift-parity vectors (TextProcessorTests.swift) the C# suite was missing =====

    [Fact]
    public void AppliesCorrections_Builtins()
        => Assert.Equal("please use JVoice with WhisperKit",
            TextProcessor.Process("please use j voice with whisper kit", ToneStyle.Casual));

    [Fact]
    public void UserDictionary_AppliedDuringProcess()
    {
        var dict = TextProcessor.BuildUserDictionary(new[] { "Claude" });
        Assert.Equal("I use Claude every day",
            TextProcessor.Process("I use claude every day", ToneStyle.Casual, dict));
    }

    [Fact]
    public void BuiltInDictionary_WinsOverUserEntry()
    {
        var dict = TextProcessor.BuildUserDictionary(new[] { "jvoice override" });
        Assert.False(dict.ContainsKey("jvoice"));
    }

    [Fact]
    public void UserDictionary_GeneratesCollapsedVariant()
    {
        var dict = TextProcessor.BuildUserDictionary(new[] { "VS Code" });
        Assert.Equal("VS Code", dict["vscode"]);
    }

    // Custom replacements must be inserted LITERALLY â€” never interpreted as regex
    // backreferences ($1) or escapes (\). Mirrors the three Swift "doesNotInjectBackreference" tests.
    [Fact]
    public void CustomWord_DollarSign_IsLiteral()
        => Assert.Equal("the price is $ortable",
            TextProcessor.Process("the price is portable", ToneStyle.Casual,
                new Dictionary<string, string> { ["portable"] = "$ortable" }));

    [Fact]
    public void CustomWord_Backslash_IsLiteral()
        => Assert.Equal(@"save to C:\path",
            TextProcessor.Process("save to cpath", ToneStyle.Casual,
                new Dictionary<string, string> { ["cpath"] = @"C:\path" }));

    [Fact]
    public void CustomWord_GroupReference_IsLiteral()
        => Assert.Contains("$1unit",
            TextProcessor.Process("send the unit", ToneStyle.Casual,
                new Dictionary<string, string> { ["unit"] = "$1unit" }));

    [Theory]
    [InlineData("Um, I was thinking", "I was thinking")]
    [InlineData("I was uh thinking", "I was thinking")]
    [InlineData("hmm I need to go", "I need to go")]
    [InlineData("I was thinking, um", "I was thinking")]
    [InlineData("I was umm uhh really", "I was really")]
    [InlineData("Umm, ahh, er, I see", "I see")]
    [InlineData("I'd like to go", "I'd like to go")]
    [InlineData("The error was clear", "The error was clear")]
    [InlineData("", "")]
    public void RemoveDisfluencies_Parity(string input, string expected)
        => Assert.Equal(expected, TextProcessor.RemoveDisfluencies(input));

    [Theory]
    [InlineData("Hello World From Me", "hello world from me.")]
    [InlineData("this has no ending", "this has no ending.")]
    [InlineData("Is It Working?", "is it working?")]
    [InlineData("Stop right there!", "stop right there.")]
    [InlineData("well,, you know,, it works", "well, you know, it works.")]
    [InlineData("first, second, third,", "first, second, third.")]
    [InlineData("use j voice now", "use JVoice now.")]
    public void VeryCasual_Parity(string input, string expected)
        => Assert.Equal(expected, TextProcessor.Process(input, ToneStyle.VeryCasual));

    [Fact]
    public void VeryCasual_PreservesCustomWordCasing()
        => Assert.Equal("open JVoice settings.",
            TextProcessor.Process("Open Jay Voice Settings", ToneStyle.VeryCasual, Empty, false, new[] { "JVoice" }));

    [Fact]
    public void Process_AppliesPhoneticVocabularyCorrection()
        => Assert.Equal("open JVoice now",
            TextProcessor.Process("open jay voice now", ToneStyle.Casual, Empty, false, new[] { "JVoice" }));

    [Theory]
    [InlineData(" Thanks for watching!", "")]
    [InlineData("Subscribe to my channel.", "")]
    [InlineData("[BLANK_TEXT]", "")]
    [InlineData("BLANK_TEXT", "")]
    [InlineData(",", "")]
    [InlineData(" . ", "")]
    public void RemoveWhisperHallucinations_Parity(string input, string expected)
        => Assert.Equal(expected, TextProcessor.RemoveWhisperHallucinations(input));

    [Theory]
    [InlineData("OK.")]
    [InlineData("Hi")]
    [InlineData("Thanks for the help, please send the file by Friday.")]
    public void RemoveWhisperHallucinations_PreservesRealSpeech(string input)
        => Assert.Equal(input, TextProcessor.RemoveWhisperHallucinations(input));

    // ===== Edge cases the suite missed: empty / whitespace / idempotency =====

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData("\n\t ")]
    public void Process_EmptyOrWhitespace_AllTones_ReturnsEmpty(string input)
    {
        Assert.Equal("", TextProcessor.Process(input, ToneStyle.Casual));
        Assert.Equal("", TextProcessor.Process(input, ToneStyle.Formal));
        Assert.Equal("", TextProcessor.Process(input, ToneStyle.VeryCasual));
    }

    [Fact]
    public void StripDecoderArtifacts_EmptyAndAllArtifact()
    {
        Assert.Equal("", TextProcessor.StripDecoderArtifacts(""));
        Assert.Equal("", TextProcessor.StripDecoderArtifacts("[BLANK_AUDIO]"));
        Assert.Equal("", TextProcessor.StripDecoderArtifacts("[MUSIC] [APPLAUSE]"));
    }

    [Fact]
    public void StripDecoderArtifacts_IsIdempotent()
    {
        const string input = "hello [BLANK_AUDIO] there [MUSIC] world";
        var once = TextProcessor.StripDecoderArtifacts(input);
        var twice = TextProcessor.StripDecoderArtifacts(once);
        Assert.Equal(once, twice);
        Assert.Equal("hello there world", once);
    }

    // Deterministic fuzz: the brain's pure string transforms must NEVER throw on
    // arbitrary/adversarial input (control chars, brackets, unicode, newlines), and
    // StripDecoderArtifacts must be idempotent on every input.
    [Fact]
    public void Fuzz_PureTransforms_NeverThrow_AndStripIsIdempotent()
    {
        const string alphabet = "ab CD_[]().,!?\t\n\r umuherahhmm jvoice \u00e9\u00a0\u2028 JVoice$1\\";
        var rng = new Random(20260623);
        for (int iter = 0; iter < 400; iter++)
        {
            int len = rng.Next(0, 40);
            var sb = new System.Text.StringBuilder(len);
            for (int j = 0; j < len; j++) sb.Append(alphabet[rng.Next(alphabet.Length)]);
            string s = sb.ToString();

            // None of these may throw on any input.
            _ = TextProcessor.Process(s, ToneStyle.Casual);
            _ = TextProcessor.Process(s, ToneStyle.Formal);
            _ = TextProcessor.Process(s, ToneStyle.VeryCasual);
            _ = TextProcessor.RemoveDisfluencies(s);
            _ = TextProcessor.RemoveWhisperHallucinations(s);
            _ = TextProcessor.ExtractCorrections(s, s);
            _ = TextProcessor.SpokenVariants(s);

            // StripDecoderArtifacts is idempotent.
            var once = TextProcessor.StripDecoderArtifacts(s);
            Assert.Equal(once, TextProcessor.StripDecoderArtifacts(once));
        }
    }
}
