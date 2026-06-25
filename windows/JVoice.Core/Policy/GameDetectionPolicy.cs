using JVoice.Core.Models;

namespace JVoice.Core;

/// Pure, side-effect-free decision for whether to suppress the JVoice hotkey because a
/// game owns the foreground. All Win32 signal-gathering lives in the App layer
/// (GameDetector); this is the unit-testable brain, mirroring HotkeyGate/CoordinatorDecisions.
/// SAFETY: the signals are all read-only OS queries — nothing here implies any interaction
/// with a game process (no memory reads, no injection). See the plan's anti-cheat section.
public readonly record struct GameSignals(
    bool D3DFullscreen,          // SHQueryUserNotificationState == QUNS_RUNNING_D3D_FULL_SCREEN
    bool RegisteredGame,         // GameConfigStore matched the foreground exe path
    bool KnownGamePath,          // foreground exe under a known game root / curated name
    bool ForegroundIsFullscreen, // foreground window covers the monitor, not shell, not self
    bool UserForceGame,          // user's per-exe "always pause here" (v2)
    bool UserForceNotGame);      // user's per-exe allowlist, never pause (v2)

public static class GameDetectionPolicy
{
    public static bool ShouldSuppress(in GameSignals s, GameDetectionMode mode)
    {
        if (s.UserForceNotGame) return false;          // explicit allow wins
        if (s.UserForceGame) return true;              // explicit deny wins
        if (mode == GameDetectionMode.Off) return false;

        // Balanced (default): high-confidence signals only. Deliberately NO bare-fullscreen,
        // so fullscreen video / accelerated browsers never false-positive.
        if (s.D3DFullscreen || s.RegisteredGame || s.KnownGamePath) return true;

        // Aggressive (opt-in): also any borderless/exclusive fullscreen app — catches obscure
        // windowed games, but WILL also trip on fullscreen YouTube/Netflix.
        if (mode == GameDetectionMode.Aggressive && s.ForegroundIsFullscreen) return true;

        return false;
    }
}
