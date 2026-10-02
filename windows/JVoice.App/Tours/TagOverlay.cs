using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Automation.Peers;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Effects;
using System.Windows.Shapes;
using System.Windows.Threading;
using JVoice.App.UI;
using JVoice.Core.Tours;

namespace JVoice.App.Tours;

/// <summary>
/// The tour tag (parity §10.5; Mac <c>TagOverlayController</c> + <c>TagViews</c>): an outline box around the step's
/// control, a dim over the rest of the host, a leader line, and the bubble (title, 1–2 line body, "n of m", Skip Tour,
/// Next / Done / Skip Step). Two borderless no-activate windows owned by the host: the decor (click-through dim,
/// outline, leader) and the bubble (takes clicks, never activates or takes focus). Native look: the bubble in the
/// HOST's light/dark, system text colours, the outline + leader + Next capsule in the user's accent colour.
/// Follows the host's moves and — in the same frame — the anchor's scroll viewer; hides while the control is scrolled
/// fully out of view.
/// </summary>
public sealed class TagOverlay : ITourTagPresenter
{
    private static readonly FontFamily UiFont = new("Segoe UI Variable Text, Segoe UI");
    private const double ShadowMargin = 14;

    public Action? OnNext { get; set; }
    public Action? OnSkipStep { get; set; }
    public Action? OnSkipTour { get; set; }

    private IOverlayHost? _host;
    private Window? _keyHost;
    private ScrollViewer? _scroller;
    private DecorWindow? _decor;
    private TagWindow? _tag;
    private readonly DispatcherTimer _follow;
    private TourStep? _step;
    private string _body = "";
    private int _number, _total;
    private bool _isLast, _done;
    private string _lastLayoutKey = "";

    public TagOverlay()
    {
        _follow = new DispatcherTimer(DispatcherPriority.Background) { Interval = TimeSpan.FromMilliseconds(100) };
        _follow.Tick += (_, _) => Layout(force: false);
    }

    /// <summary>The last placement (for the off-screen preview); null while hidden.</summary>
    public TagPlacementResult? LastPlacement { get; private set; }

    public void Show(ITourHost host, TourStep step, string body, int number, int total, bool isLast)
    {
        if (host is not IOverlayHost overlayHost) return;
        if (!ReferenceEquals(overlayHost, _host)) Detach();
        _host = overlayHost;
        _step = step;
        _body = body;
        (_number, _total, _isLast, _done) = (number, total, isLast, false);
        Attach();
        Rebuild();
        // Lay out after the coordinator's BringIntoView has scrolled (Loaded runs after layout).
        Dispatcher.CurrentDispatcher.BeginInvoke(DispatcherPriority.Loaded, () => Layout(force: true));
        Layout(force: true);
        Announce(TagStyle.Announcement(step.Title, body, number, total));
    }

    public void ShowCompleted()
    {
        if (_step is null) return;
        _done = true;
        Rebuild();
        Layout(force: true);
        Announce("Done");
    }

    public void UpdateProgress(int number, int total, bool isLast)
    {
        if (_step is null || _done || (number == _number && total == _total && isLast == _isLast)) return;
        (_number, _total, _isLast) = (number, total, isLast);
        Rebuild();
        Layout(force: true);
    }

    public void UpdateBody(string body)
    {
        if (_step is null || _done || body == _body) return;
        _body = body;
        Rebuild();
        Layout(force: true);
    }

    public void Hide()
    {
        _step = null;
        _done = false;
        _follow.Stop();
        _decor?.Hide();
        _tag?.Hide();
        LastPlacement = null;
        _lastLayoutKey = "";
        SetScroller(null);
        Unhook(); // a hidden tag must not keep listening to its last host's keys and moves (review round 1 JV #13)
    }

    private void Unhook()
    {
        if (_keyHost is not null)
        {
            _keyHost.PreviewKeyDown -= HostKeyDown;
            _keyHost.LocationChanged -= HostMoved;
            _keyHost.SizeChanged -= HostMoved;
            _keyHost.StateChanged -= HostMoved;
            _keyHost = null;
        }
        Theme.Changed -= OnThemeChanged;
    }

