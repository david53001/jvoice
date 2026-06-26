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
            Corrections: new[] { new CorrectionRule("web api", "web app") },
            Hotkey: new HotkeyChord(HotkeyModifiers.Control | HotkeyModifiers.Alt, 0x70, "F1"),
            GameMode: GameDetectionMode.Aggressive,
            DeveloperTerms: false);

        string json = SettingsStateJson.Serialize(original);
        var back = SettingsStateJson.Deserialize(json);

        Assert.Equal(original.Mode, back.Mode);
        Assert.Equal(original.Model, back.Model);
        Assert.Equal(original.Language, back.Language);
        Assert.Equal(original.CustomWords, back.CustomWords);
        Assert.Equal(original.RemoveFillerWords, back.RemoveFillerWords);
        Assert.Equal(original.Corrections, back.Corrections);
        Assert.Equal(original.Hotkey, back.Hotkey);
        Assert.Equal(original.GameMode, back.GameMode);
        Assert.Equal(original.DeveloperTerms, back.DeveloperTerms);
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
            { "schemaVersion": 3, "mode": "Casual", "model": "Tiny",
              "language": "English", "customWords": [], "removeFillerWords": true }
            """;
        var ex = Assert.Throws<ForwardVersionException>(() => SettingsStateJson.Deserialize(json));
        Assert.Equal(3, ex.FileVersion);
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
    // Windows port adds four extra on-disk keys with no macOS counterpart: `corrections`,
    // `developerTerms` (the developer-terms pack toggle), `gameMode` (the game-detection
    // suppression setting), and `hotkey` (the global-hotkey chord) — so Serialize emits exactly
    // those ten keys. Older builds / the macOS app simply ignore the unknown keys on read;
    // Deserialize tolerates their absence (a v1 file with no `gameMode` defaults to Balanced, no
    // `developerTerms` defaults to ON, no `hotkey` defaults to Ctrl+Shift+Space).
    [Fact]
    public void Serialize_EmitsExactlyTheTenKeys()
    {
        using var doc = JsonDocument.Parse(SettingsStateJson.Serialize(SettingsState.Default));
        var keys = doc.RootElement.EnumerateObject().Select(p => p.Name).OrderBy(n => n).ToArray();
        Assert.Equal(
            new[] { "corrections", "customWords", "developerTerms", "gameMode", "hotkey", "language", "mode", "model", "removeFillerWords", "schemaVersion" },
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
        var gameModes = Enum.GetValues<GameDetectionMode>();
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
                Corrections: corrections,
                Hotkey: RandomChord(rng),
                GameMode: gameModes[rng.Next(gameModes.Length)],
                DeveloperTerms: rng.Next(2) == 0);

            var back = SettingsStateJson.Deserialize(SettingsStateJson.Serialize(state));
            Assert.Equal(state.Mode, back.Mode);
            Assert.Equal(state.Model, back.Model);
            Assert.Equal(state.Language, back.Language);
            Assert.Equal(state.CustomWords, back.CustomWords);
            Assert.Equal(state.RemoveFillerWords, back.RemoveFillerWords);
            Assert.Equal(state.Corrections, back.Corrections);
            Assert.Equal(state.Hotkey, back.Hotkey);
            Assert.Equal(state.GameMode, back.GameMode);
            Assert.Equal(state.DeveloperTerms, back.DeveloperTerms);
            Assert.Equal(SettingsState.CurrentSchemaVersion, back.SchemaVersion);
        }
    }

    // ===== hotkey field (Windows-only, structural; default Ctrl+Shift+Space) =====

    // Every chord the recorder can produce round-trips losslessly: any modifier combo (incl. none),
    // and main keys whose KeyName (a WPF Key name) HotkeyChord.TryParse would NOT understand —
    // proving the structural (modifiers/virtualKey/keyName) representation, not a Format()/TryParse
    // string, is what's persisted.
    [Theory]
    [InlineData((int)(HotkeyModifiers.Control | HotkeyModifiers.Shift), 0x20, "Space")]   // the default
    [InlineData((int)HotkeyModifiers.None, 0x76, "F7")]                                    // no modifiers
    [InlineData((int)HotkeyModifiers.Win, 0x4A, "J")]                                      // Win+letter
    [InlineData((int)(HotkeyModifiers.Control | HotkeyModifiers.Alt | HotkeyModifiers.Shift | HotkeyModifiers.Win), 0xBC, "OemComma")] // all mods + a name TryParse can't handle
    public void RoundTrip_Hotkey_PreservesEveryChord(int mods, int vk, string keyName)
    {
        var chord = new HotkeyChord((HotkeyModifiers)mods, vk, keyName);
        var back = SettingsStateJson.Deserialize(
            SettingsStateJson.Serialize(SettingsState.Default with { Hotkey = chord }));
        Assert.Equal(chord, back.Hotkey);
    }

    [Fact]
    public void Serialize_WritesHotkeyStructurally()
    {
        var chord = new HotkeyChord(HotkeyModifiers.Control | HotkeyModifiers.Shift, 0x20, "Space");
        using var doc = JsonDocument.Parse(
            SettingsStateJson.Serialize(SettingsState.Default with { Hotkey = chord }));
        var h = doc.RootElement.GetProperty("hotkey");
        Assert.Equal((int)(HotkeyModifiers.Control | HotkeyModifiers.Shift), h.GetProperty("modifiers").GetInt32());
        Assert.Equal(0x20, h.GetProperty("virtualKey").GetInt32());
        Assert.Equal("Space", h.GetProperty("keyName").GetString());
    }

    [Fact]
    public void Deserialize_MissingHotkey_DefaultsToCtrlShiftSpace()
    {
        // Older build / macOS file with no `hotkey` key → Ctrl+Shift+Space.
        var s = SettingsStateJson.Deserialize(
            """{ "schemaVersion": 1, "mode": "Casual", "customWords": ["X"] }""");
        Assert.Equal(HotkeyChord.Default, s.Hotkey);
    }

    [Theory]
    [InlineData("""{ "hotkey": "not-an-object" }""")]                                  // wrong type
    [InlineData("""{ "hotkey": { "modifiers": 5, "keyName": "Space" } }""")]           // missing virtualKey
    [InlineData("""{ "hotkey": { "modifiers": 5, "virtualKey": 0, "keyName": "X" } }""")] // VK out of range
    [InlineData("""{ "hotkey": { "modifiers": 5, "virtualKey": 300, "keyName": "X" } }""")] // VK out of range
    [InlineData("""{ "hotkey": { "modifiers": 5, "virtualKey": 32, "keyName": "" } }""")]  // blank keyName
    [InlineData("""{ "hotkey": { "virtualKey": 32, "keyName": "Space" } }""")]          // missing modifiers
    public void Deserialize_MalformedHotkey_FallsBackToDefault(string json)
        => Assert.Equal(HotkeyChord.Default, SettingsStateJson.Deserialize(json).Hotkey);

    [Fact]
    public void Deserialize_HotkeyWithZeroModifiers_IsHonored()
    {
        // modifiers == 0 is a legitimate chord (e.g. a bare function key), NOT a fallback trigger.
        var s = SettingsStateJson.Deserialize(
            """{ "hotkey": { "modifiers": 0, "virtualKey": 118, "keyName": "F7" } }""");
        Assert.Equal(new HotkeyChord(HotkeyModifiers.None, 0x76, "F7"), s.Hotkey);
    }

    private static HotkeyChord RandomChord(Random rng)
    {
        var mods = (HotkeyModifiers)rng.Next(0, 16); // any combination of the 4 modifier bits
        (int vk, string name)[] keys =
        {
            (0x20, "Space"), (0x4A, "J"), (0x70, "F1"), (0x76, "F7"),
            (0x0D, "Enter"), (0xBC, "OemComma"), (0x31, "D1"), (0x60, "NumPad0"),
        };
        var (vk, name) = keys[rng.Next(keys.Length)];
        return new HotkeyChord(mods, vk, name);
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

    // ===== developerTerms field (Windows-only, default ON) =====

    [Fact]
    public void Deserialize_MissingDeveloperTerms_DefaultsToTrue()
    {
        // Older build / macOS file with no `developerTerms` key → pack is ON.
        var s = SettingsStateJson.Deserialize(
            """{ "schemaVersion": 1, "mode": "Casual", "customWords": ["X"] }""");
        Assert.True(s.DeveloperTerms);
    }

    [Fact]
    public void Deserialize_DeveloperTermsFalse_IsHonored()
    {
        var s = SettingsStateJson.Deserialize("""{ "developerTerms": false }""");
        Assert.False(s.DeveloperTerms);
    }

    [Fact]
    public void Deserialize_DeveloperTermsWrongType_DefaultsToTrue()
    {
        var s = SettingsStateJson.Deserialize("""{ "developerTerms": "notabool" }""");
        Assert.True(s.DeveloperTerms);
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
