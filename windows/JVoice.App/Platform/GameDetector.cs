using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Threading;
using JVoice.Core;
using JVoice.Core.Models;
using Microsoft.Win32;

namespace JVoice.App.Platform;

/// Gathers Win32 signals about the foreground window and caches a suppression
/// decision in <see cref="ShouldSuppress"/> (a volatile bool, O(1) for the hotkey
/// hook thread). Recomputes on every foreground change + a ~1.5 s DispatcherTimer
/// backstop (for games that go fullscreen via alt-enter without a foreground change).
///
/// SAFETY: the only process handle opened is PROCESS_QUERY_LIMITED_INFORMATION (0x1000)
/// to read the image path via QueryFullProcessImageName. No memory reads, no module
/// enumeration, no injection. If the open or query fails (hardened/anti-cheat process),
/// all path-based signals evaluate to false and the code moves on — never retried with
/// broader access. The process-untouching signals (QUNS, window-rect fullscreen) still
/// evaluate normally even when the process handle is denied.
public sealed class GameDetector : IDisposable
{
    // ---- Known game install roots (path substring, case-insensitive) ----
    // Standard install locations for the major PC game storefronts.
    // javaw.exe is intentionally NOT in KnownGameExeNames (too ambiguous — many Java
    // apps use it); Minecraft is caught by signal #2 (GameConfigStore) or Aggressive.
    private static readonly string[] KnownGameRoots =
    [
        @"\steamapps\common\",
        @"\Epic Games\",
        @"\Riot Games\",
        @"\GOG Galaxy\Games\",
        @"\Origin Games\",
        @"\EA Games\",
        @"\Ubisoft\",
        @"\Battle.net\",
        @"\Rockstar Games\",
    ];

    // Curated exe names for titles whose paths can vary or aren't under a standard root.
    private static readonly HashSet<string> KnownGameExeNames =
        new(StringComparer.OrdinalIgnoreCase)
        {
            "VALORANT-Win64-Shipping.exe",
            "FortniteClient-Win64-Shipping.exe",
            "GTA5.exe",
            "RDR2.exe",
            "csgo.exe",
            "cs2.exe",
            "RustClient.exe",
            "RobloxPlayerBeta.exe",
            "League of Legends.exe",
            "Overwatch.exe",
            "bf2042.exe",
            "ModernWarfare.exe",
            "cod.exe",
        };

    // Shell class names that represent the desktop / wallpaper worker — never a game.
    private static readonly HashSet<string> ShellClassNames =
        new(StringComparer.OrdinalIgnoreCase) { "Progman", "WorkerW" };

    private const uint PROCESS_QUERY_LIMITED_INFORMATION = 0x1000;
    private const uint MONITOR_DEFAULTTONEAREST = 2;

    // QUNS (Query User Notification State) values — Shell32 / WinUser.h
    private const int QUNS_NOT_PRESENT             = 1;
    private const int QUNS_BUSY                    = 2;
    private const int QUNS_RUNNING_D3D_FULL_SCREEN = 3;
    private const int QUNS_PRESENTATION_MODE       = 4;
    private const int QUNS_ACCEPTS_NOTIFICATIONS   = 5;
    private const int QUNS_QUIET_TIME              = 6;
    private const int QUNS_APP                     = 7;

    // GameConfigStore cache: TTL ~30 s (the list changes rarely — only when the user
    // installs or removes a game that Windows recognises).
    private HashSet<string>? _gameConfigPaths;   // null = not yet loaded
    private DateTime _gameConfigLoadedAt;
    private static readonly TimeSpan GameConfigCacheTtl = TimeSpan.FromSeconds(30);

    private readonly ForegroundWindowTracker _tracker;
    private DispatcherTimer? _timer;

    /// Cached suppression decision. Written on the WPF UI thread (event/timer); read
    /// on the hotkey hook thread. volatile gives the required visibility guarantee
    /// without locking (see plan §6 item 4 cross-thread note).
    private volatile bool _suppress;

    public GameDetector(ForegroundWindowTracker tracker)
    {
        _tracker = tracker ?? throw new ArgumentNullException(nameof(tracker));
    }

    private GameDetectionMode _mode = GameDetectionMode.Balanced;

    /// Current detection mode. Changing it immediately recomputes the cached decision.
    public GameDetectionMode Mode
    {
        get => _mode;
        set
        {
            _mode = value;
            try { Recompute(); } catch { /* never throw from a property setter */ }
        }
    }

