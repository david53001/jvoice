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

    // ===== Additional edges =====

    // The default-not-Bluetooth short-circuit fires before the endpoint list is even examined.
    [Fact]
    public void DefaultNotBluetooth_EmptyEndpoints_ReturnsNull()
        => Assert.Null(BluetoothDevicePolicy.PickNonBluetooth(false, Array.Empty<CaptureEndpointInfo>()));

    [Fact]
    public void DefaultNotBluetooth_BluetoothOnlyEndpoints_ReturnsNull()
        => Assert.Null(BluetoothDevicePolicy.PickNonBluetooth(false, new[] { Bt("a"), Bt("b") }));

    [Fact]
    public void MultipleBuiltIns_PicksFirst()
    {
        var pick = BluetoothDevicePolicy.PickNonBluetooth(
            defaultIsBluetooth: true,
            new[] { Bt("airpods"), BuiltIn("b1"), BuiltIn("b2") });
        Assert.Equal("b1", pick);
    }

    [Fact]
    public void SingleBuiltIn_DefaultBluetooth_PicksIt()
        => Assert.Equal("b", BluetoothDevicePolicy.PickNonBluetooth(true, new[] { BuiltIn("b") }));

    // Invariant: a non-null pick is always a non-Bluetooth endpoint present in the list, only ever
    // when the default IS Bluetooth, and a built-in is preferred whenever one exists.
    [Fact]
    public void Fuzz_NeverPicksBluetooth_PrefersBuiltIn()
    {
        var rng = new Random(20260623);
        for (int i = 0; i < 400; i++)
        {
            int n = rng.Next(0, 8);
            var eps = new List<CaptureEndpointInfo>();
            for (int j = 0; j < n; j++)
            {
                bool bt = rng.Next(2) == 0;
                bool builtin = !bt && rng.Next(2) == 0;
                eps.Add(new CaptureEndpointInfo($"dev{i}_{j}", bt, builtin));
            }
            bool defaultBt = rng.Next(2) == 0;

            var pick = BluetoothDevicePolicy.PickNonBluetooth(defaultBt, eps);
            if (pick is null) continue;

            Assert.True(defaultBt);                                   // only redirects off a BT default
            var chosen = eps.Single(e => e.Id == pick);
            Assert.False(chosen.IsBluetooth);                         // never a Bluetooth device
            if (eps.Any(e => !e.IsBluetooth && e.IsBuiltIn))
                Assert.True(chosen.IsBuiltIn);                        // built-in preferred when present
        }
    }
}
