using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Effects;
using JVoice.Core;

namespace JVoice.App.UI;

/// <summary>
/// Text with the "Claude is working" glow — ONE control for both places (Mac ClaudeGlowText): the
/// "AI refining" pill (<see cref="ClaudeGlow.Full"/>) and the AI Polish card's title
/// (<see cref="ClaudeGlow.Subtle"/>). The letters are <see cref="BaseBrush"/> with a #D97757 band swept
/// through them; an orange glow breathes behind. It animates only while it is actually visible (a
/// hidden pill or a closed Settings window costs nothing) and holds a still pose when Windows'
/// animations are off or the element is rendered off-screen.
/// </summary>
public sealed class ClaudeGlowText : ContentControl
{
    public static readonly DependencyProperty TextProperty = DependencyProperty.Register(
        nameof(Text), typeof(string), typeof(ClaudeGlowText), new PropertyMetadata("", (d, e) => ((ClaudeGlowText)d)._text.Text = (string)e.NewValue));

    public static readonly DependencyProperty SubtleProperty = DependencyProperty.Register(
        nameof(Subtle), typeof(bool), typeof(ClaudeGlowText), new PropertyMetadata(false, (d, _) => ((ClaudeGlowText)d).ApplyPose(null)));

    public static readonly DependencyProperty BaseBrushProperty = DependencyProperty.Register(
        nameof(BaseBrush), typeof(Brush), typeof(ClaudeGlowText), new PropertyMetadata(Brushes.White, (d, _) => ((ClaudeGlowText)d).RebuildBrush()));

    public string Text { get => (string)GetValue(TextProperty); set => SetValue(TextProperty, value); }

    /// <summary>false = the pill's full strength; true = the card title's slower, fainter glow.</summary>
    public bool Subtle { get => (bool)GetValue(SubtleProperty); set => SetValue(SubtleProperty, value); }

    /// <summary>The letters' normal colour (white on the pill, Text.Secondary on a card title).</summary>
    public Brush BaseBrush { get => (Brush)GetValue(BaseBrushProperty); set => SetValue(BaseBrushProperty, value); }

    private static readonly Color Orange = Color.FromRgb(ClaudeGlow.R, ClaudeGlow.G, ClaudeGlow.B);
    private readonly TextBlock _text = new() { VerticalAlignment = VerticalAlignment.Center };
    private readonly TranslateTransform _sweep = new();
    private readonly DropShadowEffect _glow = new() { Color = Orange, ShadowDepth = 0 };
    private readonly Stopwatch _clock = Stopwatch.StartNew();
    private bool _animating;

    private ClaudeGlow Glow => Subtle ? ClaudeGlow.Subtle : ClaudeGlow.Full;

    public ClaudeGlowText()
    {
        Focusable = false;
        IsTabStop = false;
        _text.Effect = _glow;
        Content = _text;
        RebuildBrush();
        ApplyPose(null);
        IsVisibleChanged += (_, _) => UpdateAnimation();
        Loaded += (_, _) => UpdateAnimation();
        Unloaded += (_, _) => StopAnimation();
    }

    private void RebuildBrush()
    {
        Color baseColor = (BaseBrush as SolidColorBrush)?.Color ?? Colors.White;
        var brush = new LinearGradientBrush
        {
            StartPoint = new Point(0, 0.5),
            EndPoint = new Point(1, 0.5),
            SpreadMethod = GradientSpreadMethod.Pad,
            RelativeTransform = _sweep,
        };
        brush.GradientStops.Add(new GradientStop(baseColor, 0));
        brush.GradientStops.Add(new GradientStop(baseColor, 0.32));
        brush.GradientStops.Add(new GradientStop(Orange, 0.5));
        brush.GradientStops.Add(new GradientStop(baseColor, 0.68));
        brush.GradientStops.Add(new GradientStop(baseColor, 1));
        _text.Foreground = brush;
    }

    private void ApplyPose(double? seconds)
    {
        var glow = Glow;
        var (x, opacity) = seconds is { } t ? glow.Pose(t) : glow.StaticPose;
        _sweep.X = x;
        _glow.Opacity = opacity;
        _glow.BlurRadius = glow.BlurRadius;
    }

    private void UpdateAnimation()
    {
        if (IsVisible && IsLoaded && SystemParameters.ClientAreaAnimation) StartAnimation();
        else StopAnimation();
    }

    private void StartAnimation()
    {
        if (_animating) return;
        _animating = true;
        CompositionTarget.Rendering += OnRendering;
    }

    private void StopAnimation()
    {
        if (!_animating) return;
        _animating = false;
        CompositionTarget.Rendering -= OnRendering;
        ApplyPose(null);
    }

    private void OnRendering(object? sender, EventArgs e) => ApplyPose(_clock.Elapsed.TotalSeconds);
}
