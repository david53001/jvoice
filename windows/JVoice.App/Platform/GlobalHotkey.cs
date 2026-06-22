using System.IO;
using System.Runtime.InteropServices;
using JVoice.Core;
using JVoice.Core.Models;

namespace JVoice.App.Platform;

/// System-wide hotkey via a low-level keyboard hook (WH_KEYBOARD_LL), running on a
/// dedicated thread with its own Win32 message loop (the hook only delivers to a
/// thread that pumps messages). Raises Triggered (debounced 150 ms) when the chord
/// is pressed. Faithful to HotKeyManager.swift's debounce + toggle semantics; the
/// hook approach (vs RegisterHotKey) is chosen for arbitrary-chord support, future
/// push-to-talk, and to avoid global-atom registration conflicts (see plan §Task 12).
public sealed class GlobalHotkey : IDisposable
{
    public event Action? Triggered;

    private const int WH_KEYBOARD_LL = 13;
    private const int WM_KEYDOWN = 0x0100;
    private const int WM_SYSKEYDOWN = 0x0104;
    private const uint WM_QUIT = 0x0012;
    private const uint WM_TIMER = 0x0113;

    // ---- self-healing watchdog (see HookThreadMain / WatchdogTick) ----
    // Windows 7+ SILENTLY removes a WH_KEYBOARD_LL hook if its callback ever exceeds
    // LowLevelHooksTimeout (~300 ms) — which happens when the hook thread is starved
    // during JVoice's heavy GPU transcription. Once evicted, the hook never fires
    // again and the hotkey is dead for the rest of the session. The watchdog detects
    // this and re-installs the hook. (Root cause of "the hotkey stopped working".)
    private const uint WatchdogIntervalMs = 1000;   // how often to check hook liveness
    private const int HookStaleThresholdMs = 3000;  // system input newer than our last
                                                    // callback by this much => re-arm

    // Modifier virtual-key codes we read live via GetAsyncKeyState.
    private const int VK_CONTROL = 0x11;
    private const int VK_MENU = 0x12;   // Alt
    private const int VK_SHIFT = 0x10;
    private const int VK_LWIN = 0x5B;
    private const int VK_RWIN = 0x5C;

    // Opt-in field diagnostics: set env JVOICE_HOTKEY_LOG=1 to trace hook install +
    // every main-key-down match decision to %TEMP%\jvoice-hotkey.log. Off (zero cost)
    // otherwise. Kept in-tree as a permanent troubleshooting aid for the global hook,
    // which is hardware/OS-dependent and otherwise invisible to debug.
    private static readonly bool _log = Environment.GetEnvironmentVariable("JVOICE_HOTKEY_LOG") == "1";
    private static void Log(string m)
    {
        if (!_log) return;
        try { File.AppendAllText(Path.Combine(Path.GetTempPath(), "jvoice-hotkey.log"), $"{DateTime.Now:HH:mm:ss.fff} [{Environment.CurrentManagedThreadId}] {m}{Environment.NewLine}"); }
        catch { /* logging must never throw into the hook */ }
    }

    // TEST-ONLY seams (env-gated, zero cost when unset) for the hotkey-probe to
    // reproduce-and-verify the eviction/recovery path that is otherwise OS-timing
    // dependent and impossible to unit-test in CI:
    //   JVOICE_HOTKEY_TEST_STALL_MS=<n>  one-shot Sleep(n) inside the callback to
    //                                    force Windows to evict the hook (simulates a stall).
    //   JVOICE_HOTKEY_NO_WATCHDOG=1      disable the self-heal (proves the bug without the fix).
    private static readonly int _testStallMs =
        int.TryParse(Environment.GetEnvironmentVariable("JVOICE_HOTKEY_TEST_STALL_MS"), out var v) && v > 0 ? v : 0;
    private static readonly bool _noWatchdog = Environment.GetEnvironmentVariable("JVOICE_HOTKEY_NO_WATCHDOG") == "1";
    private bool _didTestStall;

    private readonly object _gate = new();
    private Thread? _thread;
    private uint _threadId;
    private IntPtr _hook = IntPtr.Zero;
    private UIntPtr _timerId;
    private LowLevelKeyboardProc? _proc; // keep alive
    private HotkeyChord _chord = HotkeyChord.Default;
    private long _lastFiredTicks;
    private int _lastCallbackTick; // Environment.TickCount of the last hook callback
                                   // (hook-thread only; the watchdog's liveness signal)
    private volatile bool _running;

