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

    // ===== Alias canonicalization, digit/function keys, ordering =====

    [Theory]
    [InlineData("Ctrl+Escape", "Ctrl+Esc")]
    [InlineData("Ctrl+Return", "Ctrl+Enter")]
    [InlineData("Ctrl+Del", "Ctrl+Delete")]
    [InlineData("Ctrl+Ins", "Ctrl+Insert")]
    [InlineData("Ctrl+PgUp", "Ctrl+PageUp")]
    [InlineData("Ctrl+PgDn", "Ctrl+PageDown")]
    [InlineData("Cmd+Space", "Win+Space")]
    [InlineData("Windows+Space", "Win+Space")]
    [InlineData("Ctrl+5", "Ctrl+5")]
    [InlineData("Ctrl+f5", "Ctrl+F5")]
    [InlineData("Win+Alt+Shift+Ctrl+a", "Ctrl+Alt+Shift+Win+A")]   // ordering + case canonicalization
    [InlineData("  Ctrl + Shift + Space  ", "Ctrl+Shift+Space")]   // whitespace trimming
    public void Parse_Canonicalizes(string input, string expectedFormat)
    {
        Assert.True(HotkeyChord.TryParse(input, out var c));
        Assert.Equal(expectedFormat, c.Format());
    }

    [Theory]
    [InlineData("F1", 0x70)]
    [InlineData("F12", 0x7B)]
    [InlineData("F24", 0x87)]
    public void Parse_FunctionKey_VkBoundaries(string key, int vk)
    {
        Assert.True(HotkeyChord.TryParse("Ctrl+" + key, out var c));
        Assert.Equal(vk, c.VirtualKey);
        Assert.Equal("Ctrl+" + key.ToUpperInvariant(), c.Format());
    }

    [Theory]
    [InlineData("Ctrl+F0")]   // below F1
    [InlineData("Ctrl+F25")]  // above F24
    public void Parse_OutOfRangeFunctionKeys_ReturnFalse(string text)
        => Assert.False(HotkeyChord.TryParse(text, out _));

    [Fact]
    public void Parse_DigitKey()
    {
        Assert.True(HotkeyChord.TryParse("Ctrl+5", out var c));
        Assert.Equal((int)'5', c.VirtualKey); // VK_5 == '5'
    }

    [Fact]
    public void Parse_NoModifiers_IsValid()
    {
        Assert.True(HotkeyChord.TryParse("Space", out var c));
        Assert.Equal(HotkeyModifiers.None, c.Modifiers);
        Assert.Equal(0x20, c.VirtualKey);
        Assert.Equal("Space", c.Format());
    }

    [Theory]
    [InlineData("A+B")]
    [InlineData("Ctrl+A+B")]
    public void Parse_TwoMainKeys_ReturnsFalse(string text)
        => Assert.False(HotkeyChord.TryParse(text, out _));

    // Round-trip identity: parsing then re-parsing the formatted string yields an equal chord.
    [Fact]
    public void Fuzz_RoundTripIdentity()
    {
        var rng = new Random(20260623);
        string[] modAliases = { "Ctrl", "control", "Alt", "shift", "Win", "windows", "cmd" };
        string[] keys =
        {
            "A", "z", "5", "0", "Space", "enter", "Return", "Tab", "Esc", "escape",
            "Delete", "del", "Home", "End", "Up", "Down", "Left", "Right",
            "F1", "f12", "F24", "PageUp", "pgdn", "Insert",
        };
        for (int i = 0; i < 400; i++)
        {
            int nMods = rng.Next(0, 4);
            var parts = new List<string>();
            for (int m = 0; m < nMods; m++) parts.Add(modAliases[rng.Next(modAliases.Length)]);
            parts.Add(keys[rng.Next(keys.Length)]);
            for (int j = parts.Count - 1; j > 0; j--)
            {
                int k = rng.Next(j + 1);
                (parts[j], parts[k]) = (parts[k], parts[j]);
            }
            string s = string.Join("+", parts);

            Assert.True(HotkeyChord.TryParse(s, out var c1));
            Assert.True(HotkeyChord.TryParse(c1.Format(), out var c2));
            Assert.Equal(c1, c2);                       // record-struct value equality
            Assert.Equal(c1.Format(), c2.Format());
        }
    }

    // TryParse must NEVER throw on arbitrary token soup — it returns true/false.
    [Fact]
    public void Fuzz_TryParse_NeverThrows_OnGarbage()
    {
        var rng = new Random(0x4242);
        const string alpha = "+ CtrlShiftAltWinSpaceF0123ABZxyz-escdelpgup";
        for (int i = 0; i < 400; i++)
        {
            int n = rng.Next(0, 20);
            var sb = new System.Text.StringBuilder(n);
            for (int j = 0; j < n; j++) sb.Append(alpha[rng.Next(alpha.Length)]);
            var ex = Record.Exception(() => HotkeyChord.TryParse(sb.ToString(), out _));
            Assert.Null(ex);
        }
    }
}
