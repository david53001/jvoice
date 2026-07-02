using System.Runtime.InteropServices;
using JVoice.App.Platform;
using JVoice.Core.Models;

// Probe for the REAL GlobalHotkey (compiled from source). Two modes:
//
//   (default)  match test — inject Ctrl+Shift+Space with both generic (0x11/0x10) and
//              left-specific (0xA2/0xA0, what a PHYSICAL keyboard emits) modifier vk
//              codes; confirms the hook installs, matches, debounces, and fires.
//
//   recovery   eviction/recovery test — force Windows to silently evict the hook via the
//              JVOICE_HOTKEY_TEST_STALL_MS seam, then keep injecting chords and watch
//              whether they fire again. With the watchdog (default) the hook self-heals;
//              with JVOICE_HOTKEY_NO_WATCHDOG=1 it stays dead (reproduces the bug).

const int VK_LCONTROL = 0xA2;
const int VK_LSHIFT = 0xA0;
const int VK_CONTROL = 0x11;
const int VK_SHIFT = 0x10;
const int VK_SPACE = 0x20;

string mode = args.Length > 0 ? args[0] : "match";

int triggered = 0;
var hk = new GlobalHotkey();
hk.Triggered += () => { Interlocked.Increment(ref triggered); Console.WriteLine($"  >>> Triggered (#{Volatile.Read(ref triggered)})"); };
hk.Register(HotkeyChord.Default);
Console.WriteLine($"Registered {HotkeyChord.Default.Format()}; mode={mode}; stallMs={Environment.GetEnvironmentVariable("JVOICE_HOTKEY_TEST_STALL_MS")}; noWatchdog={Environment.GetEnvironmentVariable("JVOICE_HOTKEY_NO_WATCHDOG")}");
// Clear any modifier left "down" in the system async key-state by prior injections,
// so strict chord matching isn't tripped by a stuck Alt/Ctrl/Shift/Win (test hygiene).
foreach (int m in new[] { 0x12, 0x11, 0x10, 0x5B, 0x5C, 0xA0, 0xA2, 0xA1, 0xA3, 0xA4, 0xA5 }) Send(m, true);
Thread.Sleep(700); // let the hook install + start pumping

int rc = mode switch { "recovery" => RunRecovery(), "watchdog" => RunWatchdog(), _ => RunMatch() };
hk.Dispose();
return rc;

int RunWatchdog()
{
    // Validate the self-heal: a chord fires, then we go keyboard-silent but keep the
    // SYSTEM input clock advancing (mouse jiggle) past HookStaleThresholdMs so the
    // watchdog believes the hook went stale and re-arms it. Then a fresh chord must
    // still fire (proving the hook swap didn't break delivery).
    Console.WriteLine("\n[watchdog] chord before...");
    int a = Chord("before", VK_CONTROL, VK_SHIFT);
    Console.WriteLine($"[watchdog] before fired={a}; now ~6s of MOUSE-only activity (no keyboard) to trip staleness...");
    for (int i = 0; i < 30; i++) { Native.mouse_event(0x0001, (i % 2 == 0) ? 3 : -3, 0, 0, UIntPtr.Zero); Thread.Sleep(200); }
    Console.WriteLine("[watchdog] chord after (hook should have re-armed)...");
    int b = Chord("after", VK_CONTROL, VK_SHIFT);
    Console.WriteLine($"\n==== WATCHDOG RESULT ==== before={a} after={b}");
    if (a > 0 && b > 0) { Console.WriteLine("VERDICT: hook still fires after a re-arm cycle."); return 0; }
    Console.WriteLine("VERDICT: FAIL — hook stopped firing after re-arm window."); return 3;
}

