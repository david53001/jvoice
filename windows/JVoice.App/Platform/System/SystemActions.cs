namespace JVoice.App.Platform;

/// Global hook for surfacing transient errors to the user. Phase 4 wires
/// ErrorHandler once (to forward to VoiceCoordinator.ShowError) so services that
/// can't reach the coordinator directly (e.g. SettingsStore) can still report
/// failures. Faithful port of SystemActions.swift. The handler is expected to be
/// invoked from arbitrary threads; the WPF subscriber marshals to the dispatcher.
///
/// Parity row 17 ("settings load warnings reach the user"): SettingsStore reports an unreadable
/// or newer-version settings file from its constructor — before the coordinator's Start() wires
/// the handler — so a message reported with no handler is held and delivered when one is set.
public static class SystemActions
{
    private static readonly object Gate = new();
    private static readonly List<string> Pending = new();
    private static Action<string>? _handler;

    public static Action<string>? ErrorHandler
    {
        get { lock (Gate) return _handler; }
        set
        {
            string[] held;
            lock (Gate)
            {
                _handler = value;
                if (value is null || Pending.Count == 0) return;
                held = Pending.ToArray();
                Pending.Clear();
            }
            foreach (var message in held) value(message);
        }
    }

    public static void ReportError(string message)
    {
        Action<string>? handler;
        lock (Gate)
        {
            handler = _handler;
            if (handler is null)
            {
                if (Pending.Count < 8) Pending.Add(message); // a startup burst, never unbounded
                return;
            }
        }
        handler(message);
    }
}
