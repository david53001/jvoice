using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Threading;
using JVoice.Core.Models;

namespace JVoice.App.UI;

public partial class HudView : UserControl
{
    private Storyboard? _pulse;
    private Storyboard? _spin;
    private readonly DispatcherTimer _elapsedTimer = new() { Interval = TimeSpan.FromSeconds(1) };
    private DateTime _preparingStart;
    private Action? _onStop;

    // Segoe MDL2 Assets glyphs (ship with Windows 10/11).
    private const string GlyphMic = "";       // Microphone
    private const string GlyphGear = "";      // Settings
    private const string GlyphDownload = "";  // Download
    private const string GlyphWaveform = "";  // Volume (closest audio glyph for Transcribing)
    private const string GlyphCheck = "";     // CheckMark
    private const string GlyphWarning = "";   // Warning

    public HudView()
    {
        InitializeComponent();
        BuildArcGeometry();
        StopButton.Click += (_, _) => _onStop?.Invoke();
        _elapsedTimer.Tick += (_, _) => UpdateElapsed();
    }

    /// 28x28 circle, trim 0..0.28 -> an arc of 100.8 degrees starting at 12 o'clock.
    private void BuildArcGeometry()
    {
        const double size = 28, r = size / 2 - 0.75; // inset by half the stroke (1.5)
        var c = new Point(size / 2, size / 2);
        double sweep = 0.28 * 360.0; // 100.8 degrees
        double a0 = -90 * Math.PI / 180.0;            // top
        double a1 = (-90 + sweep) * Math.PI / 180.0;
        var p0 = new Point(c.X + r * Math.Cos(a0), c.Y + r * Math.Sin(a0));
        var p1 = new Point(c.X + r * Math.Cos(a1), c.Y + r * Math.Sin(a1));
        var fig = new PathFigure { StartPoint = p0 };
        fig.Segments.Add(new ArcSegment(p1, new Size(r, r), 0, sweep > 180, SweepDirection.Clockwise, true));
        var geo = new PathGeometry();
        geo.Figures.Add(fig);
        RingArc.Data = geo;
    }

    /// Apply a HUD state: recolor, pick layout, run/stop animations.
    public void Apply(HudState state, Action? onStop)
    {
        _onStop = onStop;

        switch (state.Kind)
        {
            case HudStateKind.Recording:
                Recolor("#4A9EFF", "#D1E8FF", subtitleOpacity: 0.55);
                ShowRing(GlyphMic);
                SetText("Recording", "Listening...");
                StopButton.Visibility = Visibility.Visible;
                break;

            case HudStateKind.PreparingModel:
                Recolor("#8060FF", "#CABBFF", subtitleOpacity: 0.62);
                ShowRing(GlyphGear);
                SetText("Preparing Model", "One-time setup - keep JVoice open - 0:00");
                StopButton.Visibility = Visibility.Collapsed;
                _preparingStart = DateTime.UtcNow;
                _elapsedTimer.Start();
                break;

            case HudStateKind.DownloadingModel:
                Recolor("#8060FF", "#CABBFF", subtitleOpacity: 0.62);
                ShowRing(GlyphDownload);
                int pct = (int)Math.Round((state.Progress ?? 0) * 100);
                SetText("Downloading Model", $"Downloading the speech model... {pct}%");
                StopButton.Visibility = Visibility.Collapsed;
                break;

            case HudStateKind.Transcribing:
                Recolor("#00D4E0", "#A0F0F7", subtitleOpacity: 0.55);
                ShowRing(GlyphWaveform);
                SetText("Transcribing", "Processing...");
                StopButton.Visibility = Visibility.Collapsed;
                break;

            case HudStateKind.Done:
                Recolor("#6EE7B7", "#B1FCB7", subtitleOpacity: 0);
                ShowDisc(GlyphCheck);
                SetText(state.Headline, null);
                StopButton.Visibility = Visibility.Collapsed;
                break;

            case HudStateKind.Error:
                Recolor("#FAA060", "#FFD1A0", subtitleOpacity: 0);
                ShowDisc(GlyphWarning);
                SetText(state.Headline, state.Subtitle);
                StopButton.Visibility = Visibility.Collapsed;
                break;

            default: // Idle - view is hidden by the window; nothing to draw.
                StopAnimations();
                break;
        }

        if (state.Kind != HudStateKind.PreparingModel)
            _elapsedTimer.Stop();
    }

