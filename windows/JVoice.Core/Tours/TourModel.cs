namespace JVoice.Core.Tours;

/// <summary>Every JVoice tour (Mac <c>TourID</c>). The raw values are persisted in <c>tours.json</c> — never rename one.</summary>
public enum TourId { Welcome, RecordingPill, Settings }

/// <summary>A window a tour runs on (Mac <c>TourSurface</c>): the Welcome window, the recording pill, Settings.</summary>
public enum TourSurface { Welcome, RecordingPill, Settings }

/// <summary>Where a step's tag goes; <see cref="Automatic"/> lets the layout decide.</summary>
public enum TagPlacement { Automatic, Left, Right, Above, Below, InsideCorner }

public enum TourEventKind { MenuOpened, ChoiceMade, Action }

/// <summary>Something the user did. Two events are equal only if kind and name match exactly.</summary>
public readonly record struct TourEvent(TourEventKind Kind, string Name = "")
{
    public static TourEvent MenuOpened(string anchor) => new(TourEventKind.MenuOpened, anchor);
    public static TourEvent ChoiceMade(string anchor) => new(TourEventKind.ChoiceMade, anchor);
    public static TourEvent Action(string name) => new(TourEventKind.Action, name);
}

/// <summary>Every <c>Action(…)</c> name the app posts (Mac <c>TourEventName</c>). Surfaces use these, never literals.</summary>
public static class TourEventName
{
    /// <summary>A recording started — posted after the pill is shown AND the mic actually opened.</summary>
    public const string RecordingStarted = "recording.started";
    /// <summary>A recording was stopped by the user (hotkey, tray or the pill's ■) — before the pill leaves Recording.</summary>
    public const string RecordingStopped = "recording.stopped";
    /// <summary>A dictation finished with text (pasted, or put on the clipboard).</summary>
    public const string DictationPasted = "dictation.pasted";
}

/// <summary>An Explain step advances on Next; a Try step advances when <see cref="AdvanceOn"/> is posted (or Skip Step).</summary>
public sealed record TourStep(string Anchor, string Title, string Body, TourEvent? AdvanceOn = null,
    TourEvent? Requires = null, TagPlacement Placement = TagPlacement.Automatic)
{
    public bool IsTry => AdvanceOn is not null;
}

public enum TriggerKind { SurfaceShown, Event, StartedByApp }

public readonly record struct TourTrigger(TriggerKind Kind, TourSurface Surface = default, TourEvent Event = default)
{
    public static TourTrigger Shown(TourSurface s) => new(TriggerKind.SurfaceShown, s);
    public static TourTrigger On(TourEvent e) => new(TriggerKind.Event, Event: e);
    public static TourTrigger ByApp => new(TriggerKind.StartedByApp);
}

/// <summary>A tour: its surface, what starts it by itself, its steps, and its version (bump after a big UI change).</summary>
public sealed record Tour(TourId Id, TourSurface Surface, TourTrigger Trigger, IReadOnlyList<TourStep> Steps,
    TourId? HandsOverTo = null, int Version = 1);

public static class TourIds
{
    /// <summary>The persisted raw value ("welcome", "recordingPill", "settings").</summary>
    public static string Raw(this TourId id) => char.ToLowerInvariant(id.ToString()[0]) + id.ToString()[1..];

    public static TourId? Parse(string? raw)
    {
        foreach (var t in Enum.GetValues<TourId>())
            if (t.Raw() == raw) return t;
        return null;
    }

    /// <summary>The Help &amp; Tours menu item (Mac <c>TourID.menuTitle</c>).</summary>
    public static string MenuTitle(this TourId id) => id switch
    {
        TourId.Welcome => "Welcome Tour",
        TourId.RecordingPill => "Recording Tour",
        _ => "Settings Tour",
    };
}