    /// <summary>The app switched light/dark while a tag is up: redraw it in the new look. (Changed also fires for
    /// every opacity step — the Opacity tour demo animates it — which needs no rebuild.)</summary>
    private void OnThemeChanged()
    {
        bool dark = _host?.IsDark ?? Theme.IsDark;
        if (dark == _builtDark) return;
        Rebuild();
        Layout(force: true);
    }

    private bool _builtDark;

    private void Detach()
    {
        Hide();
        try { _tag?.Close(); } catch (InvalidOperationException) { }
        try { _decor?.Close(); } catch (InvalidOperationException) { }
        (_tag, _decor, _keyHost, _host) = (null, null, null, null);
    }

    private void Attach()
    {
        if (_host is null) return;
        if (_keyHost is null && _host.Owner is { } owner)
        {
            _keyHost = owner;
            _keyHost.PreviewKeyDown += HostKeyDown;
            _keyHost.LocationChanged += HostMoved;
            _keyHost.SizeChanged += HostMoved;
            _keyHost.StateChanged += HostMoved;
        }
        // Every host, the tray one too (it has no owner window — round 2 JV #8).
        Theme.Changed -= OnThemeChanged;
        Theme.Changed += OnThemeChanged;
        if (_decor is null)
        {
            _decor = new DecorWindow();
            _tag = new TagWindow(this);
        }
        _follow.Start();
    }

    private void Rebuild()
    {
        if (_step is null) return;
        _builtDark = _host?.IsDark ?? Theme.IsDark;
        _tag?.Build(_step, _body, _number, _total, _isLast, _done, _builtDark);
    }

    private void HostMoved(object? sender, EventArgs e) => Layout(force: true);

    private void SetScroller(ScrollViewer? sv)
    {
        if (ReferenceEquals(sv, _scroller)) return;
        if (_scroller is not null) _scroller.ScrollChanged -= Scrolled;
        _scroller = sv;
        if (_scroller is not null) _scroller.ScrollChanged += Scrolled;
    }

    /// <summary>Synchronous with the scroll (Mac 157698d): a timer alone lagged the box behind the content.</summary>
    private void Scrolled(object sender, ScrollChangedEventArgs e) => Layout(force: true);

    private void HostKeyDown(object sender, KeyEventArgs e)
    {
        if (_step is null || _host is null) return;
        var key = e.Key switch { Key.Enter => TagKey.Enter, Key.Escape => TagKey.Escape, _ => TagKey.Other };
        if (key == TagKey.Other) return;
        bool editable = Keyboard.FocusedElement switch
        {
            TextBox t => !t.IsReadOnly,
            PasswordBox => true,
            _ => false,
        };
        var action = TagKeys.Action(key, Keyboard.Modifiers != ModifierKeys.None, e.IsRepeat, editable, !_step.IsTry, _done,
            hostClaimsKeys: _host.ClaimsKeys);
        if (action == TagKeyAction.None) return;
        e.Handled = true;
        if (action == TagKeyAction.Next) OnNext?.Invoke();
        else OnSkipTour?.Invoke();
    }

