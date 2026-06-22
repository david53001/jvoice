namespace JVoice.Core.Audio;

/// A capture endpoint, classified. Id is the platform device id (opaque here).
public readonly record struct CaptureEndpointInfo(string Id, bool IsBluetooth, bool IsBuiltIn);

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

        var nonBluetooth = endpoints.Where(e => !e.IsBluetooth).ToList();
        if (nonBluetooth.Count == 0) return null; // no safe fallback → accept the default

        var builtIn = nonBluetooth.FirstOrDefault(e => e.IsBuiltIn);
        if (builtIn.Id is { Length: > 0 }) return builtIn.Id;
        return nonBluetooth[0].Id;
    }
}
