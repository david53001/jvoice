using System.Text.Json;

namespace JVoice.Core.Models;

/// Thrown when a settings file was written by a newer JVoice build
/// (schemaVersion > current). The caller (SettingsStore) treats this exactly
/// like corruption: reset to defaults and back up the original blob.
/// Ports the `DecodingError.dataCorruptedError` throw in SettingsState.init(from:).
public sealed class ForwardVersionException : Exception
{
    public int FileVersion { get; }
    public int CurrentVersion { get; }

    public ForwardVersionException(int fileVersion, int currentVersion)
        : base($"Settings written by a newer JVoice build (v{fileVersion} > v{currentVersion}). Refusing to read.")
    {
        FileVersion = fileVersion;
        CurrentVersion = currentVersion;
    }
}

/// Pure JSON (de)serialization for SettingsState. Faithful port of
/// SettingsState.swift's custom Codable: forward-version refusal, schemaVersion
/// normalized forward on write, and per-field fallback to defaults on missing or
/// unparseable values. No file I/O here (that's Platform/SettingsStore).
public static class SettingsStateJson
{
    private static readonly JsonSerializerOptions WriteOptions = new()
    {
        WriteIndented = true,
    };

    public static string Serialize(SettingsState state)
    {
        var dto = new
        {
            schemaVersion = SettingsState.CurrentSchemaVersion, // always normalize forward
            mode = state.Mode.ToString(),
            model = state.Model.ToString(),
            language = state.Language.ToString(),
            customWords = state.CustomWords,
            removeFillerWords = state.RemoveFillerWords,
            // Windows-only field (no macOS counterpart). Absent in files written by
            // older builds / the macOS app; ParseCorrections falls back to empty.
            corrections = state.Corrections.Select(c => new { from = c.From, to = c.To }),
            // Added in schema v2. Absent in v1 files; ParseGameMode falls back to Balanced.
            gameMode = state.GameMode.ToString(),
            // Windows-only opt-out flag for the curated developer-terms pack. Absent in
            // older / macOS files; Deserialize falls back to true (default ON).
            developerTerms = state.DeveloperTerms,
            // Windows-only global-hotkey chord (no macOS counterpart — macOS persists its
            // shortcut via the KeyboardShortcuts library). Stored structurally so any chord
            // round-trips losslessly (KeyName can be any WPF key name, which HotkeyChord.TryParse
            // doesn't always understand). Absent in older / macOS files; ParseHotkey falls back
            // to HotkeyChord.Default (Ctrl+Shift+Space).
            hotkey = new
            {
                modifiers = (int)state.Hotkey.Modifiers,
                virtualKey = state.Hotkey.VirtualKey,
                keyName = state.Hotkey.KeyName,
            },
            // ── v3 dictation-feature keys (Windows-only) ──
            copyToClipboardOnly = state.CopyToClipboardOnly,
            // Nullable: serialized as JSON null when undo-last-paste is disabled (the opt-in default).
            undoHotkey = state.UndoHotkey is { } uh
                ? (object?)new { modifiers = (int)uh.Modifiers, virtualKey = uh.VirtualKey, keyName = uh.KeyName }
                : null,
            translateToEnglish = state.TranslateToEnglish,
            appAwareModes = state.AppAwareModes,
            appModeRules = state.AppModeRules.Select(r => new { appMatch = r.AppMatch, mode = r.Mode.ToString() }),
        };
        return JsonSerializer.Serialize(dto, WriteOptions);
    }