    /// O(1) volatile read — safe on the hotkey hook thread.
    public bool ShouldSuppress => _suppress;

    /// Seed the initial decision from the current foreground, subscribe to foreground
    /// changes, and start the backstop DispatcherTimer. Call on the WPF UI thread.
    public void Start()
    {
        try { Recompute(); } catch { /* _suppress stays false on first-seed failure */ }

        _tracker.ForegroundChanged += OnForegroundChanged;

        // Backstop: a game going fullscreen via alt-enter often does so without raising
        // a foreground-change event (the same hwnd; only its extent changes). Poll every
        // ~1.5 s so signal #4 (ForegroundIsFullscreen) catches that case.
        _timer = new DispatcherTimer(DispatcherPriority.Background)
        {
            Interval = TimeSpan.FromSeconds(1.5),
        };
        _timer.Tick += (_, _) => { try { Recompute(); } catch { } };
        _timer.Start();
    }

    /// Unsubscribe and stop the timer. Safe to call multiple times.
    public void Stop()
    {
        _tracker.ForegroundChanged -= OnForegroundChanged;
        _timer?.Stop();
        _timer = null;
    }

    public void Dispose() => Stop();

    /// Gather signals for the current foreground RIGHT NOW (bypasses all caches except
    /// GameConfigStore, which is refreshed if stale). Never throws. Used by --game-probe.
    public GameProbeResult Inspect()
    {
        try
        {
            IntPtr hwnd = ForegroundWindowTracker.GetForegroundWindowNow();
            var (signals, exePath, qunsState) = GatherSignals(hwnd);
            bool suppress = GameDetectionPolicy.ShouldSuppress(signals, _mode);
            return new GameProbeResult(hwnd, exePath, qunsState, signals, _mode, suppress);
        }
        catch (Exception ex)
        {
            return new GameProbeResult(
                IntPtr.Zero, "<error>", $"<error: {ex.Message}>",
                new GameSignals(false, false, false, false, false, false),
                _mode, false);
        }
    }

    // ---- Internal ----

    private void OnForegroundChanged(IntPtr hwnd)
    {
        try { Recompute(); } catch { }
    }

    /// Rebuild the signals from the live foreground and update _suppress.
    /// On any transient Win32 failure, leaves _suppress unchanged (fail-safe: don't
    /// flip the cached decision on a glitch in either direction).
    private void Recompute()
    {
        // When detection is Off, never inspect the foreground at all — no OpenProcess, no
        // registry read. The policy returns false regardless, so skip the work entirely and
        // don't even open a limited-info handle to the focused game while the feature is disabled.
        // (Force-flags are hard-false in v1; revisit when the v2 per-exe lists need the path in Off.)
        if (_mode == GameDetectionMode.Off) { _suppress = false; return; }
        try
        {
            IntPtr hwnd = ForegroundWindowTracker.GetForegroundWindowNow();
            var (signals, _, _) = GatherSignals(hwnd);
            _suppress = GameDetectionPolicy.ShouldSuppress(signals, _mode);
        }
        catch
        {
            // leave _suppress as-is
        }
    }

