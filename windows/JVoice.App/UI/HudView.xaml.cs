using System.Diagnostics;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Shapes;
using JVoice.App.Platform;
using JVoice.Core.Models;

namespace JVoice.App.UI;

public partial class HudView : UserControl
{
    // The bars animate from CompositionTarget.Rendering — the WPF per-frame loop (the analog of the
    // Mac's TimelineView): a storyboard started while the layered window is hidden doesn't reliably
    // drive it, and writing the bars each frame forces the layered window to repaint. The loop runs
    // ONLY while a live pill is showing; a hidden or prewarmed pill draws nothing (row 20).
    private enum BarMode { Hidden, Live, Shimmer }

    // ---- shared bar geometry (Mac HUDView.Bars): thin capsules that rest as a flat line ----
    private const int BarCount = 15;
    private const double BarWidth = 3;
    private const double BarSpacing = 2;
    private const double BarMinHeight = 2;
    private const double LiveMaxHeight = 26;
    private const double ShimmerMaxHeight = 10;

    // ---- capsule geometry (Mac HUDLayout) ----
    private const double PillMinWidth = 240;     // the recording / transcribing row
    private static readonly Duration Morph = TimeSpan.FromMilliseconds(300);

    private readonly Stopwatch _clock = Stopwatch.StartNew();
    private double _lastAppliedFrame = -1; // FramePacer: last frame we actually wrote the bars for
    private bool _animating;
    private BarMode _mode = BarMode.Hidden;
    private Rectangle[] _bars = [];
    private double[] _barLevel = [];
    private double[] _phase = [];
    private double[] _speed = [];
    private double[] _weight = [];
    private FrameworkElement? _shown;
    private System.Windows.Threading.DispatcherTimer? _elapsedTimer;
    private DateTime _preparingSince;

    /// Frames the pill actually drew, process-wide — the --latency-probe reads it to prove the hidden
    /// / prewarmed pill draws NOTHING (row 20). A global render-tick count can't show that: the
    /// probe's own CompositionTarget.Rendering subscription keeps WPF ticking.
    internal static long FramesDrawn;

    /// True while this pill is subscribed to the render loop.
    internal bool IsAnimating => _animating;

    /// The red stop control was clicked (recording only).
    public event Action? StopRequested;

    /// Supplies the live mic level (0..1). UNUSED: the recording bars are a continuous,
    /// mic-independent wave (David preferred a steady flow over mic-reactive bars, which stuttered on
    /// his words — §7 #23). Kept so a mic-reactive mode could be re-enabled without re-threading it.
    public Func<float>? InputLevelProvider { get; set; }

    public HudView()
    {
        InitializeComponent();
        HudRootScale.ScaleX = HudRootScale.ScaleY = DisplayMetrics.HudScale;
        BuildBars();
        Capsule.SizeChanged += (_, _) => ClipShadow();
        LivePanel.Visibility = Visibility.Collapsed;
        LivePanel.Opacity = 0;
    }

    private void BuildBars()
    {
        _bars = new Rectangle[BarCount];
        _barLevel = new double[BarCount];
        _phase = new double[BarCount];
        _speed = new double[BarCount];
        _weight = new double[BarCount];
        var fill = new SolidColorBrush(Colors.White);
        fill.Freeze();
        for (int i = 0; i < BarCount; i++)
        {
            double bell = Math.Sin(Math.PI * (i + 0.5) / BarCount); // 0..1, peak at centre
            _weight[i] = 0.62 + 0.38 * bell;
            _phase[i] = i * 0.7;
            _speed[i] = 6.5 + (i % 3) * 2.3;
            var bar = new Rectangle
            {
                Width = BarWidth,
                Height = BarMinHeight,
                RadiusX = BarWidth / 2,
                RadiusY = BarWidth / 2,
                Fill = fill,
                VerticalAlignment = VerticalAlignment.Center,
                Margin = new Thickness(i == 0 ? 0 : BarSpacing, 0, 0, 0),
                Opacity = 0.45,
            };
            _bars[i] = bar;
            Bars.Children.Add(bar);
        }
    }

    /// The shadow is a black capsule's drop shadow with the capsule itself cut away, so it never
    /// darkens the translucent body; re-cut whenever the capsule's size changes (every morph frame).
    private void ClipShadow()
    {
        double w = Capsule.ActualWidth, h = Capsule.ActualHeight;
        if (w <= 0 || h <= 0) return;
        var outside = new RectangleGeometry(new Rect(-40, -40, w + 80, h + 80));
        var body = new RectangleGeometry(new Rect(0, 0, w, h), h / 2, h / 2);
        var clip = new CombinedGeometry(GeometryCombineMode.Exclude, outside, body);
        clip.Freeze();
        Shadow.Clip = clip;
    }

    /// Apply a HUD state instantly (the first show, a hide, a headless render).
    public void Apply(HudState state) => Apply(state, animate: false);

