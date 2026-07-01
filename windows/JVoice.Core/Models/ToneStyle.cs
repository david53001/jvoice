namespace JVoice.Core.Models;

/// Ports Swift `AppMode` / `ToneMode`. Three tone styles applied in TextProcessor.Format.
/// `Code` is a Windows-only 4th value (no macOS equivalent) used by app-aware modes for
/// terminals/IDEs: minimal formatting that preserves casing, symbols and punctuation as spoken.
/// It is NOT part of the manual `Toggled` cycle — it is only selectable as a per-app mode override.
public enum ToneStyle
{
    Casual,
    Formal,
    VeryCasual,
    Code,
}

public static class ToneStyleExtensions
{
    public static string DisplayName(this ToneStyle style) => style switch
    {
        ToneStyle.Casual => "Casual",
        ToneStyle.Formal => "Formal",
        ToneStyle.VeryCasual => "Very Casual",
        ToneStyle.Code => "Code",
        _ => "Casual",
    };

    /// Cycle order from Swift AppMode.toggled.
    public static ToneStyle Toggled(this ToneStyle style) => style switch
    {
        ToneStyle.Casual => ToneStyle.Formal,
        ToneStyle.Formal => ToneStyle.VeryCasual,
        ToneStyle.VeryCasual => ToneStyle.Casual,
        _ => ToneStyle.Casual,
    };
}