    private void Layout(bool force)
    {
        if (_step is null || _host is null || _decor is null || _tag is null) return;
        SetScroller(_host.ScrollerFor(_step.Anchor));
        if (!_host.IsVisible || _host.AnchorRect(_step.Anchor) is not { } control)
        {
            _decor.Hide();
            _tag.Hide();
            _lastLayoutKey = "";
            return;
        }

        var dim = _host.DimFrame;
        var work = WorkArea(control);
        var tagSize = _tag.BubbleSize;
        string key = $"{control}|{dim}|{tagSize}|{work}";
        if (!force && key == _lastLayoutKey && _decor.IsVisible) return;
        _lastLayoutKey = key;

        var placed = TagLayout.Place(new TagLayoutInput(
            ToTag(control), tagSize.Width, tagSize.Height, ToTag(work),
            Host: dim is { } h ? ToTag(h) : null,
            KeepOut: _host.KeepOut is { } k ? ToTag(k) : null,
            VerticalFirst: _host.ParentIsBar(_step.Anchor),
            Placement: _step.Placement));
        LastPlacement = placed;

        double boxRadius = TagStyle.OutlineRadius(placed.Box, _host.AnchorRadius(_step.Anchor));
        var accent = new SolidColorBrush(Theme.AccentFor(_host.IsDark));
        accent.Freeze();
        _decor.Render(dim, _host.DimRadius, TagStyle.DimAlphaFor(_host.IsDark), ToRect(placed.Box), boxRadius, placed, ToRect(placed.Tag), accent);
        _tag.Place(placed.Tag.X - ShadowMargin, placed.Tag.Y - ShadowMargin);

        bool topmost = _host.Owner is null || _host.Owner.Topmost;
        _decor.Topmost = topmost;
        _tag.Topmost = topmost;
        if (!_decor.IsVisible) ShowOwned(_decor, _host.Owner);
        if (!_tag.IsVisible) ShowOwned(_tag, _host.Owner is null ? null : _decor);
    }

    private static void ShowOwned(Window w, Window? owner)
    {
        try
        {
            if (owner is not null && !ReferenceEquals(w.Owner, owner)) w.Owner = owner;
        }
        catch (InvalidOperationException) { }
        w.Show();
    }

    private static Rect WorkArea(Rect control)
    {
        // System.Windows.Forms.Screen isn't referenced here: MonitorFromPoint + GetMonitorInfo, in system-DPI DIPs.
        double scale = GetDpiForSystem() / 96.0;
        var pt = new POINT { X = (int)((control.X + control.Width / 2) * scale), Y = (int)((control.Y + control.Height / 2) * scale) };
        var mon = MonitorFromPoint(pt, 2 /* MONITOR_DEFAULTTONEAREST */);
        var info = new MONITORINFO { cbSize = Marshal.SizeOf<MONITORINFO>() };
        if (mon == IntPtr.Zero || !GetMonitorInfo(mon, ref info)) return SystemParameters.WorkArea;
        var r = info.rcWork;
        return new Rect(r.Left / scale, r.Top / scale, (r.Right - r.Left) / scale, (r.Bottom - r.Top) / scale);
    }

    private void Announce(string text)
    {
        if (_tag?.Bubble is not { } bubble) return;
        try
        {
            var peer = UIElementAutomationPeer.FromElement(bubble) ?? UIElementAutomationPeer.CreatePeerForElement(bubble);
            peer?.RaiseNotificationEvent(AutomationNotificationKind.Other, AutomationNotificationProcessing.ImportantMostRecent, text, "TourTag");
        }
        catch (Exception) { /* no screen reader listening */ }
    }

    /// <summary>Off-screen render (<c>--tour-render</c>): the bubble for one step, on a host-coloured backdrop.</summary>
    internal static FrameworkElement PreviewBubble(TourStep step, string body, int number, int total, bool isLast, bool done, bool dark)
    {
        var w = new TagWindow(new TagOverlay());
        w.Build(step, body, number, total, isLast, done, dark);
        var bubble = w.Bubble;
        w.Content = null;
        return new Border
        {
            Background = new SolidColorBrush(dark ? Color.FromRgb(0x20, 0x20, 0x20) : Color.FromRgb(0xF3, 0xF3, 0xF3)),
            Child = bubble,
        };
    }

    private static TagRect ToTag(Rect r) => new(r.X, r.Y, r.Width, r.Height);
    private static Rect ToRect(TagRect r) => new(r.X, r.Y, Math.Max(0, r.Width), Math.Max(0, r.Height));

    // ------------------------------------------------------------------ windows

    private static void MakeOverlayWindow(Window w)
    {
        w.WindowStyle = WindowStyle.None;
        w.AllowsTransparency = true;
        w.Background = Brushes.Transparent;
        w.ShowInTaskbar = false;
        w.ShowActivated = false;
        w.Focusable = false;
        w.ResizeMode = ResizeMode.NoResize;
        w.WindowStartupLocation = WindowStartupLocation.Manual;
    }

