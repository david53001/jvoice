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
}