    /// Parses a settings JSON blob. Throws <see cref="ForwardVersionException"/>
    /// when the file version is newer than we understand, and
    /// <see cref="JsonException"/> when the JSON is structurally invalid; every
    /// individual field falls back to its default rather than throwing.
    public static SettingsState Deserialize(string json)
    {
        using var doc = JsonDocument.Parse(json); // throws JsonException on bad JSON
        JsonElement root = doc.RootElement;
        if (root.ValueKind != JsonValueKind.Object)
            throw new JsonException("Settings root is not a JSON object.");

        int version = TryGetInt(root, "schemaVersion") ?? 0; // absent => 0 (Swift parity)
        if (version > SettingsState.CurrentSchemaVersion)
            throw new ForwardVersionException(version, SettingsState.CurrentSchemaVersion);

        return new SettingsState(
            SchemaVersion: SettingsState.CurrentSchemaVersion, // always normalized forward
            Mode: ParseTone(TryGetString(root, "mode")),
            Model: ParseModel(TryGetString(root, "model")),
            Language: ParseLanguage(TryGetString(root, "language")),
            CustomWords: ParseCustomWords(root),
            RemoveFillerWords: TryGetBool(root, "removeFillerWords") ?? true,
            Corrections: ParseCorrections(root),
            Hotkey: ParseHotkey(root),
            GameMode: ParseGameMode(TryGetString(root, "gameMode")),
            DeveloperTerms: TryGetBool(root, "developerTerms") ?? true,
            CopyToClipboardOnly: TryGetBool(root, "copyToClipboardOnly") ?? false,
            UndoHotkey: ParseUndoHotkey(root),
            TranslateToEnglish: TryGetBool(root, "translateToEnglish") ?? false,
            AppAwareModes: TryGetBool(root, "appAwareModes") ?? true,
            AppModeRules: ParseAppModeRules(root));
    }

    // field parsers (each falls back to the field default)

    private static ToneStyle ParseTone(string? raw)
    {
        if (raw is null) return ToneStyle.Casual;
        if (Enum.TryParse<ToneStyle>(raw, ignoreCase: true, out var v)) return v;
        return ToneStyle.Casual;
    }

    private static WhisperModelOption ParseModel(string? raw)
    {
        if (raw is null) return WhisperModelOption.Tiny;
        // Legacy macOS raw values (Swift WhisperModelOption rawValues + the pre-2026-06 alias).
        switch (raw)
        {
            case "large-v3_turbo":
            case "large-v3-v20240930":
                return WhisperModelOption.LargeTurbo;
            case "tiny": return WhisperModelOption.Tiny;
            case "base": return WhisperModelOption.Base;
            case "small": return WhisperModelOption.Small;
        }
        if (Enum.TryParse<WhisperModelOption>(raw, ignoreCase: true, out var v)) return v;
        return WhisperModelOption.Tiny;
    }

    private static TranscriptionLanguage ParseLanguage(string? raw)
    {
        if (raw is null) return TranscriptionLanguage.English;
        if (Enum.TryParse<TranscriptionLanguage>(raw, ignoreCase: true, out var v)) return v;
        return TranscriptionLanguage.English;
    }

    /// Absent in v1 files (field added in schema v2); missing or unrecognised value → Balanced.
    private static GameDetectionMode ParseGameMode(string? raw)
    {
        if (raw is null) return GameDetectionMode.Balanced;
        if (Enum.TryParse<GameDetectionMode>(raw, ignoreCase: true, out var v)) return v;
        return GameDetectionMode.Balanced;
    }

    private static IReadOnlyList<string> ParseCustomWords(JsonElement root)
    {
        if (!root.TryGetProperty("customWords", out var arr) || arr.ValueKind != JsonValueKind.Array)
            return Array.Empty<string>();
        var list = new List<string>();
        foreach (var el in arr.EnumerateArray())
            if (el.ValueKind == JsonValueKind.String && el.GetString() is { } s)
                list.Add(s);
        return list;
    }

    /// Parses the Windows-only `corrections` array: a list of `{ "from", "to" }`
    /// objects. Absent / wrong-typed array => empty. Individual entries missing a
    /// string `from` or `to` are skipped (per-field-fallback philosophy), never throwing.
    private static IReadOnlyList<CorrectionRule> ParseCorrections(JsonElement root)
    {
        if (!root.TryGetProperty("corrections", out var arr) || arr.ValueKind != JsonValueKind.Array)
            return Array.Empty<CorrectionRule>();
        var list = new List<CorrectionRule>();
        foreach (var el in arr.EnumerateArray())
        {
            if (el.ValueKind != JsonValueKind.Object) continue;
            string? from = TryGetString(el, "from");
            string? to = TryGetString(el, "to");
            if (from is null || to is null) continue;
            list.Add(new CorrectionRule(from, to));
        }
        return list;
    }

