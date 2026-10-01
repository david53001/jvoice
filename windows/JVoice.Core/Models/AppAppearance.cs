namespace JVoice.Core.Models;

/// Settings → Appearance (parity row 28, Mac `AppTheme`): follow Windows' light/dark app mode, or force
/// one. System is the default. Stored as the settings key <c>appearance</c>; the schema version did
/// not change, so an older build simply ignores the key.
public enum AppAppearance
{
    System,
    Light,
    Dark,
}

public static class AppAppearanceExtensions
{
    public static string DisplayName(this AppAppearance a) => a switch
    {
        AppAppearance.Light => "Light",
        AppAppearance.Dark => "Dark",
        _ => "System",
    };

    /// Whether the surfaces draw dark: an override wins, System follows Windows' "app mode"
    /// (<c>AppsUseLightTheme</c> = 0 means dark).
    public static bool IsDark(this AppAppearance a, bool systemUsesLightTheme) => a switch
    {
        AppAppearance.Dark => true,
        AppAppearance.Light => false,
        _ => !systemUsesLightTheme,
    };
}
