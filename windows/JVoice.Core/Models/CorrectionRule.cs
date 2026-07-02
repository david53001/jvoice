namespace JVoice.Core.Models;

/// A user-defined transcription correction: when the recognizer produces
/// <see cref="From"/> (a word or multi-word phrase, matched case-insensitively),
/// replace it with <see cref="To"/> in the final text.
///
/// Windows-only feature (no macOS counterpart): the safety net for systematic
/// recognizer mishearings of common words (e.g. "web api" → "web app") that the
/// custom-words/decoder-prompt path can't fix, because the misheard word is a
/// *different* real word, not a spelling variant of the intended one. The user
/// opts into each rule, so a rule never touches words they didn't list — keeping
/// legitimate uses of the misheard word (e.g. "REST API") intact.
public sealed record CorrectionRule(string From, string To);
