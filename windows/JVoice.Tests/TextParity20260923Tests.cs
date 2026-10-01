using JVoice.Core.Models;
using JVoice.Core.Text;
using Xunit;

namespace JVoice.Tests;

/// <summary>
/// The Mac's 2026-09-23 text bug-hunt (b0bb390, parity doc §6.3 rows 10–13) and 000a8b0 (§6.4 row 14),
/// translated case-for-case from the Mac test files: custom words keep their neighbours and
/// possessives, never join across a comma, match at edit distance ≤ 1; fillers keep real words;
/// everyday English left alone; dot-prefixed words never gain dots; thousands separators and
/// closed quotations survive formatting.
/// </summary>
public class TextParity20260923Tests
{
    // ---- PhoneticMatcher: never swallow a neighbour, tighter fuzz, possessives (row 10)

    [Theory]
    [InlineData("I deployed 2 Vercel apps today.", "Vercel", "I deployed 2 Vercel apps today.")]
    [InlineData("Spawn six sub agents", "sub agents", "Spawn six sub agents")]
    [InlineData("$20 Vercel", "Vercel", "$20 Vercel")]
    [InlineData("The power of Ollama", "Ollama", "The power of Ollama")]
    [InlineData("We scheduled a AISB meeting", "AISB", "We scheduled a AISB meeting")]
    [InlineData("run it on olama", "Ollama", "run it on Ollama")]
    public void MultiTokenWindow_NeverSwallowsTheWordBefore(string input, string word, string expected)
        => Assert.Equal(expected, PhoneticMatcher.Correct(input, new[] { word }));

    [Theory]
    [InlineData("Hey Jay, voice memos are great", "Hey Jay, voice memos are great")]
    [InlineData("Jay's voice was hoarse", "Jay's voice was hoarse")]
    [InlineData("I use J. Voice daily", "I use JVoice daily")] // an initial's period is not a clause break
    public void Window_NeverJoinsAcrossClausePunctuation(string input, string expected)
        => Assert.Equal(expected, PhoneticMatcher.Correct(input, new[] { "JVoice" }));

    [Theory]
    [InlineData("verse")]
    [InlineData("verbal")]
    [InlineData("versed")]
    [InlineData("vessel")]
    public void TwoEditsWithADifferentSound_IsADifferentWord(string word)
        => Assert.Equal($"the {word} here", PhoneticMatcher.Correct($"the {word} here", new[] { "Vercel" }));

    [Fact]
    public void FalseCorrections_FromThePastAreGone_OneEditStillCorrects()
    {
        Assert.Equal("Obama gave a speech", PhoneticMatcher.Correct("Obama gave a speech", new[] { "Ollama" }));
        Assert.Equal("Such agents are rare", PhoneticMatcher.Correct("Such agents are rare", new[] { "sub agents" }));
        Assert.Equal("deploy to Vercel", PhoneticMatcher.Correct("deploy to versel", new[] { "Vercel" }));
    }

    [Fact]
    public void SingularAndShortWordRuns_AreNotCustomWords()
    {
        Assert.Equal("spawn a sub agent", PhoneticMatcher.Correct("spawn a sub agent", new[] { "sub agents" }));
        Assert.Equal("if a is b then swap", PhoneticMatcher.Correct("if a is b then swap", new[] { "AISB" }));
    }

    [Theory]
    [InlineData("I like Vercel's dashboard", "Vercel", "I like Vercel's dashboard")]
    [InlineData("Ollama's API is local", "Ollama", "Ollama's API is local")]
    [InlineData("Vercel’s pricing", "Vercel", "Vercel’s pricing")]
    [InlineData("versel's dashboard", "Vercel", "Vercel's dashboard")]
    public void Possessive_SurvivesCorrection(string input, string word, string expected)
        => Assert.Equal(expected, PhoneticMatcher.Correct(input, new[] { word }));

    [Fact]
    public void Replacement_DoesNotDoubleTheWordsOwnPunctuation()
        => Assert.Equal("use .NET daily", PhoneticMatcher.Correct("use .nett daily", new[] { ".NET" }));

    // ---- Custom-word dictionary (row 10 item 5) + dot-prefixed words (row 13)

    [Fact]
    public void UserDictionary_KeepsPlainLowercaseKey()
    {
        Assert.Equal("AISB", TextProcessor.BuildUserDictionary(new[] { "AISB" })["aisb"]);
        Assert.Equal("the AISB meeting",
            TextProcessor.Process("the aisb meeting", ToneStyle.Casual, TextProcessor.BuildUserDictionary(new[] { "AISB" })));
    }

