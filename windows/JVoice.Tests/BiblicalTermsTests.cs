using JVoice.Core.Models;
using JVoice.Core.Text;
using Xunit;

namespace JVoice.Tests;

public class BiblicalTermsTests
{
    private static readonly IReadOnlyDictionary<string, string> Empty =
        new Dictionary<string, string>();

    // ===== Map hygiene =====

    [Fact]
    public void Map_IsNonEmpty()
        => Assert.NotEmpty(BiblicalTerms.Map);

    [Fact]
    public void Map_KeysAreLowercasedTrimmed_AndValuesNonEmpty()
    {
        foreach (var (key, value) in BiblicalTerms.Map)
        {
            Assert.Equal(key.Trim(), key);
            Assert.Equal(key.ToLowerInvariant(), key);
            Assert.NotEqual(0, key.Length);
            Assert.NotEqual(0, value.Trim().Length);
        }
    }

    // Every value must be idempotent under the pack: re-processing an already-correct
    // transcript must not change it (guards against a typo'd canonical form).
    [Fact]
    public void Map_ValuesAreIdempotent()
    {
        var extra = BiblicalTerms.Augment(Empty);
        foreach (var value in BiblicalTerms.Map.Values)
            Assert.Equal(value, TextProcessor.Process(value, ToneStyle.Casual, extra));
    }

    // Locks the exclusion policy: reverential pronouns, English/ name-colliding book names,
    // bare abstractions, and optional/stylistic words must NEVER enter the pack, or ordinary
    // dictation would be corrupted. (See the class doc-comment for the rationale.)
    [Theory]
    // reverential pronouns
    [InlineData("he")]
    [InlineData("him")]
    [InlineData("his")]
    [InlineData("thee")]
    [InlineData("thou")]
    [InlineData("thy")]
    [InlineData("thine")]
    // book names that are everyday English or common first names
    [InlineData("numbers")]
    [InlineData("acts")]
    [InlineData("kings")]
    [InlineData("judges")]
    [InlineData("job")]
    [InlineData("mark")]
    [InlineData("john")]
    [InlineData("luke")]
    [InlineData("matthew")]
    [InlineData("james")]
    [InlineData("revelation")]
    [InlineData("genesis")]
    [InlineData("exodus")]
    // bare abstractions / role words that are ordinary English or personal names
    [InlineData("father")]
    [InlineData("son")]
    [InlineData("spirit")]
    [InlineData("grace")]
    [InlineData("faith")]
    [InlineData("hope")]
    [InlineData("cross")]
    [InlineData("word")]
    [InlineData("king")]
    [InlineData("creator")]   // "content creator" — the most dangerous add
    [InlineData("devil")]
    // optional / stylistically lower-cased
    [InlineData("heaven")]
    [InlineData("hell")]
    [InlineData("amen")]
    [InlineData("hallelujah")]
    [InlineData("holy")]
    [InlineData("divine")]
    [InlineData("blessed")]
    [InlineData("sacred")]
    [InlineData("almighty")]  // bare adjective; only "almighty god" is kept
    public void Map_ExcludesDangerousWords(string risky)
        => Assert.False(BiblicalTerms.Map.ContainsKey(risky), $"pack must not contain dangerous key '{risky}'");

    // ===== Augment precedence =====

    [Fact]
    public void Augment_AddsPackEntries()
    {
        var merged = BiblicalTerms.Augment(Empty);
        Assert.Equal("God", merged["god"]);
        Assert.Equal("Jesus Christ", merged["jesus christ"]);
    }

    [Fact]
    public void Augment_PreservesNonCollidingBaseEntries()
    {
        var baseDict = new Dictionary<string, string> { ["foo bar"] = "FooBar" };
        var merged = BiblicalTerms.Augment(baseDict);
        Assert.Equal("FooBar", merged["foo bar"]);   // base kept
        Assert.Equal("God", merged["god"]);          // pack added
    }

    [Fact]
    public void Augment_BaseWins_OnKeyCollision()
    {
        // A caller's own entry (custom word / user rule) outranks the generic pack.
        var baseDict = new Dictionary<string, string> { ["god"] = "GOD" };
        var merged = BiblicalTerms.Augment(baseDict);
        Assert.Equal("GOD", merged["god"]);
    }

    // ===== End-to-end through TextProcessor.Process =====