    private static void MakeNonActivating(Window w, bool clickThrough)
    {
        var hwnd = new WindowInteropHelper(w).Handle;
        int ex = GetWindowLong(hwnd, -20);
        ex |= 0x08000000 /* NOACTIVATE */ | 0x00000080 /* TOOLWINDOW */;
        if (clickThrough) ex |= 0x00000020 /* TRANSPARENT */;
        SetWindowLong(hwnd, -20, ex);
    }

    /// <summary>The dim, the outline box and the leader line. Ignores the mouse entirely.</summary>
    private sealed class DecorWindow : Window
    {
        private readonly Canvas _canvas = new() { IsHitTestVisible = false };

        public DecorWindow()
        {
            MakeOverlayWindow(this);
            IsHitTestVisible = false;
            Content = _canvas;
            SourceInitialized += (_, _) => MakeNonActivating(this, clickThrough: true);
        }

        public void Render(Rect? dimFrame, double dimRadius, double dimAlpha, Rect box, double boxRadius,
            TagPlacementResult placed, Rect tag, Brush accent)
        {
            var bounds = Rect.Union(Grow(box, 3), tag);
            if (dimFrame is { } d) bounds.Union(d);
            bounds = Grow(bounds, 2);
            Left = bounds.X;
            Top = bounds.Y;
            Width = bounds.Width;
            Height = bounds.Height;
            Vector o = new(-bounds.X, -bounds.Y);
            _canvas.Children.Clear();

            // The outline's band: 2 outside the box (layout geometry); the visible line is 1.5 on its inner edge.
            var outer = Grow(box, 2);
            double outerRadius = boxRadius + 2;
            if (dimFrame is { } frame)
            {
                // The host's shape minus a hole at the band's outer edge.
                var dim = new CombinedGeometry(GeometryCombineMode.Exclude,
                    new RectangleGeometry(Offset(frame, o), dimRadius, dimRadius),
                    new RectangleGeometry(Offset(outer, o), outerRadius, outerRadius));
                _canvas.Children.Add(new Path { Data = dim, Fill = new SolidColorBrush(Color.FromArgb((byte)(dimAlpha * 255), 0, 0, 0)) });
            }

            double half = TagStyle.OutlineWidth / 2;
            var line = Grow(box, half);
            var r = new Rectangle
            {
                Width = line.Width, Height = line.Height, RadiusX = boxRadius + half, RadiusY = boxRadius + half,
                Stroke = accent, StrokeThickness = TagStyle.OutlineWidth,
            };
            Canvas.SetLeft(r, line.X + o.X);
            Canvas.SetTop(r, line.Y + o.Y);
            _canvas.Children.Add(r);

            if (placed.Leader is { } leader)
                _canvas.Children.Add(new Line
                {
                    X1 = leader.From.X + o.X, Y1 = leader.From.Y + o.Y, X2 = leader.To.X + o.X, Y2 = leader.To.Y + o.Y,
                    Stroke = accent, StrokeThickness = TagStyle.LeaderWidth,
                    StrokeStartLineCap = PenLineCap.Round, StrokeEndLineCap = PenLineCap.Round,
                });
        }

        private static Rect Grow(Rect r, double d) { r.Inflate(d, d); return r; }
        private static Rect Offset(Rect r, Vector v) { r.Offset(v); return r; }
    }

    /// <summary>The bubble. Takes clicks, never activates or takes focus.</summary>
    private sealed class TagWindow : Window
    {
        private readonly TagOverlay _owner;
        public Border Bubble { get; }
        public Size BubbleSize { get; private set; } = new(200, 80);