    [Fact]
    public void DotPrefixedCustomWords_NeverGainDots()
    {
        var variants = TextProcessor.SpokenVariants(".NET");
        Assert.DoesNotContain(" net", variants);
        Assert.Contains(".net", variants);
        var net = DeveloperTerms.Augment(TextProcessor.BuildUserDictionary(new[] { ".NET" }));
        Assert.Equal("We use .NET daily.", TextProcessor.Process("We use .NET daily.", ToneStyle.Formal, net, vocabulary: new[] { ".NET" }));
        Assert.Equal("We use .NET daily.", TextProcessor.Process("We use dot net daily.", ToneStyle.Formal, net, vocabulary: new[] { ".NET" }));
        Assert.Equal("we use .NET daily.", TextProcessor.Process("We use .NET daily.", ToneStyle.VeryCasual, net, vocabulary: new[] { ".NET" }));
        var env = TextProcessor.BuildUserDictionary(new[] { ".env" });
        Assert.Equal("Copy the .env file first.", TextProcessor.Process("Copy the .env file first.", ToneStyle.Formal, env, vocabulary: new[] { ".env" }));
        // A punctuated key is not glued into a longer name ("example.net").
        Assert.Equal("visit example.net today", TextProcessor.ApplyCorrections("visit example.net today", net));
    }

    // ---- Everyday English left alone (row 12)

    [Fact]
    public void BuiltInDictionary_LeavesEverydayKeyboardShortcutsAlone()
    {
        Assert.False(TextProcessor.CorrectionDictionary.ContainsKey("keyboard shortcuts"));
        Assert.Equal("My favorite keyboard shortcuts are simple", TextProcessor.Process("My favorite keyboard shortcuts are simple", ToneStyle.Casual));
        Assert.Equal("I added KeyboardShortcuts to the package", TextProcessor.Process("I added keyboardshortcuts to the package", ToneStyle.Casual));
    }

    [Fact]
    public void DeveloperTerms_ExcludeEverydayPhrases()
    {
        foreach (var key in new[] { "my sql", "no sql", "fast api", "restful", "uri" })
            Assert.False(DeveloperTerms.Map.ContainsKey(key), key);
        Assert.Equal("MySQL", DeveloperTerms.Map["mysql"]);
        Assert.Equal("NoSQL", DeveloperTerms.Map["nosql"]);
        Assert.Equal("FastAPI", DeveloperTerms.Map["fastapi"]);
        var extra = DeveloperTerms.Augment(new Dictionary<string, string>());
        foreach (var sentence in new[] { "can you check my SQL query", "there is no SQL here", "we want a fast API", "a restful weekend", "Uri sent the slides" })
            Assert.Equal(sentence, TextProcessor.Process(sentence, ToneStyle.Casual, extra));
    }

    // ---- Fillers (row 11)

    [Theory]
    [InlineData("She rushed to the ER last night.", "She rushed to the ER last night.")]
    [InlineData("To err is human.", "To err is human.")]
    [InlineData("Uh-oh, the build broke again.", "Uh-oh, the build broke again.")]
    [InlineData("Uh-huh, that works for me.", "Uh-huh, that works for me.")]
    [InlineData("Mm-hmm, sounds good.", "Mm-hmm, sounds good.")]
    [InlineData("He works at UM now.", "He works at UM now.")]
    [InlineData("Er, I was thinking.", "I was thinking.")]
    [InlineData("Errr, maybe later.", "maybe later.")]
    [InlineData("Um, I think so, uh, yes.", "I think so, yes.")]
    public void FillerRemoval_KeepsRealWords(string input, string expected)
        => Assert.Equal(expected, TextProcessor.RemoveDisfluencies(input));

    // ---- Formatting (row 13)

    [Theory]
    [InlineData("We raised $1,000,000 last year.", "we raised $1,000,000 last year.")]
    [InlineData("The file has 12,500 rows", "the file has 12,500 rows.")]
    [InlineData("1,,2 and 3 , 4", "1, 2 and 3, 4.")]
    [InlineData("apples,oranges", "apples, oranges.")]
    public void VeryCasual_KeepsThousandsSeparators(string input, string expected)
        => Assert.Equal(expected, TextProcessor.Process(input, ToneStyle.VeryCasual));

    [Theory]
    [InlineData("He said \"hello.\"", "He said \"hello.\"")]
    [InlineData("Is that right?\"", "Is that right?\"")]
    [InlineData("It was fine (mostly.)", "It was fine (mostly.)")]
    [InlineData("Here are the steps:", "Here are the steps:")]
    [InlineData("Wait for it…", "Wait for it…")]
    [InlineData("She said “yes”", "She said “yes”.")]
    public void Formal_DoesNotDoublePunctuateAClosedSentence(string input, string expected)
        => Assert.Equal(expected, TextProcessor.Process(input, ToneStyle.Formal));

    // ---- "J-Voice" + the lone "you" (row 14, Mac 000a8b0)

    [Fact]
    public void JHyphenVoice_BecomesJVoice()
        => Assert.Equal("I use JVoice daily", TextProcessor.Process("I use J-Voice daily", ToneStyle.Casual));

    [Fact]
    public void BareLowercaseYou_IsAHallucination_ButARealYouSurvives()
    {
        Assert.Equal("", TextProcessor.RemoveWhisperHallucinations("you"));
        Assert.Equal("You.", TextProcessor.RemoveWhisperHallucinations("You."));
        Assert.Equal("you know what", TextProcessor.RemoveWhisperHallucinations("you know what"));
    }
}
