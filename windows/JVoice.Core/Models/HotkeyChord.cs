namespace JVoice.Core.Models;

[Flags]
public enum HotkeyModifiers
{
    None = 0,
    Control = 1,
    Alt = 2,
    Shift = 4,
    Win = 8,
}

/// A global-hotkey chord: a set of modifiers plus one main key. Pure value type
/// (parse/format) used by the settings recorder and serialization. Default is
/// Ctrl+Shift+Space (overview §5: Alt+Space is the Windows system menu, so the
/// macOS ⌥Space default can't carry over). VirtualKey holds the Win32 VK code.
public readonly record struct HotkeyChord(HotkeyModifiers Modifiers, int VirtualKey, string KeyName)
{
    public const int VkSpace = 0x20;

    public static HotkeyChord Default =>
        new(HotkeyModifiers.Control | HotkeyModifiers.Shift, VkSpace, "Space");

    public string Format()
    {
        var parts = new List<string>(4);
        if (Modifiers.HasFlag(HotkeyModifiers.Control)) parts.Add("Ctrl");
        if (Modifiers.HasFlag(HotkeyModifiers.Alt)) parts.Add("Alt");
        if (Modifiers.HasFlag(HotkeyModifiers.Shift)) parts.Add("Shift");
        if (Modifiers.HasFlag(HotkeyModifiers.Win)) parts.Add("Win");
        parts.Add(KeyName);
        return string.Join("+", parts);
    }

    public static bool TryParse(string text, out HotkeyChord chord)
    {
        chord = default;
        if (string.IsNullOrWhiteSpace(text)) return false;

        var tokens = text.Split('+', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        if (tokens.Length == 0) return false;

        var mods = HotkeyModifiers.None;
        string? keyToken = null;
        foreach (var raw in tokens)
        {
            switch (raw.ToLowerInvariant())
            {
                case "ctrl":
                case "control": mods |= HotkeyModifiers.Control; break;
                case "alt": mods |= HotkeyModifiers.Alt; break;
                case "shift": mods |= HotkeyModifiers.Shift; break;
                case "win":
                case "windows":
                case "cmd": mods |= HotkeyModifiers.Win; break;
                default:
                    if (keyToken is not null) return false; // two main keys → invalid
                    keyToken = raw;
                    break;
            }
        }
        if (keyToken is null) return false; // modifiers only, no main key

        if (!TryKeyNameToVk(keyToken, out int vk, out string canonicalName)) return false;
        chord = new HotkeyChord(mods, vk, canonicalName);
        return true;
    }

    /// Maps a friendly key name to a Win32 virtual-key code + a canonical display name.
    private static bool TryKeyNameToVk(string name, out int vk, out string canonical)
    {
        vk = 0; canonical = "";
        string n = name.Trim();
        if (n.Length == 0) return false;

        // Single letter A–Z → VK is the uppercase ASCII code.
        if (n.Length == 1 && char.IsLetter(n[0]))
        {
            char up = char.ToUpperInvariant(n[0]);
            vk = up; canonical = up.ToString();
            return true;
        }
        // Single digit 0–9 → VK is the ASCII code of the digit.
        if (n.Length == 1 && char.IsDigit(n[0]))
        {
            vk = n[0]; canonical = n[0].ToString();
            return true;
        }
        // Function keys F1–F24.
        if ((n.Length == 2 || n.Length == 3) && (n[0] is 'F' or 'f') && int.TryParse(n[1..], out int fn) && fn is >= 1 and <= 24)
        {
            vk = 0x70 + (fn - 1); // VK_F1 = 0x70
            canonical = "F" + fn;
            return true;
        }
        // Named keys.
        switch (n.ToLowerInvariant())
        {
            case "space": vk = 0x20; canonical = "Space"; return true;
            case "enter": case "return": vk = 0x0D; canonical = "Enter"; return true;
            case "tab": vk = 0x09; canonical = "Tab"; return true;
            case "esc": case "escape": vk = 0x1B; canonical = "Esc"; return true;
            case "backspace": vk = 0x08; canonical = "Backspace"; return true;
            case "delete": case "del": vk = 0x2E; canonical = "Delete"; return true;
            case "insert": case "ins": vk = 0x2D; canonical = "Insert"; return true;
            case "home": vk = 0x24; canonical = "Home"; return true;
            case "end": vk = 0x23; canonical = "End"; return true;
            case "pageup": case "pgup": vk = 0x21; canonical = "PageUp"; return true;
            case "pagedown": case "pgdn": vk = 0x22; canonical = "PageDown"; return true;
            case "up": vk = 0x26; canonical = "Up"; return true;
            case "down": vk = 0x28; canonical = "Down"; return true;
            case "left": vk = 0x25; canonical = "Left"; return true;
            case "right": vk = 0x27; canonical = "Right"; return true;
            default: return false;
        }
    }
}
