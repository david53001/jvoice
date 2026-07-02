using JVoice.Core.Models;
using JVoice.Core.Text;
using Xunit;

namespace JVoice.Tests;

public class DeveloperTermsTests
{
    private static readonly IReadOnlyDictionary<string, string> Empty =
        new Dictionary<string, string>();

    // ===== Map hygiene =====

    [Fact]
    public void Map_IsNonEmpty()
        => Assert.NotEmpty(DeveloperTerms.Map);

    [Fact]
    public void Map_KeysAreLowercasedTrimmed_AndValuesNonEmpty()
    {
        foreach (var (key, value) in DeveloperTerms.Map)
        {
            Assert.Equal(key.Trim(), key);
            Assert.Equal(key.ToLowerInvariant(), key);
            Assert.NotEqual(0, key.Length);
            Assert.NotEqual(0, value.Trim().Length);
        }
    }

    // Locks the conservative-curation policy: ambiguous single English words must
    // never enter the pack, or ordinary dictation would be corrupted.
    [Theory]
    [InlineData("go")]
    [InlineData("rust")]
    [InlineData("swift")]
    [InlineData("react")]
    [InlineData("java")]
    [InlineData("pandas")]
    [InlineData("dotnet")]   // bare "dotnet" must stay the lowercase CLI, never ".NET"
    [InlineData("sequel")]   // "sequel"->"SQL" would wreck "the movie sequel"
    [InlineData("flask")]
    [InlineData("pip")]
    // AI / "vibe coding" exclusions (2026-07-01): hot tool names that are ordinary
    // English. Adding any of these would corrupt everyday dictation.
    [InlineData("cursor")]       // the text/mouse cursor — the single most dangerous add
    [InlineData("bolt")]         // "tighten the bolt"
    [InlineData("continue")]     // the verb — Continue.dev
    [InlineData("render")]       // the verb / a CS term — Render.com
    [InlineData("railway")]      // "we took the railway" — Railway.app
    [InlineData("remix")]        // "a great remix" — Remix
    [InlineData("warp")]         // "a warp in space" — Warp terminal
    [InlineData("astro")]        // a nickname/prefix — Astro
    [InlineData("svelte")]       // the adjective (bare) — SvelteKit is kept instead
    [InlineData("bun")]          // "a bun in the oven" — Bun runtime
    [InlineData("pinecone")]     // the botanical object — Pinecone (vector DB)
    [InlineData("pine cone")]    // ditto, spaced
    [InlineData("chroma")]       // chrominance (bare) — ChromaDB is kept instead
    [InlineData("cohere")]       // the verb — Cohere
    [InlineData("perplexity")]   // also a real ML metric — Perplexity
    [InlineData("grok")]         // the everyday verb — Grok (xAI); only "groq" is kept
    [InlineData("drizzle")]      // "drizzle olive oil" — Drizzle ORM
    [InlineData("lovable")]      // the adjective — Lovable
    [InlineData("llama")]        // the animal (bare); versioned model names are skipped
    public void Map_ExcludesAmbiguousEnglishWords(string risky)
        => Assert.False(DeveloperTerms.Map.ContainsKey(risky), $"pack must not contain ambiguous key '{risky}'");

    // ===== Augment precedence =====

    [Fact]
    public void Augment_AddsPackEntries()
    {
        var merged = DeveloperTerms.Augment(Empty);
        Assert.Equal("Node.js", merged["node js"]);
        Assert.Equal("GitHub", merged["git hub"]);
    }

    [Fact]
    public void Augment_PreservesNonCollidingBaseEntries()
    {
        var baseDict = new Dictionary<string, string> { ["foo bar"] = "FooBar" };
        var merged = DeveloperTerms.Augment(baseDict);
        Assert.Equal("FooBar", merged["foo bar"]);   // base kept
        Assert.Equal("Node.js", merged["node js"]);  // pack added
    }

