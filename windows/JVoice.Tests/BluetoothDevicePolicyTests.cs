using JVoice.Core.Audio;
using Xunit;

namespace JVoice.Tests;

public class BluetoothDevicePolicyTests
{
    private static CaptureEndpointInfo Bt(string id) => new(id, IsBluetooth: true, IsBuiltIn: false);
    private static CaptureEndpointInfo BuiltIn(string id) => new(id, IsBluetooth: false, IsBuiltIn: true);
    private static CaptureEndpointInfo Usb(string id) => new(id, IsBluetooth: false, IsBuiltIn: false);

    [Fact]
    public void DefaultNotBluetooth_ReturnsNull()
    {
        var pick = BluetoothDevicePolicy.PickNonBluetooth(
            defaultIsBluetooth: false,
            new[] { BuiltIn("builtin"), Bt("airpods") });
        Assert.Null(pick);
    }

    [Fact]
    public void DefaultBluetooth_PrefersBuiltIn()
    {
        var pick = BluetoothDevicePolicy.PickNonBluetooth(
            defaultIsBluetooth: true,
            new[] { Bt("airpods"), Usb("usbmic"), BuiltIn("builtin") });
        Assert.Equal("builtin", pick);
    }

    [Fact]
    public void DefaultBluetooth_NoBuiltIn_FallsBackToFirstNonBluetooth()
    {
        var pick = BluetoothDevicePolicy.PickNonBluetooth(
            defaultIsBluetooth: true,
            new[] { Bt("airpods"), Usb("usbmic"), Usb("usbmic2") });
        Assert.Equal("usbmic", pick);
    }

    [Fact]
    public void DefaultBluetooth_NoNonBluetooth_ReturnsNull()
    {
        var pick = BluetoothDevicePolicy.PickNonBluetooth(
            defaultIsBluetooth: true,
            new[] { Bt("airpods"), Bt("buds") });
        Assert.Null(pick);
    }

    [Fact]
    public void EmptyEndpoints_ReturnsNull()
        => Assert.Null(BluetoothDevicePolicy.PickNonBluetooth(true, Array.Empty<CaptureEndpointInfo>()));
}
