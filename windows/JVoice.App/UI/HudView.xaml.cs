using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Shapes;
using JVoice.App.Platform;
using JVoice.Core.Models;

namespace JVoice.App.UI;

public partial class HudView : UserControl
{
    // The HUD lives in an AllowsTransparency (layered) window. Storyboards started while
    // that window is hidden don't reliably drive it, so we animate from
    // CompositionTarget.Rendering — the WPF per-frame render loop (the analog of macOS
    // TimelineView(.animation)): subscribing keeps it ticking and writing the bars each
    // frame forces the layered window to repaint. A single free-running clock keeps the
    // phase continuous across states.
    private enum BarMode { Hidden, Live, Indeterminate }

    // ---- voice-bar visualizer config (all pre-scale; HudRootScale enlarges the whole pill) ----
    private const int BarCount = 9;
    private const double BarWidth = 4;
    private const double BarGap = 4;           // applied as Margin = BarGap/2 each side
    private const double MaxBarHeight = 34;    // == Bars.Height in the XAML (slim & tall pill)
    private const double MinBarHeight = 2;
    private static readonly double MinScale = MinBarHeight / MaxBarHeight;

    // Live-level shaping: gate out room noise, then lift speech so it fills the bars.
    private const double LevelGate = 0.006;
    private const double LevelGain = 3.6;
    private const double AttackRate = 0.55;    // fast rise toward a louder target
    private const double DecayRate = 0.18;     // slow fall when it goes quiet

    private readonly Stopwatch _clock = Stopwatch.StartNew();
    private bool _animating;
    private BarMode _mode = BarMode.Hidden;
    private double _smoothLevel;

    private Rectangle[] _bars = [];
    private ScaleTransform[] _barScale = [];
    private double[] _barLevel = [];           // current (smoothed) 0..1 height of each bar
    private double[] _phase = [];
    private double[] _speed = [];
    private double[] _weight = [];             // centre-weighted bell (tallest in the middle)

    /// Supplies the live mic level (0..1 peak). Set by App via HudWindow. Null => bars idle.
    public Func<float>? InputLevelProvider { get; set; }

    public HudView()
    {
        InitializeComponent();
        // Enlarge the pill to stay crisp: 1.1 at native resolution; more when the desktop
        // runs below native (the monitor's scaler interpolates the framebuffer). The new
        // bars are solid shapes, so they survive that interpolation far better than the old
        // glowy text did. See DisplayMetrics.
        HudRootScale.ScaleX = HudRootScale.ScaleY = DisplayMetrics.HudScale;
        BuildBars();
    }

    /// Create the bar Rectangles once. Each grows/shrinks symmetrically about its centre
    /// via a ScaleTransform (RenderTransform, not Height) so the per-frame animation never
    /// triggers a layout pass and the pill never resizes while recording.
    private void BuildBars()
    {
        _bars = new Rectangle[BarCount];
        _barScale = new ScaleTransform[BarCount];
        _barLevel = new double[BarCount];
        _phase = new double[BarCount];
        _speed = new double[BarCount];
        _weight = new double[BarCount];

        var fill = new SolidColorBrush(Color.FromRgb(0xFF, 0xFF, 0xFF));
        fill.Freeze();

        for (int i = 0; i < BarCount; i++)
        {
            double bell = Math.Sin(Math.PI * (i + 0.5) / BarCount); // 0..1, peak at centre
            _weight[i] = 0.45 + 0.55 * bell;
            _phase[i] = i * 0.7;
            _speed[i] = 6.5 + (i % 3) * 2.3;    // varied speeds so the bars swerve independently
            _barLevel[i] = 0;

            var scale = new ScaleTransform(1, MinScale);
            var bar = new Rectangle
            {
                Width = BarWidth,
                Height = MaxBarHeight,
                RadiusX = BarWidth / 2,
                RadiusY = BarWidth / 2,
                Fill = fill,
                VerticalAlignment = VerticalAlignment.Center,
                Margin = new Thickness(BarGap / 2, 0, BarGap / 2, 0),
                Opacity = 0.55 + 0.45 * bell,    // brightest in the centre, fading to the edges
                RenderTransformOrigin = new Point(0.5, 0.5),
                RenderTransform = scale,
            };
            _barScale[i] = scale;
            _bars[i] = bar;
            Bars.Children.Add(bar);
        }
    }

