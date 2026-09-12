namespace JVoice.Core.Models;

/// A Windows-only "app-aware mode" rule: when the foreground app's exe name matches
/// <see cref="AppMatch"/> (case-insensitive substring), dictation uses <see cref="Mode"/>
/// instead of the user's global tone. Persisted in SettingsState (schema v3). No macOS equivalent.
public sealed record AppModeRule(string AppMatch, ToneStyle Mode);
