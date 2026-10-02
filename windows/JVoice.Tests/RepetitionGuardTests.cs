using JVoice.Core.Text;
using Xunit;

namespace JVoice.Tests;

public class RepetitionGuardTests
{
    private static readonly string[] Vocab = { "sub agents", "claude", "li-fraumeni", "vs code" };

    [Fact]
    public void Strip_RemovesTrailingRegurgitationLoop()
    {
        const string input = "so the thing about money is that " +
            "sub agents, claude, li-fraumeni, vs code, sub agents, claude, li-fraumeni, vs code, " +
            "sub agents, claude, li-fraumeni, vs code";
        var r = RepetitionGuard.Scrub(input, Vocab);
        Assert.True(r.RemovedRegurgitation);
        Assert.Equal("so the thing about money is that", r.Text);
    }

    [Theory]
    [InlineData("so the answer is 2 times 2 times 2 times 2 times 2 times 2 times 2")]
    [InlineData("2 times 2 times 2 times 2 times 2 times 2 times 2")]
    [InlineData("I told him no no no no no no no no")]
    [InlineData("so the answer is 2 times 2 times 2 times 2 times 2 times 2 times 2 times 2 times 2")]   // 9 operands
    [InlineData("2 times 2 times 2 times 2 times 2 times 2 times 2 times 2 times 2 times 2")]            // 10, no lead-in
    [InlineData("x plus x plus x plus x plus x plus x plus x plus x plus x plus x plus x plus x")]      // 12 operands
    public void Scrub_KeepsARepeatedMathsOrStopwordPhrase(string input)
    {
        var r = RepetitionGuard.Scrub(input, Vocab);
        Assert.False(r.RemovedRegurgitation);
        Assert.Equal(input, r.Text);
    }

    [Fact]
    public void Scrub_LeavesCoherentSpeechUntouched()
    {
        const string input = "i really like using vs code and claude every day for my work here";
        var r = RepetitionGuard.Scrub(input, Vocab);
        Assert.False(r.RemovedRegurgitation);
        Assert.Equal(input, r.Text);
    }

    [Fact]
    public void Scrub_SingleVocabMention_NotStripped()
    {
        const string input = "we studied li-fraumeni syndrome in the lab last year for a long time okay";
        var r = RepetitionGuard.Scrub(input, Vocab);
        Assert.False(r.RemovedRegurgitation);
    }

    [Fact]
    public void Scrub_ShortInput_NeverStripped()
    {
        var r = RepetitionGuard.Scrub("claude claude claude", Vocab); // < MinLoopTokens
        Assert.False(r.RemovedRegurgitation);
    }

    // Fuzz: a coherent prefix + a loop-dominated tail must always strip back to (at
    // least) the prefix. The guard is conservative  it only fires when the trailing
    // run is genuinely loop-dominated  so we construct only loop-dominated tails:
    //   (a) the full 4-phrase cycle (6 tokens/rep) repeated 3..8 (18..48 loop tokens), and
    //   (b) a single-token loop repeated 9..14 (>= the 12-token tail window).
    [Fact]
    public void Fuzz_LoopDominatedTailsAlwaysStripped()
    {
        string[] prefixes =
        {
            "okay so here is the plan for the week ahead everyone",
            "the most important thing to remember about this topic is simple",
            "let me explain how the whole process actually works in practice",
        };
        string[] cycle = { "claude", "sub agents", "li-fraumeni", "vs code" };
        int cases = 0, failures = 0;

        foreach (var prefix in prefixes)
        {
            // (a) full-cycle loops
            for (int reps = 3; reps <= 8; reps++)
            {
                string loop = string.Join(", ",
                    Enumerable.Range(0, reps).SelectMany(_ => cycle));
                string input = prefix + " " + loop;
                var r = RepetitionGuard.Scrub(input, Vocab);
                cases++;
                if (!r.RemovedRegurgitation || r.Text.Length >= input.Length) failures++;
            }
            // (b) single-token loops
            for (int reps = 9; reps <= 14; reps++)
            {
                string loop = string.Join(", ", Enumerable.Repeat("claude", reps));
                string input = prefix + " " + loop;
                var r = RepetitionGuard.Scrub(input, Vocab);
                cases++;
                if (!r.RemovedRegurgitation || r.Text.Length >= input.Length) failures++;
            }
        }

        Assert.True(cases >= 36);
        Assert.Equal(0, failures);
    }