    /// Apply a HUD state: pick the layout (bars / error / hidden) and start or stop the loop.
    public void Apply(HudState state)
    {
        switch (state.Kind)
        {
            case HudStateKind.Recording:
                SetMode(BarMode.Live);
                break;

            case HudStateKind.Transcribing:
            case HudStateKind.PreparingModel:
            case HudStateKind.DownloadingModel:
                SetMode(BarMode.Indeterminate);
                break;

            case HudStateKind.Error:
                // The only state with text. Show the specific message ("No speech detected.",
                // a paste failure, …) so the user knows what happened; fall back to a generic
                // line if there's no payload.
                ShowError(state.Subtitle ?? "Something went wrong");
                break;

            default: // Idle / Done — nothing to draw; the window hides the HUD entirely.
                SetMode(BarMode.Hidden);
                break;
        }
    }

    /// Pose the bars in a representative static recording frame (centre-weighted bell) for a
    /// headless still capture — see App.RenderHudToFile. No animation loop is started, so a
    /// single off-screen render shows real bar heights rather than the resting floor.
    internal void PrepareStaticCapture()
    {
        SetMode(BarMode.Hidden);          // tear down any rendering subscription
        Bars.Visibility = Visibility.Visible;
        ErrorPanel.Visibility = Visibility.Collapsed;
        for (int i = 0; i < _bars.Length; i++)
        {
            double bell = Math.Sin(Math.PI * (i + 0.5) / BarCount);
            double level = 0.30 + 0.65 * bell; // a believable mid-level frame
            _barScale[i].ScaleY = MinScale + (1 - MinScale) * level;
        }
    }

    private void SetMode(BarMode mode)
    {
        _mode = mode;
        bool barsVisible = mode is BarMode.Live or BarMode.Indeterminate;
        Bars.Visibility = barsVisible ? Visibility.Visible : Visibility.Collapsed;
        ErrorPanel.Visibility = Visibility.Collapsed;
        if (barsVisible) StartAnimations();
        else StopAnimations();
    }

    private void ShowError(string message)
    {
        _mode = BarMode.Hidden;
        StopAnimations();
        Bars.Visibility = Visibility.Collapsed;
        ErrorText.Text = message;
        ErrorPanel.Visibility = Visibility.Visible;
    }

    private void StartAnimations()
    {
        if (_animating) return;
        _animating = true;
        CompositionTarget.Rendering += OnRendering;
    }

    private void StopAnimations()
    {
        if (!_animating) return;
        _animating = false;
        CompositionTarget.Rendering -= OnRendering;
        _smoothLevel = 0;
        for (int i = 0; i < _bars.Length; i++)
        {
            _barLevel[i] = 0;
            _barScale[i].ScaleY = MinScale;
        }
    }

    /// Per-frame tick: update the smoothed mic level, then drive every bar's height.
    private void OnRendering(object? sender, EventArgs e)
    {
        double t = _clock.Elapsed.TotalSeconds;

        if (_mode == BarMode.Live)
        {
            double raw = InputLevelProvider?.Invoke() ?? 0f;
            double target = Math.Clamp((raw - LevelGate) * LevelGain, 0, 1);
            double rate = target > _smoothLevel ? AttackRate : DecayRate;
            _smoothLevel += (target - _smoothLevel) * rate;
        }

        for (int i = 0; i < _bars.Length; i++)
        {
            double target01 = _mode == BarMode.Live ? LiveBar(i, t) : IndeterminateBar(i, t);
            _barLevel[i] += (Math.Clamp(target01, 0, 1) - _barLevel[i]) * 0.5; // per-bar smoothing
            _barScale[i].ScaleY = MinScale + (1 - MinScale) * _barLevel[i];
        }
    }

    /// Recording: bar height = smoothed mic energy, centre-weighted and given an independent
    /// per-bar wobble so the row "swerves"; never fully flat (a gentle breathing at silence).
    private double LiveBar(int i, double t)
    {
        double osc = 0.5 + 0.5 * Math.Sin(t * _speed[i] + _phase[i]);
        double idle = 0.05 + 0.04 * Math.Sin(t * 1.6 + _phase[i]);
        double energy = _smoothLevel * _weight[i] * (0.55 + 0.45 * osc);
        return Math.Max(idle, energy);
    }

    /// Transcribing / preparing / downloading (no live mic): a soft pulse that sweeps back
    /// and forth across the row — a quiet "working" shimmer, still text-free.
    private double IndeterminateBar(int i, double t)
    {
        double pos = 0.5 + 0.5 * Math.Sin(t * 1.7);              // sweep centre, ping-pong
        double d = (double)i / (BarCount - 1) - pos;
        double bump = Math.Exp(-(d * d) / (2 * 0.05));
        double flicker = 0.05 * Math.Sin(t * 9 + _phase[i]);
        return 0.12 + 0.72 * bump * _weight[i] + flicker;
    }
}
