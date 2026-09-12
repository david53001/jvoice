namespace JVoice.Core.Text;

/// The decode-and-recover policy that contains the vocabulary prompt's failure
/// mode. Faithful port of RegurgitationRecovery.swift.
public static class RegurgitationRecovery
{
    /// `decode(usePrompt)` runs the real model; called once in the common (clean)
    /// case and a second time, with usePrompt == false, only when the prompted
    /// decode shows regurgitation (loop removed) or came back empty.
    public static async Task<string> Decode(
        bool useVocabularyPrompt,
        IReadOnlyList<string> vocabulary,
        Func<bool, Task<string>> decode)
    {
        var primary = RepetitionGuard.Scrub(await decode(useVocabularyPrompt), vocabulary);
        if (!useVocabularyPrompt || !(primary.RemovedRegurgitation || primary.Text.Length == 0))
            return primary.Text;
        // The prompt regurgitated — a prompt-free decode transcribes what was actually spoken.
        return RepetitionGuard.Scrub(await decode(false), vocabulary).Text;
    }
}
