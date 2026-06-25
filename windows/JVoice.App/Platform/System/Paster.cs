using System.Runtime.InteropServices;
using System.Windows; // System.Windows.Clipboard / IDataObject (WPF)
using JVoice.Core;

namespace JVoice.App.Platform;

public enum PasteOutcome
{
    Ok,
    AccessDenied,   // UIPI: target is an elevated window we can't send input to
    ClipboardLocked,// another app holds the clipboard
    TargetRejected, // no usable text, or focusing/SendInput to the target failed
}

/// Pastes text into another window by saving the clipboard, setting our text,
/// focusing the target HWND, synthesizing Ctrl+V via SendInput, then restoring the
/// prior clipboard after a delay (cancelling any prior restore). Faithful port of
/// PasteManager.swift, re-expressed for Win32. No accessibility permission needed
/// (overview §6.4); the only AccessDenied source is the UIPI elevated-target rule.
public sealed class Paster : IDisposable
{
    private readonly object _gate = new();
    private CancellationTokenSource? _restoreCts;

    /// Set the clipboard to `text` only (no paste). Returns true on success.
    public bool Stage(string text) => TrySetClipboardText(text);

    public PasteOutcome Paste(string text, IntPtr targetHwnd)
    {
        if (string.IsNullOrEmpty(text)) return PasteOutcome.TargetRejected;

        // UIPI: a non-elevated process cannot SendInput to an elevated window.
        if (targetHwnd != IntPtr.Zero && IsElevatedWindow(targetHwnd))
            return PasteOutcome.AccessDenied;

        // 1. Snapshot the current clipboard so we can restore it.
        IDataObject? saved = CaptureClipboard();

        // 2. Put our text on the clipboard.
        if (!TrySetClipboardText(text))
            return PasteOutcome.ClipboardLocked;

        // 3. Focus the target window so Ctrl+V lands there.
        bool focused = FocusTarget(targetHwnd);
        if (!focused)
        {
            ScheduleRestore(saved, AppTimings.PasteRestoreDelayFailureMs);
            return PasteOutcome.TargetRejected;
        }

        // Brief settle so the target is truly foreground before we type
        // (Swift pasteActivationDelay = 80 ms). Synchronous, short.
        Thread.Sleep((int)AppTimings.PasteActivationDelay.TotalMilliseconds);

        // 4. Synthesize Ctrl+V.
        bool sent = SendCtrlV();

        // 5. Always restore — after the target consumed the text on success, or
        //    promptly on failure so the user's clipboard isn't clobbered.
        ScheduleRestore(saved,
            sent ? (int)AppTimings.PasteRestoreDelay.TotalMilliseconds
                 : AppTimings.PasteRestoreDelayFailureMs);

        return sent ? PasteOutcome.Ok : PasteOutcome.TargetRejected;
    }

    public void Dispose()
    {
        lock (_gate) { _restoreCts?.Cancel(); _restoreCts?.Dispose(); _restoreCts = null; }
    }

    // clipboard (WPF, STA)

    private static IDataObject? CaptureClipboard()
    {
        try
        {
            // Clone all formats so a later SetText doesn't mutate what we hold.
            IDataObject current = Clipboard.GetDataObject();
            var clone = new DataObject();
            foreach (string fmt in current.GetFormats(autoConvert: false))
            {
                try
                {
                    object? data = current.GetData(fmt, autoConvert: false);
                    if (data is not null) clone.SetData(fmt, data);
                }
                catch { /* skip formats that won't round-trip */ }
            }
            return clone;
        }
        catch
        {
            return null; // empty/locked clipboard → nothing to restore
        }
    }

    private static bool TrySetClipboardText(string text)
    {
        // WPF Clipboard.SetText has internal retry, but can still throw when locked.
        for (int attempt = 0; attempt < 3; attempt++)
        {
            try
            {
                Clipboard.SetText(text);
                return true;
            }
            catch (COMException) { Thread.Sleep(20); }
            catch (ExternalException) { Thread.Sleep(20); }
        }
        return false;
    }