    public void Register(HotkeyChord chord)
    {
        lock (_gate)
        {
            _chord = chord;
            if (_running) return; // already hooked; chord swap takes effect immediately
            _running = true;
            _thread = new Thread(HookThreadMain)
            {
                IsBackground = true,
                Name = "JVoice-GlobalHotkey",
                // High priority so the (trivial) hook callback is scheduled promptly and
                // returns well within LowLevelHooksTimeout even while the GPU/CPU is pegged
                // by transcription — the main way to AVOID the silent eviction in the first
                // place. The watchdog (below) recovers if eviction still slips through.
                Priority = ThreadPriority.Highest,
            };
            _thread.SetApartmentState(ApartmentState.STA);
            _thread.Start();
        }
    }

    public void Unregister()
    {
        Thread? t;
        uint tid;
        lock (_gate)
        {
            if (!_running) return;
            _running = false;
            t = _thread;
            tid = _threadId;
            _thread = null;
        }
        if (tid != 0) PostThreadMessage(tid, WM_QUIT, IntPtr.Zero, IntPtr.Zero);
        t?.Join(1000);
    }

    public void Dispose() => Unregister();

    private void HookThreadMain()
    {
        _threadId = GetCurrentThreadId();
        _proc = HookCallback;
        IntPtr hmod = GetModuleHandle(null);
        _hook = SetWindowsHookEx(WH_KEYBOARD_LL, _proc, hmod, 0);
        _lastCallbackTick = Environment.TickCount; // seed liveness so we don't re-arm at once
        Log($"SetWindowsHookEx -> hook=0x{_hook:X} err={Marshal.GetLastWin32Error()} hmod=0x{hmod:X}");

        // Watchdog tick (a thread WM_TIMER) so the hook self-heals after Windows
        // silently evicts it. NULL hwnd => the timer posts WM_TIMER to this thread's
        // queue, retrieved by the GetMessage pump below.
        if (!_noWatchdog) _timerId = SetTimer(IntPtr.Zero, UIntPtr.Zero, WatchdogIntervalMs, IntPtr.Zero);

        // Standard message pump — required for WH_KEYBOARD_LL callbacks to fire.
        while (_running && GetMessage(out MSG msg, IntPtr.Zero, 0, 0) > 0)
        {
            if (msg.message == WM_TIMER) WatchdogTick();
            TranslateMessage(ref msg);
            DispatchMessage(ref msg);
        }
        Log($"hook thread message loop exited (_running={_running})");

        if (_timerId != UIntPtr.Zero)
        {
            KillTimer(IntPtr.Zero, _timerId);
            _timerId = UIntPtr.Zero;
        }
        if (_hook != IntPtr.Zero)
        {
            UnhookWindowsHookEx(_hook);
            _hook = IntPtr.Zero;
        }
        _proc = null;
        _threadId = 0;
    }

