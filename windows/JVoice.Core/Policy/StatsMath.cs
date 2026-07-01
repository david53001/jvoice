namespace JVoice.Core;

/// Pure dictation-stats math. Faithful port of StatsStore.averageWPM:
/// words per minute = (totalWords / totalSeconds) * 60, guarded to 0 when no time.
public static class StatsMath
{
    public static double AverageWpm(int totalWords, double totalSeconds)
    {
        // Faithful negation of Swift's `guard totalSeconds > 0 else return 0`: this returns 0 for
        // <= 0 AND for NaN (NaN > 0 is false), where the old `<= 0` guard let NaN through → NaN.
        if (!(totalSeconds > 0)) return 0;
        return (double)totalWords / totalSeconds * 60.0;
    }

    /// Whether a (words, durationSeconds) sample should be recorded — faithful port of
    /// StatsStore.record's `guard words > 0, durationSeconds > 0`. Crucially `seconds > 0` is
    /// FALSE for NaN, so a NaN duration is rejected (the old `durationSeconds <= 0` negation let
    /// NaN through, poisoning totalSeconds and breaking JSON serialization) — same class as the
    /// AverageWpm guard above.
    public static bool ShouldRecord(int words, double durationSeconds)
        => words > 0 && durationSeconds > 0;

    /// Words-per-minute a competent typist is assumed to sustain, used as the baseline the
    /// "time saved" stat measures dictation against. 40 wpm is a conservative average-typist rate.
    public const double TypingWpmBaseline = 40.0;

    /// Windows-only "time saved" estimate (minutes): how much longer it would have taken to TYPE
    /// the dictated words (at TypingWpmBaseline) than it took to SPEAK them. Floored at 0 so a slow
    /// dictation never reports negative savings. NaN/negative seconds are treated as 0 spoken time
    /// (same NaN-safety intent as AverageWpm/ShouldRecord — `seconds > 0` is false for NaN).
    public static double EstimatedMinutesSaved(int totalWords, double totalSeconds)
    {
        if (totalWords <= 0) return 0;
        double typingMinutes = totalWords / TypingWpmBaseline;
        double spokenMinutes = totalSeconds > 0 ? totalSeconds / 60.0 : 0;
        double saved = typingMinutes - spokenMinutes;
        return saved > 0 ? saved : 0;
    }
}