    /// Apply a HUD state; <paramref name="animate"/> morphs the capsule from the pill on screen (only
    /// when a visible pill replaces another — the caller decides).
    public void Apply(HudState state, bool animate)
    {
        FrameworkElement? next = state.Kind switch
        {
            HudStateKind.Recording => ShowLive(stop: true),
            HudStateKind.Transcribing => ShowLive(stop: false),
            HudStateKind.PreparingModel => ShowModel(downloading: false, 0),
            HudStateKind.DownloadingModel => ShowModel(downloading: true, state.Progress ?? 0),
            HudStateKind.Done => ShowStatus("", Accent.Green, "Pasted"),
            HudStateKind.Copied => ShowStatus("", Accent.Green, "Copied"),
            HudStateKind.Notice => ShowStatus("", Accent.Neutral, state.Payload ?? ""),
            HudStateKind.Error => ShowStatus("", Accent.Red,
                string.IsNullOrEmpty(state.Payload) ? "Something went wrong" : state.Payload!),
            _ => null,
        };

        SetBarMode(state.Kind switch
        {
            HudStateKind.Recording => BarMode.Live,
            HudStateKind.Transcribing => BarMode.Shimmer,
            _ => BarMode.Hidden,
        });
        SetElapsedTimer(state.Kind == HudStateKind.PreparingModel);

        if (next is null) SwapInstant(null);
        else if (animate && _shown is not null && _shown != next && Capsule.ActualWidth > 0) MorphTo(next);
        else if (!(animate && _shown == next)) SwapInstant(next); // same pill, new content: no motion
    }

    private FrameworkElement ShowLive(bool stop)
    {
        // Transcribing keeps the stop slot, inert and grey (its template), so the J-bars-stop row stays centred in the
        // capsule and nothing moves between recording and transcribing (round 2 JV #6, round 3 JV #6).
        StopButton.IsEnabled = stop;
        StopButton.ToolTip = stop ? "Stop recording" : null;
        return LivePanel;
    }

    private enum Accent { Green, Red, Neutral }

    private static Brush AccentBrush(Accent a) => Frozen(a switch
    {
        Accent.Green => Color.FromRgb(0x6C, 0xCB, 0x5F),
        Accent.Red => Color.FromRgb(0xFF, 0x99, 0xA4),
        _ => Color.FromArgb(0xC5, 0xFF, 0xFF, 0xFF), // a notice: no meaning colour, the secondary text white
    });

    private static SolidColorBrush Frozen(Color c)
    {
        var b = new SolidColorBrush(c);
        b.Freeze();
        return b;
    }

    private FrameworkElement ShowStatus(string glyph, Accent accent, string text)
    {
        StatusIcon.Text = glyph;
        StatusIcon.Foreground = AccentBrush(accent);
        StatusText.Text = text;
        AutomationProperties.SetName(StatusPanel, text);
        return StatusPanel;
    }

    private FrameworkElement ShowModel(bool downloading, double progress)
    {
        ModelIcon.Text = downloading ? "" : "";
        ModelTitle.Text = downloading ? "Downloading Model" : "Preparing Model";
        double p = Math.Clamp(double.IsFinite(progress) ? progress : 0, 0, 1);
        ModelDetail.Text = downloading ? $"{p * 100:0}%" : PreparingDetail();
        ModelTrack.Visibility = downloading ? Visibility.Visible : Visibility.Collapsed;
        ModelFill.Width = ModelTrack.Width * p;
        return ModelPanel;
    }

    private string PreparingDetail()
    {
        int s = Math.Max(0, (int)(DateTime.UtcNow - _preparingSince).TotalSeconds);
        return $"One-time setup — keep JVoice open · {s / 60}:{s % 60:00}";
    }

    /// The preparing pill's ticking counter proves the app is alive (a static pill reads as a hang).
    private void SetElapsedTimer(bool on)
    {
        if (on)
        {
            if (_elapsedTimer is not null) return;
            _preparingSince = DateTime.UtcNow;
            ModelDetail.Text = PreparingDetail();
            _elapsedTimer = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
            _elapsedTimer.Tick += (_, _) => ModelDetail.Text = PreparingDetail();
            _elapsedTimer.Start();
        }
        else
        {
            _elapsedTimer?.Stop();
            _elapsedTimer = null;
        }
    }

    private void SwapInstant(FrameworkElement? next)
    {
        Capsule.BeginAnimation(WidthProperty, null);
        Capsule.Width = double.NaN;
        foreach (var panel in new FrameworkElement[] { LivePanel, StatusPanel, ModelPanel })
        {
            panel.BeginAnimation(OpacityProperty, null);
            bool on = panel == next;
            panel.Opacity = on ? 1 : 0;
            panel.Visibility = on ? Visibility.Visible : Visibility.Collapsed;
        }
        Capsule.MinWidth = next == LivePanel ? PillMinWidth : 56;
        _shown = next;
    }

