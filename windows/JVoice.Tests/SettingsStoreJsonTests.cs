using System.Text.Json;
using JVoice.Core.Models;
using Xunit;

namespace JVoice.Tests;

public class SettingsStoreJsonTests
{
    [Fact]
    public void RoundTrip_PreservesAllFields()
    {
        var original = new SettingsState(
            SchemaVersion: SettingsState.CurrentSchemaVersion,
            Mode: ToneStyle.Formal,
            Model: WhisperModelOption.LargeTurbo,
            Language: TranscriptionLanguage.Romanian,
            CustomWords: new[] { "JVoice", "Li-Fraumeni" },
            RemoveFillerWords: false,
            Corrections: new[] { new CorrectionRule("web api", "web app") });

        string json = SettingsStateJson.Serialize(original);
        var back = SettingsStateJson.Deserialize(json);

        Assert.Equal(original.Mode, back.Mode);
        Assert.Equal(original.Model, back.Model);
        Assert.Equal(original.Language, back.Language);
        Assert.Equal(original.CustomWords, back.CustomWords);
        Assert.Equal(original.RemoveFillerWords, back.RemoveFillerWords);
        Assert.Equal(original.Corrections, back.Corrections);
        Assert.Equal(SettingsState.CurrentSchemaVersion, back.SchemaVersion);
    }

    [Fact]
    public void Serialize_AlwaysWritesCurrentSchemaVersion()
    {
        var s = SettingsState.Default with { SchemaVersion = 0 };
        string json = SettingsStateJson.Serialize(s);
        using var doc = JsonDocument.Parse(json);
        Assert.Equal(SettingsState.CurrentSchemaVersion,
            doc.RootElement.GetProperty("schemaVersion").GetInt32());
    }

    [Fact]
    public void Deserialize_ForwardVersion_Throws()
    {
        string json = """
            { "schemaVersion": 2, "mode": "Casual", "model": "Tiny",
              "language": "English", "customWords": [], "removeFillerWords": true }
            """;
        var ex = Assert.Throws<ForwardVersionException>(() => SettingsStateJson.Deserialize(json));
        Assert.Equal(2, ex.FileVersion);
        Assert.Equal(SettingsState.CurrentSchemaVersion, ex.CurrentVersion);
    }

    [Fact]
    public void Deserialize_MissingSchemaVersion_DefaultsToZero_AndIsAcceptable()
    {
        string json = """{ "mode": "Formal" }""";
        var s = SettingsStateJson.Deserialize(json);
        Assert.Equal(SettingsState.CurrentSchemaVersion, s.SchemaVersion);
        Assert.Equal(ToneStyle.Formal, s.Mode);
    }

    [Fact]
    public void Deserialize_UnknownEnumValues_FallBackPerField()
    {
        string json = """
            { "schemaVersion": 1, "mode": "Banana", "model": "Quantum",
              "language": "Klingon", "removeFillerWords": "notabool" }
            """;
        var s = SettingsStateJson.Deserialize(json);
        Assert.Equal(ToneStyle.Casual, s.Mode);
        Assert.Equal(WhisperModelOption.Tiny, s.Model);
        Assert.Equal(TranscriptionLanguage.English, s.Language);
        Assert.True(s.RemoveFillerWords);
        Assert.Empty(s.CustomWords);
    }

    [Fact]
    public void Deserialize_MissingFields_UseDefaults()
    {
        var s = SettingsStateJson.Deserialize("{}");
        Assert.Equal(SettingsState.Default.Mode, s.Mode);
        Assert.Equal(SettingsState.Default.Model, s.Model);
        Assert.Equal(SettingsState.Default.Language, s.Language);
        Assert.True(s.RemoveFillerWords);
        Assert.Empty(s.CustomWords);
    }

    [Theory]
    [InlineData("tiny", WhisperModelOption.Tiny)]
    [InlineData("Tiny", WhisperModelOption.Tiny)]
    [InlineData("largeTurbo", WhisperModelOption.LargeTurbo)]
    [InlineData("LargeTurbo", WhisperModelOption.LargeTurbo)]
    [InlineData("large-v3_turbo", WhisperModelOption.LargeTurbo)]      // legacy macOS raw value
    [InlineData("large-v3-v20240930", WhisperModelOption.LargeTurbo)]  // legacy macOS raw value
    public void Deserialize_ModelAcceptsLegacyAndCSharpNames(string raw, WhisperModelOption expected)
    {
        string json = $$"""{ "schemaVersion": 1, "model": "{{raw}}" }""";
        Assert.Equal(expected, SettingsStateJson.Deserialize(json).Model);
    }

    [Fact]
    public void Deserialize_StructurallyInvalidJson_ThrowsJsonException()
        // JsonDocument.Parse throws JsonReaderException (a JsonException subclass), so
        // ThrowsAny - the contract is "a JsonException", not the exact leaf type.
        => Assert.ThrowsAny<JsonException>(() => SettingsStateJson.Deserialize("{ not json"));

    // ===== Serialize-side fidelity + round-trip fuzz =====

    // Swift's CodingKeys are schemaVersion/mode/model/language/customWords/removeFillerWords. The
    // Windows port adds one extra on-disk key, `corrections` (a Windows-only feature with no macOS
    // counterpart) — so Serialize emits exactly those seven keys. Older builds / the macOS app simply
    // ignore the unknown `corrections` key on read; Deserialize tolerates its absence.
    [Fact]
    public void Serialize_EmitsExactlyTheSevenKeys()
    {
        using var doc = JsonDocument.Parse(SettingsStateJson.Serialize(SettingsState.Default));
        var keys = doc.RootElement.EnumerateObject().Select(p => p.Name).OrderBy(n => n).ToArray();
        Assert.Equal(
            new[] { "corrections", "customWords", "language", "mode", "model", "removeFillerWords", "schemaVersion" },
            keys);
    }

