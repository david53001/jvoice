using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using JVoice.Core.Models;

namespace JVoice.App.UI;

/// Borderless, topmost, non-activating, click-through overlay pill.
/// Ports HUDWindow.swift (NSPanel borderless/nonactivating, bottom-center, 24px up).
public sealed class HudWindow : Window
{
    private readonly HudView _view = new();
    private IntPtr _hwnd;

    /// Unused since the HUD became text/affordance-free (the bars-only pill has no stop
    /// button — stop with the hotkey or the tray menu). Kept so existing wiring compiles
    /// and a stop affordance could be re-added without re-threading the callback.
    public Action? OnStop { get; set; }

    /// Dev/probe seam: when true the pill is positioned far off-screen instead of bottom-center,
    /// so a headless measurement (`--latency-probe`) can realize and animate the real layered
    /// window without anything appearing on the user's desktop. Never set by the app itself.
    internal bool Offscreen { get; init; }

    /// Live mic level (0..1) for the voice-activity bars. Wired by App to the coordinator.
    public Func<float>? InputLevelProvider
    {
        get => _view.InputLevelProvider;
        set => _view.InputLevelProvider = value;
    }

    public HudWindow()
    {
        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = System.Windows.Media.Brushes.Transparent;
        ResizeMode = ResizeMode.NoResize;
        ShowInTaskbar = false;
        Topmost = true;
        ShowActivated = false;
        SizeToContent = SizeToContent.WidthAndHeight;
        Content = _view;
        SourceInitialized += OnSourceInitialized;
        // Re-center whenever the realized size changes. On the FIRST show (and whenever the
        // pill grows/shrinks between states, e.g. the recording stop-button or a shorter
        // "Pasted") ActualWidth/Height are only valid after layout — so positioning solely
        // from Update() would run against a 0×0 size and leave the pill shoved to the right
        // and below the work area. SizeChanged fires during the arrange pass (before the
        // first paint), so the pill's first visible frame is already correctly centered.
        SizeChanged += (_, _) => PositionBottomCenter();
    }

    private bool _prewarmed;
    private bool _parkedOffscreen;
    private EventHandler? _prewarmFrame;

    /// Realize the layered window ONCE while the app is idle so the first hotkey press doesn't
    /// pay window/surface creation on the critical path: the pill is shown for a single frame
    /// parked far off-screen (never visible), then hidden again. Measured: a first show costs
    /// ~40-110 ms to the first rendered frame; a re-show of a realized window ~3 ms. (Creating
    /// only the HWND via EnsureHandle does NOT help — WPF still builds the render surface on
    /// the first real show, and that path measured slower, 95 ms.)
    public void Prewarm()
    {
        if (_prewarmed || IsVisible) return;
        _prewarmed = true;
        _parkedOffscreen = true;
        _view.Apply(HudState.Recording);
        UpdateLayout();
        PositionBottomCenter(); // parks off-screen while _parkedOffscreen
        ShowNoActivate();
        _prewarmFrame = (_, _) =>
        {
            CancelPrewarmFrame();
            Hide();
            _view.Apply(HudState.Idle);
        };
        System.Windows.Media.CompositionTarget.Rendering += _prewarmFrame;
    }

    /// Detach the pending prewarm hide (if any) and un-park the window. Called by Update() so a
    /// hotkey press that lands BEFORE the prewarm's first frame simply takes the realized window
    /// over instead of being hidden by it a frame later.
    private void CancelPrewarmFrame()
    {
        if (_prewarmFrame is not null)
        {
            System.Windows.Media.CompositionTarget.Rendering -= _prewarmFrame;
            _prewarmFrame = null;
        }
        _parkedOffscreen = false;
    }

    private void OnSourceInitialized(object? sender, EventArgs e)
    {
        _hwnd = new WindowInteropHelper(this).Handle;
        // WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW so it never steals foreground / no taskbar.
        int ex = GetWindowLong(_hwnd, GWL_EXSTYLE);
        ex |= WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW;
        SetWindowLong(_hwnd, GWL_EXSTYLE, ex);
        ApplyClickThrough(clickThrough: true);
    }

    /// Update to a new state (UI thread). Mirrors HUDWindow.update(state:).
    public void Update(HudState state)
    {
        CancelPrewarmFrame();
        _view.Apply(state);

        // Always click-through now: the bars-only HUD has no interactive affordances, so it
        // should never intercept a click (the old design dropped click-through while recording
        // only to make its stop button clickable).
        ApplyClickThrough(clickThrough: true);

        if (state.IsVisible)
        {
            // Lay out first so ActualWidth/Height are valid, then position.
            UpdateLayout();
            PositionBottomCenter();
            if (!IsVisible) ShowNoActivate();
        }
        else
        {
            Hide();
        }
    }

    private void ShowNoActivate()
    {
        // Show without activating (Show() would activate); set Visibility then enforce no-activate.
        Visibility = Visibility.Visible;
        ShowWindow(_hwnd, SW_SHOWNOACTIVATE);
    }

    private void PositionBottomCenter()
    {
        // Before the window is realized/laid out, ActualWidth/Height are 0 — positioning then
        // would center against a 0-size box (pill shoved right of center and hanging below the
        // work area). Skip until we have a real size; SizeChanged re-invokes us once we do.
        if (ActualWidth <= 0 || ActualHeight <= 0) return;

        if (Offscreen || _parkedOffscreen) { Left = -20000; Top = -20000; return; }

        var wa = SystemParameters.WorkArea; // DIPs, primary screen
        Left = wa.Left + (wa.Width - ActualWidth) / 2;
        // 24px above the bottom of the work area (Swift visibleFrame.minY + 24).
        Top = wa.Bottom - ActualHeight - 24;
    }

    private void ApplyClickThrough(bool clickThrough)
    {
        if (_hwnd == IntPtr.Zero) return;
        int ex = GetWindowLong(_hwnd, GWL_EXSTYLE);
        if (clickThrough) ex |= WS_EX_TRANSPARENT;
        else ex &= ~WS_EX_TRANSPARENT;
        SetWindowLong(_hwnd, GWL_EXSTYLE, ex);
    }

    // ---- Win32 ----
    private const int GWL_EXSTYLE = -20;
    private const int WS_EX_TRANSPARENT = 0x00000020;
    private const int WS_EX_TOOLWINDOW = 0x00000080;
    private const int WS_EX_NOACTIVATE = 0x08000000;
    private const int SW_SHOWNOACTIVATE = 4;

    [DllImport("user32.dll")] private static extern int GetWindowLong(IntPtr hwnd, int index);
    [DllImport("user32.dll")] private static extern int SetWindowLong(IntPtr hwnd, int index, int newLong);
    [DllImport("user32.dll")] private static extern bool ShowWindow(IntPtr hwnd, int cmd);
}
