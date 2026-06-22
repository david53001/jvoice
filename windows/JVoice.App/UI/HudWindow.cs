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

    public Action? OnStop { get; set; }

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
        _view.Apply(state, OnStop);

        // Click-through except while recording (matches ignoresMouseEvents = state != .recording).
        ApplyClickThrough(clickThrough: state.Kind != HudStateKind.Recording);

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