int RunMatch()
{
    int s1 = Chord("generic-mods", VK_CONTROL, VK_SHIFT);
    Thread.Sleep(300);
    int s2 = Chord("left-specific (physical-like)", VK_LCONTROL, VK_LSHIFT);
    Console.WriteLine($"\ngeneric={s1} physical-like={s2}");
    if (s1 > 0 && s2 > 0) { Console.WriteLine("VERDICT: hook matches + fires for both forms."); return 0; }
    Console.WriteLine("VERDICT: FAIL — a form did not fire."); return 1;
}

int RunRecovery()
{
    // 1) First chord: its callback hits the one-shot stall -> Windows evicts the hook.
    Console.WriteLine("\n[A] first chord (callback will stall and get evicted)...");
    Chord("A", VK_CONTROL, VK_SHIFT);
    Thread.Sleep(900); // wait out the stall
    int afterA = Volatile.Read(ref triggered);
    Console.WriteLine($"[A] triggers so far: {afterA}  (hook now evicted by Windows)");

    // 2) Keep injecting chords. Each advances system input; a healthy hook would fire.
    //    Without recovery, none fire. With the watchdog, the hook re-arms and they resume.
    int baseline = afterA;
    int recoveredAtMs = -1;
    for (int i = 0; i < 16; i++) // ~8s of probing
    {
        Chord($"probe{i}", VK_CONTROL, VK_SHIFT);
        Thread.Sleep(500);
        int now = Volatile.Read(ref triggered);
        if (recoveredAtMs < 0 && now > baseline) { recoveredAtMs = (i + 1) * 500; }
    }
    int total = Volatile.Read(ref triggered);
    Console.WriteLine($"\n==== RECOVERY RESULT ====  firstChord={afterA>0} postEvictionExtraFires={total - baseline} recoveredAfter≈{recoveredAtMs}ms");
    if (total > baseline) { Console.WriteLine("VERDICT: hook RECOVERED after eviction (watchdog works)."); return 0; }
    Console.WriteLine("VERDICT: hook stayed DEAD after eviction (no recovery)."); return 2;
}

int Chord(string name, int ctrlVk, int shiftVk)
{
    int before = Volatile.Read(ref triggered);
    Send(ctrlVk, false); Send(shiftVk, false); Send(VK_SPACE, false);
    Thread.Sleep(40);
    Send(VK_SPACE, true); Send(shiftVk, true); Send(ctrlVk, true);
    Thread.Sleep(250);
    return Volatile.Read(ref triggered) - before;
}

static void Send(int vk, bool keyUp)
{
    var inputs = new INPUT[1];
    inputs[0].type = 1; // INPUT_KEYBOARD
    inputs[0].u.ki.wVk = (ushort)vk;
    inputs[0].u.ki.dwFlags = keyUp ? (uint)0x0002 : 0; // KEYEVENTF_KEYUP
    uint sent = Native.SendInput(1, inputs, Marshal.SizeOf<INPUT>());
    if (sent != 1) Console.WriteLine($"  !! SendInput failed (sent={sent}, err={Marshal.GetLastWin32Error()})");
}

[StructLayout(LayoutKind.Sequential)]
struct INPUT { public uint type; public InputUnion u; }

[StructLayout(LayoutKind.Explicit)]
struct InputUnion
{
    [FieldOffset(0)] public MOUSEINPUT mi;
    [FieldOffset(0)] public KEYBDINPUT ki;
    [FieldOffset(0)] public HARDWAREINPUT hi;
}

[StructLayout(LayoutKind.Sequential)]
struct KEYBDINPUT { public ushort wVk; public ushort wScan; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }

[StructLayout(LayoutKind.Sequential)]
struct MOUSEINPUT { public int dx; public int dy; public uint mouseData; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }

[StructLayout(LayoutKind.Sequential)]
struct HARDWAREINPUT { public uint uMsg; public ushort wParamL; public ushort wParamH; }

static partial class Native
{
    [DllImport("user32.dll", SetLastError = true)]
    public static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

    [DllImport("user32.dll")]
    public static extern void mouse_event(uint dwFlags, int dx, int dy, uint dwData, UIntPtr dwExtraInfo);
}
