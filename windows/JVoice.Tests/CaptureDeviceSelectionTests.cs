using JVoice.Core.Audio;
using Xunit;

namespace JVoice.Tests;

/// Locks the v5 microphone-selection policy (§7 #46): an explicit user pick outranks the
/// Bluetooth-avoidance heuristic, but a pick that has vanished degrades to the automatic
/// policy instead of failing to record.
public class CaptureDeviceSelectionTests
{
    private static CaptureEndpointInfo Bt(string id) => new(id, IsBluetooth: true, IsBuiltIn: false);
    private static CaptureEndpointInfo BuiltIn(string id) => new(id, IsBluetooth: false, IsBuiltIn: true);
    private static CaptureEndpointInfo Usb(string id) => new(id, IsBluetooth: false, IsBuiltIn: false);

    [Fact]
    public void NoUserChoice_FallsBackToBluetoothPolicy_Null()
    {
        var pick = CaptureDeviceSelection.Resolve(
            userChoiceId: null,
            defaultIsBluetooth: false,
            new[] { BuiltIn("builtin"), Usb("yeti") });
        Assert.Null(pick); // = record from the system default
    }

    [Fact]
    public void NoUserChoice_StillAvoidsBluetoothDefault()
    {
        var pick = CaptureDeviceSelection.Resolve(
            userChoiceId: null,
            defaultIsBluetooth: true,
            new[] { Bt("airpods"), BuiltIn("builtin") });
        Assert.Equal("builtin", pick);
    }

    [Fact]
    public void UserChoice_IsHonoredWhenActive()
    {
        var pick = CaptureDeviceSelection.Resolve(
            userChoiceId: "yeti",
            defaultIsBluetooth: false,
            new[] { Usb("voicemod-virtual"), Usb("yeti") });
        Assert.Equal("yeti", pick);
    }

    /// The whole point of the feature: the system default is a silent virtual mic, and the user
    /// pointed JVoice at their real microphone instead — without changing the OS-wide default.
    [Fact]
    public void UserChoice_OverridesASilentVirtualSystemDefault()
    {
        var pick = CaptureDeviceSelection.Resolve(
            userChoiceId: "yeti",
            defaultIsBluetooth: false,
            new[] { Usb("voicemod-virtual"), Usb("yeti"), Usb("elgato-chat") });
        Assert.Equal("yeti", pick);
    }

    /// An explicit pick beats the Bluetooth heuristic: if the user deliberately selected their
    /// BT headset mic, honor it rather than silently recording from somewhere else.
    [Fact]
    public void UserChoice_BeatsBluetoothAvoidance()
    {
        var pick = CaptureDeviceSelection.Resolve(
            userChoiceId: "airpods",
            defaultIsBluetooth: true,
            new[] { Bt("airpods"), BuiltIn("builtin") });
        Assert.Equal("airpods", pick);
    }

    [Fact]
    public void UnpluggedUserChoice_FallsBackToAutomaticPolicy()
    {
        var pick = CaptureDeviceSelection.Resolve(
            userChoiceId: "yeti-not-plugged-in",
            defaultIsBluetooth: true,
            new[] { Bt("airpods"), BuiltIn("builtin") });
        Assert.Equal("builtin", pick); // BT policy, not the missing device
    }

    [Fact]
    public void UnpluggedUserChoice_WithNonBluetoothDefault_UsesSystemDefault()
    {
        var pick = CaptureDeviceSelection.Resolve(
            userChoiceId: "gone",
            defaultIsBluetooth: false,
            new[] { Usb("yeti") });
        Assert.Null(pick);
    }

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    public void BlankUserChoice_IsTreatedAsNoChoice(string blank)
    {
        var pick = CaptureDeviceSelection.Resolve(
            userChoiceId: blank,
            defaultIsBluetooth: true,
            new[] { Bt("airpods"), BuiltIn("builtin") });
        Assert.Equal("builtin", pick);
    }

    [Fact]
    public void EmptyEndpointList_NeverThrows()
    {
        Assert.Null(CaptureDeviceSelection.Resolve("yeti", false, Array.Empty<CaptureEndpointInfo>()));
        Assert.Null(CaptureDeviceSelection.Resolve(null, true, Array.Empty<CaptureEndpointInfo>()));
    }

    /// Ids are matched exactly — endpoint ids are opaque OS strings, never case-folded.
    [Fact]
    public void IdMatching_IsOrdinal()
    {
        var pick = CaptureDeviceSelection.Resolve(
            userChoiceId: "YETI",
            defaultIsBluetooth: false,
            new[] { Usb("yeti") });
        Assert.Null(pick); // no exact match => automatic policy
    }
}
