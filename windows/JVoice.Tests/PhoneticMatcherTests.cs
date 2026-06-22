using JVoice.Core.Text;
using Xunit;

namespace JVoice.Tests;

public class PhoneticMatcherTests
{
    [Theory]
    [InlineData("jvoice", "jfs")]
    [InlineData("gvoice", "jfs")]   // g and j merge (spoken "G" is /dʒ/)
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
        // "voice" alone (fs…) must not become "JVoice" (jfs…) — initial-sound guard.
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
}