    /// One capsule turns into the next: its width eases to the new pill's natural width while the old
    /// contents fade out and the new fade in (Mac `.snappy(duration: 0.3)` ≈ 300 ms ease-out).
    private void MorphTo(FrameworkElement next)
    {
        var old = _shown!;
        double from = Capsule.ActualWidth;

        next.BeginAnimation(OpacityProperty, null);
        next.Opacity = 0;
        next.Visibility = Visibility.Visible;
        next.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
        double min = next == LivePanel ? PillMinWidth : 56;
        double to = Math.Max(min, next.DesiredSize.Width + 2); // + the 1 px hairline each side

        Capsule.MinWidth = 0;
        var width = new DoubleAnimation(from, to, Morph) { EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut } };
        width.Completed += (_, _) =>
        {
            if (_shown != next) return; // another morph took over
            Capsule.BeginAnimation(WidthProperty, null);
            Capsule.Width = double.NaN;
            Capsule.MinWidth = min;
        };
        Capsule.BeginAnimation(WidthProperty, width);

        var fadeOut = new DoubleAnimation(0, TimeSpan.FromMilliseconds(150));
        fadeOut.Completed += (_, _) => { if (_shown != old) old.Visibility = Visibility.Collapsed; };
        old.BeginAnimation(OpacityProperty, fadeOut);
        next.BeginAnimation(OpacityProperty, new DoubleAnimation(1, TimeSpan.FromMilliseconds(200))
        {
            BeginTime = TimeSpan.FromMilliseconds(100),
        });
        _shown = next;
    }

    private void OnStopClick(object sender, RoutedEventArgs e) => StopRequested?.Invoke();

    /// Pose the recording pill in a representative static frame for a headless still capture (see
    /// App.RenderHudToFile). No animation loop is started.
    internal void PrepareStaticCapture()
    {
        Apply(HudState.Recording);
        SetBarMode(BarMode.Hidden);
        for (int i = 0; i < _bars.Length; i++)
        {
            double bell = Math.Sin(Math.PI * (i + 0.5) / BarCount);
            SetBar(i, 0.2 + 0.65 * bell * (0.6 + 0.4 * Math.Sin(i * 1.3)), LiveMaxHeight);
        }
    }

    // ---- the bars ----

    private void SetBarMode(BarMode mode)
    {
        _mode = mode;
        if (mode == BarMode.Hidden) StopAnimations();
        else StartAnimations();
    }

    private void StartAnimations()
    {
        if (_animating) return;
        _animating = true;
        _lastAppliedFrame = -1; // first frame of a new state always applies (no stale-pose flash)
        CompositionTarget.Rendering += OnRendering;
    }

    private void StopAnimations()
    {
        if (!_animating) return;
        _animating = false;
        CompositionTarget.Rendering -= OnRendering;
        for (int i = 0; i < _bars.Length; i++)
        {
            _barLevel[i] = 0;
            SetBar(i, 0, LiveMaxHeight);
        }
    }

    private void OnRendering(object? sender, EventArgs e)
    {
        double t = _clock.Elapsed.TotalSeconds;
        // Rendering ticks at the display refresh rate; the pill only needs ~60 fps (FramePacer).
        if (!JVoice.Core.FramePacer.ShouldApply(t, _lastAppliedFrame)) return;
        _lastAppliedFrame = t;
        FramesDrawn++;

        double max = _mode == BarMode.Live ? LiveMaxHeight : ShimmerMaxHeight;
        for (int i = 0; i < _bars.Length; i++)
        {
            double target = _mode == BarMode.Live ? LiveBar(i, t) : ShimmerBar(i, t);
            _barLevel[i] += (Math.Clamp(target, 0, 1) - _barLevel[i]) * 0.5; // per-bar smoothing
            SetBar(i, _barLevel[i], max, _mode == BarMode.Shimmer ? 0.85 : 1);
        }
    }

    /// Height from a 0..1 level; quiet bars sit at a secondary opacity and rise to full white with
    /// their height (Mac Bars.opacity).
    private void SetBar(int i, double level, double maxHeight, double opacityScale = 1)
    {
        double h = BarMinHeight + (maxHeight - BarMinHeight) * Math.Clamp(level, 0, 1);
        _bars[i].Height = h;
        double t = Math.Clamp((h - BarMinHeight) / Math.Max(1, maxHeight - BarMinHeight), 0, 1);
        _bars[i].Opacity = (0.45 + 0.55 * t) * opacityScale;
    }

    /// Recording: a continuous, mic-INDEPENDENT waveform — every bar rises and falls on its own
    /// phase/speed so the row is always flowing (David's preference over mic-reactive bars).
    private double LiveBar(int i, double t)
    {
        double w1 = Math.Sin(t * _speed[i] + _phase[i]);
        double w2 = Math.Sin(t * _speed[i] * 0.41 - _phase[i] * 1.3);
        double v = 0.5 + 0.5 * (0.62 * w1 + 0.38 * w2);
        return (0.18 + 0.82 * v) * _weight[i];
    }

    /// Transcribing: a gentle, low-amplitude shimmer (Mac ShimmerBars).
    private static double ShimmerBar(int i, double t) => 0.5 + 0.5 * Math.Sin(t * 3 + i * 0.6);
}