    private void ScheduleRestore(IDataObject? snapshot, int delayMs)
    {
        if (snapshot is null) return; // nothing to restore
        CancellationTokenSource cts;
        lock (_gate)
        {
            _restoreCts?.Cancel(); // cancel a prior pending restore (Swift restoreTask?.cancel())
            _restoreCts?.Dispose();
            _restoreCts = cts = new CancellationTokenSource();
        }
        var token = cts.Token;
        _ = Task.Run(async () =>
        {
            try { await Task.Delay(delayMs, token); }
            catch (OperationCanceledException) { return; }
            if (token.IsCancellationRequested) return;
            // Restore must run on an STA thread for the WPF clipboard.
            RunOnSta(() =>
            {
                try { Clipboard.SetDataObject(snapshot, copy: true); } catch { /* best effort */ }
            });
        }, token);
    }

    private static void RunOnSta(Action action)
    {
        if (Thread.CurrentThread.GetApartmentState() == ApartmentState.STA)
        {
            action();
            return;
        }
        var t = new Thread(() => action()) { IsBackground = true };
        t.SetApartmentState(ApartmentState.STA);
        t.Start();
        t.Join(1000);
    }

    // focus + SendInput

    private static bool FocusTarget(IntPtr hwnd)
    {
        if (hwnd == IntPtr.Zero) return false;

        // Common case: the user never left their app, so the paste target is already
        // the foreground window — no focus change is needed and SetForegroundWindow
        // (which is unreliable / can return false here) must NOT be allowed to fail us.
        if (GetForegroundWindow() == hwnd) return true;

        // Otherwise force the target to the foreground. SetForegroundWindow is gated by
        // Windows' foreground-lock rules; the robust, battle-tested workaround is to (a)
        // momentarily zero the foreground-lock timeout, (b) attach our input queue to the
        // CURRENT foreground thread (the documented requirement — NOT the target thread),
        // then (c) raise the target and verify by reading the real foreground afterwards
        // (SetForegroundWindow's return value is not trustworthy).
        uint thisThread = GetCurrentThreadId();
        IntPtr fg = GetForegroundWindow();
        uint fgThread = fg != IntPtr.Zero ? GetWindowThreadProcessId(fg, out _) : 0;
        uint targetThread = GetWindowThreadProcessId(hwnd, out _);

        IntPtr prevTimeout = IntPtr.Zero;
        bool gotPrev = SystemParametersInfo(SPI_GETFOREGROUNDLOCKTIMEOUT, 0, ref prevTimeout, 0);
        SystemParametersInfo(SPI_SETFOREGROUNDLOCKTIMEOUT, 0, IntPtr.Zero, SPIF_FLAGS);

        bool attachedFg = fgThread != 0 && fgThread != thisThread && AttachThreadInput(thisThread, fgThread, true);
        bool attachedTgt = targetThread != thisThread && targetThread != fgThread && AttachThreadInput(thisThread, targetThread, true);
        try
        {
            ShowWindowAsync(hwnd, SW_SHOW);
            BringWindowToTop(hwnd);
            SetForegroundWindow(hwnd);
            SetFocus(hwnd);
            // Trust the observed foreground, not the API return code.
            return GetForegroundWindow() == hwnd;
        }
        finally
        {
            if (attachedTgt) AttachThreadInput(thisThread, targetThread, false);
            if (attachedFg) AttachThreadInput(thisThread, fgThread, false);
            if (gotPrev) SystemParametersInfo(SPI_SETFOREGROUNDLOCKTIMEOUT, 0, prevTimeout, SPIF_FLAGS);
        }
    }

    private static bool SendCtrlV()
    {
        // KEYEVENTF_KEYUP = 0x0002; VK_CONTROL = 0x11; V = 0x56.
        var inputs = new INPUT[4];
        inputs[0] = KeyInput(VK_CONTROL, keyUp: false);
        inputs[1] = KeyInput(0x56, keyUp: false); // V down
        inputs[2] = KeyInput(0x56, keyUp: true);  // V up
        inputs[3] = KeyInput(VK_CONTROL, keyUp: true);
        uint sent = SendInput((uint)inputs.Length, inputs, Marshal.SizeOf<INPUT>());
        return sent == inputs.Length;
    }

    private static INPUT KeyInput(ushort vk, bool keyUp) => new()
    {
        type = INPUT_KEYBOARD,
        u = new InputUnion
        {
            ki = new KEYBDINPUT
            {
                wVk = vk,
                wScan = 0,
                dwFlags = keyUp ? KEYEVENTF_KEYUP : 0,
                time = 0,
                dwExtraInfo = IntPtr.Zero,
            }
        }
    };

