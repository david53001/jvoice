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

    // Modifier virtual-key codes we read live via GetAsyncKeyState.
    private const int VK_CONTROL = 0x11;
    private const int VK_MENU = 0x12;   // Alt
    private const int VK_SHIFT = 0x10;
    private const int VK_LWIN = 0x5B;
    private const int VK_RWIN = 0x5C;

    private readonly object _gate = new();
    private Thread? _thread;
    private uint _threadId;
    private IntPtr _hook = IntPtr.Zero;
    private LowLevelKeyboardProc? _proc; // keep alive
    private HotkeyChord _chord = HotkeyChord.Default;
    private long _lastFiredTicks;
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

        // Standard message pump — required for WH_KEYBOARD_LL callbacks to fire.
        while (_running && GetMessage(out MSG msg, IntPtr.Zero, 0, 0) > 0)
        {
            TranslateMessage(ref msg);
            DispatchMessage(ref msg);
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
            int msg = (int)wParam;
            if (msg == WM_KEYDOWN || msg == WM_SYSKEYDOWN)
            {
                var data = Marshal.PtrToStructure<KBDLLHOOKSTRUCT>(lParam);
                if (MatchesChord((int)data.vkCode))
                {
                    if (TryDebounce())
                        Triggered?.Invoke(); // raised on the hook thread; Phase 4 marshals
                    // Do NOT swallow the key: keep behavior transparent. If a future
                    // build wants to suppress it, return (IntPtr)1.
                }
            }
        }
        return CallNextHookEx(_hook, nCode, wParam, lParam);
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

        return ctrl == wantCtrl && alt == wantAlt && shift == wantShift && win == wantWin;
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
}
