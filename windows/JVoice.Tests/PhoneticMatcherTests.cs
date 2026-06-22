using JVoice.Core.Text;
using Xunit;

namespace JVoice.Tests;

public class PhoneticMatcherTests
{
    [Theory]
    [InlineData("jvoice", "jfs")]
    [InlineData("gvoice", "jfs")]   // g and j merge (spoken letter G sounds like j)
    [InlineData("whisperkit", "wsprkt")]
    public void PhoneticKey_KnownVectors(string input, string expected)
        => Assert.Equal(expected, PhoneticMatcher.PhoneticKey(input));

    [Fact]
    public void PhoneticKey_KeepsInitialVowel_DropsInterior()
    {
        // position 0 vowel kept; interior vowels dropped.
        Assert.StartsWith("a", PhoneticMatcher.PhoneticKey("apple"));
    }

    [Theory]
    [InlineData("a", "abc", 3, 2)]
    [InlineData("kitten", "sitting", 5, 3)]
    public void Levenshtein_Basic(string a, string b, int limit, int expected)
        => Assert.Equal(expected, PhoneticMatcher.Levenshtein(a, b, limit));

    [Fact]
    public void Levenshtein_EarlyExitReturnsLimitPlusOne()
        => Assert.Equal(2, PhoneticMatcher.Levenshtein("abcdef", "zzzzzz", 1));

    [Fact]
    public void Correct_FixesPhoneticMiss()
    {
        Assert.Equal("JVoice", PhoneticMatcher.Correct("jay voice", new[] { "JVoice" }));
        Assert.Equal("JVoice", PhoneticMatcher.Correct("g voice", new[] { "JVoice" }));
    }

    [Fact]
    public void Correct_PreservesPunctuationAroundWindow()
    {
        Assert.Equal("JVoice.", PhoneticMatcher.Correct("jvoice.", new[] { "JVoice" }));
    }

    [Fact]
    public void Correct_DoesNotHijackPlainWords()
    {
        // "voice" alone (fs...) must not become "JVoice" (jfs...) -- initial-sound guard.
        Assert.Equal("the voice", PhoneticMatcher.Correct("the voice", new[] { "JVoice" }));
    }

    [Fact]
    public void Correct_LeavesAlreadyExactMultiToken()
    {
        Assert.Equal("VS Code", PhoneticMatcher.Correct("VS Code", new[] { "VS Code" }));
    }

    [Fact]
    public void Correct_NoVocab_Identity()
        => Assert.Equal("hello world", PhoneticMatcher.Correct("hello world", Array.Empty<string>()));

    // ===== Swift-parity vectors (PhoneticMatcherTests.swift) the C# suite was missing =====

    [Theory]
    [InlineData("jvoice", "jfs")]
    [InlineData("jayvoice", "jfs")]
    [InlineData("gvoice", "jfs")]
    [InlineData("whisperkit", "wsprkt")]
    [InlineData("whispercat", "wsprkt")]
    [InlineData("voice", "fs")]
    public void PhoneticKey_WorkedExamples(string input, string expected)
        => Assert.Equal(expected, PhoneticMatcher.PhoneticKey(input));

    [Fact]
    public void PhoneticKey_KeepsLeadingVowel_AppKit()
        => Assert.Equal('a', PhoneticMatcher.PhoneticKey("appkit")[0]);

    [Theory]
    [InlineData("jvoice", "jayvoice", 3, 2)]
    [InlineData("same", "same", 3, 0)]
    [InlineData("abc", "xyz", 2, 3)] // early-exit cap = limit+1
    public void Levenshtein_SwiftBasics(string a, string b, int limit, int expected)
        => Assert.Equal(expected, PhoneticMatcher.Levenshtein(a, b, limit));

    [Theory]
    [InlineData("open jay voice settings", "open JVoice settings")]
    [InlineData("g voice is running", "JVoice is running")]
    [InlineData("is jay voice, ready", "is JVoice, ready")]      // interior punctuation preserved
    public void Correct_JVoice_Hits(string input, string expected)
        => Assert.Equal(expected, PhoneticMatcher.Correct(input, new[] { "JVoice" }));

