namespace JVoice.App.Platform;

/// Global hook for surfacing transient errors to the user. Phase 4 wires
/// ErrorHandler once (to forward to VoiceCoordinator.ShowError) so services that
/// can't reach the coordinator directly (e.g. SettingsStore) can still report
/// failures. Faithful port of SystemActions.swift. The handler is expected to be
/// invoked from arbitrary threads; the WPF subscriber marshals to the dispatcher.
public static class SystemActions
{
    public static Action<string>? ErrorHandler { get; set; }

    public static void ReportError(string message) => ErrorHandler?.Invoke(message);
}