    [Fact]
    public void Serialize_WritesEnumNames()
    {
        var s = SettingsState.Default with
        {
            Mode = ToneStyle.VeryCasual,
            Model = WhisperModelOption.LargeTurbo,
            Language = TranscriptionLanguage.Romanian,
        };
        using var doc = JsonDocument.Parse(SettingsStateJson.Serialize(s));
        var root = doc.RootElement;
        Assert.Equal("VeryCasual", root.GetProperty("mode").GetString());
        Assert.Equal("LargeTurbo", root.GetProperty("model").GetString());
        Assert.Equal("Romanian", root.GetProperty("language").GetString());
    }

    // JSON-special characters in custom words must survive a round-trip (escaping/unescaping).
    [Fact]
    public void RoundTrip_CustomWordsWithSpecialChars()
    {
        var state = SettingsState.Default with
        {
            CustomWords = new[] { "a\"b", "c\\d", "e\tf", "g\nh", "\u00e9unicode", "" },
        };
        var back = SettingsStateJson.Deserialize(SettingsStateJson.Serialize(state));
        Assert.Equal(state.CustomWords, back.CustomWords);
    }

    // Serialize - Deserialize is an identity on all fields, for any valid SettingsState.
    [Fact]
    public void Fuzz_SerializeDeserialize_RoundTrips()
    {
        var rng = new Random(20260623);
        var modes = Enum.GetValues<ToneStyle>();
        var models = Enum.GetValues<WhisperModelOption>();
        var langs = Enum.GetValues<TranscriptionLanguage>();
        for (int i = 0; i < 400; i++)
        {
            int wc = rng.Next(0, 6);
            var words = new string[wc];
            for (int w = 0; w < wc; w++) words[w] = RandomWord(rng);
            int cc = rng.Next(0, 4);
            var corrections = new CorrectionRule[cc];
            for (int c = 0; c < cc; c++)
                corrections[c] = new CorrectionRule(RandomWord(rng), RandomWord(rng));

            var state = new SettingsState(
                SchemaVersion: SettingsState.CurrentSchemaVersion,
                Mode: modes[rng.Next(modes.Length)],
                Model: models[rng.Next(models.Length)],
                Language: langs[rng.Next(langs.Length)],
                CustomWords: words,
                RemoveFillerWords: rng.Next(2) == 0,
                Corrections: corrections);

            var back = SettingsStateJson.Deserialize(SettingsStateJson.Serialize(state));
            Assert.Equal(state.Mode, back.Mode);
            Assert.Equal(state.Model, back.Model);
            Assert.Equal(state.Language, back.Language);
            Assert.Equal(state.CustomWords, back.CustomWords);
            Assert.Equal(state.RemoveFillerWords, back.RemoveFillerWords);
            Assert.Equal(state.Corrections, back.Corrections);
            Assert.Equal(SettingsState.CurrentSchemaVersion, back.SchemaVersion);
        }
    }

    // ===== corrections field (Windows-only) =====

    [Fact]
    public void RoundTrip_CorrectionsWithSpecialChars()
    {
        var state = SettingsState.Default with
        {
            Corrections = new[]
            {
                new CorrectionRule("web api", "web app"),
                new CorrectionRule("a\"b\\c", "d\te\nf"),
                new CorrectionRule("é", "unicode"),
            },
        };
        var back = SettingsStateJson.Deserialize(SettingsStateJson.Serialize(state));
        Assert.Equal(state.Corrections, back.Corrections);
    }

    [Fact]
    public void Deserialize_MissingCorrections_DefaultsToEmpty()
    {
        // Older build / macOS file with no `corrections` key.
        var s = SettingsStateJson.Deserialize(
            """{ "schemaVersion": 1, "mode": "Casual", "customWords": ["X"] }""");
        Assert.Empty(s.Corrections);
        Assert.Equal(new[] { "X" }, s.CustomWords);
    }

    [Fact]
    public void Deserialize_MalformedCorrectionEntries_AreSkipped()
    {
        // Non-object entries, and objects missing a string from/to, are dropped;
        // only the well-formed pair survives.
        string json = """
            { "corrections": [
                { "from": "web api", "to": "web app" },
                { "from": "missing-to" },
                { "to": "missing-from" },
                { "from": 5, "to": "wrongtype" },
                "not-an-object",
                42
            ] }
            """;
        var s = SettingsStateJson.Deserialize(json);
        Assert.Equal(new[] { new CorrectionRule("web api", "web app") }, s.Corrections);
    }

    [Fact]
    public void Deserialize_CorrectionsWrongType_DefaultsToEmpty()
    {
        var s = SettingsStateJson.Deserialize("""{ "corrections": "not-an-array" }""");
        Assert.Empty(s.Corrections);
    }

    private static string RandomWord(Random rng)
    {
        const string alpha = "abc XYZ 123 \"\\/,.-_'";
        int n = rng.Next(0, 8);
        var sb = new System.Text.StringBuilder(n);
        for (int i = 0; i < n; i++) sb.Append(alpha[rng.Next(alpha.Length)]);
        return sb.ToString();
    }
}