    // Control: a single mention of each vocab phrase inside a long coherent sentence
    // must NEVER be stripped (the inverse of the fuzz).
    [Fact]
    public void Fuzz_SingleMentions_NeverStripped()
    {
        string[] sentences =
        {
            "today i opened vs code and asked claude about the li-fraumeni paper for the lab meeting",
            "my favourite tool is claude and i also run a whole system of sub agents every single day now",
            "we discussed sub agents and vs code at length during the long planning session this afternoon",
        };
        foreach (var s in sentences)
            Assert.False(RepetitionGuard.Scrub(s, Vocab).RemovedRegurgitation);
    }

    // ===== Bug #2: Core must keep marks + ALL number categories (Swift CharacterSet.alphanumerics) =====

    [Fact]
    public void Core_KeepsMarksAndNumberSymbols_LikeSwiftAlphanumerics()
    {
        // Swift core() filters on CharacterSet.alphanumerics (Unicode L* + M* + N*).
        // char.IsLetterOrDigit is only L* + Nd, wrongly dropping combining marks (Mn,
        // here U+0301) and the No number category (here U+00BD = ).
        Assert.Equal("a\u00bd\u0301b", RepetitionGuard.Core("a\u00bd\u0301b"));
    }

    // End-to-end consequence of the Core bug: a repeated No-category token IS a loop in
    // Swift (the token's core is non-empty) but C# dropped it, so the loop went undetected.
    [Fact]
    public void Scrub_NumberSymbolLoop_StrippedLikeSwift()
    {
        string input = "here is a fairly long and coherent sentence that precedes the loop " +
            string.Join(" ", Enumerable.Repeat("\u00bd", 12));
        var r = RepetitionGuard.Scrub(input, Array.Empty<string>());
        Assert.True(r.RemovedRegurgitation);
        Assert.Equal("here is a fairly long and coherent sentence that precedes the loop", r.Text);
    }

    // ===== Swift-parity vectors the C# suite was missing =====

    // The original real-world report: a tariffs dictation that degenerated into a
    // vocabulary loop (with a mangled "la-fa" token tolerated mid-loop).
    [Fact]
    public void Strip_ReportedBug_KeepsSpeech_DropsRegurgitation()
    {
        const string input =
            "so basically what tariffs are is when governments put taxes on imported goods " +
            "and who pays them is the people buying the item from a country that is " +
            "sub agents, claude, li-fraumeni, sub agents, claude, vs code, li-fraumeni, " +
            "sub agents, li-fraumeni, sub agents, li-fraumeni, sub agents, li-fraumeni, " +
            "sub agents, li-fraumeni, sub agents, la-fa, li-fraumeni, sub agents, li-fraumeni";
        var outText = RepetitionGuard.Strip(input, Vocab);
        Assert.StartsWith("so basically what tariffs are", outText);
        Assert.Contains("country", outText);
        Assert.DoesNotContain("li-fraumeni", outText.ToLowerInvariant());
        Assert.DoesNotContain("sub agents", outText.ToLowerInvariant());
        Assert.DoesNotContain(",", outText);
        Assert.True(outText.Length < input.Length / 2);
    }

    [Fact]
    public void Strip_WholeTranscriptLoop_ReducesToEmpty()
        => Assert.Equal("", RepetitionGuard.Strip(
            "claude claude claude claude claude claude claude claude claude claude", new[] { "claude" }));

    [Fact]
    public void Strip_GenericRepetitionLoop_NoVocabulary()
        => Assert.Equal("the meeting is tomorrow afternoon", RepetitionGuard.Strip(
            "the meeting is tomorrow afternoon thanks thanks thanks thanks thanks thanks thanks thanks thanks",
            Array.Empty<string>()));

    [Fact]
    public void Strip_OrdinaryProse_Untouched()
    {
        const string input = "the quick brown fox jumps over the lazy dog and then runs back again to sleep";
        Assert.Equal(input, RepetitionGuard.Strip(input, Array.Empty<string>()));
    }

