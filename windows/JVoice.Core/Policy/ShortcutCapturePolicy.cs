using JVoice.Core.Models;

namespace JVoice.Core;

/// What a key press means while the Settings shortcut recorder is listening, and which
/// well-formed chords JVoice must still refuse — with a reason the recorder row shows.
///
/// Ported from the Mac's `ShortcutCapturePolicy.swift` (parity row 18, docs §6.6) with the
/// Windows equivalents of its refusal sources: the Mac reads the system's symbolic hotkeys and
/// the app's menu key equivalents; Windows has neither API, so <see cref="ReservedBySystem"/>
/// is the documented Windows shell chord list plus "RegisterHotKey failed" (decided by the
/// caller), and <see cref="EditChords"/> is the common app-edit set every app uses. Pure, so
/// the decision table is unit-tested (<c>ShortcutCapturePolicyTests</c>).
public static class ShortcutCapturePolicy
{
    /// The pressed key, classified by the caller.
    public enum CaptureKey
    {
        Escape,
        /// Tab moves focus on, so it cannot be recorded bare.
        Tab,
        /// Delete / Backspace.
        Delete,
        Other,
    }

    public enum Decision
    {
        /// Stop listening, leave the assignment as it was.
        Cancel,
        /// Remove the assigned shortcut (the record shortcut resets to its default instead).
        Clear,
        /// Not a usable global chord — say why and keep listening.
        Reject,
        /// Store the chord (subject to <see cref="Refusal"/>).
        Accept,
    }

    /// Escape/Tab/Delete only mean cancel/clear when pressed bare — with a modifier they are
    /// ordinary shortcut keys (Ctrl+Backspace is a fine chord). Shift alone does not make a
    /// working global chord (Shift+A just types "A"), and every key except F1–F24 needs a real
    /// modifier — bare arrows / navigation / keypad keys were being stored as global hotkeys.
    public static Decision Decide(CaptureKey key, HotkeyModifiers modifiers, int virtualKey)
    {
        if (modifiers == HotkeyModifiers.None)
        {
            switch (key)
            {
                case CaptureKey.Escape:
                case CaptureKey.Tab:
                    return Decision.Cancel;
                case CaptureKey.Delete:
                    return Decision.Clear;
            }
        }
        bool real = (modifiers & ~HotkeyModifiers.Shift) != HotkeyModifiers.None;
        return real || IsFunctionKey(virtualKey) ? Decision.Accept : Decision.Reject;
    }

    /// The reason line for a press <see cref="Decide"/> rejected.
    public static string RejectMessage(HotkeyModifiers modifiers) =>
        modifiers == HotkeyModifiers.Shift
            ? "Shift alone isn't enough — add Ctrl, Alt or Win."
            : "Add Ctrl, Alt or Win — a bare key can't be a global shortcut (F1–F24 can).";

    /// F1–F24 (VK_F1 0x70 … VK_F24 0x87): usable with no modifier at all.
    public static bool IsFunctionKey(int virtualKey) => virtualKey is >= 0x70 and <= 0x87;

    public const int VkTab = 0x09, VkEscape = 0x1B, VkSpace = 0x20, VkSnapshot = 0x2C, VkDelete = 0x2E,
        VkF4 = 0x73;

    /// Why a chord that <see cref="Decide"/> accepted must still be refused.
    public abstract record Refusal
    {
        /// Already assigned to the other JVoice action (its title). Both hooks would fire on one
        /// press, and the second swallow would break the first.
        public sealed record AssignedTo(string Action) : Refusal;
        /// Windows owns it — a shell shortcut, or <c>RegisterHotKey</c> failed (another app holds it).
        public sealed record ReservedBySystem : Refusal;
        /// The standard app-edit command (its title) — registered globally it would stop working in
        /// every app.
        public sealed record UsedByApps(string Title) : Refusal;

        /// One line for the Settings row. <paramref name="chord"/> is the display form ("Ctrl+C").
        public string Message(string chord) => this switch
        {
            AssignedTo a => $"{chord} is already set for {a.Action}. Pick a different shortcut.",
            UsedByApps u => $"{chord} is the standard “{u.Title}” shortcut. Pick a different one.",
            _ => $"{chord} is already used by Windows or another app. Pick a different shortcut.",
        };
    }

    /// The Windows shell chords JVoice must never take (docs §6.6): Win+L/D/E/R/Tab/Space/V,
    /// Win+Shift+S, Alt+Tab, Alt+F4, Ctrl+Alt+Del, Ctrl+Shift+Esc, Ctrl+Esc — and PrintScreen with
    /// any modifiers (screenshot shortcuts).
    private static readonly HashSet<(HotkeyModifiers, int)> Reserved = new()
    {
        (HotkeyModifiers.Win, 'L'), (HotkeyModifiers.Win, 'D'), (HotkeyModifiers.Win, 'E'),
        (HotkeyModifiers.Win, 'R'), (HotkeyModifiers.Win, VkTab), (HotkeyModifiers.Win, VkSpace),
        (HotkeyModifiers.Win, 'V'), (HotkeyModifiers.Win | HotkeyModifiers.Shift, 'S'),
        (HotkeyModifiers.Alt, VkTab), (HotkeyModifiers.Alt, VkF4),
        (HotkeyModifiers.Control | HotkeyModifiers.Alt, VkDelete),
        (HotkeyModifiers.Control | HotkeyModifiers.Shift, VkEscape),
        (HotkeyModifiers.Control, VkEscape),
    };

    /// Ctrl + letter edit commands every Windows app uses.
    public static readonly IReadOnlyDictionary<char, string> EditChords = new Dictionary<char, string>
    {
        ['C'] = "Copy", ['V'] = "Paste", ['X'] = "Cut", ['Z'] = "Undo", ['Y'] = "Redo",
        ['A'] = "Select All", ['S'] = "Save", ['F'] = "Find", ['W'] = "Close", ['Q'] = "Quit",
        ['N'] = "New", ['O'] = "Open", ['P'] = "Print", ['T'] = "New Tab",
    };

    public static bool IsReservedBySystem(HotkeyChord chord) =>
        chord.VirtualKey == VkSnapshot || Reserved.Contains((chord.Modifiers, chord.VirtualKey));

    /// The refusal for a chord <see cref="Decide"/> accepted, or null when it is free.
    /// <paramref name="otherActions"/> are the OTHER JVoice actions' assigned chords (unset ones
    /// omitted) with their titles; <paramref name="registrationFails"/> is the caller's
    /// <c>RegisterHotKey</c> probe (true = Windows or another app already holds the chord).
    public static Refusal? RefusalFor(
        HotkeyChord chord,
        IEnumerable<(string Title, HotkeyChord Chord)> otherActions,
        bool registrationFails = false)
    {
        foreach (var (title, other) in otherActions)
            if (other.Modifiers == chord.Modifiers && other.VirtualKey == chord.VirtualKey)
                return new Refusal.AssignedTo(title);
        if (IsReservedBySystem(chord)) return new Refusal.ReservedBySystem();
        if (chord.Modifiers == HotkeyModifiers.Control && chord.VirtualKey is >= 'A' and <= 'Z'
            && EditChords.TryGetValue((char)chord.VirtualKey, out var title2))
            return new Refusal.UsedByApps(title2);
        if (registrationFails) return new Refusal.ReservedBySystem();
        return null;
    }
}
