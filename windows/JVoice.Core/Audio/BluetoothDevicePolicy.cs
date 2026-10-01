namespace JVoice.Core.Audio;

/// A capture endpoint, classified. Id is the platform device id (opaque here).
/// IsVirtual: a virtual cable / voice changer / loopback input (CaptureEndpointKind) — never a redirect target.
public readonly record struct CaptureEndpointInfo(string Id, bool IsBluetooth, bool IsBuiltIn, bool IsVirtual = false);

/// Pure policy for choosing a non-Bluetooth capture endpoint to record from when
/// the system default is a Bluetooth device. Faithful port of
/// AudioInputRouter.redirectTarget: prefer a built-in mic, else the first
/// non-Bluetooth endpoint; null means "leave the default alone / nothing to do".
/// Unlike macOS we DON'T change the system default — the caller just opens the
/// returned device id (overview §6.4).
public static class BluetoothDevicePolicy
{
    public static string? PickNonBluetooth(bool defaultIsBluetooth, IReadOnlyList<CaptureEndpointInfo> endpoints)
    {
        if (!defaultIsBluetooth) return null; // default isn't BT → record from default

        // Physical inputs only (parity row 17, Mac 8ea5088): a virtual device (Voicemod, VB-Cable, Elgato's
        // mixes) is "not Bluetooth" too, but redirecting to it records silence or someone else's mix.
        var nonBluetooth = endpoints.Where(e => !e.IsBluetooth && !e.IsVirtual).ToList();
        if (nonBluetooth.Count == 0) return null; // no safe fallback → accept the default

        var builtIn = nonBluetooth.FirstOrDefault(e => e.IsBuiltIn);
        if (builtIn.Id is { Length: > 0 }) return builtIn.Id;
        return nonBluetooth[0].Id;
    }
}