        public TagWindow(TagOverlay owner)
        {
            _owner = owner;
            MakeOverlayWindow(this);
            SizeToContent = SizeToContent.WidthAndHeight;
            Bubble = new Border
            {
                CornerRadius = new CornerRadius(TagStyle.TagRadius),
                Padding = new Thickness(TagStyle.TagPaddingX, 10, TagStyle.TagPaddingX, 10),
                Margin = new Thickness(ShadowMargin),
                BorderThickness = new Thickness(1),
                Effect = new DropShadowEffect { BlurRadius = 16, ShadowDepth = 4, Direction = 270, Opacity = 0.28 },
                Focusable = false,
            };
            Content = Bubble;
            SourceInitialized += (_, _) => MakeNonActivating(this, clickThrough: false);
        }

        public void Place(double x, double y)
        {
            Left = Math.Round(x);
            Top = Math.Round(y);
        }

        public void Build(TourStep step, string body, int number, int total, bool isLast, bool done, bool dark)
        {
            // The host's light/dark: Fluent's flyout surface, system text colours, the accent for the primary capsule.
            var fill = Solid(dark ? Color.FromRgb(0x2C, 0x2C, 0x2C) : Color.FromRgb(0xF9, 0xF9, 0xF9));
            var hairline = Solid(dark ? Color.FromArgb(0x24, 0xFF, 0xFF, 0xFF) : Color.FromArgb(0x1A, 0, 0, 0));
            var text = Solid(dark ? Colors.White : Color.FromArgb(0xE4, 0, 0, 0));
            var secondary = Solid(dark ? Color.FromArgb(0xC5, 0xFF, 0xFF, 0xFF) : Color.FromArgb(0x9E, 0, 0, 0));
            var subtle = Solid(dark ? Color.FromArgb(0x14, 0xFF, 0xFF, 0xFF) : Color.FromArgb(0x14, 0, 0, 0));
            var accent = Solid(Theme.AccentFor(dark));
            var onAccent = Solid(dark ? Colors.Black : Colors.White);
            Bubble.Background = fill;
            Bubble.BorderBrush = hairline;
            AutomationProperties.SetName(Bubble, "Tour: " + step.Title);

            var title = Text(step.Title, TagStyle.TitleSize, FontWeights.SemiBold, text);
            title.TextTrimming = TextTrimming.CharacterEllipsis;
            var bodyText = Text(TagStyle.KeepChordsTogether(body), TagStyle.BodySize, FontWeights.Normal, text);
            bodyText.Margin = new Thickness(0, 2, 0, 0);

            var footer = new DockPanel { Height = 20, Margin = new Thickness(0, 8, 0, 0), LastChildFill = false };
            if (done)
            {
                var check = new TextBlock
                {
                    Text = "", FontFamily = new FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets"), FontSize = 13,
                    Foreground = accent, VerticalAlignment = VerticalAlignment.Center,
                };
                footer.Children.Add(check);
                var doneLabel = Text("Done", 11, FontWeights.SemiBold, text);
                doneLabel.Margin = new Thickness(6, 0, 0, 0);
                doneLabel.VerticalAlignment = VerticalAlignment.Center;
                footer.Children.Add(doneLabel);
            }
            else
            {
                var counter = Text(TagStyle.Counter(number, total), 11, FontWeights.Medium, secondary);
                counter.VerticalAlignment = VerticalAlignment.Center;
                DockPanel.SetDock(counter, Dock.Left);
                footer.Children.Add(counter);

                var right = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
                DockPanel.SetDock(right, Dock.Right);
                if (TagStyle.ShowsSkipTour(isLast, isExplain: !step.IsTry, total))
                {
                    var skipTour = Text("Skip Tour", 11, FontWeights.SemiBold, secondary);
                    skipTour.VerticalAlignment = VerticalAlignment.Center;
                    var link = new Border { Child = skipTour, Background = Brushes.Transparent, Padding = new Thickness(4, 0, 4, 0) };
                    Pressable(link, () => _owner.OnSkipTour?.Invoke(), "Skip Tour");
                    right.Children.Add(link);
                }
                string label = TagStyle.PrimaryTitle(step.IsTry, isLast);
                var primaryText = Text(label, 11, FontWeights.SemiBold, step.IsTry ? text : onAccent);
                primaryText.VerticalAlignment = VerticalAlignment.Center;
                var primary = new Border
                {
                    Height = 20, CornerRadius = new CornerRadius(10), Padding = new Thickness(8, 0, 8, 0), Margin = new Thickness(4, 0, 0, 0),
                    Background = step.IsTry ? subtle : accent,
                    Child = primaryText,
                };
                Pressable(primary, step.IsTry ? () => _owner.OnSkipStep?.Invoke() : () => _owner.OnNext?.Invoke(), label);
                right.Children.Add(primary);
                footer.Children.Add(right);
            }

            // Width = widest of (title, body on one line, footer) + padding, clamped to 200…260.
            title.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
            var oneLine = Text(body, TagStyle.BodySize, FontWeights.Normal, text);
            oneLine.TextWrapping = TextWrapping.NoWrap;
            oneLine.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
            footer.Measure(new Size(double.PositiveInfinity, 20));
            double content = Math.Max(title.DesiredSize.Width, Math.Max(oneLine.DesiredSize.Width, footer.DesiredSize.Width));
            double width = Math.Clamp(Math.Ceiling(content) + 2 * TagStyle.TagPaddingX + 2, TagStyle.TagMinWidth, TagStyle.TagMaxWidth);

            bodyText.TextTrimming = TextTrimming.CharacterEllipsis;
            bodyText.MaxHeight = Math.Ceiling(bodyText.FontSize * bodyText.FontFamily.LineSpacing * TagStyle.BodyMaxLines) + 1;

            var stack = new StackPanel();
            stack.Children.Add(title);
            stack.Children.Add(bodyText);
            stack.Children.Add(footer);
            Bubble.Width = width;
            Bubble.Child = stack;
            Bubble.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
            BubbleSize = new Size(width, Math.Ceiling(Bubble.DesiredSize.Height - 2 * ShadowMargin));
        }

