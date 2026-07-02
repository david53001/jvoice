namespace JVoice.Core.Models;

/// User-selectable aggressiveness of the game-detection hotkey suppression.
/// Off = never suppress; Balanced (default) = suppress only on high-confidence game
/// signals (no bare-fullscreen, so fullscreen video never false-positives);
/// Aggressive = also suppress in any borderless/exclusive fullscreen app.
public enum GameDetectionMode
{
    Off,
    Balanced,
    Aggressive,
}
