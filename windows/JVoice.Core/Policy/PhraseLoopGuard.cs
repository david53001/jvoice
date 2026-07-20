using JVoice.Core.Text;

namespace JVoice.Core.Policy;

/// §7 #42 — the phrase-loop guard (Windows-only; no macOS equivalent).
///
/// Failure mode (David-reported 2026-07-20, reproduced deterministically on the real clip
/// capture-20260720-225708-670.wav): on a long dictation the vocabulary-PROMPTED decode can
/// lock into whisper's classic repetition loop — "You're not a man of Caesar." × 16 —
/// MID-transcript, overwriting real speech while claiming full timestamp coverage, so both
/// existing detectors are blind: TailCoverageGuard sees no uncovered tail, and
/// RepetitionGuard only strips a TRAILING vocab/loop-dense run (this loop's phrase is
/// stopword-heavy — density 0.5 < 0.7 — and normal text resumes after it).
///
/// Measured discriminator (2026-07-20, --bench on the real clip, 3/3 iterations): the
/// UNPROMPTED decode of the same audio is clean and MORE complete — it restored the words
/// the loop swallowed ("Now John 19.", "You oppose Caesar."). Same prompt-failure class
/// RegurgitationRecovery already contains, so the remedy follows its shape: a detected
/// loop triggers a witness re-decode WITHOUT the prompt, and the witness is preferred
/// wholesale (unlike SilenceHallucinationGate, where the witness only vouches — here the
/// looped primary is known-lossy). Deterministic collapse is the last line: whatever text
/// is chosen, a run of MinRepeats+ identical phrases can never reach the paste.
public static class PhraseLoopGuard
{
    /// Consecutive occurrences of the same phrase that count as a decoder loop. Genuine
    /// dictation repeats stay below it — "Crucify him, crucify him" (2×), "Holy, holy,
    /// holy" (3×) — while the observed loop ran 16×.
    public const int MinRepeats = 4;

    /// Longest phrase (in tokens) considered as a loop unit. The observed loop phrase was
    /// 6 tokens; decoder loops repeat short n-grams, and a longer window would make an
    /// entire genuinely-repeated sentence collapsible.
    public const int MaxPhraseTokens = 12;

    public readonly record struct CollapseResult(string Text, bool FoundLoop);

    /// True when the text contains a run of MinRepeats+ consecutive identical phrases.
    public static bool HasLoop(string text) => Collapse(text).FoundLoop;

    /// Collapse every run of MinRepeats+ consecutive identical phrases to its FIRST
    /// occurrence (verbatim tokens). Phrases match on RepetitionGuard.Core token
    /// normalization — case- and punctuation-insensitive — so "Caesar." repeats match
    /// "Caesar,". A trailing PARTIAL repeat is deliberately left in place: absorbing it
    /// could eat a genuine sentence start that shares the phrase's first words. When no
    /// loop is found the ORIGINAL string is returned untouched (whitespace preserved).
    public static CollapseResult Collapse(string text)
    {
        var tokens = text.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
        int n = tokens.Length;
        if (n < MinRepeats) return new CollapseResult(text, false);

        var cores = new string[n];
        for (int i = 0; i < n; i++) cores[i] = RepetitionGuard.Core(tokens[i]);

        var kept = new List<string>(n);
        bool found = false;
        int idx = 0;
        while (idx < n)
        {
            var (len, count) = BestRunAt(idx, cores, n);
            if (count >= MinRepeats)
            {
                found = true;
                for (int k = 0; k < len; k++) kept.Add(tokens[idx + k]);
                idx += len * count;
            }
            else
            {
                kept.Add(tokens[idx]);
                idx++;
            }
        }
        return found ? new CollapseResult(string.Join(" ", kept), true) : new CollapseResult(text, false);
    }

    /// Choose the healed transcript after a loop was detected in `loopedPrimary`:
    /// the collapsed WITNESS (the same audio re-decoded without the prompt) when it has
    /// text — it carries the speech the loop overwrote — else the collapsed primary
    /// (prompt already off, or the witness came back empty). Never returns looped text.
    public static string Resolve(string loopedPrimary, string unpromptedWitness)
    {
        string witness = string.IsNullOrWhiteSpace(unpromptedWitness)
            ? "" : Collapse(unpromptedWitness).Text;
        return witness.Length > 0 ? witness : Collapse(loopedPrimary).Text;
    }

    /// The best loop starting exactly at `start`: the (phrase length, repeat count) whose
    /// run covers the most tokens, ties to the SMALLEST period (len ascends, strict >).
    /// A candidate phrase must contain at least one real word (non-empty core).
    private static (int Len, int Count) BestRunAt(int start, string[] cores, int n)
    {
        int bestLen = 0, bestCount = 0, bestCoverage = 0;
        int maxLen = Math.Min(MaxPhraseTokens, (n - start) / MinRepeats);
        for (int len = 1; len <= maxLen; len++)
        {
            bool hasWord = false;
            for (int k = 0; k < len && !hasWord; k++) hasWord = cores[start + k].Length > 0;
            if (!hasWord) continue;

            int count = 1;
            while (start + (count + 1) * len <= n
                   && SameCoreSequence(cores, start, start + count * len, len))
                count++;

            int coverage = len * count;
            if (count >= MinRepeats && coverage > bestCoverage)
            {
                bestLen = len; bestCount = count; bestCoverage = coverage;
            }
        }
        return (bestLen, bestCount);
    }

    private static bool SameCoreSequence(string[] cores, int a, int b, int len)
    {
        for (int k = 0; k < len; k++)
            if (!string.Equals(cores[a + k], cores[b + k], StringComparison.Ordinal)) return false;
        return true;
    }
}