        private static SolidColorBrush Solid(Color c) { var b = new SolidColorBrush(c); b.Freeze(); return b; }

        private static TextBlock Text(string s, double size, FontWeight weight, Brush fg) => new()
        {
            Text = s, FontSize = size, FontWeight = weight, Foreground = fg, FontFamily = UiFont, TextWrapping = TextWrapping.Wrap,
        };

        private static void Pressable(Border b, Action onClick, string name)
        {
            b.Cursor = Cursors.Hand;
            b.Focusable = false;
            AutomationProperties.SetName(b, name);
            b.MouseEnter += (_, _) => b.Opacity = 0.88;
            b.MouseLeave += (_, _) => b.Opacity = 1;
            b.MouseLeftButtonDown += (_, e) => { b.Opacity = 0.7; b.CaptureMouse(); e.Handled = true; };
            b.MouseLeftButtonUp += (_, e) =>
            {
                var at = e.GetPosition(b);
                bool inside = at.X >= 0 && at.Y >= 0 && at.X <= b.ActualWidth && at.Y <= b.ActualHeight;
                b.Opacity = 1;
                b.ReleaseMouseCapture();
                e.Handled = true;
                if (inside) onClick();
            };
            b.LostMouseCapture += (_, _) => b.Opacity = 1;
        }
    }

    // ------------------------------------------------------------------ Win32

    [StructLayout(LayoutKind.Sequential)] private struct POINT { public int X, Y; }
    [StructLayout(LayoutKind.Sequential)] private struct RECT { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)]
    private struct MONITORINFO { public int cbSize; public RECT rcMonitor; public RECT rcWork; public uint dwFlags; }

    [DllImport("user32.dll")] private static extern IntPtr MonitorFromPoint(POINT pt, uint flags);
    [DllImport("user32.dll")] private static extern bool GetMonitorInfo(IntPtr monitor, ref MONITORINFO info);
    [DllImport("user32.dll")] private static extern uint GetDpiForSystem();
    [DllImport("user32.dll")] private static extern int GetWindowLong(IntPtr hwnd, int index);
    [DllImport("user32.dll")] private static extern int SetWindowLong(IntPtr hwnd, int index, int value);
}
