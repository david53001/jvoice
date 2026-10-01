using JVoice.Core;
using JVoice.Core.Audio;
using Xunit;

namespace JVoice.Tests;

/// <summary>Parity row 17 (doc §6.5 item 5, Mac 8ea5088): the mic/device fixes that are pure logic.</summary>
public class DeviceFixesTests
{
    // Real endpoints from David's PC (audio-input-probe, 2026-10-02) plus the common virtual devices.
    [Theory]
    [InlineData("ROOT", "Microphone (Voicemod Virtual Audio Device (WDM))", true)]
    [InlineData("TUSBAUDIO_ENUM", "Chat Mix (Elgato Virtual Audio)", true)]
    [InlineData("TUSBAUDIO_ENUM", "Stream Mix (Elgato Virtual Audio)", true)]
    [InlineData("ROOT", "CABLE Output (VB-Audio Virtual Cable)", true)]
    [InlineData("ROOT", "VoiceMeeter Output (VB-Audio VoiceMeeter VAIO)", true)]
    [InlineData("HDAUDIO", "Stereo Mix (Realtek(R) Audio)", true)]
    [InlineData("SWD", "Microphone (NVIDIA Broadcast)", true)]
    [InlineData(null, "OBS Virtual Mic", true)]
    [InlineData("USB", "Microphone (Yeti Classic)", false)]
    [InlineData("USB", "Microphone (Razer Kraken V3)", false)]
    [InlineData("HDAUDIO", "Microphone (Realtek(R) Audio)", false)]
    [InlineData("INTELAUDIO", "Microphone Array (Intel® Smart Sound Technology)", false)]
    [InlineData("BTHENUM", "Headset (AirPods)", false)]
    [InlineData("USB", "Microphone (Jobs Lobster Mic)", false)] // "obs" only as a whole word
    [InlineData(null, null, false)]
    public void VirtualEndpointsAreRecognised(string? enumerator, string? name, bool isVirtual) =>
        Assert.Equal(isVirtual, CaptureEndpointKind.IsVirtual(enumerator, name));

    [Fact]
    public void BluetoothRedirectNeverTargetsAVirtualDevice()
    {
        var voicemod = new CaptureEndpointInfo("voicemod", IsBluetooth: false, IsBuiltIn: false, IsVirtual: true);
        var elgato = new CaptureEndpointInfo("elgato", false, false, true);
        var airpods = new CaptureEndpointInfo("airpods", true, false);
        var yeti = new CaptureEndpointInfo("yeti", false, false);
        // Before: the first non-Bluetooth endpoint — Voicemod, which sends digital silence.
        Assert.Equal("yeti", BluetoothDevicePolicy.PickNonBluetooth(true, new[] { voicemod, elgato, airpods, yeti }));
        // Only virtual devices besides the headset: leave the default alone.
        Assert.Null(BluetoothDevicePolicy.PickNonBluetooth(true, new[] { voicemod, elgato, airpods }));
        // A built-in mic still wins, and a non-Bluetooth default is never redirected.
        var builtIn = new CaptureEndpointInfo("array", false, true);
        Assert.Equal("array", BluetoothDevicePolicy.PickNonBluetooth(true, new[] { yeti, builtIn, airpods }));
        Assert.Null(BluetoothDevicePolicy.PickNonBluetooth(false, new[] { yeti, voicemod }));
        // The user's explicit pick (even a virtual one) still outranks the heuristic.
        Assert.Equal("voicemod", CaptureDeviceSelection.Resolve("voicemod", true, new[] { voicemod, yeti, airpods }));
    }

    [Fact]
    public void AnInterruptedRecordingSaysSoAndNamesTheDevice()
    {
        Assert.Equal("Recording was interrupted — Microphone (Yeti Classic) stopped.",
            CoordinatorDecisions.RecordingInterruptedMessage("Microphone (Yeti Classic)"));
        Assert.Equal("Recording was interrupted — the microphone stopped.", CoordinatorDecisions.RecordingInterruptedMessage(null));
        Assert.Equal("Recording was interrupted — the microphone stopped.", CoordinatorDecisions.RecordingInterruptedMessage("  "));
    }
}
