using System.Runtime.InteropServices;
using Microsoft.Win32;
using Microsoft.Win32.SafeHandles;

namespace JVoice.App.Platform;

/// Tells when anything under an HKCU key changed — a key added or removed, or a value written, anywhere in its
/// subtree — via RegNotifyChangeKeyValue, so a cache of that key is re-read only after a real change instead of on a
/// timer (review round 3 JV #4: GameDetector's periodic re-reads of GameConfigStore were the idle-CPU spikes).
/// Read-only: the key is opened for reading (KEY_READ includes KEY_NOTIFY); nothing is written, and no process is
/// touched (GameDetector's anti-cheat invariant).
internal sealed class RegistryChangeWatch : IDisposable
{
    private const int RegNotifyChangeName = 0x1;
    private const int RegNotifyChangeLastSet = 0x4;
    private const int RegNotifyThreadAgnostic = 0x10000000; // Windows 8+: the registration outlives the arming thread

    private readonly RegistryKey _key;
    private readonly AutoResetEvent _signal = new(false);
    private RegisteredWaitHandle? _wait;
    private int _changed = 1; // the first ask always reads
    private volatile bool _disposed;
    private volatile bool _broken; // the notification couldn't be re-armed: every ask reads

    private RegistryChangeWatch(RegistryKey key) => _key = key;

    /// A watch on HKCU\<paramref name="subKey"/>, or null when the key is absent or can't be watched (callers keep
    /// their timed re-read then).
    public static RegistryChangeWatch? TryCreate(string subKey)
    {
        RegistryKey? key = null;
        try
        {
            key = Registry.CurrentUser.OpenSubKey(subKey);
            if (key is null) return null;
            var watch = new RegistryChangeWatch(key);
            if (!watch.Arm()) { watch.Dispose(); return null; }
            watch._wait = ThreadPool.RegisterWaitForSingleObject(watch._signal, (_, _) => watch.OnSignal(), null, -1, executeOnlyOnce: false);
            return watch;
        }
        catch (Exception ex) when (ex is System.Security.SecurityException or UnauthorizedAccessException or System.IO.IOException)
        {
            key?.Dispose();
            return null;
        }
    }

    /// True once after each change (and on the first call); false while nothing changed.
    public bool ConsumeChanged() => Interlocked.Exchange(ref _changed, 0) == 1 || _broken;

    private bool Arm()
    {
        try
        {
            return RegNotifyChangeKeyValue(_key.Handle, true, RegNotifyChangeName | RegNotifyChangeLastSet | RegNotifyThreadAgnostic,
                _signal.SafeWaitHandle, true) == 0;
        }
        catch (ObjectDisposedException) { return false; }
    }

    private void OnSignal()
    {
        if (_disposed) return;
        Volatile.Write(ref _changed, 1);
        if (!Arm()) _broken = true; // couldn't re-arm (the key was deleted): every ask re-reads from now on
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        _wait?.Unregister(null);
        _key.Dispose(); // closing the key ends the pending notification
        _signal.Dispose();
    }

    [DllImport("advapi32.dll")]
    private static extern int RegNotifyChangeKeyValue(SafeRegistryHandle hKey, bool bWatchSubtree, int dwNotifyFilter,
        SafeWaitHandle hEvent, bool fAsynchronous);
}
