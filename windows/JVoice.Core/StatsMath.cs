namespace JVoice.Core;

/// Pure dictation-stats math. Faithful port of StatsStore.averageWPM:
/// words per minute = (totalWords / totalSeconds) * 60, guarded to 0 when no time.
public static class StatsMath
{
    public static double AverageWpm(int totalWords, double totalSeconds)
    {
        if (totalSeconds <= 0) return 0;
        return (double)totalWords / totalSeconds * 60.0;
    }
}
