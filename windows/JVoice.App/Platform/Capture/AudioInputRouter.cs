using JVoice.Core.Audio;
using NAudio.CoreAudioApi;

namespace JVoice.App.Platform;

/// Picks a non-Bluetooth WASAPI capture endpoint to record from when the system
/// default capture endpoint is Bluetooth — so dictating never drags a BT headset
/// out of A2DP into HFP/SCO (which collapses the user's music to mono). Windows
/// analog of AudioInputRouter.swift; unlike macOS we do NOT change the system
/// default device — we just return the device id for NAudioRecorder to open.
/// Any enumeration failure returns null (record from the default, normal path).
public static class AudioInputRouter
{
    // PKEY_Device_EnumeratorName {a45c254e-df1c-4efd-8020-67d146a850e0},24
    private static readonly PropertyKey PkeyEnumeratorName =
        new(new Guid("a45c254e-df1c-4efd-8020-67d146a850e0"), 24);

    // PKEY_AudioEndpoint_FormFactor {1da5d803-d492-4edd-8c23-e0c0ffee7f0e},0
    // NAudio 2.3.0 has no MMDevice.AudioEndpointFormFactor property, so we read the
    // form factor from the property store. Values are the Win32 EndpointFormFactor enum.
    private static readonly PropertyKey PkeyFormFactor =
        new(new Guid("1da5d803-d492-4edd-8c23-e0c0ffee7f0e"), 0);

    // Win32 EndpointFormFactor enum values we care about.
    private const int FormFactorHeadphones = 3;
    private const int FormFactorMicrophone = 4;
    private const int FormFactorHeadset = 5;

    /// The device id to record from, or null = use the system default capture device.
    public static string? PreferredCaptureDeviceId()
    {
        try
        {
            using var enumerator = new MMDeviceEnumerator();

            // The current default capture endpoint (Console role = what apps record from).
            MMDevice? defaultDevice = null;
            if (enumerator.HasDefaultAudioEndpoint(DataFlow.Capture, Role.Console))
                defaultDevice = enumerator.GetDefaultAudioEndpoint(DataFlow.Capture, Role.Console);

            bool defaultIsBluetooth = defaultDevice is not null && IsBluetooth(defaultDevice);

            var endpoints = new List<CaptureEndpointInfo>();
            foreach (var dev in enumerator.EnumerateAudioEndPoints(DataFlow.Capture, DeviceState.Active))
            {
                endpoints.Add(new CaptureEndpointInfo(
                    Id: dev.ID,
                    IsBluetooth: IsBluetooth(dev),
                    IsBuiltIn: IsBuiltIn(dev)));
            }

            string? pick = BluetoothDevicePolicy.PickNonBluetooth(defaultIsBluetooth, endpoints);
            defaultDevice?.Dispose();
            return pick;
        }
        catch
        {
            return null; // any HAL/enumeration error → fall back to system default
        }
    }

    private static bool IsBluetooth(MMDevice device)
    {
        try
        {
            // Most reliable: the enumerator name is "BTHENUM" for classic BT audio,
            // and the BLE enumerator name for Bluetooth LE. Match either.
            if (device.Properties.Contains(PkeyEnumeratorName))
            {
                object value = device.Properties[PkeyEnumeratorName].Value;
                string enumName = value?.ToString() ?? string.Empty;
                if (enumName.Contains("BTHENUM", StringComparison.OrdinalIgnoreCase) ||
                    enumName.Contains("BTHLE", StringComparison.OrdinalIgnoreCase) ||
                    enumName.Contains("Bluetooth", StringComparison.OrdinalIgnoreCase))
                    return true;
            }
        }
        catch { /* property read can throw on odd drivers — fall through */ }

        // Secondary signal: a Headset/Headphones form factor is overwhelmingly BT here.
        try
        {
            int? ff = FormFactor(device);
            if (ff == FormFactorHeadset || ff == FormFactorHeadphones)
                return true;
        }
        catch { /* ignore */ }

        // Last resort: a friendly name mentioning Bluetooth/AirPods/Hands-Free.
        try
        {
            string name = device.FriendlyName;
            if (name.Contains("Bluetooth", StringComparison.OrdinalIgnoreCase) ||
                name.Contains("Hands-Free", StringComparison.OrdinalIgnoreCase) ||
                name.Contains("AirPods", StringComparison.OrdinalIgnoreCase))
                return true;
        }
        catch { /* ignore */ }

        return false;
    }

    private static bool IsBuiltIn(MMDevice device)
    {
        try
        {
            // Microphone form factor + not Bluetooth is the integrated/array mic.
            if (FormFactor(device) == FormFactorMicrophone)
                return true;
        }
        catch { /* ignore */ }
        return false;
    }

    /// Reads PKEY_AudioEndpoint_FormFactor from the device property store, or null
    /// if absent/unreadable. NAudio exposes no typed property in 2.3.0.
    private static int? FormFactor(MMDevice device)
    {
        try
        {
            if (!device.Properties.Contains(PkeyFormFactor)) return null;
            object value = device.Properties[PkeyFormFactor].Value;
            return value is null ? null : Convert.ToInt32(value);
        }
        catch { return null; }
    }
}