    private void UpdateElapsed()
    {
        int s = Math.Max(0, (int)(DateTime.UtcNow - _preparingStart).TotalSeconds);
        Subtitle.Text = $"One-time setup - keep JVoice open - {s / 60}:{s % 60:D2}";
    }

    private void SetText(string title, string? subtitle)
    {
        Title.Text = title;
        if (subtitle is null) { Subtitle.Visibility = Visibility.Collapsed; }
        else { Subtitle.Visibility = Visibility.Visible; Subtitle.Text = subtitle; }
    }

    private void Recolor(string accentHex, string textHex, double subtitleOpacity)
    {
        var accent = (Color)ColorConverter.ConvertFromString(accentHex)!;
        var text = (Color)ColorConverter.ConvertFromString(textHex)!;

        PillBorderBrush.Color = accent;          // opacity 0.22 already set in XAML
        OverlayStop0.Color = MakeColor(accent, 0.06);
        GlowInnerFx.Color = accent;
        GlowOuterFx.Color = accent;
        AuraStop0.Color = MakeColor(accent, 0.18);
        RingArcBrush.Color = accent;
        RingArcGlow.Color = accent;
        RingGlyphBrush.Color = accent;
        DiscFillBrush.Color = accent;
        DiscStrokeBrush.Color = accent;
        DiscGlyphBrush.Color = accent;
        DiscGlow.Color = accent;
        TitleBrush.Color = text;
        TitleGlow.Color = accent;
        SubtitleBrush.Color = accent;
        SubtitleBrush.Opacity = subtitleOpacity;
    }

    private static Color MakeColor(Color c, double a)
        => Color.FromArgb((byte)Math.Round(a * 255), c.R, c.G, c.B);

    private void ShowRing(string glyph)
    {
        Ring.Visibility = Visibility.Visible;
        Disc.Visibility = Visibility.Collapsed;
        RingGlyph.Text = glyph;
        StartAnimations();
    }

    private void ShowDisc(string glyph)
    {
        Ring.Visibility = Visibility.Collapsed;
        Disc.Visibility = Visibility.Visible;
        DiscGlyph.Text = glyph;
        StopAnimations();
    }

    private void StartAnimations()
    {
        StopAnimations();

        // Pulse aura: scale 0.9 -> 1.05, easeInOut 1.8s, repeat forever, autoreverse.
        var pulseX = new DoubleAnimation
        {
            From = 0.9, To = 1.05, Duration = TimeSpan.FromSeconds(1.8),
            AutoReverse = true, RepeatBehavior = RepeatBehavior.Forever,
            EasingFunction = new SineEase { EasingMode = EasingMode.EaseInOut }
        };
        var pulseY = pulseX.Clone();
        Storyboard.SetTarget(pulseX, AuraScale);
        Storyboard.SetTargetProperty(pulseX, new PropertyPath("ScaleX"));
        Storyboard.SetTarget(pulseY, AuraScale);
        Storyboard.SetTargetProperty(pulseY, new PropertyPath("ScaleY"));
        _pulse = new Storyboard();
        _pulse.Children.Add(pulseX);
        _pulse.Children.Add(pulseY);
        _pulse.Begin();

        // Spinning arc: full 360 degrees every 4.0s, linear, forever.
        var spin = new DoubleAnimation
        {
            From = 0, To = 360, Duration = TimeSpan.FromSeconds(4.0),
            RepeatBehavior = RepeatBehavior.Forever
        };
        _spin = new Storyboard();
        Storyboard.SetTarget(spin, RingArcRotate);
        Storyboard.SetTargetProperty(spin, new PropertyPath("Angle"));
        _spin.Children.Add(spin);
        _spin.Begin();
    }

    private void StopAnimations()
    {
        _pulse?.Stop(); _pulse = null;
        _spin?.Stop(); _spin = null;
    }
}