    private IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0)
        {
            _lastCallbackTick = Environment.TickCount; // proof the hook is alive & receiving
            int msg = (int)wParam;
            if (msg == WM_KEYDOWN || msg == WM_SYSKEYDOWN)
            {
                // TEST-ONLY: one-shot stall to force Windows' eviction (see _testStallMs).
                if (_testStallMs > 0 && !_didTestStall) { _didTestStall = true; Thread.Sleep(_testStallMs); }

                var data = Marshal.PtrToStructure<KBDLLHOOKSTRUCT>(lParam);
                if (MatchesChord((int)data.vkCode))
                {
                    if (TryDebounce())
                    {
                        Log("chord matched + debounce passed -> raising Triggered");
                        Triggered?.Invoke(); // raised on the hook thread; Phase 4 marshals
                    }
                    // Do NOT swallow the key: keep behavior transparent. If a future
                    // build wants to suppress it, return (IntPtr)1.
                }
            }
        }
        return CallNextHookEx(_hook, nCode, wParam, lParam);
    }

    /// Self-heal: detect Windows' silent eviction of our low-level hook and re-install
    /// it. Liveness signal = GetLastInputInfo (system-wide last input tick, key OR mouse,
    /// independent of our hook) vs _lastCallbackTick (our hook's last callback). If the
    /// system has registered input materially newer than our hook last saw, our hook is
    /// no longer in the chain — re-arm. Runs on the hook thread (serialized with the
    /// callback), so _hook/_lastCallbackTick need no locking.
    private void WatchdogTick()
    {
        var lii = new LASTINPUTINFO { cbSize = (uint)Marshal.SizeOf<LASTINPUTINFO>() };
        if (!GetLastInputInfo(ref lii)) return;
        int sysLast = (int)lii.dwTime;                       // GetTickCount domain (32-bit ms)
        int gap = unchecked(sysLast - _lastCallbackTick);    // wrap-safe difference
        if (gap > HookStaleThresholdMs)
        {
            Log($"watchdog: hook appears evicted (gap={gap}ms) -> re-arming");
            RearmHook();
            // Treat now as fresh so a long mouse-only stretch (our keyboard hook sees
            // nothing, yet the hook may be perfectly healthy) re-arms at most once per
            // threshold window rather than every tick.
            _lastCallbackTick = sysLast;
        }
    }

    /// Install a fresh hook BEFORE removing the old one so there is never a gap where a
    /// keypress could slip through unhooked; the 150 ms debounce absorbs any transient
    /// double-delivery while both are briefly live.
    private void RearmHook()
    {
        if (_proc is null) return;
        IntPtr old = _hook;
        IntPtr fresh = SetWindowsHookEx(WH_KEYBOARD_LL, _proc, GetModuleHandle(null), 0);
        if (fresh != IntPtr.Zero)
        {
            _hook = fresh;
            if (old != IntPtr.Zero) UnhookWindowsHookEx(old);
            Log($"watchdog: re-armed hook old=0x{old:X} new=0x{fresh:X}");
        }
        else
        {
            Log($"watchdog: re-arm FAILED err={Marshal.GetLastWin32Error()} (kept old=0x{old:X})");
        }
    }

    private bool MatchesChord(int vkCode)
    {
        HotkeyChord chord;
        lock (_gate) chord = _chord;
        if (vkCode != chord.VirtualKey) return false;

        bool ctrl = IsDown(VK_CONTROL);
        bool alt = IsDown(VK_MENU);
        bool shift = IsDown(VK_SHIFT);
        bool win = IsDown(VK_LWIN) || IsDown(VK_RWIN);

        bool wantCtrl = chord.Modifiers.HasFlag(HotkeyModifiers.Control);
        bool wantAlt = chord.Modifiers.HasFlag(HotkeyModifiers.Alt);
        bool wantShift = chord.Modifiers.HasFlag(HotkeyModifiers.Shift);
        bool wantWin = chord.Modifiers.HasFlag(HotkeyModifiers.Win);

        bool match = ctrl == wantCtrl && alt == wantAlt && shift == wantShift && win == wantWin;
        Log($"main-key down vk=0x{vkCode:X2} ctrl={ctrl}/{wantCtrl} alt={alt}/{wantAlt} shift={shift}/{wantShift} win={win}/{wantWin} -> match={match}");
        return match;
    }

    private bool TryDebounce()
    {
        long now = Environment.TickCount64;
        lock (_gate)
        {
            if (now - _lastFiredTicks < AppTimings.HotkeyDebounceMs) return false;
            _lastFiredTicks = now;
            return true;
        }
    }

    private static bool IsDown(int vk) => (GetAsyncKeyState(vk) & 0x8000) != 0;

    // P/Invoke

    [StructLayout(LayoutKind.Sequential)]
    private struct KBDLLHOOKSTRUCT
    {
        public uint vkCode;
        public uint scanCode;
        public uint flags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct LASTINPUTINFO
    {
        public uint cbSize;
        public uint dwTime;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MSG
    {
        public IntPtr hwnd;
        public uint message;
        public IntPtr wParam;
        public IntPtr lParam;
        public uint time;
        public int pt_x;
        public int pt_y;
    }

    private delegate IntPtr LowLevelKeyboardProc(int nCode, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SetWindowsHookEx(int idHook, LowLevelKeyboardProc lpfn, IntPtr hMod, uint dwThreadId);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool UnhookWindowsHookEx(IntPtr hhk);

    [DllImport("user32.dll")]
    private static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern short GetAsyncKeyState(int vKey);

    [DllImport("kernel32.dll")]
    private static extern IntPtr GetModuleHandle(string? lpModuleName);

    [DllImport("kernel32.dll")]
    private static extern uint GetCurrentThreadId();

    [DllImport("user32.dll")]
    private static extern int GetMessage(out MSG lpMsg, IntPtr hWnd, uint wMsgFilterMin, uint wMsgFilterMax);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool TranslateMessage(ref MSG lpMsg);

    [DllImport("user32.dll")]
    private static extern IntPtr DispatchMessage(ref MSG lpMsg);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool PostThreadMessage(uint idThread, uint Msg, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern UIntPtr SetTimer(IntPtr hWnd, UIntPtr nIDEvent, uint uElapse, IntPtr lpTimerFunc);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool KillTimer(IntPtr hWnd, UIntPtr uIDEvent);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);
}
