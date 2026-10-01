using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using JVoice.App.UI;
using JVoice.Core.Tours;

namespace JVoice.App.Tours;

/// <summary>What the tag overlay needs from a host beyond <see cref="ITourHost"/>: where things are on screen.</summary>
public interface IOverlayHost : ITourHost
{
    /// <summary>The window the tag windows are owned by (moves/minimises with it); null for the tray icon.</summary>
    Window? Owner { get; }
    /// <summary>What the dim covers, in screen DIPs (null = nothing to dim, the tray).</summary>
    Rect? DimFrame { get; }
    /// <summary>The dim's corner radius.</summary>
    double DimRadius { get; }
    /// <summary>The tag also keeps clear of this (a small borderless host: the pill) — null = only the box.</summary>
    Rect? KeepOut { get; }
    /// <summary>The host's light/dark (the tag takes it; the pill is always dark).</summary>
    bool IsDark { get; }
    /// <summary>The host wants Enter/Esc for itself right now (Settings while a shortcut recorder listens).</summary>
    bool ClaimsKeys { get; }
    /// <summary>A control's bounds in screen DIPs, cut to its scroll viewport; null when it isn't on screen.</summary>
    Rect? AnchorRect(string anchor);
    /// <summary>The control's declared corner radius in screen DIPs (the capsule pill); null = the default box.</summary>
    double? AnchorRadius(string anchor);
    /// <summary>The control's parent is a wide bar (tag goes above/below first).</summary>
    bool ParentIsBar(string anchor);
    /// <summary>The scroll viewer the control lives in (the overlay follows its ScrollChanged in the same frame).</summary>
    ScrollViewer? ScrollerFor(string anchor);
}

/// <summary>
/// A WPF window as a tour host: anchors are <c>AutomationProperties.AutomationId</c>s found in its visual tree,
/// measured in screen DIPs. One instance per window (<see cref="For"/>) so the coordinator can compare hosts.
/// </summary>
public class WindowTourHost : IOverlayHost
{
    private static readonly ConditionalWeakTable<Window, WindowTourHost> Hosts = new();

    public static WindowTourHost For(Window window) => Hosts.GetValue(window, w => w is HudWindow hud ? new PillTourHost(hud) : new WindowTourHost(w));

    public Window Window { get; }
    /// <summary>Set by the window (Settings: true while a shortcut recorder is capturing).</summary>
    public Func<bool>? KeysClaimed { get; set; }

    protected WindowTourHost(Window window)
    {
        Window = window;
        window.Closed += (_, _) => TourEvents.HostClosed(this);
    }

    public virtual bool IsVisible => Window.IsVisible && Window.WindowState != WindowState.Minimized;
    public bool IsActive => Window.IsActive;
    public bool HasAnchor(string anchor) => IsVisible && Find(anchor) is not null;
    public void BringIntoView(string anchor) => Find(anchor)?.BringIntoView();

    public Window? Owner => Window;
    public virtual Rect? DimFrame => WindowRect(Window);
    public virtual double DimRadius => Environment.OSVersion.Version.Build >= 22000 ? 8 : 0;
    public virtual Rect? KeepOut => null;
    public virtual bool IsDark => Theme.IsDark;
    public bool ClaimsKeys => KeysClaimed?.Invoke() ?? false;
    public virtual double? AnchorRadius(string anchor) => null;

    public Rect? AnchorRect(string anchor)
    {
        if (Find(anchor) is not { } element || ScreenRect(element) is not { } rect) return null;
        // Cut to the scroll viewport: a card scrolled half out of view is outlined only where it shows.
        if (ScrollerFor(anchor) is { } sv && ScreenRect(sv) is { } port)
        {
            rect.Intersect(port);
            if (rect.IsEmpty || rect.Width < 1 || rect.Height < 1) return null;
        }
        return rect;
    }

    public bool ParentIsBar(string anchor) =>
        Find(anchor) is { } e && VisualTreeHelper.GetParent(e) is FrameworkElement p && p.ActualHeight > 0 && p.ActualWidth >= 3 * p.ActualHeight;

    public ScrollViewer? ScrollerFor(string anchor)
    {
        DependencyObject? node = Find(anchor);
        while (node is not null)
        {
            node = VisualTreeHelper.GetParent(node);
            if (node is ScrollViewer sv) return sv;
        }
        return null;
    }

    public FrameworkElement? Find(string anchor)
    {
        if (!IsVisible) return null;
        return Find(Window, anchor);
    }

    private static FrameworkElement? Find(DependencyObject node, string id)
    {
        if (node is FrameworkElement fe)
        {
            if (!fe.IsVisible) return null; // a hidden parent hides the whole subtree
            if (AutomationProperties.GetAutomationId(fe) == id && fe.ActualWidth > 0 && fe.ActualHeight > 0) return fe;
        }
        int n = VisualTreeHelper.GetChildrenCount(node);
        for (int i = 0; i < n; i++)
            if (Find(VisualTreeHelper.GetChild(node, i), id) is { } hit) return hit;
        return null;
    }

