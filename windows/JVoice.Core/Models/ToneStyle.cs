namespace JVoice.Core.Models;

/// Ports Swift `AppMode` / `ToneMode`. Three tone styles applied in TextProcessor.Format.
public enum ToneStyle
{
    Casual,
    Formal,
    VeryCasual,
}

public static class ToneStyleExtensions
{
    public static string DisplayName(this ToneStyle style) => style switch
    {
        ToneStyle.Casual => "Casual",
        ToneStyle.Formal => "Formal",
        ToneStyle.VeryCasual => "Very Casual",
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
