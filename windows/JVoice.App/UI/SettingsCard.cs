using System.Windows;
using System.Windows.Controls;

namespace JVoice.App.UI;

/// A Settings section card (parity row 28 — replaces the monochrome DarkSection and its accent dot).
/// A templated ContentControl (NOT a UserControl) so its Content keeps the declaring file's namescope —
/// letting SettingsView name elements (Recorder, NewWordBox) inside a card. The visual (a caption
/// label over the content, on a 4 % tint with an 8 % hairline, radius 10) is the implicit Style in
/// JVoicePalette.xaml.
public sealed class SettingsCard : ContentControl
{
    public static readonly DependencyProperty HeaderTextProperty =
        DependencyProperty.Register(nameof(HeaderText), typeof(string), typeof(SettingsCard),
            new FrameworkPropertyMetadata("", FrameworkPropertyMetadataOptions.None, null, CoerceUpper));

    /// Displayed UPPERCASED (coerced on set, so TemplateBinding sees the upper form).
    public string HeaderText
    {
        get => (string)GetValue(HeaderTextProperty);
        set => SetValue(HeaderTextProperty, value);
    }

    private static object CoerceUpper(DependencyObject d, object value)
        => ((string)value).ToUpperInvariant();
}
