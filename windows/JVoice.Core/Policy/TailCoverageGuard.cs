namespace JVoice.Core.Policy;

/// §7 #39 — tail-coverage recovery (Windows-only; no macOS equivalent).
///
/// Failure mode (David-reported 2026-07-03): a whole-file decode sometimes ends EARLY —
/// the decoder emits EOT after the louder leading clause and the trailing words are never
/// transcribed even though they are fully present in the WAV (confirmed: rec=3.52 s,
/// 3.48 s of audio on disk, decode = only the first clause). The transcript looks clean,
/// so no text-level guard can catch it; what CAN catch it is whisper's own segment
/// timestamps: the last segment's END lands well before the end of the audio.
///
/// Policy (same witness philosophy as SilenceHallucinationGate): when the decode leaves
/// a big uncovered tail, re-decode JUST that tail and let the model decide. An empty
/// reduced tail decode means the tail really was silence (the user paused, then pressed
/// stop) — nothing is appended, no harm. A non-empty one is the user's lost trailing
/// words — appended. A containment check makes a duplicated boundary impossible to paste
/// twice. No RMS level is ever used to reject (§7 #21 stands): the trigger is timestamp
/// coverage, the decision is the model's.
public static class TailCoverageGuard
{
    /// Minimum uncovered audio (seconds past the last segment's end) before a recovery
    /// decode fires. Normal decodes cover to within ~1 s of the clip end (stop-press lag
    /// + timestamp slack); the observed truncation left ≈2.1 s uncovered. 1.5 s stays
    /// safely between the two, and also guarantees the recovery decode gets a clip long
    /// enough to transcribe on its own.
    public const double MinUncoveredSeconds = 1.5;

    /// True when a non-empty transcript left ≥ MinUncoveredSeconds of audio after the
    /// last decoded segment — the fingerprint of an early-EOT truncation OR a trailing
    /// pause (the recovery decode distinguishes the two; a pause decodes to empty).
    public static bool ShouldRecover(double audioSeconds, double lastSegmentEndSeconds)
        => lastSegmentEndSeconds > 0
           && audioSeconds - lastSegmentEndSeconds >= MinUncoveredSeconds;

    /// Merge the recovered tail into the transcript. Empty tail (the model confirmed
    /// silence) or a tail whose words are already present (timestamp slack made us
    /// re-decode audio that WAS transcribed) → transcript unchanged. Otherwise append.
    public static string Merge(string transcript, string recoveredTail)
    {
        string tail = recoveredTail.Trim();
        if (tail.Length == 0) return transcript;
        if (Normalize(transcript).Contains(Normalize(tail))) return transcript;
        return $"{transcript.TrimEnd()} {tail}";
    }

    /// Lowercased words with punctuation stripped, single-space joined — so the
    /// containment check can't be defeated by casing or punctuation drift between the
    /// two decodes.
    internal static string Normalize(string text)
    {
        var sb = new System.Text.StringBuilder(text.Length);
        bool pendingSpace = false;
        foreach (char c in text)
        {
            if (char.IsLetterOrDigit(c))
            {
                if (pendingSpace && sb.Length > 0) sb.Append(' ');
                pendingSpace = false;
                sb.Append(char.ToLowerInvariant(c));
            }
            else pendingSpace = true;
        }
        return sb.ToString();
    }
}