    [Theory]
    [InlineData("i believe in god", "i believe in God")]
    [InlineData("praise the lord", "praise the Lord")]
    [InlineData("jesus wept", "Jesus wept")]
    [InlineData("in the name of jesus christ", "in the name of Jesus Christ")]
    [InlineData("the holy spirit guides us", "the Holy Spirit guides us")]
    [InlineData("read the bible", "read the Bible")]
    [InlineData("he is the son of god", "he is the Son of God")]
    [InlineData("the word of god is true", "the Word of God is true")]
    [InlineData("study the old testament", "study the Old Testament")]
    [InlineData("obey the ten commandments", "obey the Ten Commandments")]
    [InlineData("resist satan", "resist Satan")]
    [InlineData("i am a christian", "i am a Christian")]
    [InlineData("thanks be to god's mercy", "thanks be to God's mercy")]  // possessive keeps the fix
    [InlineData("jesus christ is the messiah", "Jesus Christ is the Messiah")]
    public void Process_CapitalizesBiblicalTerms(string input, string expected)
    {
        var extra = BiblicalTerms.Augment(Empty);
        Assert.Equal(expected, TextProcessor.Process(input, ToneStyle.Casual, extra));
    }

    // The word-boundary matcher must leave compounds and the excluded common words alone.
    [Theory]
    [InlineData("we watched godzilla last night")]
    [InlineData("the greek goddess of wisdom")]   // "goddess" must not become "Goddess"
    [InlineData("i paid the landlord on time")]    // "landlord" must not become "landLord"
    [InlineData("he is a content creator")]        // "creator" is excluded
    [InlineData("that was an almighty crash")]     // bare "almighty" is excluded
    [InlineData("i found a job in the city")]      // "job" the book is excluded
    [InlineData("she has a lot of faith in me")]   // "faith" is excluded
    public void Process_LeavesExcludedAndCompoundWordsUntouched(string input)
    {
        var extra = BiblicalTerms.Augment(Empty);
        Assert.Equal(input, TextProcessor.Process(input, ToneStyle.Casual, extra));
    }

    // ===== It works in EVERY tone (the core requirement: automatic in every mode) =====

    [Fact]
    public void Process_Casual_Capitalizes()
    {
        var extra = BiblicalTerms.Augment(Empty);
        Assert.Equal("i love Jesus", TextProcessor.Process("i love jesus", ToneStyle.Casual, extra));
    }

    [Fact]
    public void Process_Formal_Capitalizes()
    {
        var extra = BiblicalTerms.Augment(Empty);
        Assert.Equal("I love Jesus.", TextProcessor.Process("i love jesus", ToneStyle.Formal, extra));
    }

    // Very Casual lower-cases the whole transcript FIRST; corrections run after, so the
    // Biblical capitals must still survive — this is the mode most at risk.
    [Fact]
    public void Process_VeryCasual_StillCapitalizes()
    {
        var extra = BiblicalTerms.Augment(Empty);
        Assert.Equal("i love Jesus.", TextProcessor.Process("I LOVE JESUS", ToneStyle.VeryCasual, extra));
    }

    [Fact]
    public void Process_Code_Capitalizes()
    {
        var extra = BiblicalTerms.Augment(Empty);
        // Code mode leaves casing/punctuation as-spoken, but corrections still run first.
        Assert.Equal("God is good", TextProcessor.Process("god is good", ToneStyle.Code, extra));
        Assert.Equal("God bless", TextProcessor.Process("god bless", ToneStyle.Code, extra));
    }

    // ===== Layering with the rest of the correction stack =====

    [Fact]
    public void UserCorrectionRule_OverridesPack()
    {
        // A user Correction sits ABOVE the biblical pack in UserCorrections.Merge, so a user
        // who dictates the common-noun sense can opt a single term out.
        var extra = UserCorrections.Merge(
            BiblicalTerms.Augment(Empty),
            new[] { new CorrectionRule("god", "god") });
        Assert.Equal("the god of war", TextProcessor.Process("the god of war", ToneStyle.Casual, extra));
    }

    [Fact]
    public void CoexistsWithDeveloperPack()
    {
        // Both packs fire together, as they do at the real call site.
        var extra = BiblicalTerms.Augment(DeveloperTerms.Augment(Empty));
        Assert.Equal(
            "praise God in JavaScript",
            TextProcessor.Process("praise god in java script", ToneStyle.Casual, extra));
    }

    [Fact]
    public void BuiltinCorrection_StillApplies_AlongsidePack()
    {
        var extra = BiblicalTerms.Augment(Empty);
        Assert.Equal(
            "JVoice and God",
            TextProcessor.Process("jvoice and god", ToneStyle.Casual, extra));
    }
}