    /// Gather all game signals for the given foreground hwnd.
    /// Returns (signals, resolvedExePath, qunsStateName).
    private (GameSignals signals, string exePath, string qunsState) GatherSignals(IntPtr hwnd)
    {
        // If hwnd is Zero or belongs to our own process (HUD / Settings / tray),
        // there is nothing gaming-related to suppress.
        if (hwnd == IntPtr.Zero || ForegroundWindowTracker.IsOwnedByCurrentProcess(hwnd))
            return (new GameSignals(false, false, false, false, false, false), "<self>", "<n/a>");

        // ----------------------------------------------------------------
        // Signal #1 — D3D exclusive fullscreen (process-untouching, global OS state).
        // SHQueryUserNotificationState is the same API Windows Focus Assist uses;
        // QUNS_RUNNING_D3D_FULL_SCREEN (3) is Microsoft's own "a game is in exclusive
        // fullscreen" signal. Does NOT open any process.
        // ----------------------------------------------------------------
        int qunsValue = 0;
        bool d3dFullscreen = false;
        string qunsStateName = "<unknown>";
        try
        {
            int hr = SHQueryUserNotificationState(out qunsValue);
            if (hr == 0) // S_OK
            {
                d3dFullscreen = qunsValue == QUNS_RUNNING_D3D_FULL_SCREEN;
                qunsStateName = qunsValue switch
                {
                    QUNS_NOT_PRESENT             => "NOT_PRESENT",
                    QUNS_BUSY                    => "BUSY",
                    QUNS_RUNNING_D3D_FULL_SCREEN => "RUNNING_D3D_FULL_SCREEN",
                    QUNS_PRESENTATION_MODE       => "PRESENTATION_MODE",
                    QUNS_ACCEPTS_NOTIFICATIONS   => "ACCEPTS_NOTIFICATIONS",
                    QUNS_QUIET_TIME              => "QUIET_TIME",
                    QUNS_APP                     => "APP",
                    _                            => $"<{qunsValue}>",
                };
            }
            else
            {
                qunsStateName = $"<hresult:0x{hr:X8}>";
            }
        }
        catch { /* treat as unknown */ }

        // ----------------------------------------------------------------
        // Signal #2a — Foreground exe path (needed by signals #2, #3, #4).
        // ONLY open with PROCESS_QUERY_LIMITED_INFORMATION (0x1000).
        // If denied (hardened/anti-cheat process), exePath stays null →
        // path-based signals (#2/#3) are false, but signals #1/#5 still evaluate.
        // NEVER retry with broader access; NEVER enumerate modules.
        // ----------------------------------------------------------------
        string? exePath = null;
        try
        {
            _ = GetWindowThreadProcessId(hwnd, out uint pid);
            if (pid != 0)
            {
                IntPtr hProc = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid);
                if (hProc != IntPtr.Zero)
                {
                    try
                    {
                        var sb = new StringBuilder(1024);
                        uint cap = (uint)sb.Capacity;
                        if (QueryFullProcessImageName(hProc, 0, sb, ref cap))
                            exePath = sb.ToString(0, (int)cap);
                    }
                    finally
                    {
                        CloseHandle(hProc);
                    }
                }
                // If OpenProcess returns Zero, exePath stays null — path-based signals
                // will be false. This is the correct anti-cheat-safe fallback.
            }
        }
        catch { /* exePath stays null */ }

        // ----------------------------------------------------------------
        // Signal #2 — KnownGamePath: foreground exe is under a known game root
        // or matches a curated name list.
        // ----------------------------------------------------------------
        bool knownGamePath = false;
        if (exePath != null)
        {
            foreach (var root in KnownGameRoots)
            {
                if (exePath.Contains(root, StringComparison.OrdinalIgnoreCase))
                {
                    knownGamePath = true;
                    break;
                }
            }
            if (!knownGamePath)
            {
                string fileName = System.IO.Path.GetFileName(exePath);
                knownGamePath = KnownGameExeNames.Contains(fileName);
            }
        }

        // ----------------------------------------------------------------
        // Signal #3 — RegisteredGame: foreground exe is in the Windows GameConfigStore.
        // HKCU\System\GameConfigStore\Children\*  value MatchedExeFullPath.
        // Reading the registry never touches the game process.
        // The set is cached for ~30 s (it changes only when the user installs/removes a
        // recognized game).
        // ----------------------------------------------------------------
        bool registeredGame = false;
        if (exePath != null)
            registeredGame = GetOrRefreshGameConfigPaths().Contains(exePath);

        // ----------------------------------------------------------------
        // Signal #4 — ForegroundIsFullscreen: window rect covers the monitor rect
        // (within a 2 px tolerance on each edge). Excludes the shell (Progman/WorkerW)
        // and our own process (already excluded at entry). Process-untouching — works
        // even when the exe path is unknown.
        // ----------------------------------------------------------------
        bool foregroundFullscreen = false;
        try
        {
            // Exclude shell/desktop windows by class name.
            var clsBuf = new StringBuilder(256);
            _ = GetClassName(hwnd, clsBuf, clsBuf.Capacity);
            string cls = clsBuf.ToString();

            if (!ShellClassNames.Contains(cls))
            {
                if (GetWindowRect(hwnd, out RECT wr))
                {
                    IntPtr hMonitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
                    if (hMonitor != IntPtr.Zero)
                    {
                        var mi = new MONITORINFO { cbSize = (uint)Marshal.SizeOf<MONITORINFO>() };
                        if (GetMonitorInfo(hMonitor, ref mi))
                        {
                            RECT mr = mi.rcMonitor;
                            const int tol = 2; // px tolerance on each edge
                            foregroundFullscreen =
                                wr.Left   <= mr.Left   + tol &&
                                wr.Top    <= mr.Top    + tol &&
                                wr.Right  >= mr.Right  - tol &&
                                wr.Bottom >= mr.Bottom - tol;
                        }
                    }
                }
            }
        }
        catch { /* treat as not fullscreen */ }

