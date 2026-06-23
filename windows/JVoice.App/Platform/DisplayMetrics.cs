using System.Runtime.InteropServices;

namespace JVoice.App.Platform;

/// How much to enlarge the HUD pill so it stays crisp/legible on THIS display.
///
/// Two softness sources stack on the pill, and rendering it larger is the practical
/// mitigation for BOTH:
///   1. WPF disables ClearType inside the HUD's layered (AllowsTransparency) window and
///      falls back to grayscale antialiasing — small text/glyphs read as soft even at
///      native resolution. This is the historical, machine-independent reason the pill
///      was scaled to <see cref="HudBaseScale"/>.
///   2. Running the desktop BELOW the panel's native resolution (e.g. 1600×1080 on a
///      1920×1080 monitor — common for competitive gaming) makes the monitor's hardware
///      scaler interpolate the whole framebuffer. No app can exempt its own window from
///      that stretch, but rendering the pill bigger gives each glyph proportionally more
///      real device pixels, so it survives the interpolation far more legibly.
///
/// So the scale = <see cref="HudBaseScale"/> × the horizontal stretch ratio
/// (nativeWidth / currentWidth), clamped to <see cref="MaxHudScale"/>. At native
/// resolution the ratio is 1.0, so the value is exactly the old 1.1 — no regression for
/// anyone running native. The native size comes from the DisplayConfig "preferred mode"
/// API (EDID-derived), which is immune to NVIDIA DSR/DLDSR "virtual" resolutions that
/// would fool a naive max-enumerated-mode probe into over-scaling.
public static class DisplayMetrics
{
    /// Baseline enlargement for the layered-window grayscale-AA softness — applies at
    /// every resolution. Was the hard-coded ScaleTransform value in HudView.xaml.
    public const double HudBaseScale = 1.1;

    /// Upper bound so an extreme downscale (e.g. 1024×768 on a 4K panel) can't inflate
    /// the pill to an absurd size.
    private const double MaxHudScale = 1.8;

    // Display metrics are effectively constant for a tray app's session, and the pill is
    // shown on the hot path (the instant the hotkey fires), so compute once and cache —
    // a mid-session resolution change won't re-scale the pill until the next launch.
    private static readonly Lazy<double> _hudScale = new(Compute);

    /// Uniform LayoutTransform scale for the HUD pill on the primary display.
    public static double HudScale => _hudScale.Value;

    private static double Compute()
    {
        try
        {
            int current = CurrentPrimaryHorizontalPixels();
            int native = PrimaryNativeHorizontalPixels();
            if (current <= 0 || native <= current) return HudBaseScale; // native res / DSR → no stretch
            double scale = HudBaseScale * ((double)native / current);
            return Math.Min(MaxHudScale, scale);
        }
        catch
        {
            // Any interop hiccup → fall back to the always-safe baseline.
            return HudBaseScale;
        }
    }

    /// True current horizontal pixel count of the primary display (DESKTOPHORZRES is the
    /// physical resolution, unaffected by DPI scaling — unlike HORZRES).
    private static int CurrentPrimaryHorizontalPixels()
    {
        IntPtr hdc = GetDC(IntPtr.Zero);
        if (hdc == IntPtr.Zero) return 0;
        try { return GetDeviceCaps(hdc, DESKTOPHORZRES); }
        finally { ReleaseDC(IntPtr.Zero, hdc); }
    }

    /// The primary monitor's native (EDID preferred) horizontal pixel count, via
    /// DisplayConfig. Correlated to the primary by matching the source's GDI device name
    /// so a larger secondary monitor can't skew the ratio. 0 if it can't be determined.
    private static int PrimaryNativeHorizontalPixels()
    {
        string? primary = PrimaryDeviceName();
        if (primary is null) return 0;

        if (GetDisplayConfigBufferSizes(QDC_ONLY_ACTIVE_PATHS, out uint nPaths, out uint nModes) != 0)
            return 0;

        var paths = new DISPLAYCONFIG_PATH_INFO[nPaths];
        var modes = new DISPLAYCONFIG_MODE_INFO[nModes];
        if (QueryDisplayConfig(QDC_ONLY_ACTIVE_PATHS, ref nPaths, paths, ref nModes, modes, IntPtr.Zero) != 0)
            return 0;

        for (int i = 0; i < nPaths; i++)
        {
            var name = new DISPLAYCONFIG_SOURCE_DEVICE_NAME();
            name.header.type = DISPLAYCONFIG_DEVICE_INFO_GET_SOURCE_NAME;
            name.header.size = (uint)Marshal.SizeOf<DISPLAYCONFIG_SOURCE_DEVICE_NAME>();
            name.header.adapterId = paths[i].sourceInfo.adapterId;
            name.header.id = paths[i].sourceInfo.id;
            if (DisplayConfigGetDeviceInfo(ref name) != 0) continue;
            if (name.viewGdiDeviceName != primary) continue;

            var mode = new DISPLAYCONFIG_TARGET_PREFERRED_MODE();
            mode.header.type = DISPLAYCONFIG_DEVICE_INFO_GET_TARGET_PREFERRED_MODE;
            mode.header.size = (uint)Marshal.SizeOf<DISPLAYCONFIG_TARGET_PREFERRED_MODE>();
            mode.header.adapterId = paths[i].targetInfo.adapterId;
            mode.header.id = paths[i].targetInfo.id;
            if (DisplayConfigGetDeviceInfo(ref mode) != 0) return 0;
            return (int)mode.width;
        }
        return 0;
    }