    /// Best-effort detection of an elevated (higher-integrity) target window we
    /// cannot SendInput into from a non-elevated process (UIPI). Returns false if
    /// we can't tell (we then attempt the paste and report TargetRejected if it
    /// silently fails).
    private static bool IsElevatedWindow(IntPtr hwnd)
    {
        try
        {
            _ = GetWindowThreadProcessId(hwnd, out uint pid);
            if (pid == 0) return false;
            IntPtr hProc = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid);
            if (hProc == IntPtr.Zero) return false; // can't open => likely higher integrity
            try
            {
                if (!OpenProcessToken(hProc, TOKEN_QUERY, out IntPtr hToken)) return false;
                try
                {
                    int size = Marshal.SizeOf<int>();
                    IntPtr buf = Marshal.AllocHGlobal(size);
                    try
                    {
                        if (GetTokenInformation(hToken, TOKEN_ELEVATION, buf, size, out _))
                        {
                            int elevated = Marshal.ReadInt32(buf);
                            return elevated != 0 && !IsCurrentProcessElevated();
                        }
                        return false;
                    }
                    finally { Marshal.FreeHGlobal(buf); }
                }
                finally { CloseHandle(hToken); }
            }
            finally { CloseHandle(hProc); }
        }
        catch { return false; }
    }

    private static bool IsCurrentProcessElevated()
    {
        try
        {
            using var id = System.Security.Principal.WindowsIdentity.GetCurrent();
            var principal = new System.Security.Principal.WindowsPrincipal(id);
            return principal.IsInRole(System.Security.Principal.WindowsBuiltInRole.Administrator);
        }
        catch { return false; }
    }

    // P/Invoke constants + structs

    private const int INPUT_KEYBOARD = 1;
    private const uint KEYEVENTF_KEYUP = 0x0002;
    private const ushort VK_CONTROL = 0x11;
    private const int SW_SHOW = 5;
    private const uint PROCESS_QUERY_LIMITED_INFORMATION = 0x1000;
    private const uint TOKEN_QUERY = 0x0008;
    private const int TOKEN_ELEVATION = 20;
    private const uint SPI_GETFOREGROUNDLOCKTIMEOUT = 0x2000;
    private const uint SPI_SETFOREGROUNDLOCKTIMEOUT = 0x2001;
    private const uint SPIF_FLAGS = 0x0003; // SPIF_UPDATEINIFILE | SPIF_SENDCHANGE

    [StructLayout(LayoutKind.Sequential)]
    private struct INPUT { public int type; public InputUnion u; }

    // The union MUST carry its largest member (MOUSEINPUT) so sizeof(INPUT) is the
    // value SendInput's cbSize check expects (40 bytes on x64). Declaring only
    // KEYBDINPUT made it 32 bytes → SendInput rejected every call with
    // ERROR_INVALID_PARAMETER (87) and pasted nothing.
    [StructLayout(LayoutKind.Explicit)]
    private struct InputUnion
    {
        [FieldOffset(0)] public MOUSEINPUT mi;
        [FieldOffset(0)] public KEYBDINPUT ki;
        [FieldOffset(0)] public HARDWAREINPUT hi;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MOUSEINPUT
    {
        public int dx;
        public int dy;
        public uint mouseData;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct HARDWAREINPUT
    {
        public uint uMsg;
        public ushort wParamL;
        public ushort wParamH;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct KEYBDINPUT
    {
        public ushort wVk;
        public ushort wScan;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool BringWindowToTop(IntPtr hWnd);

    [DllImport("user32.dll")]
    private static extern IntPtr SetFocus(IntPtr hWnd);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SystemParametersInfo(uint uiAction, uint uiParam, ref IntPtr pvParam, uint fWinIni);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SystemParametersInfo(uint uiAction, uint uiParam, IntPtr pvParam, uint fWinIni);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

    [DllImport("kernel32.dll")]
    private static extern uint GetCurrentThreadId();

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr OpenProcess(uint dwDesiredAccess, bool bInheritHandle, uint dwProcessId);

    [DllImport("advapi32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool OpenProcessToken(IntPtr ProcessHandle, uint DesiredAccess, out IntPtr TokenHandle);

    [DllImport("advapi32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetTokenInformation(IntPtr TokenHandle, int TokenInformationClass, IntPtr TokenInformation, int TokenInformationLength, out int ReturnLength);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CloseHandle(IntPtr hObject);
}