    /// <summary>The element's bounds in screen DIPs (null when it isn't connected to a window).</summary>
    public static Rect? ScreenRect(FrameworkElement element)
    {
        if (PresentationSource.FromVisual(element) is not { CompositionTarget: { } target }) return null;
        try
        {
            var a = element.PointToScreen(new Point(0, 0));
            var b = element.PointToScreen(new Point(element.ActualWidth, element.ActualHeight));
            var m = target.TransformFromDevice;
            return new Rect(m.Transform(a), m.Transform(b));
        }
        catch (InvalidOperationException) { return null; }
    }

    /// <summary>The window's visible frame in screen DIPs (DWM extended frame: no invisible resize borders).</summary>
    public static Rect? WindowRect(Window window)
    {
        if (!window.IsVisible || PresentationSource.FromVisual(window) is not { CompositionTarget: { } target }) return null;
        var hwnd = new WindowInteropHelper(window).Handle;
        if (hwnd == IntPtr.Zero) return null;
        if (DwmGetWindowAttribute(hwnd, 9 /* DWMWA_EXTENDED_FRAME_BOUNDS */, out var r, Marshal.SizeOf<RECT>()) != 0
            && !GetWindowRect(hwnd, out r)) return null;
        var m = target.TransformFromDevice;
        return new Rect(m.Transform(new Point(r.Left, r.Top)), m.Transform(new Point(r.Right, r.Bottom)));
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct RECT { public int Left, Top, Right, Bottom; }

    [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr hwnd, out RECT rect);
    [DllImport("dwmapi.dll")] private static extern int DwmGetWindowAttribute(IntPtr hwnd, int attribute, out RECT value, int size);
}

/// <summary>
/// The recording pill as a host ("host shaping", parity §10.5): the dim covers only the capsule — not the transparent
/// shadow margin or the morph room — the tag keeps clear of the capsule, and <c>pill.controls</c> declares the
/// capsule's radius (28 × HudScale) so the outline is a concentric capsule.
/// </summary>
public sealed class PillTourHost : WindowTourHost
{
    private readonly HudWindow _hud;

    public PillTourHost(HudWindow hud) : base(hud) => _hud = hud;

    private Rect? Capsule => _hud.CapsuleElement is { } c ? ScreenRect(c) : null;

    public override bool IsVisible => _hud.IsVisible && _hud.IsShowingPill;
    public override Rect? DimFrame => Capsule;
    public override double DimRadius => Capsule is { } c ? c.Height / 2 : 0;
    public override Rect? KeepOut => Capsule;
    public override bool IsDark => true;

    public override double? AnchorRadius(string anchor) =>
        anchor == "pill.controls" && Capsule is { } c ? c.Height / 2 : null;
}

/// <summary>
/// The tray icon as a host for the Welcome tour's first step (<c>menuBar.icon</c>). There is no window to outline:
/// <c>Shell_NotifyIconGetRect</c> gives the icon's rect while it's in the taskbar's notification area; hidden in the
/// overflow flyout (or anything else failing) it counts as off screen, so the step is skipped like the Mac's.
/// </summary>
public sealed class TrayTourHost : IOverlayHost
{
    private readonly Func<(IntPtr Hwnd, Guid Id)?> _identity;

    public TrayTourHost(Func<(IntPtr Hwnd, Guid Id)?> identity) => _identity = identity;

    public bool IsVisible => IconRect() is not null;
    public bool IsActive => false;
    public bool HasAnchor(string anchor) => anchor == TourCatalog.TrayIconAnchor && IsVisible;
    public void BringIntoView(string anchor) { }
    public Window? Owner => null;
    public Rect? DimFrame => null;
    public double DimRadius => 0;
    public Rect? KeepOut => null;
    public bool IsDark => Theme.IsDark;
    public bool ClaimsKeys => false;
    public Rect? AnchorRect(string anchor) => anchor == TourCatalog.TrayIconAnchor ? IconRect() : null;
    public double? AnchorRadius(string anchor) => null;
    public bool ParentIsBar(string anchor) => true; // the taskbar: above/below first
    public ScrollViewer? ScrollerFor(string anchor) => null;

    /// <summary>The icon's rect in DIPs (system DPI — the taskbar's notification area is on the primary display).</summary>
    private Rect? IconRect()
    {
        if (_identity() is not { } id || id.Hwnd == IntPtr.Zero) return null;
        try
        {
            var nii = new NOTIFYICONIDENTIFIER { cbSize = (uint)Marshal.SizeOf<NOTIFYICONIDENTIFIER>(), hWnd = id.Hwnd, guidItem = id.Id };
            if (Shell_NotifyIconGetRect(ref nii, out var r) != 0) return null;
            if (r.Right - r.Left <= 0 || r.Bottom - r.Top <= 0) return null;
            double scale = GetDpiForSystem() / 96.0;
            return new Rect(r.Left / scale, r.Top / scale, (r.Right - r.Left) / scale, (r.Bottom - r.Top) / scale);
        }
        catch (Exception ex) when (ex is DllNotFoundException or EntryPointNotFoundException) { return null; }
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct NOTIFYICONIDENTIFIER { public uint cbSize; public IntPtr hWnd; public uint uID; public Guid guidItem; }

    [StructLayout(LayoutKind.Sequential)]
    private struct RECT { public int Left, Top, Right, Bottom; }

    [DllImport("shell32.dll")] private static extern int Shell_NotifyIconGetRect(ref NOTIFYICONIDENTIFIER identifier, out RECT iconLocation);
    [DllImport("user32.dll")] private static extern uint GetDpiForSystem();
}