    [Fact]
    public void Strip_DenseButNonRepetitive_Untouched()
    {
        const string input = "today I paired Claude with VS Code and my sub agents to ship the feature";
        Assert.Equal(input, RepetitionGuard.Strip(input, Vocab));
    }

    [Fact]
    public void Strip_EmptyAndWhitespaceInputs_AreSafe()
    {
        Assert.Equal("", RepetitionGuard.Strip("", Vocab));
        Assert.Equal("hello world", RepetitionGuard.Strip("hello world", Vocab));
    }

    [Fact]
    public void Scrub_FlagsAllLoopAsEmpty()
    {
        var r = RepetitionGuard.Scrub(
            "claude claude claude claude claude claude claude claude claude", new[] { "claude" });
        Assert.True(r.RemovedRegurgitation);
        Assert.Equal("", r.Text);
    }

    [Fact]
    public void Scrub_FlagsRemovedRegurgitation()
    {
        const string input = "and that is the part sub agents claude li-fraumeni sub agents claude " +
            "vs code li-fraumeni sub agents li-fraumeni sub agents li-fraumeni";
        var r = RepetitionGuard.Scrub(input, Vocab);
        Assert.True(r.RemovedRegurgitation);
        Assert.DoesNotContain("li-fraumeni", r.Text.ToLowerInvariant());
        Assert.StartsWith("and that is the part", r.Text);
    }

    // White-box parity: VocabularyCores splits spoken parts (cf. Swift vocabularyCoresSplitsSpokenParts).
    // The Mac's split is now acronym-aware (ffbca8a): it splits camelCase / an acronym running into a word,
    // never inside an acronym, so "VS Code" keeps "vs" (the old algorithm shredded it into V/S).
    [Fact]
    public void VocabularyCores_SplitsSpokenParts()
    {
        var cores = RepetitionGuard.VocabularyCores(new[] { "sub agents", "VS Code", "li-fraumeni" });
        Assert.Contains("sub", cores);
        Assert.Contains("agents", cores);
        Assert.Contains("subagents", cores);
        Assert.Contains("code", cores);
        Assert.Contains("vscode", cores);   // the whole entry, alphanumerics-only
        Assert.Contains("li", cores);
        Assert.Contains("fraumeni", cores);
        Assert.Contains("lifraumeni", cores);
        Assert.Contains("vs", cores);       // the Mac's acronym-aware split (ffbca8a) keeps "VS" whole
    }

    // Contrast: lowercase "vs code" has no camelCase boundary, so "vs" IS kept as a 2-char part.
    [Fact]
    public void VocabularyCores_LowercaseMultiword_KeepsShortPart()
        => Assert.Contains("vs", RepetitionGuard.VocabularyCores(new[] { "vs code" }));

    // Scrub never throws on arbitrary token soup, and never lengthens the text.
    [Fact]
    public void Fuzz_Scrub_NeverThrows_NeverLengthens()
    {
        var rng = new Random(20260623);
        string[] words = { "claude", "vs", "code", "sub", "agents", "the", "and", "a",
                           "li", "fraumeni", "x", "loop", "thanks", ",", ".", "" };
        string[][] vocabs =
        {
            Array.Empty<string>(),
            new[] { "claude" },
            new[] { "sub agents", "vs code", "li-fraumeni" },
        };
        for (int iter = 0; iter < 400; iter++)
        {
            int n = rng.Next(0, 40);
            var sb = new System.Text.StringBuilder();
            for (int i = 0; i < n; i++) { if (i > 0) sb.Append(' '); sb.Append(words[rng.Next(words.Length)]); }
            string input = sb.ToString();
            var vocab = vocabs[rng.Next(vocabs.Length)];

            var r = RepetitionGuard.Scrub(input, vocab);
            Assert.NotNull(r.Text);
            Assert.True(r.Text.Length <= input.Length);
            if (!r.RemovedRegurgitation) Assert.Equal(input, r.Text);
        }
    }

    // ===== Spoken mathematics is NOT a loop (Mac ffbca8a, parity row 8) =====

