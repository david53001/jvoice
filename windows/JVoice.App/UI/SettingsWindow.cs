using System.Windows;
using System.Windows.Documents;
using JVoice.App.Platform;

namespace JVoice.App.UI;

/// Real focusable app window hosting SettingsView. Ports SettingsWindow.swift
/// (titled "Settings", centered, hidden — not destroyed — on close).
public sealed class SettingsWindow : Window
{
    private readonly SettingsView _view = new();

    public SettingsWindow(VoiceCoordinator coordinator)
    {
        Title = "Settings";
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        // RESIZABLE (WINDOWS-HANDOFF §9.1, Mac bf23aa9…): drag any edge/corner; double-click the title bar
        // or Maximize fills the work area, and the same again restores the previous size — the native
        // Win32 behaviour, so nothing may get in its way: NO SizeToContent (it would snap the window back
        // to the content after every drag) and NO MaxHeight/MaxWidth (they cap a maximized window; the old
        // §7 #33 "MaxHeight = work area − 16" guard is replaced by sizing the first open to the work area
        // below — the title-bar X can still never start off-screen). The cards reflow live while dragging
        // (MasonryPanel) and the body scrolls when the window is shorter than the content.
        SizeToContent = SizeToContent.Manual;
        ResizeMode = ResizeMode.CanResize;
        MinWidth = MinimumSize.Width;
        MinHeight = MinimumSize.Height;
        ShowInTaskbar = true; // a real app window while open
        // The native look: Mica behind a Window.Backing layer (Opacity), title bar follows the theme.
        Theme.Attach(this);
        SetResourceReference(TextElement.ForegroundProperty, "Text.Primary");
        _view.DataContext = coordinator;
        Content = _view;
        // Measured with the real data bound, so the first open fits the actual cards.
        var designed = DesignedSize(_view, SystemParameters.WorkArea.Size);
        Width = designed.Width;
        Height = designed.Height;
        // The tour tag's Enter/Esc go to a shortcut recorder while it listens ("claims keys").
        JVoice.App.Tours.WindowTourHost.For(this).KeysClaimed = () => _view.IsCapturingShortcut;
        // Don't destroy on close — hide so a re-open is instant and state persists.
        Closing += (s, e) => { e.Cancel = true; Hide(); };
    }

    public void ShowOrActivate()
    {
        // Parity row 34: opening from hidden centres it on the monitor with the mouse pointer, placed BEFORE it
        // shows (no flash on the old monitor). Already open → just brought forward.
        // A maximized window stays maximized (and where it is) across hide/show — only a minimized one is
        // brought back; the user's own size is kept too (the window is hidden, never destroyed).
        if (!IsVisible && WindowState != WindowState.Maximized) ActiveScreen.CenterBeforeShow(this, OuterSizeEstimate(this, _view));
        Show();
        if (WindowState == WindowState.Minimized) WindowState = WindowState.Normal;
        Activate();
        Topmost = true; Topmost = false; // bring to front then release topmost
        Focus();
    }

    /// <summary>The smallest window: two columns of cards at today's card width (≈ 300 DIP each) plus the
    /// margins and frame, and enough height for the header and a card (Mac minimum 700 × 420 pt).</summary>
    public static readonly Size MinimumSize = new(700, 420);

    /// <summary>The width the window opens at: three columns (the layout every card was designed for
    /// since HANDOFF §7 #33).</summary>
    public const double DesignedWidth = 1080;

    /// <summary>The first-open size: <see cref="DesignedWidth"/> (never wider than the work area) and the
    /// content's natural height at that width, capped to the work area minus a small margin so the
    /// title bar and its X always start on-screen (the old §7 #33 guard, now a starting size, not a cap).</summary>
    internal static Size DesignedSize(FrameworkElement content, Size workArea)
    {
        var frame = SystemParameters.WindowResizeBorderThickness;
        double chromeW = frame.Left + frame.Right;
        double chromeH = SystemParameters.WindowCaptionHeight + frame.Top + frame.Bottom;
        double width = Math.Min(DesignedWidth, workArea.Width - 16);
        content.Measure(new Size(Math.Max(0, width - chromeW), double.PositiveInfinity));
        double height = Math.Min(content.DesiredSize.Height + chromeH, workArea.Height - 16);
        return new Size(Math.Max(MinimumSize.Width, width), Math.Max(MinimumSize.Height, height));
    }

    /// <summary>A window's outer size in DIPs before it shows: its last size once it has been shown, else
    /// the size it was given (Width/Height are set in the constructor).</summary>
    internal static Size OuterSizeEstimate(Window window, FrameworkElement content)
    {
        if (window.ActualWidth > 0 && window.ActualHeight > 0) return new Size(window.ActualWidth, window.ActualHeight);
        if (double.IsFinite(window.Width) && double.IsFinite(window.Height)) return new Size(window.Width, window.Height);
        // A SizeToContent window (Welcome): its content's desired size plus the title bar and frame.
        content.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
        var frame = SystemParameters.WindowResizeBorderThickness;
        double h = content.DesiredSize.Height + SystemParameters.WindowCaptionHeight + frame.Top + frame.Bottom;
        if (double.IsFinite(window.MaxHeight)) h = Math.Min(h, window.MaxHeight);
        return new Size(content.DesiredSize.Width + frame.Left + frame.Right, h);
    }
}
