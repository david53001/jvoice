using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Shapes;
using JVoice.App.UI;
using JVoice.Core.Models;
using JVoice.Core.Tours;

namespace JVoice.App.Tours;

/// <summary>
/// Hidden dev renders for parity rows 31/32 (headless, like <c>--settings-render</c>; never touch tours.json or any
/// setting): <c>--welcome-render &lt;png&gt; [allset] [question] [light|dark]</c> draws the Welcome window's content, and
/// <c>--tour-render &lt;png&gt; [light|dark]</c> a contact sheet of tag bubbles (Explain, Try, last step, Done, the
/// Opacity readout) plus the recording pill with its concentric capsule outline.
/// </summary>
internal static class TourRenders
{
    public static void Welcome(string[] args, VoiceCoordinator coordinator)
    {
        var rest = After(args, "--welcome-render");
        Theme.Initialize(Appearance(rest, coordinator), coordinator.UiOpacity);
        var model = new WelcomeModel
        {
            IsPermissionsPage = !rest.Contains("allset", StringComparer.OrdinalIgnoreCase),
            PendingQuestion = rest.Contains("question", StringComparer.OrdinalIgnoreCase),
            ToggleShortcut = coordinator.Hotkey.Format(),
            UndoShortcut = coordinator.UndoHotkey?.Format(),
            MicrophoneAllowed = WelcomeModel.ReadMicrophoneAllowed(),
        };
        var view = new WelcomeView { DataContext = model };
        view.SetInfoButton(new InfoButton(TourId.Welcome, () => WelcomeWindow.Shortcuts(coordinator)));
        view.SetResourceReference(Control.BackgroundProperty, "Window.Solid");
        Save(view, PathArg(rest, "jvoice-welcome.png"), 2);
    }

    public static void Tags(string[] args)
    {
        var rest = After(args, "--tour-render");
        bool dark = !rest.Contains("light", StringComparer.OrdinalIgnoreCase);
        Theme.Initialize(dark ? AppAppearance.Dark : AppAppearance.Light, JVoice.Core.UiOpacity.Default);
        string R(string body) => TourText.Resolve(body, n => n == "toggleRecording" ? "Ctrl+Shift+Space" : TourText.UnboundShortcut);
        var w = TourCatalog.Welcome.Steps;
        var s = TourCatalog.Settings.Steps;
        var sheet = new WrapPanel { Width = 960, Margin = new Thickness(12) };
        sheet.SetResourceReference(Panel.BackgroundProperty, "Window.Solid");
        void Add(FrameworkElement e) { e.Margin = new Thickness(6); sheet.Children.Add(e); }
        Add(TagOverlay.PreviewBubble(w[1], R(w[1].Body), 1, 2, false, false, dark));
        Add(TagOverlay.PreviewBubble(w[2], R(w[2].Body), 2, 2, true, false, dark));
        Add(TagOverlay.PreviewBubble(w[2], R(w[2].Body), 2, 2, true, true, dark));
        Add(TagOverlay.PreviewBubble(s[8], R(s[8].Body) + " Watch: 37 % ↓", 9, 10, false, false, dark));
        Add(TagOverlay.PreviewBubble(s[9], R(s[9].Body), 10, 10, true, false, dark));
        Add(TagOverlay.PreviewBubble(TourCatalog.RecordingPill.Steps[0], TourText.Resolve(TourCatalog.RecordingPill.Steps[0].Body, _ => TourText.LongestShortcut), 1, 1, true, false, dark));
        Add(PillWithOutline(R(TourCatalog.RecordingPill.Steps[0].Body)));
        Save(sheet, PathArg(rest, "jvoice-tour.png"), 2);
    }

    /// <summary>The recording pill with the tour's outline (TagStyle.OutlineRadius around the capsule) and its tag above.</summary>
    private static FrameworkElement PillWithOutline(string body)
    {
        var hud = new HudView();
        hud.PrepareStaticCapture();
        hud.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
        hud.Arrange(new Rect(hud.DesiredSize));
        hud.UpdateLayout();
        var capsule = hud.Capsule;
        // Both corners through the visual tree, like the live overlay's PointToScreen: the HUD carries a HudScale
        // LayoutTransform, so ActualWidth/Height alone are the UNscaled size.
        var at = capsule.TranslatePoint(new Point(0, 0), hud);
        var end = capsule.TranslatePoint(new Point(capsule.ActualWidth, capsule.ActualHeight), hud);
        var box = new TagRect(at.X, at.Y, end.X - at.X, end.Y - at.Y).Inflate(TagStyle.BoxPadding);
        double radius = TagStyle.OutlineRadius(box, (end.Y - at.Y) / 2);
        var canvas = new Canvas { Width = hud.DesiredSize.Width, Height = hud.DesiredSize.Height, Background = Brushes.White };
        canvas.Children.Add(hud);
        double half = TagStyle.OutlineWidth / 2;
        var outline = new Rectangle
        {
            Width = box.Width + 2 * half, Height = box.Height + 2 * half, RadiusX = radius + half, RadiusY = radius + half,
            Stroke = new SolidColorBrush(Theme.AccentFor(true)), StrokeThickness = TagStyle.OutlineWidth,
        };
        Canvas.SetLeft(outline, box.X - half);
        Canvas.SetTop(outline, box.Y - half);
        canvas.Children.Add(outline);
        var stack = new StackPanel();
        stack.Children.Add(TagOverlay.PreviewBubble(TourCatalog.RecordingPill.Steps[0], body, 1, 1, true, false, true));
        stack.Children.Add(canvas);
        return stack;
    }

    private static AppAppearance Appearance(string[] rest, VoiceCoordinator c) =>
        rest.Contains("light", StringComparer.OrdinalIgnoreCase) ? AppAppearance.Light
        : rest.Contains("dark", StringComparer.OrdinalIgnoreCase) ? AppAppearance.Dark
        : c.Appearance;

    private static string[] After(string[] args, string flag)
    {
        int i = Array.FindIndex(args, a => string.Equals(a, flag, StringComparison.OrdinalIgnoreCase));
        return i >= 0 ? args.Skip(i + 1).ToArray() : Array.Empty<string>();
    }

    private static string PathArg(string[] rest, string fallback) =>
        rest.FirstOrDefault(a => a.EndsWith(".png", StringComparison.OrdinalIgnoreCase)) ?? System.IO.Path.Combine(System.IO.Path.GetTempPath(), fallback);

    private static void Save(FrameworkElement view, string path, double scale)
    {
        view.Measure(new Size(double.IsNaN(view.Width) ? double.PositiveInfinity : view.Width, double.PositiveInfinity));
        view.Arrange(new Rect(view.DesiredSize));
        view.UpdateLayout();
        view.Measure(new Size(double.IsNaN(view.Width) ? double.PositiveInfinity : view.Width, double.PositiveInfinity));
        var size = view.DesiredSize;
        view.Arrange(new Rect(size));
        view.UpdateLayout();
        var rtb = new RenderTargetBitmap((int)Math.Ceiling(size.Width * scale), (int)Math.Ceiling(size.Height * scale),
            96 * scale, 96 * scale, PixelFormats.Pbgra32);
        rtb.Render(view);
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(rtb));
        using var fs = File.Create(path);
        encoder.Save(fs);
    }
}
