namespace JVoice.App.Platform;

/// Ensures a single running JVoice instance via a named mutex. Phase 4 calls
/// TryAcquire() in App startup; a second instance gets false and exits (after
/// optionally signaling the first to show its window — Phase 4 wiring).
/// The Local\ prefix scopes the mutex per user session (a tray app is per-user).
public static class SingleInstance
{
    // Unique, stable name. Per-user (Local\) so two different users can each run one.
    private const string MutexName = @"Local\JVoice.SingleInstance.{8F3A1C2B-7E64-4D9A-9C1F-2A5B6E0D4F71}";

    private static Mutex? _mutex;

    public static bool TryAcquire()
    {
        if (_mutex is not null) return true; // already acquired in this process
        // createdNew == true means no other instance held it.
        _mutex = new Mutex(initiallyOwned: true, MutexName, out bool createdNew);
        if (!createdNew)
        {
            _mutex.Dispose();
            _mutex = null;
            return false;
        }
        return true;
    }

    public static void Release()
    {
        try { _mutex?.ReleaseMutex(); } catch (ApplicationException) { /* not owned */ }
        _mutex?.Dispose();
        _mutex = null;
    }
}