    [Theory]
    [InlineData("and then it's 26 x 26 x 26 x 10 x 10 x 10")]
    [InlineData("and then it's 26 times 26 times 26 times 10 times 10 times 10")]
    [InlineData("So the answer is minus 3 minus 3 minus 3 minus 3")]
    [InlineData("1 over 2 plus 1 over 4 plus 1 over 8 plus 1 over 16")]
    [InlineData("2 x 2 x 2 x 2 x 2 x 2 x 2 x 2 is 256")]
    [InlineData("ten times ten times ten times ten is ten thousand")]
    public void MathsRepetition_IsNotALoop(string maths)
    {
        var r = RepetitionGuard.Scrub(maths, Vocab);
        Assert.False(r.RemovedRegurgitation);
        Assert.Equal(maths, r.Text);
    }

    [Fact]
    public void MathsCounts_DoNotAccumulateAcrossALongDictation()
    {
        string longText = string.Concat(Enumerable.Repeat("so we have 5 choose 3 which is 10 and 10 choose 3 which is 120 times 3 factorial. ", 6))
            + "so the total is 26 choose 3 times 3 factorial times 10 choose 3 times 3 factorial";
        Assert.False(RepetitionGuard.Scrub(longText, Vocab).RemovedRegurgitation);
    }

    [Fact]
    public void SustainedNumericDecoderLoop_IsStillStripped()
    {
        Assert.Equal("and then it's", RepetitionGuard.Strip("and then it's " + string.Concat(Enumerable.Repeat("26 x ", 20)), Array.Empty<string>()));
        Assert.Equal("the total is", RepetitionGuard.Strip("the total is " + string.Concat(Enumerable.Repeat("10, ", 20)), Array.Empty<string>()));
        Assert.Equal("so it's", RepetitionGuard.Strip("so it's " + string.Concat(Enumerable.Repeat("times 10 plus ", 12)), Array.Empty<string>()));
    }

    [Fact]
    public void LongCycleLoop_IsCaughtByTheTrailingPhraseNet()
    {
        Assert.Equal("see", RepetitionGuard.Strip("see " + string.Concat(Enumerable.Repeat("page 1 of 10, ", 40)), Array.Empty<string>()));
        Assert.Equal("counting", RepetitionGuard.Strip("counting " + string.Concat(Enumerable.Repeat("1, 2, 3, 4, ", 50)), Array.Empty<string>()));
        Assert.Equal("cut off", RepetitionGuard.Strip("cut off " + string.Concat(Enumerable.Repeat("page 1 of 10, ", 7)) + "page 1", Array.Empty<string>()));
        // "page 1 of 10" ×6 at the very end is a loop…
        Assert.True(RepetitionGuard.Scrub("the report says " + string.Concat(Enumerable.Repeat("page 1 of 10 ", 6)).Trim(), Array.Empty<string>()).RemovedRegurgitation);
        // …while a dictated power (5 repeats of "26 times") stays.
        Assert.False(RepetitionGuard.Scrub("five letters so 26 times 26 times 26 times 26 times 26 times 26", Array.Empty<string>()).RemovedRegurgitation);
    }

    [Fact]
    public void RealWordLoop_IsStillALoop()
        => Assert.Equal("so I said", RepetitionGuard.Strip("so I said " + string.Concat(Enumerable.Repeat("okay ", 40)).Trim(), Array.Empty<string>()));

    [Fact]
    public void TheTheThe_FortyTimes_IsStillALoop()
        => Assert.True(RepetitionGuard.Scrub("and then " + string.Concat(Enumerable.Repeat("the ", 40)).Trim(), Array.Empty<string>()).RemovedRegurgitation);

    [Fact]
    public void VocabularyCores_KeepAcronymsWhole()
    {
        var cores = RepetitionGuard.VocabularyCores(new[] { "sub agents", "VS Code", "li-fraumeni", "JVoice", "WhisperKit" });
        foreach (var c in new[] { "sub", "agents", "vs", "code", "fraumeni", "lifraumeni", "voice", "whisper", "kit" })
            Assert.Contains(c, cores);
    }

    [Theory]
    [InlineData("26", true)]
    [InlineData("x", true)]
    [InlineData("times", true)]
    [InlineData("thousand", true)]
    [InlineData("½", true)]
    [InlineData("page", false)]
    [InlineData("okay", false)]
    public void IsMathToken(string core, bool expected) => Assert.Equal(expected, RepetitionGuard.IsMathToken(core));
}
