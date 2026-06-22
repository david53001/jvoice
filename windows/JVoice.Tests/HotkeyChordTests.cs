using JVoice.Core.Models;
using Xunit;

namespace JVoice.Tests;

public class HotkeyChordTests
{
    [Fact]
    public void Default_IsCtrlShiftSpace()
    {
        var d = HotkeyChord.Default;
        Assert.True(d.Modifiers.HasFlag(HotkeyModifiers.Control));
        Assert.True(d.Modifiers.HasFlag(HotkeyModifiers.Shift));
        Assert.False(d.Modifiers.HasFlag(HotkeyModifiers.Alt));
        Assert.Equal(0x20, d.VirtualKey); // VK_SPACE
        Assert.Equal("Ctrl+Shift+Space", d.Format());
    }

    [Theory]
    [InlineData("Ctrl+Shift+Space")]
    [InlineData("ctrl+shift+space")]   // case-insensitive
    [InlineData("Control+Shift+Space")]// "Control" alias for "Ctrl"
    public void Parse_RoundTrips_Default(string text)
    {
        Assert.True(HotkeyChord.TryParse(text, out var c));
        Assert.Equal("Ctrl+Shift+Space", c.Format());
    }

    [Fact]
    public void Parse_SingleModifierLetter()
    {
        Assert.True(HotkeyChord.TryParse("Alt+A", out var c));
        Assert.True(c.Modifiers.HasFlag(HotkeyModifiers.Alt));
        Assert.Equal((int)'A', c.VirtualKey);
        Assert.Equal("Alt+A", c.Format());
    }

    [Fact]
    public void Parse_FunctionKey()
    {
        Assert.True(HotkeyChord.TryParse("Ctrl+F5", out var c));
        Assert.Equal(0x74, c.VirtualKey); // VK_F5
        Assert.Equal("Ctrl+F5", c.Format());
    }

    [Fact]
    public void Parse_WinModifier()
    {
        Assert.True(HotkeyChord.TryParse("Win+Space", out var c));
        Assert.True(c.Modifiers.HasFlag(HotkeyModifiers.Win));
        Assert.Equal("Win+Space", c.Format());
    }

    [Theory]
    [InlineData("")]
    [InlineData("Ctrl+")]            // no key
    [InlineData("Ctrl+Shift")]       // modifiers only, no main key
    [InlineData("Bogus+Space")]      // unknown modifier
    [InlineData("Ctrl+NotAKey")]     // unknown key
    public void Parse_Invalid_ReturnsFalse(string text)
        => Assert.False(HotkeyChord.TryParse(text, out _));

    [Fact]
    public void Format_OrdersModifiers_CtrlAltShiftWin()
    {
        Assert.True(HotkeyChord.TryParse("Shift+Ctrl+A", out var c));
        Assert.Equal("Ctrl+Shift+A", c.Format());
    }
}