    private static string? PrimaryDeviceName()
    {
        var dd = new DISPLAY_DEVICE();
        dd.cb = (uint)Marshal.SizeOf<DISPLAY_DEVICE>();
        for (uint i = 0; EnumDisplayDevices(null, i, ref dd, 0); i++)
        {
            if ((dd.StateFlags & DISPLAY_DEVICE_PRIMARY_DEVICE) != 0) return dd.DeviceName;
            dd.cb = (uint)Marshal.SizeOf<DISPLAY_DEVICE>();
        }
        return null;
    }

    // ---- Win32 / GDI ----
    private const int DESKTOPHORZRES = 118;
    private const uint QDC_ONLY_ACTIVE_PATHS = 0x00000002;
    private const uint DISPLAYCONFIG_DEVICE_INFO_GET_SOURCE_NAME = 1;
    private const uint DISPLAYCONFIG_DEVICE_INFO_GET_TARGET_PREFERRED_MODE = 3;
    private const uint DISPLAY_DEVICE_PRIMARY_DEVICE = 0x00000004;

    [StructLayout(LayoutKind.Sequential)]
    private struct LUID { public uint LowPart; public int HighPart; }

    [StructLayout(LayoutKind.Sequential)]
    private struct DISPLAYCONFIG_RATIONAL { public uint Numerator; public uint Denominator; }

    [StructLayout(LayoutKind.Sequential)]
    private struct DISPLAYCONFIG_2DREGION { public uint cx; public uint cy; }

    [StructLayout(LayoutKind.Sequential)]
    private struct DISPLAYCONFIG_PATH_SOURCE_INFO
    {
        public LUID adapterId; public uint id; public uint modeInfoIdx; public uint statusFlags;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct DISPLAYCONFIG_PATH_TARGET_INFO
    {
        public LUID adapterId; public uint id; public uint modeInfoIdx; public uint outputTechnology;
        public uint rotation; public uint scaling; public DISPLAYCONFIG_RATIONAL refreshRate;
        public uint scanLineOrdering; public int targetAvailable; public uint statusFlags;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct DISPLAYCONFIG_PATH_INFO
    {
        public DISPLAYCONFIG_PATH_SOURCE_INFO sourceInfo;
        public DISPLAYCONFIG_PATH_TARGET_INFO targetInfo;
        public uint flags;
    }

    // We never read the mode array's contents — only pass a correctly-sized buffer to
    // QueryDisplayConfig. DISPLAYCONFIG_MODE_INFO is a 64-byte tagged union; model it as
    // an opaque blob of that size so we don't have to define the whole union.
    [StructLayout(LayoutKind.Sequential, Size = 64)]
    private struct DISPLAYCONFIG_MODE_INFO { }

    [StructLayout(LayoutKind.Sequential)]
    private struct DISPLAYCONFIG_DEVICE_INFO_HEADER
    {
        public uint type; public uint size; public LUID adapterId; public uint id;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct DISPLAYCONFIG_VIDEO_SIGNAL_INFO
    {
        public ulong pixelRate; public DISPLAYCONFIG_RATIONAL hSyncFreq; public DISPLAYCONFIG_RATIONAL vSyncFreq;
        public DISPLAYCONFIG_2DREGION activeSize; public DISPLAYCONFIG_2DREGION totalSize;
        public uint videoStandard; public uint scanLineOrdering;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct DISPLAYCONFIG_TARGET_PREFERRED_MODE
    {
        public DISPLAYCONFIG_DEVICE_INFO_HEADER header;
        public uint width; public uint height;
        public DISPLAYCONFIG_VIDEO_SIGNAL_INFO targetMode;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct DISPLAYCONFIG_SOURCE_DEVICE_NAME
    {
        public DISPLAYCONFIG_DEVICE_INFO_HEADER header;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string viewGdiDeviceName;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct DISPLAY_DEVICE
    {
        public uint cb;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string DeviceName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceString;
        public uint StateFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceID;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceKey;
    }

    [DllImport("user32.dll")]
    private static extern int GetDisplayConfigBufferSizes(uint flags, out uint numPathArrayElements, out uint numModeInfoArrayElements);

    [DllImport("user32.dll")]
    private static extern int QueryDisplayConfig(uint flags, ref uint numPathArrayElements,
        [Out] DISPLAYCONFIG_PATH_INFO[] pathArray, ref uint numModeInfoArrayElements,
        [Out] DISPLAYCONFIG_MODE_INFO[] modeInfoArray, IntPtr currentTopologyId);

    [DllImport("user32.dll")]
    private static extern int DisplayConfigGetDeviceInfo(ref DISPLAYCONFIG_TARGET_PREFERRED_MODE requestPacket);

    [DllImport("user32.dll")]
    private static extern int DisplayConfigGetDeviceInfo(ref DISPLAYCONFIG_SOURCE_DEVICE_NAME requestPacket);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern bool EnumDisplayDevices(string? lpDevice, uint iDevNum, ref DISPLAY_DEVICE lpDisplayDevice, uint dwFlags);

    [DllImport("user32.dll")] private static extern IntPtr GetDC(IntPtr hWnd);
    [DllImport("gdi32.dll")] private static extern int GetDeviceCaps(IntPtr hdc, int nIndex);
    [DllImport("user32.dll")] private static extern int ReleaseDC(IntPtr hWnd, IntPtr hdc);
}