    [Fact]
    public void Correct_HearsSoundalikeCompound()
        => Assert.Equal("built with WhisperKit",
            PhoneticMatcher.Correct("built with whisper cat", new[] { "WhisperKit" }));

    [Theory]
    [InlineData("use your voice now")]   // "voice" (fs...) must not become JVoice (jfs...)
    [InlineData("JVoice is great")]      // already exact
    [InlineData("JVoice is so fast")]    // 2-token window jvoiceis -> jfs must NOT swallow is
    public void Correct_JVoice_FalsePositiveGuards(string input)
        => Assert.Equal(input, PhoneticMatcher.Correct(input, new[] { "JVoice" }));

    [Fact]
    public void Correct_MultiTokenExactSpellingIsUntouched()
        => Assert.Equal("I use VS Code daily",
            PhoneticMatcher.Correct("I use VS Code daily", new[] { "VS Code" }));

    [Fact]
    public void Correct_ShortVocabularyWordsAreIgnored()
        => Assert.Equal("ay bee sea", PhoneticMatcher.Correct("ay bee sea", new[] { "AB" }));

    [Fact]
    public void Correct_EmptyVocabularyIsNoop()
        => Assert.Equal("hello there", PhoneticMatcher.Correct("hello there", Array.Empty<string>()));

    // ===== Edge cases the suite missed =====

    [Fact]
    public void Correct_EmptyText_IsIdentity()
        => Assert.Equal("", PhoneticMatcher.Correct("", new[] { "JVoice" }));

    [Fact]
    public void Correct_IsIdempotent()
    {
        var once = PhoneticMatcher.Correct("jay voice is fast", new[] { "JVoice" });
        Assert.Equal("JVoice is fast", once);
        Assert.Equal(once, PhoneticMatcher.Correct(once, new[] { "JVoice" }));
    }

    // Bounded Levenshtein must be symmetric, non-negative, and never exceed limit+1.
    [Fact]
    public void Levenshtein_IsSymmetricAndBounded()
    {
        var rng = new Random(20260623);
        const string alpha = "abcdefjkqstvxz ";
        for (int iter = 0; iter < 400; iter++)
        {
            string a = RandomString(rng, alpha, rng.Next(0, 10));
            string b = RandomString(rng, alpha, rng.Next(0, 10));
            int limit = rng.Next(0, 5);
            int ab = PhoneticMatcher.Levenshtein(a, b, limit);
            int ba = PhoneticMatcher.Levenshtein(b, a, limit);
            Assert.Equal(ab, ba);
            Assert.InRange(ab, 0, limit + 1);
            Assert.Equal(0, PhoneticMatcher.Levenshtein(a, a, limit));
        }
    }

    // Correct / PhoneticKey must NEVER throw on arbitrary input + arbitrary vocab
    // (empty tokens, punctuation-only, digits, over-long windows, unicode).
    [Fact]
    public void Fuzz_Correct_AndKey_NeverThrow()
    {
        var rng = new Random(0x5151);
        const string alpha = "ab CD.,!?-_'\"()jvoiceJVOICE whisperkit 12 ";
        for (int iter = 0; iter < 400; iter++)
        {
            string text = RandomString(rng, alpha, rng.Next(0, 30));
            int vocabCount = rng.Next(0, 4);
            var vocab = new string[vocabCount];
            for (int v = 0; v < vocabCount; v++) vocab[v] = RandomString(rng, alpha, rng.Next(0, 12));

            var result = PhoneticMatcher.Correct(text, vocab);
            Assert.NotNull(result);
            _ = PhoneticMatcher.PhoneticKey(text);
        }
    }

    private static string RandomString(Random rng, string alphabet, int length)
    {
        var sb = new System.Text.StringBuilder(length);
        for (int i = 0; i < length; i++) sb.Append(alphabet[rng.Next(alphabet.Length)]);
        return sb.ToString();
    }
}
