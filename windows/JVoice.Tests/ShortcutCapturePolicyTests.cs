using JVoice.Core;
using JVoice.Core.Models;
using Xunit;
using static JVoice.Core.ShortcutCapturePolicy;

namespace JVoice.Tests;

/// The recorder's decision table (parity row 18) — the Windows twin of the Mac's
/// ShortcutCapturePolicy tests.
public class ShortcutCapturePolicyTests
{
    private const HotkeyModifiers None = HotkeyModifiers.None, Ctrl = HotkeyModifiers.Control,
        Alt = HotkeyModifiers.Alt, Shift = HotkeyModifiers.Shift, Win = HotkeyModifiers.Win;

    [Theory]
    [InlineData(CaptureKey.Escape, None, 0x1B, Decision.Cancel)]
    [InlineData(CaptureKey.Tab, None, 0x09, Decision.Cancel)]
    [InlineData(CaptureKey.Delete, None, 0x08, Decision.Clear)]
    [InlineData(CaptureKey.Delete, None, 0x2E, Decision.Clear)]
    [InlineData(CaptureKey.Delete, Ctrl, 0x08, Decision.Accept)]      // Ctrl+Backspace is a chord
    [InlineData(CaptureKey.Escape, Ctrl | Shift, 0x1B, Decision.Accept)] // decided; refused later
    [InlineData(CaptureKey.Other, None, 'A', Decision.Reject)]        // bare letter
    [InlineData(CaptureKey.Other, None, 0x25, Decision.Reject)]       // bare Left arrow
    [InlineData(CaptureKey.Other, None, 0x24, Decision.Reject)]       // bare Home
    [InlineData(CaptureKey.Other, None, 0x60, Decision.Reject)]       // bare Numpad0
    [InlineData(CaptureKey.Other, Shift, 'A', Decision.Reject)]       // Shift alone
    [InlineData(CaptureKey.Other, Shift, 0x20, Decision.Reject)]
    [InlineData(CaptureKey.Other, None, 0x70, Decision.Accept)]       // bare F1
    [InlineData(CaptureKey.Other, None, 0x87, Decision.Accept)]       // bare F24
    [InlineData(CaptureKey.Other, Shift, 0x7B, Decision.Accept)]      // Shift+F12
    [InlineData(CaptureKey.Other, Ctrl | Shift, 0x20, Decision.Accept)] // the default
    [InlineData(CaptureKey.Other, Alt, 'J', Decision.Accept)]
    [InlineData(CaptureKey.Other, Win | Shift, 'J', Decision.Accept)]
    public void Decide_FollowsTheTable(CaptureKey key, HotkeyModifiers mods, int vk, Decision expected)
        => Assert.Equal(expected, Decide(key, mods, vk));

    [Fact]
    public void RejectMessage_NamesTheMissingModifier()
    {
        Assert.Contains("Shift alone", RejectMessage(Shift));
        Assert.Contains("bare key", RejectMessage(None));
    }

    public static TheoryData<HotkeyModifiers, int> SystemChords() => new()
    {
        { Win, 'L' }, { Win, 'D' }, { Win, 'E' }, { Win, 'R' }, { Win, 0x09 }, { Win, 0x20 }, { Win, 'V' },
        { Win | Shift, 'S' }, { Alt, 0x09 }, { Alt, 0x73 }, { Ctrl | Alt, 0x2E }, { Ctrl | Shift, 0x1B },
        { Ctrl, 0x1B }, { None, 0x2C }, { Alt, 0x2C }, { Win, 0x2C },
    };

    [Theory]
    [MemberData(nameof(SystemChords))]
    public void RefusalFor_RefusesWindowsShellChords(HotkeyModifiers mods, int vk)
    {
        var r = RefusalFor(new HotkeyChord(mods, vk, "K"), []);
        Assert.IsType<Refusal.ReservedBySystem>(r);
        Assert.Contains("already used by Windows", r!.Message("Win+L"));
    }

    [Theory]
    [InlineData('C', "Copy")]
    [InlineData('V', "Paste")]
    [InlineData('X', "Cut")]
    [InlineData('Z', "Undo")]
    [InlineData('Y', "Redo")]
    [InlineData('A', "Select All")]
    [InlineData('S', "Save")]
    [InlineData('F', "Find")]
    [InlineData('W', "Close")]
    [InlineData('Q', "Quit")]
    [InlineData('N', "New")]
    [InlineData('O', "Open")]
    [InlineData('P', "Print")]
    [InlineData('T', "New Tab")]
    public void RefusalFor_RefusesCommonEditChords(char letter, string title)
    {
        var r = RefusalFor(new HotkeyChord(Ctrl, letter, letter.ToString()), []);
        var used = Assert.IsType<Refusal.UsedByApps>(r);
        Assert.Equal(title, used.Title);
        Assert.Equal($"Ctrl+{letter} is the standard “{title}” shortcut. Pick a different one.", r.Message($"Ctrl+{letter}"));
    }

    [Fact]
    public void RefusalFor_EditLettersWithMoreModifiersAreFree()
    {
        Assert.Null(RefusalFor(new HotkeyChord(Ctrl | Shift, 'C', "C"), []));
        Assert.Null(RefusalFor(new HotkeyChord(Ctrl | Alt, 'Z', "Z"), []));
        Assert.Null(RefusalFor(new HotkeyChord(Ctrl, 'J', "J"), []));
    }

    [Fact]
    public void RefusalFor_RefusesTheOtherActionsChord()
    {
        var other = new[] { ("Toggle Recording", HotkeyChord.Default) };
        var r = RefusalFor(new HotkeyChord(Ctrl | Shift, 0x20, "Space"), other);
        Assert.Equal(new Refusal.AssignedTo("Toggle Recording"), r);
        Assert.Equal("Ctrl+Shift+Space is already set for Toggle Recording. Pick a different shortcut.",
            r!.Message("Ctrl+Shift+Space"));
    }

    [Fact]
    public void RefusalFor_DuplicateBeatsEveryOtherReason()
    {
        var other = new[] { ("Undo Last Paste", new HotkeyChord(Ctrl, 'C', "C")) };
        Assert.IsType<Refusal.AssignedTo>(RefusalFor(new HotkeyChord(Ctrl, 'C', "C"), other));
    }

    [Fact]
    public void RefusalFor_AFailedRegistrationIsReservedBySystem()
    {
        var chord = new HotkeyChord(Ctrl | Alt, 'K', "K");
        Assert.Null(RefusalFor(chord, []));
        Assert.IsType<Refusal.ReservedBySystem>(RefusalFor(chord, [], registrationFails: true));
    }

    [Fact]
    public void RefusalFor_TheDefaultChordIsFree()
        => Assert.Null(RefusalFor(HotkeyChord.Default, []));
}
