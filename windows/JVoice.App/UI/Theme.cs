using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using JVoice.Core;
using JVoice.Core.Models;
using Microsoft.Win32;

namespace JVoice.App.UI;

/// The native look (parity rows 28/30, Mac `Theme.swift` + `UIOpacityStore`): System/Light/Dark and the
/// Opacity value, applied app-wide through DynamicResource brushes so a change repaints every open window
/// and a visible pill at once.
///
/// Surfaces are TINTS of the text colour over a material, never opaque fills (design-language README):
/// card 4 %, hover 8.5 %, input 6 %, hairline 8 %, row hover 7 %, small button 8/12/16 %. Windows'
/// material is Mica (DWMSBT_MAINWINDOW, Windows 11 22H2+) — the same choice as BetterScreenshot's Windows
/// port, so the two apps match; its backing is the window colour at
/// <see cref="UiOpacity.BackingAlpha"/>(Window), solid where Mica is unavailable. The pill keeps a dark
/// appearance in both themes (like the Mac's) and has no blur behind it (<c>Pill.Backing</c>).
public static class Theme
{
    public static AppAppearance Appearance { get; private set; } = AppAppearance.System;
    public static double Opacity { get; private set; } = UiOpacity.Default;
    public static bool IsDark { get; private set; } = true;

    /// Raised after the brushes changed (appearance, Windows app mode, accent or opacity).
    public static event Action? Changed;

    private static readonly List<WeakReference<Window>> Windows = new();
    private static bool _listening;

    /// Windows 11 22H2+ (build 22621) can put a system backdrop behind a window.
    public static bool MicaSupported { get; } = Environment.OSVersion.Version.Build >= 22621;

    /// Apply the stored values and start following Windows' app mode / accent colour.
    public static void Initialize(AppAppearance appearance, double opacity)
    {
        Appearance = appearance;
        Opacity = UiOpacity.Clamp(opacity);
        if (!_listening)
        {
            _listening = true;
            SystemEvents.UserPreferenceChanged += (_, e) =>
            {
                if (e.Category is UserPreferenceCategory.General or UserPreferenceCategory.Color
                    or UserPreferenceCategory.VisualStyle)
                    Application.Current?.Dispatcher.BeginInvoke(Refresh);
            };
        }
        Refresh();
    }

    public static void SetAppearance(AppAppearance appearance)
    {
        if (Appearance == appearance) return;
        Appearance = appearance;
        Refresh();
    }

    public static void SetOpacity(double value)
    {
        double v = UiOpacity.Clamp(value);
        if (Math.Abs(v - Opacity) < 1e-9) return;
        Opacity = v;
        ApplyBackings(Application.Current?.Resources);
        Changed?.Invoke();
    }

