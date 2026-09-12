namespace JVoice.Core.Policy;

/// §7 #38 — the silence-hallucination gate (Windows-only; no macOS equivalent).
///
/// Failure mode (David-reported, §7 #24): on a NEAR-SILENT press, the vocabulary-PROMPTED
/// decode sometimes invents a confident, plausible sentence ("you're welcome.", "you",
/// a vocab word like "app") that escapes the frozen RemoveWhisperHallucinations blocklist
/// and gets pasted. Whisper's own confidence is INVERTED here (it is MOST confident on
/// these inventions — measured avgConf up to 0.96 vs 0.58–0.81 for real speech), so no
/// confidence threshold works.
///
/// Measured discriminator (2026-07-02 calibration, 17 real capture clips, large-v3-turbo):
/// the UNPROMPTED decode of the same audio collapses to a stock phrase ("Thank you.") that
/// the blocklist already reduces to empty on 10/10 silent presses, while it keeps the real
/// sentence on 7/7 quiet-speech clips. So: when a decode looks suspicious (near-silent
/// audio that still produced text), re-decode WITHOUT the prompt and let that WITNESS
/// decide. The RMS level is only the cheap TRIGGER for the witness decode — the reject
/// decision is always the model's (an empty witness), so the retired-RMS-gate rule
/// (§7 #21: no level floor may reject speech) is preserved: a quiet real sentence
/// triggers verification and passes, because its witness keeps the words.
public static class SilenceHallucinationGate
{
    /// Verify-trigger level for the whole-clip peak-window RMS (HighPassSilence
    /// .PeakWindowRms). Calibrated 2026-07-02: every observed silent press measured
    /// ≤ 0.0003 (digital-level silence — 13× headroom), David's quietest REAL speech
    /// 0.0005–0.0028 (still verifies, passes via the witness), and his louder speech
    /// 0.004+ skips verification entirely (zero added latency). 0.004 is also his
    /// historic room-hum ceiling: noisier "silence" above it gets annotated by whisper
    /// itself ([BLANK_AUDIO] → NonSpeechAnnotation), which #21 already handles.
    public const float QuietRmsTrigger = 0.004f;

    /// True when the guarded transcript needs a witness decode: the clip is near-silent
    /// (below <see cref="QuietRmsTrigger"/>; NaN counts as quiet — the safe side) yet the
    /// prompted decode still produced text. Blank transcripts need no verification — the
    /// engine's empty path already reports "No speech detected."
    public static bool ShouldVerify(float rawRms, string promptedTranscript)
        => !string.IsNullOrWhiteSpace(promptedTranscript) && !(rawRms >= QuietRmsTrigger);

    /// Decide from the WITNESS — the same audio decoded WITHOUT the prompt, then fully
    /// reduced (NonSpeechAnnotation.Reduce + StripDecoderArtifacts +
    /// RemoveWhisperHallucinations). Empty witness ⇒ the prompted text was a silence
    /// hallucination ⇒ "" (no-speech). Otherwise keep the PROMPTED transcript — it is the
    /// vocab-accurate one; the witness only vouches that real speech exists.
    public static string Resolve(string promptedTranscript, string unpromptedWitness)
        => string.IsNullOrWhiteSpace(unpromptedWitness) ? "" : promptedTranscript;
}