    /// Parses the Windows-only `hotkey` object: `{ "modifiers": <int flags>, "virtualKey":
    /// <int>, "keyName": "<string>" }`. Absent / wrong-typed / incomplete => HotkeyChord.Default
    /// (Ctrl+Shift+Space). A usable chord needs a real main key, so a missing/blank keyName or an
    /// out-of-range virtualKey falls back; modifiers may legitimately be 0 (e.g. a bare "F7").
    private static HotkeyChord ParseHotkey(JsonElement root)
    {
        if (!root.TryGetProperty("hotkey", out var h) || h.ValueKind != JsonValueKind.Object)
            return HotkeyChord.Default;

        int? modifiers = TryGetInt(h, "modifiers");
        int? virtualKey = TryGetInt(h, "virtualKey");
        string? keyName = TryGetString(h, "keyName");

        if (modifiers is null || virtualKey is not (> 0 and <= 0xFF) || string.IsNullOrEmpty(keyName))
            return HotkeyChord.Default;

        return new HotkeyChord((HotkeyModifiers)modifiers.Value, virtualKey.Value, keyName);
    }

    /// v3 opt-in undo-last-paste chord. Unlike the required `hotkey`, an absent / wrong-typed /
    /// incomplete value falls back to null (feature DISABLED), never to a default chord.
    private static HotkeyChord? ParseUndoHotkey(JsonElement root)
    {
        if (!root.TryGetProperty("undoHotkey", out var h) || h.ValueKind != JsonValueKind.Object)
            return null;

        int? modifiers = TryGetInt(h, "modifiers");
        int? virtualKey = TryGetInt(h, "virtualKey");
        string? keyName = TryGetString(h, "keyName");

        if (modifiers is null || virtualKey is not (> 0 and <= 0xFF) || string.IsNullOrEmpty(keyName))
            return null;

        return new HotkeyChord((HotkeyModifiers)modifiers.Value, virtualKey.Value, keyName);
    }

    /// v3 per-app mode rules: `[{ "appMatch": "code", "mode": "Code" }]`. Absent / wrong-typed
    /// array => empty. Entries missing a string `appMatch` are skipped; an absent / unrecognised
    /// `mode` falls back to Casual (ParseTone) — the per-field-fallback philosophy, never throwing.
    private static IReadOnlyList<AppModeRule> ParseAppModeRules(JsonElement root)
    {
        if (!root.TryGetProperty("appModeRules", out var arr) || arr.ValueKind != JsonValueKind.Array)
            return Array.Empty<AppModeRule>();
        var list = new List<AppModeRule>();
        foreach (var el in arr.EnumerateArray())
        {
            if (el.ValueKind != JsonValueKind.Object) continue;
            string? appMatch = TryGetString(el, "appMatch");
            if (appMatch is null) continue;
            list.Add(new AppModeRule(appMatch, ParseTone(TryGetString(el, "mode"))));
        }
        return list;
    }

    // lenient scalar readers (wrong type => null => field default)

    private static int? TryGetInt(JsonElement root, string name)
        => root.TryGetProperty(name, out var e) && e.ValueKind == JsonValueKind.Number && e.TryGetInt32(out int v)
            ? v : null;

    private static string? TryGetString(JsonElement root, string name)
        => root.TryGetProperty(name, out var e) && e.ValueKind == JsonValueKind.String
            ? e.GetString() : null;

    private static bool? TryGetBool(JsonElement root, string name)
        => root.TryGetProperty(name, out var e) && e.ValueKind is JsonValueKind.True or JsonValueKind.False
            ? e.GetBoolean() : null;
}
