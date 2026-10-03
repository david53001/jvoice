using JVoice.Core;
using JVoice.Core.Models;
using Xunit;
using static JVoice.Core.UiOpacity;

namespace JVoice.Tests;

/// The Opacity mapping (parity row 30) and the appearance keys (row 28).
public class UiOpacityTests
{
    [Theory]
    [InlineData(0.0, 0.0)]
    [InlineData(0.25, 0.175)]       // the spec's own example
    [InlineData(0.5, 0.35)]
    [InlineData(0.75, 0.675)]
    [InlineData(1.0, 1.0)]
    public void Window_FollowsTheMacAnchors(double value, double alpha)
        => Assert.Equal(alpha, BackingAlpha(value, Surface.Window), 6);

    [Theory]
    [InlineData(0.0, 0.90)]
    [InlineData(0.5, 0.98)]
    [InlineData(0.75, 0.99)]
    [InlineData(1.0, 1.0)]
    public void Pill_UsesTheWindowsCalibratedAnchors(double value, double alpha)
        => Assert.Equal(alpha, BackingAlpha(value, Surface.Pill), 6);

    [Fact]
    public void OutOfRangeAndNonFiniteValuesAreClamped()
    {
        Assert.Equal(BackingAlpha(0, Surface.Window), BackingAlpha(-1, Surface.Window));
        Assert.Equal(BackingAlpha(1, Surface.Pill), BackingAlpha(7, Surface.Pill));
        Assert.Equal(BackingAlpha(0.5, Surface.Pill), BackingAlpha(double.NaN, Surface.Pill));
        Assert.Equal(Default, Clamp(double.PositiveInfinity));
    }

    [Fact]
    public void Pill_PrimaryTextMeetsTheContractOverAWhitePage()
    {
        Assert.True(PillTextContrast(0) >= 3.0, $"at 0: {PillTextContrast(0):0.00}");
        Assert.True(PillTextContrast(0.5) >= 4.5, $"at default: {PillTextContrast(0.5):0.00}");
        Assert.True(PillTextContrast(1) >= 15, $"opaque: {PillTextContrast(1):0.00}");
    }

    [Fact]
    public void Pill_MacAnchorsWouldFailWithoutBlur()
    {
        // Why the Windows pill anchors are raised: the Mac's 0.45 floor, with no blur behind it.
        double a = 0.45, page = 255;
        double bg = a * PillColor.R + (1 - a) * page;
        Assert.True(Contrast(Luminance(255, 255, 255), Luminance(bg, bg, bg)) < 3.0);
    }

    [Fact]
    public void Pill_OverABlackPageIsAlwaysReadable()
        => Assert.True(PillTextContrast(0, page: 0) >= 15);

    [Theory]
    [InlineData(AppAppearance.System, true, false)]
    [InlineData(AppAppearance.System, false, true)]
    [InlineData(AppAppearance.Light, false, false)]
    [InlineData(AppAppearance.Dark, true, true)]
    public void Appearance_ResolvesAgainstWindowsAppMode(AppAppearance a, bool systemLight, bool dark)
        => Assert.Equal(dark, a.IsDark(systemLight));

    [Fact]
    public void Settings_DefaultToSystemAndHalfOpacity()
    {
        Assert.Equal(AppAppearance.System, SettingsState.Default.Appearance);
        Assert.Equal(0.5, SettingsState.Default.UiOpacity);
    }

    [Fact]
    public void Settings_AppearanceAndOpacityRoundTrip()
    {
        foreach (var a in new[] { AppAppearance.System, AppAppearance.Light, AppAppearance.Dark })
        {
            var s = SettingsState.Default with { Appearance = a, UiOpacity = 0.2 };
            var back = SettingsStateJson.Deserialize(SettingsStateJson.Serialize(s));
            Assert.Equal(a, back.Appearance);
            Assert.Equal(0.2, back.UiOpacity, 6);
        }
    }

    [Theory]
    [InlineData("""{"schemaVersion":6}""", AppAppearance.System, 0.5)]
    [InlineData("""{"schemaVersion":6,"appearance":"DARK","uiOpacity":0.9}""", AppAppearance.Dark, 0.9)]
    [InlineData("""{"schemaVersion":6,"appearance":"sepia","uiOpacity":"x"}""", AppAppearance.System, 0.5)]
    [InlineData("""{"schemaVersion":6,"uiOpacity":4}""", AppAppearance.System, 1.0)]
    public void Settings_ParseLeniently(string json, AppAppearance a, double opacity)
    {
        var s = SettingsStateJson.Deserialize(json);
        Assert.Equal(a, s.Appearance);
        Assert.Equal(opacity, s.UiOpacity, 6);
        Assert.Equal(SettingsState.CurrentSchemaVersion, s.SchemaVersion);
    }
}