        // ----------------------------------------------------------------
        // Signals #5/#6 — UserForceGame / UserForceNotGame.
        // v2: per-exe allow/deny lists — hard-wired false until that feature lands.
        // ----------------------------------------------------------------
        bool userForceGame    = false; // v2: per-exe allow/deny lists
        bool userForceNotGame = false; // v2: per-exe allow/deny lists

        var signals = new GameSignals(
            D3DFullscreen:          d3dFullscreen,
            RegisteredGame:         registeredGame,
            KnownGamePath:          knownGamePath,
            ForegroundIsFullscreen: foregroundFullscreen,
            UserForceGame:          userForceGame,
            UserForceNotGame:       userForceNotGame);

        return (signals, exePath ?? "<unknown>", qunsStateName);
    }

    /// Returns the cached GameConfigStore path set, refreshing it if older than ~30 s.
    /// The set is case-insensitive (Windows paths are case-insensitive). Returns an
    /// empty set when the key is absent or on any registry access failure.
    private HashSet<string> GetOrRefreshGameConfigPaths()
    {
        if (_gameConfigPaths != null &&
            DateTime.UtcNow - _gameConfigLoadedAt < GameConfigCacheTtl)
            return _gameConfigPaths;

        _gameConfigPaths = LoadGameConfigPaths();
        _gameConfigLoadedAt = DateTime.UtcNow;
        return _gameConfigPaths;
    }

    private static HashSet<string> LoadGameConfigPaths()
    {
        var result = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        try
        {
            using var root = Registry.CurrentUser.OpenSubKey(@"System\GameConfigStore\Children");
            if (root is null) return result;

            foreach (string childName in root.GetSubKeyNames())
            {
                try
                {
                    using var child = root.OpenSubKey(childName);
                    if (child?.GetValue("MatchedExeFullPath") is string path && path.Length > 0)
                        result.Add(path);
                }
                catch { /* skip this child entry */ }
            }
        }
        catch { /* key absent or access denied — return the (possibly partial) result */ }
        return result;
    }

    // ---- P/Invoke ----

    [DllImport("shell32.dll")]
    private static extern int SHQueryUserNotificationState(out int pquns);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr OpenProcess(uint dwDesiredAccess, bool bInheritHandle, uint dwProcessId);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool CloseHandle(IntPtr hObject);

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern bool QueryFullProcessImageName(
        IntPtr hProcess, uint dwFlags, StringBuilder lpExeName, ref uint lpdwSize);

    [DllImport("user32.dll")]
    private static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

    [DllImport("user32.dll")]
    private static extern IntPtr MonitorFromWindow(IntPtr hwnd, uint dwFlags);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern bool GetMonitorInfo(IntPtr hMonitor, ref MONITORINFO lpmi);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);

    [StructLayout(LayoutKind.Sequential)]
    private struct RECT
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MONITORINFO
    {
        public uint cbSize;
        public RECT rcMonitor;
        public RECT rcWork;
        public uint dwFlags;
    }
}

/// Diagnostic snapshot for the current foreground window, produced by
/// <see cref="GameDetector.Inspect"/>. Used by the --game-probe dev CLI.
public readonly record struct GameProbeResult(
    IntPtr Hwnd,
    string ExePath,
    string QunsState,
    GameSignals Signals,
    GameDetectionMode Mode,
    bool ShouldSuppress)
{
    public override string ToString() =>
        $"""
         Hwnd             : 0x{Hwnd:X}
         ExePath          : {ExePath}
         QUNS state       : {QunsState}
         D3DFullscreen    : {Signals.D3DFullscreen}
         RegisteredGame   : {Signals.RegisteredGame}
         KnownGamePath    : {Signals.KnownGamePath}
         ForegroundFS     : {Signals.ForegroundIsFullscreen}
         UserForceGame    : {Signals.UserForceGame}
         UserForceNotGame : {Signals.UserForceNotGame}
         Mode             : {Mode}
         ShouldSuppress   : {ShouldSuppress}
         """;
}