    [Fact]
    public void Augment_BaseWins_OnKeyCollision()
    {
        // A user's own custom-word variant outranks the generic pack.
        var baseDict = new Dictionary<string, string> { ["react js"] = "React.js" };
        var merged = DeveloperTerms.Augment(baseDict);
        Assert.Equal("React.js", merged["react js"]);
    }

    // ===== End-to-end through TextProcessor.Process =====

    [Theory]
    [InlineData("i use node js daily", "i use Node.js daily")]
    [InlineData("clone it from git hub", "clone it from GitHub")]
    [InlineData("written in type script", "written in TypeScript")]
    [InlineData("i love java script", "i love JavaScript")]
    [InlineData("built with dot net", "built with .NET")]
    [InlineData("learning c sharp", "learning C#")]
    [InlineData("call the open ai api", "call the OpenAI API")]
    [InlineData("parse the jason", "parse the JSON")]
    [InlineData("train with py torch", "train with PyTorch")]
    [InlineData("deploy to vs code", "deploy to VS Code")]
    // AI / "vibe coding" additions (2026-07-01)
    [InlineData("deploy to vercel", "deploy to Vercel")]
    [InlineData("use github copilot", "use GitHub Copilot")]
    [InlineData("run it with ollama", "run it with Ollama")]
    [InlineData("validate with zod", "validate with Zod")]
    [InlineData("i tried deep seek and qwen", "i tried DeepSeek and Qwen")]
    [InlineData("the mcp server crashed", "the MCP server crashed")]
    [InlineData("using deno instead of node js", "using Deno instead of Node.js")]
    [InlineData("spun up supabase and firebase", "spun up Supabase and Firebase")]
    [InlineData("ask claude code to fix it", "ask Claude Code to fix it")]
    [InlineData("query it in qdrant", "query it in Qdrant")]
    [InlineData("gemini and groq are fast", "Gemini and Groq are fast")]
    public void Process_AppliesPack(string input, string expected)
    {
        var extra = DeveloperTerms.Augment(Empty);
        Assert.Equal(expected, TextProcessor.Process(input, ToneStyle.Casual, extra));
    }

    // The conservative exclusions really do leave ordinary dictation untouched.
    [Theory]
    [InlineData("i will go to the store")]
    [InlineData("the movie sequel was great")]
    [InlineData("i drink java every morning")]
    // AI / "vibe coding" collision guards (2026-07-01): product names that are also
    // ordinary English must leave normal dictation alone.
    [InlineData("move the cursor to the top")]
    [InlineData("please continue reading the file")]
    [InlineData("render the final frame")]
    [InlineData("we took the railway home")]
    [InlineData("he made a great remix")]
    [InlineData("the llama spat at me")]
    [InlineData("i found a pine cone")]
    [InlineData("these arguments cohere nicely")]
    [InlineData("let me grok this problem")]
    [InlineData("drizzle olive oil on top")]
    [InlineData("tighten the last bolt")]
    [InlineData("a svelte silhouette")]
    public void Process_LeavesAmbiguousWordsUntouched(string input)
    {
        var extra = DeveloperTerms.Augment(Empty);
        Assert.Equal(input, TextProcessor.Process(input, ToneStyle.Casual, extra));
    }

    // ===== Layering with the rest of the correction stack =====

    [Fact]
    public void UserCorrectionRule_OverridesPack()
    {
        // user Corrections sit ABOVE the dev pack in UserCorrections.Merge.
        var extra = UserCorrections.Merge(
            DeveloperTerms.Augment(Empty),
            new[] { new CorrectionRule("git hub", "GitLab") });
        Assert.Equal("push to GitLab", TextProcessor.Process("push to git hub", ToneStyle.Casual, extra));
    }

    [Fact]
    public void BuiltinCorrection_StillApplies_AlongsidePack()
    {
        // builtin CorrectionDictionary ("jvoice"->"JVoice") and the pack both fire.
        var extra = DeveloperTerms.Augment(Empty);
        Assert.Equal(
            "OpenAI and JVoice",
            TextProcessor.Process("open ai and jvoice", ToneStyle.Casual, extra));
    }
}
