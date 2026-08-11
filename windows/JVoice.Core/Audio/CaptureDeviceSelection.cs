namespace JVoice.Core.Audio;

/// Pure policy for deciding WHICH capture endpoint to record from, layering the user's
/// explicit choice on top of the existing Bluetooth-avoidance policy.
///
/// Windows-only (macOS has no in-app input picker). Added 2026-08-11 after the system default
/// capture endpoint turned out to be a virtual mic (Voicemod) that emits digital silence when
/// its app isn't running: JVoice always recorded from the system default and gave the user no
/// way to point it at their real microphone without changing the OS-wide default — which would
/// have broken the other apps deliberately using that virtual device (§7 #46).
///
/// Priority:
///   1. the user's explicitly chosen device, **if it is still present and active**
///   2. otherwise the Bluetooth-avoidance pick (keep BT headsets in A2DP)
///   3. otherwise null = record from the system default endpoint
public static class CaptureDeviceSelection
{
    public static string? Resolve(
        string? userChoiceId,
        bool defaultIsBluetooth,
        IReadOnlyList<CaptureEndpointInfo> endpoints)
    {
        // An explicit choice outranks the Bluetooth heuristic: if the user deliberately selected
        // their Bluetooth headset mic, honor it rather than silently recording somewhere else.
        if (!string.IsNullOrWhiteSpace(userChoiceId))
        {
            foreach (var e in endpoints)
                if (string.Equals(e.Id, userChoiceId, StringComparison.Ordinal))
                    return userChoiceId;
            // Chosen device is gone (unplugged/disabled) — fall through to the automatic policy
            // rather than failing to record. The stored id is kept so it re-binds when it returns.
        }

        return BluetoothDevicePolicy.PickNonBluetooth(defaultIsBluetooth, endpoints);
    }
}