    /// Windows' "Choose your app mode": AppsUseLightTheme = 0 means dark. Missing = light (the default).
    public static bool SystemUsesLightTheme()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
            return key?.GetValue("AppsUseLightTheme") is not int v || v != 0;
        }
        catch { return true; }
    }

    /// The Windows accent colour (DWM AccentColor is 0xAABBGGRR), or Windows' default blue.
    private static Color AccentColor()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\DWM");
            if (key?.GetValue("AccentColor") is int abgr)
                return Color.FromRgb((byte)(abgr & 0xFF), (byte)((abgr >> 8) & 0xFF), (byte)((abgr >> 16) & 0xFF));
        }
        catch { }
        return Color.FromRgb(0x00, 0x67, 0xC0);
    }

    private static void Refresh()
    {
        IsDark = Appearance.IsDark(SystemUsesLightTheme());
        var res = Application.Current?.Resources;
        if (res is null) return;

        Color primary = IsDark ? Colors.White : Color.FromRgb(0, 0, 0);
        Brush(res, "Text.Primary", IsDark ? Colors.White : Color.FromArgb(0xE4, 0, 0, 0));
        Brush(res, "Text.Secondary", IsDark ? Color.FromArgb(0xC5, 0xFF, 0xFF, 0xFF) : Color.FromArgb(0x9E, 0, 0, 0));
        Brush(res, "Text.Tertiary", IsDark ? Color.FromArgb(0x87, 0xFF, 0xFF, 0xFF) : Color.FromArgb(0x72, 0, 0, 0));
        Tint(res, "Card.Fill", primary, 0.04);
        Tint(res, "Card.Hover", primary, 0.085);
        Tint(res, "Card.Pressed", primary, 0.12);
        Tint(res, "Card.Hairline", primary, 0.08);
        Tint(res, "Input.Fill", primary, 0.06);
        Tint(res, "Row.Hover", primary, 0.07);
        Tint(res, "Button.Fill", primary, 0.08);
        Tint(res, "Button.Hover", primary, 0.12);
        Tint(res, "Button.Pressed", primary, 0.16);
        Tint(res, "Control.Stroke", primary, IsDark ? 0.55 : 0.45);
        Brush(res, "Segment.Selected", IsDark ? Color.FromArgb(0x33, 0xFF, 0xFF, 0xFF) : Colors.White);
        Brush(res, "Popup.Fill", IsDark ? Color.FromRgb(0x2C, 0x2C, 0x2C) : Color.FromRgb(0xF9, 0xF9, 0xF9));
        Color accent = AccentColor();
        // Dark mode uses a lighter accent so it reads on dark surfaces (Fluent's AccentLight2 role).
        Brush(res, "Accent", IsDark ? Lighten(accent, 0.45) : accent);
        Brush(res, "Accent.Text", IsDark ? Color.FromRgb(0, 0, 0) : Colors.White);
        Brush(res, "Danger", IsDark ? Color.FromRgb(0xFF, 0x99, 0xA4) : Color.FromRgb(0xC4, 0x2B, 0x1C));
        Brush(res, "Success", IsDark ? Color.FromRgb(0x6C, 0xCB, 0x5F) : Color.FromRgb(0x0F, 0x7B, 0x0F));
        Brush(res, "Warning", IsDark ? Color.FromRgb(0xFC, 0xE1, 0x00) : Color.FromRgb(0x9D, 0x5D, 0x00));
        ApplyBackings(res);

        foreach (var w in LiveWindows()) ApplyTitleBar(w);
        Changed?.Invoke();
    }

    private static void ApplyBackings(ResourceDictionary? res)
    {
        if (res is null) return;
        Color window = IsDark ? Color.FromRgb(0x20, 0x20, 0x20) : Color.FromRgb(0xF3, 0xF3, 0xF3);
        double layer = MicaSupported ? UiOpacity.BackingAlpha(Opacity, UiOpacity.Surface.Window) : 1;
        Brush(res, "Window.Backing", Color.FromArgb(A(layer), window.R, window.G, window.B));
        // Popups/menus can't show Mica: always the solid window colour.
        Brush(res, "Window.Solid", window);
        var (r, g, b) = UiOpacity.PillColor;
        Brush(res, "Pill.Backing", Color.FromArgb(A(UiOpacity.BackingAlpha(Opacity, UiOpacity.Surface.Pill)), r, g, b));
    }

    /// Mica + rounded corners + a title bar that follows the theme; the window's background is the
    /// <c>Window.Backing</c> layer over the material. Call before the window is shown.
    public static void Attach(Window window)
    {
        lock (Windows) Windows.Add(new WeakReference<Window>(window));
        window.SetResourceReference(Window.BackgroundProperty, "Window.Backing");
        if (new WindowInteropHelper(window).Handle != IntPtr.Zero) ApplyBackdrop(window);
        else window.SourceInitialized += (_, _) => ApplyBackdrop(window);
    }

    private static void ApplyBackdrop(Window window)
    {
        var hwnd = new WindowInteropHelper(window).Handle;
        if (hwnd == IntPtr.Zero) return;
        try
        {
            int round = DwmwcpRound;
            _ = DwmSetWindowAttribute(hwnd, DwmwaWindowCornerPreference, ref round, sizeof(int));
            if (MicaSupported)
            {
                if (HwndSource.FromHwnd(hwnd) is { CompositionTarget: { } target }) target.BackgroundColor = Colors.Transparent;
                var margins = new Margins { Left = -1, Right = -1, Top = -1, Bottom = -1 };
                _ = DwmExtendFrameIntoClientArea(hwnd, ref margins);
                int backdrop = DwmsbtMainWindow;
                _ = DwmSetWindowAttribute(hwnd, DwmwaSystemBackdropType, ref backdrop, sizeof(int));
            }
        }
        catch (DllNotFoundException) { }
        catch (EntryPointNotFoundException) { }
        ApplyTitleBar(window);
    }

    private static void ApplyTitleBar(Window window)
    {
        var hwnd = new WindowInteropHelper(window).Handle;
        if (hwnd == IntPtr.Zero) return;
        try
        {
            int dark = IsDark ? 1 : 0;
            _ = DwmSetWindowAttribute(hwnd, DwmwaUseImmersiveDarkMode, ref dark, sizeof(int));
        }
        catch (DllNotFoundException) { }
        catch (EntryPointNotFoundException) { }
    }

    private static IEnumerable<Window> LiveWindows()
    {
        lock (Windows)
        {
            Windows.RemoveAll(r => !r.TryGetTarget(out _));
            return Windows.Select(r => r.TryGetTarget(out var w) ? w : null).OfType<Window>().ToList();
        }
    }

    private static Color Lighten(Color c, double t) => Color.FromRgb(
        (byte)(c.R + (255 - c.R) * t), (byte)(c.G + (255 - c.G) * t), (byte)(c.B + (255 - c.B) * t));

    private static void Tint(ResourceDictionary res, string key, Color c, double alpha)
        => Brush(res, key, Color.FromArgb(A(alpha), c.R, c.G, c.B));

    private static void Brush(ResourceDictionary res, string key, Color c)
    {
        var b = new SolidColorBrush(c);
        b.Freeze();
        res[key] = b;
    }

    private static byte A(double alpha) => (byte)Math.Round(Math.Clamp(alpha, 0, 1) * 255);

    private const int DwmwaUseImmersiveDarkMode = 20;
    private const int DwmwaWindowCornerPreference = 33;
    private const int DwmwaSystemBackdropType = 38;
    private const int DwmwcpRound = 2;
    private const int DwmsbtMainWindow = 2;

    [StructLayout(LayoutKind.Sequential)]
    private struct Margins { public int Left, Right, Top, Bottom; }

    [DllImport("dwmapi.dll")] private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);
    [DllImport("dwmapi.dll")] private static extern int DwmExtendFrameIntoClientArea(IntPtr hwnd, ref Margins margins);
}
