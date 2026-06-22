using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace JVoice.App.UI;

/// A titled dark card (DESIGN-TOKENS §2). A templated ContentControl (NOT a
/// UserControl) so its Content keeps the declaring file's namescope — letting
/// SettingsView name elements (Recorder, NewWordBox) inside a section. The visual
/// (accent dot + UPPERCASED title + divider + content) is the implicit Style in
/// JVoicePalette.xaml.
public sealed class DarkSection : ContentControl
{
    public static readonly DependencyProperty HeaderTextProperty =
        DependencyProperty.Register(nameof(HeaderText), typeof(string), typeof(DarkSection),
            new FrameworkPropertyMetadata("", FrameworkPropertyMetadataOptions.None, null, CoerceUpper));

    /// Displayed UPPERCASED (coerced on set, so TemplateBinding sees the upper form).
    public string HeaderText
    {
        get => (string)GetValue(HeaderTextProperty);
        set => SetValue(HeaderTextProperty, value);
    }

    private static object CoerceUpper(DependencyObject d, object value)
        => ((string)value).ToUpperInvariant();

    public static readonly DependencyProperty AccentBrushProperty =
        DependencyProperty.Register(nameof(AccentBrush), typeof(Brush), typeof(DarkSection),
            new PropertyMetadata(Brushes.White, OnAccentChanged));

    public Brush AccentBrush
    {
        get => (Brush)GetValue(AccentBrushProperty);
        set => SetValue(AccentBrushProperty, value);
    }

    public static readonly DependencyProperty AccentGlowColorProperty =
        DependencyProperty.Register(nameof(AccentGlowColor), typeof(Color), typeof(DarkSection),
            new PropertyMetadata(Colors.White));

    public Color AccentGlowColor
    {
        get => (Color)GetValue(AccentGlowColorProperty);
        set => SetValue(AccentGlowColorProperty, value);
    }

    private static void OnAccentChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        if (d is DarkSection s && e.NewValue is SolidColorBrush b)
            s.AccentGlowColor = b.Color;
    }
}
