using System.Runtime.InteropServices;
using System.Security.Principal;
using Microsoft.Win32.SafeHandles;

namespace JVoice.App.Platform;

/// <summary>
/// "Launching JVoice.exe while it runs opens the real Settings" (WINDOWS-HANDOFF §9.5). The running copy
/// listens on a per-session named event; a second launch that loses the single-instance race sets it
/// and exits, and the running copy opens its Settings window (never an empty one — it is the same
/// <c>SettingsWindow</c> the tray opens). Before this, a second launch exited silently.
///
/// The event's security descriptor gives the current user (and SYSTEM) access and a MEDIUM mandatory
/// label, so a normal double-click can still signal an ELEVATED running copy (an elevated process's
/// objects are otherwise high-integrity and a medium-integrity opener is refused — the same UIPI split
/// as the mutex, §7 #25). No other user can open it (the Local\ namespace is per session anyway).
/// </summary>
public static class ShowSettingsSignal
{
    private const string EventName = @"Local\JVoice.ShowSettings.{3B7E2D41-9C58-4F0A-A6D2-51E8C7B90F13}";
    private static EventWaitHandle? _handle;
    private static RegisteredWaitHandle? _wait;

    /// <summary>The running copy: call <paramref name="onSignal"/> (on a pool thread) each time a second
    /// launch asks for Settings. Best effort — if the event can't be created, a second launch just exits.</summary>
    public static void Listen(Action onSignal)
    {
        if (_wait is not null) return;
        IntPtr h = CreateWithLabel();
        if (h == IntPtr.Zero) h = CreateEventW(IntPtr.Zero, false, false, EventName);
        if (h == IntPtr.Zero) return;
        _handle = new EventWaitHandle(false, EventResetMode.AutoReset) { SafeWaitHandle = new SafeWaitHandle(h, ownsHandle: true) };
        _wait = ThreadPool.RegisterWaitForSingleObject(_handle, (_, _) => onSignal(), null, Timeout.Infinite, executeOnlyOnce: false);
    }

    /// <summary>A second launch: ask the running copy for its Settings. False when there is no listener.</summary>
    public static bool Signal()
    {
        IntPtr h = OpenEventW(EventModifyState, false, EventName);
        if (h == IntPtr.Zero) return false;
        try { return SetEvent(h); }
        finally { CloseHandle(h); }
    }

    private static IntPtr CreateWithLabel()
    {
        string? sid = WindowsIdentity.GetCurrent().User?.Value;
        if (sid is null) return IntPtr.Zero;
        // Full access for this user and SYSTEM; mandatory label Medium, no-write-up.
        string sddl = $"D:(A;;GA;;;{sid})(A;;GA;;;SY)S:(ML;;NW;;;ME)";
        if (!ConvertStringSecurityDescriptorToSecurityDescriptorW(sddl, 1, out IntPtr sd, IntPtr.Zero)) return IntPtr.Zero;
        try
        {
            var sa = new SECURITY_ATTRIBUTES { nLength = Marshal.SizeOf<SECURITY_ATTRIBUTES>(), lpSecurityDescriptor = sd, bInheritHandle = 0 };
            IntPtr pSa = Marshal.AllocHGlobal(sa.nLength);
            try
            {
                Marshal.StructureToPtr(sa, pSa, false);
                return CreateEventW(pSa, false, false, EventName);
            }
            finally { Marshal.FreeHGlobal(pSa); }
        }
        finally { LocalFree(sd); }
    }

    private const uint EventModifyState = 0x0002;

    [StructLayout(LayoutKind.Sequential)]
    private struct SECURITY_ATTRIBUTES { public int nLength; public IntPtr lpSecurityDescriptor; public int bInheritHandle; }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr CreateEventW(IntPtr lpEventAttributes, bool bManualReset, bool bInitialState, string lpName);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr OpenEventW(uint dwDesiredAccess, bool bInheritHandle, string lpName);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool SetEvent(IntPtr hEvent);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool CloseHandle(IntPtr hObject);
    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool ConvertStringSecurityDescriptorToSecurityDescriptorW(string sddl, uint revision, out IntPtr sd, IntPtr size);
    [DllImport("kernel32.dll")]
    private static extern IntPtr LocalFree(IntPtr hMem);
}
