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

    public static bool TryAcquire() => TryAcquire(0);

    /// Acquire the single-instance slot, optionally retrying for up to `timeoutMs`. The wait is
    /// used during an elevated relaunch: the outgoing (non-elevated) instance is shutting down and
    /// releasing the mutex, and the incoming elevated copy must wait for that handoff rather than
    /// see "already running" and exit. timeoutMs == 0 → the original single-shot behaviour.
    public static bool TryAcquire(int timeoutMs)
    {
        if (_mutex is not null) return true; // already acquired in this process
        long deadline = Environment.TickCount64 + Math.Max(0, timeoutMs);
        while (true)
        {
            try
            {
                // createdNew == true means no other instance held it.
                var m = new Mutex(initiallyOwned: true, MutexName, out bool createdNew);
                if (createdNew) { _mutex = m; return true; }
                m.Dispose();
            }
            catch (UnauthorizedAccessException)
            {
                // The named mutex exists but is owned by a HIGHER-integrity instance whose object
                // we can't open (an elevated JVoice is already running). Treat as "another instance".
            }
            if (Environment.TickCount64 >= deadline) return false;
            Thread.Sleep(100);
        }
    }

    public static void Release()
    {
        try { _mutex?.ReleaseMutex(); } catch (ApplicationException) { /* not owned */ }
        _mutex?.Dispose();
        _mutex = null;
    }
}
