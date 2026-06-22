namespace JVoice.Core.Text;

/// Builds the decoder-conditioning prompt from the user's custom words
/// (OpenAI's `initial_prompt` technique). Ports VocabularyPrompt.swift verbatim.
public static class VocabularyPrompt
{
    /// Cap on words included — keeps the decoder prefill cheap.
    public const int MaxWords = 40;
    /// Hard cap on encoded tokens (consumed by the engine when tokenizing).
    public const int MaxPromptTokens = 96;

    /// The conditioning text, or null when there is nothing to bias toward.
    public static string? Text(IReadOnlyList<string> words)
    {
        var cleaned = new List<string>(words.Count);
        foreach (var w in words)
        {
            var t = w.Trim();
            if (t.Length > 0) cleaned.Add(t);
        }
        if (cleaned.Count == 0) return null;
        // Leading space matters: Whisper's BPE merges a leading space into word tokens.
        return " " + string.Join(", ", cleaned.Take(MaxWords));
    }
}
