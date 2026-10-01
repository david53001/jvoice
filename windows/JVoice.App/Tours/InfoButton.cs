using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using JVoice.Core.Tours;

namespace JVoice.App.Tours;

/// <summary>
/// The ⓘ on Settings and the Welcome window (parity §10.6; Mac <c>InfoButton</c>): a borderless info glyph whose menu
/// has <b>Replay Tour</b> (this window's tour from step 1, for every user), <b>Show Me ▸</b> (one item per step title —
/// explains just that part) and <b>Keyboard Shortcuts</b> (the live chords). Colours are the theme's DynamicResources.
/// </summary>
public sealed class InfoButton : Border
{
    private static readonly FontFamily IconFont = new("Segoe Fluent Icons, Segoe MDL2 Assets");
    private static readonly FontFamily UiFont = new("Segoe UI Variable Text, Segoe UI");

    private readonly TourId _tour;
    private readonly Func<IReadOnlyList<(string Keys, string Action)>> _shortcuts;
    private readonly Popup _shortcutsPopup;

    public InfoButton(TourId tour, Func<IReadOnlyList<(string Keys, string Action)>> shortcuts)
    {
        _tour = tour;
        _shortcuts = shortcuts;
        Width = 28;
        Height = 28;
        CornerRadius = new CornerRadius(6);
        Background = Brushes.Transparent;
        Cursor = Cursors.Hand;
        Focusable = false;
        ToolTip = "Tour & Keyboard Shortcuts";
        AutomationProperties.SetName(this, "Tour & Keyboard Shortcuts");
        var glyph = new TextBlock
        {
            Text = "", FontFamily = IconFont, FontSize = 15,
            HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center,
        };
        glyph.SetResourceReference(TextBlock.ForegroundProperty, "Text.Secondary");
        Child = glyph;
        _shortcutsPopup = new Popup
        {
            PlacementTarget = this, Placement = PlacementMode.Bottom, VerticalOffset = 4, StaysOpen = false,
            AllowsTransparency = true, PopupAnimation = PopupAnimation.Fade,
        };
        MouseEnter += (_, _) => SetResourceReference(BackgroundProperty, "Button.Hover");
        MouseLeave += (_, _) => Background = Brushes.Transparent;
        MouseLeftButtonUp += (_, e) => { e.Handled = true; ShowMenu(); };
    }

    private void ShowMenu()
    {
        var menu = new ContextMenu { PlacementTarget = this, Placement = PlacementMode.Bottom, VerticalOffset = 4 };
        var replay = new MenuItem { Header = "Replay Tour", Icon = Icon("") };
        replay.Click += (_, _) => TourEvents.Replay(_tour, Window.GetWindow(this));
        menu.Items.Add(replay);

        var showMe = new MenuItem { Header = "Show Me", Icon = Icon("") };
        var steps = TourCatalog.Get(_tour).Steps;
        for (int i = 0; i < steps.Count; i++)
        {
            int step = i;
            var item = new MenuItem { Header = steps[i].Title };
            item.Click += (_, _) => TourEvents.ReplayPart(_tour, step, Window.GetWindow(this));
            showMe.Items.Add(item);
        }
        menu.Items.Add(showMe);

        if (_shortcuts().Count > 0)
        {
            var keys = new MenuItem { Header = "Keyboard Shortcuts", Icon = Icon("") };
            keys.Click += (_, _) => ShowShortcuts();
            menu.Items.Add(keys);
        }
        menu.IsOpen = true;
    }

    private static TextBlock Icon(string glyph) => new() { Text = glyph, FontFamily = IconFont, FontSize = 13 };

    private void ShowShortcuts()
    {
        var grid = new Grid { Margin = new Thickness(14, 12, 14, 12) };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(24) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        var title = new TextBlock { Text = "Keyboard Shortcuts", FontFamily = UiFont, FontSize = 13, FontWeight = FontWeights.SemiBold, Margin = new Thickness(0, 0, 0, 10) };
        title.SetResourceReference(TextBlock.ForegroundProperty, "Text.Primary");
        Grid.SetColumnSpan(title, 3);
        grid.Children.Add(title);
        int r = 1;
        foreach (var (keys, action) in _shortcuts())
        {
            grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            var margin = new Thickness(0, r > 1 ? 6 : 0, 0, 0);
            var a = new TextBlock { Text = action, FontFamily = UiFont, FontSize = 12, Margin = margin };
            a.SetResourceReference(TextBlock.ForegroundProperty, "Text.Secondary");
            var k = new TextBlock { Text = keys, FontFamily = UiFont, FontSize = 12, FontWeight = FontWeights.Medium, HorizontalAlignment = HorizontalAlignment.Right, Margin = margin };
            k.SetResourceReference(TextBlock.ForegroundProperty, "Text.Primary");
            Grid.SetRow(a, r);
            Grid.SetRow(k, r);
            Grid.SetColumn(k, 2);
            grid.Children.Add(a);
            grid.Children.Add(k);
            r++;
        }
        var panel = new Border
        {
            BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(8), Child = grid, Margin = new Thickness(0, 0, 8, 8),
            Effect = new System.Windows.Media.Effects.DropShadowEffect { BlurRadius = 10, ShadowDepth = 2, Direction = 270, Opacity = 0.3 },
        };
        panel.SetResourceReference(BackgroundProperty, "Popup.Fill");
        panel.SetResourceReference(BorderBrushProperty, "Card.Hairline");
        _shortcutsPopup.Child = panel;
        _shortcutsPopup.IsOpen = true;
    }
}
